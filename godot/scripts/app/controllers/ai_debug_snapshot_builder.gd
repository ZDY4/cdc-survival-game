extends RefCounted


func snapshot(simulation: RefCounted, focused_actor: Dictionary) -> Dictionary:
	if simulation == null:
		return {"intent_count": 0, "intents": [], "focused_intent": {}}
	var focused_actor_id := int(focused_actor.get("actor_id", 0))
	var intents: Array[Dictionary] = []
	var focused_intent: Dictionary = {}
	# 直接读活 sim 的 ai_intents（按 actor_id 排序，与快照序列化顺序一致），避免跑整局全量 snapshot()。
	var intent_ids: Array = simulation.ai_intents.keys()
	intent_ids.sort()
	for intent_id in intent_ids:
		var intent: Dictionary = intent_summary(_dictionary_or_empty(simulation.ai_intents[intent_id]))
		if intent.is_empty():
			continue
		if focused_actor_id > 0 and int(intent.get("actor_id", 0)) == focused_actor_id:
			focused_intent = intent.duplicate(true)
		intents.append(intent)
	var latest: Dictionary = intents[intents.size() - 1].duplicate(true) if not intents.is_empty() else {}
	return {
		"intent_count": intents.size(),
		"intents": intents,
		"focused_actor_id": focused_actor_id,
		"focused_intent": focused_intent,
		"latest_intent": latest,
	}


