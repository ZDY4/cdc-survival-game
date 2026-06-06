extends RefCounted

const VisionGeometry = preload("res://scripts/core/vision/vision_geometry.gd")

const GRID_SIZE := 1.0
const RAY_DISTANCE := 500.0
const BEVY_CAMERA_YAW_DEGREES := 0.0
const BEVY_CAMERA_PITCH_DEGREES := 36.0
const BEVY_CAMERA_FOV_DEGREES := 30.0
const BEVY_CAMERA_DISTANCE_PADDING_WORLD := 8.0
const BEVY_VIEWPORT_PADDING_PX := 72.0
const BEVY_HUD_RESERVED_WIDTH_PX := 620.0
const BEVY_LEVEL_PLANE_HEIGHT := GRID_SIZE * 0.5
const BEVY_DRAG_PLANE_HEIGHT := 0.11
const SPACE_HOLD_INITIAL_DELAY_SEC := 0.45
const SPACE_HOLD_REPEAT_INTERVAL_SEC := 0.30
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const HOVER_COLOR_INTERACTION := Color(1.0, 0.82, 0.18, 0.72)
const HOVER_COLOR_MOVE_REACHABLE := Color(0.24, 0.95, 0.48, 0.72)
const HOVER_COLOR_MOVE_BLOCKED := Color(1.0, 0.22, 0.18, 0.72)
const HOVER_COLOR_MOVE_PENDING := Color(1.0, 0.78, 0.18, 0.58)
const HOVER_COLOR_ATTACK_REACHABLE := Color(1.0, 0.45, 0.16, 0.78)
const HOVER_COLOR_ATTACK_BLOCKED := Color(0.95, 0.12, 0.28, 0.78)
const HOVER_COLOR_SKILL_VALID := Color(0.38, 0.68, 1.0, 0.58)
const HOVER_COLOR_SKILL_BLOCKED := Color(0.96, 0.18, 0.55, 0.52)
const HOVER_COLOR_PICKUP := Color(0.35, 0.82, 1.0, 0.50)
const HOVER_COLOR_CONTAINER := Color(0.36, 0.95, 0.62, 0.50)
const HOVER_COLOR_TRIGGER := Color(0.70, 0.55, 1.0, 0.50)
const HOVER_COLOR_DOOR := Color(0.95, 0.72, 0.28, 0.56)
const HOVER_COLOR_ACTOR := Color(1.0, 0.88, 0.22, 0.50)

var game_root: Node
var world_container: Node3D
var world_result: Dictionary = {}
var camera: Camera3D
var hover_cursor: MeshInstance3D
var hover_target_outline: MeshInstance3D
var attack_target_marker: MeshInstance3D
var attack_target_outline: MeshInstance3D
var attack_range_markers: Node3D
var skill_target_preview_markers: Node3D
var move_path_preview_markers: Node3D
var pending_movement_path_markers: Node3D
var selected_node: Node
var camera_target: Vector3 = Vector3.ZERO
var is_middle_mouse_dragging := false
var camera_drag_anchor_world: Vector2 = Vector2.ZERO
var has_camera_drag_anchor := false
var camera_zoom_factor := 1.0
var camera_map_size := Vector2(48.0, 42.0)
var is_camera_following_player := true
var is_space_wait_held := false
var space_wait_elapsed_sec := 0.0
var space_wait_repeated := false
var _vision_geometry := VisionGeometry.new()
var last_hover_state: Dictionary = {
	"active": false,
	"kind": "",
	"grid": {},
	"target_name": "",
	"target_type": "",
	"target_id": "",
	"actor_id": 0,
	"ui_blocker": "",
	"reason": "",
	"prompt": {},
	"move_preview": {},
	"attack_preview": {},
}


func _init(p_game_root: Node) -> void:
	game_root = p_game_root
	hover_cursor = _build_hover_cursor()
	game_root.add_child(hover_cursor)
	hover_target_outline = _build_hover_target_outline()
	game_root.add_child(hover_target_outline)
	attack_target_marker = _build_attack_target_marker()
	game_root.add_child(attack_target_marker)
	attack_target_outline = _build_attack_target_outline()
	game_root.add_child(attack_target_outline)
	attack_range_markers = Node3D.new()
	attack_range_markers.name = "AttackRangeMarkers"
	game_root.add_child(attack_range_markers)
	skill_target_preview_markers = Node3D.new()
	skill_target_preview_markers.name = "SkillTargetPreviewMarkers"
	game_root.add_child(skill_target_preview_markers)
	move_path_preview_markers = Node3D.new()
	move_path_preview_markers.name = "MovePathPreviewMarkers"
	game_root.add_child(move_path_preview_markers)
	pending_movement_path_markers = Node3D.new()
	pending_movement_path_markers.name = "PendingMovementPathMarkers"
	game_root.add_child(pending_movement_path_markers)


func attach_world(p_world_container: Node3D, p_world_result: Dictionary) -> void:
	world_container = p_world_container
	world_result = p_world_result
	camera = _find_world_camera()
	if camera == null:
		push_warning("运行时输入控制器找不到 WorldCamera，鼠标拾取和相机移动暂不可用")
		return
	camera_target = _vector_meta(camera, "focus_position", _focused_actor_position())
	camera_target.y = _level_plane_height()
	camera_zoom_factor = _float_meta(camera, "zoom_factor", 1.0)
	camera_map_size = _vector2_meta(camera, "map_size", _map_size())
	is_camera_following_player = true
	has_camera_drag_anchor = false
	_sync_camera_focus_meta()
	_apply_camera_transform()
	hover_cursor.visible = false
	hover_target_outline.visible = false
	attack_target_marker.visible = false
	attack_target_outline.visible = false
	_clear_attack_range_markers()
	_clear_skill_target_preview_markers()
	_clear_move_path_preview_markers()
	_clear_selection_only()
	_set_hover_failure("world_changed")
	_update_pending_movement_path_markers()
	selected_node = null


func process(delta: float) -> void:
	if camera == null:
		return
	_process_space_wait_hold(delta)
	if is_camera_following_player and not is_middle_mouse_dragging:
		camera_target = _clamp_camera_target(_focused_actor_position())
		_apply_camera_transform()
	if _mouse_inside_viewport():
		update_hover_at_screen_position(game_root.get_viewport().get_mouse_position())
	_update_pending_movement_path_markers()


func input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventKey:
		if _handle_camera_key(event as InputEventKey):
			var key_viewport := game_root.get_viewport()
			if key_viewport != null:
				key_viewport.set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _gameplay_input_blocked_by_ui() or _mouse_over_blocking_ui():
			return
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if _close_interaction_menu_on_outside_click(mouse_button):
			var menu_viewport := game_root.get_viewport()
			if menu_viewport != null:
				menu_viewport.set_input_as_handled()
			return
		if _gameplay_input_blocked_by_ui() or _mouse_over_blocking_ui():
			return
		if _handle_mouse_button(mouse_button):
			var viewport := game_root.get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()


func unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventKey:
		_handle_camera_key(event as InputEventKey)
	elif event is InputEventMouseMotion:
		if _gameplay_input_blocked_by_ui():
			return
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if _close_interaction_menu_on_outside_click(mouse_button):
			return
		if _gameplay_input_blocked_by_ui():
			return
		_handle_mouse_button(mouse_button)


func _handle_mouse_motion(mouse_event: InputEventMouseMotion) -> void:
	if is_middle_mouse_dragging:
		_drag_camera_to_screen_position(mouse_event.position)
	else:
		update_hover_at_screen_position(mouse_event.position)


func _handle_mouse_button(mouse_event: InputEventMouseButton) -> bool:
	if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
		is_middle_mouse_dragging = mouse_event.pressed
		if is_middle_mouse_dragging:
			_begin_camera_drag(mouse_event.position)
		else:
			has_camera_drag_anchor = false
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
		if str(hover_result.get("kind", "")) == "ground" and game_root.has_method("execute_move_to_grid"):
			var ground_position: Vector3 = hover_result.get("position", Vector3.ZERO)
			var grid: Dictionary = _grid_from_world_position(ground_position)
			var result: Dictionary = game_root.execute_move_to_grid(grid)
			print("ground click move grid=%s success=%s reason=%s" % [JSON.stringify(grid), str(result.get("success", false)), str(result.get("reason", ""))])
			return true
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
		var right_hover: Dictionary = update_hover_at_screen_position(mouse_event.position)
		if _observe_mode_active():
			return true
		if str(right_hover.get("kind", "")) == "ground" and game_root.has_method("select_grid_target"):
			var right_ground_position: Vector3 = right_hover.get("position", Vector3.ZERO)
			game_root.select_grid_target(_grid_from_world_position(right_ground_position))
		if game_root.hud != null and game_root.hud.has_method("show_interaction_menu") and game_root.has_method("current_interaction_prompt"):
			game_root.hud.show_interaction_menu(mouse_event.position, game_root.current_interaction_prompt())
		return true
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
		_zoom_camera_wheel(1.0)
		return true
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
		_zoom_camera_wheel(-1.0)
		return true
	return false


func _close_interaction_menu_on_outside_click(mouse_event: InputEventMouseButton) -> bool:
	if not mouse_event.pressed:
		return false
	if mouse_event.button_index != MOUSE_BUTTON_LEFT and mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return false
	if not _interaction_menu_open():
		return false
	if _mouse_over_blocking_ui():
		return false
	if game_root.hud != null and game_root.hud.has_method("hide_interaction_menu"):
		game_root.hud.hide_interaction_menu()
	return true


func update_hover_at_screen_position(screen_position: Vector2) -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		_set_hover_failure("camera_missing")
		return {"success": false, "reason": "camera_missing"}

	var ray_from := camera.project_ray_origin(screen_position)
	var ray_to := ray_from + camera.project_ray_normal(screen_position) * RAY_DISTANCE
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		_clear_hover("no_hit")
		return {"success": false, "reason": "no_hit"}

	var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
	_update_hover_cursor(hit_position)
	var collider: Object = hit.get("collider", null)
	var target_node := _interaction_node(collider as Node)
	if target_node == null:
		_clear_selection_only()
		var hover_changed := _set_hover_ground(hit_position)
		if hover_changed and game_root.has_method("refresh_hud"):
			game_root.refresh_hud(game_root.current_interaction_prompt() if game_root.has_method("current_interaction_prompt") else {})
		_preview_skill_target_from_hover({"success": true, "kind": "ground", "position": hit_position})
		return {"success": true, "kind": "ground", "position": hit_position}

	if selected_node != target_node and game_root.has_method("select_interaction_node"):
		selected_node = target_node
		game_root.select_interaction_node(target_node)
	var hover_changed := _set_hover_interaction(target_node, hit_position)
	if hover_changed and game_root.has_method("refresh_hud"):
		game_root.refresh_hud(game_root.current_interaction_prompt() if game_root.has_method("current_interaction_prompt") else {})
	var interaction_hover := last_hover_state.duplicate(true)
	interaction_hover["success"] = true
	interaction_hover["node"] = target_node
	interaction_hover["position"] = hit_position
	_preview_skill_target_from_hover(interaction_hover)
	return interaction_hover


func hover_state_snapshot() -> Dictionary:
	var snapshot: Dictionary = last_hover_state.duplicate(true)
	snapshot["ui_blocker"] = _hover_ui_blocker_name()
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
		camera_zoom_factor = 1.0
		_apply_camera_transform()
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
		if game_root.hud != null and game_root.hud.has_method("hide_interaction_menu"):
			game_root.hud.hide_interaction_menu()
		return true
	return false


func _process_space_wait_hold(delta: float) -> void:
	if not is_space_wait_held:
		return
	if not _space_wait_repeat_allowed():
		_stop_space_wait_hold()
		return
	space_wait_elapsed_sec += delta
	var interval := SPACE_HOLD_REPEAT_INTERVAL_SEC if space_wait_repeated else SPACE_HOLD_INITIAL_DELAY_SEC
	if space_wait_elapsed_sec < interval:
		return
	space_wait_elapsed_sec = 0.0
	space_wait_repeated = true
	if game_root.has_method("press_space_action"):
		var result: Dictionary = game_root.press_space_action()
		if not _space_wait_result_can_repeat(result):
			_stop_space_wait_hold()


func _start_space_wait_hold_if_allowed(result: Dictionary) -> void:
	if not _space_wait_result_can_repeat(result) or not _space_wait_repeat_allowed():
		_stop_space_wait_hold()
		return
	is_space_wait_held = true
	space_wait_elapsed_sec = 0.0
	space_wait_repeated = false


func _stop_space_wait_hold() -> void:
	is_space_wait_held = false
	space_wait_elapsed_sec = 0.0
	space_wait_repeated = false


func _space_wait_result_can_repeat(result: Dictionary) -> bool:
	return bool(result.get("success", false)) and (bool(result.get("waited", false)) or str(result.get("kind", "")) == "wait")


func _space_wait_repeat_allowed() -> bool:
	if _gameplay_input_blocked_by_ui():
		return false
	if game_root.has_method("has_active_dialogue") and bool(game_root.has_active_dialogue()):
		return false
	return not _runtime_has_pending()


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


func clear_selection_state() -> void:
	is_middle_mouse_dragging = false
	has_camera_drag_anchor = false
	_clear_selection_only()
	_clear_skill_target_preview_markers()
	_clear_move_path_preview_markers()
	_update_pending_movement_path_markers()


