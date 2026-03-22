class_name PathPlannerService
extends RefCounted

const GridWorldScript = preload("res://systems/grid_world.gd")
const PathPlannerBackendScript = preload("res://systems/path_planner_backend.gd")
const PathPlannerGdAStarScript = preload("res://systems/path_planner_gd_astar.gd")
const PathPlannerJpsNativeScript = preload("res://systems/path_planner_jps_native.gd")

var _fallback_backend: RefCounted = PathPlannerGdAStarScript.new()
var _native_backend: RefCounted = null
var _backend: RefCounted = _fallback_backend
var _configured_grid_world: Node = null
var _configured_topology_version: int = -1
var _configured_runtime_version: int = -1

func _init() -> void:
	_try_activate_native_backend()

func set_backend(backend: RefCounted) -> void:
	if backend == null:
		return
	_backend = backend
	_configured_grid_world = null
	_configured_topology_version = -1
	_configured_runtime_version = -1

func find_path_grid(
	start_grid: Vector3i,
	end_grid: Vector3i,
	grid_world: GridWorld
) -> Array[Vector3i]:
	if grid_world == null or _backend == null:
		return []
	_select_backend_for_grid_world(grid_world)
	_sync_backend(grid_world)
	return _backend.find_path_grid(start_grid, end_grid, grid_world)

func clear_runtime_state() -> void:
	if _backend != null:
		_backend.clear_runtime_state()
	_configured_grid_world = null
	_configured_topology_version = -1
	_configured_runtime_version = -1

func is_using_native_backend() -> bool:
	return _native_backend != null and _backend == _native_backend

func get_backend_name() -> String:
	if is_using_native_backend():
		return "native_jps"
	return "gd_astar"

func _sync_backend(grid_world: GridWorld) -> void:
	var topology_version: int = grid_world.get_topology_version()
	var runtime_version: int = grid_world.get_runtime_obstacle_version()
	var grid_world_changed: bool = grid_world != _configured_grid_world

	if grid_world_changed or topology_version != _configured_topology_version:
		_backend.configure_for_grid_world(grid_world)
		_backend.sync_runtime_obstacles(grid_world)
		_configured_grid_world = grid_world
		_configured_topology_version = topology_version
		_configured_runtime_version = runtime_version
		return

	if runtime_version != _configured_runtime_version:
		_backend.sync_runtime_obstacles(grid_world)
		_configured_runtime_version = runtime_version

func _try_activate_native_backend() -> void:
	var candidate = PathPlannerJpsNativeScript.new()
	if candidate != null and candidate.has_method("is_available") and bool(candidate.call("is_available")):
		_native_backend = candidate
		_backend = _native_backend

func _select_backend_for_grid_world(grid_world: GridWorld) -> void:
	var desired_backend: RefCounted = _fallback_backend
	if _native_backend != null and _native_backend.has_method("can_handle_grid_world"):
		if bool(_native_backend.call("can_handle_grid_world", grid_world)):
			desired_backend = _native_backend
	if desired_backend == _backend:
		return
	_backend = desired_backend
	_configured_grid_world = null
	_configured_topology_version = -1
	_configured_runtime_version = -1
