extends Control

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")
const MediaTextureLoader = preload("res://scripts/ui/media_texture_loader.gd")

const DEFAULT_SETTINGS_PATH := "user://settings.json"
const SETTINGS_SCHEMA_VERSION := 1

var settings_state: Dictionary = {
	"master_volume": 100,
	"music_volume": 100,
	"sfx_volume": 100,
	"window_mode": "windowed",
	"resolution": "1280x720",
	"vsync": true,
	"keybinding_profile": "default",
}
var last_persistence_result: Dictionary = {}
var last_apply_result: Dictionary = {}
var settings_path := DEFAULT_SETTINGS_PATH


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_path = str(ProjectSettings.get_setting("cdc/settings_path", DEFAULT_SETTINGS_PATH))
	_load_settings()
	_apply_settings()
	_build_layout()


func settings_snapshot() -> Dictionary:
	var snapshot := settings_state.duplicate(true)
	snapshot["schema_version"] = SETTINGS_SCHEMA_VERSION
	snapshot["settings_path"] = settings_path
	snapshot["persistence"] = last_persistence_result.duplicate(true)
	snapshot["applied"] = last_apply_result.duplicate(true)
	return snapshot


func _build_layout() -> void:
	if get_node_or_null("SettingsPanel") != null:
		return

	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -430
	panel.offset_right = -16
	panel.offset_top = 224
	panel.offset_bottom = 612
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var box := VBoxContainer.new()
	box.name = "SettingsLines"
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	box.add_child(_settings_label("TitleLine", "设置"))
	box.add_child(_settings_label("AudioLine", ""))
	box.add_child(_settings_slider_row("MasterVolume", "主音量", int(settings_state.get("master_volume", 100)), func(value: float) -> void:
		settings_state["master_volume"] = int(roundf(value))
		_commit_settings_update()
	))
	box.add_child(_settings_slider_row("MusicVolume", "音乐", int(settings_state.get("music_volume", 100)), func(value: float) -> void:
		settings_state["music_volume"] = int(roundf(value))
		_commit_settings_update()
	))
	box.add_child(_settings_slider_row("SfxVolume", "音效", int(settings_state.get("sfx_volume", 100)), func(value: float) -> void:
		settings_state["sfx_volume"] = int(roundf(value))
		_commit_settings_update()
	))
	box.add_child(_settings_label("DisplayLine", ""))
	box.add_child(_settings_option_row("WindowMode", "窗口", _settings_window_modes(), str(settings_state.get("window_mode", "windowed")), func(option_id: String) -> void:
		settings_state["window_mode"] = option_id
		_commit_settings_update()
	))
	box.add_child(_settings_option_row("Resolution", "分辨率", _settings_resolutions(), str(settings_state.get("resolution", "1280x720")), func(option_id: String) -> void:
		settings_state["resolution"] = option_id
		_commit_settings_update()
	))
	box.add_child(_settings_checkbox_row("VSync", "VSync", bool(settings_state.get("vsync", true)), func(enabled: bool) -> void:
		settings_state["vsync"] = enabled
		_commit_settings_update()
	))
	box.add_child(_settings_keybinding_row())
	box.add_child(_settings_label("ControlsLine", ""))
	box.add_child(_settings_reset_row())
	box.add_child(_settings_label("SettingsFeedbackLine", ""))
	_refresh_settings_panel_texts()


func _settings_slider_row(node_prefix: String, label_text: String, value: int, callback: Callable, min_value: int = 0, max_value: int = 100, step: int = 1) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "%sRow" % node_prefix
	row.custom_minimum_size = Vector2(380, 28)
	row.add_theme_constant_override("separation", 8)
	var label := _settings_label("%sLabel" % node_prefix, label_text)
	label.custom_minimum_size = Vector2(64, 24)
	var slider := HSlider.new()
	slider.name = "%sSlider" % node_prefix
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = clampi(value, min_value, max_value)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = "%s %d%%" % [label_text, int(slider.value)]
	slider.value_changed.connect(callback, CONNECT_DEFERRED)
	row.add_child(label)
	row.add_child(slider)
	return row


