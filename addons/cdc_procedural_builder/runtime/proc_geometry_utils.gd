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

static func collect_occupied_grid_cells_from_collision_boxes(collision_boxes: Array, owner_global_transform: Transform3D, grid_size: float = 1.0) -> Array[Vector3i]:
	var occupied_map: Dictionary = {}
	for box_data_variant in collision_boxes:
		var box_data: Dictionary = box_data_variant
		var local_transform: Transform3D = box_data.get("transform", Transform3D.IDENTITY)
		var world_transform: Transform3D = owner_global_transform * local_transform
		var size: Vector3 = box_data.get("size", Vector3.ONE)
		var footprint: Array[Vector2] = _build_box_footprint_xz(world_transform, size)
		if footprint.size() < 3:
			continue

		var bottom_y: float = _compute_footprint_bottom_y(world_transform, size)
		for grid_cell in _collect_grid_cells_from_polygon_xz(footprint, bottom_y, grid_size):
			var key: String = "%d|%d|%d" % [grid_cell.x, grid_cell.y, grid_cell.z]
			occupied_map[key] = grid_cell

	var occupied_cells: Array[Vector3i] = [Vector3i.ZERO]
	occupied_cells.clear()
	for key in occupied_map.keys():
		occupied_cells.append(occupied_map[key])
	occupied_cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z:
			return a.z < b.z
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)
	return occupied_cells

static func build_polyline_strip(points: Array, half_width: float, closed_shape: bool, start_extension: float = 0.0, end_extension: float = 0.0, miter_limit: float = 4.0) -> Dictionary:
	var strip_points: Array[Vector3] = _sanitize_polyline_points(points, closed_shape)
	if strip_points.size() < 2 or half_width <= EPSILON:
		return {}

	if not closed_shape:
		strip_points = strip_points.duplicate()
		if start_extension > EPSILON:
			var start_direction: Vector2 = _to_xz(strip_points[1] - strip_points[0]).normalized()
			strip_points[0] = _offset_point_xz(strip_points[0], -start_direction * start_extension)
		if end_extension > EPSILON:
			var last_index: int = strip_points.size() - 1
			var end_direction: Vector2 = _to_xz(strip_points[last_index] - strip_points[last_index - 1]).normalized()
			strip_points[last_index] = _offset_point_xz(strip_points[last_index], end_direction * end_extension)

	var segment_count: int = strip_points.size() if closed_shape else strip_points.size() - 1
	var directions: Array[Vector2] = [Vector2.ZERO]
	directions.clear()
	for segment_index in range(segment_count):
		var next_index: int = (segment_index + 1) % strip_points.size()
		var segment_direction: Vector2 = _to_xz(strip_points[next_index] - strip_points[segment_index])
		if segment_direction.length() <= EPSILON:
			return {}
		directions.append(segment_direction.normalized())

	var path_lengths: PackedFloat32Array = PackedFloat32Array()
	var total_length: float = 0.0
	path_lengths.append(0.0)
	for point_index in range(1, strip_points.size()):
		total_length += _to_xz(strip_points[point_index] - strip_points[point_index - 1]).length()
		path_lengths.append(total_length)
	if closed_shape:
		total_length += _to_xz(strip_points[0] - strip_points[strip_points.size() - 1]).length()

	var left_points: Array[Vector3] = [Vector3.ZERO]
	left_points.clear()
	var right_points: Array[Vector3] = [Vector3.ZERO]
	right_points.clear()
	for point_index in range(strip_points.size()):
		if not closed_shape and point_index == 0:
			var start_normal: Vector2 = _left_normal_2d(directions[0])
			left_points.append(_offset_point_xz(strip_points[point_index], start_normal * half_width))
			right_points.append(_offset_point_xz(strip_points[point_index], -start_normal * half_width))
			continue
		if not closed_shape and point_index == strip_points.size() - 1:
			var end_normal: Vector2 = _left_normal_2d(directions[directions.size() - 1])
			left_points.append(_offset_point_xz(strip_points[point_index], end_normal * half_width))
			right_points.append(_offset_point_xz(strip_points[point_index], -end_normal * half_width))
			continue

		var previous_direction: Vector2 = directions[(point_index - 1 + segment_count) % segment_count]
		var next_direction: Vector2 = directions[point_index % segment_count]
		left_points.append(_build_miter_join_point(strip_points[point_index], previous_direction, next_direction, half_width, true, miter_limit))
		right_points.append(_build_miter_join_point(strip_points[point_index], previous_direction, next_direction, half_width, false, miter_limit))

	return {
		"points": strip_points,
		"left_points": left_points,
		"right_points": right_points,
		"path_lengths": path_lengths,
		"total_length": total_length,
		"closed": closed_shape
	}

