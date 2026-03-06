extends BaseModule
## Global debug manager with runtime console.

# 1. Constants
const MODULE_NAME: String = "DebugModule"
const CONSOLE_HEIGHT: float = 240.0
const MAX_LOG_LINES: int = 200

# 2. Signals
signal command_executed(command_name: String, success: bool, result: Dictionary)

# 3. Public variables
var module_registry: Dictionary = {}
var command_registry: Dictionary = {}
var variable_registry: Dictionary = {}
var panel_registry: Dictionary = {}

# 4. Private variables
var _active_panels: Dictionary = {}
var _console_layer: Control = null
var _console_panel: PanelContainer = null
var _output_log: RichTextLabel = null
var _input_line: LineEdit = null
var _is_console_visible: bool = false
var _log_lines: Array[String] = []
var _command_history: Array[String] = []
var _history_index: int = -1

# 5. Public methods
func _ready() -> void:
	super._ready()
	set_process_input(true)
	register_module("debug", {"description": "Runtime debug manager"})
	_register_builtin_commands()
	call_deferred("_setup_console_ui")

func _exit_tree() -> void:
	_cleanup_console_ui()
	_active_panels.clear()

func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null:
		return
	if not key_event.pressed or key_event.echo:
		return

	if _is_toggle_console_key(key_event):
		_set_console_visible(not _is_console_visible)
		if get_viewport():
			get_viewport().set_input_as_handled()
		return

	if _is_console_visible and key_event.keycode == KEY_ESCAPE:
		_set_console_visible(false)
		if get_viewport():
			get_viewport().set_input_as_handled()

func register_module(module_name: String, metadata: Dictionary = {}) -> void:
	var normalized_name := _normalize_name(module_name)
	if normalized_name.is_empty():
		return

	_ensure_module_entry(normalized_name)
	var module_entry: Dictionary = module_registry[normalized_name]
	module_entry["metadata"] = metadata.duplicate(true)
	module_registry[normalized_name] = module_entry

func unregister_module(module_name: String) -> void:
	var normalized_name := _normalize_name(module_name)
	if not module_registry.has(normalized_name):
		return

	var module_entry: Dictionary = module_registry[normalized_name]
	var commands: Array = module_entry.get("commands", [])
	for command_name in commands:
		command_registry.erase(command_name)

	var variables: Array = module_entry.get("variables", [])
	for variable_name in variables:
		variable_registry.erase(variable_name)

	var panels: Array = module_entry.get("panels", [])
	for panel_name in panels:
		panel_registry.erase(panel_name)
		close_panel(str(panel_name))

	module_registry.erase(normalized_name)

func register_command(
	module_name: String,
	command_name: String,
	handler: Callable,
	description: String = "",
	usage: String = ""
) -> bool:
	var normalized_module := _normalize_name(module_name)
	var normalized_command := _normalize_name(command_name)
	if normalized_module.is_empty() or normalized_command.is_empty():
		return false
	if not handler.is_valid():
		push_error("[DebugModule] Invalid command handler: " + normalized_command)
		return false

	_ensure_module_entry(normalized_module)
	command_registry[normalized_command] = {
		"module": normalized_module,
		"handler": handler,
		"description": description,
		"usage": usage
	}
	_append_module_ref(normalized_module, "commands", normalized_command)
	return true

func unregister_command(command_name: String) -> void:
	var normalized_command := _normalize_name(command_name)
	if not command_registry.has(normalized_command):
		return

	var entry: Dictionary = command_registry[normalized_command]
	var module_name := str(entry.get("module", ""))
	command_registry.erase(normalized_command)
	_remove_module_ref(module_name, "commands", normalized_command)

func register_variable(
	module_name: String,
	variable_name: String,
	getter: Callable,
	setter: Callable = Callable(),
	description: String = ""
) -> bool:
	var normalized_module := _normalize_name(module_name)
	var normalized_variable := _normalize_name(variable_name)
	if normalized_module.is_empty() or normalized_variable.is_empty():
		return false
	if not getter.is_valid():
		push_error("[DebugModule] Invalid variable getter: " + normalized_variable)
		return false

	_ensure_module_entry(normalized_module)
	variable_registry[normalized_variable] = {
		"module": normalized_module,
		"getter": getter,
		"setter": setter,
		"description": description
	}
	_append_module_ref(normalized_module, "variables", normalized_variable)
	return true

