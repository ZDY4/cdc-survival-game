class_name OverworldGridWorld
extends "res://systems/grid_world.gd"

var _walkable_cells: Dictionary = {}

func set_walkable_cells(cells: Array[Vector2i]) -> void:
	_walkable_cells.clear()
	for cell in cells:
		_walkable_cells[_cell_key_2d(cell)] = true
	_bump_topology_version()

func add_walkable_cell(cell: Vector2i) -> void:
	_walkable_cells[_cell_key_2d(cell)] = true
	_bump_topology_version()

func clear_walkable_cells() -> void:
	if _walkable_cells.is_empty():
		return
	_walkable_cells.clear()
	_bump_topology_version()

func is_walkable_static(grid_pos: Vector3i) -> bool:
	if grid_pos.y != 0:
		return false
	return _walkable_cells.has(_cell_key_2d(Vector2i(grid_pos.x, grid_pos.z)))

func is_cell_walkable(cell: Vector2i) -> bool:
	return _walkable_cells.has(_cell_key_2d(cell))

func get_pathfinding_bounds() -> Dictionary:
	if _walkable_cells.is_empty():
		return super.get_pathfinding_bounds()
	var cells: Array[Vector2i] = []
	for key in _walkable_cells.keys():
		var parts: PackedStringArray = String(key).split("|")
		if parts.size() != 2:
			continue
		cells.append(Vector2i(int(parts[0]), int(parts[1])))
	if cells.is_empty():
		return super.get_pathfinding_bounds()
	var min_cell: Vector2i = cells[0]
	var max_cell: Vector2i = cells[0]
	for cell in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	return {
		"min": Vector3i(min_cell.x, 0, min_cell.y),
		"max": Vector3i(max_cell.x, 0, max_cell.y)
	}

func _cell_key_2d(cell: Vector2i) -> String:
	return "%d|%d" % [cell.x, cell.y]
