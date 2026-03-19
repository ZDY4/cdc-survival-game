@tool
class_name ProcHouse3D
extends ProcShapeGenerator3D

enum RoofMode {
	FLAT,
	GABLE
}

@export_range(1.5, 12.0, 0.1, "or_greater") var wall_height: float = 3.0:
	set = set_wall_height
@export_range(0.05, 2.0, 0.05, "or_greater") var wall_thickness: float = 0.25:
	set = set_wall_thickness
@export_range(0.1, 6.0, 0.1, "or_greater") var roof_height: float = 1.2:
	set = set_roof_height
@export var roof_mode: RoofMode = RoofMode.FLAT:
	set = set_roof_mode
@export var openings: Array[HouseOpeningResource] = []:
	set = set_openings

func get_minimum_point_count() -> int:
	return 3

func _get_default_control_points() -> Array:
	return [
		Vector3(-3.0, 0.0, -2.0),
		Vector3(3.0, 0.0, -2.0),
		Vector3(3.0, 0.0, 2.0),
		Vector3(-3.0, 0.0, 2.0)
	]

func _requires_closed_shape() -> bool:
	return true

func _supports_closed_toggle() -> bool:
	return false

func set_wall_height(value: float) -> void:
	wall_height = maxf(value, 1.5)
	_request_rebuild()

func set_wall_thickness(value: float) -> void:
	wall_thickness = maxf(value, 0.05)
	_request_rebuild()

func set_roof_height(value: float) -> void:
	roof_height = maxf(value, 0.1)
	_request_rebuild()

func set_roof_mode(value: RoofMode) -> void:
	roof_mode = value
	_request_rebuild()

func set_openings(value: Array) -> void:
	var sanitized: Array[HouseOpeningResource] = [HouseOpeningResource.new()]
	sanitized.clear()
	for opening in value:
		if opening != null:
			sanitized.append(opening)
	openings = sanitized
	_request_rebuild()

func add_default_opening() -> void:
	var new_opening: HouseOpeningResource = HouseOpeningResource.new()
	new_opening.edge_index = 0
	new_opening.offset_on_edge = 1.5
	new_opening.width = 1.2
	new_opening.height = 2.1
	new_opening.sill_height = 0.0
	var updated: Array = openings.duplicate()
	updated.append(new_opening)
	set_openings(updated)

func remove_opening(index: int) -> void:
	if index < 0 or index >= openings.size():
		return
	var updated: Array = openings.duplicate()
	updated.remove_at(index)
	set_openings(updated)

func _build_geometry() -> Dictionary:
	var warnings: PackedStringArray = PackedStringArray()
	if control_points.size() < 3:
		warnings.append("House requires at least three control points.")
		return {"mesh": null, "collision_boxes": [], "warnings": warnings, "build_info": {}}
	if not ProcGeometryUtils.is_simple_polygon_xz(control_points):
		warnings.append("House footprint must be a simple, non self-intersecting polygon.")
		return {"mesh": null, "collision_boxes": [], "warnings": warnings, "build_info": {}}

	var ordered_points: Array[Vector3] = _ensure_ccw_points(control_points)
	var triangulated: PackedInt32Array = ProcGeometryUtils.triangulate_polygon_xz(ordered_points)
	if triangulated.is_empty():
		warnings.append("House footprint could not be triangulated.")
		return {"mesh": null, "collision_boxes": [], "warnings": warnings, "build_info": {}}

	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inside_point: Vector3 = _compute_inside_point(ordered_points)

	ProcGeometryUtils.add_polygon_cap(surface_tool, ordered_points, triangulated, inside_point, true)

	if roof_mode == RoofMode.GABLE:
		_add_gable_roof(surface_tool, ordered_points)
	else:
		var roof_vertices: Array[Vector3] = _build_flat_roof_vertices(ordered_points)
		ProcGeometryUtils.add_polygon_cap(surface_tool, roof_vertices, triangulated, _compute_roof_inside_point(ordered_points), false)

	var edge_opening_map: Dictionary = _build_edge_opening_map(ordered_points, warnings)
	var wall_piece_count: int = 0
	var applied_opening_count: int = 0
	for edge_index in range(ordered_points.size()):
		var start_point: Vector3 = ordered_points[edge_index]
		var end_point: Vector3 = ordered_points[(edge_index + 1) % ordered_points.size()]
		var edge_openings: Array = []
		if edge_opening_map.has(edge_index):
			for opening_data in edge_opening_map[edge_index]:
				edge_openings.append(opening_data)
		applied_opening_count += edge_openings.size()
		wall_piece_count += _build_wall_edge(surface_tool, start_point, end_point, edge_openings)

	var mesh: ArrayMesh = surface_tool.commit()
	var collision_shape: ConcavePolygonShape3D = null
	if mesh != null:
		collision_shape = mesh.create_trimesh_shape()

	return {
		"mesh": mesh,
		"collision_shape": collision_shape,
		"debug_mesh": _build_debug_mesh(),
		"warnings": warnings,
		"build_info": {
			"segment_count": ordered_points.size(),
			"opening_count": openings.size(),
			"applied_opening_count": applied_opening_count,
			"wall_piece_count": wall_piece_count,
			"surface_count": mesh.get_surface_count() if mesh != null else 0
		}
	}

