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
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0

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
	camera_target = _vector_meta(camera, "focus_position", _player_focus_position())
	camera_target.y = BEVY_LEVEL_PLANE_HEIGHT
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
	if is_camera_following_player and not is_middle_mouse_dragging:
		camera_target = _clamp_camera_target(_player_focus_position())
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
		if _gameplay_input_blocked_by_ui() or _mouse_over_blocking_ui():
			return
		if _handle_mouse_button(event as InputEventMouseButton):
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
		if _gameplay_input_blocked_by_ui():
			return
		_handle_mouse_button(event as InputEventMouseButton)


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


func update_hover_at_screen_position(screen_position: Vector2) -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		return {"success": false, "reason": "camera_missing"}

	var ray_from := camera.project_ray_origin(screen_position)
	var ray_to := ray_from + camera.project_ray_normal(screen_position) * RAY_DISTANCE
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		_clear_hover()
		return {"success": false, "reason": "no_hit"}

	var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
	_update_hover_cursor(hit_position)
	var collider: Object = hit.get("collider", null)
	var target_node := _interaction_node(collider as Node)
	if target_node == null:
		_clear_selection_only()
		return {"success": true, "kind": "ground", "position": hit_position}

	if selected_node != target_node and game_root.has_method("select_interaction_node"):
		selected_node = target_node
		game_root.select_interaction_node(target_node)
	return {"success": true, "kind": "interaction", "node": target_node}


func _handle_camera_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	var key := event.keycode
	if key == 0:
		key = event.physical_keycode
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
		is_camera_following_player = true
		has_camera_drag_anchor = false
		camera_target = _clamp_camera_target(_player_focus_position())
		_apply_camera_transform()
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
		if game_root.has_method("press_space_action"):
			game_root.press_space_action()
		if game_root.hud != null and game_root.hud.has_method("hide_interaction_menu"):
			game_root.hud.hide_interaction_menu()
		return true
	return false


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


func has_selection_state() -> bool:
	return selected_node != null or is_middle_mouse_dragging


func _stage_panel_for_key(key: int) -> String:
	match key:
		KEY_I:
			return "inventory"
		KEY_C:
			return "character"
		KEY_J:
			return "journal"
		KEY_M:
			return "map"
		KEY_K:
			return "skills"
		KEY_L:
			return "crafting"
		_:
			return ""


func _begin_camera_drag(screen_position: Vector2) -> void:
	var point: Variant = _ray_point_on_horizontal_plane(screen_position, BEVY_DRAG_PLANE_HEIGHT)
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
	var point: Variant = _ray_point_on_horizontal_plane(screen_position, BEVY_DRAG_PLANE_HEIGHT)
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
		BEVY_LEVEL_PLANE_HEIGHT,
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
	hover_cursor.global_position = Vector3(grid_x, 0.09, grid_z)
	hover_cursor.visible = true


func _clear_hover() -> void:
	hover_cursor.visible = false
	_clear_selection_only()


func _clear_selection_only() -> void:
	if selected_node == null:
		return
	selected_node = null
	if game_root.has_method("clear_interaction_selection"):
		game_root.clear_interaction_selection()


func _grid_from_world_position(world_position: Vector3) -> Dictionary:
	return {
		"x": int(roundf(world_position.x / GRID_SIZE)),
		"y": 0,
		"z": int(roundf(world_position.z / GRID_SIZE)),
	}


func _interaction_node(node: Node) -> Node:
	var current := node
	while current != null:
		if current.has_meta("interaction_target"):
			return current
		current = current.get_parent()
	return null


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


func _player_focus_position() -> Vector3:
	for actor in _array_or_empty(world_result.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if actor_data.get("kind", "") == "player":
			var grid: Dictionary = _dictionary_or_empty(actor_data.get("grid_position", {}))
			return Vector3(float(grid.get("x", 0)), BEVY_LEVEL_PLANE_HEIGHT, float(grid.get("z", 0)))
	return Vector3(0.0, BEVY_LEVEL_PLANE_HEIGHT, 0.0)


func _build_hover_cursor() -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.92, 0.045, 0.92)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.82, 0.18, 0.72)
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
