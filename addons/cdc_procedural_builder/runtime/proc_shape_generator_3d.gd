@tool
class_name ProcShapeGenerator3D
extends Node3D

signal rebuilt

const PREVIEW_MESH_NAME: String = "PreviewMesh"
const COLLISION_ROOT_NAME: String = "CollisionRoot"
const DEBUG_OVERLAY_NAME: String = "DebugOverlay"

@export var control_points: Array[Vector3] = []:
	set = set_control_points
@export var closed: bool = false:
	set = set_closed
@export var snap_enabled: bool = true:
	set = set_snap_enabled
@export_range(0.1, 10.0, 0.1, "or_greater") var snap_step: float = 1.0:
	set = set_snap_step
@export var auto_rebuild: bool = true:
	set = set_auto_rebuild
@export var generate_collision: bool = true:
	set = set_generate_collision
@export var block_grid_navigation: bool = true:
	set = set_block_grid_navigation
@export var show_blocked_cells_in_editor: bool = true:
	set = set_show_blocked_cells_in_editor
@export var material_override: Material:
	set = set_material_override

var _preview_mesh: MeshInstance3D = null
var _collision_root: StaticBody3D = null
var _debug_overlay: MeshInstance3D = null
var _last_warnings: PackedStringArray = PackedStringArray()
var _last_build_info: Dictionary = {}
var _last_collision_boxes: Array = []
var _blocked_grid_cells: Array[Vector3i] = [Vector3i.ZERO]
var _registered_grid_cells: Array[Vector3i] = [Vector3i.ZERO]
var _pending_rebuild: bool = false

func _enter_tree() -> void:
	set_notify_transform(true)
	_ensure_default_points()
	_ensure_internal_nodes()
	call_deferred("rebuild_geometry")

func _ready() -> void:
	_ensure_internal_nodes()
	if auto_rebuild:
		call_deferred("rebuild_geometry")

func _get_configuration_warnings() -> PackedStringArray:
	return _last_warnings

func set_control_points(value: Array) -> void:
	control_points = _sanitize_points(value)
	if not can_use_closed_shape():
		closed = _requires_closed_shape()
	_notify_editor_property_change()
	_request_rebuild()

func set_closed(value: bool) -> void:
	closed = _requires_closed_shape() or (value and can_edit_closed_state())
	_notify_editor_property_change()
	_request_rebuild()

func set_snap_enabled(value: bool) -> void:
	snap_enabled = value
	_notify_editor_property_change()
	_request_rebuild()

func set_snap_step(value: float) -> void:
	snap_step = maxf(value, 0.1)
	_notify_editor_property_change()
	_request_rebuild()

func set_auto_rebuild(value: bool) -> void:
	auto_rebuild = value
	_notify_editor_property_change()
	if auto_rebuild:
		_request_rebuild()

func set_generate_collision(value: bool) -> void:
	generate_collision = value
	_notify_editor_property_change()
	_request_rebuild()

func set_block_grid_navigation(value: bool) -> void:
	block_grid_navigation = value
	_notify_editor_property_change()
	_update_blocked_grid_cells()
	if Engine.is_editor_hint():
		update_gizmos()

func set_show_blocked_cells_in_editor(value: bool) -> void:
	show_blocked_cells_in_editor = value
	_notify_editor_property_change()
	if Engine.is_editor_hint():
		update_gizmos()

func set_material_override(value: Material) -> void:
	material_override = value
	_notify_editor_property_change()
	if _preview_mesh:
		_preview_mesh.material_override = material_override if material_override != null else _build_default_material()

func get_preview_mesh_instance() -> MeshInstance3D:
	_ensure_internal_nodes()
	return _preview_mesh

func get_collision_root() -> StaticBody3D:
	_ensure_internal_nodes()
	return _collision_root

func get_debug_overlay() -> MeshInstance3D:
	_ensure_internal_nodes()
	return _debug_overlay

func get_last_build_info() -> Dictionary:
	return _last_build_info.duplicate(true)

func get_blocked_grid_cells_copy() -> Array[Vector3i]:
	return _blocked_grid_cells.duplicate()

func get_control_point(index: int) -> Vector3:
	if index < 0 or index >= control_points.size():
		return Vector3.ZERO
	return control_points[index]

func get_control_points_copy() -> Array:
	return control_points.duplicate()

func can_edit_closed_state() -> bool:
	return _supports_closed_toggle() and not _requires_closed_shape() and control_points.size() >= 3

func can_use_closed_shape() -> bool:
	return _requires_closed_shape() or (_supports_closed_toggle() and control_points.size() >= 3)

func get_minimum_point_count() -> int:
	return 2

