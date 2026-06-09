extends Control

signal close_requested

const MediaTextureLoader = preload("res://scripts/ui/media_texture_loader.gd")

var _panel: PanelContainer
var _portrait_rect: TextureRect
var _speaker_label: Label
var _target_label: Label
var _text_scroll: ScrollContainer
var _text_label: Label
var _options_label: Label
var _options_box: VBoxContainer
var _close_button: Button
var _last_snapshot: Dictionary = {}


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()
	visible = false


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()
	_last_snapshot = snapshot.duplicate(true)

	var active: bool = bool(snapshot.get("active", false))
	visible = active
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if _panel != null:
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if not active:
		return

	if snapshot.has("error") and not bool(snapshot.get("fallback", false)):
		_speaker_label.text = "Dialogue %s" % snapshot.get("dialogue_id", "")
		_target_label.text = ""
		_text_label.text = "对话资源不可用: %s" % snapshot.get("error", "unknown")
		_options_label.text = ""
		_rebuild_option_buttons([])
		return

	_speaker_label.text = str(snapshot.get("speaker", ""))
	_target_label.text = _target_text(snapshot)
	_text_label.text = str(snapshot.get("text", ""))
	_apply_portrait(snapshot)
	var options: Array = snapshot.get("options", [])
	_options_label.text = _options_hint(options)
	_rebuild_option_buttons(options)
	_apply_diagnostics(snapshot)


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "DialoguePanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 220
	_panel.offset_right = -220
	_panel.offset_top = -190
	_panel.offset_bottom = -24
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "DialogueLines"
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var header := HBoxContainer.new()
	header.name = "DialogueHeader"
	header.add_theme_constant_override("separation", 8)
	_portrait_rect = TextureRect.new()
	_portrait_rect.name = "PortraitTexture"
	_portrait_rect.custom_minimum_size = Vector2(48, 48)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_speaker_label = _label("SpeakerLine")
	_speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "X"
	_close_button.tooltip_text = "关闭对话"
	_close_button.custom_minimum_size = Vector2(28, 24)
	_close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_button.pressed.connect(func() -> void:
		_play_dialogue_control_audio("ui_button_pressed", "CloseButton", "button", "close_dialogue", _dialogue_audio_payload())
		close_requested.emit()
	)
	_target_label = _label("TargetLine")
	_text_scroll = ScrollContainer.new()
	_text_scroll.name = "TextScroll"
	_text_scroll.custom_minimum_size = Vector2(0, 58)
	_text_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_text_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_text_label = _label("TextLine")
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.clip_text = false
	_options_label = _label("OptionsLine")
	_options_box = VBoxContainer.new()
	_options_box.name = "OptionButtons"
	_options_box.add_theme_constant_override("separation", 4)
	_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_portrait_rect)
	header.add_child(_speaker_label)
	header.add_child(_close_button)
	box.add_child(header)
	box.add_child(_target_label)
	_text_scroll.add_child(_text_label)
	box.add_child(_text_scroll)
	box.add_child(_options_label)
	box.add_child(_options_box)


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	return label


func _apply_portrait(snapshot: Dictionary) -> void:
	if _portrait_rect == null:
		return
	var portrait_asset := _dictionary_or_empty(snapshot.get("portrait_asset", {}))
	var texture := MediaTextureLoader.texture_from_asset(portrait_asset)
	_portrait_rect.texture = texture
	_portrait_rect.visible = texture != null
	if texture == null:
		_portrait_rect.remove_meta("portrait_resource_path")
		return
	_portrait_rect.set_meta("portrait_resource_path", MediaTextureLoader.resource_path_from_asset(portrait_asset))
	_portrait_rect.set_meta("portrait_fallback_key", str(portrait_asset.get("fallback_key", "")))


func _options_hint(options: Array) -> String:
	if options.is_empty():
		return "Space / Enter 继续"
	var parts: Array[String] = []
	for i in range(options.size()):
		var option_data: Dictionary = options[i]
		parts.append("%d. %s" % [i + 1, option_data.get("text", "")])
	return "选择: %s" % " / ".join(parts)


func _target_text(snapshot: Dictionary) -> String:
	var target: Dictionary = _dictionary_or_empty(snapshot.get("target", {}))
	var target_name := str(target.get("display_name", ""))
	if target_name.is_empty():
		target_name = str(target.get("definition_id", ""))
	if target_name.is_empty():
		return ""
	return "目标: %s" % target_name


