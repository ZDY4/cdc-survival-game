extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


func _init() -> void:
	var registry := ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		for error in load_result.errors:
			printerr(error)
		quit(1)
		return

	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var simulation: RefCounted = runtime_result.get("simulation")
	var errors: Array[String] = _run_checks(simulation, registry)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("ai_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null:
		return ["player actor missing"]

	var player_grid: RefCounted = player.grid_position
	var zombie_id: int = _register_character(simulation, registry, "zombie_walker", GridCoord.new(player_grid.x + 4, player_grid.y, player_grid.z))
	var approach: Dictionary = simulation.decide_actor_intent(zombie_id, {
		"topology": _topology(simulation, registry),
		"active_map_id": simulation.active_map_id,
	})
	if approach.get("intent", "") != "approach":
		errors.append("zombie should approach player inside aggro range")
	if int(approach.get("target_actor_id", 0)) <= 0:
		errors.append("zombie approach should select a hostile target")
	if str(approach.get("reason", "")) != "target_in_aggro_range" or float(approach.get("aggro_range", 0.0)) <= 0.0:
		errors.append("zombie approach intent should expose debug reason and aggro range")
	_expect_hostile_los_blocked_intent(errors, simulation, registry, zombie_id, player_grid)

	var zombie: RefCounted = simulation.actor_registry.get_actor(zombie_id)
	zombie.grid_position = GridCoord.new(player_grid.x + 1, player_grid.y, player_grid.z)
	var attack: Dictionary = simulation.decide_actor_intent(zombie_id, {
		"topology": _topology(simulation, registry),
		"active_map_id": simulation.active_map_id,
	})
	if attack.get("intent", "") != "attack":
		errors.append("zombie should attack inside attack range")
	if str(attack.get("reason", "")) != "target_in_attack_range" or _dictionary_or_empty(attack.get("target_grid", {})).is_empty():
		errors.append("zombie attack intent should expose debug reason and target grid")
	_expect_target_tracking_and_loss(errors, simulation, registry, zombie_id, player_grid)

	var wait_result: Dictionary = simulation.submit_player_command({"kind": "wait", "topology": _topology(simulation, registry)})
	if not bool(wait_result.get("success", false)):
		errors.append("player wait command should advance world turn")
	if not _npc_results_include_attack(_array_or_empty(wait_result.get("npc_results", [])), zombie_id):
		errors.append("adjacent hostile should attack during world turn after wait")
	if _event_count(simulation.snapshot(), "attack_resolved") <= 0:
		errors.append("adjacent hostile attack should emit attack_resolved even when armor blocks damage")
	simulation.set_relationship_score(player.actor_id, zombie_id, 25.0, "ai_smoke_pacified")
	var pacified: Dictionary = simulation.decide_actor_intent(zombie_id, {
		"topology": _topology(simulation, registry),
		"active_map_id": simulation.active_map_id,
	})
	if pacified.get("intent", "") != "idle" or pacified.get("reason", "") != "no_target_in_aggro_range":
		errors.append("positive relationship should stop hostile AI targeting player, got %s/%s" % [pacified.get("intent", ""), pacified.get("reason", "")])
	simulation.set_relationship_score(player.actor_id, zombie_id, -100.0, "ai_smoke_restore_hostile")

	_expect_hostile_weapon_and_reload_intents(errors, simulation, registry, player_grid)
	errors.append_array(_expect_npc_waits_when_ap_insufficient(registry))
	errors.append_array(_expect_hostile_auto_open_door(registry))

	zombie.grid_position = GridCoord.new(player_grid.x + 20, player_grid.y, player_grid.z)
	var idle: Dictionary = simulation.decide_actor_intent(zombie_id)
	if idle.get("intent", "") != "idle" or idle.get("reason", "") != "no_target_in_aggro_range":
		errors.append("zombie should idle outside aggro range")

	var guard_id: int = _register_character(simulation, registry, "survivor_outpost_01_guard_liu", GridCoord.new(24, 0, 35))
	var context: Dictionary = {
		"day": "monday",
		"minute_of_day": 540,
		"ai": registry.get_library("ai"),
		"settlements": registry.get_library("settlements"),
	}
	var duty: Dictionary = simulation.decide_actor_intent(guard_id, context)
	if duty.get("intent", "") != "follow_route":
		errors.append("guard should follow patrol route during shift")
	if duty.get("route_id", "") != "guard_patrol_main":
		errors.append("guard duty route should use life.duty_route_id")
	if _array_or_empty(duty.get("route_grids", [])).size() != 4:
		errors.append("guard route should resolve four anchor grids")

	context["minute_of_day"] = 1200
	var home: Dictionary = simulation.decide_actor_intent(guard_id, context)
	if home.get("intent", "") != "return_home":
		errors.append("guard should return home outside shift")
	if home.get("anchor_id", "") != "guard_bed_01":
		errors.append("guard return home should use life.home_anchor")

	var restored: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	restored.load_snapshot(simulation.snapshot())
	if JSON.stringify(restored.snapshot().get("ai_intents", [])) != JSON.stringify(simulation.snapshot().get("ai_intents", [])):
		errors.append("ai intents should roundtrip through simulation snapshot")
	if _event_count(simulation.snapshot(), "ai_intent_decided") < 5:
		errors.append("AI intent decisions should emit events")
	return errors


func _expect_hostile_los_blocked_intent(errors: Array[String], simulation: RefCounted, registry: RefCounted, zombie_id: int, player_grid: RefCounted) -> void:
	var zombie: RefCounted = simulation.actor_registry.get_actor(zombie_id)
	if zombie == null:
		errors.append("LOS blocked AI smoke missing zombie")
		return
	var original_grid: RefCounted = zombie.grid_position
	zombie.grid_position = GridCoord.new(player_grid.x + 2, player_grid.y, player_grid.z + 2)
	var blocked_topology := _los_blocked_topology(player_grid, GridCoord.new(player_grid.x + 1, player_grid.y, player_grid.z + 1))
	var blocked: Dictionary = simulation.decide_actor_intent(zombie_id, {
		"topology": blocked_topology,
		"active_map_id": simulation.active_map_id,
	})
	if blocked.get("intent", "") != "idle" or blocked.get("reason", "") != "target_blocked_by_los":
		errors.append("hostile AI should idle when only target is blocked by LOS, got %s/%s" % [blocked.get("intent", ""), blocked.get("reason", "")])
	if int(blocked.get("blocked_by_los_count", 0)) <= 0:
		errors.append("blocked LOS intent should expose blocked_by_los_count")
	var before_events: int = _event_count(simulation.snapshot(), "attack_resolved")
	var wait_result: Dictionary = simulation.submit_player_command({"kind": "wait", "topology": blocked_topology})
	if not bool(wait_result.get("success", false)):
		errors.append("blocked LOS wait command should still succeed")
	if _npc_results_include_attack(_array_or_empty(wait_result.get("npc_results", [])), zombie_id):
		errors.append("blocked LOS hostile should not attack during world turn")
	if _event_count(simulation.snapshot(), "attack_resolved") != before_events:
		errors.append("blocked LOS hostile should not emit attack_resolved")
	zombie.grid_position = original_grid


func _expect_target_tracking_and_loss(errors: Array[String], simulation: RefCounted, registry: RefCounted, zombie_id: int, player_grid: RefCounted) -> void:
	var zombie: RefCounted = simulation.actor_registry.get_actor(zombie_id)
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if zombie == null or player == null:
		errors.append("target tracking smoke missing actor")
		return
	var original_player_grid: RefCounted = player.grid_position
	var original_zombie_grid: RefCounted = zombie.grid_position
	zombie.grid_position = GridCoord.new(player_grid.x + 3, player_grid.y, player_grid.z)
	var acquired: Dictionary = simulation.decide_actor_intent(zombie_id, {
		"topology": _topology(simulation, registry),
		"active_map_id": simulation.active_map_id,
	})
	if str(acquired.get("target_tracking_state", "")) != "acquired" and str(acquired.get("target_tracking_state", "")) != "tracking":
		errors.append("hostile target memory should acquire target, got %s" % acquired)
	player.grid_position = GridCoord.new(player_grid.x + 40, player_grid.y, player_grid.z)
	var lost: Dictionary = simulation.decide_actor_intent(zombie_id, {
		"topology": _topology(simulation, registry),
		"active_map_id": simulation.active_map_id,
	})
	if not bool(lost.get("target_lost", false)) or str(lost.get("target_tracking_state", "")) != "lost":
		errors.append("hostile target memory should report target lost, got %s" % lost)
	if str(lost.get("target_lost_reason", "")) != "no_target_in_aggro_range":
		errors.append("lost target should expose no_target_in_aggro_range reason")
	if int(lost.get("previous_target_actor_id", 0)) != player.actor_id:
		errors.append("lost target should preserve previous target actor id")
	var event_payload: Dictionary = _last_event_payload(simulation.snapshot(), "ai_intent_decided")
	if not bool(event_payload.get("target_lost", false)) or str(event_payload.get("target_tracking_state", "")) != "lost":
		errors.append("ai_intent_decided should expose target lost payload, got %s" % event_payload)
	player.grid_position = original_player_grid
	zombie.grid_position = original_zombie_grid


func _expect_hostile_weapon_and_reload_intents(errors: Array[String], simulation: RefCounted, registry: RefCounted, player_grid: RefCounted) -> void:
	var ranged_ai := {"aggro_range": 20.0, "attack_range": 1.2}

	var pistol_simulation: RefCounted = _isolated_ai_simulation(registry, player_grid)
	var pistol_player: RefCounted = pistol_simulation.actor_registry.get_actor(1)
	var pistol_topology: Dictionary = _topology(pistol_simulation, registry)
	var pistol_id: int = _register_character(pistol_simulation, registry, "zombie_walker", GridCoord.new(pistol_player.grid_position.x + 4, pistol_player.grid_position.y, pistol_player.grid_position.z + 1), {
		"ai": ranged_ai,
		"equipment": {"main_hand": "1004"},
		"weapon_ammo": {"main_hand": 1},
		"inventory": {"1009": 2},
	})
	var pistol_intent: Dictionary = pistol_simulation.decide_actor_intent(pistol_id, {
		"topology": pistol_topology,
		"active_map_id": pistol_simulation.active_map_id,
	})
	if pistol_intent.get("intent", "") != "attack":
		errors.append("armed hostile should attack inside weapon range, got %s/%s" % [pistol_intent.get("intent", ""), pistol_intent.get("reason", "")])
	if int(pistol_intent.get("attack_range", 0)) < 8 or str(pistol_intent.get("weapon_item_id", "")) != "1004":
		errors.append("armed hostile intent should use equipped weapon range and expose weapon item id")
	var attack_events_before: int = _event_count(pistol_simulation.snapshot(), "attack_resolved")
	var attack_result: Dictionary = pistol_simulation.submit_player_command({"kind": "wait", "topology": pistol_topology})
	if not _npc_results_include_attack(_array_or_empty(attack_result.get("npc_results", [])), pistol_id):
		errors.append("armed hostile should attack during world turn from weapon range")
	var pistol: RefCounted = pistol_simulation.actor_registry.get_actor(pistol_id)
	if pistol == null or int(pistol.weapon_ammo.get("main_hand", 0)) != 0:
		errors.append("armed hostile attack should consume loaded magazine ammo")
	if _event_count(pistol_simulation.snapshot(), "attack_resolved") <= attack_events_before:
		errors.append("armed hostile attack should emit attack_resolved")

	var min_range_simulation: RefCounted = _isolated_ai_simulation(registry, player_grid)
	var min_range_player: RefCounted = min_range_simulation.actor_registry.get_actor(1)
	var min_range_topology: Dictionary = _topology(min_range_simulation, registry)
	var min_range_id: int = _register_character(min_range_simulation, registry, "zombie_walker", GridCoord.new(min_range_player.grid_position.x + 1, min_range_player.grid_position.y, min_range_player.grid_position.z + 1), {
		"ai": ranged_ai,
	})
	var min_range_intent: Dictionary = min_range_simulation.decide_actor_intent(min_range_id, {
		"topology": min_range_topology,
		"active_map_id": min_range_simulation.active_map_id,
		"weapon_profile": {
			"item_id": "synthetic_min_range_weapon",
			"range": 6,
			"attack_range": 6,
			"min_range": 2,
			"ammo_ready": true,
		},
	})
	if min_range_intent.get("intent", "") == "attack" or min_range_intent.get("reason", "") != "target_inside_min_range":
		errors.append("hostile inside weapon minimum range should avoid attack, got %s/%s" % [min_range_intent.get("intent", ""), min_range_intent.get("reason", "")])
	if int(min_range_intent.get("min_range", 0)) != 2:
		errors.append("minimum-range hostile intent should expose min_range")

	var reload_simulation: RefCounted = _isolated_ai_simulation(registry, player_grid)
	var reload_player: RefCounted = reload_simulation.actor_registry.get_actor(1)
	var reload_topology: Dictionary = _topology(reload_simulation, registry)
	var reload_id: int = _register_character(reload_simulation, registry, "zombie_walker", GridCoord.new(reload_player.grid_position.x + 4, reload_player.grid_position.y, reload_player.grid_position.z + 2), {
		"ai": ranged_ai,
		"equipment": {"main_hand": "1004"},
		"weapon_ammo": {"main_hand": 0},
		"inventory": {"1009": 2},
	})
	var reload_intent: Dictionary = reload_simulation.decide_actor_intent(reload_id, {
		"topology": reload_topology,
		"active_map_id": reload_simulation.active_map_id,
	})
	if reload_intent.get("intent", "") != "reload" or reload_intent.get("reason", "") != "weapon_magazine_empty":
		errors.append("empty magazine hostile should reload before attacking")
	var reload_result: Dictionary = reload_simulation.submit_player_command({"kind": "wait", "topology": reload_topology})
	if not _npc_results_include_intent(_array_or_empty(reload_result.get("npc_results", [])), reload_id, "reload"):
		errors.append("empty magazine hostile should reload during world turn")
	var reloader: RefCounted = reload_simulation.actor_registry.get_actor(reload_id)
	if reloader == null or int(reloader.weapon_ammo.get("main_hand", 0)) <= 0 or int(reloader.inventory.get("1009", 0)) >= 2:
		errors.append("hostile reload should move ammo from inventory into magazine")

	var dry_simulation: RefCounted = _isolated_ai_simulation(registry, player_grid)
	var dry_player: RefCounted = dry_simulation.actor_registry.get_actor(1)
	var dry_topology: Dictionary = _topology(dry_simulation, registry)
	var dry_id: int = _register_character(dry_simulation, registry, "zombie_walker", GridCoord.new(dry_player.grid_position.x + 4, dry_player.grid_position.y, dry_player.grid_position.z + 3), {
		"ai": ranged_ai,
		"equipment": {"main_hand": "1004"},
		"weapon_ammo": {"main_hand": 0},
		"inventory": {},
	})
	var dry_intent: Dictionary = dry_simulation.decide_actor_intent(dry_id, {
		"topology": dry_topology,
		"active_map_id": dry_simulation.active_map_id,
	})
	if dry_intent.get("intent", "") != "idle" or dry_intent.get("reason", "") != "weapon_ammo_unavailable":
		errors.append("hostile with empty magazine and no ammo should idle with weapon_ammo_unavailable, got %s/%s" % [dry_intent.get("intent", ""), dry_intent.get("reason", "")])


func _expect_npc_waits_when_ap_insufficient(registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var attack_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var attack_player: RefCounted = attack_simulation.actor_registry.get_actor(1)
	attack_player.grid_position = GridCoord.new(0, 0, 0)
	_move_non_player_actors_out_of_test_lane(attack_simulation)
	var attack_zombie_id: int = _register_character(attack_simulation, registry, "zombie_walker", GridCoord.new(1, 0, 0), {
		"ai": {"aggro_range": 10.0, "attack_range": 1.0},
		"combat_attributes": {
			"turn_ap_gain": 0.5,
			"turn_ap_max": 0.5,
			"affordable_ap_threshold": 1.0,
		},
	})
	var attack_results: Array = attack_simulation.advance_world_turn(_line_test_topology(2))
	var attack_wait: Dictionary = _npc_result_for_actor(attack_results, attack_zombie_id)
	if str(attack_wait.get("intent", "")) != "wait" or str(attack_wait.get("planned_intent", "")) != "attack":
		errors.append("AP-short hostile attack should wait, got %s" % attack_wait)
	if str(attack_wait.get("reason", "")) != "ap_insufficient_npc_attack":
		errors.append("AP-short hostile attack wait should expose stable reason")
	if str(attack_wait.get("turn_close_reason", "")) != "npc_turn_waiting_for_ap":
		errors.append("AP-short hostile attack wait should close turn as waiting_for_ap")
	if float(attack_wait.get("required_ap", 0.0)) <= float(attack_wait.get("available_ap", 0.0)):
		errors.append("AP-short hostile attack wait should expose required/available AP")
	if _event_count(attack_simulation.snapshot(), "attack_resolved") > 0:
		errors.append("AP-short hostile attack should not emit attack_resolved")
	if _event_count(attack_simulation.snapshot(), "actor_waited") <= 0:
		errors.append("AP-short hostile attack should emit actor_waited")

	var reload_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var reload_player: RefCounted = reload_simulation.actor_registry.get_actor(1)
	reload_player.grid_position = GridCoord.new(0, 0, 0)
	_move_non_player_actors_out_of_test_lane(reload_simulation)
	var reload_zombie_id: int = _register_character(reload_simulation, registry, "zombie_walker", GridCoord.new(4, 0, 0), {
		"ai": {"aggro_range": 10.0, "attack_range": 1.0},
		"equipment": {"main_hand": "1004"},
		"weapon_ammo": {"main_hand": 0},
		"inventory": {"1009": 2},
		"combat_attributes": {
			"turn_ap_gain": 0.5,
			"turn_ap_max": 0.5,
			"affordable_ap_threshold": 1.0,
		},
	})
	var reload_results: Array = reload_simulation.advance_world_turn(_line_test_topology(5))
	var reload_wait: Dictionary = _npc_result_for_actor(reload_results, reload_zombie_id)
	if str(reload_wait.get("intent", "")) != "wait" or str(reload_wait.get("planned_intent", "")) != "reload":
		errors.append("AP-short hostile reload should wait, got %s" % reload_wait)
	if str(reload_wait.get("reason", "")) != "ap_insufficient_npc_reload":
		errors.append("AP-short hostile reload wait should expose stable reason")
	if str(reload_wait.get("turn_close_reason", "")) != "npc_turn_waiting_for_ap":
		errors.append("AP-short hostile reload wait should close turn as waiting_for_ap")
	var reloader: RefCounted = reload_simulation.actor_registry.get_actor(reload_zombie_id)
	if reloader == null or int(reloader.weapon_ammo.get("main_hand", 0)) != 0:
		errors.append("AP-short hostile reload should not change magazine ammo")
	return errors


func _expect_hostile_auto_open_door(registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null:
		return ["AI door smoke missing player"]
	player.grid_position = GridCoord.new(3, 0, 0)
	player.ap = 0.0
	_move_non_player_actors_out_of_test_lane(simulation)
	var zombie_id: int = _register_character(simulation, registry, "zombie_walker", GridCoord.new(0, 0, 0), {
		"ai": {"aggro_range": 10.0, "attack_range": 1.0},
	})
	simulation.configure_map_interactions({
		"ai_smoke_door": _door_target("ai_smoke_door", false, false),
	})
	var result: Array = simulation.advance_world_turn(_door_test_topology(false))
	if not _npc_results_include_intent(result, zombie_id, "approach"):
		errors.append("hostile should approach through auto-opened door")
	var zombie: RefCounted = simulation.actor_registry.get_actor(zombie_id)
	if zombie == null or zombie.grid_position.x != 1:
		errors.append("hostile approach should step onto the door cell")
	var door_state: Dictionary = _dictionary_or_empty(simulation.door_states.get("ai_smoke_door", {}))
	if not bool(door_state.get("is_open", false)):
		errors.append("hostile approach should persist opened door state")
	if _event_count(simulation.snapshot(), "door_auto_opened") <= 0:
		errors.append("hostile approach should emit door_auto_opened")
	var auto_payload: Dictionary = _last_event_payload(simulation.snapshot(), "door_auto_opened")
	if int(auto_payload.get("actor_id", 0)) != zombie_id:
		errors.append("door_auto_opened should include hostile actor id")

	var locked_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var locked_player: RefCounted = locked_simulation.actor_registry.get_actor(1)
	locked_player.grid_position = GridCoord.new(3, 0, 0)
	_move_non_player_actors_out_of_test_lane(locked_simulation)
	var locked_zombie_id: int = _register_character(locked_simulation, registry, "zombie_walker", GridCoord.new(0, 0, 0), {
		"ai": {"aggro_range": 10.0, "attack_range": 1.0},
	})
	locked_simulation.configure_map_interactions({
		"ai_smoke_door": _door_target("ai_smoke_door", false, true),
	})
	var locked_result: Array = locked_simulation.advance_world_turn(_door_test_topology(true))
	var locked_npc_result: Dictionary = _npc_result_for_actor(locked_result, locked_zombie_id)
	if str(locked_npc_result.get("reason", "")) != "npc_no_adjacent_path":
		errors.append("hostile should not approach through locked door")
	if int(locked_npc_result.get("attempted_goal_count", 0)) <= 0:
		errors.append("failed hostile approach should expose attempted goal count")
	var attempts: Array = _array_or_empty(locked_npc_result.get("attempted_goals", []))
	if attempts.is_empty():
		errors.append("failed hostile approach should expose attempted path goals")
	else:
		var blocked_attempt: Dictionary = _first_attempt_with_reason(attempts, "path_unreachable")
		if blocked_attempt.is_empty():
			errors.append("failed hostile approach should include path_unreachable attempt diagnostics: %s" % attempts)
		elif int(blocked_attempt.get("visited_cell_count", 0)) <= 0 or _dictionary_or_empty(blocked_attempt.get("goal", {})).is_empty():
			errors.append("failed hostile approach attempt should expose goal and visited cell count: %s" % blocked_attempt)
	return errors


func _move_non_player_actors_out_of_test_lane(simulation: RefCounted) -> void:
	for actor in simulation.actor_registry.actors():
		if actor.actor_id == 1:
			continue
		actor.grid_position = GridCoord.new(0, 0, 10 + actor.actor_id)


func _isolated_ai_simulation(registry: RefCounted, player_grid: RefCounted) -> RefCounted:
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.grid_position = GridCoord.new(player_grid.x, player_grid.y, player_grid.z)
	_move_non_player_actors_out_of_test_lane(simulation)
	return simulation


func _door_test_topology(locked: bool) -> Dictionary:
	return {
		"bounds": {
			"min_x": 0,
			"max_x": 3,
			"min_z": 0,
			"max_z": 0,
		},
		"blocking_cells": {
			"1:0:0": "ai_smoke_door",
		},
		"sight_blocking_cells": {},
		"door_objects": [_door_summary("ai_smoke_door", false, locked)],
	}


func _line_test_topology(max_x: int) -> Dictionary:
	return {
		"bounds": {
			"min_x": 0,
			"max_x": max_x,
			"min_z": 0,
			"max_z": 0,
		},
		"blocking_cells": {},
		"sight_blocking_cells": {},
		"door_objects": [],
	}


func _door_target(target_id: String, is_open: bool, locked: bool) -> Dictionary:
	var door: Dictionary = _door_summary(target_id, is_open, locked)
	return {
		"target_id": target_id,
		"target_type": "map_object",
		"display_name": "AI 测试门",
		"kind": "door",
		"anchor": {"x": 1, "y": 0, "z": 0},
		"cells": [{"x": 1, "y": 0, "z": 0}],
		"door": door,
	}


func _door_summary(target_id: String, is_open: bool, locked: bool) -> Dictionary:
	return {
		"door_id": target_id,
		"object_id": target_id,
		"display_name": "AI 测试门",
		"anchor": {"x": 1, "y": 0, "z": 0},
		"cells": [{"x": 1, "y": 0, "z": 0}],
		"is_open": is_open,
		"locked": locked,
		"blocks_movement": not is_open,
		"blocks_sight": false,
		"blocks_sight_when_closed": false,
	}


func _register_character(simulation: RefCounted, registry: RefCounted, definition_id: String, grid: RefCounted, overrides: Dictionary = {}) -> int:
	var record: Dictionary = registry.get_library("characters").get(definition_id, {})
	var data: Dictionary = record.get("data", {})
	var identity: Dictionary = data.get("identity", {})
	var faction: Dictionary = data.get("faction", {})
	var combat: Dictionary = data.get("combat", {})
	var attributes: Dictionary = data.get("attributes", {})
	var sets: Dictionary = attributes.get("sets", {})
	var combat_attributes: Dictionary = sets.get("combat", {})
	var request := {
		"definition_id": definition_id,
		"display_name": str(identity.get("display_name", definition_id)),
		"kind": _actor_kind(str(data.get("archetype", "npc"))),
		"side": _actor_side(str(faction.get("disposition", "neutral"))),
		"group_id": str(faction.get("camp_id", "neutral")),
		"grid_position": grid,
		"max_hp": float(combat_attributes.get("max_hp", 10.0)),
		"hp": float(combat_attributes.get("max_hp", 10.0)),
		"attack_power": float(combat_attributes.get("attack_power", 1.0)),
		"defense": float(combat_attributes.get("defense", 0.0)),
		"xp_reward": int(combat.get("xp_reward", 0)),
		"ai": data.get("ai", {}),
		"life": data.get("life", {}),
	}
	for key in overrides.keys():
		request[key] = overrides[key]
	return simulation.register_actor(request)


func _actor_kind(archetype: String) -> String:
	match archetype:
		"enemy":
			return "enemy"
		"player":
			return "player"
		_:
			return "npc"


func _actor_side(disposition: String) -> String:
	match disposition:
		"hostile":
			return "hostile"
		"friendly":
			return "friendly"
		"player":
			return "player"
		_:
			return "neutral"


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _npc_results_include_attack(results: Array, actor_id: int) -> bool:
	return _npc_results_include_intent(results, actor_id, "attack")


func _npc_results_include_intent(results: Array, actor_id: int, intent: String) -> bool:
	for result in results:
		var result_data: Dictionary = _dictionary_or_empty(result)
		if int(result_data.get("actor_id", 0)) == actor_id and str(result_data.get("intent", "")) == intent:
			return true
	return false


func _npc_result_for_actor(results: Array, actor_id: int) -> Dictionary:
	for result in results:
		var result_data: Dictionary = _dictionary_or_empty(result)
		if int(result_data.get("actor_id", 0)) == actor_id:
			return result_data
	return {}


func _first_attempt_with_reason(attempts: Array, reason: String) -> Dictionary:
	for attempt in attempts:
		var attempt_data: Dictionary = _dictionary_or_empty(attempt)
		if str(attempt_data.get("reason", "")) == reason:
			return attempt_data
	return {}


func _last_event_payload(snapshot: Dictionary, kind: String) -> Dictionary:
	var events: Array = snapshot.get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if str(event_data.get("kind", "")) == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


func _digest(snapshot: Dictionary) -> Dictionary:
	return {
		"event_count": snapshot.get("events", []).size(),
		"ai_intents": snapshot.get("ai_intents", []),
	}


func _topology(simulation: RefCounted, registry: RefCounted) -> Dictionary:
	var world: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	return world.get("map", {})


func _los_blocked_topology(player_grid: RefCounted, blocker_grid: RefCounted) -> Dictionary:
	return {
		"bounds": {
			"min_x": min(player_grid.x, blocker_grid.x) - 4,
			"max_x": max(player_grid.x, blocker_grid.x) + 6,
			"min_z": min(player_grid.z, blocker_grid.z) - 4,
			"max_z": max(player_grid.z, blocker_grid.z) + 6,
		},
		"sight_blocking_cells": {
			blocker_grid.key(): true,
		},
		"blocking_cells": {},
	}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
