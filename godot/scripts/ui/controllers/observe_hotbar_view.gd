extends RefCounted

const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")

var _owner: Control
var _box: HBoxContainer
var _hotbar_view: RefCounted
var _reason_catalog := ReasonCatalog.new()


func build(parent: Control, owner: Control, hotbar_view: RefCounted) -> void:
	if _box != null:
		return
	_owner = owner
	_hotbar_view = hotbar_view
	_box = HBoxContainer.new()
	_box.name = "ObserveHotbarDock"
	_box.add_theme_constant_override("separation", 4)
	parent.add_child(_box)


func apply(runtime_control_value: Variant) -> void:
	if _box == null:
		return
	for child in _box.get_children():
		_box.remove_child(child)
		child.free()
	var runtime_control: Dictionary = _dictionary_or_empty(runtime_control_value)
	var observe_mode := bool(runtime_control.get("observe_mode", false))
	var playback := bool(runtime_control.get("observe_playback", false))
	var speed := str(runtime_control.get("observe_speed", "x1"))
	var auto_tick := bool(runtime_control.get("auto_tick", false))
	var map_level: Dictionary = _dictionary_or_empty(runtime_control.get("map_level", {}))
	if _hotbar_view != null and _hotbar_view.has_method("set_visible"):
		_hotbar_view.call("set_visible", not observe_mode)
	_box.add_child(_mode_button(observe_mode))
	_box.add_child(_play_button(playback, observe_mode))
	_box.add_child(_speed_button(speed, observe_mode))
	_box.add_child(_auto_button(auto_tick))
	_box.add_child(_observe_button("ObserveLevelButton", "L%d" % int(map_level.get("current", 0)), "observe_level", int(map_level.get("current", 0)), true))


