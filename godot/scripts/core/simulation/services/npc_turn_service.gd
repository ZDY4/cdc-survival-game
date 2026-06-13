extends RefCounted


func advance_turn(simulation: RefCounted, actor: RefCounted, topology: Dictionary, combat_turn_active: bool = false) -> Dictionary:
	if simulation._actor_has_special_effect(actor, "stun"):
		return simulation._stunned_npc_turn_result(actor, "npc_turn")
	if combat_turn_active:
		return advance_combat_turn(simulation, actor, topology)
	return advance_action(simulation, actor, topology)


func advance_runner_step(simulation: RefCounted, actor: RefCounted, topology: Dictionary, combat_turn_active: bool = false) -> Dictionary:
	if simulation._actor_has_special_effect(actor, "stun"):
		return simulation._stunned_npc_turn_result(actor, "npc_turn")
	var result: Dictionary = advance_action(simulation, actor, topology)
	result["runner_step"] = true
	result["combat_turn_active"] = combat_turn_active
	result["ap_after_action"] = actor.ap if actor != null else 0.0
	result["can_continue_turn"] = _can_continue_after_runner_step(simulation, actor, result, combat_turn_active)
	return result


func advance_combat_turn(simulation: RefCounted, actor: RefCounted, topology: Dictionary) -> Dictionary:
	var actions: Array[Dictionary] = []
	var ap_before: float = actor.ap
	var limit_reached := false
	while actor != null and actor.ap >= simulation._affordable_ap_threshold(actor):
		if actions.size() >= simulation.MAX_NPC_COMBAT_ACTIONS_PER_TURN:
			limit_reached = true
			break
		var action: Dictionary = advance_action(simulation, actor, topology)
		actions.append(action.duplicate(true))
		var intent := str(action.get("intent", ""))
		if intent == "idle" or intent == "wait":
			break
		if not bool(action.get("success", false)):
			break
		if not bool(simulation.combat_state.get("active", false)) or not actor.in_combat:
			break
		if float(actor.ap) <= 0.0:
			break
	var output: Dictionary = actions.back().duplicate(true) if not actions.is_empty() else {
		"success": true,
		"actor_id": actor.actor_id if actor != null else 0,
		"intent": "idle",
		"reason": "no_combat_action",
	}
	output["actions"] = actions
	output["action_count"] = actions.size()
	output["ap_before_actions"] = ap_before
	output["ap_after_actions"] = actor.ap if actor != null else 0.0
	output["combat_action_loop"] = true
	output["combat_action_limit"] = simulation.MAX_NPC_COMBAT_ACTIONS_PER_TURN
	output["combat_action_limit_reached"] = limit_reached
	if limit_reached:
		simulation.emit_event("npc_combat_action_limit_reached", {
			"actor_id": actor.actor_id if actor != null else 0,
			"action_count": actions.size(),
			"ap": actor.ap if actor != null else 0.0,
			"limit": simulation.MAX_NPC_COMBAT_ACTIONS_PER_TURN,
		})
	return output