func update_skill_target_preview_markers(preview: Dictionary) -> void:
	if skill_target_preview_markers == null:
		return
	_clear_skill_target_preview_markers()
	if preview.is_empty():
		return
	var color := HOVER_COLOR_SKILL_VALID if bool(preview.get("success", false)) else HOVER_COLOR_SKILL_BLOCKED
	var skill_id := str(preview.get("skill_id", ""))
	var target_shape := str(preview.get("target_shape", preview.get("shape", "")))
	var cell_count := 0
	for cell in _array_or_empty(preview.get("affected_cells", [])):
		var grid: Dictionary = _dictionary_or_empty(cell)
		if grid.is_empty():
			continue
		var marker := _build_skill_target_cell_marker(color)
		marker.position = Vector3(
			float(grid.get("x", 0)),
			float(grid.get("y", _observed_level())) + 0.16,
			float(grid.get("z", 0))
		)
		marker.set_meta("grid", grid.duplicate(true))
		marker.set_meta("skill_id", skill_id)
		marker.set_meta("target_shape", target_shape)
		marker.set_meta("preview_success", bool(preview.get("success", false)))
		marker.set_meta("reason", str(preview.get("reason", "")))
		skill_target_preview_markers.add_child(marker)
		cell_count += 1
	var actor_count := 0
	for actor_id_value in _array_or_empty(preview.get("affected_actor_ids", [])):
		var actor_id := int(actor_id_value)
		var actor_grid := _actor_grid(actor_id)
		if actor_grid.is_empty():
			continue
		var outline := _build_skill_target_actor_marker(color)
		outline.position = Vector3(
			float(actor_grid.get("x", 0)),
			float(actor_grid.get("y", _observed_level())) + 0.84,
			float(actor_grid.get("z", 0))
		)
		outline.set_meta("actor_id", actor_id)
		outline.set_meta("skill_id", skill_id)
		outline.set_meta("target_shape", target_shape)
		outline.set_meta("preview_success", bool(preview.get("success", false)))
		outline.set_meta("reason", str(preview.get("reason", "")))
		skill_target_preview_markers.add_child(outline)
		actor_count += 1
	skill_target_preview_markers.set_meta("skill_id", skill_id)
	skill_target_preview_markers.set_meta("target_shape", target_shape)
	skill_target_preview_markers.set_meta("preview_success", bool(preview.get("success", false)))
	skill_target_preview_markers.set_meta("reason", str(preview.get("reason", "")))
	skill_target_preview_markers.set_meta("cell_marker_count", cell_count)
	skill_target_preview_markers.set_meta("actor_marker_count", actor_count)


func focus_current_actor() -> void:
	is_camera_following_player = true
	has_camera_drag_anchor = false
	camera_target = _clamp_camera_target(_focused_actor_position())
	_apply_camera_transform()


func has_selection_state() -> bool:
	return selected_node != null or is_middle_mouse_dragging


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
	var point: Variant = _ray_point_on_horizontal_plane(screen_position, float(_observed_level()) + BEVY_DRAG_PLANE_HEIGHT)
	if typeof(point) != TYPE_VECTOR3:
		has_camera_drag_anchor = false
		return
	is_camera_following_player = false
	camera_drag_anchor_world = Vector2((point as Vector3).x, (point as Vector3).z)
	has_camera_drag_anchor = true


func _drag_camera_to_screen_position(screen_position: Vector2) -> void:
	if not has_camera_drag_anchor:
		_begin_camera_drag(screen_position)
		return
	var point: Variant = _ray_point_on_horizontal_plane(screen_position, float(_observed_level()) + BEVY_DRAG_PLANE_HEIGHT)
	if typeof(point) != TYPE_VECTOR3:
		return
	var current := Vector2((point as Vector3).x, (point as Vector3).z)
	var pan_delta := camera_drag_anchor_world - current
	if pan_delta.length_squared() <= 0.000001:
		return
	camera_target = _clamp_camera_target(camera_target + Vector3(pan_delta.x, 0.0, pan_delta.y))
	_apply_camera_transform()


func _zoom_camera_wheel(direction: float) -> void:
	var zoom_multiplier := clampf(1.0 + direction * 0.12, 0.5, 2.0)
	_scale_zoom(zoom_multiplier)


func _scale_zoom(multiplier: float) -> void:
	camera_zoom_factor = clampf(camera_zoom_factor * multiplier, ZOOM_MIN, ZOOM_MAX)
	_apply_camera_transform()


func _apply_camera_transform() -> void:
	if camera == null:
		return
	var distance := _bevy_camera_world_distance(camera_map_size.x, camera_map_size.y, _viewport_size(), camera_zoom_factor)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = BEVY_CAMERA_FOV_DEGREES
	camera.near = 0.1
	camera.far = max(distance * 8.0, 1000.0)
	camera.global_position = camera_target + _bevy_camera_offset(distance)
	camera.look_at(camera_target, Vector3.BACK)
	_sync_camera_focus_meta()


func _bevy_camera_offset(distance: float) -> Vector3:
	var pitch: float = deg_to_rad(BEVY_CAMERA_PITCH_DEGREES)
	var yaw: float = deg_to_rad(BEVY_CAMERA_YAW_DEGREES)
	var horizontal: float = distance * cos(pitch)
	return Vector3(horizontal * sin(yaw), distance * sin(pitch), -horizontal * cos(yaw))


func _bevy_camera_world_distance(width: float, height: float, viewport_size: Vector2, zoom_factor: float) -> float:
	var world_width: float = max(1.0, width) * GRID_SIZE + BEVY_CAMERA_DISTANCE_PADDING_WORLD
	var world_depth: float = max(1.0, height) * GRID_SIZE + BEVY_CAMERA_DISTANCE_PADDING_WORLD
	var usable_width: float = max(160.0, viewport_size.x - BEVY_HUD_RESERVED_WIDTH_PX - BEVY_VIEWPORT_PADDING_PX * 2.0)
	var usable_height: float = max(160.0, viewport_size.y - BEVY_VIEWPORT_PADDING_PX * 2.0)
	var vertical_fov: float = deg_to_rad(BEVY_CAMERA_FOV_DEGREES)
	var aspect: float = max(0.1, usable_width / max(1.0, usable_height))
	var horizontal_fov: float = 2.0 * atan(tan(vertical_fov * 0.5) * aspect)
	var zoom: float = max(0.1, zoom_factor)
	var half_visible_width: float = (world_width / zoom) * 0.5
	var half_visible_depth: float = (world_depth / zoom) * 0.5
	var width_distance: float = half_visible_width / max(0.01, tan(horizontal_fov * 0.5))
	var depth_distance: float = half_visible_depth * max(0.1, sin(deg_to_rad(BEVY_CAMERA_PITCH_DEGREES))) / max(0.01, tan(vertical_fov * 0.5))
	return max(max(width_distance, depth_distance), 10.0 * GRID_SIZE)