func _build_default_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.77, 0.73, 0.67)
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material

func _build_debug_mesh() -> ImmediateMesh:
	var debug_mesh: ImmediateMesh = ImmediateMesh.new()
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for line_point in get_debug_line_points():
		debug_mesh.surface_add_vertex(line_point + Vector3.UP * 0.1)
	debug_mesh.surface_end()
	return debug_mesh

func _ensure_ccw_points(points: Array) -> Array[Vector3]:
	var ccw_points: Array[Vector3] = [Vector3.ZERO]
	ccw_points.clear()
	for point in points:
		if point is Vector3:
			ccw_points.append(point)
	if ProcGeometryUtils.polygon_area_xz(ccw_points) < 0.0:
		ccw_points.reverse()
	return ccw_points

func _build_flat_roof_vertices(points: Array) -> Array[Vector3]:
	var roof_vertices: Array[Vector3] = [Vector3.ZERO]
	roof_vertices.clear()
	for point in points:
		roof_vertices.append(point + Vector3.UP * wall_height)
	return roof_vertices

func _add_gable_roof(surface_tool: SurfaceTool, points: Array[Vector3]) -> void:
	if points.size() < 3:
		return

	var bounds: Dictionary = _compute_roof_bounds(points)
	var bounds_min: Vector3 = bounds.get("min", Vector3.ZERO)
	var bounds_max: Vector3 = bounds.get("max", Vector3.ZERO)
	var span_x: float = maxf(bounds_max.x - bounds_min.x, ProcGeometryUtils.EPSILON)
	var span_z: float = maxf(bounds_max.z - bounds_min.z, ProcGeometryUtils.EPSILON)
	var ridge_on_x: bool = span_x >= span_z
	var roof_inside_point: Vector3 = _compute_roof_inside_point(points)

	for point_index in range(points.size()):
		var next_index: int = (point_index + 1) % points.size()
		var edge_start: Vector3 = points[point_index] + Vector3.UP * wall_height
		var edge_end: Vector3 = points[next_index] + Vector3.UP * wall_height
		var ridge_start: Vector3 = _project_point_to_roof_ridge(points[point_index], bounds_min, bounds_max, ridge_on_x)
		var ridge_end: Vector3 = _project_point_to_roof_ridge(points[next_index], bounds_min, bounds_max, ridge_on_x)

		if ridge_start.distance_to(ridge_end) <= ProcGeometryUtils.EPSILON:
			ProcGeometryUtils.add_triangle(
				surface_tool,
				edge_start,
				edge_end,
				ridge_start,
				Vector2(edge_start.x, edge_start.z),
				Vector2(edge_end.x, edge_end.z),
				Vector2(ridge_start.x, ridge_start.z),
				roof_inside_point
			)
			continue

		ProcGeometryUtils.add_quad(
			surface_tool,
			edge_start,
			edge_end,
			ridge_end,
			ridge_start,
			Vector2(edge_start.x, edge_start.z),
			Vector2(edge_end.x, edge_end.z),
			Vector2(ridge_end.x, ridge_end.z),
			Vector2(ridge_start.x, ridge_start.z),
			roof_inside_point
		)

func _compute_roof_bounds(points: Array[Vector3]) -> Dictionary:
	var bounds_min: Vector3 = points[0]
	var bounds_max: Vector3 = points[0]
	for point in points:
		bounds_min.x = minf(bounds_min.x, point.x)
		bounds_min.z = minf(bounds_min.z, point.z)
		bounds_max.x = maxf(bounds_max.x, point.x)
		bounds_max.z = maxf(bounds_max.z, point.z)
	return {
		"min": bounds_min,
		"max": bounds_max
	}

func _project_point_to_roof_ridge(point: Vector3, bounds_min: Vector3, bounds_max: Vector3, ridge_on_x: bool) -> Vector3:
	var ridge_height: float = wall_height + roof_height
	if ridge_on_x:
		return Vector3(point.x, ridge_height, lerpf(bounds_min.z, bounds_max.z, 0.5))
	return Vector3(lerpf(bounds_min.x, bounds_max.x, 0.5), ridge_height, point.z)

func _compute_inside_point(points: Array[Vector3]) -> Vector3:
	var center: Vector3 = Vector3.ZERO
	for point in points:
		center += point
	center /= float(maxi(points.size(), 1))
	center.y = wall_height * 0.5
	return center

func _compute_roof_inside_point(points: Array[Vector3]) -> Vector3:
	return ProcGeometryUtils.find_polygon_interior_point_xz(points, wall_height + roof_height * 0.5)

