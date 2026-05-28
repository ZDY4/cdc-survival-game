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
