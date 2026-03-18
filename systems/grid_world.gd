class_name GridWorld
extends Node

const GRID_SIZE := 1.0

var _obstacle_ref_counts: Dictionary = {}

func register_obstacle(world_pos: Vector3) -> void:
    var grid_pos := GridNavigator.new().world_to_grid(world_pos)
    var key := _build_obstacle_key(grid_pos)
    _obstacle_ref_counts[key] = int(_obstacle_ref_counts.get(key, 0)) + 1

func unregister_obstacle(world_pos: Vector3) -> void:
    var grid_pos := GridNavigator.new().world_to_grid(world_pos)
    var key := _build_obstacle_key(grid_pos)
    if not _obstacle_ref_counts.has(key):
        return
    var next_count: int = int(_obstacle_ref_counts.get(key, 0)) - 1
    if next_count <= 0:
        _obstacle_ref_counts.erase(key)
        return
    _obstacle_ref_counts[key] = next_count

func is_walkable(grid_pos: Vector3i) -> bool:
    return not _obstacle_ref_counts.has(_build_obstacle_key(grid_pos))

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
    _obstacle_ref_counts.clear()

func _build_obstacle_key(grid_pos: Vector3i) -> String:
    return "%d|%d|%d" % [grid_pos.x, grid_pos.y, grid_pos.z]
