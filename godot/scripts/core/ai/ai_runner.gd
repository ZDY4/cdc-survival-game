extends RefCounted


func decide_actor_intent(simulation: RefCounted, ai_rules: RefCounted, actor_id: int, context: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var intent: Dictionary = ai_rules.decide_actor_intent(actor, simulation.actor_registry.actors(), context)
	if bool(intent.get("success", false)):
		simulation.ai_intents[actor_id] = intent.duplicate(true)
		simulation.emit_event("ai_intent_decided", {
			"actor_id": actor_id,
			"intent": str(intent.get("intent", "")),
			"target_actor_id": int(intent.get("target_actor_id", 0)),
			"reason": str(intent.get("reason", "")),
		})
	return intent


func decide_all_ai_intents(simulation: RefCounted, ai_rules: RefCounted, context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for actor in simulation.actor_registry.actors():
		if actor.kind == "player":
			continue
		output.append(decide_actor_intent(simulation, ai_rules, actor.actor_id, context))
	return output
