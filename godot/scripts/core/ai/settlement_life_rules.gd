extends RefCounted


func decide_intent(actor: RefCounted, context: Dictionary) -> Dictionary:
	var life: Dictionary = _dictionary_or_empty(actor.life)
	var ai_library: Dictionary = _dictionary_or_empty(context.get("ai", {}))
	var settlement: Dictionary = _settlement_data(str(life.get("settlement_id", "")), _dictionary_or_empty(context.get("settlements", {})))
	if settlement.is_empty():
		return _idle_intent(actor, "settlement_missing")

	var minute_of_day: int = posmod(int(context.get("minute_of_day", 0)), 1440)
	var day: String = str(context.get("day", "monday"))
	var schedule_block: Dictionary = _active_schedule_block(str(life.get("schedule_profile_id", "")), day, minute_of_day, ai_library)
	var planner_intent: Dictionary = _planned_life_intent(actor, life, settlement, ai_library, context, schedule_block, day, minute_of_day)
	if not planner_intent.is_empty():
		return planner_intent

	if not schedule_block.is_empty():
		var route: Dictionary = _route_by_id(settlement, str(life.get("duty_route_id", "")))
		if not route.is_empty():
			return {
				"success": true,
				"actor_id": actor.actor_id,
				"intent": "follow_route",
				"settlement_id": str(settlement.get("id", "")),
				"route_id": str(route.get("id", "")),
				"route_grids": _route_grids(route, settlement),
				"schedule_label": str(schedule_block.get("label", "")),
			}
		var duty_object: Dictionary = _first_accessible_smart_object(life, settlement, _dictionary_or_empty(context.get("ai", {})))
		if not duty_object.is_empty():
			return {
				"success": true,
				"actor_id": actor.actor_id,
				"intent": "use_smart_object",
				"settlement_id": str(settlement.get("id", "")),
				"smart_object_id": str(duty_object.get("id", "")),
				"smart_object_kind": str(duty_object.get("kind", "")),
				"smart_object_tags": _array_or_empty(duty_object.get("tags", [])).duplicate(true),
				"target_grid": _anchor_grid(settlement, str(duty_object.get("anchor_id", ""))),
				"schedule_label": str(schedule_block.get("label", "")),
			}

	var home_anchor: String = str(life.get("home_anchor", ""))
	if not home_anchor.is_empty():
		return {
			"success": true,
			"actor_id": actor.actor_id,
			"intent": "return_home",
			"settlement_id": str(settlement.get("id", "")),
			"anchor_id": home_anchor,
			"target_grid": _anchor_grid(settlement, home_anchor),
		}
	return _idle_intent(actor, "life_no_home_anchor")


func _planned_life_intent(actor: RefCounted, life: Dictionary, settlement: Dictionary, ai_library: Dictionary, context: Dictionary, schedule_block: Dictionary, day: String, minute_of_day: int) -> Dictionary:
	var planner_data: Dictionary = _planner_data(ai_library)
	if planner_data.is_empty():
		return {}
	var state: Dictionary = _planner_world_state(actor, life, settlement, ai_library, context, schedule_block, day, minute_of_day)
	var facts: Dictionary = _evaluate_planner_facts(planner_data, state)
	state["facts"] = facts
	var behavior_chain: Array[Dictionary] = _behavior_chain(str(life.get("ai_behavior_profile_id", "")), ai_library)
	var goal_ids: Array = _available_goal_ids(behavior_chain, planner_data)
	var action_ids: Array = _available_action_ids(behavior_chain, planner_data)
	var scored_goals: Array[Dictionary] = _score_goals(goal_ids, planner_data, state)
	var queued_intent: Dictionary = _queued_life_intent(actor, life, settlement, ai_library, planner_data, state, schedule_block, scored_goals)
	if not queued_intent.is_empty():
		return queued_intent
	for scored_goal in scored_goals:
		var goal: Dictionary = _dictionary_or_empty(scored_goal.get("goal", {}))
		var requirements: Array = _goal_requirements(goal, state)
		var action_result: Dictionary = _select_goal_action(requirements, action_ids, planner_data, state)
		if action_result.is_empty():
			continue
		var action: Dictionary = _dictionary_or_empty(action_result.get("action", {}))
		var intent: Dictionary = _intent_for_planner_action(actor, life, settlement, ai_library, action, schedule_block)
		if intent.is_empty():
			continue
		var planner_summary: Dictionary = {
			"goal_id": str(goal.get("id", "")),
			"goal_score": float(scored_goal.get("score", 0.0)),
			"score_rule_ids": _array_or_empty(scored_goal.get("score_rule_ids", [])).duplicate(true),
			"action_id": str(action.get("id", "")),
			"action_cost": float(action.get("planner_cost", 0.0)),
			"action_reason": str(action_result.get("reason", "")),
			"action_queue": _array_or_empty(action_result.get("action_queue", [])).duplicate(true),
			"queue_length": _array_or_empty(action_result.get("action_queue", [])).size(),
			"current_action_index": 0,
			"queue_remaining": _array_or_empty(action_result.get("action_queue", [])).size(),
			"queue_complete": false,
			"requirements": requirements.duplicate(true),
			"unmet_requirements": _unmet_assignments(requirements, state),
			"facts": facts.duplicate(true),
			"role": str(state.get("role", "")),
		}
		intent["planner"] = planner_summary
		intent["goal_id"] = str(goal.get("id", ""))
		intent["planner_action_id"] = str(action.get("id", ""))
		intent["planner_action_reason"] = str(action_result.get("reason", ""))
		intent["planner_goal_score"] = float(scored_goal.get("score", 0.0))
		return intent
	return {}


