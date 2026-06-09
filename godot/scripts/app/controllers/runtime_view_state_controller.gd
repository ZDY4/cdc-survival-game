extends RefCounted

var focused_actor_id: int = 0
var observed_map_level: int = 0


func current_map_level(world_result: Dictionary) -> int:
	observed_map_level = normalized_map_level(observed_map_level, world_result)
	return observed_map_level


func map_level_snapshot(world_result: Dictionary) -> Dictionary:
	return {
		"current": current_map_level(world_result),
		"default": default_map_level(world_result),
		"available": available_map_levels(world_result),
	}


func change_observed_level(direction: int, world_result: Dictionary) -> Dictionary:
	var levels: Array[int] = available_map_levels(world_result)
	if levels.is_empty():
		return {"success": false, "reason": "map_level_missing", "current": observed_map_level}
	var current_level := current_map_level(world_result)
	var current_index := levels.find(current_level)
	if current_index < 0:
		current_index = 0
	var step := 1 if direction > 0 else -1 if direction < 0 else 0
	var next_index := clampi(current_index + step, 0, levels.size() - 1)
	var next_level := int(levels[next_index])
	var changed := next_level != observed_map_level
	observed_map_level = next_level
	return {
		"success": true,
		"changed": changed,
		"current": observed_map_level,
		"available": levels,
	}


func cycle_focused_actor(world_result: Dictionary, simulation: RefCounted, observe_mode_enabled: bool, ui_blocked: bool) -> Dictionary:
	if ui_blocked:
		return {"success": false, "reason": "ui_blocked", "actor_id": focused_actor_id}
	var focused_actor: Dictionary = focused_actor_data(world_result, observe_mode_enabled)
	var busy_state: Dictionary = focused_actor_busy_state(focused_actor, simulation)
	if not observe_mode_enabled and not busy_state.is_empty():
		return {
			"success": false,
			"reason": "actor_busy",
			"actor_id": int(focused_actor.get("actor_id", focused_actor_id)),
			"busy": busy_state,
		}
	var candidates: Array[Dictionary] = focus_actor_candidates(world_result, observe_mode_enabled)
	if candidates.is_empty():
		return {"success": false, "reason": "focus_actor_missing", "actor_id": focused_actor_id}
	var current_index := -1
	for index in range(candidates.size()):
		if int(candidates[index].get("actor_id", 0)) == focused_actor_id:
			current_index = index
			break
	var next_actor: Dictionary = candidates[(current_index + 1) % candidates.size()]
	focused_actor_id = int(next_actor.get("actor_id", 0))
	return {"success": true, "actor": next_actor.duplicate(true), "actor_id": focused_actor_id}


func focus_actor(actor_id: int, world_result: Dictionary, simulation: RefCounted, observe_mode_enabled: bool, ui_blocked: bool) -> Dictionary:
	if ui_blocked:
		return {"success": false, "reason": "ui_blocked", "actor_id": focused_actor_id}
	var candidates: Array[Dictionary] = focus_actor_candidates(world_result, observe_mode_enabled)
	for candidate in candidates:
		if int(candidate.get("actor_id", 0)) != actor_id:
			continue
		var busy_state: Dictionary = focused_actor_busy_state(candidate, simulation)
		if not observe_mode_enabled and not busy_state.is_empty():
			return {
				"success": false,
				"reason": "actor_busy",
				"actor_id": actor_id,
				"busy": busy_state,
			}
		focused_actor_id = actor_id
		return {"success": true, "actor": candidate.duplicate(true), "actor_id": focused_actor_id}
	return {"success": false, "reason": "focus_actor_missing", "actor_id": actor_id}


func focused_actor_snapshot(world_result: Dictionary, observe_mode_enabled: bool) -> Dictionary:
	var actor: Dictionary = focused_actor_data(world_result, observe_mode_enabled)
	if actor.is_empty():
		return {}
	return {
		"actor_id": int(actor.get("actor_id", 0)),
		"definition_id": str(actor.get("definition_id", "")),
		"display_name": str(actor.get("display_name", "")),
		"kind": str(actor.get("kind", "")),
		"side": str(actor.get("side", "")),
		"grid_position": _dictionary_or_empty(actor.get("grid_position", {})).duplicate(true),
	}


