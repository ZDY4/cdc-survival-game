class_name GridWorld
extends Node

const GridNavigatorScript = preload("res://systems/grid_navigator.gd")

const GRID_SIZE := 1.0

var _obstacle_ref_counts: Dictionary = {}
var _runtime_occupants_by_cell: Dictionary = {}
var _runtime_actor_cells: Dictionary = {}
var _topology_version: int = 0
var _runtime_obstacle_version: int = 0

func register_obstacle(world_pos: Vector3) -> void:
    var grid_pos := GridNavigatorScript.new().world_to_grid(world_pos)
    var key := _build_obstacle_key(grid_pos)
    _obstacle_ref_counts[key] = int(_obstacle_ref_counts.get(key, 0)) + 1
    _bump_runtime_obstacle_version()

func unregister_obstacle(world_pos: Vector3) -> void:
    var grid_pos := GridNavigatorScript.new().world_to_grid(world_pos)
    var key := _build_obstacle_key(grid_pos)
    if not _obstacle_ref_counts.has(key):
        return
    var next_count: int = int(_obstacle_ref_counts.get(key, 0)) - 1
    if next_count <= 0:
        _obstacle_ref_counts.erase(key)
        _bump_runtime_obstacle_version()
        return
    _obstacle_ref_counts[key] = next_count
    _bump_runtime_obstacle_version()

func is_walkable(grid_pos: Vector3i) -> bool:
    return is_walkable_static(grid_pos) and is_walkable_dynamic(grid_pos)

func is_walkable_static(_grid_pos: Vector3i) -> bool:
    return true

func is_walkable_dynamic(grid_pos: Vector3i) -> bool:
    var cell_key := _build_obstacle_key(grid_pos)
    return not _obstacle_ref_counts.has(cell_key) and not _runtime_occupants_by_cell.has(cell_key)

func is_walkable_for_pathfinding(grid_pos: Vector3i) -> bool:
    return is_walkable(grid_pos)

func is_walkable_for_actor(grid_pos: Vector3i, _actor: Node = null) -> bool:
    if not is_walkable_static(grid_pos):
        return false
    var cell_key := _build_obstacle_key(grid_pos)
    if _obstacle_ref_counts.has(cell_key):
        return false
    if _actor == null:
        return not _runtime_occupants_by_cell.has(cell_key)
    var occupants: Dictionary = _runtime_occupants_by_cell.get(cell_key, {})
    if occupants.is_empty():
        return true
    return occupants.size() == 1 and occupants.has(_build_actor_key(_actor))

func world_to_grid(world_pos: Vector3) -> Vector3i:
    return Vector3i(
        floor(world_pos.x / GRID_SIZE),
        floor(world_pos.y / GRID_SIZE),
        floor(world_pos.z / GRID_SIZE)
    )

func grid_to_world(grid_pos: Vector3i) -> Vector3:
    return Vector3(
        grid_pos.x * GRID_SIZE + GRID_SIZE / 2.0,
        grid_pos.y * GRID_SIZE + GRID_SIZE / 2.0,
        grid_pos.z * GRID_SIZE + GRID_SIZE / 2.0
    )

func snap_to_grid(world_pos: Vector3) -> Vector3:
    var grid_pos := world_to_grid(world_pos)
    return grid_to_world(grid_pos)

func get_all_obstacles() -> Array[Vector3i]:
    var obstacles: Array[Vector3i] = [Vector3i.ZERO]
    obstacles.clear()
    for key in _obstacle_ref_counts.keys():
        var parts: PackedStringArray = String(key).split("|")
        if parts.size() != 3:
            continue
        obstacles.append(Vector3i(int(parts[0]), int(parts[1]), int(parts[2])))
    return obstacles

func clear_obstacles() -> void:
    if _obstacle_ref_counts.is_empty():
        return
    _obstacle_ref_counts.clear()
    _bump_runtime_obstacle_version()

