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

	print("vision_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var topology: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot()).get("map", {})
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null:
		return ["player actor missing"]

	simulation.set_actor_vision_radius(1, 0)
	var zero_radius: Dictionary = simulation.refresh_actor_vision(1, topology)
	if not bool(zero_radius.get("success", false)):
		errors.append("zero radius vision refresh failed: %s" % zero_radius.get("reason", "unknown"))
	if _array_or_empty(zero_radius.get("visible_cells", [])).size() != 1:
		errors.append("zero radius should only reveal actor cell")
	if _event_count(simulation.snapshot(), "actor_vision_updated") != 1:
		errors.append("initial vision refresh should emit actor_vision_updated")

	simulation.set_actor_vision_radius(1, 6)
	var expanded: Dictionary = simulation.refresh_actor_vision(1, topology)
	if _array_or_empty(expanded.get("visible_cells", [])).size() <= 1:
		errors.append("radius 6 should reveal more than actor cell")
	if not _has_cell(expanded.get("visible_cells", []), player.grid_position.to_dictionary()):
		errors.append("visible cells should include player cell")

	var blocker_key: String = _first_sight_blocker_key(topology)
	if blocker_key.is_empty():
		errors.append("survivor_outpost_01 should expose a sight blocker")
	else:
		var blocker_cell: Dictionary = _cell_from_key(blocker_key)
		player.grid_position = GridCoord.new(int(blocker_cell.get("x", 0)) - 1, int(blocker_cell.get("y", 0)), int(blocker_cell.get("z", 0)))
		simulation.set_actor_vision_radius(1, 3)
		var blocked_topology: Dictionary = {
			"bounds": {
				"min_x": min(player.grid_position.x, int(blocker_cell.get("x", 0)) + 1) - 1,
				"max_x": max(player.grid_position.x, int(blocker_cell.get("x", 0)) + 1) + 1,
				"min_z": int(blocker_cell.get("z", 0)) - 1,
				"max_z": int(blocker_cell.get("z", 0)) + 1,
			},
			"sight_blocking_cells": {
				blocker_key: "smoke_blocker",
			},
		}
		var blocked: Dictionary = simulation.refresh_actor_vision(1, blocked_topology)
		var behind_blocker: Dictionary = {
			"x": int(blocker_cell.get("x", 0)) + 1,
			"y": int(blocker_cell.get("y", 0)),
			"z": int(blocker_cell.get("z", 0)),
		}
		if _has_cell(blocked.get("visible_cells", []), behind_blocker):
			errors.append("line of sight should stop behind blocker")
		if not _has_cell(blocked.get("visible_cells", []), blocker_cell):
			errors.append("blocking cell itself should remain visible")

	var explored_before: int = _actor_explored_cell_count(simulation.snapshot(), 1, simulation.active_map_id)
	player.grid_position.x += 2
	var moved_update: Dictionary = simulation.refresh_actor_vision(1, topology)
	var explored_after: int = _actor_explored_cell_count(simulation.snapshot(), 1, simulation.active_map_id)
	if not bool(moved_update.get("success", false)):
		errors.append("moved vision refresh failed")
	if explored_after < explored_before:
		errors.append("explored cells should not shrink after movement")

	var restored: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	restored.load_snapshot(simulation.snapshot())
	var restored_vision: Dictionary = restored.snapshot().get("vision", {})
	if JSON.stringify(_actor_vision_snapshot(restored_vision, 1)) != JSON.stringify(_actor_vision_snapshot(simulation.snapshot().get("vision", {}), 1)):
		errors.append("vision snapshot should roundtrip through simulation load_snapshot")
	return errors


func _first_sight_blocker_key(topology: Dictionary) -> String:
	var keys: Array = topology.get("sight_blocking_cells", {}).keys()
	keys.sort()
	return str(keys[0]) if not keys.is_empty() else ""


func _cell_from_key(key: String) -> Dictionary:
	var parts: PackedStringArray = key.split(":")
	return {
		"x": int(parts[0]),
		"y": int(parts[1]),
		"z": int(parts[2]),
	}


func _has_cell(cells: Array, expected: Dictionary) -> bool:
	for cell in cells:
		var cell_data: Dictionary = cell
		if int(cell_data.get("x", 0)) == int(expected.get("x", 0)) and int(cell_data.get("y", 0)) == int(expected.get("y", 0)) and int(cell_data.get("z", 0)) == int(expected.get("z", 0)):
			return true
	return false


func _actor_explored_cell_count(snapshot: Dictionary, actor_id: int, map_id: String) -> int:
	var actor_vision: Dictionary = _actor_vision_snapshot(snapshot.get("vision", {}), actor_id)
	for explored_map in actor_vision.get("explored_maps", []):
		var map_data: Dictionary = explored_map
		if str(map_data.get("map_id", "")) == map_id:
			return _array_or_empty(map_data.get("explored_cells", [])).size()
	return 0


func _actor_vision_snapshot(vision_snapshot: Dictionary, actor_id: int) -> Dictionary:
	for actor in _array_or_empty(vision_snapshot.get("actors", [])):
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


func _digest(snapshot: Dictionary) -> Dictionary:
	var actor_vision: Dictionary = _actor_vision_snapshot(snapshot.get("vision", {}), 1)
	return {
		"event_count": snapshot.get("events", []).size(),
		"vision": actor_vision,
	}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
