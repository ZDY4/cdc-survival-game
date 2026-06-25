extends RefCounted

const WorldInteractionPicker = preload("res://scripts/app/controllers/runtime_input/world_interaction_picker.gd")
const RuntimeMarkerController = preload("res://scripts/app/controllers/runtime_input/runtime_marker_controller.gd")
const HoverStateController = preload("res://scripts/app/controllers/runtime_input/hover_state_controller.gd")
const CameraInputController = preload("res://scripts/app/controllers/runtime_input/camera_input_controller.gd")
const SpaceWaitHoldController = preload("res://scripts/app/controllers/runtime_input/space_wait_hold_controller.gd")

const GRID_SIZE := 1.0
const BEVY_LEVEL_PLANE_HEIGHT := GRID_SIZE * 0.5
const BEVY_DRAG_PLANE_HEIGHT := 0.11

var game_root: Node
var world_container: Node3D
var world_result: Dictionary = {}
var camera: Camera3D
var camera_input_controller: RefCounted = CameraInputController.new()
var world_interaction_picker: RefCounted = WorldInteractionPicker.new()
var runtime_marker_controller: RefCounted = RuntimeMarkerController.new()
var hover_state_controller: RefCounted = HoverStateController.new()
var space_wait_hold_controller: RefCounted = SpaceWaitHoldController.new()
var hover_cursor: MeshInstance3D
var hover_target_outline: MeshInstance3D
var attack_target_marker: MeshInstance3D
var attack_target_outline: MeshInstance3D
var attack_range_markers: Node3D
var skill_target_preview_markers: Node3D
var move_path_preview_markers: Node3D
var selected_node: Node
var hover_refresh_requested := false
var last_selection_clear_result: Dictionary = {}
var cached_player_actor_id := 0
var last_hover_screen_position := Vector2(-1000000.0, -1000000.0)


func _init(p_game_root: Node) -> void:
	game_root = p_game_root
	runtime_marker_controller.attach(game_root)
	hover_cursor = runtime_marker_controller.get("hover_cursor") as MeshInstance3D
	hover_target_outline = runtime_marker_controller.get("hover_target_outline") as MeshInstance3D
	attack_target_marker = runtime_marker_controller.get("attack_target_marker") as MeshInstance3D
	attack_target_outline = runtime_marker_controller.get("attack_target_outline") as MeshInstance3D
	attack_range_markers = runtime_marker_controller.get("attack_range_markers") as Node3D
	skill_target_preview_markers = runtime_marker_controller.get("skill_target_preview_markers") as Node3D
	move_path_preview_markers = runtime_marker_controller.get("move_path_preview_markers") as Node3D


func attach_world(p_world_container: Node3D, p_world_result: Dictionary) -> void:
	world_container = p_world_container
	world_result = p_world_result
	cached_player_actor_id = _player_actor_id_from_world_result()
	last_hover_screen_position = Vector2(-1000000.0, -1000000.0)
	camera = _find_world_camera()
	if camera == null:
		push_warning("运行时输入控制器找不到 WorldCamera，鼠标拾取和相机移动暂不可用")
		return
	camera_input_controller.attach(camera, _focused_actor_position(), _map_size(), _viewport_size(), _level_plane_height())
	runtime_marker_controller.reset_for_world()
	_clear_selection_only()
	_set_hover_failure("world_changed")
	_request_hover_refresh()
	selected_node = null


func process(delta: float) -> void:
	if camera == null:
		return
	_process_space_wait_hold(delta)
	var follow_target: Dictionary = _focused_actor_follow_target()
	_process_camera_follow_target(follow_target)
	if hover_refresh_requested and not camera_input_controller.is_dragging() and _mouse_inside_viewport():
		hover_refresh_requested = false
		update_hover_at_screen_position(game_root.get_viewport().get_mouse_position())
	_sync_move_path_preview_with_active_movement()


func input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventKey:
		if _handle_camera_key(event as InputEventKey):
			var key_viewport := game_root.get_viewport()
			if key_viewport != null:
				key_viewport.set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _mouse_motion_blocked_by_ui():
			return
		handle_world_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if close_context_menu_on_outside_click(mouse_button):
			var menu_viewport := game_root.get_viewport()
			if menu_viewport != null:
				menu_viewport.set_input_as_handled()
			return
		if _blocked_camera_drag_button_allowed(mouse_button):
			if handle_world_mouse_button(mouse_button):
				var blocked_drag_viewport := game_root.get_viewport()
				if blocked_drag_viewport != null:
					blocked_drag_viewport.set_input_as_handled()
			return
		if _gameplay_input_blocked_by_ui() or _mouse_over_blocking_ui():
			return
		if handle_world_mouse_button(mouse_button):
			var viewport := game_root.get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()


func unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventKey:
		_handle_camera_key(event as InputEventKey)
	elif event is InputEventMouseMotion:
		if _mouse_motion_blocked_by_ui():
			return
		handle_world_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if close_context_menu_on_outside_click(mouse_button):
			return
		if _blocked_camera_drag_button_allowed(mouse_button):
			handle_world_mouse_button(mouse_button)
			return
		if _gameplay_input_blocked_by_ui():
			return
		handle_world_mouse_button(mouse_button)


