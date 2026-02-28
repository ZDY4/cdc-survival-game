class_name GridWorld
extends Node

const GRID_SIZE := 1.0

var _walkable_grids: Dictionary = {}
var _obstacles: Array[Vector3i] = []

func register_obstacle(world_pos: Vector3) -> void:
    var grid_pos := GridNavigator.new().world_to_grid(world_pos)
    if not grid_pos in _obstacles:
        _obstacles.append(grid_pos)

func unregister_obstacle(world_pos: Vector3) -> void:
    var grid_pos := GridNavigator.new().world_to_grid(world_pos)
    _obstacles.erase(grid_pos)

func is_walkable(grid_pos: Vector3i) -> bool:
    return not grid_pos in _obstacles

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
    return _obstacles.duplicate()

func clear_obstacles() -> void:
    _obstacles.clear()
