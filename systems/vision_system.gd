class_name VisionSystem
extends Node
## Grid-based vision system that outputs visible/explored cells.

signal vision_updated(visible: Array[Vector3i], explored: Array[Vector3i])

@export var vision_radius: int = 10

var visible_cells: Array[Vector3i] = []
var explored_cells: Array[Vector3i] = []

var _player: Node3D = null
var _world_to_grid: Callable = Callable()
var _grid_to_world: Callable = Callable()
var _blocker_provider: Callable = Callable()
var _explored_set: Dictionary = {}
var _explored_dirty: bool = false
var _grid_bounds: Dictionary = {}
var _movement_component: Node = null

func initialize(player: Node3D, world_to_grid: Callable, grid_to_world: Callable, blocker_provider: Callable) -> void:
	_player = player
	_world_to_grid = world_to_grid
	_grid_to_world = grid_to_world
	_blocker_provider = blocker_provider

func set_grid_bounds(bounds: Dictionary) -> void:
	_grid_bounds = bounds.duplicate(true)

func set_explored_cells(cells: Array[Vector3i]) -> void:
	_explored_set.clear()
	for cell in cells:
		_explored_set[cell] = true
	_explored_dirty = true
	_rebuild_explored_cells()

func bind_to_movement_component(movement_component: Node) -> void:
	if not movement_component:
		return
	if _movement_component and is_instance_valid(_movement_component):
		if _movement_component.is_connected("movement_step_completed", Callable(self, "_on_movement_step_completed")):
			_movement_component.disconnect("movement_step_completed", Callable(self, "_on_movement_step_completed"))
	_movement_component = movement_component
	if _movement_component.has_signal("movement_step_completed"):
		_movement_component.movement_step_completed.connect(_on_movement_step_completed)

func update_from_world(world_pos: Vector3) -> void:
	if not _world_to_grid.is_valid():
		return
	var grid_pos: Vector3i = _world_to_grid.call(world_pos)
	update_from_grid(grid_pos)

func update_from_grid(center: Vector3i) -> void:
	var center_cell := Vector3i(center.x, 0, center.z)
	var blockers: Dictionary = _get_blocker_set()
	var visible: Array[Vector3i] = []
	var radius: int = maxi(0, vision_radius)
	var min_x: int = center_cell.x - radius
	var max_x: int = center_cell.x + radius
	var min_z: int = center_cell.z - radius
	var max_z: int = center_cell.z + radius
	if not _grid_bounds.is_empty():
		min_x = maxi(min_x, int(_grid_bounds.min_x))
		max_x = mini(max_x, int(_grid_bounds.max_x))
		min_z = maxi(min_z, int(_grid_bounds.min_z))
		max_z = mini(max_z, int(_grid_bounds.max_z))
	var radius_sq: int = radius * radius
	for x in range(min_x, max_x + 1):
		var dx: int = x - center_cell.x
		for z in range(min_z, max_z + 1):
			var dz: int = z - center_cell.z
			if dx * dx + dz * dz > radius_sq:
				continue
			var cell := Vector3i(x, 0, z)
			if _has_line_of_sight(center_cell, cell, blockers):
				visible.append(cell)
				if not _explored_set.has(cell):
					_explored_set[cell] = true
					_explored_dirty = true
	visible_cells = visible
	if _explored_dirty:
		_rebuild_explored_cells()
	vision_updated.emit(visible_cells, explored_cells)

func _rebuild_explored_cells() -> void:
	var arr: Array[Vector3i] = []
	for key in _explored_set.keys():
		arr.append(key)
	explored_cells = arr
	_explored_dirty = false

func _get_blocker_set() -> Dictionary:
	var blockers: Dictionary = {}
	if _blocker_provider.is_valid():
		var cells_var: Variant = _blocker_provider.call()
		if cells_var is Array:
			var cells: Array = cells_var
			for cell in cells:
				if cell is Vector3i:
					blockers[Vector3i(cell.x, 0, cell.z)] = true
				elif cell is Vector3:
					blockers[Vector3i(int(cell.x), 0, int(cell.z))] = true
	else:
		var nodes := get_tree().get_nodes_in_group("vision_blocker")
		for node in nodes:
			if node is Node3D:
				var world_pos: Vector3 = node.global_position
				var grid_pos: Vector3i = GridMovementSystem.world_to_grid(world_pos)
				blockers[Vector3i(grid_pos.x, 0, grid_pos.z)] = true
	return blockers

func _has_line_of_sight(from: Vector3i, to: Vector3i, blockers: Dictionary) -> bool:
	if from == to:
		return true
	var x0: int = from.x
	var z0: int = from.z
	var x1: int = to.x
	var z1: int = to.z
	var dx: int = abs(x1 - x0)
	var dz: int = abs(z1 - z0)
	var sx: int = 1 if x0 < x1 else -1
	var sz: int = 1 if z0 < z1 else -1
	var err: int = dx - dz
	var x: int = x0
	var z: int = z0
	while true:
		if x == x1 and z == z1:
			return true
		var e2: int = err * 2
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
		if x == x1 and z == z1:
			return true
		var pos := Vector3i(x, from.y, z)
		if blockers.has(pos):
			return false
	return true

func _on_movement_step_completed(grid_pos: Vector3i, _world_pos: Vector3, _step_index: int, _total_steps: int) -> void:
	update_from_grid(grid_pos)
