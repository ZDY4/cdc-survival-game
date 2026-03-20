extends Node

const InputActions = preload("res://core/input_actions.gd")
const ValueUtils = preload("res://core/value_utils.gd")

const SETTINGS_DIR: String = "user://settings"
const SETTINGS_PATH: String = "user://settings/controls.json"

signal bindings_changed()
signal binding_changed(action_name: StringName, binding: Dictionary)
signal settings_loaded()

var _controls: Dictionary = {}
var _audio: Dictionary = {
	"master": 1.0,
	"music": 1.0,
	"sfx": 1.0
}
var _display: Dictionary = {
	"window_mode": "windowed",
	"vsync": true,
	"ui_scale": 1.0
}

func _ready() -> void:
	InputActions.ensure_actions_registered()
	_load_or_initialize()
	_apply_controls()
	_apply_audio()
	_apply_display()
	settings_loaded.emit()

func get_binding(action_name: StringName) -> Dictionary:
	if not _controls.has(action_name):
		return InputActions.get_current_binding(action_name)
	return (_controls.get(action_name, {}) as Dictionary).duplicate(true)

func get_bindings() -> Dictionary:
	return _controls.duplicate(true)

func set_binding(action_name: StringName, keycode: int, physical_keycode: int = -1) -> Dictionary:
	if action_name == InputActions.ACTION_MENU_SETTINGS:
		return {"success": false, "reason": "设置面板按键不可修改"}
	if not InputActions.REBINDABLE_ACTIONS.has(action_name):
		return {"success": false, "reason": "动作不支持重绑定"}

	var conflict: StringName = _find_conflict_action(action_name, keycode)
	if conflict != StringName():
		return {
			"success": false,
			"reason": "按键冲突: %s" % InputActions.get_action_label(conflict)
		}

	_controls[action_name] = {
		"keycode": keycode,
		"physical_keycode": physical_keycode if physical_keycode >= 0 else keycode
	}
	InputActions.apply_binding(
		action_name,
		ValueUtils.to_int(_controls[action_name].keycode, KEY_NONE),
		ValueUtils.to_int(_controls[action_name].physical_keycode, KEY_NONE)
	)
	_save_settings()
	binding_changed.emit(action_name, get_binding(action_name))
	bindings_changed.emit()
	return {"success": true, "reason": ""}

func reset_defaults() -> void:
	_controls.clear()
	for action_variant in InputActions.DEFAULT_BINDINGS.keys():
		var action_name: StringName = action_variant
		var keycode: int = ValueUtils.to_int(InputActions.DEFAULT_BINDINGS[action_name], KEY_NONE)
		_controls[action_name] = {
			"keycode": keycode,
			"physical_keycode": keycode
		}
	_apply_controls()
	_save_settings()
	bindings_changed.emit()

func get_audio_settings() -> Dictionary:
	return _audio.duplicate(true)

func get_display_settings() -> Dictionary:
	return _display.duplicate(true)

func set_audio_setting(setting_name: String, value: float) -> void:
	if not _audio.has(setting_name):
		return
	_audio[setting_name] = clampf(value, 0.0, 1.0)
	_apply_audio()
	_save_settings()

func set_display_setting(setting_name: String, value: Variant) -> void:
	if not _display.has(setting_name):
		return
	if setting_name == "ui_scale":
		_display[setting_name] = clampf(float(value), 0.75, 1.5)
	else:
		_display[setting_name] = value
	_apply_display()
	_save_settings()

func _load_or_initialize() -> void:
	reset_defaults()
	if not FileAccess.file_exists(SETTINGS_PATH):
		_save_settings()
		return

	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return

	var data: Dictionary = parsed
	var controls: Dictionary = data.get("controls", {})
	for action_variant in controls.keys():
		var action_name: StringName = StringName(str(action_variant))
		if not InputActions.MENU_ACTIONS.has(action_name):
			continue
		var binding_variant: Variant = controls[action_variant]
		if binding_variant is Dictionary:
			var binding: Dictionary = binding_variant
			_controls[action_name] = {
				"keycode": ValueUtils.to_int(binding.get("keycode", InputActions.DEFAULT_BINDINGS.get(action_name, KEY_NONE)), KEY_NONE),
				"physical_keycode": ValueUtils.to_int(binding.get("physical_keycode", binding.get("keycode", KEY_NONE)), KEY_NONE)
			}

	var audio: Dictionary = data.get("audio", {})
	for key in _audio.keys():
		if audio.has(key):
			_audio[key] = clampf(float(audio[key]), 0.0, 1.0)

	var display: Dictionary = data.get("display", {})
	if display.has("window_mode"):
		_display["window_mode"] = str(display["window_mode"])
	if display.has("vsync"):
		_display["vsync"] = bool(display["vsync"])
	if display.has("ui_scale"):
		_display["ui_scale"] = clampf(float(display["ui_scale"]), 0.75, 1.5)

func _save_settings() -> void:
	DirAccess.make_dir_recursive_absolute(SETTINGS_DIR)
	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if not file:
		push_warning("[ControlSettingsService] 无法写入设置文件")
		return
	var data := {
		"controls": _controls,
		"audio": _audio,
		"display": _display
	}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _apply_controls() -> void:
	for action_variant in InputActions.MENU_ACTIONS:
		var action_name: StringName = action_variant
		var binding: Dictionary = _controls.get(action_name, {
			"keycode": ValueUtils.to_int(InputActions.DEFAULT_BINDINGS.get(action_name, KEY_NONE), KEY_NONE),
			"physical_keycode": ValueUtils.to_int(InputActions.DEFAULT_BINDINGS.get(action_name, KEY_NONE), KEY_NONE)
		})
		InputActions.apply_binding(
			action_name,
			ValueUtils.to_int(binding.get("keycode", KEY_NONE), KEY_NONE),
			ValueUtils.to_int(binding.get("physical_keycode", binding.get("keycode", KEY_NONE)), KEY_NONE)
		)

func _apply_audio() -> void:
	_apply_bus_volume("Master", float(_audio["master"]))
	_apply_bus_volume("Music", float(_audio["music"]))
	_apply_bus_volume("SFX", float(_audio["sfx"]))

func _apply_bus_volume(bus_name: String, value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var db_value: float = linear_to_db(value)
	if value <= 0.001:
		db_value = -80.0
	AudioServer.set_bus_volume_db(bus_index, db_value)

func _apply_display() -> void:
	var mode_name: String = str(_display["window_mode"])
	match mode_name:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(_display["vsync"]) else DisplayServer.VSYNC_DISABLED
	)
	get_tree().root.content_scale_factor = float(_display["ui_scale"])

func _find_conflict_action(target_action: StringName, keycode: int) -> StringName:
	for action_variant in InputActions.MENU_ACTIONS:
		var action_name: StringName = action_variant
		if action_name == target_action:
			continue
		var binding: Dictionary = get_binding(action_name)
		if ValueUtils.to_int(binding.get("keycode", KEY_NONE), KEY_NONE) == keycode:
			return action_name
	return StringName()
