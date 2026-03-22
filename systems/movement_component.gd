class_name MovementComponent
extends Node

const GridWorldScript = preload("res://systems/grid_world.gd")
const GridNavigatorScript = preload("res://systems/grid_navigator.gd")
const GridMovementScript = preload("res://systems/grid_movement.gd")
const PathPlannerServiceScript = preload("res://systems/path_planner_service.gd")

signal move_requested(world_pos: Vector3)
signal move_started(path: Array[Vector3])
signal move_finished
signal move_cancelled
signal move_failed(target_pos: Vector3)
signal move_blocked(grid_pos: Vector3i, world_pos: Vector3, step_index: int, total_steps: int)
signal movement_step_completed(grid_pos: Vector3i, world_pos: Vector3, step_index: int, total_steps: int)

@export var step_duration: float = 0.25
@export var ground_snap_enabled: bool = true
@export_flags_3d_physics var ground_collision_mask: int = 1
@export var ground_probe_height: float = 4.0
@export var ground_probe_depth: float = 12.0
@export var occupies_runtime_grid: bool = false

var _grid_world: GridWorld = null
var _navigator: GridNavigator = null
var _grid_movement: GridMovement = null
var _owner_node: Node3D = null
var _path_planner_service: RefCounted = null
var _presented_move_active: bool = false
var _presented_move_job_id: String = ""
var _presented_move_token: int = 0

func _ready() -> void:
	_navigator = GridNavigatorScript.new()
	_path_planner_service = PathPlannerServiceScript.new()
	_grid_movement = GridMovementScript.new()
	_grid_movement.step_duration = step_duration
	add_child(_grid_movement)

	_grid_movement.movement_started.connect(_on_movement_started)
	_grid_movement.movement_finished.connect(_on_movement_finished)
	_grid_movement.movement_cancelled.connect(_on_movement_cancelled)
	_grid_movement.movement_blocked.connect(_on_movement_blocked)
	_grid_movement.step_completed.connect(_on_step_completed)

func initialize(owner_node: Node3D, grid_world: GridWorld) -> void:
	_owner_node = owner_node
	_grid_world = grid_world
	_sync_runtime_occupancy(false)

func _exit_tree() -> void:
	_clear_runtime_occupancy()

func set_grid_world(grid_world: GridWorld) -> void:
	_clear_runtime_occupancy()
	_grid_world = grid_world
	if _path_planner_service != null:
		_path_planner_service.clear_runtime_state()
	_sync_runtime_occupancy(false)

func move_to(world_pos: Vector3) -> bool:
	var path := find_path(world_pos)
	if path.is_empty():
		move_failed.emit(world_pos)
		return false
	return move_along_world_path(path)

func find_path(world_pos: Vector3) -> Array[Vector3]:
	if not _owner_node or not _grid_world or not _navigator or not _grid_movement:
		return []

	var start_pos := _owner_node.global_position
	if ground_snap_enabled:
		start_pos.y = _resolve_ground_y(start_pos, start_pos.y)
		_owner_node.global_position = start_pos
	var target_pos := world_pos
	target_pos.y = _resolve_ground_y(world_pos, start_pos.y) if ground_snap_enabled else start_pos.y

	var start_grid := _grid_world.world_to_grid(start_pos)
	var target_grid := _grid_world.world_to_grid(target_pos)
	var grid_path: Array[Vector3i] = []
	if _path_planner_service != null:
		grid_path = _path_planner_service.find_path_grid(start_grid, target_grid, _grid_world)
	else:
		grid_path = _navigator.find_path_grid(start_grid, target_grid, _grid_world.is_walkable_for_pathfinding)
	if grid_path.is_empty():
		return []

	if not grid_path.is_empty() and grid_path[0] == start_grid:
		grid_path.remove_at(0)
	if grid_path.is_empty():
		return []

	var path: Array[Vector3] = []
	for grid_pos in grid_path:
		var point: Vector3 = _grid_world.grid_to_world(grid_pos)
		point.y = _resolve_ground_y(point, start_pos.y) if ground_snap_enabled else start_pos.y
		path.append(point)

	return path

func move_along_world_path(path: Array[Vector3]) -> bool:
	if not _owner_node or not _grid_movement or path.is_empty():
		return false

	move_requested.emit(path[path.size() - 1])
	var should_use_presented_move: bool = (
		ActionPresentationSystem != null
		and ActionPresentationSystem.has_method("play")
		and TurnSystem != null
		and TurnSystem.has_method("is_in_combat")
		and TurnSystem.is_in_combat()
	)
	if should_use_presented_move:
		return _start_presented_move(path)
	_grid_movement.move_along_path(path, _owner_node, Callable(self, "_can_enter_world_position"))
	return true

func cancel() -> void:
	if _presented_move_active:
		_presented_move_token += 1
		_presented_move_active = false
		var actor: Node3D = _owner_node
		_presented_move_job_id = ""
		if ActionPresentationSystem != null and ActionPresentationSystem.has_method("cancel_jobs_for_actor") and actor != null:
			ActionPresentationSystem.cancel_jobs_for_actor(actor, "move")
		move_cancelled.emit()
		return
	if _grid_movement:
		_grid_movement.cancel_movement()

