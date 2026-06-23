extends RefCounted

## 聚落生活「规划」层：预约/抢占、背景生活推进、生活状态、planner 运行时、路线跟随与 smart object。
## 无状态规则计算；权威 actor.life 状态由 simulation 持有，所有读写经 simulation 转发。

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")


func expire_life_planner_reservations(simulation: RefCounted) -> Array[Dictionary]:
	var expired: Array[Dictionary] = []
	for actor in simulation.actor_registry.actors():
		if actor.hp <= 0.0:
			continue
		var life: Dictionary = simulation._dictionary_or_empty(actor.life)
		if str(life.get("settlement_id", "")).is_empty():
			continue
		var runtime: Dictionary = simulation._ensure_life_runtime(actor)
		var reservations: Dictionary = simulation._dictionary_or_empty(runtime.get("reservations", {}))
		if reservations.is_empty():
			continue
		var planner_state: Dictionary = simulation._dictionary_or_empty(runtime.get("planner_state", {})).duplicate(true)
		var changed := false
		for reservation_target in reservations.keys():
			var target := str(reservation_target)
			var reservation: Dictionary = simulation._dictionary_or_empty(reservations.get(reservation_target, {}))
			if not simulation._life_planner_reservation_expired(reservation):
				continue
			if simulation._life_background_action_holds_reservation(runtime, target, reservation):
				continue
			var release: Dictionary = simulation._release_life_planner_reservation(actor, runtime, planner_state, target, {
				"action_id": str(reservation.get("action_id", "")),
			}, {
				"smart_object_id": str(reservation.get("smart_object_id", "")),
				"smart_object_kind": str(reservation.get("smart_object_kind", "")),
				"target_grid": simulation._dictionary_or_empty(reservation.get("target_grid", {})).duplicate(true),
			}, {
				"smart_object_id": str(reservation.get("smart_object_id", "")),
				"smart_object_kind": str(reservation.get("smart_object_kind", "")),
				"target_grid": simulation._dictionary_or_empty(reservation.get("target_grid", {})).duplicate(true),
			}, "reservation_expired")
			expired.append(release.duplicate(true))
			changed = true
		if changed:
			runtime["planner_state"] = planner_state
			simulation._set_life_runtime(actor, runtime)
	return expired


func life_planner_reservation_expired(simulation: RefCounted, reservation: Dictionary) -> bool:
	if reservation.is_empty() or not bool(reservation.get("active", false)):
		return false
	var ttl_minutes := int(reservation.get("reservation_ttl_minutes", 0))
	var created_total_minutes := int(reservation.get("created_total_minutes", -1))
	if ttl_minutes <= 0 or created_total_minutes < 0:
		return false
	return simulation._world_time_elapsed_minutes(created_total_minutes, simulation._world_time_total_minutes(simulation.world_time)) >= ttl_minutes


func life_background_action_holds_reservation(simulation: RefCounted, runtime: Dictionary, reservation_target: String, reservation: Dictionary) -> bool:
	var action: Dictionary = simulation._dictionary_or_empty(runtime.get("background_action", {}))
	if action.is_empty() or bool(action.get("completed", false)):
		return false
	if int(action.get("remaining_minutes", 0)) <= 0:
		return false
	if str(action.get("reservation_target", "")) != reservation_target:
		return false
	var reserved_smart_object_id := str(reservation.get("smart_object_id", ""))
	var action_smart_object_id := str(action.get("smart_object_id", ""))
	if not reserved_smart_object_id.is_empty() and not action_smart_object_id.is_empty() and reserved_smart_object_id != action_smart_object_id:
		return false
	return true


func life_need_tick_for_actor(_simulation: RefCounted, ticks: Array[Dictionary], actor_id: int) -> Dictionary:
	for tick in ticks:
		var tick_data: Dictionary = tick
		if int(tick_data.get("actor_id", 0)) == actor_id:
			return tick_data.duplicate(true)
	return {}


func tick_background_settlement_life(simulation: RefCounted, life_tick_results: Array[Dictionary], minutes: int, expired_reservations: Array[Dictionary] = []) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var expired_actor_ids: Dictionary = simulation._life_reservation_actor_id_set(expired_reservations)
	for actor in simulation.actor_registry.actors():
		if actor.kind == "player" or actor.hp <= 0.0:
			continue
		if actor.map_id.is_empty() or actor.map_id == simulation.active_map_id:
			continue
		var life: Dictionary = simulation._dictionary_or_empty(actor.life)
		if str(life.get("settlement_id", "")).is_empty():
			continue
		var need_tick: Dictionary = simulation._life_need_tick_for_actor(life_tick_results, actor.actor_id)
		var background_action: Dictionary = simulation._background_life_idle_result(actor, {}, "background_life_reservation_expired") if expired_actor_ids.has(actor.actor_id) else simulation._advance_background_settlement_life(actor, minutes)
		var presence: Dictionary = simulation._record_life_presence(actor, "background", minutes, need_tick, background_action)
		output.append(presence)
		simulation._emit("settlement_life_background_ticked", presence.duplicate(true))
	return output


func sync_online_life_background_action(simulation: RefCounted, actor: RefCounted) -> Dictionary:
	if actor == null or actor.hp <= 0.0:
		return {}
	if actor.map_id.is_empty() or actor.map_id != simulation.active_map_id:
		return {}
	var life: Dictionary = simulation._dictionary_or_empty(actor.life)
	if str(life.get("settlement_id", "")).is_empty():
		return {}
	var runtime: Dictionary = simulation._ensure_life_runtime(actor)
	var background_action: Dictionary = simulation._dictionary_or_empty(runtime.get("background_action", {}))
	if background_action.is_empty() or bool(background_action.get("completed", false)):
		return {}
	var previous_presence: Dictionary = simulation._dictionary_or_empty(runtime.get("presence", {}))
	var resync := {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"settlement_id": str(life.get("settlement_id", "")),
		"reason": "actor_became_online",
		"from_mode": str(previous_presence.get("mode", "background")),
		"to_mode": "online",
		"actor_map_id": actor.map_id,
		"active_map_id": simulation.active_map_id,
		"world_time": simulation.world_time.duplicate(true),
		"background_action": simulation._background_life_action_summary(background_action),
	}
	runtime.erase("background_action")
	runtime["last_background_resync"] = resync.duplicate(true)
	simulation._set_life_runtime(actor, runtime)
	simulation._emit("settlement_life_background_resynced", resync.duplicate(true))
	return resync


