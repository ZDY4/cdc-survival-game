extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const MapSceneLoader = preload("res://scripts/world/map_scene_loader.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


func _init() -> void:
	var registry := ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		for error in load_result.errors:
			printerr(error)
		quit(1)
		return

	var runtime_snapshot: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("snapshot", {})
	var map_scene_result: Dictionary = MapSceneLoader.new().load_map_definition(str(runtime_snapshot.get("active_map_id", "")))
	if not bool(map_scene_result.get("ok", false)):
		printerr("active runtime map must load from Godot scene: %s" % map_scene_result.get("error", "unknown"))
		quit(1)
		return
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(runtime_snapshot)
	if not bool(world_result.get("ok", false)):
		printerr(world_result.get("error", "world build failed"))
		quit(1)
		return

	var errors := _validate_world(world_result)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("world_smoke passed:")
	print(JSON.stringify(_digest(world_result), "\t"))
	quit(0)


func _validate_world(world_result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var map: Dictionary = world_result.get("map", {})
	if map.get("map_id", "") != "survivor_outpost_01":
		errors.append("expected survivor_outpost_01 map")
	if int(map.get("object_count", 0)) <= 0:
		errors.append("expected map objects")
	if int(map.get("occupied_cell_count", 0)) <= 0:
		errors.append("expected occupied cells from object footprints")
	var entry_points: Dictionary = map.get("entry_points", {})
	if not entry_points.has("default_entry"):
		errors.append("missing default_entry")
	var actors: Array = world_result.get("actors", [])
	if actors.size() != 3:
		errors.append("expected 3 runtime actors in world snapshot")
	return errors


func _digest(world_result: Dictionary) -> Dictionary:
	var map: Dictionary = world_result.get("map", {})
	return {
		"map_id": map.get("map_id", ""),
		"bounds": map.get("bounds", {}),
		"entry_points": map.get("entry_points", {}).keys(),
		"object_count": map.get("object_count", 0),
		"objects_by_kind": map.get("objects_by_kind", {}),
		"occupied_cell_count": map.get("occupied_cell_count", 0),
		"blocking_cell_count": map.get("blocking_cell_count", 0),
		"interactive_count": map.get("interactive_objects", []).size(),
		"trigger_count": map.get("trigger_objects", []).size(),
		"pickup_count": map.get("pickup_objects", []).size(),
		"ai_spawn_count": map.get("ai_spawn_objects", []).size(),
		"actor_count": world_result.get("actors", []).size(),
	}