func unregister_variable(variable_name: String) -> void:
	var normalized_variable := _normalize_name(variable_name)
	if not variable_registry.has(normalized_variable):
		return

	var entry: Dictionary = variable_registry[normalized_variable]
	var module_name := str(entry.get("module", ""))
	variable_registry.erase(normalized_variable)
	_remove_module_ref(module_name, "variables", normalized_variable)

func register_panel(
	module_name: String,
	panel_name: String,
	panel_builder: Callable,
	description: String = ""
) -> bool:
	var normalized_module := _normalize_name(module_name)
	var normalized_panel := _normalize_name(panel_name)
	if normalized_module.is_empty() or normalized_panel.is_empty():
		return false
	if not panel_builder.is_valid():
		push_error("[DebugModule] Invalid panel builder: " + normalized_panel)
		return false

	_ensure_module_entry(normalized_module)
	panel_registry[normalized_panel] = {
		"module": normalized_module,
		"builder": panel_builder,
		"description": description
	}
	_append_module_ref(normalized_module, "panels", normalized_panel)
	return true

func unregister_panel(panel_name: String) -> void:
	var normalized_panel := _normalize_name(panel_name)
	if not panel_registry.has(normalized_panel):
		return

	var entry: Dictionary = panel_registry[normalized_panel]
	var module_name := str(entry.get("module", ""))
	panel_registry.erase(normalized_panel)
	close_panel(normalized_panel)
	_remove_module_ref(module_name, "panels", normalized_panel)

func execute_command(raw_command: String) -> Dictionary:
	var tokens: Array[String] = _tokenize_command(raw_command)
	if tokens.is_empty():
		return {"success": false, "error": "Empty command"}

	var command_name := _normalize_name(tokens[0])
	var args: Array[String] = []
	for i in range(1, tokens.size()):
		args.append(tokens[i])

	if not command_registry.has(command_name):
		return {"success": false, "error": "Unknown command: " + command_name}

	var entry: Dictionary = command_registry[command_name]
	var handler: Callable = entry.get("handler", Callable())
	if not handler.is_valid():
		return {"success": false, "error": "Command handler unavailable: " + command_name}

	var raw_result: Variant = handler.call(args)
	var result := _normalize_command_result(command_name, raw_result)
	command_executed.emit(command_name, bool(result.get("success", false)), result)
	return result

func get_debug_variable(variable_name: String) -> Dictionary:
	var normalized_variable := _normalize_name(variable_name)
	if not variable_registry.has(normalized_variable):
		return {"success": false, "error": "Unknown variable: " + normalized_variable}

	var entry: Dictionary = variable_registry[normalized_variable]
	var getter: Callable = entry.get("getter", Callable())
	if not getter.is_valid():
		return {"success": false, "error": "Variable getter unavailable: " + normalized_variable}

	return {
		"success": true,
		"name": normalized_variable,
		"value": getter.call()
	}

func set_debug_variable(variable_name: String, raw_value: String) -> Dictionary:
	var normalized_variable := _normalize_name(variable_name)
	if not variable_registry.has(normalized_variable):
		return {"success": false, "error": "Unknown variable: " + normalized_variable}

	var entry: Dictionary = variable_registry[normalized_variable]
	var setter: Callable = entry.get("setter", Callable())
	if not setter.is_valid():
		return {"success": false, "error": "Variable is read-only: " + normalized_variable}

	var parsed_value: Variant = _parse_string_value(raw_value)
	setter.call(parsed_value)

	var refreshed_value: Variant = parsed_value
	var getter: Callable = entry.get("getter", Callable())
	if getter.is_valid():
		refreshed_value = getter.call()

	return {
		"success": true,
		"name": normalized_variable,
		"value": refreshed_value
	}

