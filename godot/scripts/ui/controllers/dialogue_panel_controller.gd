extends Control

var _panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _options_label: Label


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
	if not active:
		return

	if snapshot.has("error"):
		_speaker_label.text = "Dialogue %s" % snapshot.get("dialogue_id", "")
		_text_label.text = "对话资源不可用: %s" % snapshot.get("error", "unknown")
		_options_label.text = ""
		return

	_speaker_label.text = str(snapshot.get("speaker", ""))
	_text_label.text = str(snapshot.get("text", ""))
	_options_label.text = _options_text(snapshot.get("options", []))


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

	_speaker_label = _label("SpeakerLine")
	_text_label = _label("TextLine")
	_options_label = _label("OptionsLine")
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_speaker_label)
	box.add_child(_text_label)
	box.add_child(_options_label)


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	return label


func _options_text(options: Array) -> String:
	if options.is_empty():
		return ""
	var parts: Array[String] = []
	for i in range(options.size()):
		var option_data: Dictionary = options[i]
		parts.append("%d. %s" % [i + 1, option_data.get("text", "")])
	return " / ".join(parts)
