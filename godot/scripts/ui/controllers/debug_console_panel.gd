extends RefCounted

var _panel: Control
var _background: PanelContainer
var _history_label: Label
var _suggestions_label: Label
var _completion_list: ItemList
var _input: LineEdit
var _owner: Control
var _visible := false
var _history: Array[String] = []
var _command_history: Array[String] = []
var _history_index := -1
var _command_schema: Array[Dictionary] = []
var _permission: Dictionary = {}
var _completion_candidates: Array[String] = []
var _completion_selected_index := -1
var _completion_query_text := ""
var _suppress_completion_refresh := false
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
	_panel = Control.new()
	_panel.name = "DebugConsole"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = -236
	_panel.offset_bottom = 0
	owner.add_child(_panel)

	_background = PanelContainer.new()
	_background.name = "ConsoleBackground"
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.offset_left = 0
	_background.offset_top = 0
	_background.offset_right = 0
	_background.offset_bottom = 0
	_background.add_theme_stylebox_override("panel", _console_panel_style())
	_panel.add_child(_background)

	var box := VBoxContainer.new()
	box.name = "ConsoleLines"
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_top = 8
	box.offset_right = -12
	box.offset_bottom = -36
	_panel.add_child(box)

	_history_label = _line("ConsoleHistory")
	_history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_suggestions_label = _line("ConsoleSuggestions")
	_suggestions_label.custom_minimum_size = Vector2(0, 20)
	_completion_list = ItemList.new()
	_completion_list.name = "ConsoleCompletionList"
	_completion_list.custom_minimum_size = Vector2(0, 112)
	_completion_list.auto_height = false
	_completion_list.select_mode = ItemList.SELECT_SINGLE
	_completion_list.allow_reselect = true
	_completion_list.focus_mode = Control.FOCUS_NONE
	_completion_list.visible = false
	_completion_list.item_selected.connect(_select_completion_index)
	_completion_list.item_activated.connect(_activate_completion_index)
	_input = LineEdit.new()
	_input.name = "ConsoleInput"
	_input.placeholder_text = "debug command"
	_input.focus_mode = Control.FOCUS_ALL
	_input.custom_minimum_size = Vector2(0, 32)
	_input.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_input.offset_left = 12
	_input.offset_top = -32
	_input.offset_right = -12
	_input.offset_bottom = 0
	_input.text_changed.connect(_input_text_changed)
	_input.text_submitted.connect(_submit_command)
	_input.gui_input.connect(_handle_input_event)
	box.add_child(_history_label)
	box.add_child(_suggestions_label)
	box.add_child(_completion_list)
	_panel.add_child(_input)
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
		"completion_visible": _completion_list != null and _completion_list.visible,
		"completion_candidates": _completion_candidates.duplicate(),
		"completion_selected_index": _completion_selected_index,
		"completion_selected_text": _selected_completion_text(),
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
	_refresh_completions()
	apply()


func set_result(command_text: String, result: Dictionary) -> void:
	var status := "ok" if bool(result.get("success", false)) else "err"
	var message := str(result.get("message", result.get("reason", "")))
	_history.append("> %s" % command_text)
	_history.append("%s: %s" % [status, message])
	_record_command(command_text)
	while _history.size() > 8:
		_history.pop_front()
	_completion_query_text = ""
	if _input != null:
		_replace_input_text("")
	_refresh_completions()
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
	_refresh_completion_list()
	if not _visible and _input != null and _input.is_inside_tree():
		_input.release_focus()


func _submit_command(text: String) -> void:
	if _complete_selected_if_needed():
		return
	if _owner == null:
		return
	var root := _owner.get_tree().current_scene
	if root != null and root.has_method("submit_debug_console_command"):
		root.submit_debug_console_command(text)


func _input_text_changed(_text: String) -> void:
	if _suppress_completion_refresh:
		return
	_history_index = -1
	_completion_query_text = _text
	_refresh_completions()


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
		if not _move_completion_selection(-1):
			_recall_history(-1)
		_input.accept_event()
	elif key == KEY_DOWN:
		if not _move_completion_selection(1):
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
		_replace_input_text("")
	else:
		_replace_input_text(_command_history[_history_index])
	_completion_query_text = ""
	_completion_candidates.clear()
	_completion_selected_index = -1
	_refresh_completion_list()


