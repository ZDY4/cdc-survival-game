extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")


func move_actor_to(simulation: RefCounted, pathfinder: RefCounted, actor_id: int, target_position: Dictionary, topology: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var goal: RefCounted = GridCoord.from_dictionary(target_position)
	var occupied: Dictionary = _occupied_actor_cells(simulation, actor_id)
	var path_result: Dictionary = pathfinder.find_path(actor.grid_position, goal, topology, occupied)
	if not bool(path_result.get("success", false)):
		return path_result
	actor.grid_position = goal
	simulation.emit_event("actor_moved", {
		"actor_id": actor_id,
		"from": _array_or_empty(path_result.get("path", [])).front() if int(path_result.get("steps", 0)) > 0 else goal.to_dictionary(),
		"to": goal.to_dictionary(),
		"steps": int(path_result.get("steps", 0)),
	})
	return {
		"success": true,
		"actor_id": actor_id,
		"to": goal.to_dictionary(),
		"path": path_result.get("path", []),
		"steps": int(path_result.get("steps", 0)),
	}


func _occupied_actor_cells(simulation: RefCounted, excluded_actor_id: int) -> Dictionary:
	var output: Dictionary = {}
	for actor in simulation.actor_registry.actors():
		if actor.actor_id == excluded_actor_id:
			continue
		output[actor.grid_position.key()] = actor.actor_id
	return output


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