func mouse_over_blocking_ui() -> bool:
	return _mouse_over_blocking_ui()


func camera_drag_active() -> bool:
	return camera_input_controller.is_dragging()


func camera_drag_allowed_while_gameplay_blocked() -> bool:
	return _camera_drag_allowed_by_action_blocker()


func close_context_menu_on_outside_click(mouse_event: InputEventMouseButton) -> bool:
	return _close_context_menu_on_outside_click(mouse_event)


func handle_world_mouse_motion(mouse_event: InputEventMouseMotion) -> void:
	if camera == null:
		return
	_handle_mouse_motion(mouse_event)


func handle_world_mouse_button(mouse_event: InputEventMouseButton) -> bool:
	if camera == null:
		return false
	return _handle_mouse_button(mouse_event)


func _handle_mouse_motion(mouse_event: InputEventMouseMotion) -> void:
	if camera_input_controller.is_dragging():
		_drag_camera_to_screen_position(mouse_event.position)
	else:
		if mouse_event.position == last_hover_screen_position:
			return
		update_hover_at_screen_position(mouse_event.position)


func _handle_mouse_button(mouse_event: InputEventMouseButton) -> bool:
	if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
		camera_input_controller.set_dragging(mouse_event.pressed)
		if mouse_event.pressed:
			_begin_camera_drag(mouse_event.position)
		else:
			camera_input_controller.end_drag()
			_request_hover_refresh()
		return true
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		var hover_result: Dictionary = update_hover_at_screen_position(mouse_event.position)
		if _observe_mode_active():
			_focus_observe_hover(hover_result)
			return true
		if _skill_targeting_active() and game_root.has_method("confirm_active_skill_target"):
			var skill_target: Dictionary = _skill_target_from_hover(hover_result)
			if not skill_target.is_empty():
				game_root.confirm_active_skill_target(skill_target)
				return true
		if selected_node != null and game_root.has_method("execute_primary_interaction"):
			game_root.execute_primary_interaction()
			return true
		if str(hover_result.get("kind", "")) == "ground" and (game_root.has_method("request_player_move") or game_root.has_method("execute_move_to_grid")):
			var ground_position: Vector3 = hover_result.get("position", Vector3.ZERO)
			var grid: Dictionary = _grid_from_world_position(ground_position)
			var result: Dictionary = game_root.request_player_move(grid) if game_root.has_method("request_player_move") else game_root.execute_move_to_grid(grid)
			print("ground click move grid=%s success=%s reason=%s" % [JSON.stringify(grid), str(result.get("success", false)), str(result.get("reason", ""))])
			return true
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
		var right_hover: Dictionary = update_hover_at_screen_position(mouse_event.position)
		if _observe_mode_active():
			return true
		if str(right_hover.get("kind", "")) == "ground" and game_root.has_method("select_grid_target"):
			var right_ground_position: Vector3 = right_hover.get("position", Vector3.ZERO)
			game_root.select_grid_target(_grid_from_world_position(right_ground_position))
		if game_root.has_method("show_interaction_menu") and game_root.has_method("current_interaction_prompt"):
			game_root.show_interaction_menu(mouse_event.position, game_root.current_interaction_prompt())
		return true
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
		_zoom_camera_wheel(1.0)
		return true
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
		_zoom_camera_wheel(-1.0)
		return true
	return false


func _close_context_menu_on_outside_click(mouse_event: InputEventMouseButton) -> bool:
	if not mouse_event.pressed:
		return false
	if mouse_event.button_index != MOUSE_BUTTON_LEFT and mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return false
	if not _context_menu_open():
		return false
	if _mouse_over_blocking_ui():
		return false
	if game_root.has_method("hide_interaction_menu"):
		game_root.hide_interaction_menu()
	if game_root.has_method("close_active_context_menu"):
		game_root.close_active_context_menu()
	return true


func update_hover_at_screen_position(screen_position: Vector2) -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		_set_hover_failure("camera_missing")
		return {"success": false, "reason": "camera_missing"}
	last_hover_screen_position = screen_position

	var hit: Dictionary = world_interaction_picker.pick_from_screen(camera, screen_position, world_result, _observed_level())
	if hit.is_empty():
		var no_hit_clear_result := _clear_hover("no_hit")
		return {"success": false, "reason": "no_hit", "clear_selection_result": no_hit_clear_result}

	var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
	_update_hover_cursor(hit_position)
	var collider: Object = hit.get("collider", null)
	var target_node := _interaction_node(collider as Node)
	if target_node == null:
		var ground_clear_result := _clear_selection_only("ground_hover")
		var hover_changed := _set_hover_ground(hit_position, _dictionary_or_empty(hit.get("picking", {})))
		if hover_changed and game_root.has_method("refresh_hud"):
			game_root.refresh_hud(game_root.current_interaction_prompt() if game_root.has_method("current_interaction_prompt") else {})
		_preview_skill_target_from_hover({"success": true, "kind": "ground", "position": hit_position})
		return {"success": true, "kind": "ground", "position": hit_position, "clear_selection_result": ground_clear_result, "picking": _dictionary_or_empty(hit.get("picking", {}))}

	if selected_node != target_node and game_root.has_method("select_interaction_node"):
		selected_node = target_node
		game_root.select_interaction_node(target_node)
	var hover_changed := _set_hover_interaction(target_node, hit_position, _dictionary_or_empty(hit.get("picking", {})))
	if hover_changed and game_root.has_method("refresh_hud"):
		game_root.refresh_hud(game_root.current_interaction_prompt() if game_root.has_method("current_interaction_prompt") else {})
	var interaction_hover: Dictionary = hover_state_controller.current_state()
	interaction_hover["success"] = true
	interaction_hover["node"] = target_node
	interaction_hover["position"] = hit_position
	interaction_hover["picking"] = _dictionary_or_empty(hit.get("picking", {}))
	_preview_skill_target_from_hover(interaction_hover)
	return interaction_hover