func _clamp_camera_target(target: Vector3) -> Vector3:
	var width: float = max(1.0, camera_map_size.x)
	var height: float = max(1.0, camera_map_size.y)
	var center_x: float = width * GRID_SIZE * 0.5
	var center_z: float = height * GRID_SIZE * 0.5
	var distance: float = _bevy_camera_world_distance(width, height, _viewport_size(), camera_zoom_factor)
	var visible: Vector2 = _visible_world_footprint(distance, _viewport_size())
	var half_visible_width: float = visible.x * 0.5
	var half_visible_depth: float = visible.y * 0.5
	var half_cell: float = GRID_SIZE * 0.5
	var focus_min_x: float = min(half_visible_width, half_cell)
	var focus_max_x: float = max(width * GRID_SIZE - half_visible_width, width * GRID_SIZE - half_cell)
	var focus_min_z: float = min(half_visible_depth, half_cell)
	var focus_max_z: float = max(height * GRID_SIZE - half_visible_depth, height * GRID_SIZE - half_cell)
	return Vector3(
		clampf(target.x, focus_min_x, focus_max_x) if focus_min_x <= focus_max_x else center_x,
		_level_plane_height(),
		clampf(target.z, focus_min_z, focus_max_z) if focus_min_z <= focus_max_z else center_z
	)


func _visible_world_footprint(distance: float, viewport_size: Vector2) -> Vector2:
	var usable_width: float = max(160.0, viewport_size.x - BEVY_HUD_RESERVED_WIDTH_PX - BEVY_VIEWPORT_PADDING_PX * 2.0)
	var usable_height: float = max(160.0, viewport_size.y - BEVY_VIEWPORT_PADDING_PX * 2.0)
	var vertical_fov: float = deg_to_rad(BEVY_CAMERA_FOV_DEGREES)
	var aspect: float = max(0.1, usable_width / max(1.0, usable_height))
	var horizontal_fov: float = 2.0 * atan(tan(vertical_fov * 0.5) * aspect)
	var width: float = 2.0 * distance * tan(horizontal_fov * 0.5)
	var depth: float = 2.0 * distance * tan(vertical_fov * 0.5) / max(0.1, sin(deg_to_rad(BEVY_CAMERA_PITCH_DEGREES)))
	return Vector2(width, depth)


func _ray_point_on_horizontal_plane(screen_position: Vector2, plane_height: float) -> Variant:
	if camera == null or not camera.is_inside_tree():
		return null
	var ray_from := camera.project_ray_origin(screen_position)
	var ray_dir := camera.project_ray_normal(screen_position)
	if absf(ray_dir.y) <= 0.0001:
		return null
	var t := (plane_height - ray_from.y) / ray_dir.y
	if t < 0.0:
		return null
	return ray_from + ray_dir * t


func _sync_camera_focus_meta() -> void:
	if camera != null:
		camera.set_meta("focus_position", camera_target)
		camera.set_meta("zoom_factor", camera_zoom_factor)


func _update_hover_cursor(world_position: Vector3) -> void:
	var grid_x := roundf(world_position.x / GRID_SIZE) * GRID_SIZE
	var grid_z := roundf(world_position.z / GRID_SIZE) * GRID_SIZE
	hover_cursor.global_position = Vector3(grid_x, float(_observed_level()) + 0.09, grid_z)
	hover_cursor.visible = true


func _clear_hover(reason: String = "") -> void:
	hover_cursor.visible = false
	_clear_selection_only()
	_set_hover_failure(reason)


func _clear_selection_only() -> void:
	if selected_node == null:
		return
	selected_node = null
	if game_root.has_method("clear_interaction_selection"):
		game_root.clear_interaction_selection()


func _set_hover_ground(world_position: Vector3) -> bool:
	var grid: Dictionary = _grid_from_world_position(world_position)
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
	})


func _set_hover_interaction(target_node: Node, world_position: Vector3) -> bool:
	var metadata: Dictionary = {}
	if target_node != null and target_node.has_meta("interaction_target"):
		var raw: Variant = target_node.get_meta("interaction_target")
		if typeof(raw) == TYPE_DICTIONARY:
			metadata = raw
	metadata = _merge_world_interaction_target(metadata)
	var target_id := str(metadata.get("target_id", ""))
	var target_name := str(metadata.get("target_name", metadata.get("display_name", "")))
	if target_name.is_empty():
		target_name = target_id
	if target_name.is_empty() and target_node != null:
		target_name = str(target_node.name)
	var prompt: Dictionary = _hover_prompt_for_target(metadata)
	var attack_preview: Dictionary = _attack_preview_for_target(metadata)
	var target_category: String = _hover_target_category(metadata, prompt)
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
	})


func _merge_world_interaction_target(metadata: Dictionary) -> Dictionary:
	var target_id := str(metadata.get("target_id", ""))
	if target_id.is_empty():
		return metadata
	var targets: Dictionary = _dictionary_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("interaction_targets", {}))
	var world_target: Dictionary = _dictionary_or_empty(targets.get(target_id, {}))
	if world_target.is_empty():
		return metadata
	var merged: Dictionary = world_target.duplicate(true)
	for key in metadata.keys():
		if key == "door" and world_target.has("door"):
			continue
		merged[key] = metadata[key]
	if not world_target.has("target_kind") and world_target.has("kind"):
		merged["target_kind"] = str(world_target.get("kind", ""))
	return merged


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
	})


func _replace_hover_state(next_state: Dictionary) -> bool:
	if last_hover_state == next_state:
		return false
	last_hover_state = next_state
	return true


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
	if simulation == null or not simulation.has_method("query_interaction_options"):
		return {}
	var player_id := _player_actor_id()
	if player_id <= 0:
		return {}
	var prompt: Dictionary = simulation.query_interaction_options(player_id, target)
	return {
		"ok": bool(prompt.get("ok", false)),
		"reason": str(prompt.get("reason", "")),
		"target_name": str(prompt.get("target_name", "")),
		"primary_option_id": str(prompt.get("primary_option_id", "")),
		"primary_option_kind": str(prompt.get("primary_option_kind", "")),
		"action_label": str(prompt.get("action_label", "")),
		"ap_cost": float(prompt.get("ap_cost", 0.0)),
		"target_distance": int(prompt.get("target_distance", -1)),
		"interaction_range": int(prompt.get("interaction_range", -1)),
		"requires_approach": bool(prompt.get("requires_approach", false)),
		"option_count": _array_or_empty(prompt.get("options", [])).size(),
		"disabled_option_count": _array_or_empty(prompt.get("disabled_options", [])).size(),
	}