func _queued_life_intent(actor: RefCounted, life: Dictionary, settlement: Dictionary, ai_library: Dictionary, planner_data: Dictionary, state: Dictionary, schedule_block: Dictionary, scored_goals: Array[Dictionary]) -> Dictionary:
	var runtime: Dictionary = _dictionary_or_empty(life.get("runtime", {}))
	var runtime_planner: Dictionary = _dictionary_or_empty(runtime.get("planner", {}))
	if runtime_planner.is_empty() or bool(runtime_planner.get("queue_complete", false)):
		return {}
	if bool(runtime_planner.get("replan_requested", false)):
		return {}
	var queue: Array = _array_or_empty(runtime_planner.get("action_queue", []))
	var current_index: int = int(runtime_planner.get("current_action_index", 0))
	if queue.is_empty() or current_index < 0 or current_index >= queue.size():
		return {}
	var queued_goal_id := str(runtime_planner.get("goal_id", ""))
	if queued_goal_id.is_empty() or _top_scored_goal_id(scored_goals) != queued_goal_id:
		return {}
	var queued_action_id := str(_dictionary_or_empty(queue[current_index]).get("action_id", ""))
	var action: Dictionary = _dictionary_or_empty(_dictionary_or_empty(planner_data.get("actions", {})).get(queued_action_id, {}))
	if action.is_empty() or not _assignments_satisfied(_array_or_empty(action.get("preconditions", [])), state):
		return {}
	var intent: Dictionary = _intent_for_planner_action(actor, life, settlement, ai_library, action, schedule_block)
	if intent.is_empty():
		return {}
	var planner_summary: Dictionary = runtime_planner.duplicate(true)
	planner_summary["action_id"] = queued_action_id
	planner_summary["action_cost"] = float(action.get("planner_cost", 0.0))
	planner_summary["action_reason"] = "queued_action"
	planner_summary["facts"] = _dictionary_or_empty(state.get("facts", {})).duplicate(true)
	planner_summary["current_action_index"] = current_index
	planner_summary["queue_length"] = queue.size()
	planner_summary["queue_remaining"] = max(0, queue.size() - current_index)
	planner_summary["queue_complete"] = false
	intent["planner"] = planner_summary
	intent["goal_id"] = queued_goal_id
	intent["planner_action_id"] = queued_action_id
	intent["planner_action_reason"] = "queued_action"
	intent["planner_goal_score"] = float(planner_summary.get("goal_score", 0.0))
	return intent


func _top_scored_goal_id(scored_goals: Array[Dictionary]) -> String:
	if scored_goals.is_empty():
		return ""
	var goal: Dictionary = _dictionary_or_empty(_dictionary_or_empty(scored_goals.front()).get("goal", {}))
	return str(goal.get("id", ""))


func _planner_data(ai_library: Dictionary) -> Dictionary:
	var output := {
		"facts": {},
		"score_rules": {},
		"goals": {},
		"actions": {},
		"goal_groups": {},
		"action_groups": {},
		"fact_groups": {},
	}
	for record in ai_library.values():
		var data: Dictionary = _record_data(record)
		for collection_name in output.keys():
			if not data.has(collection_name):
				continue
			for entry in _array_or_empty(data.get(collection_name, [])):
				var entry_data: Dictionary = _dictionary_or_empty(entry)
				var entry_id := str(entry_data.get("id", ""))
				if not entry_id.is_empty():
					output[collection_name][entry_id] = entry_data
	return output