func _build_edge_opening_map(points: Array[Vector3], warnings: PackedStringArray) -> Dictionary:
	var opening_map: Dictionary = {}
	for opening in openings:
		if opening == null:
			continue
		var edge_index: int = clampi(opening.edge_index, 0, points.size() - 1)
		var start_point: Vector3 = points[edge_index]
		var end_point: Vector3 = points[(edge_index + 1) % points.size()]
		var edge_length: float = start_point.distance_to(end_point)
		if edge_length <= ProcGeometryUtils.EPSILON:
			continue

		var opening_width: float = clampf(opening.width, 0.4, edge_length - 0.1)
		var opening_height: float = clampf(opening.height, 0.4, wall_height)
		var sill_height: float = clampf(opening.sill_height, 0.0, wall_height - 0.2)
		if opening.opening_type == "door":
			sill_height = 0.0
		var offset: float = clampf(opening.offset_on_edge, opening_width * 0.5, edge_length - opening_width * 0.5)
		var span_start: float = offset - opening_width * 0.5
		var span_end: float = offset + opening_width * 0.5
		var top_height: float = minf(wall_height, sill_height + opening_height)
		if top_height <= sill_height + ProcGeometryUtils.EPSILON:
			warnings.append("Ignored zero-height opening on edge %d." % edge_index)
			continue

		if not opening_map.has(edge_index):
			opening_map[edge_index] = []
		var edge_openings: Array = opening_map[edge_index]
		edge_openings.append({
			"start": span_start,
			"end": span_end,
			"sill": sill_height,
			"top": top_height
		})
		opening_map[edge_index] = edge_openings

	for edge_index in opening_map.keys():
		var edge_openings: Array = opening_map[edge_index]
		edge_openings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("start", 0.0)) < float(b.get("start", 0.0))
		)
		var filtered_openings: Array = []
		var last_end: float = -1.0
		for opening_data_variant in edge_openings:
			var opening_data: Dictionary = opening_data_variant
			if float(opening_data.get("start", 0.0)) < last_end - ProcGeometryUtils.EPSILON:
				warnings.append("Skipped overlapping opening on edge %d." % int(edge_index))
				continue
			filtered_openings.append(opening_data)
			last_end = float(opening_data.get("end", 0.0))
		opening_map[edge_index] = filtered_openings

	return opening_map

func _build_wall_edge(surface_tool: SurfaceTool, start_point: Vector3, end_point: Vector3, edge_openings: Array) -> int:
	var direction: Vector3 = end_point - start_point
	var edge_length: float = direction.length()
	if edge_length <= ProcGeometryUtils.EPSILON:
		return 0

	var basis: Basis = ProcGeometryUtils.build_segment_basis(direction)
	var forward: Vector3 = direction.normalized()
	var cursor: float = 0.0
	var piece_count: int = 0

	for opening_data in edge_openings:
		var opening_start: float = clampf(float(opening_data.get("start", 0.0)), 0.0, edge_length)
		var opening_end: float = clampf(float(opening_data.get("end", edge_length)), 0.0, edge_length)
		var sill_height: float = clampf(float(opening_data.get("sill", 0.0)), 0.0, wall_height)
		var top_height: float = clampf(float(opening_data.get("top", wall_height)), 0.0, wall_height)

		if opening_start > cursor + ProcGeometryUtils.EPSILON:
			piece_count += _add_wall_box(surface_tool, start_point + forward * cursor, start_point + forward * opening_start, 0.0, wall_height, basis)
		if sill_height > ProcGeometryUtils.EPSILON:
			piece_count += _add_wall_box(surface_tool, start_point + forward * opening_start, start_point + forward * opening_end, 0.0, sill_height, basis)
		if top_height < wall_height - ProcGeometryUtils.EPSILON:
			piece_count += _add_wall_box(surface_tool, start_point + forward * opening_start, start_point + forward * opening_end, top_height, wall_height, basis)
		cursor = maxf(cursor, opening_end)

	if cursor < edge_length - ProcGeometryUtils.EPSILON:
		piece_count += _add_wall_box(surface_tool, start_point + forward * cursor, end_point, 0.0, wall_height, basis)
	return piece_count

func _add_wall_box(surface_tool: SurfaceTool, start_point: Vector3, end_point: Vector3, bottom_height: float, top_height: float, basis: Basis) -> int:
	var height: float = top_height - bottom_height
	var length: float = start_point.distance_to(end_point)
	if height <= ProcGeometryUtils.EPSILON or length <= ProcGeometryUtils.EPSILON:
		return 0

	var center: Vector3 = (start_point + end_point) * 0.5 + Vector3.UP * (bottom_height + height * 0.5)
	ProcGeometryUtils.add_box_prism(surface_tool, center, basis, Vector3(wall_thickness, height, length))
	return 1
