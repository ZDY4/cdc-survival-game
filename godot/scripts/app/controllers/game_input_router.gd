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
		if _handle_trade_shortcut_key(game_root, event as InputEventKey):
			var trade_viewport := game_root.get_viewport()
			if trade_viewport != null:
				trade_viewport.set_input_as_handled()
			return
		if _handle_hotbar_shortcut_key(game_root, event as InputEventKey):
			var hotbar_viewport := game_root.get_viewport()
			if hotbar_viewport != null:
				hotbar_viewport.set_input_as_handled()
			return
		if _handle_dialogue_enter_key(game_root, event as InputEventKey):
			var enter_viewport := game_root.get_viewport()
			if enter_viewport != null:
				enter_viewport.set_input_as_handled()
			return
		if _handle_space_key(game_root, runtime_input_controller, event as InputEventKey):
			var space_viewport := game_root.get_viewport()
			if space_viewport != null:
				space_viewport.set_input_as_handled()
			return
		if _handle_global_shortcut_key(game_root, event as InputEventKey):
			var shortcut_viewport := game_root.get_viewport()
			if shortcut_viewport != null:
				shortcut_viewport.set_input_as_handled()
			return
		if _handle_camera_shortcut_key(game_root, runtime_input_controller, event as InputEventKey):
			var camera_viewport := game_root.get_viewport()
			if camera_viewport != null:
				camera_viewport.set_input_as_handled()
			return
	elif event is InputEventMouseMotion:
		if _handle_mouse_motion(game_root, runtime_input_controller, event as InputEventMouseMotion, true):
			return
	elif event is InputEventMouseButton:
		if _handle_mouse_button(game_root, runtime_input_controller, event as InputEventMouseButton, true):
			return
	if runtime_input_controller != null:
		runtime_input_controller.input(event)


func unhandled_input(game_root: Node, runtime_input_controller: RefCounted, event: InputEvent) -> void:
	if event is InputEventKey and _debug_console_open(game_root):
		return
	if event is InputEventKey and _handle_trade_shortcut_key(game_root, event as InputEventKey):
		return
	if event is InputEventKey and _handle_hotbar_shortcut_key(game_root, event as InputEventKey):
		return
	if event is InputEventKey and _handle_dialogue_enter_key(game_root, event as InputEventKey):
		return
	if event is InputEventKey and _handle_space_key(game_root, runtime_input_controller, event as InputEventKey):
		return
	if event is InputEventKey and _handle_global_shortcut_key(game_root, event as InputEventKey):
		return
	if event is InputEventKey and _handle_camera_shortcut_key(game_root, runtime_input_controller, event as InputEventKey):
		return
	if event is InputEventMouseMotion and _handle_mouse_motion(game_root, runtime_input_controller, event as InputEventMouseMotion, false):
		return
	if event is InputEventMouseButton and _handle_mouse_button(game_root, runtime_input_controller, event as InputEventMouseButton, false):
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
	var stage_panel := _stage_panel_for_key(key)
	if not stage_panel.is_empty():
		if game_root.has_method("toggle_stage_panel"):
			game_root.toggle_stage_panel(stage_panel)
		return true
	return false