func hover_state_snapshot() -> Dictionary:
	return hover_state_controller.hover_state_snapshot(_hover_ui_blocker_name())


func selection_debug_snapshot() -> Dictionary:
	return hover_state_controller.selection_debug_snapshot(hover_state_snapshot())


func camera_follow_snapshot() -> Dictionary:
	if camera_input_controller == null or not camera_input_controller.has_method("snapshot"):
		return {"has_camera": false, "reason": "camera_input_snapshot_missing"}
	var snapshot: Dictionary = _dictionary_or_empty(camera_input_controller.call("snapshot"))
	snapshot["focused_target"] = _focused_actor_follow_target()
	return snapshot


func _handle_camera_key(event: InputEventKey) -> bool:
	var key := event.keycode
	if key == 0:
		key = event.physical_keycode
	if not event.pressed:
		if key == KEY_SPACE:
			_stop_space_wait_hold()
		return false
	if event.echo:
		return false
	if key == KEY_QUOTELEFT:
		if game_root.has_method("toggle_debug_console"):
			game_root.toggle_debug_console()
		return true
	if game_root.has_method("is_debug_console_open") and bool(game_root.is_debug_console_open()):
		if key == KEY_ESCAPE and game_root.has_method("close_active_ui"):
			game_root.close_active_ui("keyboard_escape")
			return true
		return true
	if game_root.has_method("handle_trade_shortcut") and bool(game_root.handle_trade_shortcut(event)):
		return true
	var digit := _digit_for_key(key)
	if digit >= 1 and event.alt_pressed and _handle_hotbar_group_key(digit):
		return true
	if digit >= 0 and not (key == KEY_0 and event.ctrl_pressed) and _handle_digit_key(digit):
		return true
	var stage_panel := _stage_panel_for_key(key)
	if not stage_panel.is_empty():
		if game_root.has_method("toggle_stage_panel"):
			game_root.toggle_stage_panel(stage_panel)
		return true
	if key == KEY_EQUAL or key == KEY_PLUS:
		_scale_zoom(1.2)
		return true
	elif key == KEY_MINUS:
		_scale_zoom(1.0 / 1.2)
		return true
	elif key == KEY_0 and event.ctrl_pressed:
		camera_input_controller.reset_zoom(_viewport_size(), _level_plane_height())
		_request_hover_refresh()
		return true
	elif key == KEY_F:
		focus_current_actor()
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
	elif key == KEY_V:
		if game_root.has_method("cycle_debug_overlay_mode"):
			game_root.cycle_debug_overlay_mode()
		return true
	elif key == KEY_F3:
		if game_root.has_method("toggle_debug_panel"):
			game_root.toggle_debug_panel()
		return true
	elif key == KEY_BRACKETLEFT:
		if game_root.has_method("cycle_info_panel"):
			game_root.cycle_info_panel(-1)
		return true
	elif key == KEY_BRACKETRIGHT:
		if game_root.has_method("cycle_info_panel"):
			game_root.cycle_info_panel(1)
		return true
	elif key == KEY_A:
		if game_root.has_method("toggle_auto_tick"):
			game_root.toggle_auto_tick()
		return true
	elif key == KEY_SLASH:
		if game_root.has_method("toggle_controls_hint"):
			game_root.toggle_controls_hint()
		return true
	elif key == KEY_ESCAPE:
		if game_root.has_method("close_active_ui"):
			game_root.close_active_ui("keyboard_escape")
		return true
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		if game_root.has_method("has_active_dialogue") and bool(game_root.has_active_dialogue()) and game_root.has_method("press_enter_action"):
			game_root.press_enter_action()
			return true
		return false
	elif key == KEY_SPACE:
		var result: Dictionary = {}
		if game_root.has_method("press_space_action"):
			result = game_root.press_space_action()
		_start_space_wait_hold_if_allowed(result)
		if game_root.has_method("hide_interaction_menu"):
			game_root.hide_interaction_menu()
		return true
	return false


func _process_space_wait_hold(delta: float) -> void:
	space_wait_hold_controller.process(delta, _space_wait_repeat_allowed(), Callable(game_root, "repeat_space_wait_action") if game_root.has_method("repeat_space_wait_action") else Callable())


func _start_space_wait_hold_if_allowed(result: Dictionary) -> void:
	space_wait_hold_controller.start_if_allowed(result, _space_wait_repeat_allowed())


func _stop_space_wait_hold() -> void:
	space_wait_hold_controller.stop()


