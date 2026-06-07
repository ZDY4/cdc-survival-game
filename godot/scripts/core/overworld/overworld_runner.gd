extends RefCounted


func unlock_location(simulation: RefCounted, location_id: String) -> bool:
	var normalized_location_id: String = str(location_id)
	if normalized_location_id.is_empty():
		return false
	if not simulation.unlocked_locations.has(normalized_location_id):
		simulation.unlocked_locations.append(normalized_location_id)
		simulation.emit_event("location_unlocked", {
			"location_id": normalized_location_id,
		})
		return true
	return false


func enter_location(simulation: RefCounted, actor_id: int, location_id: String, overworld_library: Dictionary, entry_point_override: String = "") -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var location: Dictionary = _overworld_location(location_id, overworld_library)
	if location.is_empty():
		return {"success": false, "reason": "unknown_location", "location_id": location_id}
	var normalized_location_id: String = str(location.get("id", location_id))
	if not simulation.unlocked_locations.has(normalized_location_id):
		return {"success": false, "reason": "location_locked", "location_id": normalized_location_id}
	var map_id: String = str(location.get("map_id", ""))
	if map_id.is_empty():
		return {"success": false, "reason": "location_map_missing", "location_id": normalized_location_id}
	var entry_point_id: String = str(entry_point_override)
	if entry_point_id.is_empty():
		entry_point_id = str(location.get("entry_point_id", ""))
	var previous_map_id: String = simulation.active_map_id
	simulation.active_map_id = map_id
	simulation.active_location_id = normalized_location_id
	simulation.active_entry_point_id = entry_point_id
	simulation.start_entry_point_id = entry_point_id
	_clear_runtime_ui_state(simulation, actor, actor_id, normalized_location_id)
	var combat_end: Dictionary = {}
	if previous_map_id != map_id and simulation.has_method("force_end_combat"):
		combat_end = simulation.call("force_end_combat", "map_changed", {
			"from_map_id": previous_map_id,
			"to_map_id": map_id,
			"location_id": normalized_location_id,
			"source": "enter_location",
		})
	simulation.emit_event("location_entered", {
		"actor_id": actor_id,
		"location_id": normalized_location_id,
		"from_map_id": previous_map_id,
		"to_map_id": map_id,
		"entry_point_id": entry_point_id,
		"combat_ended": bool(combat_end.get("success", false)),
	})
	return {
		"success": true,
		"location_id": normalized_location_id,
		"map_id": map_id,
		"entry_point_id": entry_point_id,
		"combat_ended": bool(combat_end.get("success", false)),
		"combat_end_reason": str(combat_end.get("reason", "")),
	}


func _clear_runtime_ui_state(simulation: RefCounted, actor: RefCounted, actor_id: int, location_id: String) -> void:
	var dialogue_id := str(actor.active_dialogue_id)
	if not dialogue_id.is_empty():
		actor.active_dialogue_id = ""
		actor.active_dialogue_node_id = ""
		actor.active_dialogue_target_actor_id = 0
		actor.active_dialogue_target_definition_id = ""
		simulation.emit_event("dialogue_closed", {
			"actor_id": actor_id,
			"dialogue_id": dialogue_id,
			"reason": "location_changed:%s" % location_id,
		})
	var container_id := str(actor.active_container_id)
	if not container_id.is_empty():
		actor.active_container_id = ""
		simulation.emit_event("container_closed", {
			"actor_id": actor_id,
			"container_id": container_id,
			"reason": "location_changed:%s" % location_id,
		})
	var pending_movement: Dictionary = simulation.pending_movement.duplicate(true)
	var pending_interaction: Dictionary = simulation.pending_interaction.duplicate(true)
	var pending_crafting: Dictionary = simulation.pending_crafting.duplicate(true)
	var had_pending := not pending_movement.is_empty() or not pending_interaction.is_empty() or not pending_crafting.is_empty()
	simulation.pending_movement.clear()
	simulation.pending_interaction.clear()
	simulation.pending_crafting.clear()
	simulation.interaction_menu.clear()
	if had_pending:
		if not pending_crafting.is_empty():
			simulation.emit_event("crafting_cancelled", {
				"actor_id": actor_id,
				"reason": "location_changed:%s" % location_id,
				"pending_crafting": pending_crafting.duplicate(true),
			})
		simulation.emit_event("pending_cancelled", {
			"actor_id": actor_id,
			"reason": "location_changed:%s" % location_id,
			"movement": pending_movement,
			"interaction": pending_interaction,
			"crafting": pending_crafting,
		})


func _overworld_location(location_id: String, overworld_library: Dictionary) -> Dictionary:
	for overworld_id in overworld_library.keys():
		var record: Dictionary = _dictionary_or_empty(overworld_library[overworld_id])
		var data: Dictionary = _dictionary_or_empty(record.get("data", record))
		for location in _array_or_empty(data.get("locations", [])):
			var location_data: Dictionary = _dictionary_or_empty(location)
			if str(location_data.get("id", "")) == location_id:
				return location_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