func _autocomplete_input() -> void:
	if _input == null:
		return
	if _completion_candidates.is_empty():
		_refresh_completions()
	var replacement := _selected_completion_text()
	if replacement.is_empty() and not _completion_candidates.is_empty():
		replacement = _completion_candidates[0]
	if replacement.is_empty():
		return
	_set_input_text(replacement)


func _refresh_completions() -> void:
	_completion_candidates.clear()
	var source_text := _completion_query_text
	if source_text.is_empty() and _input != null:
		source_text = _input.text
	var prefix := source_text.strip_edges().to_lower()
	var compact_prefix := _completion_key(prefix)
	var limit := 6
	for suggestion in _suggestions:
		var suggestion_text := str(suggestion).strip_edges()
		if suggestion_text.is_empty():
			continue
		var suggestion_key := suggestion_text.to_lower()
		var compact_suggestion_key := _completion_key(suggestion_key)
		if prefix.is_empty() or suggestion_key.begins_with(prefix) or (not compact_prefix.is_empty() and compact_suggestion_key.begins_with(compact_prefix)):
			_completion_candidates.append(suggestion_text)
			if _completion_candidates.size() >= limit:
				break
	_completion_selected_index = 0 if not prefix.is_empty() and not _completion_candidates.is_empty() else -1
	_refresh_completion_list()


func _refresh_completion_list() -> void:
	if _completion_list == null:
		return
	_completion_list.clear()
	for candidate in _completion_candidates:
		_completion_list.add_item(candidate)
	_completion_list.visible = _visible and not _completion_candidates.is_empty()
	_completion_list.deselect_all()
	if _completion_selected_index >= 0 and _completion_selected_index < _completion_candidates.size():
		_completion_list.select(_completion_selected_index)


func _move_completion_selection(direction: int) -> bool:
	if _input == null or _input.text.strip_edges().is_empty() or _completion_candidates.is_empty():
		return false
	if _completion_selected_index < 0:
		_completion_selected_index = 0 if direction >= 0 else _completion_candidates.size() - 1
	else:
		_completion_selected_index = wrapi(_completion_selected_index + direction, 0, _completion_candidates.size())
	var replacement := _selected_completion_text()
	if replacement.is_empty():
		return false
	_replace_input_text(replacement, true)
	_refresh_completion_list()
	return true


func _select_completion_index(index: int) -> void:
	_completion_selected_index = clampi(index, 0, max(0, _completion_candidates.size() - 1))
	var replacement := _selected_completion_text()
	if not replacement.is_empty() and _input != null:
		_replace_input_text(replacement, true)
	_refresh_completion_list()


func _activate_completion_index(index: int) -> void:
	_select_completion_index(index)
	_autocomplete_input()


func _complete_selected_if_needed() -> bool:
	var selected := _selected_completion_text()
	if _input == null or selected.is_empty():
		return false
	if _input.text.strip_edges() == selected:
		return false
	_set_input_text(selected)
	return true


func _selected_completion_text() -> String:
	if _completion_selected_index < 0 or _completion_selected_index >= _completion_candidates.size():
		return ""
	return _completion_candidates[_completion_selected_index]


func _set_input_text(value: String) -> void:
	_replace_input_text(value, false)


func _replace_input_text(value: String, preserve_completion_query: bool = false) -> void:
	if _input == null:
		return
	_suppress_completion_refresh = true
	_input.text = value
	_input.caret_column = _input.text.length()
	_suppress_completion_refresh = false
	if not preserve_completion_query:
		_completion_query_text = value
		if value.strip_edges().is_empty():
			_completion_candidates.clear()
			_completion_selected_index = -1
			_refresh_completion_list()
		else:
			_refresh_completions()
	else:
		_refresh_completion_list()


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


func _line(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	return label


func _console_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.07, 0.88)
	style.border_color = Color(0.25, 0.31, 0.34, 0.95)
	style.border_width_top = 1
	style.content_margin_left = 12
	style.content_margin_top = 8
	style.content_margin_right = 12
	style.content_margin_bottom = 0
	return style


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _completion_key(value: String) -> String:
	return value.replace(" ", "").replace("\t", "")
