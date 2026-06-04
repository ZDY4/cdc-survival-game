extends Control

signal close_requested

var _panel: PanelContainer
var _speaker_label: Label
var _target_label: Label
var _text_scroll: ScrollContainer
var _text_label: Label
var _options_label: Label
var _options_box: VBoxContainer
var _close_button: Button


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()
	visible = false


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	var active: bool = bool(snapshot.get("active", false))
	visible = active
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if _panel != null:
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if not active:
		return

	if snapshot.has("error"):
		_speaker_label.text = "Dialogue %s" % snapshot.get("dialogue_id", "")
		_target_label.text = ""
		_text_label.text = "对话资源不可用: %s" % snapshot.get("error", "unknown")
		_options_label.text = ""
		_rebuild_option_buttons([])
		return

	_speaker_label.text = str(snapshot.get("speaker", ""))
	_target_label.text = _target_text(snapshot)
	_text_label.text = str(snapshot.get("text", ""))
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
	_speaker_label = _label("SpeakerLine")
	_speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "X"
	_close_button.tooltip_text = "关闭对话"
	_close_button.custom_minimum_size = Vector2(28, 24)
	_close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_button.pressed.connect(func() -> void:
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
	_panel.tooltip_text = "dialogue=%s node=%s target_actor=%d" % [
		str(snapshot.get("dialogue_id", "")),
		str(snapshot.get("node_id", "")),
		int(target.get("actor_id", 0)),
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
	button.tooltip_text = "选择 %d | next: %s" % [option_index + 1, str(option.get("next", ""))]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = Vector2(420, 28)
	button.set_meta("option_index", option_index)
	button.set_meta("next", str(option.get("next", "")))
	button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("choose_dialogue_option"):
			root.choose_dialogue_option(option_index)
	, CONNECT_DEFERRED)
	return button


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