func _planner_world_state(actor: RefCounted, life: Dictionary, settlement: Dictionary, ai_library: Dictionary, context: Dictionary, schedule_block: Dictionary, day: String, minute_of_day: int) -> Dictionary:
	var runtime: Dictionary = _dictionary_or_empty(life.get("runtime", {}))
	var reservations: Dictionary = _dictionary_or_empty(runtime.get("reservations", {}))
	var needs: Dictionary = _dictionary_or_empty(runtime.get("needs", {}))
	var hunger := _need_current(needs, "hunger")
	var energy := _need_current(needs, "energy")
	var morale := _need_current(needs, "morale")
	var home_anchor := str(life.get("home_anchor", ""))
	var duty_anchor := _duty_anchor_id(life, settlement)
	var current_anchor := _current_anchor_id(actor, settlement)
	var role := _life_role(life)
	var personality: Dictionary = _profile_by_id(ai_library, "personality_profiles", str(life.get("personality_profile_id", "")))
	var meal_window_open := _meal_window_open(settlement, minute_of_day)
	var on_shift := not schedule_block.is_empty()
	var shift_starting_soon := _shift_starting_soon(str(life.get("schedule_profile_id", "")), day, minute_of_day, ai_library)
	var bed_reserved: bool = bool(runtime.get("bed_reserved", false)) or _reservation_active(reservations, "bed")
	var meal_object_reserved: bool = bool(runtime.get("meal_object_reserved", false)) or _reservation_active(reservations, "meal_object")
	var guard_post_reserved: bool = bool(runtime.get("guard_post_reserved", false)) or _reservation_active(reservations, "guard_post")
	var medical_station_reserved: bool = bool(runtime.get("medical_station_reserved", false)) or _reservation_active(reservations, "medical_station")
	var leisure_object_reserved: bool = bool(runtime.get("leisure_object_reserved", false)) or _reservation_active(reservations, "leisure_object")
	var state := {
		"role": role,
		"need.hunger": hunger,
		"need.energy": energy,
		"need.morale": morale,
		"schedule.on_shift": on_shift,
		"schedule.shift_starting_soon": shift_starting_soon,
		"schedule.meal_window_open": meal_window_open,
		"world.alert_active": bool(context.get("world_alert_active", false)),
		"anchor.current": current_anchor,
		"anchor.home": home_anchor,
		"anchor.duty": duty_anchor,
		"at_home": not home_anchor.is_empty() and current_anchor == home_anchor,
		"at_duty_area": not duty_anchor.is_empty() and current_anchor == duty_anchor,
		"at_canteen": current_anchor == "canteen_main" or current_anchor == "kitchen_station",
		"at_leisure": current_anchor == "recreation_yard",
		"on_shift": on_shift,
		"threat_detected": bool(context.get("world_alert_active", false)),
		"availability.patrol_route": not _route_by_id(settlement, str(life.get("duty_route_id", ""))).is_empty(),
		"settlement.guard_coverage_insufficient": bool(context.get("guard_coverage_insufficient", false)),
		"reservation.bed.active": bed_reserved,
		"reservation.meal_object.active": meal_object_reserved,
		"reservation.guard_post.active": guard_post_reserved,
		"reservation.medical_station.active": medical_station_reserved,
		"reservation.leisure_object.active": leisure_object_reserved,
		"has_reserved_bed": bed_reserved,
		"has_reserved_meal_seat": meal_object_reserved,
		"has_reserved_guard_post": guard_post_reserved,
		"has_reserved_medical_station": medical_station_reserved,
		"has_reserved_leisure_object": leisure_object_reserved,
		"is_hungry": hunger <= 50.0,
		"is_very_hungry": hunger <= 25.0,
		"sleepy": energy <= 50.0,
		"exhausted": energy <= 25.0,
		"is_rested": energy >= 70.0,
		"need_morale": morale <= 40.0,
		"morale_recovered": morale >= 70.0,
		"is_idle_safe": false,
	}
	for key in _dictionary_or_empty(runtime.get("planner_state", {})).keys():
		var state_key := str(key)
		state[state_key] = runtime["planner_state"][key]
	for key in personality.keys():
		state["personality.%s" % str(key)] = personality[key]
	return state


func _evaluate_planner_facts(planner_data: Dictionary, state: Dictionary) -> Dictionary:
	var facts: Dictionary = {}
	for fact_id in _dictionary_or_empty(planner_data.get("facts", {})).keys():
		var fact: Dictionary = _dictionary_or_empty(planner_data["facts"].get(fact_id, {}))
		facts[str(fact_id)] = _condition_matches(_dictionary_or_empty(fact.get("condition", {})), state, facts)
	return facts


func _score_goals(goal_ids: Array, planner_data: Dictionary, state: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var goals: Dictionary = _dictionary_or_empty(planner_data.get("goals", {}))
	for goal_id in goal_ids:
		var goal: Dictionary = _dictionary_or_empty(goals.get(str(goal_id), {}))
		if goal.is_empty():
			continue
		var score := 0.0
		var matched_rules: Array = []
		for rule_id in _array_or_empty(goal.get("score_rule_ids", [])):
			var rule: Dictionary = _dictionary_or_empty(_dictionary_or_empty(planner_data.get("score_rules", {})).get(str(rule_id), {}))
			if rule.is_empty():
				continue
			if rule.has("when") and not _condition_matches(_dictionary_or_empty(rule.get("when", {})), state, _dictionary_or_empty(state.get("facts", {}))):
				continue
			var delta := float(rule.get("score_delta", 0.0))
			var multiplier_key := str(rule.get("score_multiplier_key", ""))
			if not multiplier_key.is_empty():
				delta *= float(state.get(multiplier_key, 1.0))
			score += delta
			matched_rules.append(str(rule_id))
		if score <= 0.0 and str(goal.get("id", "")) == "idle_safely":
			score = 1.0
		output.append({"goal": goal, "score": score, "score_rule_ids": matched_rules})
	output.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.get("score", 0.0)) > float(right.get("score", 0.0))
	)
	return output