func open_panel(panel_name: String) -> Dictionary:
	var normalized_panel := _normalize_name(panel_name)
	var error := ""
	var success_message := ""

	if normalized_panel.is_empty():
		error = "Panel name is required"
	elif _active_panels.has(normalized_panel):
		success_message = "Panel already open: " + normalized_panel
	elif not panel_registry.has(normalized_panel):
		error = "Unknown panel: " + normalized_panel
	else:
		var entry: Dictionary = panel_registry[normalized_panel]
		var builder: Callable = entry.get("builder", Callable())
		if not builder.is_valid():
			error = "Panel builder unavailable: " + normalized_panel
		else:
			var panel_result: Variant = builder.call()
			var panel_control := panel_result as Control
			if panel_control == null:
				error = "Panel builder must return Control: " + normalized_panel
			else:
				if _console_layer == null or not is_instance_valid(_console_layer):
					_setup_console_ui()
				if _console_layer == null:
					error = "Console layer unavailable"
				else:
					_console_layer.add_child(panel_control)
					_active_panels[normalized_panel] = panel_control
					success_message = "Panel opened: " + normalized_panel

	if not error.is_empty():
		return {"success": false, "error": error}
	return {"success": true, "message": success_message}

func close_panel(panel_name: String) -> Dictionary:
	var normalized_panel := _normalize_name(panel_name)
	if not _active_panels.has(normalized_panel):
		return {"success": false, "error": "Panel not open: " + normalized_panel}

	var panel_control: Control = _active_panels[normalized_panel]
	if panel_control and is_instance_valid(panel_control):
		panel_control.queue_free()
	_active_panels.erase(normalized_panel)
	return {"success": true, "message": "Panel closed: " + normalized_panel}

func log_message(message: String, is_error: bool = false) -> void:
	var line := "[Error] " + message if is_error else message
	_append_log_line(line)

# 6. Private methods
func _setup_console_ui() -> void:
	if not get_tree() or not get_tree().root:
		return
	if _console_layer and is_instance_valid(_console_layer):
		return

	_console_layer = Control.new()
	_console_layer.name = "DebugConsoleLayer"
	_console_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_console_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(_console_layer)

	_console_panel = PanelContainer.new()
	_console_panel.name = "DebugConsolePanel"
	_console_panel.anchor_left = 0.0
	_console_panel.anchor_top = 1.0
	_console_panel.anchor_right = 1.0
	_console_panel.anchor_bottom = 1.0
	_console_panel.offset_left = 0.0
	_console_panel.offset_top = -CONSOLE_HEIGHT
	_console_panel.offset_right = 0.0
	_console_panel.offset_bottom = 0.0
	_console_panel.visible = false
	_console_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_console_layer.add_child(_console_panel)

	var layout := VBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_console_panel.add_child(layout)

	_output_log = RichTextLabel.new()
	_output_log.selection_enabled = true
	_output_log.fit_content = false
	_output_log.scroll_following = true
	_output_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_output_log)

	var input_row := HBoxContainer.new()
	layout.add_child(input_row)

	var prompt := Label.new()
	prompt.text = ">"
	input_row.add_child(prompt)

	_input_line = LineEdit.new()
	_input_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_line.placeholder_text = "Type command and press Enter (help)"
	_input_line.text_submitted.connect(_on_command_submitted)
	_input_line.gui_input.connect(_on_input_line_gui_input)
	input_row.add_child(_input_line)

	_append_log_line("[Debug] Console ready. Press ` to toggle.")

func _cleanup_console_ui() -> void:
	if _console_layer and is_instance_valid(_console_layer):
		_console_layer.queue_free()
	_console_layer = null
	_console_panel = null
	_output_log = null
	_input_line = null

func _set_console_visible(visible: bool) -> void:
	_is_console_visible = visible
	if _console_panel and is_instance_valid(_console_panel):
		_console_panel.visible = _is_console_visible

	if _is_console_visible and _input_line and is_instance_valid(_input_line):
		_input_line.grab_focus()
		_input_line.caret_column = _input_line.text.length()
	elif _input_line and is_instance_valid(_input_line):
		_input_line.release_focus()

func _on_command_submitted(command_text: String) -> void:
	var normalized_command := command_text.strip_edges()
	if normalized_command.is_empty():
		return

	_command_history.append(normalized_command)
	_history_index = _command_history.size()
	_append_log_line("> " + normalized_command)

	var result: Dictionary = execute_command(normalized_command)
	if bool(result.get("success", false)):
		var message := str(result.get("message", ""))
		if not message.is_empty():
			_append_log_line(message)
	else:
		var error_text := str(result.get("error", "Command failed"))
		_append_log_line("[Error] " + error_text)

	if _input_line and is_instance_valid(_input_line):
		_input_line.clear()