func get_runtime_blocked_cells() -> Array[Vector3i]:
    var blocked: Array[Vector3i] = get_all_obstacles()
    for key in _runtime_occupants_by_cell.keys():
        var grid_pos: Variant = _parse_grid_key(String(key))
        if grid_pos != null:
            blocked.append(grid_pos)
    return blocked

func get_pathfinding_bounds() -> Dictionary:
    var obstacle_cells: Array[Vector3i] = get_runtime_blocked_cells()
    if obstacle_cells.is_empty():
        return {}
    var min_grid: Vector3i = obstacle_cells[0]
    var max_grid: Vector3i = obstacle_cells[0]
    for grid_pos in obstacle_cells:
        min_grid = Vector3i(
            mini(min_grid.x, grid_pos.x),
            mini(min_grid.y, grid_pos.y),
            mini(min_grid.z, grid_pos.z)
        )
        max_grid = Vector3i(
            maxi(max_grid.x, grid_pos.x),
            maxi(max_grid.y, grid_pos.y),
            maxi(max_grid.z, grid_pos.z)
        )
    return {
        "min": min_grid,
        "max": max_grid
    }

func get_topology_version() -> int:
    return _topology_version

func get_runtime_obstacle_version() -> int:
    return _runtime_obstacle_version

func register_runtime_actor(actor: Node, world_pos: Vector3) -> void:
    if actor == null or not is_instance_valid(actor):
        return
    _set_runtime_actor_cell(actor, world_to_grid(world_pos))

func update_runtime_actor(actor: Node, world_pos: Vector3) -> void:
    if actor == null or not is_instance_valid(actor):
        return
    _set_runtime_actor_cell(actor, world_to_grid(world_pos))

func unregister_runtime_actor(actor: Node) -> void:
    if actor == null:
        return
    var actor_key := _build_actor_key(actor)
    if not _runtime_actor_cells.has(actor_key):
        return
    var previous_key: String = String(_runtime_actor_cells.get(actor_key, ""))
    _runtime_actor_cells.erase(actor_key)
    var occupants: Dictionary = _runtime_occupants_by_cell.get(previous_key, {})
    if occupants.has(actor_key):
        occupants.erase(actor_key)
        if occupants.is_empty():
            _runtime_occupants_by_cell.erase(previous_key)
        else:
            _runtime_occupants_by_cell[previous_key] = occupants
        _bump_runtime_obstacle_version()

func _build_obstacle_key(grid_pos: Vector3i) -> String:
    return "%d|%d|%d" % [grid_pos.x, grid_pos.y, grid_pos.z]

func _build_actor_key(actor: Node) -> String:
    return str(actor.get_instance_id())

func _set_runtime_actor_cell(actor: Node, grid_pos: Vector3i) -> void:
    var actor_key := _build_actor_key(actor)
    var next_key := _build_obstacle_key(grid_pos)
    var previous_key: String = String(_runtime_actor_cells.get(actor_key, ""))
    if previous_key == next_key:
        return

    if not previous_key.is_empty():
        var previous_occupants: Dictionary = _runtime_occupants_by_cell.get(previous_key, {})
        if previous_occupants.has(actor_key):
            previous_occupants.erase(actor_key)
            if previous_occupants.is_empty():
                _runtime_occupants_by_cell.erase(previous_key)
            else:
                _runtime_occupants_by_cell[previous_key] = previous_occupants

    var next_occupants: Dictionary = _runtime_occupants_by_cell.get(next_key, {})
    next_occupants[actor_key] = actor
    _runtime_occupants_by_cell[next_key] = next_occupants
    _runtime_actor_cells[actor_key] = next_key
    _bump_runtime_obstacle_version()

func _parse_grid_key(key: String) -> Variant:
    var parts: PackedStringArray = key.split("|")
    if parts.size() != 3:
        return null
    return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))

func _bump_topology_version() -> void:
    _topology_version += 1

func _bump_runtime_obstacle_version() -> void:
    _runtime_obstacle_version += 1
