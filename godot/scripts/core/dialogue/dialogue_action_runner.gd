extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

var _inventory_entries := InventoryEntries.new()


func apply_action(simulation: RefCounted, actor_id: int, action: Dictionary, context: Dictionary = {}) -> Dictionary:
	var action_type: String = str(action.get("type", action.get("action_type", "")))
	match action_type:
		"start_quest":
			var quest_id: String = str(action.get("quest_id", action.get("questId", "")))
			var started: bool = simulation.start_quest(actor_id, quest_id)
			if started:
				return {"type": action_type, "success": true, "quest_id": quest_id, "status": "started"}
			if simulation.active_quests.has(quest_id):
				return {"type": action_type, "success": true, "quest_id": quest_id, "status": "already_active"}
			if simulation.completed_quests.has(quest_id):
				return {"type": action_type, "success": true, "quest_id": quest_id, "status": "already_completed"}
			return {"type": action_type, "success": false, "reason": "quest_start_failed", "quest_id": quest_id}
		"turn_in_quest":
			var quest_id: String = str(action.get("quest_id", action.get("questId", "")))
			var result: Dictionary = simulation.turn_in_quest(actor_id, quest_id, context)
			result["type"] = action_type
			result["quest_id"] = quest_id
			return result
		"unlock_location":
			var location_id: String = str(action.get("location_id", action.get("locationId", "")))
			var unlocked: bool = simulation.unlock_location(location_id)
			if unlocked:
				return {"type": action_type, "success": true, "location_id": location_id, "status": "unlocked"}
			if simulation.unlocked_locations.has(location_id):
				return {"type": action_type, "success": true, "location_id": location_id, "status": "already_unlocked"}
			return {"type": action_type, "success": false, "reason": "location_unlock_failed", "location_id": location_id}
		"set_world_flag", "set_flag", "world_flag":
			return _set_world_flag(simulation, actor_id, action, action_type)
		"change_relationship", "adjust_relationship", "set_relationship":
			return _change_relationship(simulation, actor_id, action, action_type)
		"give_item", "grant_item":
			return _give_item(simulation, actor_id, action, action_type)
		"give_reward", "grant_reward":
			return _give_reward(simulation, actor_id, action, action_type)
		"open_trade":
			var shop_id: String = _trade_shop_id(action)
			simulation.emit_event("dialogue_trade_requested", {
				"actor_id": actor_id,
				"shop_id": shop_id,
			})
			return {"type": action_type, "success": true, "shop_id": shop_id}
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


func _trade_shop_id(action: Dictionary) -> String:
	return str(action.get("shop_id", action.get("shopId", action.get("action_key", action.get("actionKey", ""))))).strip_edges()


func _give_item(simulation: RefCounted, actor_id: int, action: Dictionary, action_type: String) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"type": action_type, "success": false, "reason": "unknown_actor", "actor_id": actor_id}
	var item_id := _inventory_entries.normalize_content_id(action.get("item_id", action.get("itemId", action.get("id", ""))))
	var count: int = max(1, int(action.get("count", 1)))
	if item_id.is_empty():
		return {"type": action_type, "success": false, "reason": "item_id_missing", "actor_id": actor_id}
	var before_count: int = int(actor.inventory.get(item_id, 0))
	_inventory_entries.add_actor_item(actor, item_id, count, simulation.item_library)
	var after_count: int = int(actor.inventory.get(item_id, 0))
	simulation.emit_event("dialogue_item_granted", {
		"actor_id": actor_id,
		"item_id": item_id,
		"count": count,
		"inventory_before": before_count,
		"inventory_after": after_count,
	})
	return {
		"type": action_type,
		"success": true,
		"actor_id": actor_id,
		"item_id": item_id,
		"count": count,
		"inventory_before": before_count,
		"inventory_after": after_count,
	}


func _give_reward(simulation: RefCounted, actor_id: int, action: Dictionary, action_type: String) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"type": action_type, "success": false, "reason": "unknown_actor", "actor_id": actor_id}
	var rewards: Dictionary = _dictionary_or_empty(action.get("rewards", action))
	var granted_items: Array[Dictionary] = []
	for item in _array_or_empty(rewards.get("items", [])):
		var item_data: Dictionary = _dictionary_or_empty(item)
		var item_id := _inventory_entries.normalize_content_id(item_data.get("item_id", item_data.get("itemId", item_data.get("id", ""))))
		var count: int = max(1, int(item_data.get("count", 1)))
		if item_id.is_empty():
			continue
		var before_count: int = int(actor.inventory.get(item_id, 0))
		_inventory_entries.add_actor_item(actor, item_id, count, simulation.item_library)
		granted_items.append({
			"item_id": item_id,
			"count": count,
			"inventory_before": before_count,
			"inventory_after": int(actor.inventory.get(item_id, 0)),
		})
	var money: int = max(0, int(rewards.get("money", 0)))
	var money_before: int = actor.money
	if money > 0:
		actor.money += money
	var experience: int = max(0, int(rewards.get("experience", rewards.get("xp", 0))))
	var skill_points: int = max(0, int(rewards.get("skill_points", rewards.get("skillPoints", 0))))
	if experience > 0:
		simulation.grant_experience(actor_id, experience, "dialogue_action")
	if skill_points > 0:
		simulation.grant_skill_points(actor_id, skill_points, "dialogue_action")
	simulation.emit_event("dialogue_reward_granted", {
		"actor_id": actor_id,
		"items": granted_items.duplicate(true),
		"money": money,
		"money_before": money_before,
		"money_after": actor.money,
		"experience": experience,
		"skill_points": skill_points,
	})
	return {
		"type": action_type,
		"success": true,
		"actor_id": actor_id,
		"items": granted_items,
		"money": money,
		"money_before": money_before,
		"money_after": actor.money,
		"experience": experience,
		"skill_points": skill_points,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