func _hover_target_category(target: Dictionary, prompt: Dictionary) -> String:
	var target_type := str(target.get("target_type", ""))
	if target_type == "actor":
		var actor_id := int(target.get("actor_id", 0))
		for actor in _array_or_empty(_runtime_snapshot().get("actors", [])):
			var actor_data: Dictionary = _dictionary_or_empty(actor)
			if int(actor_data.get("actor_id", 0)) == actor_id:
				var side := str(actor_data.get("side", ""))
				if not side.is_empty():
					return "actor:%s" % side
				return "actor"
		return "actor"
	if target_type == "map_object":
		var target_kind := str(target.get("target_kind", target.get("kind", "")))
		if target_kind == "door":
			return "door"
		var prompt_kind := str(prompt.get("primary_option_kind", ""))
		if prompt_kind == "door_toggle":
			return "door"
		if prompt_kind == "open_container":
			return "container"
		if prompt_kind in ["enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor"]:
			return "trigger"
		if not prompt_kind.is_empty():
			return prompt_kind
		return "map_object"
	return target_type if not target_type.is_empty() else "interaction"


func _move_preview_for_grid(grid: Dictionary) -> Dictionary:
	var simulation: Variant = game_root.get("simulation") if game_root != null else null
	if simulation == null or not simulation.has_method("preview_move"):
		return {}
	var player_id := _player_actor_id()
	if player_id <= 0:
		return {}
	var preview: Dictionary = simulation.preview_move(player_id, grid, _dictionary_or_empty(world_result.get("map", {})))
	return {
		"reachable": bool(preview.get("reachable", preview.get("success", false))),
		"reason": str(preview.get("reason", "")),
		"steps": int(preview.get("steps", 0)),
		"path": _array_or_empty(preview.get("path", [])).duplicate(true),
		"ap_cost": float(preview.get("ap_cost", 0.0)),
		"ap_available": float(preview.get("ap_available", 0.0)),
		"ap_affordable": bool(preview.get("ap_affordable", true)),
		"affordable_steps": int(preview.get("affordable_steps", 0)),
		"requires_pending": bool(preview.get("requires_pending", false)),
		"pending_steps": int(preview.get("pending_steps", 0)),
		"target_position": _dictionary_or_empty(preview.get("target_position", grid)).duplicate(true),
		"blocker": _dictionary_or_empty(preview.get("blocker", {})).duplicate(true),
		"visited_cell_count": int(preview.get("visited_cell_count", 0)),
	}


func _attack_preview_for_target(target: Dictionary) -> Dictionary:
	if str(target.get("target_type", "")) != "actor":
		return {}
	var simulation: Variant = game_root.get("simulation") if game_root != null else null
	if simulation == null or not simulation.has_method("preview_attack"):
		return {}
	var player_id := _player_actor_id()
	var target_actor_id := int(target.get("actor_id", 0))
	if player_id <= 0 or target_actor_id <= 0 or player_id == target_actor_id:
		return {}
	var preview: Dictionary = simulation.preview_attack(player_id, target_actor_id, _dictionary_or_empty(world_result.get("map", {})))
	return {
		"can_attack": bool(preview.get("can_attack", preview.get("success", false))),
		"success": bool(preview.get("success", false)),
		"reason": str(preview.get("reason", "")),
		"actor_id": int(preview.get("actor_id", player_id)),
		"target_actor_id": int(preview.get("target_actor_id", target_actor_id)),
		"target_grid": _dictionary_or_empty(preview.get("target_grid", {})).duplicate(true),
		"distance": int(preview.get("distance", -1)),
		"range": int(preview.get("range", -1)),
		"ap_cost": float(preview.get("ap_cost", 0.0)),
		"ap_available": float(preview.get("ap_available", 0.0)),
		"ap_affordable": bool(preview.get("ap_affordable", true)),
		"ammo_available": bool(preview.get("ammo_available", true)),
		"hit_chance": float(preview.get("hit_chance", -1.0)),
		"crit_chance": float(preview.get("crit_chance", 0.0)),
		"estimated_damage": float(preview.get("estimated_damage", 0.0)),
	}


func _apply_hover_cursor_state(move_preview: Dictionary, attack_preview: Dictionary = {}) -> void:
	if hover_cursor == null:
		return
	var color := HOVER_COLOR_INTERACTION
	if not move_preview.is_empty():
		color = HOVER_COLOR_MOVE_REACHABLE if bool(move_preview.get("reachable", false)) else HOVER_COLOR_MOVE_BLOCKED
		hover_cursor.set_meta("move_reachable", bool(move_preview.get("reachable", false)))
		hover_cursor.set_meta("move_steps", int(move_preview.get("steps", 0)))
		hover_cursor.set_meta("move_reason", str(move_preview.get("reason", "")))
		hover_cursor.set_meta("move_ap_cost", float(move_preview.get("ap_cost", 0.0)))
		hover_cursor.set_meta("move_ap_available", float(move_preview.get("ap_available", 0.0)))
		hover_cursor.set_meta("move_ap_affordable", bool(move_preview.get("ap_affordable", true)))
		hover_cursor.set_meta("move_affordable_steps", int(move_preview.get("affordable_steps", 0)))
		hover_cursor.set_meta("move_requires_pending", bool(move_preview.get("requires_pending", false)))
		_update_move_path_preview_markers(move_preview, color)
	else:
		hover_cursor.set_meta("move_reachable", false)
		hover_cursor.set_meta("move_steps", 0)
		hover_cursor.set_meta("move_reason", "")
		hover_cursor.set_meta("move_ap_cost", 0.0)
		hover_cursor.set_meta("move_ap_available", 0.0)
		hover_cursor.set_meta("move_ap_affordable", true)
		hover_cursor.set_meta("move_affordable_steps", 0)
		hover_cursor.set_meta("move_requires_pending", false)
		_clear_move_path_preview_markers()
	if not attack_preview.is_empty():
		color = HOVER_COLOR_ATTACK_REACHABLE if bool(attack_preview.get("can_attack", false)) else HOVER_COLOR_ATTACK_BLOCKED
		hover_cursor.set_meta("attack_can_attack", bool(attack_preview.get("can_attack", false)))
		hover_cursor.set_meta("attack_target_actor_id", int(attack_preview.get("target_actor_id", 0)))
		hover_cursor.set_meta("attack_reason", str(attack_preview.get("reason", "")))
		hover_cursor.set_meta("attack_hit_chance", float(attack_preview.get("hit_chance", -1.0)))
	else:
		hover_cursor.set_meta("attack_can_attack", false)
		hover_cursor.set_meta("attack_target_actor_id", 0)
		hover_cursor.set_meta("attack_reason", "")
		hover_cursor.set_meta("attack_hit_chance", -1.0)
	var material := hover_cursor.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color
	hover_cursor.set_meta("hover_color", color)
	_update_attack_target_marker(attack_preview, color)
	_update_attack_target_outline(attack_preview, color)
	_update_attack_range_markers(attack_preview, color)