func _space_wait_result_can_repeat(result: Dictionary) -> bool:
	return space_wait_hold_controller.result_can_repeat(result)


func _space_wait_repeat_allowed() -> bool:
	if _gameplay_input_blocked_by_ui() and not _space_wait_runner_blocks_input():
		return false
	if game_root.has_method("has_active_dialogue") and bool(game_root.has_active_dialogue()):
		return false
	return not _runtime_has_pending()


func _space_wait_runner_blocks_input() -> bool:
	if not game_root.has_method("turn_action_runner_snapshot"):
		return false
	var runner: Dictionary = _dictionary_or_empty(game_root.turn_action_runner_snapshot())
	return (bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))) and str(runner.get("action_kind", "")) == "wait"


func _handle_digit_key(digit: int) -> bool:
	if digit <= 0:
		return false
	if game_root.has_method("has_active_dialogue") and bool(game_root.has_active_dialogue()):
		if digit <= 9 and game_root.has_method("choose_dialogue_option_by_index"):
			game_root.choose_dialogue_option_by_index(digit - 1)
			return true
		return false
	if _observe_mode_active():
		return true
	if _gameplay_input_blocked_by_ui():
		return false
	if game_root.has_method("use_hotbar_slot"):
		var slot_id := "slot_%d" % (10 if digit == 10 else digit)
		game_root.use_hotbar_slot(slot_id)
		return true
	return false


func _observe_mode_active() -> bool:
	return game_root.has_method("is_observe_mode_enabled") and bool(game_root.is_observe_mode_enabled())


func _focus_observe_hover(hover_result: Dictionary) -> void:
	if str(hover_result.get("kind", "")) != "interaction":
		return
	var actor_id := int(hover_result.get("actor_id", 0))
	if actor_id <= 0:
		return
	if game_root.has_method("focus_actor"):
		game_root.focus_actor(actor_id)


func _handle_hotbar_group_key(digit: int) -> bool:
	if digit < 1 or digit > 3:
		return false
	if game_root.has_method("has_active_dialogue") and bool(game_root.has_active_dialogue()):
		return false
	if _observe_mode_active():
		return true
	if _gameplay_input_blocked_by_ui():
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


func clear_selection_state(reason: String = "cleared") -> Dictionary:
	camera_input_controller.clear_drag_state()
	var result := _clear_selection_only(reason)
	_clear_skill_target_preview_markers()
	_clear_move_path_preview_markers()
	return result


func update_skill_target_preview_markers(preview: Dictionary) -> void:
	runtime_marker_controller.update_skill_target_preview_markers(preview, _runtime_snapshot(), _observed_level())


func focus_current_actor() -> void:
	var follow_target: Dictionary = _focused_actor_follow_target()
	_focus_camera_target(follow_target)
	_request_hover_refresh()


func handle_space_key_pressed() -> bool:
	var result: Dictionary = {}
	if game_root.has_method("press_space_action"):
		result = game_root.press_space_action()
	_start_space_wait_hold_if_allowed(result)
	if game_root.has_method("hide_interaction_menu"):
		game_root.hide_interaction_menu()
	return true


func stop_space_wait_hold() -> void:
	_stop_space_wait_hold()


func scale_camera_zoom(multiplier: float) -> void:
	_scale_zoom(multiplier)


func reset_camera_zoom() -> void:
	camera_input_controller.reset_zoom(_viewport_size(), _level_plane_height())
	_request_hover_refresh()


func has_selection_state() -> bool:
	return selected_node != null or camera_input_controller.is_dragging()


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


func _begin_camera_drag(screen_position: Vector2) -> void:
	camera_input_controller.begin_drag(screen_position, float(_observed_level()) + BEVY_DRAG_PLANE_HEIGHT)


func _drag_camera_to_screen_position(screen_position: Vector2) -> void:
	camera_input_controller.drag_to_screen_position(screen_position, float(_observed_level()) + BEVY_DRAG_PLANE_HEIGHT, _viewport_size(), _level_plane_height())


func _zoom_camera_wheel(direction: float) -> void:
	camera_input_controller.zoom_wheel(direction, _viewport_size(), _level_plane_height())
	_request_hover_refresh()


func _scale_zoom(multiplier: float) -> void:
	camera_input_controller.scale_zoom(multiplier, _viewport_size(), _level_plane_height())
	_request_hover_refresh()


func _request_hover_refresh() -> void:
	hover_refresh_requested = true
	last_hover_screen_position = Vector2(-1000000.0, -1000000.0)


func _update_hover_cursor(world_position: Vector3) -> void:
	runtime_marker_controller.update_hover_cursor(world_position, _observed_level())


func _clear_hover(reason: String = "") -> Dictionary:
	runtime_marker_controller.hide_hover_cursor()
	var result := _clear_selection_only(reason)
	_set_hover_failure(reason)
	return result


func _clear_selection_only(reason: String = "cleared") -> Dictionary:
	if selected_node == null:
		last_selection_clear_result = _selection_clear_result(false, reason, {})
		return last_selection_clear_result.duplicate(true)
	selected_node = null
	if game_root.has_method("clear_interaction_selection"):
		last_selection_clear_result = game_root.clear_interaction_selection(reason)
		return last_selection_clear_result.duplicate(true)
	last_selection_clear_result = _selection_clear_result(false, reason, {
		"success": false,
		"reason": "clear_interaction_selection_missing",
	})
	return last_selection_clear_result.duplicate(true)