func _observe_button(node_name: String, text: String, meta_key: String, meta_value: Variant, disabled: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = _tooltip(meta_key, meta_value, disabled)
	button.custom_minimum_size = Vector2(max(42, text.length() * 10 + 18), 26)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = disabled
	button.set_meta(meta_key, meta_value)
	button.set_meta("disabled_reason", "observe_control_unavailable" if disabled else "")
	button.set_drag_forwarding(
		Callable(self, "_empty_drag_data"),
		Callable(self, "_can_drop_observe"),
		Callable(self, "_drop_observe")
	)
	_prepare_drop_target(button)
	return button


func _mode_button(observe_mode: bool) -> Button:
	var button := _observe_button("ObserveModeButton", "Player" if observe_mode else "Observe", "observe_mode", observe_mode, false)
	button.pressed.connect(func() -> void:
		_play_audio("ui_button_pressed", "ObserveModeButton", "observe_button", "toggle_observe_mode", {
			"observe_mode": observe_mode,
			"value": "off" if observe_mode else "on",
		})
		var root := _root()
		if root != null and root.has_method("toggle_observe_mode"):
			root.call_deferred("toggle_observe_mode")
	)
	return button


func _play_button(playback: bool, observe_mode: bool) -> Button:
	var button := _observe_button("ObservePlayButton", "Pause" if playback else "Play", "observe_playback", playback, not observe_mode)
	button.set_meta("observe_mode", observe_mode)
	if observe_mode:
		button.pressed.connect(func() -> void:
			_play_audio("ui_button_pressed", "ObservePlayButton", "observe_button", "toggle_observe_playback", {
				"observe_mode": observe_mode,
				"observe_playback": playback,
				"value": "pause" if playback else "play",
			})
			var root := _root()
			if root != null and root.has_method("toggle_observe_playback"):
				root.call_deferred("toggle_observe_playback")
		)
	return button


func _speed_button(speed: String, observe_mode: bool) -> Button:
	var button := _observe_button("ObserveSpeedButton", speed, "observe_speed", speed, not observe_mode)
	button.set_meta("observe_mode", observe_mode)
	if observe_mode:
		button.pressed.connect(func() -> void:
			_play_audio("ui_button_pressed", "ObserveSpeedButton", "observe_button", "cycle_observe_speed", {
				"observe_mode": observe_mode,
				"observe_speed": speed,
				"value": speed,
			})
			var root := _root()
			if root != null and root.has_method("cycle_observe_speed"):
				root.call_deferred("cycle_observe_speed")
		)
	return button


func _auto_button(auto_tick: bool) -> Button:
	var button := _observe_button("ObserveAutoButton", "Auto on" if auto_tick else "Auto off", "auto_tick", auto_tick, false)
	button.pressed.connect(func() -> void:
		_play_audio("ui_button_pressed", "ObserveAutoButton", "observe_button", "toggle_auto_tick", {
			"auto_tick": auto_tick,
			"value": "off" if auto_tick else "on",
		})
		var root := _root()
		if root != null and root.has_method("toggle_auto_tick"):
			root.call_deferred("toggle_auto_tick")
	)
	return button


func _tooltip(meta_key: String, meta_value: Variant, disabled: bool) -> String:
	var state := str(meta_value)
	match meta_key:
		"observe_playback":
			state = "播放" if bool(meta_value) else "暂停"
		"observe_speed":
			state = "速度 %s" % str(meta_value)
		"observe_level":
			state = "观察楼层 %d" % int(meta_value)
		"auto_tick":
			state = "自动推进 %s" % ("开启" if bool(meta_value) else "关闭")
		"observe_mode":
			state = "观察模式 %s" % ("开启" if bool(meta_value) else "关闭")
	if disabled:
		state = "%s | %s" % [state, _reason_catalog.disabled_text_for("observe_control_unavailable")]
	else:
		match meta_key:
			"observe_mode":
				state = "%s | 点击切换控制模式" % state
			"observe_playback":
				state = "%s | 点击切换观察播放" % state
			"observe_speed":
				state = "%s | 点击切换观察速度" % state
	return state


func _play_audio(event_kind: String, control_name: String, control_kind: String, action: String, extra_payload: Dictionary = {}) -> Dictionary:
	var root := _root()
	if root == null or not root.has_method("play_ui_audio_feedback"):
		return {}
	var payload := {
		"audio_source": "ui",
		"panel_id": "hud",
		"control_name": control_name,
		"control_kind": control_kind,
		"action": action,
	}
	for key in extra_payload.keys():
		payload[key] = extra_payload[key]
	return _dictionary_or_empty(root.call("play_ui_audio_feedback", event_kind, payload))


func _empty_drag_data(_position: Vector2, _from_control: Control) -> Variant:
	return null


func _can_drop_observe(_position: Vector2, data: Variant, from_control: Control) -> bool:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var reject_reason := "observe_hotbar_drag_unsupported" if not drag_data.is_empty() else ""
	_apply_drag_hover(from_control, reject_reason)
	return false


func _drop_observe(_position: Vector2, _data: Variant, from_control: Control) -> void:
	_clear_drag_hover(from_control)


func _prepare_drop_target(control: Control) -> void:
	if control == null:
		return
	control.set_meta("observe_hotbar_drag_hovered", false)
	control.set_meta("observe_hotbar_drag_last_accept", false)
	control.set_meta("observe_hotbar_drag_reject_reason", "")
	control.set_meta("observe_hotbar_drag_highlight_style", "")
	control.set_meta("observe_hotbar_drag_highlight_color", "")
	control.mouse_exited.connect(func() -> void:
		_clear_drag_hover(control)
	)


func _apply_drag_hover(control: Control, reject_reason: String) -> void:
	if control == null or not is_instance_valid(control) or _observe_control_key(control).is_empty():
		return
	var color_text := "#e25c5c"
	control.set_meta("observe_hotbar_drag_hovered", true)
	control.set_meta("observe_hotbar_drag_last_accept", false)
	control.set_meta("observe_hotbar_drag_reject_reason", reject_reason)
	control.set_meta("observe_hotbar_drag_highlight_style", "reject")
	control.set_meta("observe_hotbar_drag_highlight_color", color_text)
	control.modulate = Color(1.0, 0.90, 0.90, 1.0)
	if control is Button:
		(control as Button).add_theme_color_override("font_color", Color.html(color_text))


func _clear_drag_hover(control: Control) -> void:
	if control == null or not is_instance_valid(control) or _observe_control_key(control).is_empty():
		return
	control.set_meta("observe_hotbar_drag_hovered", false)
	control.set_meta("observe_hotbar_drag_last_accept", false)
	control.set_meta("observe_hotbar_drag_reject_reason", "")
	control.set_meta("observe_hotbar_drag_highlight_style", "")
	control.set_meta("observe_hotbar_drag_highlight_color", "")
	control.modulate = Color.WHITE
	if control is Button:
		(control as Button).remove_theme_color_override("font_color")


func _observe_control_key(control: Control) -> String:
	for key in ["observe_playback", "observe_speed", "auto_tick", "observe_level", "observe_mode"]:
		if control != null and control.has_meta(key):
			return key
	return ""


func _root() -> Node:
	return _owner.get_parent() if _owner != null else null


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