func _update_hover_target_outline(target: Dictionary, grid: Dictionary, target_category: String, attack_preview: Dictionary) -> void:
	if hover_target_outline == null:
		return
	if not attack_preview.is_empty():
		_hide_hover_target_outline()
		return
	if target.is_empty() or grid.is_empty():
		_hide_hover_target_outline()
		return
	var color := _hover_outline_color(target_category)
	hover_target_outline.global_position = Vector3(
		float(grid.get("x", 0)),
		float(grid.get("y", _observed_level())) + _hover_outline_height(target_category),
		float(grid.get("z", 0))
	)
	var material := hover_target_outline.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color
	hover_target_outline.visible = true
	hover_target_outline.set_meta("target_type", str(target.get("target_type", "")))
	hover_target_outline.set_meta("target_id", str(target.get("target_id", "")))
	hover_target_outline.set_meta("actor_id", int(target.get("actor_id", 0)))
	hover_target_outline.set_meta("target_category", target_category)
	hover_target_outline.set_meta("hover_color", color)
	var door: Dictionary = _dictionary_or_empty(target.get("door", {}))
	hover_target_outline.set_meta("door_is_open", bool(door.get("is_open", false)))
	hover_target_outline.set_meta("door_locked", bool(door.get("locked", false)))


func _hide_hover_target_outline() -> void:
	if hover_target_outline == null:
		return
	hover_target_outline.visible = false
	hover_target_outline.set_meta("target_type", "")
	hover_target_outline.set_meta("target_id", "")
	hover_target_outline.set_meta("actor_id", 0)
	hover_target_outline.set_meta("target_category", "")
	hover_target_outline.set_meta("door_is_open", false)
	hover_target_outline.set_meta("door_locked", false)


func _hover_outline_color(target_category: String) -> Color:
	if target_category.begins_with("actor"):
		return HOVER_COLOR_ACTOR
	match target_category:
		"pickup":
			return HOVER_COLOR_PICKUP
		"container":
			return HOVER_COLOR_CONTAINER
		"trigger":
			return HOVER_COLOR_TRIGGER
		"door":
			return HOVER_COLOR_DOOR
	return HOVER_COLOR_INTERACTION


func _hover_outline_height(target_category: String) -> float:
	if target_category.begins_with("actor"):
		return 0.82
	return 0.38


func _update_attack_target_marker(attack_preview: Dictionary, color: Color) -> void:
	if attack_target_marker == null:
		return
	if attack_preview.is_empty():
		attack_target_marker.visible = false
		attack_target_marker.set_meta("attack_target_actor_id", 0)
		attack_target_marker.set_meta("attack_can_attack", false)
		return
	var target_grid: Dictionary = _attack_target_grid_from_preview(attack_preview)
	if target_grid.is_empty():
		attack_target_marker.visible = false
		return
	attack_target_marker.global_position = Vector3(
		float(target_grid.get("x", 0)),
		float(target_grid.get("y", _observed_level())) + 1.42,
		float(target_grid.get("z", 0))
	)
	var material := attack_target_marker.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color
	attack_target_marker.visible = true
	attack_target_marker.set_meta("attack_target_actor_id", int(attack_preview.get("target_actor_id", 0)))
	attack_target_marker.set_meta("attack_can_attack", bool(attack_preview.get("can_attack", false)))
	attack_target_marker.set_meta("hover_color", color)


func _update_attack_target_outline(attack_preview: Dictionary, color: Color) -> void:
	if attack_target_outline == null:
		return
	if attack_preview.is_empty():
		attack_target_outline.visible = false
		attack_target_outline.set_meta("attack_target_actor_id", 0)
		attack_target_outline.set_meta("attack_can_attack", false)
		return
	var target_grid: Dictionary = _attack_target_grid_from_preview(attack_preview)
	if target_grid.is_empty():
		attack_target_outline.visible = false
		return
	attack_target_outline.global_position = Vector3(
		float(target_grid.get("x", 0)),
		float(target_grid.get("y", _observed_level())) + 0.82,
		float(target_grid.get("z", 0))
	)
	var material := attack_target_outline.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(color.r, color.g, color.b, 0.24)
	attack_target_outline.visible = true
	attack_target_outline.set_meta("attack_target_actor_id", int(attack_preview.get("target_actor_id", 0)))
	attack_target_outline.set_meta("attack_can_attack", bool(attack_preview.get("can_attack", false)))
	attack_target_outline.set_meta("hover_color", color)


func _update_attack_range_markers(attack_preview: Dictionary, color: Color) -> void:
	if attack_range_markers == null:
		return
	_clear_attack_range_markers()
	if attack_preview.is_empty():
		return
	var target_grid: Dictionary = _dictionary_or_empty(attack_preview.get("target_grid", {}))
	var attack_range: int = int(attack_preview.get("range", -1))
	if target_grid.is_empty() or attack_range < 0:
		return
	var markers := 0
	var candidates: Array[Dictionary] = _attack_range_candidate_grids(target_grid, attack_range)
	for grid in candidates:
		var marker := _build_attack_range_marker(color)
		marker.position = Vector3(
			float(grid.get("x", 0)),
			float(grid.get("y", _observed_level())) + 0.13,
			float(grid.get("z", 0))
		)
		marker.set_meta("grid", grid.duplicate(true))
		marker.set_meta("attack_target_actor_id", int(attack_preview.get("target_actor_id", 0)))
		attack_range_markers.add_child(marker)
		markers += 1
	attack_range_markers.set_meta("marker_count", markers)
	attack_range_markers.set_meta("candidate_count", candidates.size())
	attack_range_markers.set_meta("attack_target_actor_id", int(attack_preview.get("target_actor_id", 0)))


func _attack_target_grid_from_preview(attack_preview: Dictionary) -> Dictionary:
	var target_grid: Dictionary = _dictionary_or_empty(attack_preview.get("target_grid", {}))
	if not target_grid.is_empty():
		return target_grid
	for actor in _array_or_empty(_runtime_snapshot().get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == int(attack_preview.get("target_actor_id", 0)):
			return _dictionary_or_empty(actor_data.get("grid_position", {}))
	return {}


func _attack_range_candidate_grids(target_grid: Dictionary, attack_range: int) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var target_x := int(target_grid.get("x", 0))
	var target_y := int(target_grid.get("y", _observed_level()))
	var target_z := int(target_grid.get("z", 0))
	var bounds: Dictionary = _dictionary_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("bounds", {}))
	var blocking: Dictionary = _dictionary_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("blocking_cells", {}))
	var topology: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	for x in range(target_x - attack_range, target_x + attack_range + 1):
		for z in range(target_z - attack_range, target_z + attack_range + 1):
			var distance: int = abs(x - target_x) + abs(z - target_z)
			if distance > attack_range:
				continue
			var candidate := {"x": x, "y": target_y, "z": z}
			if not _grid_in_bounds(candidate, bounds):
				continue
			var key := "%d:%d:%d" % [x, target_y, z]
			if blocking.has(key):
				continue
			if not _vision_geometry.has_line_of_sight(candidate, target_grid, topology):
				continue
			output.append(candidate)
	return output