func _apply_diagnostics(snapshot: Dictionary) -> void:
	var target: Dictionary = _dictionary_or_empty(snapshot.get("target", {}))
	set_meta("dialogue_id", str(snapshot.get("dialogue_id", "")))
	set_meta("node_id", str(snapshot.get("node_id", "")))
	set_meta("target_actor_id", int(target.get("actor_id", 0)))
	set_meta("target_definition_id", str(target.get("definition_id", "")))
	set_meta("target_display_name", str(target.get("display_name", "")))
	set_meta("target_source", str(target.get("source", "")))
	_panel.tooltip_text = "dialogue=%s node=%s target_actor=%d target_definition=%s target_source=%s" % [
		str(snapshot.get("dialogue_id", "")),
		str(snapshot.get("node_id", "")),
		int(target.get("actor_id", 0)),
		str(target.get("definition_id", "")),
		str(target.get("source", "")),
	]


func _rebuild_option_buttons(options: Array) -> void:
	if _options_box == null:
		return
	for child in _options_box.get_children():
		_options_box.remove_child(child)
		child.free()
	for i in range(options.size()):
		var option_data: Dictionary = options[i]
		_options_box.add_child(_option_button(i, option_data))


func _option_button(option_index: int, option: Dictionary) -> Button:
	var button := Button.new()
	button.name = "DialogueOption_%d" % (option_index + 1)
	button.text = "%d. %s" % [option_index + 1, str(option.get("text", ""))]
	var preview: Dictionary = _dictionary_or_empty(option.get("resolution_preview", {}))
	button.tooltip_text = _option_tooltip(option_index, option, preview)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = Vector2(420, 28)
	button.set_meta("option_index", option_index)
	button.set_meta("option_id", str(option.get("id", "")))
	button.set_meta("next", str(option.get("next", "")))
	button.set_meta("preview_ok", bool(preview.get("ok", true)))
	button.set_meta("preview_next_node_id", str(preview.get("next_node_id", "")))
	button.set_meta("preview_next_node_type", str(preview.get("next_node_type", "")))
	button.set_meta("preview_end_type", str(preview.get("end_type", "")))
	button.set_meta("preview_will_finish", bool(preview.get("will_finish", false)))
	button.set_meta("preview_action_count", int(preview.get("action_count", _array_or_empty(option.get("action_previews", [])).size())))
	button.set_meta("preview_action_types", ",".join(_string_array(_array_or_empty(option.get("action_types_preview", [])))))
	var turn_in_preview := _first_turn_in_preview(preview)
	button.set_meta("preview_turn_in_ready", bool(turn_in_preview.get("ready", true)))
	button.set_meta("preview_turn_in_reason", str(turn_in_preview.get("reason", "")))
	button.set_meta("preview_turn_in_summary", str(turn_in_preview.get("summary", "")))
	var condition_preview := _first_condition_preview(preview)
	button.set_meta("preview_condition_ready", bool(condition_preview.get("ready", true)))
	button.set_meta("preview_condition_reason", str(condition_preview.get("reason", "")))
	button.set_meta("preview_condition_summary", _condition_preview_summary(condition_preview))
	button.set_meta("preview_condition_missing_count", _array_or_empty(condition_preview.get("missing", [])).size())
	button.pressed.connect(func() -> void:
		_play_dialogue_control_audio("ui_button_pressed", "DialogueOption_%d" % (option_index + 1), "option_button", "choose_option", _dialogue_option_audio_payload(option_index, option, preview))
		var root := get_parent()
		if root != null and root.has_method("choose_dialogue_option"):
			root.choose_dialogue_option(option_index)
	, CONNECT_DEFERRED)
	return button


