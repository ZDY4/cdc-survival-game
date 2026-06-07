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


func find_path(start: RefCounted, goal: RefCounted, topology: Dictionary, occupied_actor_cells: Dictionary = {}) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	if start == null or goal == null:
		return _finish({
			"success": false,
			"reason": "invalid_endpoint",
		}, started_usec)
	if start.y != goal.y:
		return _finish({
			"success": false,
			"reason": "level_mismatch",
			"start": start.to_dictionary(),
			"goal": goal.to_dictionary(),
			"start_level": start.y,
			"goal_level": goal.y,
		}, started_usec)
	if not _within_bounds(goal, topology):
		return _finish({
			"success": false,
			"reason": "goal_out_of_bounds",
			"goal": goal.to_dictionary(),
			"bounds": _dictionary_or_empty(topology.get("bounds", {})).duplicate(true),
		}, started_usec)
	var goal_blocking: Dictionary = _blocking_info(goal, topology, occupied_actor_cells, start.key())
	if not goal_blocking.is_empty():
		var blocked_reason: String = "goal_occupied" if str(goal_blocking.get("kind", "")) == "actor" else "goal_blocked"
		return _finish({
			"success": false,
			"reason": blocked_reason,
			"goal": goal.to_dictionary(),
			"blocker": goal_blocking,
		}, started_usec)
	if start.key() == goal.key():
		return _finish({
			"success": true,
			"path": [start.to_dictionary()],
			"steps": 0,
			"visited_cell_count": 1,
		}, started_usec)

	var frontier: Array[RefCounted] = [start]
	var came_from: Dictionary = {start.key(): ""}
	var coords: Dictionary = {start.key(): start}
	var cursor := 0
	while cursor < frontier.size():
		var current: RefCounted = frontier[cursor]
		cursor += 1
		for next in _neighbors(current, topology, occupied_actor_cells, start.key()):
			var next_coord: RefCounted = next
			var next_key: String = next_coord.key()
			if came_from.has(next_key):
				continue
			came_from[next_key] = current.key()
			coords[next_key] = next_coord
			if next_key == goal.key():
				return _finish({
					"success": true,
					"path": _reconstruct_path(start.key(), goal.key(), came_from, coords),
					"steps": _path_length(start.key(), goal.key(), came_from),
					"visited_cell_count": came_from.size(),
				}, started_usec)
			frontier.append(next_coord)

	return _finish({
		"success": false,
		"reason": "path_unreachable",
		"start": start.to_dictionary(),
		"goal": goal.to_dictionary(),
		"visited_cell_count": came_from.size(),
	}, started_usec)


func _finish(result: Dictionary, started_usec: int) -> Dictionary:
	result["pathfinding_time_ms"] = max(0.0, float(Time.get_ticks_usec() - started_usec) / 1000.0)
	if not result.has("visited_cell_count"):
		result["visited_cell_count"] = 0
	return result


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


func _within_bounds(coord: RefCounted, topology: Dictionary) -> bool:
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	return coord.x >= int(bounds.get("min_x", 0)) \
		and coord.x <= int(bounds.get("max_x", 0)) \
		and coord.z >= int(bounds.get("min_z", 0)) \
		and coord.z <= int(bounds.get("max_z", 0))


func _blocked(coord: RefCounted, topology: Dictionary, occupied_actor_cells: Dictionary, start_key: String) -> bool:
	return not _blocking_info(coord, topology, occupied_actor_cells, start_key).is_empty()


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


func _reconstruct_path(start_key: String, goal_key: String, came_from: Dictionary, coords: Dictionary) -> Array[Dictionary]:
	var reversed: Array[Dictionary] = []
	var current_key: String = goal_key
	while not current_key.is_empty():
		var coord: RefCounted = coords[current_key]
		reversed.append(coord.to_dictionary())
		if current_key == start_key:
			break
		current_key = str(came_from.get(current_key, ""))
	reversed.reverse()
	return reversed


func _path_length(start_key: String, goal_key: String, came_from: Dictionary) -> int:
	var steps := 0
	var current_key: String = goal_key
	while current_key != start_key and not current_key.is_empty():
		steps += 1
		current_key = str(came_from.get(current_key, ""))
	return steps


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
