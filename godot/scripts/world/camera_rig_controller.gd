extends RefCounted

const GRID_SIZE := 1.0
const BEVY_CAMERA_YAW_DEGREES := 0.0
const BEVY_CAMERA_PITCH_DEGREES := 36.0
const BEVY_CAMERA_FOV_DEGREES := 30.0
const BEVY_CAMERA_DISTANCE_PADDING_WORLD := 8.0
const BEVY_VIEWPORT_PADDING_PX := 72.0
const BEVY_HUD_RESERVED_WIDTH_PX := 620.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0

var camera: Camera3D
var target: Vector3 = Vector3.ZERO
var drag_anchor_world: Vector2 = Vector2.ZERO
var has_drag_anchor := false
var is_dragging := false
var zoom_factor := 1.0
var map_size := Vector2(48.0, 42.0)
var following_focus := true


func attach(p_camera: Camera3D, focus_position: Vector3, p_map_size: Vector2, viewport_size: Vector2, level_plane_height: float) -> bool:
	camera = p_camera
	if camera == null:
		return false
	map_size = p_map_size
	target = _vector_meta(camera, "focus_position", focus_position)
	target.y = level_plane_height
	zoom_factor = _float_meta(camera, "zoom_factor", 1.0)
	following_focus = true
	is_dragging = false
	has_drag_anchor = false
	_sync_camera_focus_meta()
	_apply_camera_transform(viewport_size, level_plane_height)
	return true


func process_follow(focus_position: Vector3, viewport_size: Vector2, level_plane_height: float) -> bool:
	if camera == null or not following_focus or is_dragging:
		return false
	var follow_target := _clamp_target(focus_position, viewport_size, level_plane_height)
	if target.distance_squared_to(follow_target) <= 0.000001:
		return false
	target = follow_target
	_apply_camera_transform(viewport_size, level_plane_height)
	return true


func clear_drag_state() -> void:
	is_dragging = false
	has_drag_anchor = false


func begin_drag(screen_position: Vector2, plane_height: float) -> bool:
	var point: Variant = ray_point_on_horizontal_plane(screen_position, plane_height)
	if typeof(point) != TYPE_VECTOR3:
		has_drag_anchor = false
		return false
	following_focus = false
	drag_anchor_world = Vector2((point as Vector3).x, (point as Vector3).z)
	has_drag_anchor = true
	return true


func end_drag() -> void:
	is_dragging = false
	has_drag_anchor = false


func drag_to_screen_position(screen_position: Vector2, plane_height: float, viewport_size: Vector2, level_plane_height: float) -> bool:
	if not has_drag_anchor:
		return begin_drag(screen_position, plane_height)
	var point: Variant = ray_point_on_horizontal_plane(screen_position, plane_height)
	if typeof(point) != TYPE_VECTOR3:
		return false
	var current := Vector2((point as Vector3).x, (point as Vector3).z)
	var pan_delta := drag_anchor_world - current
	if pan_delta.length_squared() <= 0.000001:
		return false
	target = _clamp_target(target + Vector3(pan_delta.x, 0.0, pan_delta.y), viewport_size, level_plane_height)
	_apply_camera_transform(viewport_size, level_plane_height)
	return true


func zoom_wheel(direction: float, viewport_size: Vector2, level_plane_height: float) -> bool:
	var zoom_multiplier := clampf(1.0 + direction * 0.12, 0.5, 2.0)
	return scale_zoom(zoom_multiplier, viewport_size, level_plane_height)


func scale_zoom(multiplier: float, viewport_size: Vector2, level_plane_height: float) -> bool:
	zoom_factor = clampf(zoom_factor * multiplier, ZOOM_MIN, ZOOM_MAX)
	_apply_camera_transform(viewport_size, level_plane_height)
	return true


func reset_zoom(viewport_size: Vector2, level_plane_height: float) -> void:
	zoom_factor = 1.0
	_apply_camera_transform(viewport_size, level_plane_height)


func focus(focus_position: Vector3, viewport_size: Vector2, level_plane_height: float) -> void:
	following_focus = true
	has_drag_anchor = false
	target = _clamp_target(focus_position, viewport_size, level_plane_height)
	_apply_camera_transform(viewport_size, level_plane_height)


func ray_point_on_horizontal_plane(screen_position: Vector2, plane_height: float) -> Variant:
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