static func add_polyline_prism(surface_tool: SurfaceTool, strip_data: Dictionary, bottom_offset: float, top_offset: float, inside_point: Vector3) -> void:
	var strip_points: Array = strip_data.get("points", [])
	var left_points: Array = strip_data.get("left_points", [])
	var right_points: Array = strip_data.get("right_points", [])
	var path_lengths: PackedFloat32Array = strip_data.get("path_lengths", PackedFloat32Array())
	var total_length: float = float(strip_data.get("total_length", 0.0))
	var closed_shape: bool = bool(strip_data.get("closed", false))
	if strip_points.size() < 2 or left_points.size() != strip_points.size() or right_points.size() != strip_points.size():
		return

	var segment_count: int = strip_points.size() if closed_shape else strip_points.size() - 1
	var top_width_v: float = _compute_average_strip_width(left_points, right_points)
	for segment_index in range(segment_count):
		var next_index: int = (segment_index + 1) % strip_points.size()
		var segment_start: float = path_lengths[segment_index]
		var segment_end: float = total_length if (closed_shape and next_index == 0) else path_lengths[next_index]

		var left_bottom_start: Vector3 = left_points[segment_index] + Vector3.UP * bottom_offset
		var left_bottom_end: Vector3 = left_points[next_index] + Vector3.UP * bottom_offset
		var right_bottom_start: Vector3 = right_points[segment_index] + Vector3.UP * bottom_offset
		var right_bottom_end: Vector3 = right_points[next_index] + Vector3.UP * bottom_offset
		var left_top_start: Vector3 = left_points[segment_index] + Vector3.UP * top_offset
		var left_top_end: Vector3 = left_points[next_index] + Vector3.UP * top_offset
		var right_top_start: Vector3 = right_points[segment_index] + Vector3.UP * top_offset
		var right_top_end: Vector3 = right_points[next_index] + Vector3.UP * top_offset

		add_quad(
			surface_tool,
			left_bottom_start,
			left_bottom_end,
			left_top_end,
			left_top_start,
			Vector2(segment_start, bottom_offset),
			Vector2(segment_end, bottom_offset),
			Vector2(segment_end, top_offset),
			Vector2(segment_start, top_offset),
			inside_point
		)
		add_quad(
			surface_tool,
			right_bottom_start,
			right_bottom_end,
			right_top_end,
			right_top_start,
			Vector2(segment_start, bottom_offset),
			Vector2(segment_end, bottom_offset),
			Vector2(segment_end, top_offset),
			Vector2(segment_start, top_offset),
			inside_point
		)
		add_quad(
			surface_tool,
			left_top_start,
			right_top_start,
			right_top_end,
			left_top_end,
			Vector2(segment_start, 0.0),
			Vector2(segment_start, top_width_v),
			Vector2(segment_end, top_width_v),
			Vector2(segment_end, 0.0),
			inside_point
		)
		add_quad(
			surface_tool,
			left_bottom_start,
			right_bottom_start,
			right_bottom_end,
			left_bottom_end,
			Vector2(segment_start, 0.0),
			Vector2(segment_start, top_width_v),
			Vector2(segment_end, top_width_v),
			Vector2(segment_end, 0.0),
			inside_point
		)

	if closed_shape:
		return

	var start_cap_width: float = left_points[0].distance_to(right_points[0])
	add_quad(
		surface_tool,
		right_points[0] + Vector3.UP * bottom_offset,
		left_points[0] + Vector3.UP * bottom_offset,
		left_points[0] + Vector3.UP * top_offset,
		right_points[0] + Vector3.UP * top_offset,
		Vector2(0.0, bottom_offset),
		Vector2(start_cap_width, bottom_offset),
		Vector2(start_cap_width, top_offset),
		Vector2(0.0, top_offset),
		inside_point
	)

	var last_index: int = strip_points.size() - 1
	var end_cap_width: float = left_points[last_index].distance_to(right_points[last_index])
	add_quad(
		surface_tool,
		left_points[last_index] + Vector3.UP * bottom_offset,
		right_points[last_index] + Vector3.UP * bottom_offset,
		right_points[last_index] + Vector3.UP * top_offset,
		left_points[last_index] + Vector3.UP * top_offset,
		Vector2(0.0, bottom_offset),
		Vector2(end_cap_width, bottom_offset),
		Vector2(end_cap_width, top_offset),
		Vector2(0.0, top_offset),
		inside_point
	)

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
		add_quad(
			surface_tool,
			corners[indices[0]],
			corners[indices[1]],
			corners[indices[2]],
			corners[indices[3]],
			Vector2(0, uv_size.y),
			Vector2(uv_size.x, uv_size.y),
			Vector2(uv_size.x, 0),
			Vector2(0, 0),
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

static func add_quad(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2, inside_point: Vector3) -> void:
	_add_triangle(surface_tool, a, b, c, uv_a, uv_b, uv_c, inside_point)
	_add_triangle(surface_tool, a, c, d, uv_a, uv_c, uv_d, inside_point)

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

static func _sanitize_polyline_points(points: Array, closed_shape: bool) -> Array[Vector3]:
	var sanitized: Array[Vector3] = [Vector3.ZERO]
	sanitized.clear()
	for point_variant in points:
		if not (point_variant is Vector3):
			continue
		var point: Vector3 = point_variant
		if sanitized.is_empty():
			sanitized.append(point)
			continue
		if _to_xz(point - sanitized[sanitized.size() - 1]).length() <= EPSILON:
			continue
		sanitized.append(point)

	if closed_shape and sanitized.size() > 2 and _to_xz(sanitized[0] - sanitized[sanitized.size() - 1]).length() <= EPSILON:
		sanitized.remove_at(sanitized.size() - 1)

	return sanitized

static func _build_miter_join_point(point: Vector3, previous_direction: Vector2, next_direction: Vector2, half_width: float, left_side: bool, miter_limit: float) -> Vector3:
	var previous_normal: Vector2 = _left_normal_2d(previous_direction)
	var next_normal: Vector2 = _left_normal_2d(next_direction)
	if not left_side:
		previous_normal = -previous_normal
		next_normal = -next_normal

	var miter: Vector2 = previous_normal + next_normal
	if miter.length() <= EPSILON:
		return _offset_point_xz(point, next_normal * half_width)

	var miter_direction: Vector2 = miter.normalized()
	var denominator: float = miter_direction.dot(next_normal)
	if absf(denominator) <= EPSILON:
		return _offset_point_xz(point, next_normal * half_width)

	var max_scale: float = half_width * maxf(miter_limit, 1.0)
	var miter_scale: float = clampf(half_width / denominator, -max_scale, max_scale)
	return _offset_point_xz(point, miter_direction * miter_scale)

static func _compute_average_strip_width(left_points: Array, right_points: Array) -> float:
	if left_points.is_empty() or left_points.size() != right_points.size():
		return 1.0
	var width_sum: float = 0.0
	for point_index in range(left_points.size()):
		var left_point: Vector3 = left_points[point_index]
		var right_point: Vector3 = right_points[point_index]
		width_sum += left_point.distance_to(right_point)
	return maxf(width_sum / float(left_points.size()), EPSILON)

static func _left_normal_2d(direction: Vector2) -> Vector2:
	return Vector2(-direction.y, direction.x)

static func _offset_point_xz(point: Vector3, offset: Vector2) -> Vector3:
	return Vector3(point.x + offset.x, point.y, point.z + offset.y)

static func _to_xz(value: Vector3) -> Vector2:
	return Vector2(value.x, value.z)

static func _build_box_footprint_xz(world_transform: Transform3D, size: Vector3) -> Array[Vector2]:
	var half_size: Vector3 = size * 0.5
	var footprint: Array[Vector2] = [Vector2.ZERO]
	footprint.clear()
	var corners: Array[Vector3] = [
		world_transform * Vector3(-half_size.x, -half_size.y, -half_size.z),
		world_transform * Vector3(half_size.x, -half_size.y, -half_size.z),
		world_transform * Vector3(half_size.x, -half_size.y, half_size.z),
		world_transform * Vector3(-half_size.x, -half_size.y, half_size.z)
	]
	for corner in corners:
		footprint.append(Vector2(corner.x, corner.z))
	return footprint

static func _compute_footprint_bottom_y(world_transform: Transform3D, size: Vector3) -> float:
	var half_size: Vector3 = size * 0.5
	var bottom_y: float = INF
	var bottom_corners: Array[Vector3] = [
		world_transform * Vector3(-half_size.x, -half_size.y, -half_size.z),
		world_transform * Vector3(half_size.x, -half_size.y, -half_size.z),
		world_transform * Vector3(half_size.x, -half_size.y, half_size.z),
		world_transform * Vector3(-half_size.x, -half_size.y, half_size.z)
	]
	for corner in bottom_corners:
		bottom_y = minf(bottom_y, corner.y)
	return bottom_y

static func _collect_grid_cells_from_polygon_xz(footprint: Array[Vector2], bottom_y: float, grid_size: float) -> Array[Vector3i]:
	var occupied_cells: Array[Vector3i] = [Vector3i.ZERO]
	occupied_cells.clear()
	if footprint.size() < 3 or grid_size <= EPSILON:
		return occupied_cells

	var min_x: float = footprint[0].x
	var max_x: float = footprint[0].x
	var min_z: float = footprint[0].y
	var max_z: float = footprint[0].y
	for point in footprint:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.y)
		max_z = maxf(max_z, point.y)

	var min_cell_x: int = int(floor(min_x / grid_size))
	var max_cell_x: int = int(floor((max_x - EPSILON) / grid_size))
	var min_cell_z: int = int(floor(min_z / grid_size))
	var max_cell_z: int = int(floor((max_z - EPSILON) / grid_size))
	var cell_y: int = int(floor(bottom_y / grid_size))

	for cell_x in range(min_cell_x, max_cell_x + 1):
		for cell_z in range(min_cell_z, max_cell_z + 1):
			var rect_min: Vector2 = Vector2(cell_x * grid_size, cell_z * grid_size)
			var rect_max: Vector2 = rect_min + Vector2(grid_size, grid_size)
			if _polygon_intersects_rect_xz(footprint, rect_min, rect_max):
				occupied_cells.append(Vector3i(cell_x, cell_y, cell_z))

	return occupied_cells

