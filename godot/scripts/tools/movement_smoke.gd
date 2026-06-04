extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
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
	var topology: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot()).get("map", {})
	var errors: Array[String] = _run_checks(simulation, registry, topology)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("movement_smoke passed:")
	print(JSON.stringify(_digest(simulation, registry), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted, registry: RefCounted, topology: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var start: Dictionary = player.grid_position.to_dictionary()
	var goal: Dictionary = _first_open_neighbor(player.grid_position, topology, _occupied_actor_cells(simulation, 1))
	var move_result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": goal, "topology": topology})
	if not bool(move_result.get("success", false)):
		errors.append("reachable move failed: %s" % move_result.get("reason", "unknown"))
	if int(move_result.get("steps", 0)) != 1:
		errors.append("reachable command move should take 1 step")
	if player.grid_position.key() == "%d:%d:%d" % [int(start.get("x", 0)), int(start.get("y", 0)), int(start.get("z", 0))]:
		errors.append("player grid position did not update after move")
	if _event_count(simulation.snapshot(), "actor_moved") != 1:
		errors.append("move did not emit actor_moved")
	if _event_count(simulation.snapshot(), "movement_step") != 1:
		errors.append("command move did not emit movement_step")
	var movement_step_payload: Dictionary = _last_event_payload(simulation.snapshot(), "movement_step")
	if int(movement_step_payload.get("actor_id", 0)) != 1:
		errors.append("movement_step should include actor_id")
	var movement_step_to: Dictionary = _dictionary_or_empty(movement_step_payload.get("to", {}))
	if int(movement_step_to.get("x", -1)) != int(goal.get("x", -2)) or int(movement_step_to.get("z", -1)) != int(goal.get("z", -2)):
		errors.append("movement_step should include destination grid")
	var ap_spent_payload: Dictionary = _last_event_payload(simulation.snapshot(), "ap_spent")
	if int(ap_spent_payload.get("actor_id", 0)) != 1:
		errors.append("ap_spent should include actor_id")
	if not ap_spent_payload.has("cost") or not ap_spent_payload.has("before") or not ap_spent_payload.has("after"):
		errors.append("ap_spent should include cost, before, and after")
	if str(ap_spent_payload.get("reason", "")) != "move":
		errors.append("ap_spent should include move reason")

	_expect_ap_depletion_auto_advances_turn(errors, simulation, topology)
	errors.append_array(_expect_configured_ap_rules(registry))

	var blocked_goal: Dictionary = _first_blocking_cell(topology)
	var blocked_result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": blocked_goal, "topology": topology})
	if blocked_result.get("reason", "") != "goal_blocked":
		errors.append("moving into blocking cell should report goal_blocked")
	if str(_dictionary_or_empty(blocked_result.get("blocker", {})).get("kind", "")) != "map_object":
		errors.append("blocked movement should expose map object blocker info")

	var occupied_result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": _actor_grid(simulation, 2), "topology": topology})
	if occupied_result.get("reason", "") != "goal_occupied":
		errors.append("moving into occupied actor cell should report goal_occupied")
	if int(_dictionary_or_empty(occupied_result.get("blocker", {})).get("actor_id", 0)) != 2:
		errors.append("occupied movement should expose blocking actor id")
	if int(_dictionary_or_empty(_dictionary_or_empty(occupied_result.get("ui_feedback", {})).get("blocker", {})).get("actor_id", 0)) != 2:
		errors.append("occupied movement feedback should expose blocking actor id")
	_expect_rejected_command(errors, occupied_result, "goal_occupied", "occupied movement")
	_expect_path_failure_reasons(errors, simulation, topology)
	errors.append_array(_expect_auto_open_door_movement(registry))

	player.ap = 0.0
	var queued_goal: Dictionary = _first_open_neighbor(player.grid_position, topology, _occupied_actor_cells(simulation, 1))
	var queued_result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": queued_goal, "topology": topology})
	if queued_result.get("reason", "") != "ap_insufficient_movement_queued":
		errors.append("AP shortage should queue pending movement")
	_expect_rejected_command(errors, queued_result, "ap_insufficient_movement_queued", "AP shortage movement")
	if simulation.snapshot().get("pending_movement", {}).is_empty():
		errors.append("pending movement should be exposed in snapshot")
	var queued_payload: Dictionary = _last_event_payload(simulation.snapshot(), "movement_queued")
	if int(queued_payload.get("actor_id", 0)) != 1:
		errors.append("movement_queued should include actor_id")
	if _dictionary_or_empty(queued_payload.get("target_position", {})).is_empty():
		errors.append("movement_queued should include target_position")
	if not queued_payload.has("required_ap") or not queued_payload.has("available_ap"):
		errors.append("movement_queued should include required and available AP")
	if _array_or_empty(queued_payload.get("path", [])).is_empty():
		errors.append("movement_queued should include planned path")

	var replacement_goal: Dictionary = _different_open_neighbor(player.grid_position, topology, _occupied_actor_cells(simulation, 1), queued_goal)
	var replacement_cancelled_before: int = _event_count(simulation.snapshot(), "movement_cancelled")
	var replacement_result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": replacement_goal, "topology": topology})
	if replacement_result.get("reason", "") != "ap_insufficient_movement_queued":
		errors.append("new target move should queue replacement pending movement")
	var cancelled_pending: Dictionary = _dictionary_or_empty(replacement_result.get("cancelled_pending", {}))
	if str(cancelled_pending.get("reason", "")) != "new_target_command":
		errors.append("new target command should report cancelled pending reason")
	if _dictionary_or_empty(cancelled_pending.get("movement", {})).is_empty():
		errors.append("new target command should include cancelled movement payload")
	var replacement_pending: Dictionary = _dictionary_or_empty(simulation.snapshot().get("pending_movement", {}))
	var replacement_target: Dictionary = _dictionary_or_empty(replacement_pending.get("target_position", {}))
	if int(replacement_target.get("x", -999)) != int(replacement_goal.get("x", -998)) or int(replacement_target.get("z", -999)) != int(replacement_goal.get("z", -998)):
		errors.append("new target command should replace pending movement target")
	if _event_count(simulation.snapshot(), "movement_cancelled") <= replacement_cancelled_before:
		errors.append("new target command should emit movement_cancelled")
	var pending_cancelled_payload: Dictionary = _last_event_payload(simulation.snapshot(), "pending_cancelled")
	if str(pending_cancelled_payload.get("reason", "")) != "new_target_command":
		errors.append("new target command should emit pending_cancelled with replacement reason")
	if not _recent_feedback_has(simulation.snapshot(), "pending_cancelled"):
		errors.append("new target command should expose pending_cancelled in recent feedback")

	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	var player_snapshot: Dictionary = _actor_snapshot(world_result, 1)
	var grid: Dictionary = player_snapshot.get("grid_position", {})
	if int(grid.get("x", -1)) != player.grid_position.x or int(grid.get("z", -1)) != player.grid_position.z:
		errors.append("world snapshot did not expose moved player position")
	var movement_cancelled_before: int = _event_count(simulation.snapshot(), "movement_cancelled")
	var cancel_result: Dictionary = simulation.cancel_pending("movement_smoke_cancelled")
	if not bool(cancel_result.get("had_pending", false)):
		errors.append("cancel_pending should report the queued movement")
	if not simulation.snapshot().get("pending_movement", {}).is_empty():
		errors.append("cancel_pending should clear pending movement")
	if _event_count(simulation.snapshot(), "movement_cancelled") <= movement_cancelled_before:
		errors.append("cancel_pending should emit movement_cancelled")
	return errors


func _expect_path_failure_reasons(errors: Array[String], simulation: RefCounted, topology: Dictionary) -> void:
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	var out_of_bounds_goal := {
		"x": int(bounds.get("max_x", player.grid_position.x)) + 1,
		"y": player.grid_position.y,
		"z": player.grid_position.z,
	}
	var out_of_bounds_result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": out_of_bounds_goal, "topology": topology})
	if str(out_of_bounds_result.get("reason", "")) != "goal_out_of_bounds":
		errors.append("out of bounds move should report goal_out_of_bounds")
	if _dictionary_or_empty(out_of_bounds_result.get("bounds", {})).is_empty():
		errors.append("out of bounds move should expose topology bounds")

	var different_level_goal := {
		"x": player.grid_position.x,
		"y": player.grid_position.y + 1,
		"z": player.grid_position.z,
	}
	var level_result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": different_level_goal, "topology": topology})
	if str(level_result.get("reason", "")) != "level_mismatch":
		errors.append("different level move should report level_mismatch")
	if int(level_result.get("start_level", -99)) != player.grid_position.y or int(level_result.get("goal_level", -99)) != player.grid_position.y + 1:
		errors.append("level mismatch should expose start and goal levels")

	var unreachable_topology: Dictionary = _minimal_unreachable_topology(player.grid_position)
	var unreachable_goal := {
		"x": player.grid_position.x + 1,
		"y": player.grid_position.y,
		"z": player.grid_position.z + 1,
	}
	var unreachable_result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": unreachable_goal, "topology": unreachable_topology})
	if str(unreachable_result.get("reason", "")) != "path_unreachable":
		errors.append("sealed path should report path_unreachable")
	if int(unreachable_result.get("visited_cell_count", 0)) < 1:
		errors.append("unreachable path should expose visited cell count")
	var recent_failure: Dictionary = _dictionary_or_empty(simulation.snapshot().get("recent_failure", {}))
	if str(recent_failure.get("reason", "")) != "path_unreachable":
		errors.append("recent_failure should expose latest path failure reason")
	if int(recent_failure.get("visited_cell_count", 0)) < 1:
		errors.append("recent_failure should expose latest path failure context")


func _expect_ap_depletion_auto_advances_turn(errors: Array[String], simulation: RefCounted, topology: Dictionary) -> void:
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.ap = 1.0
	var round_before: int = int(simulation.snapshot().get("turn_state", {}).get("round", 0))
	var turn_started_before: int = _event_count(simulation.snapshot(), "turn_started")
	var turn_ended_before: int = _event_count(simulation.snapshot(), "turn_ended")
	var goal: Dictionary = _first_open_neighbor(player.grid_position, topology, _occupied_actor_cells(simulation, 1))
	var result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": goal, "topology": topology})
	if not bool(result.get("success", false)):
		errors.append("AP-depleting move failed: %s" % result.get("reason", "unknown"))
	if not bool(result.get("auto_turn_advanced", false)):
		errors.append("AP-depleting move should auto advance the player turn")
	if player.ap < 1.0:
		errors.append("auto advanced player turn should reopen with affordable AP")
	if int(simulation.snapshot().get("turn_state", {}).get("round", 0)) <= round_before:
		errors.append("auto advanced turn should run a world cycle and increment round")
	if _event_count(simulation.snapshot(), "turn_ended") <= turn_ended_before:
		errors.append("auto advanced turn should emit turn_ended")
	if _event_count(simulation.snapshot(), "turn_started") <= turn_started_before:
		errors.append("auto advanced turn should emit turn_started")
	if not _has_turn_payload_for_actor(simulation.snapshot(), "turn_ended", 1):
		errors.append("turn_ended should include actor_id, AP, round, and reason")
	if not _has_turn_payload_for_actor(simulation.snapshot(), "turn_started", 1):
		errors.append("turn_started should include actor_id, AP, round, and reason")


func _expect_configured_ap_rules(registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var topology: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot()).get("map", {})
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.combat_attributes["turn_ap_gain"] = 3.0
	player.combat_attributes["turn_ap_max"] = 4.0
	player.combat_attributes["affordable_ap_threshold"] = 2.0
	player.ap = 0.0
	var wait_result: Dictionary = simulation.submit_player_command({
		"kind": "wait",
		"topology": topology,
	})
	if not bool(wait_result.get("success", false)):
		errors.append("configured AP wait should succeed: %s" % wait_result.get("reason", "unknown"))
	if absf(player.ap - 3.0) > 0.001:
		errors.append("configured turn AP gain/max should reopen player at 3 AP, got %.2f" % player.ap)
	var turn_payload: Dictionary = _last_event_payload(simulation.snapshot(), "turn_started")
	if absf(float(turn_payload.get("ap_gain", -1.0)) - 3.0) > 0.001:
		errors.append("turn_started should include configured ap_gain")
	if absf(float(turn_payload.get("ap_max", -1.0)) - 4.0) > 0.001:
		errors.append("turn_started should include configured ap_max")
	if absf(float(turn_payload.get("affordable_ap_threshold", -1.0)) - 2.0) > 0.001:
		errors.append("turn_started should include configured affordable threshold")
	var control_actor: Dictionary = _dictionary_or_empty(simulation.snapshot().get("current_control_actor", {}))
	if absf(float(control_actor.get("turn_ap_gain", -1.0)) - 3.0) > 0.001 or absf(float(control_actor.get("turn_ap_max", -1.0)) - 4.0) > 0.001:
		errors.append("runtime snapshot should expose configured AP turn parameters")
	player.ap = 2.0
	var goal: Dictionary = _first_open_neighbor(player.grid_position, topology, _occupied_actor_cells(simulation, 1))
	var move_result: Dictionary = simulation.submit_player_command({
		"kind": "move",
		"target_position": goal,
		"topology": topology,
	})
	if not bool(move_result.get("success", false)):
		errors.append("configured AP threshold move should succeed: %s" % move_result.get("reason", "unknown"))
	if not bool(move_result.get("auto_turn_advanced", false)):
		errors.append("configured affordable threshold should auto advance when AP drops below 2")
	if absf(player.ap - 4.0) > 0.001:
		errors.append("configured AP max should cap auto-opened player AP at 4, got %.2f" % player.ap)
	return errors


func _expect_auto_open_door_movement(registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.grid_position.x = 0
	player.grid_position.y = 0
	player.grid_position.z = 0
	player.ap = 5.0
	_move_non_player_actors_out_of_test_lane(simulation)
	var topology: Dictionary = _door_test_topology(false)
	simulation.configure_map_interactions({
		"movement_smoke_door": _door_target("movement_smoke_door", false, false),
	})
	var result: Dictionary = simulation.submit_player_command({
		"kind": "move",
		"target_position": {"x": 2, "y": 0, "z": 0},
		"topology": topology,
	})
	if not bool(result.get("success", false)):
		errors.append("movement through unlocked closed door should auto-open: %s" % result.get("reason", "unknown"))
	if player.grid_position.x != 2 or player.grid_position.z != 0:
		errors.append("movement through auto-opened door should reach goal")
	var door_state: Dictionary = _dictionary_or_empty(simulation.door_states.get("movement_smoke_door", {}))
	if not bool(door_state.get("is_open", false)):
		errors.append("auto-open movement should persist door open state")
	if _event_count(simulation.snapshot(), "door_toggled") <= 0:
		errors.append("auto-open movement should emit door_toggled")
	if _event_count(simulation.snapshot(), "door_auto_opened") <= 0:
		errors.append("auto-open movement should emit door_auto_opened")
	var auto_payload: Dictionary = _last_event_payload(simulation.snapshot(), "door_auto_opened")
	if str(auto_payload.get("door_id", "")) != "movement_smoke_door":
		errors.append("door_auto_opened should include door_id")

	var locked_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var locked_player: RefCounted = locked_simulation.actor_registry.get_actor(1)
	locked_player.grid_position.x = 0
	locked_player.grid_position.y = 0
	locked_player.grid_position.z = 0
	locked_player.ap = 5.0
	_move_non_player_actors_out_of_test_lane(locked_simulation)
	locked_simulation.configure_map_interactions({
		"movement_smoke_door": _door_target("movement_smoke_door", false, true),
	})
	var locked_result: Dictionary = locked_simulation.submit_player_command({
		"kind": "move",
		"target_position": {"x": 2, "y": 0, "z": 0},
		"topology": _door_test_topology(true),
	})
	if str(locked_result.get("reason", "")) != "path_unreachable":
		errors.append("movement through locked door should remain blocked")
	var keyed_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var keyed_player: RefCounted = keyed_simulation.actor_registry.get_actor(1)
	keyed_player.grid_position.x = 0
	keyed_player.grid_position.y = 0
	keyed_player.grid_position.z = 0
	keyed_player.ap = 5.0
	keyed_player.inventory["1138"] = 1
	_move_non_player_actors_out_of_test_lane(keyed_simulation)
	keyed_simulation.configure_map_interactions({
		"movement_smoke_door": _door_target("movement_smoke_door", false, true, {"required_item_ids": ["1138"]}),
	})
	var keyed_result: Dictionary = keyed_simulation.submit_player_command({
		"kind": "move",
		"target_position": {"x": 2, "y": 0, "z": 0},
		"topology": _door_test_topology(true, {"required_item_ids": ["1138"]}),
	})
	if not bool(keyed_result.get("success", false)):
		errors.append("movement through key-locked door should auto-open with key: %s" % keyed_result.get("reason", "unknown"))
	if keyed_player.grid_position.x != 2 or keyed_player.grid_position.z != 0:
		errors.append("movement through key-locked auto-opened door should reach goal")
	if not bool(_dictionary_or_empty(keyed_simulation.door_states.get("movement_smoke_door", {})).get("is_open", false)):
		errors.append("key-locked auto-open movement should persist door open state")
	var tool_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var tool_player: RefCounted = tool_simulation.actor_registry.get_actor(1)
	tool_player.grid_position.x = 0
	tool_player.grid_position.y = 0
	tool_player.grid_position.z = 0
	tool_player.ap = 5.0
	tool_player.inventory["1150"] = 1
	_move_non_player_actors_out_of_test_lane(tool_simulation)
	tool_simulation.configure_map_interactions({
		"movement_smoke_door": _door_target("movement_smoke_door", false, true, {"required_tool_ids": ["1150"]}),
	})
	var tool_result: Dictionary = tool_simulation.submit_player_command({
		"kind": "move",
		"target_position": {"x": 2, "y": 0, "z": 0},
		"topology": _door_test_topology(true, {"required_tool_ids": ["1150"]}),
	})
	if not bool(tool_result.get("success", false)):
		errors.append("movement through tool-locked door should auto-open with tool: %s" % tool_result.get("reason", "unknown"))
	return errors


func _move_non_player_actors_out_of_test_lane(simulation: RefCounted) -> void:
	for actor in simulation.actor_registry.actors():
		if actor.actor_id == 1:
			continue
		actor.grid_position.x = 0
		actor.grid_position.y = 0
		actor.grid_position.z = 9 + actor.actor_id


func _door_test_topology(locked: bool, extra_door: Dictionary = {}) -> Dictionary:
	return {
		"bounds": {
			"min_x": 0,
			"max_x": 2,
			"min_z": 0,
			"max_z": 0,
		},
		"blocking_cells": {
			"1:0:0": "movement_smoke_door",
		},
		"sight_blocking_cells": {
			"1:0:0": "movement_smoke_door",
		},
		"door_objects": [_door_summary("movement_smoke_door", false, locked, extra_door)],
	}


func _door_target(target_id: String, is_open: bool, locked: bool, extra_door: Dictionary = {}) -> Dictionary:
	var door: Dictionary = _door_summary(target_id, is_open, locked, extra_door)
	return {
		"target_id": target_id,
		"target_type": "map_object",
		"display_name": "移动测试门",
		"kind": "door",
		"anchor": {"x": 1, "y": 0, "z": 0},
		"cells": [{"x": 1, "y": 0, "z": 0}],
		"door": door,
	}


func _door_summary(target_id: String, is_open: bool, locked: bool, extra_door: Dictionary = {}) -> Dictionary:
	var door := {
		"door_id": target_id,
		"object_id": target_id,
		"display_name": "移动测试门",
		"anchor": {"x": 1, "y": 0, "z": 0},
		"cells": [{"x": 1, "y": 0, "z": 0}],
		"is_open": is_open,
		"locked": locked,
		"blocks_movement": not is_open,
		"blocks_sight": not is_open,
		"blocks_sight_when_closed": true,
	}
	for key in extra_door.keys():
		door[key] = extra_door[key]
	return door


func _minimal_unreachable_topology(coord: RefCounted) -> Dictionary:
	var east_key := "%d:%d:%d" % [coord.x + 1, coord.y, coord.z]
	var south_key := "%d:%d:%d" % [coord.x, coord.y, coord.z + 1]
	return {
		"bounds": {
			"min_x": coord.x,
			"max_x": coord.x + 1,
			"min_z": coord.z,
			"max_z": coord.z + 1,
		},
		"blocking_cells": {
			east_key: "smoke_wall_east",
			south_key: "smoke_wall_south",
		},
	}


func _first_blocking_cell(topology: Dictionary) -> Dictionary:
	var keys: Array = topology.get("blocking_cells", {}).keys()
	keys.sort()
	var parts: PackedStringArray = str(keys[0]).split(":")
	return {
		"x": int(parts[0]),
		"y": int(parts[1]),
		"z": int(parts[2]),
	}


func _actor_snapshot(world_result: Dictionary, actor_id: int) -> Dictionary:
	for actor in world_result.get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return actor_data
	return {}


func _first_open_neighbor(coord: RefCounted, topology: Dictionary, occupied: Dictionary) -> Dictionary:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var candidate := {
			"x": coord.x + offset.x,
			"y": coord.y,
			"z": coord.z + offset.y,
		}
		var key := "%d:%d:%d" % [candidate["x"], candidate["y"], candidate["z"]]
		if occupied.has(key):
			continue
		if topology.get("blocking_cells", {}).has(key):
			continue
		var bounds: Dictionary = topology.get("bounds", {})
		if int(candidate["x"]) < int(bounds.get("min_x", 0)) or int(candidate["x"]) > int(bounds.get("max_x", 0)):
			continue
		if int(candidate["z"]) < int(bounds.get("min_z", 0)) or int(candidate["z"]) > int(bounds.get("max_z", 0)):
			continue
		return candidate
	return coord.to_dictionary()


func _different_open_neighbor(coord: RefCounted, topology: Dictionary, occupied: Dictionary, excluded: Dictionary) -> Dictionary:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var candidate := {
			"x": coord.x + offset.x,
			"y": coord.y,
			"z": coord.z + offset.y,
		}
		if int(candidate.get("x", 0)) == int(excluded.get("x", 0)) and int(candidate.get("z", 0)) == int(excluded.get("z", 0)):
			continue
		var key := "%d:%d:%d" % [candidate["x"], candidate["y"], candidate["z"]]
		if occupied.has(key):
			continue
		if topology.get("blocking_cells", {}).has(key):
			continue
		var bounds: Dictionary = topology.get("bounds", {})
		if int(candidate["x"]) < int(bounds.get("min_x", 0)) or int(candidate["x"]) > int(bounds.get("max_x", 0)):
			continue
		if int(candidate["z"]) < int(bounds.get("min_z", 0)) or int(candidate["z"]) > int(bounds.get("max_z", 0)):
			continue
		return candidate
	return excluded.duplicate(true)


func _occupied_actor_cells(simulation: RefCounted, excluded_actor_id: int) -> Dictionary:
	var output: Dictionary = {}
	for actor in simulation.actor_registry.actors():
		if actor.actor_id == excluded_actor_id:
			continue
		output[actor.grid_position.key()] = actor.actor_id
	return output


func _actor_grid(simulation: RefCounted, actor_id: int) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {}
	return actor.grid_position.to_dictionary()


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _last_event_payload(snapshot: Dictionary, kind: String) -> Dictionary:
	var events: Array = snapshot.get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = events[index]
		if event_data.get("kind", "") == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


func _recent_feedback_has(snapshot: Dictionary, kind: String) -> bool:
	for entry in snapshot.get("recent_event_feedback", []):
		var data: Dictionary = _dictionary_or_empty(entry)
		if str(data.get("kind", "")) == kind:
			return true
	return false


func _expect_rejected_command(errors: Array[String], result: Dictionary, expected_reason: String, context: String) -> void:
	if bool(result.get("success", false)):
		errors.append("%s should be rejected" % context)
	if str(result.get("reason", "")) != expected_reason:
		errors.append("%s reason expected %s, got %s" % [context, expected_reason, result.get("reason", "")])
	var feedback: Dictionary = _dictionary_or_empty(result.get("ui_feedback", {}))
	if bool(feedback.get("success", true)):
		errors.append("%s ui_feedback should report failure" % context)
	if str(feedback.get("reason", "")) != expected_reason:
		errors.append("%s ui_feedback reason expected %s, got %s" % [context, expected_reason, feedback.get("reason", "")])
	var rejected_payload: Dictionary = _last_result_event_payload(result, "player_command_rejected")
	if str(rejected_payload.get("reason", "")) != expected_reason:
		errors.append("%s player_command_rejected should include reason" % context)
	var ui_payload: Dictionary = _last_result_event_payload(result, "ui_feedback")
	if str(ui_payload.get("reason", "")) != expected_reason:
		errors.append("%s ui_feedback event should include reason" % context)


func _last_result_event_payload(result: Dictionary, kind: String) -> Dictionary:
	var events: Array = result.get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if event_data.get("kind", "") == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


func _has_turn_payload_for_actor(snapshot: Dictionary, kind: String, actor_id: int) -> bool:
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") != kind:
			continue
		var payload: Dictionary = _dictionary_or_empty(event_data.get("payload", {}))
		if int(payload.get("actor_id", 0)) != actor_id:
			continue
		if not payload.has("ap") or not payload.has("round"):
			return false
		return not str(payload.get("reason", "")).is_empty()
	return false


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _digest(simulation: RefCounted, registry: RefCounted) -> Dictionary:
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	return {
		"event_count": simulation.snapshot().get("events", []).size(),
		"player": _actor_snapshot(world_result, 1),
	}
