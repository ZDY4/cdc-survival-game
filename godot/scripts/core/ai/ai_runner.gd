extends RefCounted


func decide_actor_intent(simulation: RefCounted, ai_rules: RefCounted, actor_id: int, context: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var previous_intent: Dictionary = _dictionary_or_empty(simulation.ai_intents.get(actor_id, {})).duplicate(true)
	var intent: Dictionary = ai_rules.decide_actor_intent(actor, simulation.actor_registry.actors(), context)
	if bool(intent.get("success", false)):
		intent = _with_target_memory(intent, previous_intent)
		simulation.ai_intents[actor_id] = intent.duplicate(true)
		var payload: Dictionary = {
			"actor_id": actor_id,
			"intent": str(intent.get("intent", "")),
			"target_actor_id": int(intent.get("target_actor_id", 0)),
			"previous_target_actor_id": int(intent.get("previous_target_actor_id", 0)),
			"target_lost": bool(intent.get("target_lost", false)),
			"target_lost_reason": str(intent.get("target_lost_reason", "")),
			"target_tracking_state": str(intent.get("target_tracking_state", "")),
			"reason": str(intent.get("reason", "")),
			"distance": float(intent.get("distance", -1.0)),
			"aggro_range": float(intent.get("aggro_range", 0.0)),
			"attack_range": float(intent.get("attack_range", 0.0)),
			"ap": float(intent.get("ap", 0.0)),
			"target_grid": _dictionary_or_empty(intent.get("target_grid", {})).duplicate(true),
			"path": _array_or_empty(intent.get("path", [])).duplicate(true),
			"weapon_item_id": str(intent.get("weapon_item_id", "")),
			"weapon_slot_id": str(intent.get("weapon_slot_id", "")),
			"ammo_type": str(intent.get("ammo_type", "")),
			"ammo_ready": bool(intent.get("ammo_ready", true)),
			"can_reload": bool(intent.get("can_reload", false)),
			"loaded": int(intent.get("loaded", 0)),
			"capacity": int(intent.get("capacity", 0)),
			"inventory_ammo": int(intent.get("inventory_ammo", 0)),
			"candidate_count": int(intent.get("candidate_count", 0)),
			"blocked_by_los_count": int(intent.get("blocked_by_los_count", 0)),
		}
		simulation.emit_event("ai_intent_decided", payload)
	return intent


func decide_all_ai_intents(simulation: RefCounted, ai_rules: RefCounted, context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for actor in simulation.actor_registry.actors():
		if actor.kind == "player":
			continue
		output.append(decide_actor_intent(simulation, ai_rules, actor.actor_id, context))
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _with_target_memory(intent: Dictionary, previous_intent: Dictionary) -> Dictionary:
	var output: Dictionary = intent.duplicate(true)
	var target_actor_id: int = int(output.get("target_actor_id", 0))
	var previous_target_actor_id: int = int(previous_intent.get("target_actor_id", previous_intent.get("last_seen_target_actor_id", 0)))
	if previous_target_actor_id > 0:
		output["previous_target_actor_id"] = previous_target_actor_id
	if target_actor_id > 0:
		output["last_seen_target_actor_id"] = target_actor_id
		output["target_tracking_state"] = "tracking" if previous_target_actor_id == target_actor_id else "acquired"
		output["target_lost"] = false
		output["target_lost_reason"] = ""
	elif previous_target_actor_id > 0:
		output["last_seen_target_actor_id"] = previous_target_actor_id
		output["target_tracking_state"] = "lost"
		output["target_lost"] = true
		output["target_lost_reason"] = str(output.get("reason", "target_lost"))
	else:
		output["target_tracking_state"] = "none"
		output["target_lost"] = false
		output["target_lost_reason"] = ""
	return output


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
