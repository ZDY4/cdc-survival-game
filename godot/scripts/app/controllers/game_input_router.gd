extends RefCounted


func process(runtime_input_controller: RefCounted, delta: float) -> void:
	if runtime_input_controller != null:
		runtime_input_controller.process(delta)


func input(game_root: Node, runtime_input_controller: RefCounted, event: InputEvent) -> void:
	if event is InputEventKey:
		if _handle_debug_console_key(game_root, event as InputEventKey):
			var viewport := game_root.get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
			return
		if _debug_console_open(game_root):
			return
		if _handle_global_shortcut_key(game_root, event as InputEventKey):
			var shortcut_viewport := game_root.get_viewport()
			if shortcut_viewport != null:
				shortcut_viewport.set_input_as_handled()
			return
	if runtime_input_controller != null:
		runtime_input_controller.input(event)


func unhandled_input(game_root: Node, runtime_input_controller: RefCounted, event: InputEvent) -> void:
	if event is InputEventKey and _debug_console_open(game_root):
		return
	if event is InputEventKey and _handle_global_shortcut_key(game_root, event as InputEventKey):
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


func _handle_global_shortcut_key(game_root: Node, event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	var key := event.keycode
	if key == 0:
		key = event.physical_keycode
	match key:
		KEY_V:
			if game_root.has_method("cycle_debug_overlay_mode"):
				game_root.cycle_debug_overlay_mode()
			return true
		KEY_F3:
			if game_root.has_method("toggle_debug_panel"):
				game_root.toggle_debug_panel()
			return true
		KEY_BRACKETLEFT:
			if game_root.has_method("cycle_info_panel"):
				game_root.cycle_info_panel(-1)
			return true
		KEY_BRACKETRIGHT:
			if game_root.has_method("cycle_info_panel"):
				game_root.cycle_info_panel(1)
			return true
		KEY_A:
			if game_root.has_method("toggle_auto_tick"):
				game_root.toggle_auto_tick()
			return true
		KEY_SLASH:
			if game_root.has_method("toggle_controls_hint"):
				game_root.toggle_controls_hint()
			return true
		KEY_ESCAPE:
			if game_root.has_method("close_active_ui"):
				game_root.close_active_ui("keyboard_escape")
			return true
	return false


func _debug_console_open(game_root: Node) -> bool:
	return game_root.has_method("is_debug_console_open") and bool(game_root.is_debug_console_open())
