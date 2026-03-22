class_name PathPlannerJpsNative
extends "res://systems/path_planner_backend.gd"

const NATIVE_CLASS_NAME: StringName = &"NativeJpsPlanner"
const GDEXTENSION_PATH: String = "res://native/jps_extension/native_jps.gdextension"

static var _extension_resource: Resource = null

var _native_planner: Object = null
var _configured_grid_world: GridWorld = null

func _init() -> void:
	if _extension_resource == null:
		_extension_resource = load(GDEXTENSION_PATH)
	if ClassDB.class_exists(NATIVE_CLASS_NAME):
		_native_planner = ClassDB.instantiate(StringName(NATIVE_CLASS_NAME))

func is_available() -> bool:
	return _native_planner != null

func can_handle_grid_world(grid_world: GridWorld) -> bool:
	if not is_available() or grid_world == null:
		return false
	var bounds: Dictionary = grid_world.get_pathfinding_bounds()
	return not bounds.is_empty()

func configure_for_grid_world(grid_world: GridWorld) -> void:
	_configured_grid_world = grid_world
	if not is_available() or grid_world == null:
		return
	var bounds: Dictionary = grid_world.get_pathfinding_bounds()
	if bounds.is_empty():
		return
	if _native_planner.has_method("rebuild_static_map"):
		_native_planner.call("rebuild_static_map", bounds, _build_static_blocked_cells(grid_world))
	if _native_planner.has_method("set_runtime_blocked_cells"):
		_native_planner.call("set_runtime_blocked_cells", grid_world.get_runtime_blocked_cells())

func sync_runtime_obstacles(grid_world: GridWorld) -> void:
	_configured_grid_world = grid_world
	if not is_available() or grid_world == null:
		return
	if _native_planner.has_method("set_runtime_blocked_cells"):
		_native_planner.call("set_runtime_blocked_cells", grid_world.get_runtime_blocked_cells())

func find_path_grid(
	start_grid: Vector3i,
	end_grid: Vector3i,
	grid_world: GridWorld
) -> Array[Vector3i]:
	if not is_available() or grid_world == null:
		return []
	if not _native_planner.has_method("find_path"):
		return []
	var result: Variant = _native_planner.call("find_path", start_grid, end_grid)
	return _extract_vector3i_array(result)

func clear_runtime_state() -> void:
	if is_available() and _native_planner.has_method("clear_runtime_state"):
		_native_planner.call("clear_runtime_state")
	_configured_grid_world = null

func _build_static_blocked_cells(grid_world: GridWorld) -> Array[Vector3i]:
	var bounds: Dictionary = grid_world.get_pathfinding_bounds()
	if bounds.is_empty():
		return []
	var min_grid: Vector3i = bounds["min"] if bounds.has("min") else Vector3i.ZERO
	var max_grid: Vector3i = bounds["max"] if bounds.has("max") else Vector3i.ZERO
	var blocked: Array[Vector3i] = []
	for x in range(min_grid.x, max_grid.x + 1):
		for y in range(min_grid.y, max_grid.y + 1):
			for z in range(min_grid.z, max_grid.z + 1):
				var grid_pos := Vector3i(x, y, z)
				if not grid_world.is_walkable_static(grid_pos):
					blocked.append(grid_pos)
	return blocked

func _extract_vector3i_array(path_variant: Variant) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	if not (path_variant is Array):
		return path
	for point_variant in path_variant:
		if point_variant is Vector3i:
			path.append(point_variant)
	return path
