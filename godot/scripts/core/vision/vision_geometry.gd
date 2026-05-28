extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")


func compute_visible_cells(topology: Dictionary, center: RefCounted, radius: int) -> Array[Dictionary]:
	var normalized_radius: int = max(0, radius)
	var bounds: Dictionary = _vision_bounds(topology, center, normalized_radius)
	var blockers: Dictionary = _dictionary_or_empty(topology.get("sight_blocking_cells", {}))
	var visible: Array[Dictionary] = []
	for x in range(int(bounds.get("min_x", center.x)), int(bounds.get("max_x", center.x)) + 1):
		var dx: int = x - center.x
		for z in range(int(bounds.get("min_z", center.z)), int(bounds.get("max_z", center.z)) + 1):
			var dz: int = z - center.z
			# 视野按格子与圆形半径相交计算，避免边缘格子被整格中心点误排除。
			if not _cell_intersects_vision_circle(dx, dz, float(normalized_radius)):
				continue
			var target := GridCoord.new(x, center.y, z)
			if _has_line_of_sight(center, target, blockers):
				visible.append(target.to_dictionary())
	return _sorted_cells(visible)


func has_line_of_sight(from_data: Dictionary, to_data: Dictionary, topology: Dictionary) -> bool:
	var from: RefCounted = GridCoord.from_dictionary(from_data)
	var to: RefCounted = GridCoord.from_dictionary(to_data)
	if from.y != to.y:
		return false
	return _has_line_of_sight(from, to, _dictionary_or_empty(topology.get("sight_blocking_cells", {})))


func _vision_bounds(topology: Dictionary, center: RefCounted, radius: int) -> Dictionary:
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	return {
		"min_x": max(int(bounds.get("min_x", center.x - radius)), center.x - radius),
		"max_x": min(int(bounds.get("max_x", center.x + radius)), center.x + radius),
		"min_z": max(int(bounds.get("min_z", center.z - radius)), center.z - radius),
		"max_z": min(int(bounds.get("max_z", center.z + radius)), center.z + radius),
	}


func _has_line_of_sight(from: RefCounted, to: RefCounted, blockers: Dictionary) -> bool:
	if from.x == to.x and from.y == to.y and from.z == to.z:
		return true
	var x: int = from.x
	var z: int = from.z
	var dx: int = abs(to.x - x)
	var dz: int = abs(to.z - z)
	var sx: int = 1 if x < to.x else -1
	var sz: int = 1 if z < to.z else -1
	var err: int = dx - dz
	while true:
		if x == to.x and z == to.z:
			return true
		var e2: int = err * 2
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
		if x == to.x and z == to.z:
			return true
		# 起点和终点可见，中间格若被 sight blocker 占用则截断视线。
		if blockers.has(GridCoord.new(x, from.y, z).key()):
			return false
	return true


func _cell_intersects_vision_circle(dx: int, dz: int, radius: float) -> bool:
	if radius <= 0.0:
		return dx == 0 and dz == 0
	var qx: float = max(0.0, float(abs(dx)) - 0.5)
	var qz: float = max(0.0, float(abs(dz)) - 0.5)
	return qx * qx + qz * qz <= radius * radius


func _sorted_cells(cells: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for cell in cells:
		output.append(_normalized_cell(_dictionary_or_empty(cell)))
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("y", 0)) != int(b.get("y", 0)):
			return int(a.get("y", 0)) < int(b.get("y", 0))
		if int(a.get("x", 0)) != int(b.get("x", 0)):
			return int(a.get("x", 0)) < int(b.get("x", 0))
		return int(a.get("z", 0)) < int(b.get("z", 0))
	)
	return output


func _normalized_cell(cell: Dictionary) -> Dictionary:
	return {
		"x": int(cell.get("x", 0)),
		"y": int(cell.get("y", 0)),
		"z": int(cell.get("z", 0)),
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
