extends RefCounted


func apply_action(simulation: RefCounted, actor_id: int, action: Dictionary) -> Dictionary:
	var action_type: String = str(action.get("type", action.get("action_type", "")))
	match action_type:
		"start_quest":
			var quest_id: String = str(action.get("quest_id", action.get("questId", "")))
			var started: bool = simulation.start_quest(actor_id, quest_id)
			return {"type": action_type, "success": started, "quest_id": quest_id}
		"turn_in_quest":
			var quest_id: String = str(action.get("quest_id", action.get("questId", "")))
			var result: Dictionary = simulation.turn_in_quest(actor_id, quest_id)
			result["type"] = action_type
			result["quest_id"] = quest_id
			return result
		"unlock_location":
			var location_id: String = str(action.get("location_id", action.get("locationId", "")))
			var unlocked: bool = simulation.unlock_location(location_id)
			return {"type": action_type, "success": unlocked, "location_id": location_id}
		"set_world_flag", "set_flag", "world_flag":
			return _set_world_flag(simulation, actor_id, action, action_type)
		"change_relationship", "adjust_relationship", "set_relationship":
			return _change_relationship(simulation, actor_id, action, action_type)
		"open_trade":
			simulation.emit_event("dialogue_trade_requested", {
				"actor_id": actor_id,
			})
			return {"type": action_type, "success": true}
		_:
			simulation.emit_event("dialogue_action_unsupported", {
				"actor_id": actor_id,
				"action_type": action_type,
			})
			return {"type": action_type, "success": false, "reason": "unsupported_dialogue_action"}


func _set_world_flag(simulation: RefCounted, actor_id: int, action: Dictionary, action_type: String) -> Dictionary:
	var flag_id := str(action.get("flag_id", action.get("flagId", action.get("world_flag", action.get("worldFlag", ""))))).strip_edges()
	if simulation == null or not simulation.has_method("set_world_flag"):
		return {"type": action_type, "success": false, "reason": "world_flag_api_missing", "flag_id": flag_id}
	var value := bool(action.get("value", action.get("enabled", true)))
	var reason := str(action.get("reason", "dialogue_action:%s" % action_type))
	var result: Dictionary = simulation.call("set_world_flag", flag_id, value, reason, actor_id)
	result["type"] = action_type
	return result


func _change_relationship(simulation: RefCounted, actor_id: int, action: Dictionary, action_type: String) -> Dictionary:
	if simulation == null or not simulation.has_method("set_relationship_score"):
		return {"type": action_type, "success": false, "reason": "relationship_api_missing"}
	var source_actor_id := int(action.get("actor_id", action.get("source_actor_id", actor_id)))
	var target_actor_id := _relationship_target_actor_id(simulation, source_actor_id, action)
	if target_actor_id <= 0:
		return {"type": action_type, "success": false, "reason": "relationship_target_missing", "actor_id": source_actor_id}
	var current_score := 0.0
	if simulation.has_method("relationship_score"):
		current_score = float(simulation.call("relationship_score", source_actor_id, target_actor_id))
	var next_score := current_score
	if action.has("score"):
		next_score = float(action.get("score", current_score))
	elif action.has("value"):
		next_score = float(action.get("value", current_score))
	else:
		next_score = current_score + float(action.get("delta", action.get("amount", 0.0)))
	var reason := str(action.get("reason", "dialogue_action:%s" % action_type))
	var result: Dictionary = simulation.call("set_relationship_score", source_actor_id, target_actor_id, next_score, reason)
	result["type"] = action_type
	result["delta"] = next_score - current_score
	return result


func _relationship_target_actor_id(simulation: RefCounted, source_actor_id: int, action: Dictionary) -> int:
	var explicit_id := int(action.get("target_actor_id", action.get("targetActorId", 0)))
	if explicit_id > 0:
		return explicit_id
	var definition_id := str(action.get("target_definition_id", action.get("targetDefinitionId", ""))).strip_edges()
	if definition_id.is_empty():
		return 0
	for actor in simulation.actor_registry.actors():
		if actor.actor_id == source_actor_id:
			continue
		if actor.definition_id == definition_id:
			return actor.actor_id
	return 0