func _grid_in_bounds(grid: Dictionary, bounds: Dictionary) -> bool:
	if bounds.is_empty():
		return true
	var x := int(grid.get("x", 0))
	var z := int(grid.get("z", 0))
	return x >= int(bounds.get("min_x", x)) \
		and x <= int(bounds.get("max_x", x)) \
		and z >= int(bounds.get("min_z", z)) \
		and z <= int(bounds.get("max_z", z))


func _clear_attack_range_markers() -> void:
	if attack_range_markers == null:
		return
	for child in attack_range_markers.get_children():
		child.queue_free()
	attack_range_markers.set_meta("marker_count", 0)
	attack_range_markers.set_meta("candidate_count", 0)
	attack_range_markers.set_meta("attack_target_actor_id", 0)


func _update_move_path_preview_markers(move_preview: Dictionary, color: Color) -> void:
	if move_path_preview_markers == null:
		return
	_clear_move_path_preview_markers()
	var path: Array = _array_or_empty(move_preview.get("path", []))
	if path.is_empty():
		return
	var affordable_steps := int(move_preview.get("affordable_steps", path.size()))
	var index := 0
	for cell in path:
		var grid: Dictionary = _dictionary_or_empty(cell)
		if grid.is_empty():
			continue
		var step_index: int = max(0, index)
		var within_current_ap: bool = step_index <= affordable_steps
		var marker_color: Color = color if within_current_ap else HOVER_COLOR_MOVE_PENDING
		var marker := _build_move_path_preview_marker(marker_color, index, path.size())
		marker.position = Vector3(
			float(grid.get("x", 0)),
			float(grid.get("y", _observed_level())) + 0.12,
			float(grid.get("z", 0))
		)
		marker.set_meta("grid", grid.duplicate(true))
		marker.set_meta("path_index", index)
		marker.set_meta("step_cost", step_index)
		marker.set_meta("within_current_ap", within_current_ap)
		marker.set_meta("requires_pending", bool(move_preview.get("requires_pending", false)) and not within_current_ap)
		marker.set_meta("reachable", bool(move_preview.get("reachable", false)))
		marker.set_meta("reason", str(move_preview.get("reason", "")))
		move_path_preview_markers.add_child(marker)
		index += 1
	move_path_preview_markers.set_meta("marker_count", index)
	move_path_preview_markers.set_meta("path_length", path.size())
	move_path_preview_markers.set_meta("reachable", bool(move_preview.get("reachable", false)))
	move_path_preview_markers.set_meta("reason", str(move_preview.get("reason", "")))
	move_path_preview_markers.set_meta("steps", int(move_preview.get("steps", 0)))
	move_path_preview_markers.set_meta("ap_cost", float(move_preview.get("ap_cost", 0.0)))
	move_path_preview_markers.set_meta("ap_available", float(move_preview.get("ap_available", 0.0)))
	move_path_preview_markers.set_meta("ap_affordable", bool(move_preview.get("ap_affordable", true)))
	move_path_preview_markers.set_meta("affordable_steps", affordable_steps)
	move_path_preview_markers.set_meta("requires_pending", bool(move_preview.get("requires_pending", false)))
	move_path_preview_markers.set_meta("pending_steps", int(move_preview.get("pending_steps", 0)))


func _clear_move_path_preview_markers() -> void:
	if move_path_preview_markers == null:
		return
	for child in move_path_preview_markers.get_children():
		child.queue_free()
	move_path_preview_markers.set_meta("marker_count", 0)
	move_path_preview_markers.set_meta("path_length", 0)
	move_path_preview_markers.set_meta("reachable", false)
	move_path_preview_markers.set_meta("reason", "")
	move_path_preview_markers.set_meta("steps", 0)
	move_path_preview_markers.set_meta("ap_cost", 0.0)
	move_path_preview_markers.set_meta("ap_available", 0.0)
	move_path_preview_markers.set_meta("ap_affordable", true)
	move_path_preview_markers.set_meta("affordable_steps", 0)
	move_path_preview_markers.set_meta("requires_pending", false)
	move_path_preview_markers.set_meta("pending_steps", 0)


func _update_pending_movement_path_markers() -> void:
	if pending_movement_path_markers == null:
		return
	var pending: Dictionary = _dictionary_or_empty(_runtime_snapshot().get("pending_movement", {}))
	if pending.is_empty():
		_clear_pending_movement_path_markers()
		return
	var path: Array = _array_or_empty(pending.get("path", []))
	if path.is_empty():
		_clear_pending_movement_path_markers()
		return
	var signature := "%s|%s|%d|%.2f|%.2f" % [
		str(pending.get("actor_id", 0)),
		JSON.stringify(pending.get("target_position", {})),
		path.size(),
		float(pending.get("required_ap", 0.0)),
		float(pending.get("available_ap", 0.0)),
	]
	if str(pending_movement_path_markers.get_meta("signature", "")) == signature:
		return
	_clear_pending_movement_path_markers()
	var index := 0
	for cell in path:
		var grid: Dictionary = _dictionary_or_empty(cell)
		if grid.is_empty():
			continue
		var marker := _build_pending_movement_path_marker(index, path.size())
		marker.position = Vector3(
			float(grid.get("x", 0)),
			float(grid.get("y", _observed_level())) + 0.18,
			float(grid.get("z", 0))
		)
		marker.set_meta("grid", grid.duplicate(true))
		marker.set_meta("path_index", index)
		marker.set_meta("step_cost", max(0, index))
		marker.set_meta("actor_id", int(pending.get("actor_id", 0)))
		marker.set_meta("target_position", _dictionary_or_empty(pending.get("target_position", {})).duplicate(true))
		marker.set_meta("required_ap", float(pending.get("required_ap", 0.0)))
		marker.set_meta("available_ap", float(pending.get("available_ap", 0.0)))
		pending_movement_path_markers.add_child(marker)
		index += 1
	pending_movement_path_markers.set_meta("signature", signature)
	pending_movement_path_markers.set_meta("marker_count", index)
	pending_movement_path_markers.set_meta("path_length", path.size())
	pending_movement_path_markers.set_meta("actor_id", int(pending.get("actor_id", 0)))
	pending_movement_path_markers.set_meta("target_position", _dictionary_or_empty(pending.get("target_position", {})).duplicate(true))
	pending_movement_path_markers.set_meta("required_ap", float(pending.get("required_ap", 0.0)))
	pending_movement_path_markers.set_meta("available_ap", float(pending.get("available_ap", 0.0)))
	pending_movement_path_markers.set_meta("remaining_steps", max(0, path.size() - 1))