func _option_tooltip(option_index: int, option: Dictionary, preview: Dictionary) -> String:
	var parts: Array[String] = ["选择 %d | next: %s" % [option_index + 1, str(option.get("next", ""))]]
	var action_types := _string_array(_array_or_empty(option.get("action_types_preview", [])))
	if not action_types.is_empty():
		parts.append("actions: %s" % ", ".join(action_types))
	var turn_in_preview := _first_turn_in_preview(preview)
	var turn_in_summary := str(turn_in_preview.get("summary", ""))
	if not turn_in_summary.is_empty():
		parts.append("交付: %s" % turn_in_summary)
		if not bool(turn_in_preview.get("ready", true)):
			parts.append("交付限制: %s" % str(turn_in_preview.get("reason", "")))
	var condition_preview := _first_condition_preview(preview)
	var condition_summary := _condition_preview_summary(condition_preview)
	if not condition_summary.is_empty():
		parts.append("条件: %s" % condition_summary)
		if not bool(condition_preview.get("ready", true)):
			parts.append("条件限制: %s" % str(condition_preview.get("reason", "")))
	if bool(preview.get("will_finish", false)):
		parts.append("end: %s" % str(preview.get("end_type", "leave")))
	else:
		var next_type := str(preview.get("next_node_type", ""))
		var next_node := str(preview.get("next_node_id", ""))
		if not next_type.is_empty() or not next_node.is_empty():
			parts.append("preview: %s %s" % [next_type, next_node])
	if not bool(preview.get("ok", true)):
		parts.append("preview reason: %s" % str(preview.get("reason", "")))
	return " | ".join(parts)


func _play_dialogue_control_audio(event_kind: String, control_name: String, control_kind: String, action: String, extra_payload: Dictionary = {}) -> Dictionary:
	var root := get_parent()
	if root == null or not root.has_method("play_ui_audio_feedback"):
		return {}
	var payload := {
		"audio_source": "ui",
		"panel_id": "dialogue",
		"control_name": control_name,
		"control_kind": control_kind,
		"action": action,
	}
	for key in extra_payload.keys():
		payload[key] = extra_payload[key]
	return _dictionary_or_empty(root.call("play_ui_audio_feedback", event_kind, payload))


func _dialogue_audio_payload(extra_payload: Dictionary = {}) -> Dictionary:
	var target: Dictionary = _dictionary_or_empty(_last_snapshot.get("target", {}))
	var payload := {
		"dialogue_id": str(_last_snapshot.get("dialogue_id", "")),
		"node_id": str(_last_snapshot.get("node_id", "")),
		"target_actor_id": int(target.get("actor_id", 0)),
		"target_definition_id": str(target.get("definition_id", "")),
	}
	for key in extra_payload.keys():
		payload[key] = extra_payload[key]
	return payload


func _dialogue_option_audio_payload(option_index: int, option: Dictionary, preview: Dictionary) -> Dictionary:
	return _dialogue_audio_payload({
		"option_id": str(option.get("id", "")),
		"option_index": option_index + 1,
		"value": str(option.get("text", "")),
		"reason": str(preview.get("reason", "")),
	})


func _first_condition_preview(preview: Dictionary) -> Dictionary:
	for action in _array_or_empty(preview.get("action_previews", [])):
		var action_data := _dictionary_or_empty(action)
		var condition_preview := _dictionary_or_empty(action_data.get("condition_preview", {}))
		if not condition_preview.is_empty():
			return condition_preview
	return {}


func _condition_preview_summary(condition_preview: Dictionary) -> String:
	if condition_preview.is_empty():
		return ""
	var missing: Array = _array_or_empty(condition_preview.get("missing", []))
	if missing.is_empty():
		return "满足"
	var parts: Array[String] = []
	for missing_entry in missing:
		var data: Dictionary = _dictionary_or_empty(missing_entry)
		match str(data.get("kind", "")):
			"player_item_count_min":
				parts.append("%s %d/%d" % [
					str(data.get("item_id", "")),
					int(data.get("current", 0)),
					int(data.get("required", 0)),
				])
			"player_active_quests_any", "player_completed_quests_any", "world_flags_all", "world_flags_any", "world_flags_none":
				parts.append("%s: %s" % [str(data.get("kind", "")), ", ".join(_string_array(_array_or_empty(data.get("ids", []))))])
			_:
				parts.append(str(data.get("kind", "condition")))
	return " / ".join(parts)


func _first_turn_in_preview(preview: Dictionary) -> Dictionary:
	for action in _array_or_empty(preview.get("action_previews", [])):
		var action_data := _dictionary_or_empty(action)
		var turn_in_preview := _dictionary_or_empty(action_data.get("turn_in_preview", {}))
		if not turn_in_preview.is_empty():
			return turn_in_preview
	return {}


func _string_array(values: Array) -> Array[String]:
	var output: Array[String] = []
	for value in values:
		output.append(str(value))
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