func focused_actor_grid_position(world_result: Dictionary, observe_mode_enabled: bool) -> Dictionary:
	return _dictionary_or_empty(focused_actor_snapshot(world_result, observe_mode_enabled).get("grid_position", {})).duplicate(true)


func focused_actor_data(world_result: Dictionary, observe_mode_enabled: bool) -> Dictionary:
	var candidates: Array[Dictionary] = focus_actor_candidates(world_result, observe_mode_enabled)
	if candidates.is_empty():
		focused_actor_id = 0
		return {}
	for candidate in candidates:
		if int(candidate.get("actor_id", 0)) == focused_actor_id:
			return candidate.duplicate(true)
	focused_actor_id = int(candidates[0].get("actor_id", 0))
	return candidates[0].duplicate(true)


func focus_actor_candidates(world_result: Dictionary, observe_mode_enabled: bool) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if world_result.is_empty():
		return candidates
	var focused_level := current_map_level(world_result)
	for actor in _array_or_empty(world_result.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if actor_data.is_empty():
			continue
		if not observe_mode_enabled and not is_player_side_actor(actor_data):
			continue
		var grid: Dictionary = _dictionary_or_empty(actor_data.get("grid_position", {}))
		if int(grid.get("y", 0)) != focused_level:
			continue
		candidates.append(actor_data.duplicate(true))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("actor_id", 0)) < int(b.get("actor_id", 0))
	)
	return candidates


func sync_observed_level_to_map(world_result: Dictionary) -> void:
	observed_map_level = normalized_map_level(observed_map_level if not available_map_levels(world_result).is_empty() else default_map_level(world_result), world_result)


func normalized_map_level(level: int, world_result: Dictionary) -> int:
	var levels: Array[int] = available_map_levels(world_result)
	if levels.is_empty():
		return default_map_level(world_result)
	if levels.has(level):
		return level
	var nearest := int(levels[0])
	var nearest_distance := absi(nearest - level)
	for candidate in levels:
		var distance := absi(int(candidate) - level)
		if distance < nearest_distance:
			nearest = int(candidate)
			nearest_distance = distance
	return nearest


func default_map_level(world_result: Dictionary) -> int:
	var map: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	return int(map.get("default_level", 0))


func available_map_levels(world_result: Dictionary) -> Array[int]:
	var seen: Dictionary = {}
	var map: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	for level in _array_or_empty(map.get("levels", [])):
		var level_data: Dictionary = _dictionary_or_empty(level)
		seen[int(level_data.get("y", default_map_level(world_result)))] = true
	seen[default_map_level(world_result)] = true
	for actor in _array_or_empty(world_result.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		var grid: Dictionary = _dictionary_or_empty(actor_data.get("grid_position", {}))
		if not grid.is_empty():
			seen[int(grid.get("y", default_map_level(world_result)))] = true
	var levels: Array[int] = []
	for key in seen.keys():
		levels.append(int(key))
	levels.sort()
	return levels


func is_player_side_actor(actor_data: Dictionary) -> bool:
	return str(actor_data.get("side", "")) == "player" or str(actor_data.get("kind", "")) == "player"


func focused_actor_busy_state(focused_actor: Dictionary, simulation: RefCounted) -> Dictionary:
	if focused_actor.is_empty() or simulation == null:
		return {}
	var actor_id := int(focused_actor.get("actor_id", 0))
	var snapshot: Dictionary = simulation.snapshot()
	var pending_movement: Dictionary = _dictionary_or_empty(snapshot.get("pending_movement", {}))
	if not pending_movement.is_empty() and int(pending_movement.get("actor_id", 0)) == actor_id:
		return {"kind": "pending_movement", "state": pending_movement.duplicate(true)}
	var pending_interaction: Dictionary = _dictionary_or_empty(snapshot.get("pending_interaction", {}))
	if not pending_interaction.is_empty() and int(pending_interaction.get("actor_id", 0)) == actor_id:
		return {"kind": "pending_interaction", "state": pending_interaction.duplicate(true)}
	var pending_crafting: Dictionary = _dictionary_or_empty(snapshot.get("pending_crafting", {}))
	if not pending_crafting.is_empty() and int(pending_crafting.get("actor_id", 0)) == actor_id:
		return {"kind": "pending_crafting", "state": pending_crafting.duplicate(true)}
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
