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
	var builder := WorldSnapshotBuilder.new(registry)
	var world_result: Dictionary = builder.build_from_runtime_snapshot(runtime_snapshot)
	if not bool(world_result.get("ok", false)):
		printerr(world_result.get("error", "world build failed"))
		quit(1)
		return

	var errors := _validate_world(world_result)
	errors.append_array(_validate_legacy_actor_appearance_fill(builder, runtime_snapshot))
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
	for actor in actors:
		var actor_data: Dictionary = actor
		if str(actor_data.get("map_id", "")) != "survivor_outpost_01":
			errors.append("world snapshot actor %s should belong to survivor_outpost_01" % actor_data.get("definition_id", ""))
		if str(actor_data.get("definition_id", "")) == "player" and str(actor_data.get("model_asset", "")) != "preview_placeholders/characters/humanoid_mannequin.gltf":
			errors.append("player actor should carry appearance model asset in world snapshot")
	return errors


func _validate_legacy_actor_appearance_fill(builder: RefCounted, runtime_snapshot: Dictionary) -> Array[String]:
	var legacy_snapshot: Dictionary = runtime_snapshot.duplicate(true)
	var actors: Array = legacy_snapshot.get("actors", [])
	for i in range(actors.size()):
		var actor_data: Dictionary = actors[i]
		if str(actor_data.get("definition_id", "")) != "player":
			continue
		actor_data.erase("appearance_profile_id")
		actor_data.erase("model_asset")
		actors[i] = actor_data
		break

	var world_result: Dictionary = builder.build_from_runtime_snapshot(legacy_snapshot)
	if not bool(world_result.get("ok", false)):
		return ["legacy actor appearance fill world build failed: %s" % world_result.get("error", "unknown")]
	for actor in world_result.get("actors", []):
		var actor_data: Dictionary = actor
		if str(actor_data.get("definition_id", "")) != "player":
			continue
		if str(actor_data.get("appearance_profile_id", "")) != "default_humanoid":
			return ["legacy player actor should fill appearance_profile_id from character definition"]
		if str(actor_data.get("model_asset", "")) != "preview_placeholders/characters/humanoid_mannequin.gltf":
			return ["legacy player actor should fill model_asset from appearance profile"]
		return []
	return ["legacy world snapshot missing player actor"]


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