func selection_clear_result_snapshot() -> Dictionary:
	return last_selection_clear_result.duplicate(true)


func _selection_clear_result(had_selected_node: bool, reason: String, source_result: Dictionary) -> Dictionary:
	return {
		"success": bool(source_result.get("success", true)),
		"reason": reason,
		"had_selected_node": had_selected_node,
		"target": {},
		"prompt": {},
		"turn_policy": {
			"action_kind": "clear_selection",
			"reason": reason,
			"had_selection": had_selected_node,
			"had_prompt": false,
			"had_pending": _runtime_has_pending(),
			"auto_advanced": false,
			"turn_preserved": true,
			"skip_reason": "selection_only",
		},
	}


func _set_hover_ground(world_position: Vector3, picking: Dictionary = {}) -> bool:
	var grid: Dictionary = _grid_from_world_position(world_position)
	if _can_reuse_ground_hover(grid):
		return false
	var move_preview: Dictionary = _move_preview_for_grid(grid)
	_apply_hover_cursor_state(move_preview)
	_hide_hover_target_outline()
	return _replace_hover_state({
		"active": true,
		"kind": "ground",
		"grid": grid,
		"target_name": "",
		"target_type": "grid",
		"target_category": "grid",
		"target_id": "",
		"actor_id": 0,
		"ui_blocker": _hover_ui_blocker_name(),
		"reason": "",
		"prompt": _hover_prompt_for_target({"target_type": "grid", "grid": grid}),
		"move_preview": move_preview,
		"attack_preview": {},
		"picking": picking.duplicate(true),
	})


func _can_reuse_ground_hover(grid: Dictionary) -> bool:
	return hover_state_controller.can_reuse_ground_hover(grid, _skill_targeting_active())


func _set_hover_interaction(target_node: Node, world_position: Vector3, picking: Dictionary = {}) -> bool:
	var metadata: Dictionary = {}
	if target_node != null and target_node.has_meta("interaction_target"):
		var raw: Variant = target_node.get_meta("interaction_target")
		if typeof(raw) == TYPE_DICTIONARY:
			metadata = raw
	metadata = world_interaction_picker.merge_world_interaction_target(metadata, world_result)
	var target_id := str(metadata.get("target_id", ""))
	if target_id.is_empty() and int(metadata.get("actor_id", 0)) > 0:
		target_id = str(int(metadata.get("actor_id", 0)))
		metadata["target_id"] = target_id
	var target_name := str(metadata.get("target_name", metadata.get("display_name", "")))
	if target_name.is_empty():
		target_name = target_id
	if target_name.is_empty() and target_node != null:
		target_name = str(target_node.name)
	var prompt: Dictionary = _hover_prompt_for_target(metadata)
	var target_category: String = _hover_target_category(metadata, prompt)
	var attack_preview: Dictionary = _attack_preview_for_target(metadata) if str(prompt.get("primary_option_kind", "")) == "attack" else {}
	_apply_hover_cursor_state({}, attack_preview)
	_update_hover_target_outline(metadata, _grid_from_world_position(world_position), target_category, attack_preview)
	return _replace_hover_state({
		"active": true,
		"kind": "interaction",
		"grid": _grid_from_world_position(world_position),
		"target_name": target_name,
		"target_type": str(metadata.get("target_type", "")),
		"target_category": target_category,
		"target_id": target_id,
		"actor_id": int(metadata.get("actor_id", 0)),
		"ui_blocker": _hover_ui_blocker_name(),
		"reason": "",
		"prompt": prompt,
		"move_preview": {},
		"attack_preview": attack_preview,
		"picking": picking.duplicate(true),
	})


func _set_hover_failure(reason: String = "") -> bool:
	_apply_hover_cursor_state({}, {})
	_hide_hover_target_outline()
	return _replace_hover_state({
		"active": false,
		"kind": "",
		"grid": {},
		"target_name": "",
		"target_type": "",
		"target_category": "",
		"target_id": "",
		"actor_id": 0,
		"ui_blocker": _hover_ui_blocker_name(),
		"reason": reason,
		"prompt": {},
		"move_preview": {},
		"attack_preview": {},
		"picking": {},
	})


func _replace_hover_state(next_state: Dictionary) -> bool:
	return hover_state_controller.replace_hover_state(next_state)


func _hover_ui_blocker_name() -> String:
	if _mouse_over_blocking_ui():
		var viewport := game_root.get_viewport()
		var hovered := viewport.gui_get_hovered_control() if viewport != null else null
		return str(hovered.name) if hovered != null else "ui"
	if _gameplay_input_blocked_by_ui() and game_root.has_method("gameplay_input_blocker_name"):
		return str(game_root.gameplay_input_blocker_name())
	return ""


func _hover_prompt_for_target(target: Dictionary) -> Dictionary:
	var simulation: Variant = game_root.get("simulation") if game_root != null else null
	return hover_state_controller.hover_prompt_for_target(target, simulation, _player_actor_id())


