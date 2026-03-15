@tool
class_name ProcGeometryUtils
extends RefCounted

const EPSILON: float = 0.001

static func snap_vector(value: Vector3, step: float) -> Vector3:
	if step <= 0.0:
		return value
	return Vector3(
		round(value.x / step) * step,
		round(value.y / step) * step,
		round(value.z / step) * step
	)

static func polygon_area_xz(points: Array[Vector3]) -> float:
	if points.size() < 3:
		return 0.0

	var twice_area: float = 0.0
	for index in range(points.size()):
		var current: Vector3 = points[index]
		var next: Vector3 = points[(index + 1) % points.size()]
		twice_area += current.x * next.z - next.x * current.z
	return twice_area * 0.5

static func is_simple_polygon_xz(points: Array[Vector3]) -> bool:
	if points.size() < 3:
		return false

	for edge_a_index in range(points.size()):
		var a0: Vector2 = Vector2(points[edge_a_index].x, points[edge_a_index].z)
		var a1: Vector2 = Vector2(points[(edge_a_index + 1) % points.size()].x, points[(edge_a_index + 1) % points.size()].z)
		for edge_b_index in range(edge_a_index + 1, points.size()):
			var next_b_index: int = (edge_b_index + 1) % points.size()
			if edge_a_index == edge_b_index:
				continue
			if (edge_a_index + 1) % points.size() == edge_b_index:
				continue
			if next_b_index == edge_a_index:
				continue

			var b0: Vector2 = Vector2(points[edge_b_index].x, points[edge_b_index].z)
			var b1: Vector2 = Vector2(points[next_b_index].x, points[next_b_index].z)
			if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
				return false
	return true

static func triangulate_polygon_xz(points: Array[Vector3]) -> PackedInt32Array:
	var polygon: PackedVector2Array = PackedVector2Array()
	for point in points:
		polygon.append(Vector2(point.x, point.z))
	return Geometry2D.triangulate_polygon(polygon)

static func build_segment_basis(direction: Vector3) -> Basis:
	var forward: Vector3 = direction.normalized()
	if forward.length() <= EPSILON:
		return Basis.IDENTITY

	var up: Vector3 = Vector3.UP
	if absf(forward.dot(up)) > 0.99:
		up = Vector3.FORWARD

	var right: Vector3 = up.cross(forward).normalized()
	var corrected_up: Vector3 = forward.cross(right).normalized()
	return Basis(right, corrected_up, forward)

static func add_box_prism(surface_tool: SurfaceTool, center: Vector3, basis: Basis, size: Vector3) -> void:
	var half_size: Vector3 = size * 0.5
	var corners: Array[Vector3] = [
		center + basis * Vector3(-half_size.x, -half_size.y, -half_size.z),
		center + basis * Vector3(half_size.x, -half_size.y, -half_size.z),
		center + basis * Vector3(half_size.x, half_size.y, -half_size.z),
		center + basis * Vector3(-half_size.x, half_size.y, -half_size.z),
		center + basis * Vector3(-half_size.x, -half_size.y, half_size.z),
		center + basis * Vector3(half_size.x, -half_size.y, half_size.z),
		center + basis * Vector3(half_size.x, half_size.y, half_size.z),
		center + basis * Vector3(-half_size.x, half_size.y, half_size.z)
	]

	var faces: Array[Dictionary] = [
		{"indices": PackedInt32Array([4, 5, 6, 7]), "normal": basis.z, "uv": Vector2(size.z, size.y)},
		{"indices": PackedInt32Array([1, 0, 3, 2]), "normal": -basis.z, "uv": Vector2(size.z, size.y)},
		{"indices": PackedInt32Array([0, 4, 7, 3]), "normal": -basis.x, "uv": Vector2(size.z, size.y)},
		{"indices": PackedInt32Array([5, 1, 2, 6]), "normal": basis.x, "uv": Vector2(size.z, size.y)},
		{"indices": PackedInt32Array([3, 7, 6, 2]), "normal": basis.y, "uv": Vector2(size.x, size.z)},
		{"indices": PackedInt32Array([0, 1, 5, 4]), "normal": -basis.y, "uv": Vector2(size.x, size.z)}
	]

	for face in faces:
		var indices: PackedInt32Array = face["indices"]
		var uv_size: Vector2 = face["uv"]
		_add_quad(
			surface_tool,
			corners[indices[0]],
			corners[indices[1]],
			corners[indices[2]],
			corners[indices[3]],
			uv_size,
			center
		)

static func add_polygon_cap(surface_tool: SurfaceTool, vertices: Array[Vector3], indices: PackedInt32Array, inside_point: Vector3, flip_winding: bool = false) -> void:
	if vertices.size() < 3 or indices.is_empty():
		return

	for triangle_index in range(0, indices.size(), 3):
		var a_index: int = indices[triangle_index]
		var b_index: int = indices[triangle_index + 1]
		var c_index: int = indices[triangle_index + 2]

		var a: Vector3 = vertices[a_index]
		var b: Vector3 = vertices[b_index]
		var c: Vector3 = vertices[c_index]
		if flip_winding:
			var temp: Vector3 = b
			b = c
			c = temp

		_add_triangle(
			surface_tool,
			a,
			b,
			c,
			Vector2(a.x, a.z),
			Vector2(b.x, b.z),
			Vector2(c.x, c.z),
			inside_point
		)

static func _add_quad(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_size: Vector2, inside_point: Vector3) -> void:
	_add_triangle(surface_tool, a, b, c, Vector2(0, uv_size.y), Vector2(uv_size.x, uv_size.y), Vector2(uv_size.x, 0), inside_point)
	_add_triangle(surface_tool, a, c, d, Vector2(0, uv_size.y), Vector2(uv_size.x, 0), Vector2(0, 0), inside_point)

static func _add_triangle(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, inside_point: Vector3) -> void:
	var final_b: Vector3 = b
	var final_c: Vector3 = c
	var final_uv_b: Vector2 = uv_b
	var final_uv_c: Vector2 = uv_c
	var triangle_normal: Vector3 = (b - a).cross(c - a).normalized()
	var triangle_center: Vector3 = (a + b + c) / 3.0
	if triangle_normal.dot(inside_point - triangle_center) < 0.0:
		final_b = c
		final_c = b
		final_uv_b = uv_c
		final_uv_c = uv_b
		triangle_normal = -triangle_normal

	# Godot treats clockwise triangles as front faces, so the geometric normal
	# points toward the inside while the shading normal still needs to face out.
	var shading_normal: Vector3 = -triangle_normal

	surface_tool.set_smooth_group(-1)
	surface_tool.set_normal(shading_normal)
	surface_tool.set_uv(uv_a)
	surface_tool.add_vertex(a)
	surface_tool.set_normal(shading_normal)
	surface_tool.set_uv(final_uv_b)
	surface_tool.add_vertex(final_b)
	surface_tool.set_normal(shading_normal)
	surface_tool.set_uv(final_uv_c)
	surface_tool.add_vertex(final_c)