func _goal_requirements(goal: Dictionary, state: Dictionary) -> Array:
	var output: Array = _array_or_empty(goal.get("planner_requirements", [])).duplicate(true)
	for conditional in _array_or_empty(goal.get("conditional_requirements", [])):
		var conditional_data: Dictionary = _dictionary_or_empty(conditional)
		if conditional_data.has("when") and not _condition_matches(_dictionary_or_empty(conditional_data.get("when", {})), state, _dictionary_or_empty(state.get("facts", {}))):
			continue
		output.append_array(_array_or_empty(conditional_data.get("requirements", [])))
	return output


func _select_goal_action(requirements: Array, action_ids: Array, planner_data: Dictionary, state: Dictionary) -> Dictionary:
	var unmet: Array = _unmet_assignments(requirements, state)
	var actions: Dictionary = _dictionary_or_empty(planner_data.get("actions", {}))
	var best: Dictionary = {}
	var best_score := -INF
	for action_id in action_ids:
		var action: Dictionary = _dictionary_or_empty(actions.get(str(action_id), {}))
		if action.is_empty():
			continue
		var match_count := _effect_match_count(_array_or_empty(action.get("effects", [])), unmet)
		if match_count <= 0 and not unmet.is_empty():
			continue
		if not _assignments_satisfied(_array_or_empty(action.get("preconditions", [])), state):
			var support: Dictionary = _support_action_for_preconditions(action, action_ids, actions, state)
			if support.is_empty():
				continue
			return {
				"action": support,
				"reason": "support_precondition:%s" % str(action.get("id", "")),
				"action_queue": [_planner_action_summary(support), _planner_action_summary(action)],
			}
		var score := float(match_count * 100) - float(action.get("planner_cost", 0.0))
		if unmet.is_empty() and _assignments_satisfied(_array_or_empty(action.get("preconditions", [])), state):
			score += 10.0
		if score > best_score:
			best_score = score
			best = action
	if best.is_empty():
		return {}
	return {"action": best, "reason": "satisfy_goal", "action_queue": [_planner_action_summary(best)]}


func _planner_action_summary(action: Dictionary) -> Dictionary:
	return {
		"action_id": str(action.get("id", "")),
		"executor_binding_id": str(action.get("executor_binding_id", "")),
		"planner_cost": float(action.get("planner_cost", 0.0)),
		"target_anchor": str(action.get("target_anchor", "")),
		"reservation_target": str(action.get("reservation_target", "")),
		"need_effects": _dictionary_or_empty(action.get("need_effects", {})).duplicate(true),
		"effects": _array_or_empty(action.get("effects", [])).duplicate(true),
		"world_state_effects": _dictionary_or_empty(action.get("world_state_effects", {})).duplicate(true),
	}


func _support_action_for_preconditions(action: Dictionary, action_ids: Array, actions: Dictionary, state: Dictionary) -> Dictionary:
	var missing: Array = _unmet_assignments(_array_or_empty(action.get("preconditions", [])), state)
	for action_id in action_ids:
		var candidate: Dictionary = _dictionary_or_empty(actions.get(str(action_id), {}))
		if candidate.is_empty() or str(candidate.get("id", "")) == str(action.get("id", "")):
			continue
		if _effect_match_count(_array_or_empty(candidate.get("effects", [])), missing) <= 0:
			continue
		if _assignments_satisfied(_array_or_empty(candidate.get("preconditions", [])), state):
			return candidate
	return {}


func _intent_for_planner_action(actor: RefCounted, life: Dictionary, settlement: Dictionary, ai_library: Dictionary, action: Dictionary, schedule_block: Dictionary) -> Dictionary:
	var binding := str(action.get("executor_binding_id", ""))
	var base := {
		"success": true,
		"actor_id": actor.actor_id,
		"settlement_id": str(settlement.get("id", "")),
		"schedule_label": str(schedule_block.get("label", "")),
		"need_effects": _dictionary_or_empty(action.get("need_effects", {})).duplicate(true),
	}
	match binding:
		"follow_patrol_route":
			var route: Dictionary = _route_by_id(settlement, str(life.get("duty_route_id", "")))
			if route.is_empty():
				return {}
			return base.merged({
				"intent": "follow_route",
				"route_id": str(route.get("id", "")),
				"route_grids": _route_grids(route, settlement),
			}, true)
		"travel_to_anchor":
			return _travel_intent_for_action(base, life, settlement, action)
		"use_smart_object":
			return _smart_object_intent_for_action(base, life, settlement, ai_library, action)
		"idle_at_anchor":
			return _travel_intent_for_action(base, life, settlement, action)
		"resolve_alarm":
			return _alarm_intent_for_action(base, life, settlement, ai_library, action)
	return {}


