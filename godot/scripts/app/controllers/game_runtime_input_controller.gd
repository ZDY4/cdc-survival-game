extends RefCounted

const GRID_SIZE := 1.0
const RAY_DISTANCE := 500.0
const CAMERA_MOVE_SPEED := 12.0
const CAMERA_DRAG_SPEED := 0.035

var game_root: Node
var world_container: Node3D
var world_result: Dictionary = {}
var camera: Camera3D
var hover_cursor: MeshInstance3D
var selected_node: Node
var camera_target: Vector3 = Vector3.ZERO
var camera_key_state: Dictionary = {}
var is_middle_mouse_dragging := false


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
	hover_cursor.visible = false
	selected_node = null


func process(delta: float) -> void:
	if camera == null:
		return
	_process_keyboard_camera(delta)
	if _mouse_inside_viewport():
		update_hover_at_screen_position(game_root.get_viewport().get_mouse_position())


func input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventKey:
		_update_camera_key_state(event as InputEventKey)


func unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventKey:
		_update_camera_key_state(event as InputEventKey)
	elif event is InputEventMouseMotion:
		if is_middle_mouse_dragging:
			_drag_camera((event as InputEventMouseMotion).relative)
		else:
			update_hover_at_screen_position((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			is_middle_mouse_dragging = mouse_event.pressed
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			update_hover_at_screen_position(mouse_event.position)
			if selected_node != null and game_root.has_method("execute_primary_interaction"):
				game_root.execute_primary_interaction()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom_camera(-1.0)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom_camera(1.0)


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


func _process_keyboard_camera(delta: float) -> void:
	var direction := _camera_keyboard_direction()
	if direction.is_zero_approx():
		return
	_move_camera(direction.normalized() * CAMERA_MOVE_SPEED * delta)


func _camera_keyboard_direction() -> Vector3:
	var direction := Vector3.ZERO
	if bool(camera_key_state.get(KEY_W, false)) or bool(camera_key_state.get(KEY_UP, false)) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.z -= 1.0
	if bool(camera_key_state.get(KEY_S, false)) or bool(camera_key_state.get(KEY_DOWN, false)) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.z += 1.0
	if bool(camera_key_state.get(KEY_A, false)) or bool(camera_key_state.get(KEY_LEFT, false)) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if bool(camera_key_state.get(KEY_D, false)) or bool(camera_key_state.get(KEY_RIGHT, false)) or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	return direction


func _update_camera_key_state(event: InputEventKey) -> void:
	var key := event.keycode
	if key == 0:
		key = event.physical_keycode
	if not [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT].has(key):
		return
	camera_key_state[key] = event.pressed and not event.echo


func _move_camera(delta_world: Vector3) -> void:
	camera.global_position += delta_world
	camera_target += delta_world
	camera.look_at(camera_target, Vector3.UP)


func _drag_camera(relative: Vector2) -> void:
	_move_camera(Vector3(relative.x, 0.0, relative.y) * CAMERA_DRAG_SPEED)


func _zoom_camera(direction: float) -> void:
	var forward := (camera_target - camera.global_position).normalized()
	var next_position := camera.global_position + forward * direction * 2.0
	if next_position.distance_to(camera_target) < 6.0 or next_position.distance_to(camera_target) > 60.0:
		return
	camera.global_position = next_position
	camera.look_at(camera_target, Vector3.UP)


func _update_hover_cursor(world_position: Vector3) -> void:
	var grid_x := roundf(world_position.x / GRID_SIZE) * GRID_SIZE
	var grid_z := roundf(world_position.z / GRID_SIZE) * GRID_SIZE
	hover_cursor.global_position = Vector3(grid_x, 0.045, grid_z)
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
			return Vector3(float(grid.get("x", 0)), 0.0, float(grid.get("z", 0)))
	return Vector3.ZERO


func _build_hover_cursor() -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.92, 0.035, 0.92)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.82, 0.18, 0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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


func _vector_meta(node: Node, key: String, fallback: Vector3) -> Vector3:
	if node != null and node.has_meta(key):
		var value: Variant = node.get_meta(key)
		if typeof(value) == TYPE_VECTOR3:
			return value
	return fallback


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