static func _polygon_intersects_rect_xz(footprint: Array[Vector2], rect_min: Vector2, rect_max: Vector2) -> bool:
	var polygon: PackedVector2Array = PackedVector2Array(footprint)
	var rect_points: Array[Vector2] = [
		rect_min,
		Vector2(rect_max.x, rect_min.y),
		rect_max,
		Vector2(rect_min.x, rect_max.y)
	]

	for point in footprint:
		if _point_in_rect(point, rect_min, rect_max):
			return true

	for rect_point in rect_points:
		if Geometry2D.is_point_in_polygon(rect_point, polygon):
			return true

	for edge_index in range(footprint.size()):
		var segment_start: Vector2 = footprint[edge_index]
		var segment_end: Vector2 = footprint[(edge_index + 1) % footprint.size()]
		for rect_edge_index in range(rect_points.size()):
			var rect_edge_start: Vector2 = rect_points[rect_edge_index]
			var rect_edge_end: Vector2 = rect_points[(rect_edge_index + 1) % rect_points.size()]
			if Geometry2D.segment_intersects_segment(segment_start, segment_end, rect_edge_start, rect_edge_end) != null:
				return true

	return false

static func _point_in_rect(point: Vector2, rect_min: Vector2, rect_max: Vector2) -> bool:
	return point.x >= rect_min.x - EPSILON \
		and point.x <= rect_max.x + EPSILON \
		and point.y >= rect_min.y - EPSILON \
		and point.y <= rect_max.y + EPSILON