func _travel_intent_for_action(base: Dictionary, life: Dictionary, settlement: Dictionary, action: Dictionary) -> Dictionary:
	var target_anchor := _target_anchor_for_action(life, settlement, action)
	if target_anchor.is_empty():
		return {}
	if str(action.get("target_anchor", "")) == "duty":
		var route: Dictionary = _route_by_id(settlement, str(life.get("duty_route_id", "")))
		if not route.is_empty():
			return base.merged({
				"intent": "follow_route",
				"route_id": str(route.get("id", "")),
				"route_grids": _route_grids(route, settlement),
			}, true)
	return base.merged({
		"intent": "return_home" if str(action.get("target_anchor", "")) == "home" else "use_smart_object",
		"anchor_id": target_anchor,
		"target_grid": _anchor_grid(settlement, target_anchor),
	}, true)


func _smart_object_intent_for_action(base: Dictionary, life: Dictionary, settlement: Dictionary, ai_library: Dictionary, action: Dictionary) -> Dictionary:
	var smart_object: Dictionary = _smart_object_for_action(life, settlement, ai_library, action)
	if smart_object.is_empty():
		return {}
	return base.merged({
		"intent": "use_smart_object",
		"smart_object_id": str(smart_object.get("id", "")),
		"smart_object_kind": str(smart_object.get("kind", "")),
		"smart_object_tags": _array_or_empty(smart_object.get("tags", [])).duplicate(true),
		"target_grid": _anchor_grid(settlement, str(smart_object.get("anchor_id", ""))),
	}, true)


func _alarm_intent_for_action(base: Dictionary, life: Dictionary, settlement: Dictionary, ai_library: Dictionary, action: Dictionary) -> Dictionary:
	var smart_object: Dictionary = _smart_object_for_kind(life, settlement, ai_library, "alarm_point", "")
	if smart_object.is_empty():
		return _travel_intent_for_action(base, life, settlement, action)
	return base.merged({
		"intent": "use_smart_object",
		"smart_object_id": str(smart_object.get("id", "")),
		"smart_object_kind": str(smart_object.get("kind", "")),
		"smart_object_tags": _array_or_empty(smart_object.get("tags", [])).duplicate(true),
		"target_grid": _anchor_grid(settlement, str(smart_object.get("anchor_id", ""))),
	}, true)


func _available_goal_ids(behavior_chain: Array[Dictionary], planner_data: Dictionary) -> Array:
	var ids: Array = []
	for behavior in behavior_chain:
		_append_unique(ids, _array_or_empty(behavior.get("goal_ids", [])))
		for group_id in _array_or_empty(behavior.get("goal_group_ids", [])):
			var group: Dictionary = _dictionary_or_empty(_dictionary_or_empty(planner_data.get("goal_groups", {})).get(str(group_id), {}))
			_append_unique(ids, _array_or_empty(group.get("goal_ids", [])))
	if ids.is_empty():
		_append_unique(ids, _dictionary_or_empty(planner_data.get("goals", {})).keys())
	return ids


func _available_action_ids(behavior_chain: Array[Dictionary], planner_data: Dictionary) -> Array:
	var ids: Array = []
	for behavior in behavior_chain:
		_append_unique(ids, _array_or_empty(behavior.get("action_ids", [])))
		for group_id in _array_or_empty(behavior.get("action_group_ids", [])):
			var group: Dictionary = _dictionary_or_empty(_dictionary_or_empty(planner_data.get("action_groups", {})).get(str(group_id), {}))
			_append_unique(ids, _array_or_empty(group.get("action_ids", [])))
	if ids.is_empty():
		_append_unique(ids, _dictionary_or_empty(planner_data.get("actions", {})).keys())
	return ids


func _active_schedule_block(profile_id: String, day: String, minute_of_day: int, ai_library: Dictionary) -> Dictionary:
	for profile in _ai_collection(ai_library, "schedule_templates"):
		var profile_data: Dictionary = _dictionary_or_empty(profile)
		if str(profile_data.get("id", "")) != profile_id:
			continue
		for block in _array_or_empty(profile_data.get("blocks", [])):
			var block_data: Dictionary = _dictionary_or_empty(block)
			if not _array_or_empty(block_data.get("days", [])).has(day):
				continue
			var start_minute: int = int(block_data.get("start_minute", 0))
			var end_minute: int = int(block_data.get("end_minute", 0))
			if _minute_in_range(minute_of_day, start_minute, end_minute):
				return block_data
	return {}


