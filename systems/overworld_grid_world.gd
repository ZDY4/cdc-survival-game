class_name OverworldGridWorld
extends "res://systems/grid_world.gd"

var _walkable_cells: Dictionary = {}

func set_walkable_cells(cells: Array[Vector2i]) -> void:
	_walkable_cells.clear()
	for cell in cells:
		_walkable_cells[_cell_key_2d(cell)] = true

func add_walkable_cell(cell: Vector2i) -> void:
	_walkable_cells[_cell_key_2d(cell)] = true

func clear_walkable_cells() -> void:
	_walkable_cells.clear()

func is_walkable(grid_pos: Vector3i) -> bool:
	if grid_pos.y != 0:
		return false
	if not _walkable_cells.has(_cell_key_2d(Vector2i(grid_pos.x, grid_pos.z))):
		return false
	return super.is_walkable(grid_pos)

func is_cell_walkable(cell: Vector2i) -> bool:
	return _walkable_cells.has(_cell_key_2d(cell))

func _cell_key_2d(cell: Vector2i) -> String:
	return "%d|%d" % [cell.x, cell.y]