func _handle_trade_shortcut_key(game_root: Node, event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	return game_root.has_method("handle_trade_shortcut") and bool(game_root.handle_trade_shortcut(event))


func _handle_hotbar_shortcut_key(game_root: Node, event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	var key := event.keycode
	if key == 0:
		key = event.physical_keycode
	var digit := _digit_for_key(key)
	if digit < 0:
		return false
	if digit >= 1 and event.alt_pressed:
		return _handle_hotbar_group_key(game_root, digit)
	if key == KEY_0 and event.ctrl_pressed:
		return false
	return _handle_digit_key(game_root, digit)


func _handle_dialogue_enter_key(game_root: Node, event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	var key := event.keycode
	if key == 0:
		key = event.physical_keycode
	if key != KEY_ENTER and key != KEY_KP_ENTER:
		return false
	if game_root.has_method("has_active_dialogue") and bool(game_root.has_active_dialogue()) and game_root.has_method("press_enter_action"):
		game_root.press_enter_action()
		return true
	return false


func _handle_space_key(game_root: Node, runtime_input_controller: RefCounted, event: InputEventKey) -> bool:
	var key := event.keycode
	if key == 0:
		key = event.physical_keycode
	if key != KEY_SPACE:
		return false
	if not event.pressed:
		if runtime_input_controller != null and runtime_input_controller.has_method("stop_space_wait_hold"):
			runtime_input_controller.call("stop_space_wait_hold")
		return false
	if event.echo:
		return false
	if runtime_input_controller != null and runtime_input_controller.has_method("handle_space_key_pressed"):
		return bool(runtime_input_controller.call("handle_space_key_pressed"))
	return false


func _handle_camera_shortcut_key(game_root: Node, runtime_input_controller: RefCounted, event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	var key := event.keycode
	if key == 0:
		key = event.physical_keycode
	if key == KEY_EQUAL or key == KEY_PLUS:
		if runtime_input_controller != null and runtime_input_controller.has_method("scale_camera_zoom"):
			runtime_input_controller.call("scale_camera_zoom", 1.2)
			return true
	elif key == KEY_MINUS:
		if runtime_input_controller != null and runtime_input_controller.has_method("scale_camera_zoom"):
			runtime_input_controller.call("scale_camera_zoom", 1.0 / 1.2)
			return true
	elif key == KEY_0 and event.ctrl_pressed:
		if runtime_input_controller != null and runtime_input_controller.has_method("reset_camera_zoom"):
			runtime_input_controller.call("reset_camera_zoom")
			return true
	elif key == KEY_F:
		if runtime_input_controller != null and runtime_input_controller.has_method("focus_current_actor"):
			runtime_input_controller.call("focus_current_actor")
			return true
	elif key == KEY_TAB:
		if game_root.has_method("cycle_focused_actor"):
			game_root.cycle_focused_actor()
			return true
	elif key == KEY_PAGEUP:
		if game_root.has_method("change_observed_level"):
			game_root.change_observed_level(1)
			return true
	elif key == KEY_PAGEDOWN:
		if game_root.has_method("change_observed_level"):
			game_root.change_observed_level(-1)
			return true
	return false


func _handle_mouse_motion(game_root: Node, runtime_input_controller: RefCounted, event: InputEventMouseMotion, respect_mouse_blocker: bool) -> bool:
	if runtime_input_controller == null:
		return false
	if _gameplay_input_blocked(game_root):
		return true
	if respect_mouse_blocker and runtime_input_controller.has_method("mouse_over_blocking_ui") and bool(runtime_input_controller.call("mouse_over_blocking_ui")):
		return true
	if runtime_input_controller.has_method("handle_world_mouse_motion"):
		runtime_input_controller.call("handle_world_mouse_motion", event)
		return true
	return false


func _handle_mouse_button(game_root: Node, runtime_input_controller: RefCounted, event: InputEventMouseButton, respect_mouse_blocker: bool) -> bool:
	if runtime_input_controller == null:
		return false
	if runtime_input_controller.has_method("close_context_menu_on_outside_click") and bool(runtime_input_controller.call("close_context_menu_on_outside_click", event)):
		_mark_input_handled(game_root)
		return true
	if _gameplay_input_blocked(game_root):
		return true
	if respect_mouse_blocker and runtime_input_controller.has_method("mouse_over_blocking_ui") and bool(runtime_input_controller.call("mouse_over_blocking_ui")):
		return true
	if runtime_input_controller.has_method("handle_world_mouse_button") and bool(runtime_input_controller.call("handle_world_mouse_button", event)):
		_mark_input_handled(game_root)
		return true
	return false


func _handle_digit_key(game_root: Node, digit: int) -> bool:
	if digit <= 0:
		return false
	if game_root.has_method("has_active_dialogue") and bool(game_root.has_active_dialogue()):
		if digit <= 9 and game_root.has_method("choose_dialogue_option_by_index"):
			game_root.choose_dialogue_option_by_index(digit - 1)
			return true
		return false
	if _observe_mode_active(game_root):
		return true
	if _gameplay_input_blocked(game_root):
		return false
	if game_root.has_method("use_hotbar_slot"):
		var slot_id := "slot_%d" % (10 if digit == 10 else digit)
		game_root.use_hotbar_slot(slot_id)
		return true
	return false


func _handle_hotbar_group_key(game_root: Node, digit: int) -> bool:
	if digit < 1 or digit > 3:
		return false
	if game_root.has_method("has_active_dialogue") and bool(game_root.has_active_dialogue()):
		return false
	if _observe_mode_active(game_root):
		return true
	if _gameplay_input_blocked(game_root):
		return false
	if game_root.has_method("set_hotbar_group"):
		game_root.set_hotbar_group("group_%d" % digit)
		return true
	return false


func _digit_for_key(key: int) -> int:
	match key:
		KEY_1:
			return 1
		KEY_2:
			return 2
		KEY_3:
			return 3
		KEY_4:
			return 4
		KEY_5:
			return 5
		KEY_6:
			return 6
		KEY_7:
			return 7
		KEY_8:
			return 8
		KEY_9:
			return 9
		KEY_0:
			return 10
		_:
			return -1


func _observe_mode_active(game_root: Node) -> bool:
	return game_root.has_method("is_observe_mode_enabled") and bool(game_root.is_observe_mode_enabled())


func _gameplay_input_blocked(game_root: Node) -> bool:
	return game_root.has_method("gameplay_input_blocked_by_ui") and bool(game_root.gameplay_input_blocked_by_ui())


func _debug_console_open(game_root: Node) -> bool:
	return game_root.has_method("is_debug_console_open") and bool(game_root.is_debug_console_open())


func _mark_input_handled(game_root: Node) -> void:
	var viewport := game_root.get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _stage_panel_for_key(key: int) -> String:
	var bindings := _stage_panel_keybindings()
	for panel_id in bindings.keys():
		if int(bindings[panel_id]) == key:
			return str(panel_id)
	return ""


func _stage_panel_keybindings() -> Dictionary:
	match str(ProjectSettings.get_setting("cdc/keybinding_profile", "default")):
		"left_handed":
			return {
				"inventory": KEY_Q,
				"character": KEY_E,
				"journal": KEY_R,
				"map": KEY_T,
				"skills": KEY_Y,
				"crafting": KEY_U,
			}
		_:
			return {
				"inventory": KEY_I,
				"character": KEY_C,
				"journal": KEY_J,
				"map": KEY_M,
				"skills": KEY_K,
				"crafting": KEY_L,
			}