func _on_input_line_gui_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null:
		return
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_UP:
		_move_history_cursor(-1)
		_input_line.accept_event()
	elif key_event.keycode == KEY_DOWN:
		_move_history_cursor(1)
		_input_line.accept_event()

func _move_history_cursor(direction: int) -> void:
	if _command_history.is_empty():
		return
	if _input_line == null or not is_instance_valid(_input_line):
		return

	var max_index := _command_history.size()
	_history_index = clampi(_history_index + direction, 0, max_index)
	if _history_index == max_index:
		_input_line.text = ""
		return

	_input_line.text = _command_history[_history_index]
	_input_line.caret_column = _input_line.text.length()

func _append_log_line(line: String) -> void:
	var lines: Array[String] = line.split("\n", false)
	for split_line in lines:
		_log_lines.append(split_line)

	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)

	_refresh_log_view()

func _refresh_log_view() -> void:
	if _output_log == null or not is_instance_valid(_output_log):
		return

	_output_log.text = "\n".join(_log_lines)
	if _log_lines.size() > 0:
		_output_log.scroll_to_line(_log_lines.size() - 1)

func _is_toggle_console_key(event: InputEventKey) -> bool:
	return event.keycode == KEY_QUOTELEFT or event.physical_keycode == KEY_QUOTELEFT

func _normalize_name(raw_name: String) -> String:
	return raw_name.strip_edges().to_lower()

func _ensure_module_entry(module_name: String) -> void:
	if module_registry.has(module_name):
		return
	module_registry[module_name] = {
		"metadata": {},
		"commands": [],
		"variables": [],
		"panels": []
	}

func _append_module_ref(module_name: String, field_name: String, value: String) -> void:
	if not module_registry.has(module_name):
		return

	var entry: Dictionary = module_registry[module_name]
	var refs: Array = entry.get(field_name, [])
	if not refs.has(value):
		refs.append(value)
	entry[field_name] = refs
	module_registry[module_name] = entry

func _remove_module_ref(module_name: String, field_name: String, value: String) -> void:
	if module_name.is_empty() or not module_registry.has(module_name):
		return

	var entry: Dictionary = module_registry[module_name]
	var refs: Array = entry.get(field_name, [])
	refs.erase(value)
	entry[field_name] = refs
	module_registry[module_name] = entry

func _tokenize_command(raw_command: String) -> Array[String]:
	var parts: Array[String] = []
	for part in raw_command.split(" ", false):
		var token := str(part).strip_edges()
		if not token.is_empty():
			parts.append(token)
	return parts

func _normalize_command_result(command_name: String, raw_result: Variant) -> Dictionary:
	if raw_result is Dictionary:
		var result := raw_result.duplicate(true)
		if not result.has("success"):
			result["success"] = true
		if not result.has("message") and not result.has("error"):
			result["message"] = ""
		return result

	if raw_result is bool:
		var success := bool(raw_result)
		return {
			"success": success,
			"message": "OK" if success else "",
			"error": "" if success else "Command failed: " + command_name
		}

	if raw_result == null:
		return {"success": true, "message": ""}

	return {"success": true, "message": str(raw_result)}

func _parse_string_value(raw_value: String) -> Variant:
	var lower := raw_value.to_lower()
	if lower in ["true", "on", "yes", "1"]:
		return true
	if lower in ["false", "off", "no", "0"]:
		return false
	if raw_value.is_valid_int():
		return int(raw_value)
	if raw_value.is_valid_float():
		return float(raw_value)
	return raw_value

func _register_builtin_commands() -> void:
	register_command(
		"debug",
		"help",
		Callable(self, "_cmd_help"),
		"List available commands",
		"help"
	)
	register_command(
		"debug",
		"clear",
		Callable(self, "_cmd_clear"),
		"Clear console output",
		"clear"
	)
	register_command(
		"debug",
		"modules",
		Callable(self, "_cmd_modules"),
		"List registered debug modules",
		"modules"
	)
	register_command(
		"debug",
		"vars",
		Callable(self, "_cmd_vars"),
		"List registered debug variables",
		"vars"
	)
	register_command(
		"debug",
		"get",
		Callable(self, "_cmd_get"),
		"Read a debug variable",
		"get <variable>"
	)
	register_command(
		"debug",
		"set",
		Callable(self, "_cmd_set"),
		"Write a debug variable",
		"set <variable> <value>"
	)
	register_command(
		"debug",
		"panel",
		Callable(self, "_cmd_panel"),
		"Open/close/list debug panels",
		"panel <open|close|list> [name]"
	)

