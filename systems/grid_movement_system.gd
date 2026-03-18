extends Node

var navigator: GridNavigator
var grid_world: GridWorld

func _ready() -> void:
    navigator = GridNavigator.new()
    grid_world = GridWorld.new()
    add_child(grid_world)

func find_path(start: Vector3, end: Vector3) -> Array[Vector3]:
    return navigator.find_path(start, end, grid_world.is_walkable)

func world_to_grid(world_pos: Vector3) -> Vector3i:
    return navigator.world_to_grid(world_pos)

func grid_to_world(grid_pos: Vector3i) -> Vector3:
    return navigator.grid_to_world(grid_pos)

func snap_to_grid(world_pos: Vector3) -> Vector3:
    return grid_world.snap_to_grid(world_pos)

func register_obstacle(world_pos: Vector3) -> void:
    grid_world.register_obstacle(world_pos)

func unregister_obstacle(world_pos: Vector3) -> void:
    grid_world.unregister_obstacle(world_pos)

func is_walkable(grid_pos: Vector3i) -> bool:
    return grid_world.is_walkable(grid_pos)
