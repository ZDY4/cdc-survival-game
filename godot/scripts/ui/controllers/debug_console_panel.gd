extends RefCounted

var _panel: PanelContainer
var _history_label: Label
var _suggestions_label: Label
var _input: LineEdit
var _owner: Control
var _visible := false
var _history: Array[String] = []
var _command_history: Array[String] = []
var _history_index := -1
var _command_schema: Array[Dictionary] = []
var _permission: Dictionary = {}
var _suggestions: Array[String] = [
	"help",
	"show fps",
	"show overlays",
	"observe mode",
	"clear",
	"restart",
	"give item 1006 1",
	"teleport 0 0 0",
	"spawn zombie_walker",
	"unlock location forest",
]


func build(owner: Control) -> void:
	if _panel != null:
		return
	_owner = owner
	_panel = PanelContainer.new()
	_panel.name = "DebugConsole"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 16
	_panel.offset_right = -16
	_panel.offset_top = -142
	_panel.offset_bottom = -16
	owner.add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "ConsoleLines"
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)

	_history_label = _line("ConsoleHistory")
	_suggestions_label = _line("ConsoleSuggestions")
	_input = LineEdit.new()
	_input.name = "ConsoleInput"
	_input.placeholder_text = "debug command"
	_input.focus_mode = Control.FOCUS_ALL
	_input.text_submitted.connect(_submit_command)
	_input.gui_input.connect(_handle_input_event)
	box.add_child(_history_label)
	box.add_child(_suggestions_label)
	box.add_child(_input)
	apply()


func toggle() -> Dictionary:
	_visible = not _visible
	apply()
	if _visible and _input != null:
		_input.grab_focus()
	return {"success": true, "visible": _visible}


func hide() -> void:
	_visible = false
	apply()


func is_open() -> bool:
	return _visible


func input_node() -> LineEdit:
	return _input


func snapshot() -> Dictionary:
	return {
		"visible": _visible,
		"history": _history.duplicate(),
		"history_count": _history.size(),
		"command_history": _command_history.duplicate(),
		"command_history_count": _command_history.size(),
		"history_index": _history_index,
		"command_schema": _command_schema.duplicate(true),
		"command_schema_count": _command_schema.size(),
		"command_details": _command_detail_lines(),
		"permission": _permission.duplicate(true),
		"suggestions": _suggestions.duplicate(),
		"suggestion_count": _suggestions.size(),
		"input_text": _input.text if _input != null else "",
	}


func set_schema(schema: Array, suggestions: Array, permission: Dictionary = {}) -> void:
	_command_schema.clear()
	for command in schema:
		var command_data: Dictionary = _dictionary_or_empty(command)
		if not command_data.is_empty():
			_command_schema.append(command_data.duplicate(true))
	_permission = permission.duplicate(true)
	var normalized_suggestions: Array[String] = []
	for suggestion in suggestions:
		var suggestion_text := str(suggestion).strip_edges()
		if not suggestion_text.is_empty() and not normalized_suggestions.has(suggestion_text):
			normalized_suggestions.append(suggestion_text)
	if not normalized_suggestions.is_empty():
		_suggestions = normalized_suggestions
	apply()


func set_result(command_text: String, result: Dictionary) -> void:
	var status := "ok" if bool(result.get("success", false)) else "err"
	var message := str(result.get("message", result.get("reason", "")))
	_history.append("> %s" % command_text)
	_history.append("%s: %s" % [status, message])
	_record_command(command_text)
	while _history.size() > 8:
		_history.pop_front()
	if _input != null:
		_input.text = ""
	apply()


func clear_history() -> void:
	_history.clear()
	apply()


func apply() -> void:
	if _panel == null:
		return
	_panel.visible = _visible
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if _visible else Control.MOUSE_FILTER_IGNORE
	if _history_label != null:
		_history_label.text = "\n".join(_history)
	if _suggestions_label != null:
		_suggestions_label.text = _help_text()
	if not _visible and _input != null:
		_input.release_focus()


func _submit_command(text: String) -> void:
	if _owner == null:
		return
	var root := _owner.get_tree().current_scene
	if root != null and root.has_method("submit_debug_console_command"):
		root.submit_debug_console_command(text)


func _handle_input_event(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var key := key_event.keycode
	if key == 0:
		key = key_event.physical_keycode
	if key == KEY_UP:
		_recall_history(-1)
		_input.accept_event()
	elif key == KEY_DOWN:
		_recall_history(1)
		_input.accept_event()
	elif key == KEY_TAB:
		_autocomplete_input()
		_input.accept_event()


func _recall_history(direction: int) -> void:
	if _input == null or _command_history.is_empty():
		return
	if _history_index < 0:
		_history_index = _command_history.size()
	_history_index = clampi(_history_index + direction, 0, _command_history.size())
	if _history_index >= _command_history.size():
		_input.text = ""
	else:
		_input.text = _command_history[_history_index]
	_input.caret_column = _input.text.length()


func _autocomplete_input() -> void:
	if _input == null:
		return
	var prefix := _input.text.strip_edges().to_lower()
	var matches: Array[String] = []
	for suggestion in _suggestions:
		if str(suggestion).begins_with(prefix):
			matches.append(str(suggestion))
	if matches.is_empty():
		return
	var replacement := matches[0] if matches.size() == 1 else _shared_prefix(matches)
	if replacement.length() <= prefix.length():
		replacement = matches[0]
	_input.text = replacement
	_input.caret_column = _input.text.length()


func _record_command(command_text: String) -> void:
	var normalized := command_text.strip_edges()
	if normalized.is_empty():
		_history_index = -1
		return
	if _command_history.is_empty() or _command_history[_command_history.size() - 1] != normalized:
		_command_history.append(normalized)
	while _command_history.size() > 16:
		_command_history.pop_front()
	_history_index = -1


func _help_text() -> String:
	var details := _command_detail_lines()
	if not details.is_empty():
		var shown := details.slice(0, mini(details.size(), 5))
		var suffix := " | ..." if details.size() > shown.size() else ""
		return "commands: %s%s" % [" | ".join(shown), suffix]
	return "suggestions: %s" % ", ".join(_suggestions)


func _command_detail_lines() -> Array[String]:
	var lines: Array[String] = []
	for command in _command_schema:
		var usage := str(command.get("usage", "")).strip_edges()
		if usage.is_empty():
			continue
		var description := str(command.get("description", "")).strip_edges()
		lines.append("%s - %s" % [usage, description] if not description.is_empty() else usage)
	return lines


func _shared_prefix(values: Array[String]) -> String:
	if values.is_empty():
		return ""
	var prefix := values[0]
	for value in values:
		while not str(value).begins_with(prefix) and not prefix.is_empty():
			prefix = prefix.substr(0, prefix.length() - 1)
	return prefix


func _line(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	return label


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