func get_segment_count() -> int:
	if control_points.size() < 2:
		return 0
	if _requires_closed_shape() or closed:
		return control_points.size()
	return control_points.size() - 1

func get_segment_points(segment_index: int) -> Array:
	if segment_index < 0 or segment_index >= get_segment_count():
		return []
	var start_point: Vector3 = control_points[segment_index]
	var end_index: int = (segment_index + 1) % control_points.size()
	var end_point: Vector3 = control_points[end_index]
	return [start_point, end_point]

func get_debug_line_points() -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	if control_points.size() < 2:
		return points

	for index in range(get_segment_count()):
		var segment_points: Array = get_segment_points(index)
		if segment_points.size() != 2:
			continue
		points.append(segment_points[0])
		points.append(segment_points[1])
	return points

func set_control_point(index: int, value: Vector3) -> void:
	if index < 0 or index >= control_points.size():
		return
	var updated_points: Array = get_control_points_copy()
	updated_points[index] = snap_point(value)
	set_control_points(updated_points)

func append_control_point(value: Vector3) -> void:
	var updated_points: Array = control_points.duplicate()
	updated_points.append(snap_point(value))
	set_control_points(updated_points)

func insert_control_point(segment_index: int, value: Vector3) -> void:
	var insert_index: int = clampi(segment_index + 1, 0, control_points.size())
	var updated_points: Array = control_points.duplicate()
	updated_points.insert(insert_index, snap_point(value))
	set_control_points(updated_points)

func remove_control_point(index: int) -> void:
	if control_points.size() <= get_minimum_point_count():
		return
	if index < 0 or index >= control_points.size():
		return
	var updated_points: Array = control_points.duplicate()
	updated_points.remove_at(index)
	set_control_points(updated_points)

func snap_point(value: Vector3) -> Vector3:
	if not snap_enabled:
		return value
	return ProcGeometryUtils.snap_vector(value, snap_step)

func rebuild_geometry() -> void:
	_pending_rebuild = false
	_ensure_default_points()
	_ensure_internal_nodes()
	_clear_collision_shapes()

	var build_result: Dictionary = _build_geometry()
	_last_build_info = build_result.get("build_info", {}).duplicate(true)
	_last_warnings = PackedStringArray(build_result.get("warnings", PackedStringArray()))
	_last_collision_boxes = build_result.get("collision_boxes", []).duplicate(true)
	update_configuration_warnings()

	var mesh: Mesh = build_result.get("mesh", null)
	if _preview_mesh:
		_preview_mesh.mesh = mesh
		_preview_mesh.material_override = material_override if material_override != null else _build_default_material()

	var debug_mesh: Mesh = build_result.get("debug_mesh", null)
	if _debug_overlay:
		_debug_overlay.mesh = debug_mesh
		_debug_overlay.material_override = _build_debug_material()

	if generate_collision:
		var collision_shape: Shape3D = build_result.get("collision_shape", null)
		if collision_shape != null:
			var collision_shape_node: CollisionShape3D = CollisionShape3D.new()
			collision_shape_node.shape = collision_shape
			_collision_root.add_child(collision_shape_node)
		else:
			for box_data_variant in build_result.get("collision_boxes", []):
				var box_data: Dictionary = box_data_variant
				var collision_box: CollisionShape3D = CollisionShape3D.new()
				var shape: BoxShape3D = BoxShape3D.new()
				shape.size = box_data.get("size", Vector3.ONE)
				collision_box.shape = shape
				collision_box.transform = box_data.get("transform", Transform3D.IDENTITY)
				_collision_root.add_child(collision_box)

	_update_blocked_grid_cells()
	if Engine.is_editor_hint():
		update_gizmos()
	rebuilt.emit()

func _request_rebuild() -> void:
	if not auto_rebuild:
		return
	if _pending_rebuild:
		return
	_pending_rebuild = true
	if is_inside_tree():
		call_deferred("rebuild_geometry")

func _ensure_default_points() -> void:
	if not control_points.is_empty():
		return
	control_points = _get_default_control_points()

func _exit_tree() -> void:
	_unregister_grid_obstacles()

func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED:
		return
	if _last_collision_boxes.is_empty():
		return
	_update_blocked_grid_cells()
	if Engine.is_editor_hint():
		update_gizmos()

func _validate_property(property: Dictionary) -> void:
	if str(property.get("name", "")) != "closed":
		return
	if can_edit_closed_state():
		return
	property["usage"] = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) | PROPERTY_USAGE_READ_ONLY

func _get_default_control_points() -> Array:
	return [Vector3.ZERO, Vector3(4.0, 0.0, 0.0)]

