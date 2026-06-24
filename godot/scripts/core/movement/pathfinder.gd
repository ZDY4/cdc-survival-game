extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")

const CARDINAL_OFFSETS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

const DIAGONAL_OFFSETS := [
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

const DEFAULT_MAX_VISITED_CELLS := 2048
const DEFAULT_TIME_BUDGET_MS := 8.0
const MAX_CACHE_ENTRIES := 64
const MAX_PACKED_BLOCKING_CACHE_ENTRIES := 16
const MAX_NATIVE_GRID_CACHE_ENTRIES := 8
const GOAL_ISLAND_PROBE_LIMIT := 16

var max_visited_cells: int = DEFAULT_MAX_VISITED_CELLS
var time_budget_ms: float = DEFAULT_TIME_BUDGET_MS
var profiler_budget_ms: float = DEFAULT_TIME_BUDGET_MS
var cache_enabled: bool = true
var native_grid_enabled: bool = true
var _cache: Dictionary = {}
var _cache_order: Array[String] = []
var _packed_blocking_cache: Dictionary = {}
var _packed_blocking_cache_order: Array[String] = []
var _native_grid_cache: Dictionary = {}
var _native_grid_cache_order: Array[String] = []
var _last_result: Dictionary = {}
var search_call_count: int = 0
var search_execution_count: int = 0
var native_grid_build_count: int = 0


func find_path(start: RefCounted, goal: RefCounted, topology: Dictionary, occupied_actor_cells: Dictionary = {}) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var invalid: Dictionary = _validate_start(start, "astar", started_usec, 1)
	if not invalid.is_empty():
		return invalid
	var goal_error: Dictionary = _validate_goal(start, goal, topology, occupied_actor_cells, 0)
	if not goal_error.is_empty():
		goal_error["algorithm"] = "astar"
		return _finish(goal_error, started_usec)
	if start.key() == goal.key():
		return _finish(_zero_step_result(start, "astar", 1, 1, [], goal), started_usec)

	var cache_key: String = _cache_key("astar", start, [goal], topology, occupied_actor_cells)
	if not cache_key.is_empty():
		var cached: Dictionary = _cache_get(cache_key)
		if not cached.is_empty():
			return _finish_cached(cached, started_usec)

	var result: Dictionary = _native_grid_path(start, [goal], topology, occupied_actor_cells, started_usec, "astar")
	if result.is_empty():
		result = _astar(start, [goal], topology, occupied_actor_cells, started_usec, "astar")
	if not cache_key.is_empty():
		_cache_put(cache_key, result)
	return result


func find_path_to_any(start: RefCounted, goals: Array[RefCounted], topology: Dictionary, occupied_actor_cells: Dictionary = {}) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var invalid: Dictionary = _validate_start(start, "multi_goal_astar", started_usec, goals.size())
	if not invalid.is_empty():
		return invalid

	var valid_goals: Array[RefCounted] = []
	var rejected_goals: Array[Dictionary] = []
	var seen_goal_keys: Dictionary = {}
	for index in range(goals.size()):
		var goal: RefCounted = goals[index]
		var goal_error: Dictionary = _validate_goal(start, goal, topology, occupied_actor_cells, index)
		if not goal_error.is_empty():
			rejected_goals.append(goal_error)
			continue
		var goal_key: String = goal.key()
		if seen_goal_keys.has(goal_key):
			continue
		seen_goal_keys[goal_key] = index
		valid_goals.append(goal)

	if valid_goals.is_empty():
		return _finish({
			"success": false,
			"reason": "goal_all_blocked" if not goals.is_empty() else "invalid_endpoint",
			"algorithm": "multi_goal_astar",
			"start": start.to_dictionary(),
			"goal_count": goals.size(),
			"valid_goal_count": 0,
			"rejected_goals": rejected_goals,
		}, started_usec)

	for goal in valid_goals:
		if start.key() == goal.key():
			return _finish(_zero_step_result(start, "multi_goal_astar", goals.size(), valid_goals.size(), rejected_goals, goal), started_usec)

	var cache_key: String = _cache_key("multi_goal_astar", start, valid_goals, topology, occupied_actor_cells)
	if not cache_key.is_empty():
		var cached: Dictionary = _cache_get(cache_key)
		if not cached.is_empty():
			var cached_result: Dictionary = _finish_cached(cached, started_usec)
			cached_result["goal_count"] = goals.size()
			cached_result["valid_goal_count"] = valid_goals.size()
			cached_result["rejected_goals"] = rejected_goals
			return cached_result

	var island_failure: Dictionary = _goal_island_unreachable(start, valid_goals, topology, occupied_actor_cells, started_usec)
	if not island_failure.is_empty():
		island_failure["goal_count"] = goals.size()
		island_failure["valid_goal_count"] = valid_goals.size()
		island_failure["rejected_goals"] = rejected_goals
		if not cache_key.is_empty():
			_cache_put(cache_key, island_failure)
		return island_failure

	var result: Dictionary = _native_grid_path(start, valid_goals, topology, occupied_actor_cells, started_usec, "multi_goal_astar")
	if result.is_empty():
		result = _astar(start, valid_goals, topology, occupied_actor_cells, started_usec, "multi_goal_astar", true)
	result["goal_count"] = goals.size()
	result["valid_goal_count"] = valid_goals.size()
	result["rejected_goals"] = rejected_goals
	if not cache_key.is_empty():
		_cache_put(cache_key, result)
	return result


func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()
	_packed_blocking_cache.clear()
	_packed_blocking_cache_order.clear()
	_native_grid_cache.clear()
	_native_grid_cache_order.clear()


func prepare_native_grid(topology: Dictionary) -> Dictionary:
	if not native_grid_enabled:
		return {"prepared": false, "reason": "native_grid_disabled"}
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	if bounds.is_empty():
		return {"prepared": false, "reason": "bounds_missing"}
	var min_x: int = int(bounds.get("min_x", 0))
	var max_x: int = int(bounds.get("max_x", 0))
	var min_z: int = int(bounds.get("min_z", 0))
	var max_z: int = int(bounds.get("max_z", 0))
	var before_build_count := native_grid_build_count
	var grid_state: Dictionary = _native_grid_state(topology, min_x, max_x, min_z, max_z)
	if grid_state.is_empty() or grid_state.get("astar") == null:
		return {"prepared": false, "reason": "native_grid_build_failed"}
	_sync_native_dynamic_solids(grid_state, {})
	return {
		"prepared": true,
		"cache_hit": native_grid_build_count == before_build_count,
		"native_grid_build_count": native_grid_build_count,
	}


func last_result() -> Dictionary:
	return _last_result.duplicate(true)


func _validate_start(start: RefCounted, algorithm: String, started_usec: int, goal_count: int) -> Dictionary:
	if start != null:
		return {}
	return _finish({
		"success": false,
		"reason": "invalid_endpoint",
		"algorithm": algorithm,
		"goal_count": goal_count,
	}, started_usec)


func _validate_goal(start: RefCounted, goal: RefCounted, topology: Dictionary, occupied_actor_cells: Dictionary, index: int) -> Dictionary:
	if goal == null:
		return {"success": false, "reason": "invalid_endpoint", "index": index}
	if start.y != goal.y:
		return {
			"success": false,
			"reason": "level_mismatch",
			"index": index,
			"start": start.to_dictionary(),
			"goal": goal.to_dictionary(),
			"start_level": start.y,
			"goal_level": goal.y,
		}
	if not _within_bounds(goal, topology):
		return {
			"success": false,
			"reason": "goal_out_of_bounds",
			"index": index,
			"goal": goal.to_dictionary(),
			"bounds": _dictionary_or_empty(topology.get("bounds", {})).duplicate(true),
		}
	var goal_blocking: Dictionary = _blocking_info(goal, topology, occupied_actor_cells, start.key())
	if not goal_blocking.is_empty():
		return {
			"success": false,
			"reason": "goal_occupied" if str(goal_blocking.get("kind", "")) == "actor" else "goal_blocked",
			"index": index,
			"goal": goal.to_dictionary(),
			"blocker": goal_blocking,
		}
	return {}


func _zero_step_result(start: RefCounted, algorithm: String, goal_count: int, valid_goal_count: int, rejected_goals: Array[Dictionary], goal: RefCounted) -> Dictionary:
	return {
		"success": true,
		"algorithm": algorithm,
		"path": [start.to_dictionary()],
		"steps": 0,
		"visited_cell_count": 1,
		"expanded_cell_count": 0,
		"max_frontier_size": 1,
		"goal_count": goal_count,
		"valid_goal_count": valid_goal_count,
		"rejected_goals": rejected_goals,
		"chosen_goal": goal.to_dictionary(),
	}


func _astar(start: RefCounted, goals: Array[RefCounted], topology: Dictionary, occupied_actor_cells: Dictionary, started_usec: int, algorithm: String, reverse_search: bool = false) -> Dictionary:
	search_execution_count += 1
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	var min_x: int = int(bounds.get("min_x", 0))
	var max_x: int = int(bounds.get("max_x", 0))
	var min_z: int = int(bounds.get("min_z", 0))
	var max_z: int = int(bounds.get("max_z", 0))
	var width: int = max(1, max_x - min_x + 1)
	var height: int = max(1, max_z - min_z + 1)
	var cell_count: int = width * height
	var origin_key: int = _packed_key(start.x, start.z, min_x, min_z, width)
	var blocking_mask: PackedByteArray = _packed_blocking_cell_mask(topology, min_x, min_z, width, cell_count)
	var occupied_packed: Dictionary = _packed_cell_keys(occupied_actor_cells, min_x, min_z, width)
	var search_roots: Array[RefCounted] = []
	var target_coords: Array[RefCounted] = []
	if reverse_search:
		search_roots = goals.duplicate()
		target_coords.append(start)
	else:
		search_roots.append(start)
		target_coords = goals.duplicate()
	var target_mask := PackedByteArray()
	target_mask.resize(cell_count)
	target_mask.fill(0)
	var target_points := PackedInt32Array()
	for target in target_coords:
		var target_key: int = _packed_key(target.x, target.z, min_x, min_z, width)
		if target_key >= 0 and target_key < cell_count:
			target_mask[target_key] = 1
			target_points.append(target.x)
			target_points.append(target.z)

	var open_heap: Array[Array] = []
	var push_seq := 0
	var came_from := PackedInt32Array()
	came_from.resize(cell_count)
	came_from.fill(-2)
	var g_score := PackedInt32Array()
	g_score.resize(cell_count)
	g_score.fill(999999)
	var closed := PackedByteArray()
	closed.resize(cell_count)
	closed.fill(0)
	var visited_count := 0
	for root in search_roots:
		var root_key: int = _packed_key(root.x, root.z, min_x, min_z, width)
		if root_key < 0 or root_key >= cell_count or came_from[root_key] != -2:
			continue
		var root_h: float = _heuristic_to_goal_points(root.x, root.z, target_points)
		_heap_push(open_heap, [root_h, root_h, push_seq, root_key, root.x, root.y, root.z])
		push_seq += 1
		came_from[root_key] = -1
		g_score[root_key] = 0
		visited_count += 1
	var expanded_count := 0
	var max_frontier_size := open_heap.size()

	while not open_heap.is_empty():
		if visited_count >= max_visited_cells or (time_budget_ms > 0.0 and _elapsed_ms(started_usec) > time_budget_ms):
			return _finish({
				"success": false,
				"reason": "pathfinding_budget_exceeded",
				"algorithm": algorithm,
				"budget_exceeded": true,
				"start": start.to_dictionary(),
				"goal": goals[0].to_dictionary() if goals.size() == 1 else {},
				"goal_count": goals.size(),
				"visited_cell_count": visited_count,
				"expanded_cell_count": expanded_count,
				"max_frontier_size": max_frontier_size,
			}, started_usec)

		var heap_item: Array = _heap_pop_min(open_heap)
		var current_key: int = int(heap_item[3])
		if current_key < 0 or current_key >= cell_count or closed[current_key] != 0:
			continue
		closed[current_key] = 1
		var current_steps: int = int(g_score[current_key])

		if target_mask[current_key] != 0:
			if reverse_search:
				return _success_result_reverse(origin_key, came_from, algorithm, goals.size(), visited_count, expanded_count, max_frontier_size, started_usec, min_x, min_z, width, start.y)
			return _success_result(origin_key, current_key, came_from, algorithm, goals.size(), visited_count, expanded_count, max_frontier_size, started_usec, min_x, min_z, width, start.y)

		expanded_count += 1
		var current_x: int = int(heap_item[4])
		var current_y: int = int(heap_item[5])
		var current_z: int = int(heap_item[6])
		for offset in CARDINAL_OFFSETS:
			var next_x: int = current_x + offset.x
			var next_z: int = current_z + offset.y
			if not _append_astar_neighbor(open_heap, came_from, g_score, closed, origin_key, current_key, current_steps, current_y, next_x, next_z, target_points, push_seq, min_x, max_x, min_z, max_z, width, cell_count, blocking_mask, occupied_packed):
				continue
			push_seq += 1
			visited_count += 1
			max_frontier_size = max(max_frontier_size, open_heap.size())
		for offset in DIAGONAL_OFFSETS:
			var next_x: int = current_x + offset.x
			var next_z: int = current_z + offset.y
			if _diagonal_corner_blocked_fast(current_x, current_z, offset, min_x, min_z, width, origin_key, blocking_mask, occupied_packed):
				continue
			if not _append_astar_neighbor(open_heap, came_from, g_score, closed, origin_key, current_key, current_steps, current_y, next_x, next_z, target_points, push_seq, min_x, max_x, min_z, max_z, width, cell_count, blocking_mask, occupied_packed):
				continue
			push_seq += 1
			visited_count += 1
			max_frontier_size = max(max_frontier_size, open_heap.size())

	return _finish({
		"success": false,
		"reason": "path_unreachable",
		"algorithm": algorithm,
		"start": start.to_dictionary(),
		"goal": goals[0].to_dictionary() if goals.size() == 1 else {},
		"goal_count": goals.size(),
		"visited_cell_count": visited_count,
		"expanded_cell_count": expanded_count,
		"max_frontier_size": max_frontier_size,
	}, started_usec)


func _native_grid_path(start: RefCounted, goals: Array[RefCounted], topology: Dictionary, occupied_actor_cells: Dictionary, started_usec: int, algorithm: String) -> Dictionary:
	if not native_grid_enabled:
		return {}
	if start == null or goals.is_empty():
		return {}
	search_execution_count += 1
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	var min_x: int = int(bounds.get("min_x", 0))
	var max_x: int = int(bounds.get("max_x", 0))
	var min_z: int = int(bounds.get("min_z", 0))
	var max_z: int = int(bounds.get("max_z", 0))
	var grid_state: Dictionary = _native_grid_state(topology, min_x, max_x, min_z, max_z)
	var astar: AStarGrid2D = grid_state.get("astar") as AStarGrid2D
	if astar == null:
		return {}
	var start_point := Vector2i(start.x, start.z)
	_sync_native_dynamic_solids(
		grid_state,
		_occupied_point_solid_keys(occupied_actor_cells, start.key(), min_x, max_x, min_z, max_z)
	)
	var best_path: PackedVector2Array = PackedVector2Array()
	var best_goal: RefCounted = null
	var searched_goals := 0
	for goal in goals:
		var goal_point := Vector2i(goal.x, goal.z)
		if not _point_in_bounds(goal_point, min_x, max_x, min_z, max_z) or astar.is_point_solid(goal_point):
			continue
		searched_goals += 1
		var path: PackedVector2Array = astar.get_id_path(start_point, goal_point)
		if time_budget_ms > 0.0 and _elapsed_ms(started_usec) > time_budget_ms:
			return _finish({
				"success": false,
				"reason": "pathfinding_budget_exceeded",
				"algorithm": algorithm,
				"budget_exceeded": true,
				"start": start.to_dictionary(),
				"goal": goals[0].to_dictionary() if goals.size() == 1 else {},
				"goal_count": goals.size(),
				"visited_cell_count": best_path.size(),
				"expanded_cell_count": searched_goals,
				"max_frontier_size": 0,
			}, started_usec)
		if path.is_empty():
			continue
		if best_goal == null or path.size() < best_path.size():
			best_path = path
			best_goal = goal
	if best_goal == null:
		return _finish({
			"success": false,
			"reason": "path_unreachable",
			"algorithm": algorithm,
			"start": start.to_dictionary(),
			"goal": goals[0].to_dictionary() if not goals.is_empty() else {},
			"goal_count": goals.size(),
			"visited_cell_count": max(1, searched_goals),
			"expanded_cell_count": searched_goals,
			"max_frontier_size": 0,
		}, started_usec)
	var output_path: Array[Dictionary] = []
	for point in best_path:
		output_path.append({
			"x": int(point.x),
			"y": start.y,
			"z": int(point.y),
		})
	if output_path.size() >= max_visited_cells:
		return _finish({
			"success": false,
			"reason": "pathfinding_budget_exceeded",
			"algorithm": algorithm,
			"budget_exceeded": true,
			"start": start.to_dictionary(),
			"goal": goals[0].to_dictionary() if goals.size() == 1 else {},
			"goal_count": goals.size(),
			"visited_cell_count": output_path.size(),
			"expanded_cell_count": searched_goals,
			"max_frontier_size": 0,
		}, started_usec)
	return _finish({
		"success": true,
		"algorithm": algorithm,
		"chosen_goal": best_goal.to_dictionary(),
		"goal_count": goals.size(),
		"path": output_path,
		"steps": max(0, output_path.size() - 1),
		"visited_cell_count": output_path.size(),
		"expanded_cell_count": searched_goals,
		"max_frontier_size": 0,
	}, started_usec)


func _goal_island_unreachable(start: RefCounted, goals: Array[RefCounted], topology: Dictionary, occupied_actor_cells: Dictionary, started_usec: int) -> Dictionary:
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	var min_x: int = int(bounds.get("min_x", 0))
	var max_x: int = int(bounds.get("max_x", 0))
	var min_z: int = int(bounds.get("min_z", 0))
	var max_z: int = int(bounds.get("max_z", 0))
	var width: int = max(1, max_x - min_x + 1)
	var height: int = max(1, max_z - min_z + 1)
	var cell_count: int = width * height
	var start_key: int = _packed_key(start.x, start.z, min_x, min_z, width)
	var blocking_mask: PackedByteArray = _packed_blocking_cell_mask(topology, min_x, min_z, width, cell_count)
	var occupied_packed: Dictionary = _packed_cell_keys(occupied_actor_cells, min_x, min_z, width)
	var frontier: Array[Dictionary] = []
	var came_from: Dictionary = {}
	var cursor := 0
	for goal in goals:
		var goal_key: int = _packed_key(goal.x, goal.z, min_x, min_z, width)
		if came_from.has(goal_key):
			continue
		came_from[goal_key] = -1
		frontier.append({
			"key": goal_key,
			"x": goal.x,
			"y": goal.y,
			"z": goal.z,
		})
	while cursor < frontier.size() and came_from.size() <= GOAL_ISLAND_PROBE_LIMIT:
		if time_budget_ms > 0.0 and _elapsed_ms(started_usec) > time_budget_ms:
			return {}
		var current: Dictionary = frontier[cursor]
		cursor += 1
		var current_key: int = int(current.get("key", -1))
		if current_key == start_key:
			return {}
		var current_x: int = int(current.get("x", 0))
		var current_z: int = int(current.get("z", 0))
		for offset in CARDINAL_OFFSETS:
			_append_probe_neighbor(frontier, came_from, start_key, current_key, current_x + offset.x, current_z + offset.y, start.y, min_x, max_x, min_z, max_z, width, blocking_mask, occupied_packed)
		for offset in DIAGONAL_OFFSETS:
			if _diagonal_corner_blocked_fast(current_x, current_z, offset, min_x, min_z, width, start_key, blocking_mask, occupied_packed):
				continue
			_append_probe_neighbor(frontier, came_from, start_key, current_key, current_x + offset.x, current_z + offset.y, start.y, min_x, max_x, min_z, max_z, width, blocking_mask, occupied_packed)
	if cursor < frontier.size():
		return {}
	search_execution_count += 1
	return _finish({
		"success": false,
		"reason": "path_unreachable",
		"algorithm": "multi_goal_astar",
		"start": start.to_dictionary(),
		"goal": goals[0].to_dictionary() if not goals.is_empty() else {},
		"goal_count": goals.size(),
		"visited_cell_count": came_from.size(),
		"expanded_cell_count": cursor,
		"max_frontier_size": frontier.size(),
	}, started_usec)


func _append_probe_neighbor(
	frontier: Array[Dictionary],
	came_from: Dictionary,
	start_key: int,
	current_key: int,
	next_x: int,
	next_z: int,
	y: int,
	min_x: int,
	max_x: int,
	min_z: int,
	max_z: int,
	width: int,
	blocking_mask: PackedByteArray,
	occupied_packed: Dictionary
) -> void:
	if next_x < min_x or next_x > max_x or next_z < min_z or next_z > max_z:
		return
	var next_key: int = _packed_key(next_x, next_z, min_x, min_z, width)
	if came_from.has(next_key) or _blocked_packed(next_key, start_key, blocking_mask, occupied_packed):
		return
	came_from[next_key] = current_key
	frontier.append({
		"key": next_key,
		"x": next_x,
		"y": y,
		"z": next_z,
	})


func _append_astar_neighbor(
	open_heap: Array[Array],
	came_from: PackedInt32Array,
	g_score: PackedInt32Array,
	closed: PackedByteArray,
	start_key: int,
	current_key: int,
	current_steps: int,
	y: int,
	next_x: int,
	next_z: int,
	goal_points: PackedInt32Array,
	push_seq: int,
	min_x: int,
	max_x: int,
	min_z: int,
	max_z: int,
	width: int,
	cell_count: int,
	blocking_mask: PackedByteArray,
	occupied_packed: Dictionary
) -> bool:
	if next_x < min_x or next_x > max_x or next_z < min_z or next_z > max_z:
		return false
	var next_key: int = _packed_key(next_x, next_z, min_x, min_z, width)
	if next_key < 0 or next_key >= cell_count or closed[next_key] != 0 or _blocked_packed(next_key, start_key, blocking_mask, occupied_packed):
		return false
	var tentative_g: int = current_steps + 1
	if came_from[next_key] != -2 and tentative_g >= int(g_score[next_key]):
		return false
	came_from[next_key] = current_key
	g_score[next_key] = tentative_g
	var heuristic: float = _heuristic_to_goal_points(next_x, next_z, goal_points)
	_heap_push(open_heap, [float(tentative_g) + heuristic, heuristic, push_seq, next_key, next_x, y, next_z])
	return true


func _success_result(start_key: int, goal_key: int, came_from: PackedInt32Array, algorithm: String, goal_count: int, visited_count: int, expanded_count: int, max_frontier_size: int, started_usec: int, min_x: int, min_z: int, width: int, y: int) -> Dictionary:
	var path: Array[Dictionary] = _reconstruct_path(start_key, goal_key, came_from, min_x, min_z, width, y)
	return _finish({
		"success": true,
		"algorithm": algorithm,
		"chosen_goal": _coord_from_packed(goal_key, min_x, min_z, width, y),
		"goal_count": goal_count,
		"path": path,
		"steps": _path_length(start_key, goal_key, came_from),
		"visited_cell_count": visited_count,
		"expanded_cell_count": expanded_count,
		"max_frontier_size": max_frontier_size,
	}, started_usec)


func _success_result_reverse(start_key: int, came_from: PackedInt32Array, algorithm: String, goal_count: int, visited_count: int, expanded_count: int, max_frontier_size: int, started_usec: int, min_x: int, min_z: int, width: int, y: int) -> Dictionary:
	var path: Array[Dictionary] = []
	var current_key: int = start_key
	while current_key >= 0:
		path.append(_coord_from_packed(current_key, min_x, min_z, width, y))
		current_key = int(came_from[current_key])
	var goal_key: int = start_key if path.is_empty() else _packed_key(int(path.back().get("x", 0)), int(path.back().get("z", 0)), min_x, min_z, width)
	return _finish({
		"success": true,
		"algorithm": algorithm,
		"chosen_goal": _coord_from_packed(goal_key, min_x, min_z, width, y),
		"goal_count": goal_count,
		"path": path,
		"steps": max(0, path.size() - 1),
		"visited_cell_count": visited_count,
		"expanded_cell_count": expanded_count,
		"max_frontier_size": max_frontier_size,
	}, started_usec)


func _finish(result: Dictionary, started_usec: int) -> Dictionary:
	result["pathfinding_time_ms"] = max(0.0, float(Time.get_ticks_usec() - started_usec) / 1000.0)
	if not result.has("algorithm"):
		result["algorithm"] = "unknown"
	if not result.has("visited_cell_count"):
		result["visited_cell_count"] = 0
	if not result.has("expanded_cell_count"):
		result["expanded_cell_count"] = 0
	if not result.has("max_frontier_size"):
		result["max_frontier_size"] = 0
	if not result.has("budget_exceeded"):
		result["budget_exceeded"] = false
	result["profiler_budget_ms"] = profiler_budget_ms
	result["over_profiler_budget"] = float(result.get("pathfinding_time_ms", 0.0)) > profiler_budget_ms
	if not bool(result.get("_skip_profiler_record", false)):
		search_call_count += 1
		result["search_call_count"] = search_call_count
		result["search_execution_count"] = search_execution_count
		result["native_grid_build_count"] = native_grid_build_count
		_last_result = result.duplicate(true)
	result.erase("_skip_profiler_record")
	return result


func _finish_cached(cached: Dictionary, started_usec: int) -> Dictionary:
	var result: Dictionary = cached.duplicate(true)
	result["cache_hit"] = true
	result["_skip_profiler_record"] = false
	return _finish(result, started_usec)


func _elapsed_ms(started_usec: int) -> float:
	return max(0.0, float(Time.get_ticks_usec() - started_usec) / 1000.0)


func _neighbors(coord: RefCounted, topology: Dictionary, occupied_actor_cells: Dictionary, start_key: String) -> Array[RefCounted]:
	var output: Array[RefCounted] = []
	for offset in CARDINAL_OFFSETS:
		_append_neighbor(output, coord, offset, topology, occupied_actor_cells, start_key)
	for offset in DIAGONAL_OFFSETS:
		_append_neighbor(output, coord, offset, topology, occupied_actor_cells, start_key)
	return output


func _append_neighbor(output: Array[RefCounted], coord: RefCounted, offset: Vector2i, topology: Dictionary, occupied_actor_cells: Dictionary, start_key: String) -> void:
	var next := GridCoord.new(coord.x + offset.x, coord.y, coord.z + offset.y)
	if not _within_bounds(next, topology):
		return
	if _blocked(next, topology, occupied_actor_cells, start_key):
		return
	if offset.x != 0 and offset.y != 0 and _diagonal_corner_blocked(coord, offset, topology, occupied_actor_cells, start_key):
		return
	output.append(next)


func _diagonal_corner_blocked(coord: RefCounted, offset: Vector2i, topology: Dictionary, occupied_actor_cells: Dictionary, start_key: String) -> bool:
	var side_x := GridCoord.new(coord.x + offset.x, coord.y, coord.z)
	var side_z := GridCoord.new(coord.x, coord.y, coord.z + offset.y)
	return _blocked(side_x, topology, occupied_actor_cells, start_key) or _blocked(side_z, topology, occupied_actor_cells, start_key)


func _diagonal_corner_blocked_fast(x: int, z: int, offset: Vector2i, min_x: int, min_z: int, width: int, start_key: int, blocking_mask: PackedByteArray, occupied_packed: Dictionary) -> bool:
	return _blocked_packed(_packed_key(x + offset.x, z, min_x, min_z, width), start_key, blocking_mask, occupied_packed) \
		or _blocked_packed(_packed_key(x, z + offset.y, min_x, min_z, width), start_key, blocking_mask, occupied_packed)


func _within_bounds(coord: RefCounted, topology: Dictionary) -> bool:
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	return coord.x >= int(bounds.get("min_x", 0)) \
		and coord.x <= int(bounds.get("max_x", 0)) \
		and coord.z >= int(bounds.get("min_z", 0)) \
		and coord.z <= int(bounds.get("max_z", 0))


func _within_bounds_fast(x: int, z: int, topology: Dictionary) -> bool:
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	return x >= int(bounds.get("min_x", 0)) \
		and x <= int(bounds.get("max_x", 0)) \
		and z >= int(bounds.get("min_z", 0)) \
		and z <= int(bounds.get("max_z", 0))


func _blocked(coord: RefCounted, topology: Dictionary, occupied_actor_cells: Dictionary, start_key: String) -> bool:
	return not _blocking_info(coord, topology, occupied_actor_cells, start_key).is_empty()


func _blocked_key(key: String, topology: Dictionary, occupied_actor_cells: Dictionary, start_key: String) -> bool:
	var blocking_cells: Dictionary = _dictionary_or_empty(topology.get("blocking_cells", {}))
	return blocking_cells.has(key) or (key != start_key and occupied_actor_cells.has(key))


func _blocked_packed(key: int, start_key: int, blocking_mask: PackedByteArray, occupied_packed: Dictionary) -> bool:
	return key >= 0 and key < blocking_mask.size() and (blocking_mask[key] != 0 or (key != start_key and occupied_packed.has(key)))


func _blocking_info(coord: RefCounted, topology: Dictionary, occupied_actor_cells: Dictionary, start_key: String) -> Dictionary:
	var key: String = coord.key()
	var blocking_cells: Dictionary = _dictionary_or_empty(topology.get("blocking_cells", {}))
	if blocking_cells.has(key):
		return {
			"kind": "map_object",
			"key": key,
			"id": blocking_cells.get(key),
		}
	if key != start_key and occupied_actor_cells.has(key):
		return {
			"kind": "actor",
			"key": key,
			"actor_id": int(occupied_actor_cells.get(key, 0)),
		}
	return {}


func _heuristic_to_any(coord: RefCounted, goals: Array[RefCounted]) -> float:
	var best := 999999
	for goal in goals:
		var dx: int = abs(coord.x - goal.x)
		var dz: int = abs(coord.z - goal.z)
		best = min(best, max(dx, dz))
	return float(best)


func _heuristic_to_goal_data(x: int, z: int, goals: Array[Dictionary]) -> float:
	var best := 999999
	for goal in goals:
		var dx: int = abs(x - int(goal.get("x", 0)))
		var dz: int = abs(z - int(goal.get("z", 0)))
		best = min(best, max(dx, dz))
	return float(best)


func _heuristic_to_goal_points(x: int, z: int, goal_points: PackedInt32Array) -> float:
	var best := 999999
	var index := 0
	while index + 1 < goal_points.size():
		var dx: int = abs(x - int(goal_points[index]))
		var dz: int = abs(z - int(goal_points[index + 1]))
		best = min(best, max(dx, dz))
		index += 2
	return float(best)


func _reconstruct_path(start_key: int, goal_key: int, came_from: PackedInt32Array, min_x: int, min_z: int, width: int, y: int) -> Array[Dictionary]:
	var reversed: Array[Dictionary] = []
	var current_key: int = goal_key
	while current_key >= 0:
		reversed.append(_coord_from_packed(current_key, min_x, min_z, width, y))
		if current_key == start_key:
			break
		current_key = int(came_from[current_key])
	reversed.reverse()
	return reversed


func _path_length(start_key: int, goal_key: int, came_from: PackedInt32Array) -> int:
	var steps := 0
	var current_key: int = goal_key
	while current_key != start_key and current_key >= 0:
		steps += 1
		current_key = int(came_from[current_key])
	return steps


func _coord_key(x: int, y: int, z: int) -> String:
	return "%d:%d:%d" % [x, y, z]


func _packed_key(x: int, z: int, min_x: int, min_z: int, width: int) -> int:
	return (z - min_z) * width + (x - min_x)


func _coord_from_packed(key: int, min_x: int, min_z: int, width: int, y: int) -> Dictionary:
	var local_z: int = int(key / width)
	return {
		"x": min_x + key - local_z * width,
		"y": y,
		"z": min_z + local_z,
	}


func _point_from_cell_key(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(":")
	if parts.size() < 3:
		return Vector2i(999999, 999999)
	return Vector2i(int(parts[0]), int(parts[2]))


func _point_in_bounds(point: Vector2i, min_x: int, max_x: int, min_z: int, max_z: int) -> bool:
	return point.x >= min_x and point.x <= max_x and point.y >= min_z and point.y <= max_z


func _packed_cell_keys(cells: Dictionary, min_x: int, min_z: int, width: int) -> Dictionary:
	var output: Dictionary = {}
	for key in cells.keys():
		var text: String = str(key)
		var parts: PackedStringArray = text.split(":")
		if parts.size() < 3:
			continue
		output[_packed_key(int(parts[0]), int(parts[2]), min_x, min_z, width)] = true
	return output


func _native_grid_state(topology: Dictionary, min_x: int, max_x: int, min_z: int, max_z: int) -> Dictionary:
	var cache_key: String = _native_grid_cache_key(topology, min_x, max_x, min_z, max_z)
	if not cache_key.is_empty() and _native_grid_cache.has(cache_key):
		_native_grid_cache_order.erase(cache_key)
		_native_grid_cache_order.append(cache_key)
		return _dictionary_or_empty(_native_grid_cache.get(cache_key, {}))
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(min_x, min_z, max_x - min_x + 1, max_z - min_z + 1)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	astar.update()
	var static_solid_points: Dictionary = {}
	for key in _dictionary_or_empty(topology.get("blocking_cells", {})).keys():
		var point: Vector2i = _point_from_cell_key(str(key))
		if not _point_in_bounds(point, min_x, max_x, min_z, max_z):
			continue
		var point_key := _point_key(point)
		static_solid_points[point_key] = true
		astar.set_point_solid(point, true)
	var state := {
		"astar": astar,
		"static_solid_points": static_solid_points,
		"dynamic_solid_points": {},
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
	}
	native_grid_build_count += 1
	if cache_key.is_empty():
		return state
	_native_grid_cache[cache_key] = state
	_native_grid_cache_order.erase(cache_key)
	_native_grid_cache_order.append(cache_key)
	while _native_grid_cache_order.size() > MAX_NATIVE_GRID_CACHE_ENTRIES:
		var evicted_key: String = _native_grid_cache_order.pop_front()
		_native_grid_cache.erase(evicted_key)
	return state


func _sync_native_dynamic_solids(grid_state: Dictionary, next_dynamic_points: Dictionary) -> void:
	var astar: AStarGrid2D = grid_state.get("astar") as AStarGrid2D
	if astar == null:
		return
	var current_dynamic_points: Dictionary = _dictionary_or_empty(grid_state.get("dynamic_solid_points", {}))
	var static_solid_points: Dictionary = _dictionary_or_empty(grid_state.get("static_solid_points", {}))
	for key in current_dynamic_points.keys():
		if next_dynamic_points.has(key):
			continue
		var point: Vector2i = current_dynamic_points.get(key)
		if not static_solid_points.has(key):
			astar.set_point_solid(point, false)
	for key in next_dynamic_points.keys():
		if current_dynamic_points.has(key):
			continue
		var point: Vector2i = next_dynamic_points.get(key)
		if not static_solid_points.has(key):
			astar.set_point_solid(point, true)
	grid_state["dynamic_solid_points"] = next_dynamic_points


func _occupied_point_solid_keys(occupied_actor_cells: Dictionary, start_key: String, min_x: int, max_x: int, min_z: int, max_z: int) -> Dictionary:
	var output: Dictionary = {}
	for key in occupied_actor_cells.keys():
		var cell_key := str(key)
		if cell_key == start_key:
			continue
		var point: Vector2i = _point_from_cell_key(cell_key)
		if not _point_in_bounds(point, min_x, max_x, min_z, max_z):
			continue
		output[_point_key(point)] = point
	return output


func _native_grid_cache_key(topology: Dictionary, min_x: int, max_x: int, min_z: int, max_z: int) -> String:
	var cells: Dictionary = _dictionary_or_empty(topology.get("blocking_cells", {}))
	var topology_revision: String = str(topology.get("topology_revision", topology.get("revision", "")))
	var map_id: String = str(topology.get("map_id", topology.get("id", "")))
	return "%s|%s|%d:%d:%d:%d|%d|%d" % [
		map_id,
		topology_revision,
		min_x,
		max_x,
		min_z,
		max_z,
		cells.size(),
		hash(cells),
	]


func _point_key(point: Vector2i) -> String:
	return "%d:%d" % [point.x, point.y]


func _packed_blocking_cell_keys(topology: Dictionary, min_x: int, min_z: int, width: int) -> Dictionary:
	var cells: Dictionary = _dictionary_or_empty(topology.get("blocking_cells", {}))
	var cache_key: String = _packed_blocking_cache_key(topology, cells, min_x, min_z, width)
	if not cache_key.is_empty() and _packed_blocking_cache.has(cache_key):
		_packed_blocking_cache_order.erase(cache_key)
		_packed_blocking_cache_order.append(cache_key)
		return _dictionary_or_empty(_packed_blocking_cache.get(cache_key, {}))
	var packed: Dictionary = _packed_cell_keys(cells, min_x, min_z, width)
	if not cache_key.is_empty():
		_packed_blocking_cache[cache_key] = packed
		_packed_blocking_cache_order.erase(cache_key)
		_packed_blocking_cache_order.append(cache_key)
		while _packed_blocking_cache_order.size() > MAX_PACKED_BLOCKING_CACHE_ENTRIES:
			var evicted_key: String = _packed_blocking_cache_order.pop_front()
			_packed_blocking_cache.erase(evicted_key)
	return packed


func _packed_blocking_cell_mask(topology: Dictionary, min_x: int, min_z: int, width: int, cell_count: int) -> PackedByteArray:
	var cells: Dictionary = _dictionary_or_empty(topology.get("blocking_cells", {}))
	var cache_key: String = _packed_blocking_cache_key(topology, cells, min_x, min_z, width)
	if not cache_key.is_empty() and _packed_blocking_cache.has(cache_key):
		_packed_blocking_cache_order.erase(cache_key)
		_packed_blocking_cache_order.append(cache_key)
		return _packed_blocking_cache.get(cache_key, PackedByteArray())
	var mask := PackedByteArray()
	mask.resize(cell_count)
	mask.fill(0)
	for key in cells.keys():
		var text: String = str(key)
		var parts: PackedStringArray = text.split(":")
		if parts.size() < 3:
			continue
		var packed_key: int = _packed_key(int(parts[0]), int(parts[2]), min_x, min_z, width)
		if packed_key >= 0 and packed_key < cell_count:
			mask[packed_key] = 1
	if not cache_key.is_empty():
		_packed_blocking_cache[cache_key] = mask
		_packed_blocking_cache_order.erase(cache_key)
		_packed_blocking_cache_order.append(cache_key)
		while _packed_blocking_cache_order.size() > MAX_PACKED_BLOCKING_CACHE_ENTRIES:
			var evicted_key: String = _packed_blocking_cache_order.pop_front()
			_packed_blocking_cache.erase(evicted_key)
	return mask


func _packed_blocking_cache_key(topology: Dictionary, cells: Dictionary, min_x: int, min_z: int, width: int) -> String:
	var topology_revision: String = str(topology.get("topology_revision", topology.get("revision", "")))
	if topology_revision.is_empty():
		return ""
	return "%s|%d:%d:%d|%d|%d" % [
		topology_revision,
		min_x,
		min_z,
		width,
		cells.size(),
		hash(cells),
	]


func _heap_push(heap: Array[Array], item: Array) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := int((index - 1) / 2)
		if _heap_less_or_equal(heap[parent], heap[index]):
			break
		var temp: Array = heap[parent]
		heap[parent] = heap[index]
		heap[index] = temp
		index = parent


func _heap_pop_min(heap: Array[Array]) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = last
	var index := 0
	while true:
		var left := index * 2 + 1
		var right := left + 1
		var smallest := index
		if left < heap.size() and not _heap_less_or_equal(heap[smallest], heap[left]):
			smallest = left
		if right < heap.size() and not _heap_less_or_equal(heap[smallest], heap[right]):
			smallest = right
		if smallest == index:
			break
		var temp: Array = heap[index]
		heap[index] = heap[smallest]
		heap[smallest] = temp
		index = smallest
	return result


func _heap_less_or_equal(left: Array, right: Array) -> bool:
	var left_f: float = float(left[0])
	var right_f: float = float(right[0])
	if not is_equal_approx(left_f, right_f):
		return left_f < right_f
	var left_h: float = float(left[1])
	var right_h: float = float(right[1])
	if not is_equal_approx(left_h, right_h):
		return left_h < right_h
	return int(left[2]) <= int(right[2])


func _cache_key(algorithm: String, start: RefCounted, goals: Array[RefCounted], topology: Dictionary, occupied_actor_cells: Dictionary) -> String:
	var goal_keys: Array[String] = []
	for goal in goals:
		goal_keys.append(goal.key())
	var topology_revision: String = str(topology.get("topology_revision", topology.get("revision", "")))
	if topology_revision.is_empty():
		return ""
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	var occupied_hash: int = hash(occupied_actor_cells)
	var map_id: String = str(topology.get("map_id", topology.get("id", "")))
	return "%s|%s|%s|m:%s|r:%s|bounds:%d:%d:%d:%d|bc:%d|o:%d|v:%d|t:%.2f|p:%.2f" % [
		algorithm,
		start.key(),
		",".join(goal_keys),
		map_id,
		topology_revision,
		int(bounds.get("min_x", 0)),
		int(bounds.get("max_x", 0)),
		int(bounds.get("min_z", 0)),
		int(bounds.get("max_z", 0)),
		int(topology.get("blocking_cell_count", 0)),
		occupied_hash,
		max_visited_cells,
		time_budget_ms,
		profiler_budget_ms,
	]


func _cache_get(key: String) -> Dictionary:
	if not cache_enabled or not _cache.has(key):
		return {}
	_cache_order.erase(key)
	_cache_order.append(key)
	return _dictionary_or_empty(_cache.get(key, {})).duplicate(true)


func _cache_put(key: String, result: Dictionary) -> void:
	if not cache_enabled:
		return
	if bool(result.get("budget_exceeded", false)):
		return
	var cached: Dictionary = result.duplicate(true)
	cached.erase("pathfinding_time_ms")
	cached.erase("search_call_count")
	cached.erase("cache_hit")
	_cache[key] = cached
	_cache_order.erase(key)
	_cache_order.append(key)
	while _cache_order.size() > MAX_CACHE_ENTRIES:
		var evicted_key: String = _cache_order.pop_front()
		_cache.erase(evicted_key)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
