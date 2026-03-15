@tool
class_name ProcFence3D
extends ProcShapeGenerator3D

@export_range(0.5, 6.0, 0.1, "or_greater") var fence_height: float = 2.0:
	set = set_fence_height
@export_range(0.5, 12.0, 0.1, "or_greater") var post_spacing: float = 2.0:
	set = set_post_spacing
@export var post_size: Vector3 = Vector3(0.18, 2.0, 0.18):
	set = set_post_size
@export_range(1, 4, 1) var rail_count: int = 2:
	set = set_rail_count
@export_range(0.05, 1.0, 0.05, "or_greater") var rail_thickness: float = 0.14:
	set = set_rail_thickness

func set_fence_height(value: float) -> void:
	fence_height = maxf(value, 0.5)
	_request_rebuild()

func set_post_spacing(value: float) -> void:
	post_spacing = maxf(value, 0.5)
	_request_rebuild()

func set_post_size(value: Vector3) -> void:
	post_size = Vector3(maxf(value.x, 0.05), maxf(value.y, 0.5), maxf(value.z, 0.05))
	_request_rebuild()

func set_rail_count(value: int) -> void:
	rail_count = maxi(value, 1)
	_request_rebuild()

func set_rail_thickness(value: float) -> void:
	rail_thickness = maxf(value, 0.05)
	_request_rebuild()

func _build_geometry() -> Dictionary:
	var warnings: PackedStringArray = PackedStringArray()
	if control_points.size() < 2:
		warnings.append("Fence requires at least two control points.")
		return {"mesh": null, "collision_boxes": [], "warnings": warnings, "build_info": {}}

	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var collision_boxes: Array = []
	var unique_posts: Dictionary = {}
	var post_count: int = 0
	var rail_box_width: float = maxf(maxf(post_size.x, post_size.z), rail_thickness)

	for segment_index in range(get_segment_count()):
		var segment_points: Array = get_segment_points(segment_index)
		var start_point: Vector3 = segment_points[0]
		var end_point: Vector3 = segment_points[1]
		var direction: Vector3 = end_point - start_point
		var length: float = direction.length()
		if length <= ProcGeometryUtils.EPSILON:
			continue

		var basis: Basis = ProcGeometryUtils.build_segment_basis(direction)
		var forward: Vector3 = direction.normalized()
		var rail_size: Vector3 = Vector3(rail_box_width, rail_thickness, length)
		for rail_index in range(rail_count):
			var height_ratio: float = float(rail_index + 1) / float(rail_count + 1)
			var rail_center: Vector3 = (start_point + end_point) * 0.5 + Vector3.UP * (fence_height * height_ratio)
			ProcGeometryUtils.add_box_prism(surface_tool, rail_center, basis, rail_size)
			collision_boxes.append({
				"transform": Transform3D(basis, rail_center),
				"size": rail_size
			})

		var distances: Array[float] = [0.0]
		var step_distance: float = post_spacing
		while step_distance < length - ProcGeometryUtils.EPSILON:
			distances.append(step_distance)
			step_distance += post_spacing
		distances.append(length)

		for distance_along in distances:
			var post_base_center: Vector3 = start_point + forward * distance_along
			var key: String = _build_post_key(post_base_center)
			if unique_posts.has(key):
				continue
			unique_posts[key] = true
			post_count += 1

			var post_center: Vector3 = post_base_center + Vector3.UP * (fence_height * 0.5)
			var post_basis: Basis = Basis.IDENTITY
			var post_dimensions: Vector3 = Vector3(post_size.x, fence_height, post_size.z)
			ProcGeometryUtils.add_box_prism(surface_tool, post_center, post_basis, post_dimensions)
			collision_boxes.append({
				"transform": Transform3D(post_basis, post_center),
				"size": post_dimensions
			})

	var mesh: ArrayMesh = surface_tool.commit()
	return {
		"mesh": mesh,
		"collision_boxes": collision_boxes,
		"debug_mesh": _build_debug_mesh(),
		"warnings": warnings,
		"build_info": {
			"segment_count": get_segment_count(),
			"post_count": post_count,
			"collision_shape_count": collision_boxes.size(),
			"surface_count": mesh.get_surface_count() if mesh != null else 0
		}
	}

func _build_default_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.46, 0.34, 0.21)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material

func _build_debug_mesh() -> ImmediateMesh:
	var debug_mesh: ImmediateMesh = ImmediateMesh.new()
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for line_point in get_debug_line_points():
		debug_mesh.surface_add_vertex(line_point + Vector3.UP * 0.08)
	debug_mesh.surface_end()
	return debug_mesh

func _build_post_key(point: Vector3) -> String:
	return "%.3f|%.3f|%.3f" % [point.x, point.y, point.z]