func _clear_pending_movement_path_markers() -> void:
	if pending_movement_path_markers == null:
		return
	for child in pending_movement_path_markers.get_children():
		child.queue_free()
	pending_movement_path_markers.set_meta("signature", "")
	pending_movement_path_markers.set_meta("marker_count", 0)
	pending_movement_path_markers.set_meta("path_length", 0)
	pending_movement_path_markers.set_meta("actor_id", 0)
	pending_movement_path_markers.set_meta("target_position", {})
	pending_movement_path_markers.set_meta("required_ap", 0.0)
	pending_movement_path_markers.set_meta("available_ap", 0.0)
	pending_movement_path_markers.set_meta("remaining_steps", 0)


func _player_actor_id() -> int:
	for actor in _array_or_empty(_runtime_snapshot().get("actors", [])):
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
	if game_root.has_method("focused_actor_grid_position"):
		var focused_grid: Dictionary = _dictionary_or_empty(game_root.focused_actor_grid_position())
		if not focused_grid.is_empty():
			return Vector3(
				float(focused_grid.get("x", 0)),
				float(focused_grid.get("y", _observed_level())) + BEVY_LEVEL_PLANE_HEIGHT,
				float(focused_grid.get("z", 0))
			)
	return _map_center_focus_position()


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


func _build_hover_cursor() -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.92, 0.045, 0.92)
	var material := StandardMaterial3D.new()
	material.albedo_color = HOVER_COLOR_INTERACTION
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "HoverGridCursor"
	node.mesh = mesh
	node.material_override = material
	node.visible = false
	return node


func _build_hover_target_outline() -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.50
	mesh.bottom_radius = 0.50
	mesh.height = 0.72
	mesh.radial_segments = 20
	var material := StandardMaterial3D.new()
	material.albedo_color = HOVER_COLOR_INTERACTION
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "HoverTargetOutline"
	node.mesh = mesh
	node.material_override = material
	node.visible = false
	return node


func _build_attack_target_marker() -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.38
	mesh.outer_radius = 0.48
	var material := StandardMaterial3D.new()
	material.albedo_color = HOVER_COLOR_ATTACK_REACHABLE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "AttackTargetMarker"
	node.mesh = mesh
	node.material_override = material
	node.visible = false
	node.rotation_degrees.x = 90.0
	return node


func _build_attack_target_outline() -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.48
	mesh.bottom_radius = 0.48
	mesh.height = 1.48
	mesh.radial_segments = 24
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(HOVER_COLOR_ATTACK_REACHABLE.r, HOVER_COLOR_ATTACK_REACHABLE.g, HOVER_COLOR_ATTACK_REACHABLE.b, 0.24)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "AttackTargetOutline"
	node.mesh = mesh
	node.material_override = material
	node.visible = false
	return node


func _build_attack_range_marker(color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.66, 0.035, 0.66)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.34)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "AttackRangeMarker"
	node.mesh = mesh
	node.material_override = material
	return node


func _build_move_path_preview_marker(color: Color, index: int, path_length: int) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	var width := 0.42 if index == 0 or index == path_length - 1 else 0.34
	mesh.size = Vector3(width, 0.032, width)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.30)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "MovePathPreviewMarker"
	node.mesh = mesh
	node.material_override = material
	return node


func _build_pending_movement_path_marker(index: int, path_length: int) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	var width := 0.50 if index == path_length - 1 else 0.38
	mesh.size = Vector3(width, 0.036, width)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(HOVER_COLOR_MOVE_PENDING.r, HOVER_COLOR_MOVE_PENDING.g, HOVER_COLOR_MOVE_PENDING.b, 0.34)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "PendingMovementPathMarker"
	node.mesh = mesh
	node.material_override = material
	return node


func _build_skill_target_cell_marker(color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.78, 0.04, 0.78)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "SkillTargetCellMarker"
	node.mesh = mesh
	node.material_override = material
	return node


func _build_skill_target_actor_marker(color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.52
	mesh.bottom_radius = 0.52
	mesh.height = 1.50
	mesh.radial_segments = 24
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, minf(0.32, color.a))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "SkillTargetActorMarker"
	node.mesh = mesh
	node.material_override = material
	return node


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


func _interaction_menu_open() -> bool:
	return game_root.hud != null and game_root.hud.has_method("is_interaction_menu_open") and bool(game_root.hud.is_interaction_menu_open())


func _runtime_has_pending() -> bool:
	var simulation: Variant = game_root.get("simulation") if game_root != null else null
	if simulation == null:
		return false
	var snapshot: Dictionary = simulation.snapshot()
	return not _dictionary_or_empty(snapshot.get("pending_movement", {})).is_empty() or not _dictionary_or_empty(snapshot.get("pending_interaction", {})).is_empty()


func _actor_grid(actor_id: int) -> Dictionary:
	for actor in _array_or_empty(_runtime_snapshot().get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return _dictionary_or_empty(actor_data.get("grid_position", {})).duplicate(true)
	return {}


func _clear_skill_target_preview_markers() -> void:
	if skill_target_preview_markers == null:
		return
	for child in skill_target_preview_markers.get_children():
		child.queue_free()
	skill_target_preview_markers.set_meta("skill_id", "")
	skill_target_preview_markers.set_meta("target_shape", "")
	skill_target_preview_markers.set_meta("preview_success", false)
	skill_target_preview_markers.set_meta("reason", "")
	skill_target_preview_markers.set_meta("cell_marker_count", 0)
	skill_target_preview_markers.set_meta("actor_marker_count", 0)


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


func _vector_meta(node: Node, key: String, fallback: Vector3) -> Vector3:
	if node != null and node.has_meta(key):
		var value: Variant = node.get_meta(key)
		if typeof(value) == TYPE_VECTOR3:
			return value
	return fallback


func _vector2_meta(node: Node, key: String, fallback: Vector2) -> Vector2:
	if node != null and node.has_meta(key):
		var value: Variant = node.get_meta(key)
		if typeof(value) == TYPE_VECTOR2:
			return value
	return fallback


func _float_meta(node: Node, key: String, fallback: float) -> float:
	if node != null and node.has_meta(key):
		var value: Variant = node.get_meta(key)
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			return float(value)
	return fallback


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