func _shift_starting_soon(profile_id: String, day: String, minute_of_day: int, ai_library: Dictionary) -> bool:
	for profile in _ai_collection(ai_library, "schedule_templates"):
		var profile_data: Dictionary = _dictionary_or_empty(profile)
		if str(profile_data.get("id", "")) != profile_id:
			continue
		for block in _array_or_empty(profile_data.get("blocks", [])):
			var block_data: Dictionary = _dictionary_or_empty(block)
			if not _array_or_empty(block_data.get("days", [])).has(day):
				continue
			var start_minute: int = int(block_data.get("start_minute", 0))
			var delta: int = posmod(start_minute - minute_of_day, 1440)
			if delta > 0 and delta <= 60:
				return true
	return false


func _first_accessible_smart_object(life: Dictionary, settlement: Dictionary, ai_library: Dictionary) -> Dictionary:
	var access_profile_id: String = str(life.get("smart_object_access_profile_id", ""))
	for profile in _ai_collection(ai_library, "smart_object_access_profiles"):
		var profile_data: Dictionary = _dictionary_or_empty(profile)
		if str(profile_data.get("id", "")) != access_profile_id:
			continue
		for rule in _array_or_empty(profile_data.get("rules", [])):
			var rule_data: Dictionary = _dictionary_or_empty(rule)
			var smart_object: Dictionary = _matching_smart_object(settlement, rule_data)
			if not smart_object.is_empty():
				return smart_object
	return {}


func _smart_object_for_action(life: Dictionary, settlement: Dictionary, ai_library: Dictionary, action: Dictionary) -> Dictionary:
	var reservation_target := str(action.get("reservation_target", ""))
	var target_anchor_kind := str(action.get("target_anchor", ""))
	var desired_kind := _reservation_target_kind(reservation_target, target_anchor_kind)
	var desired_tag := _reservation_target_tag(reservation_target, target_anchor_kind)
	if not desired_kind.is_empty():
		var smart_object: Dictionary = _smart_object_for_kind(life, settlement, ai_library, desired_kind, desired_tag)
		if not smart_object.is_empty():
			return smart_object
	return _first_accessible_smart_object(life, settlement, ai_library)


func _smart_object_for_kind(life: Dictionary, settlement: Dictionary, ai_library: Dictionary, kind: String, desired_tag: String) -> Dictionary:
	var access_profile_id: String = str(life.get("smart_object_access_profile_id", ""))
	var fallback: Dictionary = {}
	for profile in _ai_collection(ai_library, "smart_object_access_profiles"):
		var profile_data: Dictionary = _dictionary_or_empty(profile)
		if str(profile_data.get("id", "")) != access_profile_id:
			continue
		for rule in _array_or_empty(profile_data.get("rules", [])):
			var rule_data: Dictionary = _dictionary_or_empty(rule)
			if str(rule_data.get("kind", "")) != kind:
				continue
			var preferred_tags: Array = _array_or_empty(rule_data.get("preferred_tags", [])).duplicate(true)
			if not desired_tag.is_empty() and not preferred_tags.has(desired_tag):
				preferred_tags.append(desired_tag)
			var best_object: Dictionary = {}
			var best_score := 0
			for smart_object in _array_or_empty(settlement.get("smart_objects", [])):
				var object_data: Dictionary = _dictionary_or_empty(smart_object)
				if str(object_data.get("kind", "")) != kind:
					continue
				if fallback.is_empty():
					fallback = object_data
				var score := _tag_match_score(_array_or_empty(object_data.get("tags", [])), preferred_tags)
				if score > best_score:
					best_score = score
					best_object = object_data
			if not best_object.is_empty():
				return best_object
	return fallback


func _reservation_target_kind(reservation_target: String, target_anchor_kind: String) -> String:
	match reservation_target:
		"guard_post":
			return "guard_post"
		"meal_object":
			return "canteen_seat"
		"leisure_object":
			return "recreation_spot"
		"bed":
			return "bed"
		"medical_station":
			return "medical_station"
	match target_anchor_kind:
		"canteen":
			return "canteen_seat"
		"leisure":
			return "recreation_spot"
		"home":
			return "bed"
		"alarm":
			return "alarm_point"
	return ""


func _reservation_target_tag(reservation_target: String, target_anchor_kind: String) -> String:
	match reservation_target:
		"meal_object":
			return "meal"
		"leisure_object":
			return "morale"
	return target_anchor_kind


func _reservation_active(reservations: Dictionary, reservation_target: String) -> bool:
	if reservation_target.is_empty():
		return false
	var reservation: Dictionary = _dictionary_or_empty(reservations.get(reservation_target, {}))
	return not reservation.is_empty() and bool(reservation.get("active", true))


