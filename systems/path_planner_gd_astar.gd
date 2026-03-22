class_name PathPlannerGdAStar
extends "res://systems/path_planner_backend.gd"

const GridNavigatorScript = preload("res://systems/grid_navigator.gd")

var _navigator: GridNavigator = GridNavigatorScript.new()

func find_path_grid(
	start_grid: Vector3i,
	end_grid: Vector3i,
	grid_world: GridWorld
) -> Array[Vector3i]:
	if grid_world == null:
		return []
	return _navigator.find_path_grid(start_grid, end_grid, grid_world.is_walkable_for_pathfinding)