func _supports_closed_toggle() -> bool:
	return true

func _requires_closed_shape() -> bool:
	return false

func _sanitize_points(value: Array) -> Array[Vector3]:
	var sanitized: Array[Vector3] = [Vector3.ZERO]
	sanitized.clear()
	for point_variant in value:
		if point_variant is Vector3:
			sanitized.append(snap_point(point_variant))

	while sanitized.size() < get_minimum_point_count():
		if sanitized.is_empty():
			sanitized.append(Vector3.ZERO)
		else:
			sanitized.append(sanitized[sanitized.size() - 1] + Vector3.RIGHT * maxf(snap_step, 1.0))
	return sanitized

func _notify_editor_property_change() -> void:
	if not Engine.is_editor_hint():
		return
	notify_property_list_changed()

func _ensure_internal_nodes() -> void:
	if _preview_mesh == null:
		_preview_mesh = get_node_or_null(PREVIEW_MESH_NAME)
	if _preview_mesh == null:
		_preview_mesh = MeshInstance3D.new()
		_preview_mesh.name = PREVIEW_MESH_NAME
		_preview_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(_preview_mesh, false, Node.INTERNAL_MODE_FRONT)

	if _collision_root == null:
		_collision_root = get_node_or_null(COLLISION_ROOT_NAME)
	if _collision_root == null:
		_collision_root = StaticBody3D.new()
		_collision_root.name = COLLISION_ROOT_NAME
		add_child(_collision_root, false, Node.INTERNAL_MODE_FRONT)

	if _debug_overlay == null:
		_debug_overlay = get_node_or_null(DEBUG_OVERLAY_NAME)
	if _debug_overlay == null:
		_debug_overlay = MeshInstance3D.new()
		_debug_overlay.name = DEBUG_OVERLAY_NAME
		_debug_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_overlay, false, Node.INTERNAL_MODE_FRONT)

func _clear_collision_shapes() -> void:
	if _collision_root == null:
		return
	for child in _collision_root.get_children():
		child.free()

func _build_geometry() -> Dictionary:
	return {
		"mesh": null,
		"collision_boxes": [],
		"warnings": PackedStringArray(["Base generator does not implement geometry construction."]),
		"build_info": {}
	}

func _build_default_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.65, 0.65, 0.7, 1.0)
	material.roughness = 0.9
	return material

func _build_debug_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.85, 1.0, 0.8)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _update_blocked_grid_cells() -> void:
	_blocked_grid_cells.clear()
	_unregister_grid_obstacles()
	if not block_grid_navigation or _last_collision_boxes.is_empty():
		return

	_blocked_grid_cells = ProcGeometryUtils.collect_occupied_grid_cells_from_collision_boxes(
		_last_collision_boxes,
		global_transform,
		_get_effective_grid_size()
	)
	_register_grid_obstacles()

func _register_grid_obstacles() -> void:
	if Engine.is_editor_hint():
		return
	if GridMovementSystem == null or not GridMovementSystem.has_method("register_obstacle"):
		return
	for cell in _blocked_grid_cells:
		GridMovementSystem.register_obstacle(_grid_cell_to_world_center(cell))
	_registered_grid_cells = _blocked_grid_cells.duplicate()

func _unregister_grid_obstacles() -> void:
	if Engine.is_editor_hint():
		_registered_grid_cells.clear()
		return
	if GridMovementSystem == null or not GridMovementSystem.has_method("unregister_obstacle"):
		_registered_grid_cells.clear()
		return
	for cell in _registered_grid_cells:
		GridMovementSystem.unregister_obstacle(_grid_cell_to_world_center(cell))
	_registered_grid_cells.clear()

func _get_effective_grid_size() -> float:
	# In the editor, GridMovementSystem is a placeholder instance because the
	# autoload is not a tool script. Avoid calling into it from @tool code.
	if Engine.is_editor_hint():
		return 1.0
	if GridMovementSystem != null and GridMovementSystem.has_method("grid_to_world"):
		var origin_world: Vector3 = GridMovementSystem.grid_to_world(Vector3i.ZERO)
		var next_world: Vector3 = GridMovementSystem.grid_to_world(Vector3i(1, 0, 0))
		var grid_size: float = origin_world.distance_to(next_world)
		if grid_size > ProcGeometryUtils.EPSILON:
			return grid_size
	return 1.0

func _grid_cell_to_world_center(cell: Vector3i) -> Vector3:
	var grid_size: float = _get_effective_grid_size()
	return Vector3(
		(float(cell.x) + 0.5) * grid_size,
		(float(cell.y) + 0.5) * grid_size,
		(float(cell.z) + 0.5) * grid_size
	)