func record_life_presence(simulation: RefCounted, actor: RefCounted, mode: String, minutes: int, need_tick: Dictionary = {}, background_action: Dictionary = {}) -> Dictionary:
	var life: Dictionary = simulation._dictionary_or_empty(actor.life)
	var presence: Dictionary = {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"settlement_id": str(life.get("settlement_id", "")),
		"mode": mode,
		"actor_map_id": actor.map_id,
		"active_map_id": simulation.active_map_id,
		"world_time": simulation.world_time.duplicate(true),
		"minutes": max(0, minutes),
		"has_need_tick": not need_tick.is_empty(),
	}
	if not need_tick.is_empty():
		presence["last_need_tick"] = need_tick.duplicate(true)
	if not background_action.is_empty():
		presence["background_action"] = simulation._background_life_action_summary(background_action)
	var runtime: Dictionary = simulation._ensure_life_runtime(actor)
	var status: Dictionary = {}
	if mode == "background":
		status = simulation._record_life_status(actor, simulation._life_status_from_background_action(actor, background_action, presence))
	else:
		status = simulation._dictionary_or_empty(runtime.get("status", {})).duplicate(true)
		if status.is_empty() or str(status.get("mode", "")) != mode:
			status = simulation._record_life_status(actor, simulation._life_status_base(actor, "idle", "idle", "idle", "待命", presence, {}))
	if not status.is_empty():
		presence["status"] = status.duplicate(true)
	runtime = simulation._ensure_life_runtime(actor)
	runtime["presence"] = presence.duplicate(true)
	simulation._set_life_runtime(actor, runtime)
	return presence


func life_reservation_actor_id_set(simulation: RefCounted, reservations: Array[Dictionary]) -> Dictionary:
	var output: Dictionary = {}
	for reservation in reservations:
		var data: Dictionary = simulation._dictionary_or_empty(reservation)
		var actor_id := int(data.get("actor_id", 0))
		if actor_id > 0:
			output[actor_id] = true
	return output


func record_life_status(simulation: RefCounted, actor: RefCounted, status: Dictionary) -> Dictionary:
	if actor == null or status.is_empty():
		return {}
	var runtime: Dictionary = simulation._ensure_life_runtime(actor)
	var previous: Dictionary = simulation._dictionary_or_empty(runtime.get("status", {}))
	var output: Dictionary = status.duplicate(true)
	output["previous_state_id"] = str(previous.get("state_id", ""))
	output["changed"] = simulation._life_status_changed(previous, output)
	runtime["status"] = output.duplicate(true)
	simulation._set_life_runtime(actor, runtime)
	if bool(output.get("changed", false)):
		simulation._emit("settlement_life_status_changed", output.duplicate(true))
	return output


func life_status_changed(_simulation: RefCounted, previous: Dictionary, status: Dictionary) -> bool:
	if previous.is_empty():
		return true
	for key in ["state_id", "state_group", "activity_id", "mode", "planner_action_id", "smart_object_id", "route_id"]:
		if str(previous.get(key, "")) != str(status.get(key, "")):
			return true
	return false


func life_status_from_background_action(simulation: RefCounted, actor: RefCounted, action: Dictionary, presence: Dictionary) -> Dictionary:
	if action.is_empty():
		return simulation._life_status_base(actor, "background_idle", "idle", "background_idle", "后台待命", presence, {})
	var status: Dictionary = simulation._life_status_from_life_result(actor, simulation._dictionary_or_empty(action.get("life_intent", {})), action, "background")
	status["mode"] = "background"
	status["elapsed_minutes"] = int(action.get("elapsed_minutes", 0))
	status["remaining_minutes"] = int(action.get("remaining_minutes", 0))
	status["action_duration_minutes"] = int(action.get("action_duration_minutes", 0))
	status["completed"] = bool(action.get("completed", false))
	status["world_time"] = simulation._dictionary_or_empty(presence.get("world_time", simulation.world_time)).duplicate(true)
	return status


func life_status_from_life_result(simulation: RefCounted, actor: RefCounted, intent: Dictionary, result: Dictionary, mode: String) -> Dictionary:
	var planner: Dictionary = simulation._dictionary_or_empty(intent.get("planner", {}))
	var planner_action_id := str(intent.get("planner_action_id", planner.get("action_id", result.get("planner_action_id", ""))))
	var status_id: String = simulation._life_status_id(intent, result, planner_action_id)
	var group: String = simulation._life_status_group(status_id, planner_action_id)
	var activity_id := planner_action_id if not planner_action_id.is_empty() else str(result.get("intent", intent.get("intent", "idle")))
	var label: String = simulation._life_status_label(status_id, activity_id)
	var status: Dictionary = simulation._life_status_base(actor, status_id, group, activity_id, label, {
		"mode": mode,
		"world_time": simulation.world_time.duplicate(true),
	}, result)
	status["goal_id"] = str(intent.get("goal_id", planner.get("goal_id", result.get("goal_id", ""))))
	status["planner_action_id"] = planner_action_id
	status["planner_action_reason"] = str(intent.get("planner_action_reason", planner.get("action_reason", result.get("planner_action_reason", ""))))
	status["intent"] = str(result.get("intent", intent.get("intent", "")))
	status["reason"] = str(result.get("reason", ""))
	status["settlement_id"] = str(intent.get("settlement_id", status.get("settlement_id", "")))
	status["schedule_label"] = str(intent.get("schedule_label", ""))
	status["route_id"] = str(result.get("route_id", intent.get("route_id", "")))
	status["anchor_id"] = str(intent.get("anchor_id", ""))
	status["smart_object_id"] = str(result.get("smart_object_id", intent.get("smart_object_id", "")))
	status["smart_object_kind"] = str(result.get("smart_object_kind", intent.get("smart_object_kind", "")))
	status["target_grid"] = simulation._dictionary_or_empty(result.get("target_grid", intent.get("target_grid", {}))).duplicate(true)
	return status


func life_status_base(simulation: RefCounted, actor: RefCounted, state_id: String, state_group: String, activity_id: String, activity_label: String, presence: Dictionary, result: Dictionary) -> Dictionary:
	var life: Dictionary = simulation._dictionary_or_empty(actor.life)
	return {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"settlement_id": str(life.get("settlement_id", "")),
		"state_id": state_id,
		"state_group": state_group,
		"activity_id": activity_id,
		"activity_label": activity_label,
		"mode": str(presence.get("mode", "online")),
		"world_time": simulation._dictionary_or_empty(presence.get("world_time", simulation.world_time)).duplicate(true),
		"success": bool(result.get("success", true)),
	}


func life_status_id(_simulation: RefCounted, intent: Dictionary, result: Dictionary, planner_action_id: String) -> String:
	if not bool(result.get("success", true)):
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
	match str(result.get("intent", intent.get("intent", ""))):
		"follow_route":
			return "patrolling"
		"return_home":
			return "traveling"
		"use_smart_object":
			return "servicing"
	return "idle"


