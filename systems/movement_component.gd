class_name MovementComponent
extends Node

const GridMovement = preload("res://systems/grid_movement.gd")
const GridNavigator = preload("res://systems/grid_navigator.gd")
const GridWorld = preload("res://systems/grid_world.gd")

signal move_requested(world_pos: Vector3)
signal move_started(path: Array[Vector3])
signal move_finished
signal move_cancelled
signal move_failed(target_pos: Vector3)
signal movement_step_completed(grid_pos: Vector3i, world_pos: Vector3, step_index: int, total_steps: int)

@export var step_duration: float = 0.25
@export var ground_snap_enabled: bool = true
@export_flags_3d_physics var ground_collision_mask: int = 1
@export var ground_probe_height: float = 4.0
@export var ground_probe_depth: float = 12.0

var _grid_world: GridWorld = null
var _navigator: GridNavigator = null
var _grid_movement: GridMovement = null
var _owner_node: Node3D = null

func _ready() -> void:
	_navigator = GridNavigator.new()
	_grid_movement = GridMovement.new()
	_grid_movement.step_duration = step_duration
	add_child(_grid_movement)

	_grid_movement.movement_started.connect(_on_movement_started)
	_grid_movement.movement_finished.connect(_on_movement_finished)
	_grid_movement.movement_cancelled.connect(_on_movement_cancelled)
	_grid_movement.step_completed.connect(_on_step_completed)

func initialize(owner_node: Node3D, grid_world: GridWorld) -> void:
	_owner_node = owner_node
	_grid_world = grid_world

func set_grid_world(grid_world: GridWorld) -> void:
	_grid_world = grid_world

func move_to(world_pos: Vector3) -> bool:
	if not _owner_node or not _grid_world or not _navigator or not _grid_movement:
		move_failed.emit(world_pos)
		return false

	var start_pos := _owner_node.global_position
	if ground_snap_enabled:
		start_pos.y = _resolve_ground_y(start_pos, start_pos.y)
		_owner_node.global_position = start_pos
	var target_pos := world_pos
	target_pos.y = _resolve_ground_y(world_pos, start_pos.y) if ground_snap_enabled else start_pos.y

	var path := _navigator.find_path(start_pos, target_pos, _grid_world.is_walkable)
	if path.is_empty():
		move_failed.emit(target_pos)
		return false

	for i in range(path.size()):
		var point: Vector3 = path[i]
		point.y = _resolve_ground_y(point, start_pos.y) if ground_snap_enabled else start_pos.y
		path[i] = point

	move_requested.emit(target_pos)
	_grid_movement.move_along_path(path, _owner_node)
	return true

func cancel() -> void:
	if _grid_movement:
		_grid_movement.cancel_movement()

func is_moving() -> bool:
	return _grid_movement != null and _grid_movement.is_moving()

func _on_movement_started(path: Array[Vector3]) -> void:
	move_started.emit(path)

func _on_movement_finished() -> void:
	move_finished.emit()

func _on_movement_cancelled() -> void:
	move_cancelled.emit()

func _on_step_completed(world_pos: Vector3, step_index: int, total_steps: int) -> void:
	var grid_pos := Vector3i.ZERO
	if _grid_world:
		grid_pos = _grid_world.world_to_grid(world_pos)
	else:
		grid_pos = GridMovementSystem.world_to_grid(world_pos)
	movement_step_completed.emit(grid_pos, world_pos, step_index, total_steps)

func _resolve_ground_y(world_pos: Vector3, fallback_y: float) -> float:
	if not ground_snap_enabled or not _owner_node:
		return fallback_y
	var world_3d := _owner_node.get_world_3d()
	if not world_3d:
		return fallback_y

	var from := world_pos + Vector3(0.0, maxf(ground_probe_height, 0.1), 0.0)
	var to := world_pos - Vector3(0.0, maxf(ground_probe_depth, 0.1), 0.0)
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = ground_collision_mask
	query.exclude = [_owner_node.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return fallback_y
	return float(hit.position.y)
