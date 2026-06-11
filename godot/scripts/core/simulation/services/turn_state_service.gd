extends RefCounted


func open_turn(simulation: RefCounted, actor_id: int, reason: String) -> void:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return
	var turn_ap_gain: float = turn_ap_gain(simulation, actor)
	var turn_ap_max: float = turn_ap_max(simulation, actor)
	actor.ap = clampf(actor.ap + turn_ap_gain, 0.0, turn_ap_max)
	actor.turn_open = true
	simulation.turn_state["active_actor_id"] = actor_id
	simulation.turn_state["phase"] = "player" if actor.kind == "player" else "npc"
	simulation._refresh_combat_turn_order("turn_opened")
	simulation.emit_event("turn_started", {
		"actor_id": actor_id,
		"ap": actor.ap,
		"ap_gain": turn_ap_gain,
		"ap_max": turn_ap_max,
		"affordable_ap_threshold": affordable_ap_threshold(simulation, actor),
		"round": int(simulation.turn_state.get("round", 1)),
		"reason": reason,
	})


func close_turn(simulation: RefCounted, actor_id: int, reason: String) -> void:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return
	actor.turn_open = false
	simulation._refresh_combat_turn_order("turn_closed")
	simulation.emit_event("turn_ended", {
		"actor_id": actor_id,
		"ap": actor.ap,
		"round": int(simulation.turn_state.get("round", 1)),
		"reason": reason,
	})


func spend_ap(simulation: RefCounted, actor: RefCounted, cost: float, reason: String) -> void:
	if cost <= 0.0:
		return
	var before: float = actor.ap
	actor.ap = max(0.0, actor.ap - cost)
	simulation.emit_event("ap_spent", {
		"actor_id": actor.actor_id,
		"cost": cost,
		"before": before,
		"after": actor.ap,
		"reason": reason,
	})


func turn_ap_gain(simulation: RefCounted, actor: RefCounted) -> float:
	var attributes: Dictionary = _dictionary_or_empty(actor.combat_attributes)
	if actor_uses_combat_turn_ap(simulation, actor) and attributes.has("combat_turn_ap_gain"):
		return max(0.0, float(attributes.get("combat_turn_ap_gain", simulation.DEFAULT_TURN_AP_GAIN)))
	if attributes.has("turn_ap_gain"):
		return max(0.0, float(attributes.get("turn_ap_gain", simulation.DEFAULT_TURN_AP_GAIN)))
	if attributes.has("speed"):
		return max(1.0, float(attributes.get("speed", simulation.DEFAULT_TURN_AP_GAIN)) + 1.0)
	return simulation.DEFAULT_TURN_AP_GAIN


func turn_ap_max(simulation: RefCounted, actor: RefCounted) -> float:
	var attributes: Dictionary = _dictionary_or_empty(actor.combat_attributes)
	if actor_uses_combat_turn_ap(simulation, actor) and attributes.has("combat_turn_ap_max"):
		return max(1.0, float(attributes.get("combat_turn_ap_max", simulation.DEFAULT_TURN_AP)))
	if attributes.has("turn_ap_max"):
		return max(1.0, float(attributes.get("turn_ap_max", simulation.DEFAULT_TURN_AP)))
	if attributes.has("ap_max"):
		return max(1.0, float(attributes.get("ap_max", simulation.DEFAULT_TURN_AP)))
	return max(simulation.DEFAULT_TURN_AP, turn_ap_gain(simulation, actor))


func affordable_ap_threshold(simulation: RefCounted, actor: RefCounted) -> float:
	var attributes: Dictionary = _dictionary_or_empty(actor.combat_attributes)
	if actor_uses_combat_turn_ap(simulation, actor) and attributes.has("combat_affordable_ap_threshold"):
		return max(0.0, float(attributes.get("combat_affordable_ap_threshold", simulation.AFFORDABLE_AP_THRESHOLD)))
	if attributes.has("affordable_ap_threshold"):
		return max(0.0, float(attributes.get("affordable_ap_threshold", simulation.AFFORDABLE_AP_THRESHOLD)))
	if attributes.has("ap_affordable_threshold"):
		return max(0.0, float(attributes.get("ap_affordable_threshold", simulation.AFFORDABLE_AP_THRESHOLD)))
	return simulation.AFFORDABLE_AP_THRESHOLD


func actor_uses_combat_turn_ap(simulation: RefCounted, actor: RefCounted) -> bool:
	return actor != null and actor.in_combat and bool(simulation.combat_state.get("active", false))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
