extends RefCounted


func decide_actor_intent(simulation: RefCounted, ai_rules: RefCounted, actor_id: int, context: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var intent: Dictionary = ai_rules.decide_actor_intent(actor, simulation.actor_registry.actors(), context)
	if bool(intent.get("success", false)):
		simulation.ai_intents[actor_id] = intent.duplicate(true)
		var payload: Dictionary = {
			"actor_id": actor_id,
			"intent": str(intent.get("intent", "")),
			"target_actor_id": int(intent.get("target_actor_id", 0)),
			"reason": str(intent.get("reason", "")),
			"distance": float(intent.get("distance", -1.0)),
			"aggro_range": float(intent.get("aggro_range", 0.0)),
			"attack_range": float(intent.get("attack_range", 0.0)),
			"ap": float(intent.get("ap", 0.0)),
			"target_grid": _dictionary_or_empty(intent.get("target_grid", {})).duplicate(true),
			"path": _array_or_empty(intent.get("path", [])).duplicate(true),
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


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