func life_status_group(_simulation: RefCounted, state_id: String, planner_action_id: String) -> String:
	match state_id:
		"traveling", "patrolling":
			return "work"
		"guarding", "servicing", "treating":
			return "service"
		"eating", "resting", "relaxing":
			return "rest"
		"blocked":
			return "blocked"
	if planner_action_id.is_empty():
		return "idle"
	return "work"


func life_status_label(_simulation: RefCounted, state_id: String, activity_id: String) -> String:
	match state_id:
		"traveling":
			return "前往目标"
		"patrolling":
			return "巡逻"
		"guarding":
			return "警戒"
		"servicing":
			return "服务"
		"treating":
			return "治疗"
		"eating":
			return "用餐"
		"resting":
			return "休息"
		"relaxing":
			return "放松"
		"blocked":
			return "受阻"
		"background_idle":
			return "后台待命"
	if activity_id.is_empty():
		return "待命"
	return activity_id


func advance_background_settlement_life(simulation: RefCounted, actor: RefCounted, minutes: int) -> Dictionary:
	var intent: Dictionary = simulation.decide_actor_intent(actor.actor_id, {"background_life": true})
	var intent_name := str(intent.get("intent", ""))
	if not ["follow_route", "return_home", "use_smart_object"].has(intent_name):
		return simulation._background_life_idle_result(actor, intent, "background_life_no_action")
	var background_intent: Dictionary = intent.duplicate(true)
	var target_grid: Dictionary = simulation._background_life_target_grid(actor, background_intent)
	if target_grid.is_empty():
		var failed_result: Dictionary = simulation._background_life_base_result(actor, background_intent, false, "background_life_target_missing")
		simulation._record_life_planner_runtime(actor, background_intent, failed_result)
		simulation._emit("settlement_life_background_action_failed", failed_result.duplicate(true))
		return failed_result
	background_intent["target_grid"] = target_grid.duplicate(true)
	var action_key: String = simulation._background_life_action_key(background_intent, target_grid)
	var duration_minutes: int = simulation._background_life_action_duration_minutes(background_intent)
	var planner_action: Dictionary = simulation._background_life_current_planner_action(background_intent)
	var runtime: Dictionary = simulation._ensure_life_runtime(actor)
	var previous_action: Dictionary = simulation._dictionary_or_empty(runtime.get("background_action", {}))
	var elapsed_before: int = int(previous_action.get("elapsed_minutes", 0)) if str(previous_action.get("action_key", "")) == action_key else 0
	var elapsed_after: int = elapsed_before + max(0, minutes)
	var completed: bool = duration_minutes <= 0 or elapsed_after >= duration_minutes
	var result: Dictionary = simulation._background_life_base_result(actor, background_intent, true, "background_life_action_completed" if completed else "background_life_action_progressed")
	var from_grid: Dictionary = actor.grid_position.to_dictionary()
	result["action_key"] = action_key
	result["target_grid"] = target_grid.duplicate(true)
	result["from"] = from_grid
	result["elapsed_before_minutes"] = elapsed_before
	result["elapsed_minutes"] = elapsed_after
	result["action_duration_minutes"] = duration_minutes
	result["remaining_minutes"] = max(0, duration_minutes - elapsed_after)
	result["completed"] = completed
	result["world_time"] = simulation.world_time.duplicate(true)
	result["reservation_target"] = str(planner_action.get("reservation_target", ""))
	simulation._attach_life_smart_object_summary(background_intent, result)
	if completed:
		actor.grid_position = GridCoord.from_dictionary(target_grid)
		result["to"] = actor.grid_position.to_dictionary()
		result["remaining_steps"] = 0
		simulation._apply_life_arrival_effect(actor, background_intent, result)
		simulation._record_life_planner_runtime(actor, background_intent, result)
		runtime = simulation._ensure_life_runtime(actor)
		runtime.erase("background_action")
		runtime["last_background_action"] = result.duplicate(true)
		simulation._set_life_runtime(actor, runtime)
		simulation._emit("settlement_life_background_action_completed", result.duplicate(true))
	else:
		result["to"] = from_grid
		result["remaining_steps"] = 1
		simulation._record_life_planner_runtime(actor, background_intent, result)
		runtime = simulation._ensure_life_runtime(actor)
		runtime["background_action"] = simulation._background_life_action_summary(result)
		simulation._set_life_runtime(actor, runtime)
		simulation._emit("settlement_life_background_action_progressed", result.duplicate(true))
	return result


func background_life_idle_result(simulation: RefCounted, actor: RefCounted, intent: Dictionary, reason: String) -> Dictionary:
	return simulation._background_life_base_result(actor, intent, true, reason)


func background_life_base_result(simulation: RefCounted, actor: RefCounted, intent: Dictionary, success: bool, reason: String) -> Dictionary:
	var planner: Dictionary = simulation._dictionary_or_empty(intent.get("planner", {}))
	return {
		"success": success,
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"intent": str(intent.get("intent", "idle")),
		"reason": reason,
		"life_intent": intent.duplicate(true),
		"goal_id": str(intent.get("goal_id", planner.get("goal_id", ""))),
		"planner_action_id": str(intent.get("planner_action_id", planner.get("action_id", ""))),
		"planner_action_reason": str(intent.get("planner_action_reason", planner.get("action_reason", ""))),
	}


func background_life_target_grid(simulation: RefCounted, actor: RefCounted, intent: Dictionary) -> Dictionary:
	if str(intent.get("intent", "")) == "follow_route":
		var route_grids: Array = simulation._array_or_empty(intent.get("route_grids", []))
		if route_grids.is_empty():
			return {}
		return simulation._next_life_route_grid(actor, route_grids)
	return simulation._dictionary_or_empty(intent.get("target_grid", {})).duplicate(true)


func background_life_action_duration_minutes(simulation: RefCounted, intent: Dictionary) -> int:
	var action: Dictionary = simulation._background_life_current_planner_action(intent)
	if not action.is_empty():
		var travel_minutes := int(action.get("default_travel_minutes", 0))
		var perform_minutes := int(action.get("perform_minutes", 0))
		return max(travel_minutes, perform_minutes)
	match str(intent.get("intent", "")):
		"follow_route", "return_home", "use_smart_object":
			return simulation.WORLD_TURN_MINUTES
	return 0


func background_life_current_planner_action(simulation: RefCounted, intent: Dictionary) -> Dictionary:
	var planner: Dictionary = simulation._dictionary_or_empty(intent.get("planner", {}))
	var queue: Array = simulation._array_or_empty(planner.get("action_queue", []))
	var current_index: int = int(planner.get("current_action_index", 0))
	if current_index < 0 or current_index >= queue.size():
		return {}
	return simulation._dictionary_or_empty(queue[current_index]).duplicate(true)