func advance_action(simulation: RefCounted, actor: RefCounted, topology: Dictionary) -> Dictionary:
	var weapon_profile: Dictionary = simulation._attack_profile(actor, simulation.item_library)
	var intent: Dictionary = simulation.decide_actor_intent(actor.actor_id, {
		"topology": topology,
		"active_map_id": simulation.active_map_id,
		"weapon_profile": simulation._npc_weapon_context(actor, weapon_profile),
	})
	var target_actor_id: int = int(intent.get("target_actor_id", simulation._player_actor_id()))
	match str(intent.get("intent", "")):
		"attack":
			var attack_cost: float = float(weapon_profile.get("ap_cost", simulation.DEFAULT_ATTACK_AP))
			if actor.ap < attack_cost:
				return wait_for_ap(simulation, actor, target_actor_id, "attack", "ap_insufficient_npc_attack", attack_cost)
			var ammo_check: Dictionary = simulation._attack_ammo_check(actor, weapon_profile)
			if not bool(ammo_check.get("success", true)):
				ammo_check["actor_id"] = actor.actor_id
				ammo_check["target_actor_id"] = target_actor_id
				ammo_check["intent"] = "attack"
				return ammo_check
			var durability_check: Dictionary = simulation._attack_weapon_durability_check(actor, weapon_profile)
			if not bool(durability_check.get("success", true)):
				durability_check["actor_id"] = actor.actor_id
				durability_check["target_actor_id"] = target_actor_id
				durability_check["intent"] = "attack"
				return durability_check
			simulation._spend_ap(actor, attack_cost, "npc_attack")
			simulation._enter_combat([actor.actor_id, target_actor_id], "npc_attack")
			var result: Dictionary = simulation.perform_attack(actor.actor_id, target_actor_id, topology, {
				"range": int(weapon_profile.get("range", simulation.DEFAULT_ATTACK_RANGE)),
				"min_range": int(weapon_profile.get("min_range", 0)),
				"weapon_profile": weapon_profile,
			})
			if bool(result.get("success", false)):
				var ammo_result: Dictionary = simulation._consume_attack_ammo(actor, weapon_profile)
				if bool(ammo_result.get("consumed", false)):
					result["ammo_consumed"] = ammo_result
				var durability_result: Dictionary = simulation._consume_attack_weapon_durability(actor, weapon_profile)
				if bool(durability_result.get("consumed", false)):
					result["weapon_durability_consumed"] = durability_result
			result["intent"] = "attack"
			return result
		"reload":
			var reload_result: Dictionary = simulation._submit_reload_equipped_action(actor, {
				"slot_id": str(weapon_profile.get("equipment_slot", "main_hand")),
			}, simulation.item_library)
			if not bool(reload_result.get("success", false)) and str(reload_result.get("reason", "")) == "ap_insufficient_reload":
				return wait_for_ap(simulation, actor, target_actor_id, "reload", "ap_insufficient_npc_reload", float(reload_result.get("required_ap", 0.0)))
			reload_result["actor_id"] = actor.actor_id
			reload_result["intent"] = "reload"
			reload_result["target_actor_id"] = target_actor_id
			return reload_result
		"approach":
			var move_result: Dictionary = simulation._npc_approach(actor, target_actor_id, topology)
			move_result["intent"] = "approach"
			return move_result
		"follow_route", "return_home", "use_smart_object":
			return simulation._advance_npc_life_action(actor, intent, topology)
	return {
		"success": true,
		"actor_id": actor.actor_id,
		"intent": "idle",
		"reason": intent.get("reason", "idle"),
	}


func _can_continue_after_runner_step(simulation: RefCounted, actor: RefCounted, result: Dictionary, combat_turn_active: bool) -> bool:
	if actor == null:
		return false
	var combat_active_now: bool = combat_turn_active or (bool(simulation.combat_state.get("active", false)) and actor.in_combat)
	if not combat_active_now:
		return false
	if not bool(result.get("success", false)):
		return false
	var intent := str(result.get("intent", ""))
	if intent == "idle" or intent == "wait":
		return false
	if not bool(simulation.combat_state.get("active", false)) or not actor.in_combat:
		return false
	if actor.ap < simulation._affordable_ap_threshold(actor):
		return false
	return true


func wait_for_ap(simulation: RefCounted, actor: RefCounted, target_actor_id: int, planned_intent: String, reason: String, required_ap: float) -> Dictionary:
	simulation.emit_event("actor_waited", {
		"actor_id": actor.actor_id,
		"ap_before": actor.ap,
		"reason": reason,
		"planned_intent": planned_intent,
		"target_actor_id": target_actor_id,
		"required_ap": required_ap,
		"available_ap": actor.ap,
	})
	return {
		"success": true,
		"actor_id": actor.actor_id,
		"target_actor_id": target_actor_id,
		"intent": "wait",
		"planned_intent": planned_intent,
		"reason": reason,
		"required_ap": required_ap,
		"available_ap": actor.ap,
	}


func turn_close_reason(actor: RefCounted, result: Dictionary) -> String:
	if actor == null:
		return "npc_turn_actor_missing"
	if actor.ap <= 0.0:
		return "npc_turn_exhausted"
	if str(result.get("intent", "")) == "skip" and bool(result.get("skipped_turn", false)):
		return "npc_turn_stunned"
	if str(result.get("intent", "")) == "idle":
		return "npc_turn_idle"
	if str(result.get("intent", "")) == "wait":
		return "npc_turn_waiting_for_ap"
	if not bool(result.get("success", false)):
		return "npc_turn_failed:%s" % str(result.get("reason", "unknown"))
	return "npc_turn_complete"
