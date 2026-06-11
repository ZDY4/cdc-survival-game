extends RefCounted


func advance(simulation: RefCounted, topology: Dictionary = {}) -> Array[Dictionary]:
	var runtime_topology: Dictionary = simulation._topology_with_runtime_door_states(topology)
	var results: Array[Dictionary] = []
	var time_before: Dictionary = simulation.world_time.duplicate(true)
	simulation.turn_state["phase"] = "world"
	simulation._tick_hotbar_cooldowns()
	simulation._tick_actor_active_effects()
	var expired_reservations: Array[Dictionary] = simulation._expire_life_planner_reservations()
	var life_tick_results: Array[Dictionary] = simulation._tick_settlement_life_needs(simulation.WORLD_TURN_MINUTES)
	var background_life_ticks: Array[Dictionary] = simulation._tick_background_settlement_life(life_tick_results, simulation.WORLD_TURN_MINUTES, expired_reservations)
	if bool(simulation.combat_state.get("active", false)):
		simulation._refresh_combat_turn_order("world_turn_started")
	for actor in world_turn_actor_order(simulation):
		if actor.kind == "player":
			continue
		if not actor.map_id.is_empty() and actor.map_id != simulation.active_map_id:
			continue
		if actor.hp <= 0.0:
			continue
		var background_resync: Dictionary = simulation._sync_online_life_background_action(actor)
		simulation._open_turn(actor.actor_id, "npc_turn")
		var turn_open_snapshot := {
			"ap": actor.ap,
			"ap_gain": simulation._turn_ap_gain(actor),
			"ap_max": simulation._turn_ap_max(actor),
			"affordable_ap_threshold": simulation._affordable_ap_threshold(actor),
			"combat_active": bool(simulation.combat_state.get("active", false)) and actor.in_combat,
		}
		var result: Dictionary = simulation._advance_npc_turn(actor, runtime_topology, bool(turn_open_snapshot.get("combat_active", false)))
		if not background_resync.is_empty():
			result["life_background_resync"] = background_resync.duplicate(true)
		result["turn_open"] = turn_open_snapshot
		result["ap_after_action"] = actor.ap
		result["turn_close_reason"] = simulation._npc_turn_close_reason(actor, result)
		result["world_turn_minutes"] = simulation.WORLD_TURN_MINUTES
		result["world_time_before"] = time_before.duplicate(true)
		result["life_need_tick"] = simulation._life_need_tick_for_actor(life_tick_results, actor.actor_id)
		result["life_presence"] = simulation._record_life_presence(actor, "online", simulation.WORLD_TURN_MINUTES, result["life_need_tick"])
		results.append(result)
		simulation._close_turn(actor.actor_id, str(result.get("turn_close_reason", "npc_turn_complete")))
		result["turn_closed"] = true
		result["ap_after_close"] = actor.ap
		if bool(simulation.combat_state.get("active", false)):
			var visibility_result: Dictionary = simulation.update_combat_visibility_decay(runtime_topology)
			if bool(visibility_result.get("combat_exited", false)):
				break
	simulation.turn_state["round"] = int(simulation.turn_state.get("round", 1)) + 1
	if bool(simulation.combat_state.get("active", false)):
		simulation.combat_state["round"] = int(simulation.combat_state.get("round", 0)) + 1
	advance_world_time(simulation, simulation.WORLD_TURN_MINUTES)
	for result in results:
		var result_data: Dictionary = result
		result_data["world_time_after"] = simulation.world_time.duplicate(true)
	simulation.emit_event("world_time_advanced", {
		"before": time_before,
		"after": simulation.world_time.duplicate(true),
		"minutes": simulation.WORLD_TURN_MINUTES,
		"life_tick_count": life_tick_results.size(),
		"background_life_tick_count": background_life_ticks.size(),
		"expired_life_reservation_count": expired_reservations.size(),
	})
	return results


func advance_world_time(simulation: RefCounted, minutes: int) -> void:
	var current_day: String = str(simulation.world_time.get("day", "monday"))
	var current_minute: int = posmod(int(simulation.world_time.get("minute_of_day", 540)), 1440)
	var total_minutes: int = current_minute + max(0, minutes)
	var day_offset: int = int(total_minutes / 1440)
	simulation.world_time["minute_of_day"] = posmod(total_minutes, 1440)
	simulation.world_time["day"] = simulation.WORLD_DAYS[(world_day_index(simulation, current_day) + day_offset) % simulation.WORLD_DAYS.size()]


func world_day_index(simulation: RefCounted, day: String) -> int:
	var index: int = simulation.WORLD_DAYS.find(day)
	return index if index >= 0 else 0


func world_turn_actor_order(simulation: RefCounted) -> Array:
	var registry_order: Array = simulation.actor_registry.actors()
	if not bool(simulation.combat_state.get("active", false)):
		return registry_order
	var by_id: Dictionary = {}
	for actor in registry_order:
		by_id[int(actor.actor_id)] = actor
	var output: Array = []
	var seen: Dictionary = {}
	for value in _array_or_empty(simulation.combat_state.get("turn_order", [])):
		var actor_id := int(value)
		var actor: RefCounted = by_id.get(actor_id)
		if actor == null or seen.has(actor_id):
			continue
		output.append(actor)
		seen[actor_id] = true
	for actor in registry_order:
		if seen.has(int(actor.actor_id)):
			continue
		output.append(actor)
	return output


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
