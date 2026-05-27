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
	var move_result: Dictionary = simulation.move_actor_to(1, {"x": 0, "y": 0, "z": 3}, topology)
	if not bool(move_result.get("success", false)):
		errors.append("reachable move failed: %s" % move_result.get("reason", "unknown"))
	if int(move_result.get("steps", 0)) != 3:
		errors.append("reachable move should take 3 steps")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player.grid_position.z != 3:
		errors.append("player grid position did not update after move")
	if _event_count(simulation.snapshot(), "actor_moved") != 1:
		errors.append("move did not emit actor_moved")

	var blocked_goal: Dictionary = _first_blocking_cell(topology)
	var blocked_result: Dictionary = simulation.move_actor_to(1, blocked_goal, topology)
	if blocked_result.get("reason", "") != "goal_blocked":
		errors.append("moving into blocking cell should report goal_blocked")

	var occupied_result: Dictionary = simulation.move_actor_to(1, {"x": 1, "y": 0, "z": 0}, topology)
	if occupied_result.get("reason", "") != "goal_blocked":
		errors.append("moving into occupied actor cell should report goal_blocked")

	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	var player_snapshot: Dictionary = _actor_snapshot(world_result, 1)
	var grid: Dictionary = player_snapshot.get("grid_position", {})
	if int(grid.get("z", -1)) != 3:
		errors.append("world snapshot did not expose moved player position")
	return errors


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