func _hover_target_category(target: Dictionary, prompt: Dictionary) -> String:
	return hover_state_controller.hover_target_category(target, prompt, _runtime_snapshot())


func _move_preview_for_grid(grid: Dictionary) -> Dictionary:
	var simulation: Variant = game_root.get("simulation") if game_root != null else null
	return hover_state_controller.move_preview_for_grid(grid, simulation, _player_actor_id(), world_result)


func _attack_preview_for_target(target: Dictionary) -> Dictionary:
	var simulation: Variant = game_root.get("simulation") if game_root != null else null
	return hover_state_controller.attack_preview_for_target(target, simulation, _player_actor_id(), world_result)


func _apply_hover_cursor_state(move_preview: Dictionary, attack_preview: Dictionary = {}) -> void:
	runtime_marker_controller.apply_hover_cursor_state(move_preview, attack_preview, world_result, _runtime_snapshot(), _observed_level())


func _update_hover_target_outline(target: Dictionary, grid: Dictionary, target_category: String, attack_preview: Dictionary) -> void:
	runtime_marker_controller.update_hover_target_outline(target, grid, target_category, attack_preview, _observed_level())


func _hide_hover_target_outline() -> void:
	runtime_marker_controller.hide_hover_target_outline()


func _hover_outline_color(target_category: String) -> Color:
	return runtime_marker_controller.hover_outline_color(target_category)


func _hover_outline_height(target_category: String) -> float:
	return runtime_marker_controller.hover_outline_height(target_category)


func _update_attack_target_marker(attack_preview: Dictionary, color: Color) -> void:
	runtime_marker_controller.update_attack_target_marker(attack_preview, color, _runtime_snapshot(), _observed_level())


func _update_attack_target_outline(attack_preview: Dictionary, color: Color) -> void:
	runtime_marker_controller.update_attack_target_outline(attack_preview, color, _runtime_snapshot(), _observed_level())


func _update_attack_range_markers(attack_preview: Dictionary, color: Color) -> void:
	runtime_marker_controller.update_attack_range_markers(attack_preview, color, world_result, _observed_level())


func _attack_target_grid_from_preview(attack_preview: Dictionary) -> Dictionary:
	return runtime_marker_controller.attack_target_grid_from_preview(attack_preview, _runtime_snapshot())


func _attack_range_candidate_grids(target_grid: Dictionary, attack_range: int) -> Array[Dictionary]:
	return runtime_marker_controller.attack_range_candidate_grids(target_grid, attack_range, world_result, _observed_level())


func _grid_in_bounds(grid: Dictionary, bounds: Dictionary) -> bool:
	return runtime_marker_controller.call("_grid_in_bounds", grid, bounds)


func _clear_attack_range_markers() -> void:
	runtime_marker_controller.clear_attack_range_markers()


func _update_move_path_preview_markers(move_preview: Dictionary, color: Color) -> void:
	runtime_marker_controller.update_move_path_preview_markers(move_preview, color, _observed_level())


func _clear_move_path_preview_markers() -> void:
	runtime_marker_controller.clear_move_path_preview_markers()


func _sync_move_path_preview_with_active_movement() -> void:
	if game_root == null:
		return
	if game_root.has_method("turn_action_runner_snapshot"):
		var runner: Dictionary = _dictionary_or_empty(game_root.turn_action_runner_snapshot())
		var queue: Dictionary = _dictionary_or_empty(runner.get("queue", {}))
		if bool(queue.get("active", false)) and not _array_or_empty(queue.get("remaining_move_path", [])).is_empty():
			queue["compat"] = _dictionary_or_empty(runner.get("compat", {})).duplicate(true)
			runtime_marker_controller.sync_move_path_preview_with_action_queue(queue, _observed_level())
			return
	var presenter: Dictionary = _active_turn_runner_move_snapshot()
	if presenter.is_empty() and game_root.has_method("world_action_presenter_snapshot"):
		presenter = _dictionary_or_empty(game_root.world_action_presenter_snapshot())
	runtime_marker_controller.sync_move_path_preview_with_active_movement(presenter)


func _active_turn_runner_move_snapshot() -> Dictionary:
	if game_root == null or not game_root.has_method("turn_action_runner_snapshot"):
		return {}
	var runner: Dictionary = _dictionary_or_empty(game_root.turn_action_runner_snapshot())
	if str(runner.get("action_kind", "")) != "move":
		return {}
	var path: Array = _array_or_empty(runner.get("path", []))
	if path.is_empty():
		return {}
	return {
		"active": bool(runner.get("active", false)) or bool(runner.get("presentation_active", false)),
		"kind": "movement",
		"path": path.duplicate(true),
		"current_step_index": int(runner.get("step_index", runner.get("completed_steps", 0))),
	}