func background_life_action_key(simulation: RefCounted, intent: Dictionary, target_grid: Dictionary) -> String:
	var planner: Dictionary = simulation._dictionary_or_empty(intent.get("planner", {}))
	var parts: Array[String] = [
		str(intent.get("intent", "")),
		str(intent.get("goal_id", planner.get("goal_id", ""))),
		str(intent.get("planner_action_id", planner.get("action_id", ""))),
		str(planner.get("current_action_index", 0)),
		str(intent.get("route_id", "")),
		str(intent.get("smart_object_id", "")),
		JSON.stringify(target_grid),
	]
	return "|".join(parts)


func background_life_action_summary(simulation: RefCounted, result: Dictionary) -> Dictionary:
	return {
		"actor_id": int(result.get("actor_id", 0)),
		"definition_id": str(result.get("definition_id", "")),
		"intent": str(result.get("intent", "")),
		"reason": str(result.get("reason", "")),
		"success": bool(result.get("success", false)),
		"completed": bool(result.get("completed", false)),
		"goal_id": str(result.get("goal_id", "")),
		"planner_action_id": str(result.get("planner_action_id", "")),
		"planner_action_reason": str(result.get("planner_action_reason", "")),
		"action_key": str(result.get("action_key", "")),
		"elapsed_minutes": int(result.get("elapsed_minutes", 0)),
		"action_duration_minutes": int(result.get("action_duration_minutes", 0)),
		"remaining_minutes": int(result.get("remaining_minutes", 0)),
		"reservation_target": str(result.get("reservation_target", "")),
		"target_grid": simulation._dictionary_or_empty(result.get("target_grid", {})).duplicate(true),
		"from": simulation._dictionary_or_empty(result.get("from", {})).duplicate(true),
		"to": simulation._dictionary_or_empty(result.get("to", {})).duplicate(true),
		"smart_object_id": str(result.get("smart_object_id", "")),
		"smart_object_kind": str(result.get("smart_object_kind", "")),
		"world_time": simulation._dictionary_or_empty(result.get("world_time", {})).duplicate(true),
	}


func advance_npc_life_action(simulation: RefCounted, actor: RefCounted, intent: Dictionary, topology: Dictionary) -> Dictionary:
	if actor.ap < 1.0:
		var wait_result: Dictionary = simulation._npc_wait_for_ap(actor, 0, str(intent.get("intent", "life")), "ap_insufficient_npc_life_move", 1.0)
		wait_result["life_intent"] = intent.duplicate(true)
		simulation._record_life_planner_runtime(actor, intent, wait_result)
		return wait_result
	var result: Dictionary = {}
	match str(intent.get("intent", "")):
		"follow_route":
			result = simulation._npc_follow_route(actor, intent, topology)
		"return_home":
			result = simulation._npc_move_to_life_target(actor, simulation._dictionary_or_empty(intent.get("target_grid", {})), topology, intent, "return_home", "life_return_home")
		"use_smart_object":
			result = simulation._npc_move_to_life_target(actor, simulation._dictionary_or_empty(intent.get("target_grid", {})), topology, intent, "use_smart_object", "life_use_smart_object")
	if result.is_empty():
		result = {
			"success": true,
			"actor_id": actor.actor_id,
			"intent": "idle",
			"reason": "life_intent_unhandled",
			"life_intent": intent.duplicate(true),
		}
	simulation._record_life_planner_runtime(actor, intent, result)
	var status: Dictionary = simulation._record_life_status(actor, simulation._life_status_from_life_result(actor, intent, result, "online"))
	if not status.is_empty():
		result["life_status"] = status.duplicate(true)
	return result


func record_life_planner_runtime(simulation: RefCounted, actor: RefCounted, intent: Dictionary, result: Dictionary) -> void:
	var planner: Dictionary = simulation._dictionary_or_empty(intent.get("planner", {}))
	if planner.is_empty():
		return
	var runtime: Dictionary = simulation._ensure_life_runtime(actor)
	var execution: Dictionary = {
		"world_time": simulation.world_time.duplicate(true),
		"goal_id": str(planner.get("goal_id", "")),
		"action_id": str(planner.get("action_id", "")),
		"intent": str(intent.get("intent", "")),
		"result_intent": str(result.get("intent", "")),
		"success": bool(result.get("success", false)),
		"reason": str(result.get("reason", "")),
		"remaining_steps": int(result.get("remaining_steps", 0)),
		"target_grid": simulation._dictionary_or_empty(result.get("target_grid", intent.get("target_grid", {}))).duplicate(true),
		"smart_object_id": str(result.get("smart_object_id", intent.get("smart_object_id", ""))),
		"route_id": str(result.get("route_id", intent.get("route_id", ""))),
	}
	var queue: Array = simulation._array_or_empty(planner.get("action_queue", [])).duplicate(true)
	var current_index: int = clampi(int(planner.get("current_action_index", 0)), 0, max(0, queue.size()))
	var completed_current_action: bool = simulation._life_planner_action_completed(result)
	var replan_request: Dictionary = simulation._life_planner_replan_request(actor, planner, result, current_index)
	var completed_action: Dictionary = simulation._dictionary_or_empty(queue[current_index]) if current_index >= 0 and current_index < queue.size() else {}
	var planner_state: Dictionary = simulation._dictionary_or_empty(runtime.get("planner_state", {})).duplicate(true)
	var applied_effects: Array = []
	var applied_world_state_effects: Array = []
	var applied_executor_side_effects: Array = []
	var reservation_result: Dictionary = {}
	if completed_current_action:
		applied_effects = simulation._apply_life_planner_action_effects(planner_state, simulation._array_or_empty(completed_action.get("effects", [])))
		applied_world_state_effects = simulation._apply_life_planner_world_state_effects(actor, completed_action)
		applied_executor_side_effects = simulation._apply_life_planner_executor_side_effects(actor, completed_action, intent, result)
	var next_index: int = current_index + 1 if completed_current_action else current_index
	next_index = clampi(next_index, 0, queue.size())
	var queue_complete: bool = not queue.is_empty() and next_index >= queue.size()
	if completed_current_action:
		reservation_result = simulation._record_life_planner_reservation_step(actor, runtime, planner_state, completed_action, intent, result, queue_complete)
	execution["applied_effects"] = applied_effects.duplicate(true)
	execution["applied_world_state_effects"] = applied_world_state_effects.duplicate(true)
	execution["applied_executor_side_effects"] = applied_executor_side_effects.duplicate(true)
	if not reservation_result.is_empty():
		execution["reservation"] = reservation_result.duplicate(true)
	var planner_runtime: Dictionary = {
		"goal_id": str(planner.get("goal_id", "")),
		"goal_score": float(planner.get("goal_score", 0.0)),
		"score_rule_ids": simulation._array_or_empty(planner.get("score_rule_ids", [])).duplicate(true),
		"action_id": str(planner.get("action_id", "")),
		"action_reason": str(planner.get("action_reason", "")),
		"action_queue": queue,
		"queue_length": queue.size(),
		"current_action_index": next_index,
		"completed_action_index": current_index if completed_current_action else -1,
		"completed_action_id": str(planner.get("action_id", "")) if completed_current_action else "",
		"next_action_id": simulation._life_planner_queue_action_id(queue, next_index),
		"queue_remaining": max(0, queue.size() - next_index),
		"queue_complete": queue_complete,
		"requirements": simulation._array_or_empty(planner.get("requirements", [])).duplicate(true),
		"unmet_requirements": simulation._array_or_empty(planner.get("unmet_requirements", [])).duplicate(true),
		"facts": simulation._dictionary_or_empty(planner.get("facts", {})).duplicate(true),
		"role": str(planner.get("role", "")),
		"last_execution": execution,
	}
	if not replan_request.is_empty():
		planner_runtime["replan_requested"] = true
		planner_runtime["replan_request"] = replan_request.duplicate(true)
		execution["replan_requested"] = true
		execution["replan_request"] = replan_request.duplicate(true)
	runtime["planner_state"] = planner_state
	runtime["planner"] = planner_runtime
	simulation._set_life_runtime(actor, runtime)
	if not replan_request.is_empty():
		simulation._emit("settlement_life_planner_replan_requested", replan_request.duplicate(true))
	simulation._emit("settlement_life_planner_updated", {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"planner": planner_runtime.duplicate(true),
	})