func _target_anchor_for_action(life: Dictionary, settlement: Dictionary, action: Dictionary) -> String:
	match str(action.get("target_anchor", "")):
		"home":
			return str(life.get("home_anchor", ""))
		"duty":
			return _duty_anchor_id(life, settlement)
		"canteen":
			return "canteen_main"
		"leisure":
			return "recreation_yard"
		"alarm":
			return "alarm_bell"
	return str(action.get("target_anchor", ""))


func _duty_anchor_id(life: Dictionary, settlement: Dictionary) -> String:
	var route: Dictionary = _route_by_id(settlement, str(life.get("duty_route_id", "")))
	var anchors: Array = _array_or_empty(route.get("anchors", []))
	if not anchors.is_empty():
		return str(anchors.front())
	return ""


func _current_anchor_id(actor: RefCounted, settlement: Dictionary) -> String:
	if actor == null:
		return ""
	for anchor in _array_or_empty(settlement.get("anchors", [])):
		var anchor_data: Dictionary = _dictionary_or_empty(anchor)
		if actor.grid_position.key() == _grid_key(_dictionary_or_empty(anchor_data.get("grid", {}))):
			return str(anchor_data.get("id", ""))
	return ""


func _meal_window_open(settlement: Dictionary, minute_of_day: int) -> bool:
	var service_rules: Dictionary = _dictionary_or_empty(settlement.get("service_rules", {}))
	for window in _array_or_empty(service_rules.get("meal_windows", [])):
		var window_data: Dictionary = _dictionary_or_empty(window)
		if _minute_in_range(minute_of_day, int(window_data.get("start_minute", 0)), int(window_data.get("end_minute", 0))):
			return true
	return false


func _matching_smart_object(settlement: Dictionary, rule: Dictionary) -> Dictionary:
	var required_kind: String = str(rule.get("kind", ""))
	var preferred_tags: Array = _array_or_empty(rule.get("preferred_tags", []))
	var fallback_to_any: bool = bool(rule.get("fallback_to_any", false))
	var fallback: Dictionary = {}
	for smart_object in _array_or_empty(settlement.get("smart_objects", [])):
		var object_data: Dictionary = _dictionary_or_empty(smart_object)
		if not required_kind.is_empty() and str(object_data.get("kind", "")) != required_kind:
			continue
		if fallback.is_empty():
			fallback = object_data
		if _tags_match(_array_or_empty(object_data.get("tags", [])), preferred_tags):
			return object_data
	return fallback if fallback_to_any else {}


func _tags_match(tags: Array, preferred_tags: Array) -> bool:
	if preferred_tags.is_empty():
		return true
	for tag in preferred_tags:
		if tags.has(str(tag)):
			return true
	return false


func _tag_match_score(tags: Array, preferred_tags: Array) -> int:
	if preferred_tags.is_empty():
		return 1
	var score := 0
	for tag in preferred_tags:
		if tags.has(str(tag)):
			score += 1
	return score


func _route_by_id(settlement: Dictionary, route_id: String) -> Dictionary:
	for route in _array_or_empty(settlement.get("routes", [])):
		var route_data: Dictionary = _dictionary_or_empty(route)
		if str(route_data.get("id", "")) == route_id:
			return route_data
	return {}


