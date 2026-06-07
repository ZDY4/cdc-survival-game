extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const Simulation = preload("res://scripts/core/simulation/simulation.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const MapSceneLoader = preload("res://scripts/world/map_scene_loader.gd")
const MapBuilder = preload("res://scripts/world/map_builder.gd")
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
	errors.append_array(_validate_map_scene_failure_reasons(builder, runtime_snapshot))
	errors.append_array(_validate_door_topology_and_runtime())
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
		if str(actor_data.get("definition_id", "")) == "player":
			_validate_player_equipment_visuals(actor_data, errors)
	return errors


func _validate_player_equipment_visuals(player_actor: Dictionary, errors: Array[String]) -> void:
	var by_slot: Dictionary = {}
	for visual in player_actor.get("equipment_visuals", []):
		var visual_data: Dictionary = visual
		by_slot[str(visual_data.get("slot_id", ""))] = visual_data
	for required_slot in ["main_hand", "body", "legs", "feet"]:
		if not by_slot.has(required_slot):
			errors.append("player equipment visual missing slot %s" % required_slot)
	if by_slot.has("main_hand") and str(by_slot["main_hand"].get("model_asset", "")) != "preview_placeholders/placeholders/weapon_dagger.gltf":
		errors.append("player main_hand equipment should resolve dagger glTF")
	if by_slot.has("body") and str(by_slot["body"].get("model_asset", "")) != "preview_placeholders/placeholders/equipment_body.gltf":
		errors.append("player body equipment should resolve body glTF")


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


func _validate_map_scene_failure_reasons(builder: RefCounted, runtime_snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var missing_map_id := "missing_map_scene_reason_smoke"
	var load_result: Dictionary = MapSceneLoader.new().load_map_definition(missing_map_id)
	if bool(load_result.get("ok", false)) or str(load_result.get("reason", "")) != "map_scene_missing":
		errors.append("missing map scene should expose stable map_scene_missing reason: %s" % load_result)
	var missing_snapshot := runtime_snapshot.duplicate(true)
	missing_snapshot["active_map_id"] = missing_map_id
	var world_result: Dictionary = builder.build_from_runtime_snapshot(missing_snapshot)
	if bool(world_result.get("ok", false)) or str(world_result.get("reason", "")) != "map_scene_missing":
		errors.append("world snapshot build should propagate map scene failure reason: %s" % world_result)
	return errors


func _validate_door_topology_and_runtime() -> Array[String]:
	var errors: Array[String] = []
	var map_builder := MapBuilder.new()
	var door_map := {
		"id": "door_smoke_map",
		"name": "Door Smoke Map",
		"size": {"width": 4, "height": 4},
		"default_level": 0,
		"entry_points": [{"id": "default_entry", "grid": {"x": 0, "y": 0, "z": 0}}],
		"objects": [{
			"object_id": "door_smoke_closed",
			"kind": "interactive",
			"anchor": {"x": 1, "y": 0, "z": 1},
			"footprint": {"width": 1, "height": 1},
			"rotation": "north",
			"props": {
				"door": {
					"display_name": "测试门",
					"blocks_sight_when_closed": true,
					"required_item_ids": ["1138"],
					"required_tool_ids": ["1150"]
				}
			}
		}],
	}
	var topology: RefCounted = map_builder.build_from_definition(door_map)
	var map_snapshot: Dictionary = topology.to_dictionary()
	if map_snapshot.get("door_objects", []).size() != 1:
		errors.append("door topology should expose one door object")
	var door_target: Dictionary = _dictionary_or_empty(_dictionary_or_empty(map_snapshot.get("interaction_targets", {})).get("door_smoke_closed", {}))
	if str(door_target.get("kind", "")) != "door":
		errors.append("door interaction target should use door kind")
	var door_data: Dictionary = _dictionary_or_empty(door_target.get("door", {}))
	if not _array_or_empty(door_data.get("required_item_ids", [])).has("1138"):
		errors.append("door interaction target should preserve required item ids")
	if not _array_or_empty(door_data.get("required_tool_ids", [])).has("1150"):
		errors.append("door interaction target should preserve required tool ids")
	if not _dictionary_or_empty(map_snapshot.get("blocking_cells", {})).has("1:0:1"):
		errors.append("closed door should block movement by default")
	if not _dictionary_or_empty(map_snapshot.get("sight_blocking_cells", {})).has("1:0:1"):
		errors.append("closed door should block sight by default")

	var simulation := Simulation.new()
	simulation.register_actor({
		"definition_id": "player",
		"kind": "player",
		"display_name": "玩家",
		"grid_position": GridCoord.new(0, 0, 0),
	})
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.inventory["1138"] = 1
	player.inventory["1150"] = 1
	simulation.configure_map_interactions(_dictionary_or_empty(map_snapshot.get("interaction_targets", {})))
	var toggle_result: Dictionary = simulation.toggle_door(1, "door_smoke_closed")
	if not bool(toggle_result.get("success", false)):
		errors.append("door toggle should succeed: %s" % toggle_result.get("reason", "unknown"))
	var snapshot: Dictionary = simulation.snapshot()
	var door_states: Array = _array_or_empty(snapshot.get("door_states", []))
	if door_states.is_empty() or not bool(_dictionary_or_empty(door_states[0]).get("is_open", false)):
		errors.append("door state should snapshot open after toggle")
	var open_map: Dictionary = map_snapshot.duplicate(true)
	WorldSnapshotBuilder.new(null).call("_apply_door_states", open_map, door_states)
	if _dictionary_or_empty(open_map.get("blocking_cells", {})).has("1:0:1"):
		errors.append("open door should remove movement blocking cell")
	if _dictionary_or_empty(open_map.get("sight_blocking_cells", {})).has("1:0:1"):
		errors.append("open door should remove sight blocking cell")
	var open_target: Dictionary = _dictionary_or_empty(_dictionary_or_empty(open_map.get("interaction_targets", {})).get("door_smoke_closed", {}))
	if not bool(_dictionary_or_empty(open_target.get("door", {})).get("is_open", false)):
		errors.append("door interaction target should reflect open runtime state")
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
		"door_count": map.get("door_objects", []).size(),
		"ai_spawn_count": map.get("ai_spawn_objects", []).size(),
		"actor_count": world_result.get("actors", []).size(),
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