func _apply_camera_transform(viewport_size: Vector2, level_plane_height: float) -> void:
	if camera == null:
		return
	var distance := _camera_world_distance(map_size.x, map_size.y, viewport_size, zoom_factor)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = BEVY_CAMERA_FOV_DEGREES
	camera.near = 0.1
	camera.far = max(distance * 8.0, 1000.0)
	target.y = level_plane_height
	camera.global_position = target + _camera_offset(distance)
	camera.look_at(target, Vector3.BACK)
	_sync_camera_focus_meta()


func _camera_offset(distance: float) -> Vector3:
	var pitch: float = deg_to_rad(BEVY_CAMERA_PITCH_DEGREES)
	var yaw: float = deg_to_rad(BEVY_CAMERA_YAW_DEGREES)
	var horizontal: float = distance * cos(pitch)
	return Vector3(horizontal * sin(yaw), distance * sin(pitch), -horizontal * cos(yaw))


func _camera_world_distance(width: float, height: float, viewport_size: Vector2, zoom: float) -> float:
	var world_width: float = max(1.0, width) * GRID_SIZE + BEVY_CAMERA_DISTANCE_PADDING_WORLD
	var world_depth: float = max(1.0, height) * GRID_SIZE + BEVY_CAMERA_DISTANCE_PADDING_WORLD
	var usable_width: float = max(160.0, viewport_size.x - BEVY_HUD_RESERVED_WIDTH_PX - BEVY_VIEWPORT_PADDING_PX * 2.0)
	var usable_height: float = max(160.0, viewport_size.y - BEVY_VIEWPORT_PADDING_PX * 2.0)
	var vertical_fov: float = deg_to_rad(BEVY_CAMERA_FOV_DEGREES)
	var aspect: float = max(0.1, usable_width / max(1.0, usable_height))
	var horizontal_fov: float = 2.0 * atan(tan(vertical_fov * 0.5) * aspect)
	var normalized_zoom: float = max(0.1, zoom)
	var half_visible_width: float = (world_width / normalized_zoom) * 0.5
	var half_visible_depth: float = (world_depth / normalized_zoom) * 0.5
	var width_distance: float = half_visible_width / max(0.01, tan(horizontal_fov * 0.5))
	var depth_distance: float = half_visible_depth * max(0.1, sin(deg_to_rad(BEVY_CAMERA_PITCH_DEGREES))) / max(0.01, tan(vertical_fov * 0.5))
	return max(max(width_distance, depth_distance), 10.0 * GRID_SIZE)


func _clamp_target(next_target: Vector3, viewport_size: Vector2, level_plane_height: float) -> Vector3:
	var width: float = max(1.0, map_size.x)
	var height: float = max(1.0, map_size.y)
	var center_x: float = width * GRID_SIZE * 0.5
	var center_z: float = height * GRID_SIZE * 0.5
	var distance: float = _camera_world_distance(width, height, viewport_size, zoom_factor)
	var visible: Vector2 = _visible_world_footprint(distance, viewport_size)
	var half_visible_width: float = visible.x * 0.5
	var half_visible_depth: float = visible.y * 0.5
	var half_cell: float = GRID_SIZE * 0.5
	var focus_min_x: float = min(half_visible_width, half_cell)
	var focus_max_x: float = max(width * GRID_SIZE - half_visible_width, width * GRID_SIZE - half_cell)
	var focus_min_z: float = min(half_visible_depth, half_cell)
	var focus_max_z: float = max(height * GRID_SIZE - half_visible_depth, height * GRID_SIZE - half_cell)
	return Vector3(
		clampf(next_target.x, focus_min_x, focus_max_x) if focus_min_x <= focus_max_x else center_x,
		level_plane_height,
		clampf(next_target.z, focus_min_z, focus_max_z) if focus_min_z <= focus_max_z else center_z
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


func _sync_camera_focus_meta() -> void:
	if camera != null:
		camera.set_meta("focus_position", target)
		camera.set_meta("zoom_factor", zoom_factor)


func _vector_meta(node: Node, key: String, fallback: Vector3) -> Vector3:
	if node != null and node.has_meta(key):
		var value: Variant = node.get_meta(key)
		if typeof(value) == TYPE_VECTOR3:
			return value
	return fallback


func _float_meta(node: Node, key: String, fallback: float) -> float:
	if node != null and node.has_meta(key):
		var value: Variant = node.get_meta(key)
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			return float(value)
	return fallback
