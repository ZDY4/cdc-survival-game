extends RefCounted


func set_actor_vision_radius(vision_rules: RefCounted, actor_id: int, radius: int) -> void:
	vision_rules.set_actor_radius(actor_id, radius)


func refresh_actor_vision(simulation: RefCounted, vision_rules: RefCounted, actor_id: int, topology: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var update: Dictionary = vision_rules.recompute_actor(actor_id, simulation.active_map_id, actor.grid_position.to_dictionary(), topology)
	if bool(update.get("changed", false)):
		simulation.emit_event("actor_vision_updated", {
			"actor_id": actor_id,
			"active_map_id": str(update.get("active_map_id", "")),
			"visible_cell_count": _array_or_empty(update.get("visible_cells", [])).size(),
			"explored_cell_count": _array_or_empty(update.get("explored_cells", [])).size(),
		})
	update["success"] = true
	return update


func clear_actor_vision(vision_rules: RefCounted, actor_id: int) -> void:
	vision_rules.clear_actor(actor_id)


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
