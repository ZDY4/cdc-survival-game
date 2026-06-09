extends RefCounted


func input(game_root: Node, runtime_input_controller: RefCounted, event: InputEvent) -> void:
	if event is InputEventKey:
		if _handle_debug_console_key(game_root, event as InputEventKey):
			var viewport := game_root.get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
			return
		if _debug_console_open(game_root):
			return
	if runtime_input_controller != null:
		runtime_input_controller.input(event)


func unhandled_input(game_root: Node, runtime_input_controller: RefCounted, event: InputEvent) -> void:
	if event is InputEventKey and _debug_console_open(game_root):
		return
	if runtime_input_controller != null:
		runtime_input_controller.unhandled_input(event)


func _handle_debug_console_key(game_root: Node, event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	var key := event.keycode
	if key == 0:
		key = event.physical_keycode
	if key == KEY_QUOTELEFT:
		if game_root.has_method("toggle_debug_console"):
			game_root.toggle_debug_console()
		return true
	if _debug_console_open(game_root) and key == KEY_ESCAPE:
		if game_root.has_method("close_debug_console"):
			game_root.close_debug_console()
			return true
		if game_root.has_method("close_active_ui"):
			game_root.close_active_ui("keyboard_escape")
			return true
	return false


func _debug_console_open(game_root: Node) -> bool:
	return game_root.has_method("is_debug_console_open") and bool(game_root.is_debug_console_open())