func is_moving() -> bool:
	return _presented_move_active or (_grid_movement != null and _grid_movement.is_moving())

func _start_presented_move(path: Array[Vector3]) -> bool:
	if _owner_node == null or not is_instance_valid(_owner_node) or path.is_empty():
		return false
	if _presented_move_active:
		cancel()

	_presented_move_active = true
	_presented_move_job_id = ""
	_presented_move_token += 1
	var move_token: int = _presented_move_token
	var move_path: Array[Vector3] = path.duplicate()
	var from_pos: Vector3 = _owner_node.global_position
	var to_pos: Vector3 = move_path[move_path.size() - 1]

	move_started.emit(move_path.duplicate())
	for step_index in range(move_path.size()):
		var step_world_pos: Vector3 = move_path[step_index]
		_owner_node.global_position = step_world_pos
		_emit_step_completed(step_world_pos, step_index, move_path.size())

	var handle: Variant = ActionPresentationSystem.play(_build_move_action_result(from_pos, to_pos, move_path))
	if handle is Dictionary and bool((handle as Dictionary).get("started", false)):
		_presented_move_job_id = str((handle as Dictionary).get("job_id", ""))
		call_deferred("_await_presented_move_completion", move_token, _presented_move_job_id)
		return true

	_complete_presented_move(move_token, true)
	return true

func _await_presented_move_completion(move_token: int, job_id: String) -> void:
	if job_id.is_empty() or ActionPresentationSystem == null or not ActionPresentationSystem.has_method("wait_for_job"):
		_complete_presented_move(move_token, true)
		return
	var result: Dictionary = await ActionPresentationSystem.wait_for_job(job_id)
	_complete_presented_move(move_token, not bool(result.get("cancelled", false)))

func _complete_presented_move(move_token: int, success: bool) -> void:
	if move_token != _presented_move_token:
		return
	_presented_move_active = false
	_presented_move_job_id = ""
	if success:
		move_finished.emit()
		return
	move_cancelled.emit()

func _build_move_action_result(from_pos: Vector3, to_pos: Vector3, path: Array[Vector3]) -> Dictionary:
	var in_combat: bool = bool(TurnSystem != null and TurnSystem.has_method("is_in_combat") and TurnSystem.is_in_combat())
	return {
		"actor": _owner_node,
		"action_type": "move",
		"mode": "combat" if in_combat else "noncombat",
		"wait_for_presentation": in_combat,
		"presentation_policy": "FULL_BLOCKING" if in_combat else "FULL_NONBLOCKING",
		"from_pos": from_pos,
		"to_pos": to_pos,
		"path": path.duplicate()
	}

func _emit_step_completed(world_pos: Vector3, step_index: int, total_steps: int) -> void:
	_sync_runtime_occupancy(true, world_pos)
	var grid_pos := Vector3i.ZERO
	if _grid_world:
		grid_pos = _grid_world.world_to_grid(world_pos)
	else:
		grid_pos = GridMovementSystem.world_to_grid(world_pos)
	movement_step_completed.emit(grid_pos, world_pos, step_index, total_steps)

func _on_movement_started(path: Array[Vector3]) -> void:
	move_started.emit(path)

func _on_movement_finished() -> void:
	move_finished.emit()

func _on_movement_cancelled() -> void:
	move_cancelled.emit()

func _on_movement_blocked(world_pos: Vector3, step_index: int, total_steps: int) -> void:
	_emit_move_blocked(world_pos, step_index, total_steps)

func _on_step_completed(world_pos: Vector3, step_index: int, total_steps: int) -> void:
	_emit_step_completed(world_pos, step_index, total_steps)

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

func _can_enter_world_position(world_pos: Vector3) -> bool:
	if _grid_world == null:
		return true
	var grid_pos: Vector3i = _grid_world.world_to_grid(world_pos)
	return _grid_world.is_walkable_for_actor(grid_pos, _owner_node)

func _emit_move_blocked(world_pos: Vector3, step_index: int, total_steps: int) -> void:
	var grid_pos := Vector3i.ZERO
	if _grid_world:
		grid_pos = _grid_world.world_to_grid(world_pos)
	else:
		grid_pos = GridMovementSystem.world_to_grid(world_pos)
	move_blocked.emit(grid_pos, world_pos, step_index, total_steps)

func _sync_runtime_occupancy(use_world_pos: bool, world_pos: Vector3 = Vector3.ZERO) -> void:
	if not occupies_runtime_grid or _grid_world == null or _owner_node == null or not is_instance_valid(_owner_node):
		return
	var resolved_world_pos: Vector3 = world_pos if use_world_pos else _owner_node.global_position
	_grid_world.update_runtime_actor(_owner_node, resolved_world_pos)

func _clear_runtime_occupancy() -> void:
	if not occupies_runtime_grid or _grid_world == null or _owner_node == null:
		return
	_grid_world.unregister_runtime_actor(_owner_node)