func _player_actor_id() -> int:
	if cached_player_actor_id > 0:
		return cached_player_actor_id
	cached_player_actor_id = _player_actor_id_from_world_result()
	if cached_player_actor_id > 0:
		return cached_player_actor_id
	for actor in _array_or_empty(_runtime_snapshot().get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if str(actor_data.get("kind", "")) == "player":
			cached_player_actor_id = int(actor_data.get("actor_id", 0))
			return cached_player_actor_id
	return 0


func _player_actor_id_from_world_result() -> int:
	for actor in _array_or_empty(world_result.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if str(actor_data.get("kind", "")) == "player":
			return int(actor_data.get("actor_id", 0))
	return 0


func _runtime_snapshot() -> Dictionary:
	var simulation: Variant = game_root.get("simulation") if game_root != null else null
	if simulation == null or not simulation.has_method("snapshot"):
		return {}
	return _dictionary_or_empty(simulation.snapshot())


func _grid_from_world_position(world_position: Vector3) -> Dictionary:
	return {
		"x": int(roundf(world_position.x / GRID_SIZE)),
		"y": _observed_level(),
		"z": int(roundf(world_position.z / GRID_SIZE)),
	}


func _interaction_node(node: Node) -> Node:
	var current := node
	while current != null:
		if current.has_meta("interaction_target"):
			return current
		current = current.get_parent()
	return null


func _preview_skill_target_from_hover(hover_result: Dictionary) -> void:
	if not _skill_targeting_active() or not game_root.has_method("preview_active_skill_target"):
		_clear_skill_target_preview_markers()
		return
	var target: Dictionary = _skill_target_from_hover(hover_result)
	if target.is_empty():
		_clear_skill_target_preview_markers()
		return
	game_root.preview_active_skill_target(target)


func _skill_target_from_hover(hover_result: Dictionary) -> Dictionary:
	match str(hover_result.get("kind", "")):
		"ground":
			var position: Vector3 = hover_result.get("position", Vector3.ZERO)
			return {
				"target_type": "grid",
				"grid": _grid_from_world_position(position),
			}
		"interaction":
			var node: Node = hover_result.get("node", null)
			if node == null or not node.has_meta("interaction_target"):
				return {}
			var metadata: Variant = node.get_meta("interaction_target")
			if typeof(metadata) != TYPE_DICTIONARY:
				return {}
			var target: Dictionary = metadata
			if str(target.get("target_type", "")) == "actor":
				return {
					"target_type": "actor",
					"actor_id": int(target.get("actor_id", 0)),
				}
			if str(target.get("target_type", "")) == "map_object":
				return target.duplicate(true)
	return {}


func _skill_targeting_active() -> bool:
	return game_root.has_method("has_active_skill_targeting") and bool(game_root.has_active_skill_targeting())


func _find_world_camera() -> Camera3D:
	if world_container == null:
		return null
	var pending: Array[Node] = [world_container]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.name == "WorldCamera" and node is Camera3D and not node.is_queued_for_deletion():
			return node as Camera3D
		for child in node.get_children():
			pending.append(child)
	return null


func _focused_actor_position() -> Vector3:
	var follow_target: Dictionary = _focused_actor_follow_target()
	var follow_position: Vector3 = follow_target.get("position", _map_center_focus_position())
	return follow_position


func _focused_actor_follow_target() -> Dictionary:
	var actor_id := _focused_actor_id_for_follow()
	if game_root.has_method("focused_actor_node_for_camera_follow"):
		var actor_node := game_root.focused_actor_node_for_camera_follow() as Node3D
		if actor_node != null:
			return {
				"position": actor_node.global_position,
				"source": "actor_node",
				"actor_id": actor_id,
				"actor_node": actor_node,
			}
	if game_root.has_method("focused_actor_visual_position"):
		var visual_position: Variant = game_root.focused_actor_visual_position()
		if typeof(visual_position) == TYPE_VECTOR3:
			var visual := visual_position as Vector3
			return {
				"position": Vector3(visual.x, _level_plane_height(), visual.z),
				"source": "actor_node",
				"actor_id": actor_id,
			}
	if game_root.has_method("focused_actor_grid_position"):
		var focused_grid: Dictionary = _dictionary_or_empty(game_root.focused_actor_grid_position())
		if not focused_grid.is_empty():
			return {
				"position": Vector3(
					float(focused_grid.get("x", 0)),
					float(focused_grid.get("y", _observed_level())) + BEVY_LEVEL_PLANE_HEIGHT,
					float(focused_grid.get("z", 0))
				),
				"source": "grid",
				"actor_id": actor_id,
				"grid": focused_grid.duplicate(true),
			}
	return {
		"position": _map_center_focus_position(),
		"source": "map_center",
		"actor_id": 0,
	}


func _process_camera_follow_target(follow_target: Dictionary) -> void:
	var actor_node := follow_target.get("actor_node", null) as Node3D
	if actor_node != null:
		camera_input_controller.process_actor_node_follow(actor_node, _viewport_size(), _level_plane_height())
		return
	var follow_position: Vector3 = follow_target.get("position", _map_center_focus_position())
	camera_input_controller.process_follow(
		follow_position,
		_viewport_size(),
		_level_plane_height(),
		str(follow_target.get("source", "map_center")),
		int(follow_target.get("actor_id", 0))
	)


func _focus_camera_target(follow_target: Dictionary) -> void:
	var actor_node := follow_target.get("actor_node", null) as Node3D
	if actor_node != null:
		camera_input_controller.follow_actor_node(actor_node, _viewport_size(), _level_plane_height())
		return
	var focused_grid: Dictionary = _dictionary_or_empty(follow_target.get("grid", {}))
	if not focused_grid.is_empty() and str(follow_target.get("source", "")) == "grid":
		camera_input_controller.follow_grid(focused_grid, _viewport_size(), _level_plane_height(), int(follow_target.get("actor_id", 0)))
		return
	var follow_position: Vector3 = follow_target.get("position", _map_center_focus_position())
	camera_input_controller.focus(
		follow_position,
		_viewport_size(),
		_level_plane_height(),
		str(follow_target.get("source", "map_center")),
		int(follow_target.get("actor_id", 0))
	)


func _focused_actor_id_for_follow() -> int:
	if game_root.has_method("turn_action_runner_snapshot"):
		var runner: Dictionary = _dictionary_or_empty(game_root.turn_action_runner_snapshot())
		if bool(runner.get("active", false)) or bool(runner.get("presentation_active", false)):
			return int(runner.get("actor_id", 0))
	if game_root.has_method("focused_actor_snapshot"):
		return int(_dictionary_or_empty(game_root.focused_actor_snapshot()).get("actor_id", 0))
	return _player_actor_id()


func _player_focus_position() -> Vector3:
	for actor in _array_or_empty(world_result.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if actor_data.get("kind", "") == "player":
			var grid: Dictionary = _dictionary_or_empty(actor_data.get("grid_position", {}))
			return Vector3(float(grid.get("x", 0)), float(grid.get("y", _observed_level())) + BEVY_LEVEL_PLANE_HEIGHT, float(grid.get("z", 0)))
	return _map_center_focus_position()


func _map_center_focus_position() -> Vector3:
	var size := _map_size()
	return Vector3(size.x * GRID_SIZE * 0.5, _level_plane_height(), size.y * GRID_SIZE * 0.5)


func _level_plane_height() -> float:
	return float(_observed_level()) + BEVY_LEVEL_PLANE_HEIGHT


func _observed_level() -> int:
	if game_root.has_method("current_map_level"):
		return int(game_root.current_map_level())
	return 0


func _mouse_inside_viewport() -> bool:
	var viewport := game_root.get_viewport()
	if viewport == null:
		return false
	var size := viewport.get_visible_rect().size
	var position := viewport.get_mouse_position()
	return position.x >= 0.0 and position.y >= 0.0 and position.x <= size.x and position.y <= size.y


func _mouse_over_blocking_ui() -> bool:
	var viewport := game_root.get_viewport()
	if viewport == null:
		return false
	var hovered := viewport.gui_get_hovered_control()
	var current := hovered
	while current != null:
		if current.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
		current = current.get_parent() as Control
	return false


func _gameplay_input_blocked_by_ui() -> bool:
	return game_root.has_method("gameplay_input_blocked_by_ui") and bool(game_root.gameplay_input_blocked_by_ui())


func _mouse_motion_blocked_by_ui() -> bool:
	if not _gameplay_input_blocked_by_ui():
		return _mouse_over_blocking_ui()
	if camera_input_controller.is_dragging() and _camera_drag_allowed_by_action_blocker():
		return false
	return true


func _blocked_camera_drag_button_allowed(mouse_event: InputEventMouseButton) -> bool:
	if mouse_event.button_index != MOUSE_BUTTON_MIDDLE:
		return false
	if not _gameplay_input_blocked_by_ui():
		return false
	return _camera_drag_allowed_by_action_blocker()


func _camera_drag_allowed_by_action_blocker() -> bool:
	if game_root == null or not game_root.has_method("gameplay_input_blocker_snapshot"):
		return false
	var blocker: Dictionary = _dictionary_or_empty(game_root.gameplay_input_blocker_snapshot())
	if not bool(blocker.get("blocked", false)):
		return false
	if not bool(blocker.get("camera_drag_allowed", false)):
		return false
	return str(blocker.get("kind", "")) in ["turn_action_runner", "world_action_presenter"]


func _interaction_menu_open() -> bool:
	return game_root.has_method("is_interaction_menu_open") and bool(game_root.is_interaction_menu_open())


func _context_menu_open() -> bool:
	if game_root.has_method("context_menu_snapshot"):
		return bool(_dictionary_or_empty(game_root.context_menu_snapshot()).get("active", false))
	return _interaction_menu_open()


func _runtime_has_pending() -> bool:
	var simulation: Variant = game_root.get("simulation") if game_root != null else null
	if simulation == null:
		return false
	return not _dictionary_or_empty(simulation.get("pending_movement")).is_empty() \
		or not _dictionary_or_empty(simulation.get("pending_interaction")).is_empty() \
		or not _dictionary_or_empty(simulation.get("pending_crafting")).is_empty()


func _clear_skill_target_preview_markers() -> void:
	runtime_marker_controller.clear_skill_target_preview_markers()


func _viewport_size() -> Vector2:
	var viewport := game_root.get_viewport()
	if viewport == null:
		return Vector2(1440.0, 900.0)
	var size := viewport.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2(1440.0, 900.0)
	return size


func _map_size() -> Vector2:
	var map: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	var size: Dictionary = _dictionary_or_empty(map.get("size", {}))
	return Vector2(max(1.0, float(size.get("width", 48.0))), max(1.0, float(size.get("height", 42.0))))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
