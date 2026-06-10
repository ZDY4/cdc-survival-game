extends RefCounted

const AFFORDABLE_AP_THRESHOLD := 1.0
const AUTO_TURN_ADVANCE_LIMIT := 8


func cancel_pending(simulation: RefCounted, reason: String = "cancelled", auto_end_turn: bool = false, topology: Dictionary = {}) -> Dictionary:
	var actor_id: int = simulation._player_actor_id()
	var event_start_index: int = simulation.events.size()
	var had_pending: bool = not simulation.pending_movement.is_empty() or not simulation.pending_interaction.is_empty() or not simulation.pending_crafting.is_empty()
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var ap_before: float = actor.ap if actor != null else 0.0
	var turn_open_before: bool = bool(actor.turn_open) if actor != null else false
	var round_before: int = int(simulation.turn_state.get("round", 1))
	var combat_active_before: bool = bool(simulation.combat_state.get("active", false))
	var movement: Dictionary = simulation.pending_movement.duplicate(true)
	var interaction: Dictionary = simulation.pending_interaction.duplicate(true)
	var crafting: Dictionary = simulation.pending_crafting.duplicate(true)
	simulation.pending_movement.clear()
	simulation.pending_interaction.clear()
	simulation.pending_crafting.clear()
	simulation.interaction_menu.clear()
	if had_pending:
		if not movement.is_empty():
			simulation.emit_event("movement_cancelled", {
				"actor_id": int(movement.get("actor_id", actor_id)),
				"reason": reason,
				"pending_movement": movement.duplicate(true),
			})
		if not interaction.is_empty():
			simulation.emit_event("interaction_cancelled", {
				"actor_id": int(interaction.get("actor_id", actor_id)),
				"reason": reason,
				"pending_interaction": interaction.duplicate(true),
			})
		if not crafting.is_empty():
			simulation.emit_event("crafting_cancelled", {
				"actor_id": int(crafting.get("actor_id", actor_id)),
				"reason": reason,
				"pending_crafting": crafting.duplicate(true),
			})
		simulation.emit_event("pending_cancelled", {
			"actor_id": actor_id,
			"reason": reason,
			"movement": movement,
			"interaction": interaction,
			"crafting": crafting,
		})
	var turn_auto_ended := false
	var auto_end_blocked_reason := ""
	if had_pending and auto_end_turn:
		if actor != null and actor.turn_open and not combat_active_before:
			simulation._close_turn(actor_id, "pending_cancelled:%s" % reason)
			simulation.advance_world_turn(topology)
			simulation._open_turn(actor_id, "player_turn")
			turn_auto_ended = true
		elif combat_active_before:
			auto_end_blocked_reason = "combat_active"
		elif actor == null:
			auto_end_blocked_reason = "actor_missing"
		elif not actor.turn_open:
			auto_end_blocked_reason = "turn_closed"
	var cancel_policy_extra := {
		"combat_active_before": combat_active_before,
		"combat_active_after": bool(simulation.combat_state.get("active", false)),
	}
	if not auto_end_blocked_reason.is_empty():
		cancel_policy_extra["auto_end_blocked_reason"] = auto_end_blocked_reason
	var turn_policy: Dictionary = build_cancel_turn_policy(
		simulation,
		"cancel_pending",
		reason,
		had_pending,
		auto_end_turn,
		turn_auto_ended,
		actor,
		ap_before,
		turn_open_before,
		round_before,
		cancel_policy_extra
	)
	var output := {
		"success": true,
		"had_pending": had_pending,
		"reason": reason,
		"pending_movement": movement.duplicate(true),
		"pending_interaction": interaction.duplicate(true),
		"pending_crafting": crafting.duplicate(true),
		"cancelled_crafting": crafting.duplicate(true),
		"turn_policy": turn_policy,
	}
	var emitted_events: Array[Dictionary] = simulation._events_since(event_start_index)
	output["events"] = emitted_events
	output["runtime_snapshot_delta"] = {
		"active_map_id": simulation.active_map_id,
		"combat_active": bool(simulation.combat_state.get("active", false)),
		"events": emitted_events,
		"pending_movement": simulation.pending_movement.duplicate(true),
		"pending_interaction": simulation.pending_interaction.duplicate(true),
		"pending_crafting": simulation.pending_crafting.duplicate(true),
		"turn_state": simulation.turn_state.duplicate(true),
	}
	return output


