extends RefCounted


func grant_experience(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, amount: int, source: String = "") -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var result: Dictionary = progression_rules.grant_experience(actor.progression, amount)
	if not bool(result.get("changed", false)):
		return {"success": false, "reason": "experience_amount_invalid"}
	actor.progression = _dictionary_or_empty(result.get("state", {}))
	simulation.emit_event("experience_granted", {
		"actor_id": actor_id,
		"amount": int(result.get("amount", amount)),
		"total_xp": int(result.get("total_xp", 0)),
		"source": source,
	})
	for level_up in _array_or_empty(result.get("level_ups", [])):
		var level_up_data: Dictionary = _dictionary_or_empty(level_up)
		simulation.emit_event("actor_leveled_up", {
			"actor_id": actor_id,
			"new_level": int(level_up_data.get("new_level", 1)),
			"available_stat_points": int(level_up_data.get("available_stat_points", 0)),
			"available_skill_points": int(level_up_data.get("available_skill_points", 0)),
		})
	return {
		"success": true,
		"level": int(actor.progression.get("level", 1)),
		"current_xp": int(actor.progression.get("current_xp", 0)),
		"available_skill_points": int(actor.progression.get("available_skill_points", 0)),
	}


func grant_skill_points(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, amount: int, source: String = "") -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var result: Dictionary = progression_rules.add_skill_points(actor.progression, amount)
	if not bool(result.get("changed", false)):
		return {"success": false, "reason": "skill_point_amount_invalid"}
	actor.progression = _dictionary_or_empty(result.get("state", {}))
	simulation.emit_event("skill_points_granted", {
		"actor_id": actor_id,
		"amount": max(0, amount),
		"available_skill_points": int(result.get("available_skill_points", 0)),
		"source": source,
	})
	return {
		"success": true,
		"available_skill_points": int(actor.progression.get("available_skill_points", 0)),
	}


func allocate_attribute_point(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, attribute: String) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var result: Dictionary = progression_rules.allocate_attribute_point(actor.progression, attribute)
	if not bool(result.get("success", false)):
		return result
	actor.progression = _dictionary_or_empty(result.get("state", {}))
	_apply_attribute_derived_values(actor, str(result.get("attribute", "")))
	simulation.emit_event("attribute_allocated", {
		"actor_id": actor_id,
		"attribute": str(result.get("attribute", "")),
		"value": int(result.get("value", 0)),
		"available_stat_points": int(result.get("available_stat_points", 0)),
	})
	return result


func learn_skill(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, skill_id: String, skill_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var result: Dictionary = progression_rules.learn_skill(actor.progression, skill_id, skill_library)
	if not bool(result.get("success", false)):
		return result
	actor.progression = _dictionary_or_empty(result.get("state", {}))
	simulation.emit_event("skill_learned", {
		"actor_id": actor_id,
		"skill_id": str(result.get("skill_id", skill_id)),
		"level": int(result.get("level", 0)),
		"available_skill_points": int(result.get("available_skill_points", 0)),
	})
	return result


func _apply_attribute_derived_values(actor: RefCounted, attribute: String) -> void:
	var attributes: Dictionary = _dictionary_or_empty(actor.progression.get("attributes", {}))
	match attribute:
		"constitution":
			var new_max_hp: float = max(float(actor.max_hp), 50.0 + float(attributes.get("constitution", 0)) * 5.0)
			var hp_delta: float = new_max_hp - float(actor.max_hp)
			actor.max_hp = new_max_hp
			actor.hp = min(actor.max_hp, float(actor.hp) + max(0.0, hp_delta))
			actor.combat_attributes["max_hp"] = actor.max_hp
		"strength":
			var new_attack_power: float = max(float(actor.attack_power), float(attributes.get("strength", 0)))
			actor.attack_power = new_attack_power
			actor.combat_attributes["attack_power"] = actor.attack_power
		"agility":
			actor.combat_attributes["speed"] = max(float(_dictionary_or_empty(actor.combat_attributes).get("speed", 0.0)), float(attributes.get("agility", 0)))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