func intent_summary(intent: Dictionary) -> Dictionary:
	var actor_id := int(intent.get("actor_id", 0))
	if actor_id <= 0:
		return {}
	var path: Array = _array_or_empty(intent.get("path", []))
	var target_actor_id := int(intent.get("target_actor_id", 0))
	var reason := str(intent.get("reason", ""))
	var intent_kind := str(intent.get("intent", ""))
	var target_tracking_state := str(intent.get("target_tracking_state", ""))
	var settlement_id := str(intent.get("settlement_id", ""))
	var route_id := str(intent.get("route_id", ""))
	var anchor_id := str(intent.get("anchor_id", ""))
	var smart_object_id := str(intent.get("smart_object_id", ""))
	var schedule_label := str(intent.get("schedule_label", ""))
	var planner: Dictionary = _dictionary_or_empty(intent.get("planner", {}))
	var planner_goal_id := str(planner.get("goal_id", intent.get("goal_id", "")))
	var planner_action_id := str(planner.get("action_id", intent.get("planner_action_id", "")))
	var life_status_id := life_status_id(intent_kind, planner_action_id, reason)
	var life_status_group := life_status_group(life_status_id, planner_action_id)
	var life_goal_kind := "settlement_life" if not settlement_id.is_empty() else ("combat" if target_actor_id > 0 else "idle")
	var goal_id := "none"
	if target_actor_id > 0:
		goal_id = "hostile_target"
	elif not planner_goal_id.is_empty():
		goal_id = planner_goal_id
	elif not route_id.is_empty():
		goal_id = route_id
	elif not smart_object_id.is_empty():
		goal_id = smart_object_id
	elif not anchor_id.is_empty():
		goal_id = anchor_id
	var goal := {
		"id": goal_id,
		"kind": life_goal_kind,
		"target_actor_id": target_actor_id,
		"target_grid": _dictionary_or_empty(intent.get("target_grid", {})).duplicate(true),
		"settlement_id": settlement_id,
		"route_id": route_id,
		"anchor_id": anchor_id,
		"smart_object_id": smart_object_id,
		"planner_score": float(planner.get("goal_score", intent.get("planner_goal_score", 0.0))),
		"planner_action_id": planner_action_id,
		"life_status_id": life_status_id,
		"life_status_group": life_status_group,
		"tracking_state": target_tracking_state,
		"lost": bool(intent.get("target_lost", false)),
		"lost_reason": str(intent.get("target_lost_reason", "")),
	}
	var action := {
		"id": planner_action_id if not planner_action_id.is_empty() else intent_kind,
		"kind": intent_kind,
		"reason": reason,
		"planned_intent": str(intent.get("planned_intent", "")),
		"planner_reason": str(planner.get("action_reason", intent.get("planner_action_reason", ""))),
		"planner_cost": float(planner.get("action_cost", 0.0)),
		"path_length": path.size(),
		"remaining_steps": int(intent.get("remaining_steps", 0)),
		"required_ap": float(intent.get("required_ap", 0.0)),
		"available_ap": float(intent.get("available_ap", intent.get("ap", 0.0))),
		"settlement_id": settlement_id,
		"route_id": route_id,
		"anchor_id": anchor_id,
		"smart_object_id": smart_object_id,
		"schedule_label": schedule_label,
		"life_status_id": life_status_id,
		"life_status_group": life_status_group,
	}
	var blackboard := {
		"target_actor_id": target_actor_id,
		"previous_target_actor_id": int(intent.get("previous_target_actor_id", 0)),
		"last_seen_target_actor_id": int(intent.get("last_seen_target_actor_id", 0)),
		"target_tracking_state": target_tracking_state,
		"target_lost": bool(intent.get("target_lost", false)),
		"target_lost_reason": str(intent.get("target_lost_reason", "")),
		"candidate_count": int(intent.get("candidate_count", 0)),
		"blocked_by_los_count": int(intent.get("blocked_by_los_count", 0)),
		"ammo_ready": bool(intent.get("ammo_ready", true)),
		"can_reload": bool(intent.get("can_reload", false)),
		"ap": float(intent.get("ap", 0.0)),
		"settlement_id": settlement_id,
		"route_id": route_id,
		"route_grid_count": _array_or_empty(intent.get("route_grids", [])).size(),
		"anchor_id": anchor_id,
		"smart_object_id": smart_object_id,
		"schedule_label": schedule_label,
		"planner_goal_id": planner_goal_id,
		"planner_action_id": planner_action_id,
		"life_status_id": life_status_id,
		"life_status_group": life_status_group,
		"planner_score_rule_ids": _array_or_empty(planner.get("score_rule_ids", [])).duplicate(true),
		"planner_facts": _dictionary_or_empty(planner.get("facts", {})).duplicate(true),
	}
	return {
		"actor_id": actor_id,
		"intent": intent_kind,
		"reason": reason,
		"settlement_id": settlement_id,
		"route_id": route_id,
		"route_grid_count": _array_or_empty(intent.get("route_grids", [])).size(),
		"anchor_id": anchor_id,
		"smart_object_id": smart_object_id,
		"schedule_label": schedule_label,
		"life_status_id": life_status_id,
		"life_status_group": life_status_group,
		"target_actor_id": target_actor_id,
		"target_grid": _dictionary_or_empty(intent.get("target_grid", {})).duplicate(true),
		"path_length": path.size(),
		"ap": float(intent.get("ap", 0.0)),
		"distance": float(intent.get("distance", -1.0)),
		"aggro_range": float(intent.get("aggro_range", 0.0)),
		"attack_range": float(intent.get("attack_range", 0.0)),
		"weapon_item_id": str(intent.get("weapon_item_id", "")),
		"ammo_type": str(intent.get("ammo_type", "")),
		"ammo_ready": bool(intent.get("ammo_ready", true)),
		"can_reload": bool(intent.get("can_reload", false)),
		"failure_reason": str(intent.get("failure_reason", intent.get("reason", ""))),
		"planner": planner.duplicate(true),
		"goal": goal,
		"action": action,
		"blackboard": blackboard,
		"target_tracking_state": target_tracking_state,
		"target_lost": bool(intent.get("target_lost", false)),
		"target_lost_reason": str(intent.get("target_lost_reason", "")),
	}


func life_status_id(intent_kind: String, planner_action_id: String, reason: String) -> String:
	if reason.begins_with("life_") and reason.ends_with("_unreachable"):
		return "blocked"
	match planner_action_id:
		"travel_to_duty_area", "travel_home", "travel_to_canteen", "travel_to_leisure":
			return "traveling"
		"patrol_route":
			return "patrolling"
		"stand_guard", "respond_alarm", "raise_alarm":
			return "guarding"
		"restock_meal_service":
			return "servicing"
		"treat_patients":
			return "treating"
		"eat_meal":
			return "eating"
		"sleep":
			return "resting"
		"relax":
			return "relaxing"
		"idle_safely":
			return "idle"
	match intent_kind:
		"follow_route":
			return "patrolling"
		"return_home":
			return "traveling"
		"use_smart_object":
			return "servicing"
	return ""


func life_status_group(state_id: String, planner_action_id: String) -> String:
	match state_id:
		"traveling", "patrolling":
			return "work"
		"guarding", "servicing", "treating":
			return "service"
		"eating", "resting", "relaxing":
			return "rest"
		"blocked":
			return "blocked"
	if state_id.is_empty() and planner_action_id.is_empty():
		return ""
	return "idle" if state_id == "idle" else "work"


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
