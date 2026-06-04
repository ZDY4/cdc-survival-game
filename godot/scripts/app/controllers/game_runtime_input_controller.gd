extends RefCounted

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

var game_root: Node
var world_container: Node3D
var world_result: Dictionary = {}
var camera: Camera3D
var hover_cursor: MeshInstance3D
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
}


func _init(p_game_root: Node) -> void:
	game_root = p_game_root
	hover_cursor = _build_hover_cursor()
	game_root.add_child(hover_cursor)


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
	var interaction_hover := {"success": true, "kind": "interaction", "node": target_node}
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
	var digit := _digit_for_key(key)
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
	if _gameplay_input_blocked_by_ui():
		return false
	if game_root.has_method("use_hotbar_slot"):
		var slot_id := "slot_%d" % (10 if digit == 10 else digit)
		game_root.use_hotbar_slot(slot_id)
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
	})


func _set_hover_interaction(target_node: Node, world_position: Vector3) -> bool:
	var metadata: Dictionary = {}
	if target_node != null and target_node.has_meta("interaction_target"):
		var raw: Variant = target_node.get_meta("interaction_target")
		if typeof(raw) == TYPE_DICTIONARY:
			metadata = raw
	var target_id := str(metadata.get("target_id", ""))
	var target_name := str(metadata.get("target_name", metadata.get("display_name", "")))
	if target_name.is_empty():
		target_name = target_id
	if target_name.is_empty() and target_node != null:
		target_name = str(target_node.name)
	var prompt: Dictionary = _hover_prompt_for_target(metadata)
	_apply_hover_cursor_state({})
	return _replace_hover_state({
		"active": true,
		"kind": "interaction",
		"grid": _grid_from_world_position(world_position),
		"target_name": target_name,
		"target_type": str(metadata.get("target_type", "")),
		"target_category": _hover_target_category(metadata, prompt),
		"target_id": target_id,
		"actor_id": int(metadata.get("actor_id", 0)),
		"ui_blocker": _hover_ui_blocker_name(),
		"reason": "",
		"prompt": prompt,
		"move_preview": {},
	})


func _set_hover_failure(reason: String = "") -> bool:
	_apply_hover_cursor_state({})
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
		var prompt_kind := str(prompt.get("primary_option_kind", ""))
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
		"target_position": _dictionary_or_empty(preview.get("target_position", grid)).duplicate(true),
		"blocker": _dictionary_or_empty(preview.get("blocker", {})).duplicate(true),
		"visited_cell_count": int(preview.get("visited_cell_count", 0)),
	}


func _apply_hover_cursor_state(move_preview: Dictionary) -> void:
	if hover_cursor == null:
		return
	var color := HOVER_COLOR_INTERACTION
	if not move_preview.is_empty():
		color = HOVER_COLOR_MOVE_REACHABLE if bool(move_preview.get("reachable", false)) else HOVER_COLOR_MOVE_BLOCKED
		hover_cursor.set_meta("move_reachable", bool(move_preview.get("reachable", false)))
		hover_cursor.set_meta("move_steps", int(move_preview.get("steps", 0)))
		hover_cursor.set_meta("move_reason", str(move_preview.get("reason", "")))
	else:
		hover_cursor.set_meta("move_reachable", false)
		hover_cursor.set_meta("move_steps", 0)
		hover_cursor.set_meta("move_reason", "")
	var material := hover_cursor.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color
	hover_cursor.set_meta("hover_color", color)


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
		return
	var target: Dictionary = _skill_target_from_hover(hover_result)
	if target.is_empty():
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