func _route_grids(route: Dictionary, settlement: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for anchor_id in _array_or_empty(route.get("anchors", [])):
		output.append(_anchor_grid(settlement, str(anchor_id)))
	return output


func _anchor_grid(settlement: Dictionary, anchor_id: String) -> Dictionary:
	for anchor in _array_or_empty(settlement.get("anchors", [])):
		var anchor_data: Dictionary = _dictionary_or_empty(anchor)
		if str(anchor_data.get("id", "")) == anchor_id:
			return _dictionary_or_empty(anchor_data.get("grid", {})).duplicate(true)
	return {}


func _settlement_data(settlement_id: String, settlement_library: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(settlement_library.get(settlement_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _profile_by_id(ai_library: Dictionary, collection_name: String, profile_id: String) -> Dictionary:
	for profile in _ai_collection(ai_library, collection_name):
		var profile_data: Dictionary = _dictionary_or_empty(profile)
		if str(profile_data.get("id", "")) == profile_id:
			return profile_data
	return {}


func _behavior_chain(behavior_id: String, ai_library: Dictionary) -> Array[Dictionary]:
	var by_id: Dictionary = {}
	for record in ai_library.values():
		var data: Dictionary = _record_data(record)
		if data.has("included_behavior_ids") or data.has("action_group_ids") or data.has("goal_group_ids"):
			var id := str(data.get("id", ""))
			if not id.is_empty():
				by_id[id] = data
	var output: Array[Dictionary] = []
	_append_behavior_chain(output, behavior_id, by_id)
	return output


func _append_behavior_chain(output: Array[Dictionary], behavior_id: String, by_id: Dictionary) -> void:
	if behavior_id.is_empty():
		return
	var behavior: Dictionary = _dictionary_or_empty(by_id.get(behavior_id, {}))
	if behavior.is_empty():
		return
	for included_id in _array_or_empty(behavior.get("included_behavior_ids", [])):
		_append_behavior_chain(output, str(included_id), by_id)
	output.append(behavior)


func _record_data(record: Variant) -> Dictionary:
	var record_data: Dictionary = _dictionary_or_empty(record)
	return _dictionary_or_empty(record_data.get("data", record_data))


func _ai_collection(ai_library: Dictionary, collection_name: String) -> Array:
	for record in ai_library.values():
		var data: Dictionary = _record_data(record)
		if data.has(collection_name):
			return _array_or_empty(data.get(collection_name, []))
	return []


func _minute_in_range(minute: int, start_minute: int, end_minute: int) -> bool:
	if start_minute <= end_minute:
		return minute >= start_minute and minute < end_minute
	return minute >= start_minute or minute < end_minute


func _condition_matches(condition: Dictionary, state: Dictionary, facts: Dictionary) -> bool:
	if condition.is_empty():
		return true
	match str(condition.get("kind", "")):
		"number_compare":
			var left := float(state.get(str(condition.get("key", "")), 0.0))
			var right := float(condition.get("value", 0.0))
			match str(condition.get("op", "")):
				"less_than_or_equal":
					return left <= right
				"less_than":
					return left < right
				"greater_than_or_equal":
					return left >= right
				"greater_than":
					return left > right
				"equals":
					return is_equal_approx(left, right)
			return false
		"bool_equals":
			return bool(state.get(str(condition.get("key", "")), false)) == bool(condition.get("value", false))
		"text_key_equals":
			return str(state.get(str(condition.get("left_key", "")), "")) == str(state.get(str(condition.get("right_key", "")), ""))
		"fact_true":
			return bool(facts.get(str(condition.get("fact_id", "")), false))
		"role_is":
			return str(state.get("role", "")) == str(condition.get("role", ""))
		"all_of":
			for child in _array_or_empty(condition.get("conditions", [])):
				if not _condition_matches(_dictionary_or_empty(child), state, facts):
					return false
			return true
		"any_of":
			for child in _array_or_empty(condition.get("conditions", [])):
				if _condition_matches(_dictionary_or_empty(child), state, facts):
					return true
			return false
		"not":
			return not _condition_matches(_dictionary_or_empty(condition.get("condition", {})), state, facts)
	return false


func _assignments_satisfied(assignments: Array, state: Dictionary) -> bool:
	for assignment in assignments:
		var assignment_data: Dictionary = _dictionary_or_empty(assignment)
		var key := str(assignment_data.get("key", ""))
		if key.is_empty():
			continue
		if bool(state.get(key, false)) != bool(assignment_data.get("value", false)):
			return false
	return true


func _unmet_assignments(assignments: Array, state: Dictionary) -> Array:
	var output: Array = []
	for assignment in assignments:
		var assignment_data: Dictionary = _dictionary_or_empty(assignment)
		var key := str(assignment_data.get("key", ""))
		if key.is_empty():
			continue
		if not state.has(key) or bool(state.get(key, false)) != bool(assignment_data.get("value", false)):
			output.append(assignment_data.duplicate(true))
	return output


func _effect_match_count(effects: Array, requirements: Array) -> int:
	var count := 0
	for requirement in requirements:
		var requirement_data: Dictionary = _dictionary_or_empty(requirement)
		for effect in effects:
			var effect_data: Dictionary = _dictionary_or_empty(effect)
			if str(effect_data.get("key", "")) == str(requirement_data.get("key", "")) and bool(effect_data.get("value", false)) == bool(requirement_data.get("value", false)):
				count += 1
				break
	return count


func _append_unique(target: Array, values: Array) -> void:
	for value in values:
		var text := str(value)
		if not text.is_empty() and not target.has(text):
			target.append(text)


func _need_current(needs: Dictionary, need_id: String) -> float:
	var need: Dictionary = _dictionary_or_empty(needs.get(need_id, {}))
	var max_value := float(need.get("max", 100.0))
	return clampf(float(need.get("current", max_value)), 0.0, max(1.0, max_value))


func _life_role(life: Dictionary) -> String:
	var behavior_id := str(life.get("ai_behavior_profile_id", ""))
	if behavior_id.ends_with("_settlement"):
		return behavior_id.trim_suffix("_settlement")
	return behavior_id


func _grid_key(grid: Dictionary) -> String:
	return "%d:%d:%d" % [int(grid.get("x", 0)), int(grid.get("y", 0)), int(grid.get("z", 0))]


func _idle_intent(actor: RefCounted, reason: String) -> Dictionary:
	return {
		"success": true,
		"actor_id": actor.actor_id if actor != null else 0,
		"intent": "idle",
		"reason": reason,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