func _cmd_help(_args: Array[String]) -> Dictionary:
	var lines: Array[String] = ["Commands:"]
	var names: Array = command_registry.keys()
	names.sort()

	for command_name in names:
		var entry: Dictionary = command_registry[command_name]
		var usage := str(entry.get("usage", command_name))
		var description := str(entry.get("description", ""))
		var line := usage
		if not description.is_empty():
			line += " - " + description
		lines.append(line)

	return {"success": true, "message": "\n".join(lines)}

func _cmd_clear(_args: Array[String]) -> Dictionary:
	_log_lines.clear()
	_refresh_log_view()
	return {"success": true, "message": ""}

func _cmd_modules(_args: Array[String]) -> Dictionary:
	var names: Array = module_registry.keys()
	names.sort()
	if names.is_empty():
		return {"success": true, "message": "No modules registered"}

	var lines: Array[String] = []
	for module_name in names:
		var entry: Dictionary = module_registry[module_name]
		var commands: Array = entry.get("commands", [])
		var variables: Array = entry.get("variables", [])
		var panels: Array = entry.get("panels", [])
		lines.append(
			"%s (commands=%d, vars=%d, panels=%d)"
			% [module_name, commands.size(), variables.size(), panels.size()]
		)

	return {"success": true, "message": "\n".join(lines)}

func _cmd_vars(_args: Array[String]) -> Dictionary:
	var names: Array = variable_registry.keys()
	names.sort()
	if names.is_empty():
		return {"success": true, "message": "No variables registered"}

	var lines: Array[String] = []
	for variable_name in names:
		var read_result: Dictionary = get_debug_variable(variable_name)
		if bool(read_result.get("success", false)):
			lines.append("%s = %s" % [variable_name, str(read_result.get("value"))])
		else:
			lines.append("%s = <error>" % variable_name)

	return {"success": true, "message": "\n".join(lines)}

func _cmd_get(args: Array[String]) -> Dictionary:
	if args.is_empty():
		return {"success": false, "error": "Usage: get <variable>"}

	var result: Dictionary = get_debug_variable(args[0])
	if not bool(result.get("success", false)):
		return result

	return {
		"success": true,
		"message": "%s = %s" % [result.get("name"), str(result.get("value"))]
	}

func _cmd_set(args: Array[String]) -> Dictionary:
	if args.size() < 2:
		return {"success": false, "error": "Usage: set <variable> <value>"}

	var variable_name := args[0]
	var value_parts: Array[String] = []
	for i in range(1, args.size()):
		value_parts.append(args[i])
	var raw_value := " ".join(value_parts)
	var result: Dictionary = set_debug_variable(variable_name, raw_value)
	if not bool(result.get("success", false)):
		return result

	return {
		"success": true,
		"message": "%s = %s" % [result.get("name"), str(result.get("value"))]
	}

func _cmd_panel(args: Array[String]) -> Dictionary:
	var result := {"success": false, "error": "Usage: panel <open|close|list> [name]"}
	if args.is_empty():
		return result

	var action := args[0].to_lower()
	if action == "list":
		var names: Array = panel_registry.keys()
		names.sort()
		if names.is_empty():
			result = {"success": true, "message": "No panels registered"}
		else:
			var formatted_names: Array[String] = []
			for panel_name in names:
				formatted_names.append(str(panel_name))
			result = {"success": true, "message": "Panels: " + ", ".join(formatted_names)}
	elif action == "open":
		if args.size() < 2:
			result = {"success": false, "error": "Usage: panel open <name>"}
		else:
			result = open_panel(args[1])
	elif action == "close":
		if args.size() < 2:
			result = {"success": false, "error": "Usage: panel close <name>"}
		else:
			result = close_panel(args[1])
	else:
		result = {"success": false, "error": "Unknown panel action: " + action}

	return result
