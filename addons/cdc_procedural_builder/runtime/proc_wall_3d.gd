@tool
class_name ProcWall3D
extends "res://addons/cdc_procedural_builder/runtime/proc_shape_generator_3d.gd"

@export_range(0.5, 12.0, 0.1, "or_greater") var wall_height: float = 2.8:
	set = set_wall_height
@export_range(0.05, 4.0, 0.05, "or_greater") var wall_thickness: float = 0.25:
	set = set_wall_thickness
@export var cap_ends: bool = true:
	set = set_cap_ends

func set_wall_height(value: float) -> void:
	wall_height = maxf(value, 0.5)
	_request_rebuild()

func set_wall_thickness(value: float) -> void:
	wall_thickness = maxf(value, 0.05)
	_request_rebuild()

func set_cap_ends(value: bool) -> void:
	cap_ends = value
	_request_rebuild()

func _build_geometry() -> Dictionary:
	var warnings: PackedStringArray = PackedStringArray()
	if control_points.size() < 2:
		warnings.append("Wall requires at least two control points.")
		return {"mesh": null, "collision_boxes": [], "warnings": warnings, "build_info": {}}

	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var strip_data: Dictionary = ProcGeometryUtils.build_polyline_strip(
		control_points,
		wall_thickness * 0.5,
		closed,
		wall_thickness * 0.5 if (cap_ends and not closed) else 0.0,
		wall_thickness * 0.5 if (cap_ends and not closed) else 0.0
	)
	if strip_data.is_empty():
		warnings.append("Wall requires at least one non-zero-length segment.")
		return {"mesh": null, "collision_boxes": [], "warnings": warnings, "build_info": {}}

	var inside_point: Vector3 = _compute_inside_point(strip_data)
	ProcGeometryUtils.add_polyline_prism(surface_tool, strip_data, 0.0, wall_height, inside_point)

	var collision_boxes: Array = []
	for segment_index in range(get_segment_count()):
		var segment_points: Array = get_segment_points(segment_index)
		var start_point: Vector3 = segment_points[0]
		var end_point: Vector3 = segment_points[1]
		var direction: Vector3 = end_point - start_point
		var length: float = direction.length()
		if length <= ProcGeometryUtils.EPSILON:
			continue

		var forward: Vector3 = direction.normalized()
		var start_extension: float = wall_thickness * 0.5 if (_requires_closed_shape() or closed or segment_index > 0 or cap_ends) else 0.0
		var end_extension: float = wall_thickness * 0.5 if (_requires_closed_shape() or closed or segment_index < get_segment_count() - 1 or cap_ends) else 0.0
		var adjusted_start: Vector3 = start_point - forward * start_extension
		var adjusted_end: Vector3 = end_point + forward * end_extension

		var basis: Basis = ProcGeometryUtils.build_segment_basis(adjusted_end - adjusted_start)
		var center: Vector3 = (adjusted_start + adjusted_end) * 0.5 + Vector3.UP * (wall_height * 0.5)
		var size: Vector3 = Vector3(wall_thickness, wall_height, adjusted_start.distance_to(adjusted_end))

		collision_boxes.append({
			"transform": Transform3D(basis, center),
			"size": size
		})

	var mesh: ArrayMesh = surface_tool.commit()
	return {
		"mesh": mesh,
		"collision_boxes": collision_boxes,
		"debug_mesh": _build_debug_mesh(),
		"warnings": warnings,
		"build_info": {
			"segment_count": get_segment_count(),
			"collision_shape_count": collision_boxes.size(),
			"surface_count": mesh.get_surface_count() if mesh != null else 0
		}
	}

func _build_default_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.72, 0.68)
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material

func _build_debug_mesh() -> ImmediateMesh:
	var debug_mesh: ImmediateMesh = ImmediateMesh.new()
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for line_point in get_debug_line_points():
		debug_mesh.surface_add_vertex(line_point + Vector3.UP * 0.05)
	debug_mesh.surface_end()
	return debug_mesh

func _compute_inside_point(strip_data: Dictionary) -> Vector3:
	var strip_points: Array = strip_data.get("points", [])
	if strip_points.is_empty():
		return Vector3.UP * (wall_height * 0.5)
	if bool(strip_data.get("closed", false)):
		return ProcGeometryUtils.find_polygon_interior_point_xz(strip_points, wall_height * 0.5)

	var center: Vector3 = Vector3.ZERO
	for point_variant in strip_points:
		var point: Vector3 = point_variant
		center += point
	center /= float(strip_points.size())
	center.y += wall_height * 0.5
	return center