func finalize_player_ap_action(simulation: RefCounted, actor: RefCounted, result: Dictionary, command: Dictionary, reason: String) -> Dictionary:
	if actor == null or not bool(result.get("success", false)):
		return result
	var policy: Dictionary = build_turn_policy(simulation, actor, reason, result)
	result["turn_policy"] = policy.duplicate(true)
	if not actor.turn_open:
		result["turn_policy"]["reason"] = "turn_closed"
		return result
	if actor.ap >= float(policy.get("affordable_ap_threshold", 0.0)):
		result["turn_policy"]["reason"] = "ap_still_affordable"
		return result
	if simulation._result_changes_active_map(result):
		result["auto_turn_skipped"] = "map_changed"
		result["turn_policy"]["reason"] = "map_changed"
		return result
	if not str(actor.active_dialogue_id).is_empty():
		result["auto_turn_skipped"] = "active_dialogue"
		result["turn_policy"]["reason"] = "active_dialogue"
		return result
	var topology: Dictionary = _dictionary_or_empty(command.get("topology", {}))
	if topology.is_empty():
		result["auto_turn_skipped"] = "topology_missing"
		result["turn_policy"]["reason"] = "topology_missing"
		return result
	var auto_turn: Dictionary = auto_advance_player_turn(simulation, actor, topology, reason)
	if bool(auto_turn.get("advanced", false)):
		merge_auto_turn_final_result(result, auto_turn)
		result["auto_turn_advanced"] = true
		result["auto_turn"] = auto_turn
		result["turn_state"] = simulation.turn_state.duplicate(true)
		result["turn_policy"]["auto_advanced"] = true
		result["turn_policy"]["reason"] = "ap_depleted_auto_advanced"
		result["turn_policy"]["ap_after_auto"] = actor.ap
		result["turn_policy"]["auto_turn_cycles"] = _array_or_empty(auto_turn.get("cycles", [])).size()
		result["turn_policy"]["auto_turn_limit_reached"] = bool(auto_turn.get("limit_reached", false))
		if bool(auto_turn.get("limit_reached", false)):
			result["auto_turn_limit_reached"] = true
			result["turn_policy"]["reason"] = "auto_advance_limit_reached"
			result["turn_policy"]["auto_turn_limit"] = int(auto_turn.get("limit", AUTO_TURN_ADVANCE_LIMIT))
	else:
		result["turn_policy"]["reason"] = "auto_advance_unresolved"
	return result


func build_turn_policy(simulation: RefCounted, actor: RefCounted, action_kind: String, result: Dictionary) -> Dictionary:
	var ap_after: float = actor.ap if actor != null else 0.0
	var threshold: float = simulation._affordable_ap_threshold(actor) if actor != null else AFFORDABLE_AP_THRESHOLD
	var policy := {
		"action_kind": action_kind,
		"success": bool(result.get("success", false)),
		"ap_after_action": ap_after,
		"affordable_ap_threshold": threshold,
		"below_affordable_threshold": ap_after < threshold,
		"pending_movement": not simulation.pending_movement.is_empty(),
		"pending_interaction": not simulation.pending_interaction.is_empty(),
		"pending_crafting": not simulation.pending_crafting.is_empty(),
		"auto_advanced": false,
		"reason": "pending_evaluation",
	}
	if result.has("ap_cost"):
		policy["ap_cost"] = float(result.get("ap_cost", 0.0))
	elif result.has("steps"):
		policy["ap_cost"] = float(result.get("steps", 0))
	elif result.has("attack_result"):
		var attack_result: Dictionary = _dictionary_or_empty(result.get("attack_result", {}))
		if attack_result.has("ap_cost"):
			policy["ap_cost"] = float(attack_result.get("ap_cost", 0.0))
	if result.has("reason"):
		policy["result_reason"] = str(result.get("reason", ""))
	return policy


