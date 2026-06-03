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

	_expect_ap_depletion_auto_advances_turn(errors, simulation, topology)

	var blocked_goal: Dictionary = _first_blocking_cell(topology)
	var blocked_result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": blocked_goal, "topology": topology})
	if blocked_result.get("reason", "") != "goal_blocked":
		errors.append("moving into blocking cell should report goal_blocked")

	var occupied_result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": _actor_grid(simulation, 2), "topology": topology})
	if occupied_result.get("reason", "") != "goal_blocked":
		errors.append("moving into occupied actor cell should report goal_blocked")

	player.ap = 0.0
	var queued_goal: Dictionary = _first_open_neighbor(player.grid_position, topology, _occupied_actor_cells(simulation, 1))
	var queued_result: Dictionary = simulation.submit_player_command({"kind": "move", "target_position": queued_goal, "topology": topology})
	if queued_result.get("reason", "") != "ap_insufficient_movement_queued":
		errors.append("AP shortage should queue pending movement")
	if simulation.snapshot().get("pending_movement", {}).is_empty():
		errors.append("pending movement should be exposed in snapshot")

	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	var player_snapshot: Dictionary = _actor_snapshot(world_result, 1)
	var grid: Dictionary = player_snapshot.get("grid_position", {})
	if int(grid.get("x", -1)) != player.grid_position.x or int(grid.get("z", -1)) != player.grid_position.z:
		errors.append("world snapshot did not expose moved player position")
	return errors


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


func _digest(simulation: RefCounted, registry: RefCounted) -> Dictionary:
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	return {
		"event_count": simulation.snapshot().get("events", []).size(),
		"player": _actor_snapshot(world_result, 1),
	}