func _settings_option_row(node_prefix: String, label_text: String, options: Array[Dictionary], selected_id: String, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "%sRow" % node_prefix
	row.custom_minimum_size = Vector2(380, 30)
	row.add_theme_constant_override("separation", 8)
	var label := _settings_label("%sLabel" % node_prefix, label_text)
	label.custom_minimum_size = Vector2(64, 24)
	var option := OptionButton.new()
	option.name = "%sOption" % node_prefix
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_index := 0
	for i in range(options.size()):
		var option_data: Dictionary = _dictionary_or_empty(options[i])
		option.add_item(str(option_data.get("label", option_data.get("id", ""))))
		option.set_item_metadata(i, str(option_data.get("id", "")))
		if str(option_data.get("id", "")) == selected_id:
			selected_index = i
	option.select(selected_index)
	option.item_selected.connect(func(index: int) -> void:
		callback.call(str(option.get_item_metadata(index)))
	, CONNECT_DEFERRED)
	row.add_child(label)
	row.add_child(option)
	return row


func _settings_checkbox_row(node_prefix: String, label_text: String, enabled: bool, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "%sRow" % node_prefix
	row.custom_minimum_size = Vector2(380, 28)
	var checkbox := CheckBox.new()
	checkbox.name = "%sCheckBox" % node_prefix
	checkbox.text = label_text
	checkbox.button_pressed = enabled
	checkbox.tooltip_text = "切换 %s" % label_text
	checkbox.toggled.connect(callback, CONNECT_DEFERRED)
	row.add_child(checkbox)
	return row


func _settings_keybinding_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "KeybindingRow"
	row.custom_minimum_size = Vector2(380, 30)
	row.add_theme_constant_override("separation", 8)
	var label := _settings_label("KeybindingLabel", "按键")
	label.custom_minimum_size = Vector2(64, 24)
	var button := Button.new()
	button.name = "KeybindingCycleButton"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "切换按键方案"
	_apply_settings_button_icon(button, "res://assets/icons/settings/keybinding.svg")
	button.pressed.connect(func() -> void:
		settings_state["keybinding_profile"] = _next_keybinding_profile(str(settings_state.get("keybinding_profile", "default")))
		_commit_settings_update()
	, CONNECT_DEFERRED)
	row.add_child(label)
	row.add_child(button)
	return row


func _settings_reset_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "ResetSettingsRow"
	row.custom_minimum_size = Vector2(380, 30)
	var button := Button.new()
	button.name = "ResetSettingsButton"
	button.text = "恢复默认"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "恢复默认设置并保存"
	_apply_settings_button_icon(button, "res://assets/icons/settings/reset.svg")
	button.pressed.connect(reset_to_defaults, CONNECT_DEFERRED)
	row.add_child(button)
	return row


func _apply_settings_button_icon(button: Button, resource_path: String) -> void:
	var icon_asset := AssetPathResolver.resolve_media_asset(resource_path, "settings")
	var texture := MediaTextureLoader.texture_from_asset(icon_asset)
	if texture == null:
		button.icon = null
		return
	button.icon = texture
	button.expand_icon = true
	button.set_meta("icon_resource_path", MediaTextureLoader.resource_path_from_asset(icon_asset))
	button.set_meta("icon_fallback_key", str(icon_asset.get("fallback_key", "")))


func reset_to_defaults() -> Dictionary:
	settings_state = _default_settings_state()
	_commit_settings_update()
	return settings_snapshot()


func _refresh_settings_panel_texts() -> void:
	var audio := find_child("AudioLine", true, false) as Label
	if audio != null:
		audio.text = "音量: 主音量 %d%% | 音乐 %d%% | 音效 %d%%" % [
			int(settings_state.get("master_volume", 100)),
			int(settings_state.get("music_volume", 100)),
			int(settings_state.get("sfx_volume", 100)),
		]
	var display := find_child("DisplayLine", true, false) as Label
	if display != null:
		display.text = "显示: %s | %s | VSync %s" % [
			_settings_option_label(_settings_window_modes(), str(settings_state.get("window_mode", "windowed"))),
			str(settings_state.get("resolution", "1280x720")),
			"开启" if bool(settings_state.get("vsync", true)) else "关闭",
		]
	var controls := find_child("ControlsLine", true, false) as Label
	if controls != null:
		controls.text = "按键方案: %s | Esc 关闭 | I/C/M/J/K/L 面板 | Space 等待" % _settings_option_label(_settings_keybinding_profiles(), str(settings_state.get("keybinding_profile", "default")))
	var feedback := find_child("SettingsFeedbackLine", true, false) as Label
	if feedback != null:
		feedback.text = _settings_feedback_text()
	var key_button := find_child("KeybindingCycleButton", true, false) as Button
	if key_button != null:
		key_button.text = _settings_option_label(_settings_keybinding_profiles(), str(settings_state.get("keybinding_profile", "default")))
	_sync_settings_controls()
	_sync_slider_tooltip("MasterVolume", "主音量")
	_sync_slider_tooltip("MusicVolume", "音乐")
	_sync_slider_tooltip("SfxVolume", "音效")


func _commit_settings_update() -> void:
	_normalize_settings_state()
	_save_settings()
	_apply_settings()
	_refresh_settings_panel_texts()


func _load_settings() -> void:
	last_persistence_result = {"loaded": false, "saved": false, "path": settings_path}
	if not FileAccess.file_exists(settings_path):
		_normalize_settings_state()
		return
	var raw := FileAccess.get_file_as_string(settings_path)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		last_persistence_result["error"] = "invalid_json"
		settings_state = _default_settings_state()
		_normalize_settings_state()
		return
	var envelope: Dictionary = parsed
	var loaded_settings := {}
	var migrated := false
	var loaded_schema := int(envelope.get("schema_version", 0))
	if envelope.has("settings"):
		if loaded_schema != SETTINGS_SCHEMA_VERSION:
			last_persistence_result["error"] = "settings_schema_unsupported"
			last_persistence_result["schema_version"] = loaded_schema
			settings_state = _default_settings_state()
			_normalize_settings_state()
			return
		loaded_settings = _dictionary_or_empty(envelope.get("settings", {}))
	else:
		loaded_settings = envelope
		migrated = true
		loaded_schema = 0
	settings_state = _default_settings_state()
	for key in settings_state.keys():
		if loaded_settings.has(key):
			settings_state[key] = loaded_settings[key]
	_normalize_settings_state()
	last_persistence_result = {
		"loaded": true,
		"saved": false,
		"path": settings_path,
		"schema_version": SETTINGS_SCHEMA_VERSION,
		"loaded_schema_version": loaded_schema,
		"migrated": migrated,
	}
	if migrated:
		_save_settings()


func _save_settings() -> void:
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file == null:
		last_persistence_result = {
			"loaded": bool(last_persistence_result.get("loaded", false)),
			"saved": false,
			"path": settings_path,
			"error": error_string(FileAccess.get_open_error()),
		}
		return
	file.store_string(JSON.stringify({
		"schema_version": SETTINGS_SCHEMA_VERSION,
		"settings": settings_state,
	}, "\t"))
	file.close()
	last_persistence_result = {
		"loaded": bool(last_persistence_result.get("loaded", false)),
		"saved": true,
		"path": settings_path,
		"schema_version": SETTINGS_SCHEMA_VERSION,
		"migrated": bool(last_persistence_result.get("migrated", false)),
		"loaded_schema_version": int(last_persistence_result.get("loaded_schema_version", SETTINGS_SCHEMA_VERSION)),
	}


func _apply_settings() -> void:
	var audio: Dictionary = _apply_audio_settings()
	var display: Dictionary = _apply_display_settings()
	var keybinding: Dictionary = _apply_keybinding_settings()
	last_apply_result = {
		"audio": audio,
		"display": display,
		"keybinding": keybinding,
	}
	_notify_settings_applied()


func _apply_audio_settings() -> Dictionary:
	var result: Dictionary = {}
	_apply_bus_volume(result, "Master", int(settings_state.get("master_volume", 100)))
	_apply_bus_volume(result, "Music", int(settings_state.get("music_volume", 100)))
	_apply_bus_volume(result, "SFX", int(settings_state.get("sfx_volume", 100)))
	return result


func _apply_bus_volume(result: Dictionary, bus_name: String, percent: int) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		result[bus_name] = {"applied": false, "reason": "bus_missing", "percent": percent}
		return
	var clamped := clampi(percent, 0, 100)
	AudioServer.set_bus_volume_db(bus_index, -80.0 if clamped <= 0 else linear_to_db(float(clamped) / 100.0))
	result[bus_name] = {"applied": true, "percent": clamped}


func _apply_display_settings() -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {
			"applied": false,
			"reason": "headless",
			"window_mode": str(settings_state.get("window_mode", "windowed")),
			"resolution": str(settings_state.get("resolution", "1280x720")),
			"vsync": bool(settings_state.get("vsync", true)),
		}
	var resolution := _resolution_vector(str(settings_state.get("resolution", "1280x720")))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(settings_state.get("vsync", true)) else DisplayServer.VSYNC_DISABLED)
	match str(settings_state.get("window_mode", "windowed")):
		"fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
	return {
		"applied": true,
		"window_mode": str(settings_state.get("window_mode", "windowed")),
		"resolution": str(settings_state.get("resolution", "1280x720")),
		"vsync": bool(settings_state.get("vsync", true)),
	}


func _apply_keybinding_settings() -> Dictionary:
	var profile := str(settings_state.get("keybinding_profile", "default"))
	ProjectSettings.set_setting("cdc/keybinding_profile", profile)
	return {
		"applied": true,
		"profile": profile,
		"panel_keys": _panel_key_labels_for_profile(profile),
	}


func _notify_settings_applied() -> void:
	var target := get_parent()
	if target != null and target.has_method("settings_applied"):
		target.call("settings_applied", settings_snapshot())


func _panel_key_labels_for_profile(profile: String) -> Dictionary:
	match profile:
		"left_handed":
			return {
				"inventory": "Q",
				"character": "E",
				"journal": "R",
				"map": "T",
				"skills": "Y",
				"crafting": "U",
			}
		"controller":
			return {
				"inventory": "I",
				"character": "C",
				"journal": "J",
				"map": "M",
				"skills": "K",
				"crafting": "L",
			}
		_:
			return {
				"inventory": "I",
				"character": "C",
				"journal": "J",
				"map": "M",
				"skills": "K",
				"crafting": "L",
			}


func _resolution_vector(value: String) -> Vector2i:
	var parts := value.split("x", false)
	if parts.size() != 2:
		return Vector2i(1280, 720)
	return Vector2i(max(1, int(parts[0])), max(1, int(parts[1])))


func _normalize_settings_state() -> void:
	settings_state["master_volume"] = clampi(int(settings_state.get("master_volume", 100)), 0, 100)
	settings_state["music_volume"] = clampi(int(settings_state.get("music_volume", 100)), 0, 100)
	settings_state["sfx_volume"] = clampi(int(settings_state.get("sfx_volume", 100)), 0, 100)
	settings_state["window_mode"] = _known_option_id(_settings_window_modes(), str(settings_state.get("window_mode", "windowed")), "windowed")
	settings_state["resolution"] = _known_option_id(_settings_resolutions(), str(settings_state.get("resolution", "1280x720")), "1280x720")
	settings_state["keybinding_profile"] = _known_option_id(_settings_keybinding_profiles(), str(settings_state.get("keybinding_profile", "default")), "default")
	settings_state["vsync"] = bool(settings_state.get("vsync", true))


func _default_settings_state() -> Dictionary:
	return {
		"master_volume": 100,
		"music_volume": 100,
		"sfx_volume": 100,
		"window_mode": "windowed",
		"resolution": "1280x720",
		"vsync": true,
		"keybinding_profile": "default",
	}


func _known_option_id(options: Array[Dictionary], option_id: String, fallback: String) -> String:
	for option in options:
		if str(_dictionary_or_empty(option).get("id", "")) == option_id:
			return option_id
	return fallback


func _settings_feedback_text() -> String:
	var saved := bool(last_persistence_result.get("saved", false))
	var display: Dictionary = _dictionary_or_empty(last_apply_result.get("display", {}))
	if saved and bool(display.get("applied", false)):
		return "设置已保存并应用"
	if saved:
		return "设置已保存（%s）" % str(display.get("reason", "部分应用待完成"))
	if last_persistence_result.has("error"):
		return "设置保存失败: %s" % last_persistence_result.get("error", "")
	return "设置已加载（当前会话）"


func _sync_slider_tooltip(node_prefix: String, label_text: String) -> void:
	var slider := find_child("%sSlider" % node_prefix, true, false) as HSlider
	if slider != null:
		slider.tooltip_text = "%s %d%%" % [label_text, int(slider.value)]


func _sync_settings_controls() -> void:
	_sync_slider_value("MasterVolumeSlider", int(settings_state.get("master_volume", 100)))
	_sync_slider_value("MusicVolumeSlider", int(settings_state.get("music_volume", 100)))
	_sync_slider_value("SfxVolumeSlider", int(settings_state.get("sfx_volume", 100)))
	_sync_option_value("WindowModeOption", str(settings_state.get("window_mode", "windowed")))
	_sync_option_value("ResolutionOption", str(settings_state.get("resolution", "1280x720")))
	var checkbox := find_child("VSyncCheckBox", true, false) as CheckBox
	if checkbox != null:
		checkbox.set_block_signals(true)
		checkbox.button_pressed = bool(settings_state.get("vsync", true))
		checkbox.set_block_signals(false)


func _sync_slider_value(node_name: String, value: int) -> void:
	var slider := find_child(node_name, true, false) as HSlider
	if slider == null:
		return
	slider.set_block_signals(true)
	slider.value = value
	slider.set_block_signals(false)


func _sync_option_value(node_name: String, option_id: String) -> void:
	var option := find_child(node_name, true, false) as OptionButton
	if option == null:
		return
	for i in range(option.get_item_count()):
		if str(option.get_item_metadata(i)) == option_id:
			option.set_block_signals(true)
			option.select(i)
			option.set_block_signals(false)
			return


func _settings_window_modes() -> Array[Dictionary]:
	return [
		{"id": "windowed", "label": "窗口模式"},
		{"id": "fullscreen", "label": "全屏"},
		{"id": "borderless", "label": "无边框"},
	]


func _settings_resolutions() -> Array[Dictionary]:
	return [
		{"id": "1280x720", "label": "1280x720"},
		{"id": "1600x900", "label": "1600x900"},
		{"id": "1920x1080", "label": "1920x1080"},
	]


func _settings_keybinding_profiles() -> Array[Dictionary]:
	return [
		{"id": "default", "label": "默认"},
		{"id": "left_handed", "label": "左手"},
		{"id": "controller", "label": "手柄"},
	]


func _settings_option_label(options: Array[Dictionary], option_id: String) -> String:
	for option in options:
		var data: Dictionary = _dictionary_or_empty(option)
		if str(data.get("id", "")) == option_id:
			return str(data.get("label", option_id))
	return option_id


func _next_keybinding_profile(current_id: String) -> String:
	var profiles := _settings_keybinding_profiles()
	for i in range(profiles.size()):
		if str(_dictionary_or_empty(profiles[i]).get("id", "")) == current_id:
			return str(_dictionary_or_empty(profiles[(i + 1) % profiles.size()]).get("id", "default"))
	return "default"


func _settings_label(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