func auto_advance_player_turn(simulation: RefCounted, actor: RefCounted, topology: Dictionary, reason: String) -> Dictionary:
	var cycles: Array[Dictionary] = []
	var guard := 0
	var limit_reached := false
	while guard < AUTO_TURN_ADVANCE_LIMIT:
		guard += 1
		if actor == null or not actor.turn_open:
			break
		if actor.ap >= simulation._affordable_ap_threshold(actor):
			break
		if not str(actor.active_dialogue_id).is_empty():
			break
		simulation._close_turn(actor.actor_id, "auto_ap_depleted:%s" % reason)
		var npc_results: Array[Dictionary] = simulation.advance_world_turn(topology)
		simulation._open_turn(actor.actor_id, "auto_player_turn")
		var pending_result: Dictionary = {}
		if not simulation.pending_movement.is_empty() or not simulation.pending_interaction.is_empty() or not simulation.pending_crafting.is_empty():
			pending_result = simulation._resume_pending_for_actor(actor, topology)
		cycles.append({
			"round": int(simulation.turn_state.get("round", 1)),
			"npc_results": npc_results,
			"pending_result": pending_result,
			"player_ap": actor.ap,
		})
		if pending_result.is_empty():
			break
		if not bool(pending_result.get("success", false)):
			break
	limit_reached = guard >= AUTO_TURN_ADVANCE_LIMIT and actor != null and actor.turn_open and actor.ap < simulation._affordable_ap_threshold(actor)
	if limit_reached:
		simulation.emit_event("auto_turn_advance_limit_reached", {
			"actor_id": actor.actor_id,
			"reason": reason,
			"limit": AUTO_TURN_ADVANCE_LIMIT,
			"cycles": cycles.size(),
			"ap": actor.ap,
			"affordable_ap_threshold": simulation._affordable_ap_threshold(actor),
			"pending_movement": simulation.pending_movement.duplicate(true),
			"pending_interaction": simulation.pending_interaction.duplicate(true),
			"pending_crafting": simulation.pending_crafting.duplicate(true),
			"round": int(simulation.turn_state.get("round", 1)),
		})
	return {
		"advanced": not cycles.is_empty(),
		"cycles": cycles,
		"limit": AUTO_TURN_ADVANCE_LIMIT,
		"limit_reached": limit_reached,
	}


func merge_auto_turn_final_result(result: Dictionary, auto_turn: Dictionary) -> void:
	var cycles: Array = _array_or_empty(auto_turn.get("cycles", []))
	for cycle_index in range(cycles.size() - 1, -1, -1):
		var cycle: Dictionary = _dictionary_or_empty(cycles[cycle_index])
		var pending_result: Dictionary = _dictionary_or_empty(cycle.get("pending_result", {}))
		if pending_result.is_empty() or not bool(pending_result.get("success", false)):
			continue
		for key in ["dialogue_id", "requested_dialogue_id", "dialogue_rule_key", "dialogue_rule_source", "dialogue_state", "container", "context_snapshot", "consumed_target", "item_id", "count", "inventory_before", "inventory_after", "defeated", "attack_result", "auto_resumed_interaction", "resumed_pending_interaction", "approach_result", "recipe_id", "output_item_id", "output_count", "craft_time", "ap_cost", "ap_remaining", "completed_count", "requested_count", "pending_crafting", "resumed_pending_crafting"]:
			if pending_result.has(key) and not result.has(key):
				result[key] = pending_result.get(key)
		if pending_result.has("kind") and str(result.get("kind", "")) == "pending_movement_completed":
			result["kind"] = pending_result.get("kind")
		result["auto_turn_final_result"] = pending_result.duplicate(true)
		return


func build_cancel_turn_policy(simulation: RefCounted, action_kind: String, reason: String, had_pending: bool, auto_end_requested: bool, auto_advanced: bool, actor: RefCounted, ap_before: float, turn_open_before: bool, round_before: int, extra: Dictionary = {}) -> Dictionary:
	var policy := {
		"action_kind": action_kind,
		"success": true,
		"reason": "auto_ended" if auto_advanced else ("preserved_turn" if had_pending else "no_pending"),
		"cancel_reason": reason,
		"had_pending": had_pending,
		"auto_end_requested": auto_end_requested,
		"auto_advanced": auto_advanced,
		"turn_open_before": turn_open_before,
		"turn_open_after": bool(actor.turn_open) if actor != null else false,
		"round_before": round_before,
		"round_after": int(simulation.turn_state.get("round", 1)),
		"ap_before_cancel": ap_before,
		"ap_after_cancel": actor.ap if actor != null else 0.0,
		"pending_movement": false,
		"pending_interaction": false,
		"pending_crafting": false,
	}
	for key in extra.keys():
		policy[key] = extra[key]
	return policy


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
