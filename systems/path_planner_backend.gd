class_name PathPlannerBackend
extends RefCounted

const GridWorldScript = preload("res://systems/grid_world.gd")

func configure_for_grid_world(_grid_world: GridWorld) -> void:
	pass

func can_handle_grid_world(_grid_world: GridWorld) -> bool:
	return true

func sync_runtime_obstacles(_grid_world: GridWorld) -> void:
	pass

func find_path_grid(
	_start_grid: Vector3i,
	_end_grid: Vector3i,
	_grid_world: GridWorld
) -> Array[Vector3i]:
	return []

func clear_runtime_state() -> void:
	pass