func life_planner_action_completed(_simulation: RefCounted, result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		return false
	var intent_name := str(result.get("intent", ""))
	if not ["follow_route", "return_home", "use_smart_object"].has(intent_name):
		return false
	if str(result.get("reason", "")) == "already_at_life_target":
		return true
	if result.has("remaining_steps"):
		return int(result.get("remaining_steps", 0)) <= 0
	return false


func life_planner_replan_request(simulation: RefCounted, actor: RefCounted, planner: Dictionary, result: Dictionary, current_index: int) -> Dictionary:
	if bool(result.get("success", false)):
		return {}
	var action_id := str(planner.get("action_id", ""))
	if action_id.is_empty():
		return {}
	var intent_name := str(result.get("intent", ""))
	if not ["follow_route", "return_home", "use_smart_object"].has(intent_name):
		return {}
	return {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"goal_id": str(planner.get("goal_id", "")),
		"action_id": action_id,
		"action_index": current_index,
		"intent": intent_name,
		"reason": str(result.get("reason", "")),
		"world_time": simulation.world_time.duplicate(true),
		"target_grid": simulation._dictionary_or_empty(result.get("target_grid", {})).duplicate(true),
	}


func life_planner_queue_action_id(simulation: RefCounted, queue: Array, index: int) -> String:
	if index < 0 or index >= queue.size():
		return ""
	return str(simulation._dictionary_or_empty(queue[index]).get("action_id", ""))


func apply_life_planner_action_effects(simulation: RefCounted, planner_state: Dictionary, effects: Array) -> Array:
	var applied: Array = []
	for effect in effects:
		var effect_data: Dictionary = simulation._dictionary_or_empty(effect)
		var key := str(effect_data.get("key", ""))
		if key.is_empty():
			continue
		var value: bool = bool(effect_data.get("value", false))
		if value and simulation._life_planner_location_fact_keys().has(key):
			for sibling_key in simulation._life_planner_location_fact_keys():
				if sibling_key != key:
					planner_state[sibling_key] = false
		planner_state[key] = value
		applied.append({"key": key, "value": value})
	return applied


func apply_life_planner_world_state_effects(simulation: RefCounted, actor: RefCounted, action: Dictionary) -> Array:
	var effects: Dictionary = simulation._dictionary_or_empty(action.get("world_state_effects", {}))
	var applied: Array = []
	for key in effects.keys():
		var effect_key := str(key)
		if effect_key.is_empty():
			continue
		var flag_id := ""
		var value := bool(effects.get(key, false))
		if effect_key.begins_with("set_"):
			flag_id = effect_key.trim_prefix("set_")
		elif effect_key.begins_with("clear_"):
			flag_id = effect_key.trim_prefix("clear_")
			value = false
		if flag_id.is_empty():
			continue
		var result: Dictionary = simulation.set_world_flag(flag_id, value, "settlement_life_world_state_effect", actor.actor_id)
		var summary: Dictionary = {
			"key": effect_key,
			"flag_id": flag_id,
			"value": value,
			"changed": bool(result.get("changed", false)),
			"action_id": str(action.get("action_id", "")),
			"actor_id": actor.actor_id,
		}
		applied.append(summary)
		simulation._emit("settlement_life_world_state_effect_applied", summary.duplicate(true))
	return applied


func apply_life_planner_executor_side_effects(simulation: RefCounted, actor: RefCounted, action: Dictionary, _intent: Dictionary, result: Dictionary) -> Array:
	var action_id := str(action.get("action_id", ""))
	var executor_binding_id := str(action.get("executor_binding_id", ""))
	var applied: Array = []
	if executor_binding_id == "resolve_alarm" and action_id == "respond_alarm":
		applied.append(simulation._apply_life_executor_world_flag(actor, action_id, executor_binding_id, "world_alert_active", false, "alarm_resolved"))
	if action_id == "restock_meal_service":
		applied.append(simulation._apply_life_executor_world_flag(actor, action_id, executor_binding_id, "settlement_meal_service_restocked", true, "service_restocked"))
	elif action_id == "treat_patients":
		applied.append(simulation._apply_life_executor_world_flag(actor, action_id, executor_binding_id, "settlement_patients_treated", true, "service_completed"))
	if not applied.is_empty():
		result["life_executor_side_effects"] = applied.duplicate(true)
	return applied


func apply_life_executor_world_flag(simulation: RefCounted, actor: RefCounted, action_id: String, executor_binding_id: String, flag_id: String, value: bool, effect_kind: String) -> Dictionary:
	var flag_result: Dictionary = simulation.set_world_flag(flag_id, value, "settlement_life_executor", actor.actor_id)
	var summary: Dictionary = {
		"kind": effect_kind,
		"flag_id": flag_id,
		"value": value,
		"changed": bool(flag_result.get("changed", false)),
		"action_id": action_id,
		"executor_binding_id": executor_binding_id,
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
	}
	simulation._emit("settlement_life_executor_side_effect_applied", summary.duplicate(true))
	return summary


func record_life_planner_reservation_step(simulation: RefCounted, actor: RefCounted, runtime: Dictionary, planner_state: Dictionary, action: Dictionary, intent: Dictionary, result: Dictionary, queue_complete: bool) -> Dictionary:
	var reservation_target := str(action.get("reservation_target", ""))
	if reservation_target.is_empty():
		return {}
	if queue_complete:
		return simulation._release_life_planner_reservation(actor, runtime, planner_state, reservation_target, action, intent, result, "planner_queue_complete")
	return simulation._apply_life_planner_reservation(actor, runtime, planner_state, action, intent, result)


func apply_life_planner_reservation(simulation: RefCounted, actor: RefCounted, runtime: Dictionary, planner_state: Dictionary, action: Dictionary, intent: Dictionary, result: Dictionary) -> Dictionary:
	var reservation_target := str(action.get("reservation_target", ""))
	if reservation_target.is_empty():
		return {}
	var preemption: Dictionary = simulation._apply_life_reservation_preemption(actor, reservation_target, action, intent, result)
	var ttl_minutes: int = simulation._life_planner_reservation_ttl_minutes(action)
	var reservation: Dictionary = {
		"active": true,
		"phase": "reserved",
		"reservation_target": reservation_target,
		"smart_object_id": str(result.get("smart_object_id", intent.get("smart_object_id", ""))),
		"smart_object_kind": str(result.get("smart_object_kind", intent.get("smart_object_kind", ""))),
		"action_id": str(action.get("action_id", "")),
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"world_time": simulation.world_time.duplicate(true),
		"created_total_minutes": simulation._world_time_total_minutes(simulation.world_time),
		"reservation_ttl_minutes": ttl_minutes,
		"expires_world_time": simulation._world_time_after(simulation.world_time, ttl_minutes),
		"target_grid": simulation._dictionary_or_empty(result.get("target_grid", intent.get("target_grid", {}))).duplicate(true),
		"reservation_priority": simulation._life_reservation_priority(action, intent, result),
		"reservation_preemptible": simulation._life_reservation_preemptible(action, intent, result),
	}
	if not preemption.is_empty():
		reservation["preempted_reservation"] = preemption.duplicate(true)
	var reservations: Dictionary = simulation._dictionary_or_empty(runtime.get("reservations", {})).duplicate(true)
	reservations[reservation_target] = reservation.duplicate(true)
	runtime["reservations"] = reservations
	var flag_key: String = simulation._life_reservation_flag_key(reservation_target)
	if not flag_key.is_empty():
		runtime[flag_key] = true
	planner_state["reservation.%s.active" % reservation_target] = true
	var fact_key: String = simulation._life_reservation_fact_key(reservation_target)
	if not fact_key.is_empty():
		planner_state[fact_key] = true
	simulation._emit("settlement_life_reservation_updated", reservation.duplicate(true))
	return reservation


func apply_life_reservation_preemption(simulation: RefCounted, requester: RefCounted, reservation_target: String, action: Dictionary, intent: Dictionary, result: Dictionary) -> Dictionary:
	var preemption: Dictionary = simulation._dictionary_or_empty(result.get("reservation_preemption", intent.get("reservation_preemption", {}))).duplicate(true)
	if preemption.is_empty():
		return {}
	var preempted_actor_id := int(preemption.get("actor_id", preemption.get("preempted_actor_id", 0)))
	if preempted_actor_id <= 0 or requester == null or preempted_actor_id == requester.actor_id:
		return {}
	var preempted_actor: RefCounted = simulation.actor_registry.get_actor(preempted_actor_id)
	if preempted_actor == null or preempted_actor.hp <= 0.0:
		return {}
	var preempted_runtime: Dictionary = simulation._ensure_life_runtime(preempted_actor)
	var preempted_reservations: Dictionary = simulation._dictionary_or_empty(preempted_runtime.get("reservations", {}))
	var preempted_target := str(preemption.get("reservation_target", reservation_target))
	var existing: Dictionary = simulation._dictionary_or_empty(preempted_reservations.get(preempted_target, {}))
	if existing.is_empty() or not bool(existing.get("active", false)):
		return {}
	var planner_state: Dictionary = simulation._dictionary_or_empty(preempted_runtime.get("planner_state", {})).duplicate(true)
	var release: Dictionary = simulation._release_life_planner_reservation(preempted_actor, preempted_runtime, planner_state, preempted_target, {
		"action_id": str(existing.get("action_id", "")),
	}, {
		"smart_object_id": str(existing.get("smart_object_id", "")),
		"smart_object_kind": str(existing.get("smart_object_kind", "")),
		"target_grid": simulation._dictionary_or_empty(existing.get("target_grid", {})).duplicate(true),
	}, {
		"smart_object_id": str(existing.get("smart_object_id", "")),
		"smart_object_kind": str(existing.get("smart_object_kind", "")),
		"target_grid": simulation._dictionary_or_empty(existing.get("target_grid", {})).duplicate(true),
	}, "reservation_preempted")
	var planner_runtime: Dictionary = simulation._dictionary_or_empty(preempted_runtime.get("planner", {})).duplicate(true)
	var replan_request := {
		"actor_id": preempted_actor.actor_id,
		"definition_id": preempted_actor.definition_id,
		"goal_id": str(planner_runtime.get("goal_id", "")),
		"action_id": str(planner_runtime.get("action_id", existing.get("action_id", ""))),
		"intent": "reservation",
		"reason": "reservation_preempted",
		"world_time": simulation.world_time.duplicate(true),
		"reservation_target": preempted_target,
		"smart_object_id": str(existing.get("smart_object_id", "")),
		"preempted_by_actor_id": requester.actor_id,
		"preempted_by_definition_id": requester.definition_id,
		"requester_action_id": str(action.get("action_id", intent.get("planner_action_id", ""))),
		"request_priority": simulation._life_reservation_priority(action, intent, result),
		"preempted_priority": float(existing.get("reservation_priority", preemption.get("preempted_priority", 0.0))),
	}
	planner_runtime["replan_requested"] = true
	planner_runtime["replan_request"] = replan_request.duplicate(true)
	preempted_runtime["planner"] = planner_runtime
	preempted_runtime["planner_state"] = planner_state
	simulation._set_life_runtime(preempted_actor, preempted_runtime)
	simulation._emit("settlement_life_planner_replan_requested", replan_request.duplicate(true))
	var event := release.duplicate(true)
	event["preempted_by_actor_id"] = requester.actor_id
	event["preempted_by_definition_id"] = requester.definition_id
	event["requester_action_id"] = str(action.get("action_id", intent.get("planner_action_id", "")))
	event["request_priority"] = simulation._life_reservation_priority(action, intent, result)
	event["preempted_priority"] = float(existing.get("reservation_priority", preemption.get("preempted_priority", 0.0)))
	simulation._emit("settlement_life_reservation_preempted", event.duplicate(true))
	return event


func life_reservation_priority(_simulation: RefCounted, action: Dictionary, intent: Dictionary, result: Dictionary = {}) -> float:
	if result.has("reservation_priority"):
		return float(result.get("reservation_priority", 0.0))
	if intent.has("reservation_priority"):
		return float(intent.get("reservation_priority", 0.0))
	return float(action.get("reservation_priority", 0.0))


func life_reservation_preemptible(_simulation: RefCounted, action: Dictionary, intent: Dictionary, result: Dictionary = {}) -> bool:
	if result.has("reservation_preemptible"):
		return bool(result.get("reservation_preemptible", true))
	if intent.has("reservation_preemptible"):
		return bool(intent.get("reservation_preemptible", true))
	return bool(action.get("reservation_preemptible", true))


func release_life_planner_reservation(simulation: RefCounted, actor: RefCounted, runtime: Dictionary, planner_state: Dictionary, reservation_target: String, action: Dictionary, intent: Dictionary, result: Dictionary, reason: String) -> Dictionary:
	var reservations: Dictionary = simulation._dictionary_or_empty(runtime.get("reservations", {})).duplicate(true)
	var existing: Dictionary = simulation._dictionary_or_empty(reservations.get(reservation_target, {})).duplicate(true)
	var reservation: Dictionary = existing.duplicate(true)
	reservation["active"] = false
	reservation["phase"] = "released"
	reservation["release_reason"] = reason
	reservation["reservation_target"] = reservation_target
	reservation["action_id"] = str(action.get("action_id", ""))
	reservation["actor_id"] = actor.actor_id
	reservation["definition_id"] = actor.definition_id
	reservation["released_world_time"] = simulation.world_time.duplicate(true)
	if reservation.get("smart_object_id", "") == "":
		reservation["smart_object_id"] = str(result.get("smart_object_id", intent.get("smart_object_id", "")))
	if reservation.get("smart_object_kind", "") == "":
		reservation["smart_object_kind"] = str(result.get("smart_object_kind", intent.get("smart_object_kind", "")))
	reservation["target_grid"] = simulation._dictionary_or_empty(result.get("target_grid", intent.get("target_grid", {}))).duplicate(true)
	reservations[reservation_target] = reservation.duplicate(true)
	runtime["reservations"] = reservations
	var flag_key: String = simulation._life_reservation_flag_key(reservation_target)
	if not flag_key.is_empty():
		runtime[flag_key] = false
	planner_state["reservation.%s.active" % reservation_target] = false
	var fact_key: String = simulation._life_reservation_fact_key(reservation_target)
	if not fact_key.is_empty():
		planner_state[fact_key] = false
	simulation._emit("settlement_life_reservation_released", reservation.duplicate(true))
	return reservation


func life_planner_reservation_ttl_minutes(simulation: RefCounted, action: Dictionary) -> int:
	var explicit_ttl := int(action.get("reservation_ttl_minutes", 0))
	if explicit_ttl > 0:
		return max(simulation.LIFE_RESERVATION_MIN_TTL_MINUTES, explicit_ttl)
	var action_minutes: int = max(int(action.get("perform_minutes", 0)), int(action.get("default_travel_minutes", 0)))
	return max(simulation.LIFE_RESERVATION_MIN_TTL_MINUTES, action_minutes)


func life_reservation_flag_key(_simulation: RefCounted, reservation_target: String) -> String:
	match reservation_target:
		"bed":
			return "bed_reserved"
		"meal_object":
			return "meal_object_reserved"
		"guard_post":
			return "guard_post_reserved"
		"medical_station":
			return "medical_station_reserved"
		"leisure_object":
			return "leisure_object_reserved"
	return ""


func life_reservation_fact_key(_simulation: RefCounted, reservation_target: String) -> String:
	match reservation_target:
		"bed":
			return "has_reserved_bed"
		"meal_object":
			return "has_reserved_meal_seat"
		"guard_post":
			return "has_reserved_guard_post"
		"medical_station":
			return "has_reserved_medical_station"
		"leisure_object":
			return "has_reserved_leisure_object"
	return ""


func life_planner_location_fact_keys(_simulation: RefCounted) -> Array[String]:
	return ["at_home", "at_duty_area", "at_canteen", "at_leisure"]


func npc_follow_route(simulation: RefCounted, actor: RefCounted, intent: Dictionary, topology: Dictionary) -> Dictionary:
	var route_grids: Array = simulation._array_or_empty(intent.get("route_grids", []))
	if route_grids.is_empty():
		return {
			"success": false,
			"actor_id": actor.actor_id,
			"intent": "follow_route",
			"reason": "life_route_empty",
			"life_intent": intent.duplicate(true),
		}
	var target_grid: Dictionary = simulation._next_life_route_grid(actor, route_grids)
	return simulation._npc_move_to_life_target(actor, target_grid, topology, intent, "follow_route", "life_follow_route")


func next_life_route_grid(simulation: RefCounted, actor: RefCounted, route_grids: Array) -> Dictionary:
	var nearest_index: int = 0
	var nearest_distance: int = 999999
	for index in range(route_grids.size()):
		var grid: Dictionary = simulation._dictionary_or_empty(route_grids[index])
		var distance: int = simulation._grid_distance(actor.grid_position, GridCoord.from_dictionary(grid))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
		if actor.grid_position.key() == GridCoord.from_dictionary(grid).key():
			var next_index := (index + 1) % route_grids.size()
			return simulation._dictionary_or_empty(route_grids[next_index]).duplicate(true)
	return simulation._dictionary_or_empty(route_grids[nearest_index]).duplicate(true)


func npc_move_to_life_target(simulation: RefCounted, actor: RefCounted, target_grid: Dictionary, topology: Dictionary, intent: Dictionary, intent_name: String, move_reason: String) -> Dictionary:
	if topology.is_empty():
		return {"success": false, "reason": "npc_topology_missing", "actor_id": actor.actor_id, "intent": intent_name, "life_intent": intent.duplicate(true)}
	if target_grid.is_empty():
		return {"success": false, "reason": "life_target_missing", "actor_id": actor.actor_id, "intent": intent_name, "life_intent": intent.duplicate(true)}
	var target_coord: RefCounted = GridCoord.from_dictionary(target_grid)
	var movement_topology: Dictionary = simulation._topology_with_auto_open_doors(actor.actor_id, topology)
	var candidates: Array[RefCounted] = [target_coord]
	if simulation._occupied_actor_cells(actor.actor_id).has(target_coord.key()):
		candidates.append_array(simulation._adjacent_goals(target_coord))
	var attempted_goals: Array[Dictionary] = []
	var best_plan: Dictionary = simulation._pathfinder.find_path_to_any(actor.grid_position, candidates, movement_topology, simulation._occupied_actor_cells(actor.actor_id))
	var chosen_goal_data: Dictionary = simulation._dictionary_or_empty(best_plan.get("chosen_goal", {}))
	attempted_goals.append(simulation._npc_approach_attempt_summary(GridCoord.from_dictionary(chosen_goal_data) if not chosen_goal_data.is_empty() else null, best_plan))
	if not bool(best_plan.get("success", false)):
		return {
			"success": false,
			"actor_id": actor.actor_id,
			"intent": intent_name,
			"reason": "life_target_unreachable",
			"target_grid": target_grid.duplicate(true),
			"attempted_goals": attempted_goals,
			"attempted_goal_count": attempted_goals.size(),
			"life_intent": intent.duplicate(true),
		}
	var best_goal: RefCounted = GridCoord.from_dictionary(simulation._dictionary_or_empty(best_plan.get("chosen_goal", {})))
	var path: Array = simulation._array_or_empty(best_plan.get("path", []))
	if path.size() <= 1:
		var already_result := {
			"success": true,
			"actor_id": actor.actor_id,
			"intent": intent_name,
			"reason": "already_at_life_target",
			"target_grid": target_grid.duplicate(true),
			"chosen_goal": best_goal.to_dictionary(),
			"attempted_goals": attempted_goals,
			"path": path.duplicate(true),
			"path_length": path.size(),
			"life_intent": intent.duplicate(true),
		}
		simulation._apply_life_arrival_effect(actor, intent, already_result)
		return already_result
	var next_step: Dictionary = simulation._dictionary_or_empty(path[1])
	var from: Dictionary = actor.grid_position.to_dictionary()
	simulation._auto_open_door_for_step(actor.actor_id, next_step, topology)
	actor.grid_position = GridCoord.from_dictionary(next_step)
	simulation._spend_ap(actor, min(actor.ap, 1.0), move_reason)
	simulation._emit("movement_step", {
		"actor_id": actor.actor_id,
		"from": from,
		"to": next_step,
		"life_intent": intent_name,
	})
	simulation._emit("actor_moved", {
		"actor_id": actor.actor_id,
		"from": from,
		"to": next_step,
		"steps": 1,
		"life_intent": intent_name,
	})
	var move_result := {
		"success": true,
		"actor_id": actor.actor_id,
		"intent": intent_name,
		"reason": move_reason,
		"from": from,
		"to": next_step,
		"target_grid": target_grid.duplicate(true),
		"chosen_goal": best_goal.to_dictionary(),
		"attempted_goals": attempted_goals,
		"path": path.duplicate(true),
		"path_length": path.size(),
		"remaining_steps": max(0, int(best_plan.get("steps", 0)) - 1),
		"life_intent": intent.duplicate(true),
	}
	simulation._attach_life_smart_object_summary(intent, move_result)
	if actor.grid_position.key() == target_coord.key():
		simulation._apply_life_arrival_effect(actor, intent, move_result)
	return move_result


func attach_life_smart_object_summary(simulation: RefCounted, intent: Dictionary, result: Dictionary) -> void:
	if str(intent.get("intent", "")) != "use_smart_object":
		return
	result["smart_object_id"] = str(intent.get("smart_object_id", ""))
	result["smart_object_kind"] = str(intent.get("smart_object_kind", ""))
	result["smart_object_tags"] = simulation._array_or_empty(intent.get("smart_object_tags", [])).duplicate(true)
	if intent.has("reservation_priority"):
		result["reservation_priority"] = float(intent.get("reservation_priority", 0.0))
	if intent.has("reservation_preemptible"):
		result["reservation_preemptible"] = bool(intent.get("reservation_preemptible", true))
	var preemption: Dictionary = simulation._dictionary_or_empty(intent.get("reservation_preemption", {}))
	if not preemption.is_empty():
		result["reservation_preemption"] = preemption.duplicate(true)


func apply_life_arrival_effect(simulation: RefCounted, actor: RefCounted, intent: Dictionary, result: Dictionary) -> void:
	if str(intent.get("intent", "")) != "use_smart_object":
		return
	var smart_object_id := str(intent.get("smart_object_id", ""))
	var smart_object_kind := str(intent.get("smart_object_kind", ""))
	var deltas: Dictionary = simulation._dictionary_or_empty(intent.get("need_effects", {})).duplicate(true)
	if deltas.is_empty():
		deltas = simulation._smart_object_need_deltas(smart_object_kind, simulation._array_or_empty(intent.get("smart_object_tags", [])))
	var need_change: Dictionary = simulation._apply_life_need_delta(actor, deltas, "smart_object", smart_object_id)
	result["smart_object_id"] = smart_object_id
	result["smart_object_kind"] = smart_object_kind
	result["smart_object_tags"] = simulation._array_or_empty(intent.get("smart_object_tags", [])).duplicate(true)
	if intent.has("reservation_priority"):
		result["reservation_priority"] = float(intent.get("reservation_priority", 0.0))
	if intent.has("reservation_preemptible"):
		result["reservation_preemptible"] = bool(intent.get("reservation_preemptible", true))
	var preemption: Dictionary = simulation._dictionary_or_empty(intent.get("reservation_preemption", {}))
	if not preemption.is_empty():
		result["reservation_preemption"] = preemption.duplicate(true)
	result["life_need_change"] = need_change
	simulation._emit("settlement_life_smart_object_used", {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"settlement_id": str(intent.get("settlement_id", "")),
		"smart_object_id": smart_object_id,
		"smart_object_kind": smart_object_kind,
		"smart_object_tags": simulation._array_or_empty(intent.get("smart_object_tags", [])).duplicate(true),
		"target_grid": simulation._dictionary_or_empty(intent.get("target_grid", {})).duplicate(true),
		"need_change": need_change,
	})


func smart_object_need_deltas(_simulation: RefCounted, kind: String, tags: Array) -> Dictionary:
	match kind:
		"bed":
			return {"energy_delta": 20.0, "morale_delta": 4.0}
		"canteen_seat":
			return {"hunger_delta": 28.0, "morale_delta": 3.0}
		"recreation_spot":
			return {"morale_delta": 20.0}
		"medical_station":
			return {"morale_delta": 8.0}
		"guard_post":
			return {"morale_delta": 2.0}
		"alarm_point":
			return {"morale_delta": -2.0}
	if tags.has("meal"):
		return {"hunger_delta": 20.0}
	if tags.has("morale"):
		return {"morale_delta": 15.0}
	return {}
