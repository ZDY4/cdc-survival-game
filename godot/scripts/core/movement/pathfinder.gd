extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")

const CARDINAL_OFFSETS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]


func find_path(start: RefCounted, goal: RefCounted, topology: Dictionary, occupied_actor_cells: Dictionary = {}) -> Dictionary:
	if start == null or goal == null:
		return {
			"success": false,
			"reason": "invalid_endpoint",
		}
	if start.y != goal.y:
		return {
			"success": false,
			"reason": "level_mismatch",
			"start": start.to_dictionary(),
			"goal": goal.to_dictionary(),
			"start_level": start.y,
			"goal_level": goal.y,
		}
	if not _within_bounds(goal, topology):
		return {
			"success": false,
			"reason": "goal_out_of_bounds",
			"goal": goal.to_dictionary(),
			"bounds": _dictionary_or_empty(topology.get("bounds", {})).duplicate(true),
		}
	var goal_blocking: Dictionary = _blocking_info(goal, topology, occupied_actor_cells, start.key())
	if not goal_blocking.is_empty():
		var blocked_reason: String = "goal_occupied" if str(goal_blocking.get("kind", "")) == "actor" else "goal_blocked"
		return {
			"success": false,
			"reason": blocked_reason,
			"goal": goal.to_dictionary(),
			"blocker": goal_blocking,
		}
	if start.key() == goal.key():
		return {
			"success": true,
			"path": [start.to_dictionary()],
			"steps": 0,
		}

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
				return {
					"success": true,
					"path": _reconstruct_path(start.key(), goal.key(), came_from, coords),
					"steps": _path_length(start.key(), goal.key(), came_from),
				}
			frontier.append(next_coord)

	return {
		"success": false,
		"reason": "path_unreachable",
		"start": start.to_dictionary(),
		"goal": goal.to_dictionary(),
		"visited_cell_count": came_from.size(),
	}


func _neighbors(coord: RefCounted, topology: Dictionary, occupied_actor_cells: Dictionary, start_key: String) -> Array[RefCounted]:
	var output: Array[RefCounted] = []
	for offset in CARDINAL_OFFSETS:
		var next := GridCoord.new(coord.x + offset.x, coord.y, coord.z + offset.y)
		if not _within_bounds(next, topology):
			continue
		if _blocked(next, topology, occupied_actor_cells, start_key):
			continue
		output.append(next)
	return output


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
