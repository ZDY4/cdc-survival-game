extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var registry := ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		for error in load_result.errors:
			printerr(error)
		quit(1)
		return

	var runtime_snapshot: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("snapshot", {})
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(runtime_snapshot)
	if not bool(world_result.get("ok", false)):
		printerr(world_result.get("error", "world build failed"))
		quit(1)
		return

	var root := Node3D.new()
	root.name = "SceneSmokeRoot"
	root.name = "SceneSmokeRoot"
	root.add_to_group("scene_smoke_root")
	root.set_meta("world_result", world_result)
	get_root().add_child(root)
	await process_frame

	var counts: Dictionary = WorldSceneRenderer.new().render_world(root, world_result)
	await process_frame
	var errors := _validate_scene(root, counts)
	errors.append_array(_validate_door_state_visuals())
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("scene_smoke passed:")
	print(JSON.stringify(counts, "\t"))
	quit(0)


func _validate_scene(root: Node3D, counts: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if root.get_node_or_null("GeneratedWorld") == null:
		errors.append("missing GeneratedWorld root")
	if int(counts.get("ground", 0)) != 1:
		errors.append("expected one ground mesh")
	if int(counts.get("objects", 0)) <= 0:
		errors.append("expected object marker meshes")
	if int(counts.get("actors", 0)) != 3:
		errors.append("expected 3 actor markers")
	_validate_actor_model_assets(root, errors)
	if int(counts.get("colliders", 0)) <= int(counts.get("actors", 0)):
		errors.append("expected pickable colliders for ground, actors and objects")
	if _interaction_target_node_count(root) <= 0:
		errors.append("expected interaction target metadata on generated nodes")
	_validate_declared_map_visual_assets(root, counts, errors)
	_validate_all_map_scene_visual_assets(counts, errors)
	_validate_imported_gltf_assets(counts, errors)
	if int(counts.get("lights", 0)) <= 0:
		errors.append("expected light")
	if int(counts.get("cameras", 0)) <= 0:
		errors.append("expected camera")
	else:
		_validate_player_camera_focus(root, errors)
	_validate_runtime_map_object_fallbacks(root, errors)
	return errors


func _validate_player_camera_focus(root: Node3D, errors: Array[String]) -> void:
	var player: Node3D = root.find_child("Actor_player_1", true, false) as Node3D
	if player == null:
		errors.append("missing player actor marker")
		return
	if player.position.distance_to(Vector3(24.0, 0.58, 39.0)) > 0.1:
		errors.append("player actor should spawn near default_entry on survivor_outpost_01")
	var camera: Camera3D = root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("missing WorldCamera")
		return
	if not camera.current:
		errors.append("WorldCamera should be the current startup camera")
	var focus: Variant = camera.get_meta("focus_position", Vector3.ZERO)
	if typeof(focus) != TYPE_VECTOR3 or (focus as Vector3).distance_to(Vector3(24.0, 0.5, 39.0)) > 0.1:
		errors.append("WorldCamera should focus the player/default entry at startup")
	if camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		errors.append("WorldCamera should use the legacy Bevy perspective projection")
	if absf(camera.fov - 30.0) > 0.01:
		errors.append("WorldCamera should use the legacy Bevy 30 degree fov")
	if camera.is_position_behind(player.global_position):
		errors.append("WorldCamera should face the startup player marker")
	var projected := camera.unproject_position(player.global_position)
	if projected.x < 0.0 or projected.y < 0.0 or projected.x > 1440.0 or projected.y > 900.0:
		errors.append("startup player marker should be inside the default camera viewport")


func _validate_door_state_visuals() -> Array[String]:
	var errors: Array[String] = []
	var closed_root := Node3D.new()
	closed_root.name = "SceneSmokeDoorClosedRoot"
	get_root().add_child(closed_root)
	WorldSceneRenderer.new().render_world(closed_root, _door_visual_world(false, false), {"load_map_visuals": false})
	var closed_visual: MeshInstance3D = closed_root.find_child("DoorStateVisual", true, false) as MeshInstance3D
	if closed_visual == null:
		errors.append("closed door should render DoorStateVisual")
	else:
		if str(closed_visual.get_meta("door_visual_state", "")) != "closed":
			errors.append("closed door visual should expose closed state")
		if bool(closed_visual.get_meta("door_is_open", true)):
			errors.append("closed door visual should expose door_is_open false")
		if absf(closed_visual.rotation_degrees.y) > 0.01:
			errors.append("closed door visual should keep closed yaw")
	closed_root.queue_free()

	var open_root := Node3D.new()
	open_root.name = "SceneSmokeDoorOpenRoot"
	get_root().add_child(open_root)
	WorldSceneRenderer.new().render_world(open_root, _door_visual_world(true, false), {"load_map_visuals": false})
	var open_visual: MeshInstance3D = open_root.find_child("DoorStateVisual", true, false) as MeshInstance3D
	if open_visual == null:
		errors.append("open door should render DoorStateVisual")
	else:
		if str(open_visual.get_meta("door_visual_state", "")) != "open":
			errors.append("open door visual should expose open state")
		if not bool(open_visual.get_meta("door_is_open", false)):
			errors.append("open door visual should expose door_is_open true")
		if absf(open_visual.rotation_degrees.y) < 45.0:
			errors.append("open door visual should rotate away from closed pose")
	open_root.queue_free()

	var locked_root := Node3D.new()
	locked_root.name = "SceneSmokeDoorLockedRoot"
	get_root().add_child(locked_root)
	WorldSceneRenderer.new().render_world(locked_root, _door_visual_world(false, true), {"load_map_visuals": false})
	var locked_visual: MeshInstance3D = locked_root.find_child("DoorStateVisual", true, false) as MeshInstance3D
	if locked_visual == null:
		errors.append("locked door should render DoorStateVisual")
	else:
		if str(locked_visual.get_meta("door_visual_state", "")) != "locked":
			errors.append("locked door visual should expose locked state")
		if not bool(locked_visual.get_meta("door_locked", false)):
			errors.append("locked door visual should expose door_locked true")
	locked_root.queue_free()
	return errors


func _door_visual_world(is_open: bool, locked: bool) -> Dictionary:
	var grid := {"x": 1, "y": 0, "z": 1}
	var door := {
		"door_id": "scene_smoke_door",
		"object_id": "scene_smoke_door",
		"display_name": "Scene Smoke Door",
		"anchor": grid,
		"cells": [grid],
		"is_open": is_open,
		"locked": locked,
		"blocks_movement": not is_open,
		"blocks_sight": not is_open,
		"blocks_sight_when_closed": true,
	}
	var target := {
		"target_id": "scene_smoke_door",
		"target_type": "map_object",
		"display_name": "Scene Smoke Door",
		"kind": "door",
		"anchor": grid,
		"cells": [grid],
		"door": door,
	}
	return {
		"map": {
			"map_id": "scene_smoke_door_map",
			"size": {"width": 3, "height": 3},
			"entry_points": {"default_entry": {"x": 0, "y": 0, "z": 0}},
			"interactive_objects": [{
				"object_id": "scene_smoke_door",
				"kind": "interactive",
				"anchor": grid,
				"footprint": {"width": 1, "height": 1},
			}],
			"trigger_objects": [],
			"pickup_objects": [],
			"interaction_targets": {"scene_smoke_door": target},
			"door_objects": [door],
		},
		"actors": [],
		"corpses": [],
	}


func _validate_actor_model_assets(root: Node3D, errors: Array[String]) -> void:
	var player: Node = root.find_child("Actor_player_1", true, false)
	if player == null:
		return
	var actor_model: Node = player.find_child("ActorModel", true, false)
	if actor_model == null:
		errors.append("player actor should instantiate its appearance glTF model")
	elif str(actor_model.get_meta("model_asset", "")) != "preview_placeholders/characters/humanoid_mannequin.gltf":
		errors.append("player actor model should come from default_humanoid appearance asset")
	if player.find_child("ActorFallbackMesh", true, false) != null:
		errors.append("player actor should not use fallback capsule mesh when appearance model exists")
	if player.find_child("PlayerRuntimeMarker", true, false) == null:
		errors.append("player actor should include a visible runtime marker")
	_validate_player_equipment_models(player, errors)


func _validate_player_equipment_models(player: Node, errors: Array[String]) -> void:
	for slot_id in ["main_hand", "body", "legs", "feet"]:
		var model: Node = player.find_child("EquipmentModel_%s" % slot_id, true, false)
		if model == null:
			errors.append("player actor should instantiate equipment model for %s" % slot_id)
			continue
		if str(model.get_meta("slot_id", "")) != slot_id:
			errors.append("equipment model %s should expose slot_id metadata" % slot_id)
	var main_hand: Node = player.find_child("EquipmentModel_main_hand", true, false)
	if main_hand != null and str(main_hand.get_meta("model_asset", "")) != "preview_placeholders/placeholders/weapon_dagger.gltf":
		errors.append("main_hand equipment model should use dagger glTF")


func _validate_declared_map_visual_assets(root: Node3D, counts: Dictionary, errors: Array[String]) -> void:
	var visual_root: Node = root.find_child("MapSceneVisuals", true, false)
	if visual_root == null:
		errors.append("scene smoke should instantiate MapSceneVisuals")
		return
	var stats := _declared_visual_stats(visual_root, "runtime MapSceneVisuals", errors)
	var declared_count := int(stats.get("declared", 0))
	var instantiated_count := int(stats.get("instantiated", 0))
	counts["declared_map_visuals"] = declared_count
	counts["instantiated_map_visuals"] = instantiated_count
	if declared_count <= 0:
		errors.append("scene smoke expected at least one map object with declared visual props")
	if instantiated_count != declared_count:
		errors.append("scene smoke visual instancing mismatch %d/%d" % [instantiated_count, declared_count])


func _validate_all_map_scene_visual_assets(counts: Dictionary, errors: Array[String]) -> void:
	var dir := DirAccess.open("res://scenes/maps")
	if dir == null:
		errors.append("scene smoke cannot open res://scenes/maps")
		return
	var map_count := 0
	var declared_total := 0
	var instantiated_total := 0
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir() or not file_name.ends_with(".tscn"):
			continue
		map_count += 1
		var scene_path := "res://scenes/maps/%s" % file_name
		var packed: PackedScene = load(scene_path)
		if packed == null:
			errors.append("map scene visual smoke failed to load %s" % scene_path)
			continue
		var scene_root: Node = packed.instantiate()
		if scene_root == null:
			errors.append("map scene visual smoke failed to instantiate %s" % scene_path)
			continue
		var stats := _declared_visual_stats(scene_root, file_name, errors)
		declared_total += int(stats.get("declared", 0))
		instantiated_total += int(stats.get("instantiated", 0))
		scene_root.free()
	dir.list_dir_end()
	counts["map_scene_count"] = map_count
	counts["all_map_declared_visuals"] = declared_total
	counts["all_map_instantiated_visuals"] = instantiated_total
	if map_count <= 0:
		errors.append("scene smoke expected at least one map scene")
	if declared_total <= 0:
		errors.append("scene smoke expected declared visual props across map scenes")
	if instantiated_total != declared_total:
		errors.append("all map scene visual instancing mismatch %d/%d" % [instantiated_total, declared_total])


func _validate_runtime_map_object_fallbacks(root: Node3D, errors: Array[String]) -> void:
	var visual_backed_marker: Node = root.find_child("MapObject_survivor_outpost_01_pickup_medkit", true, false)
	if visual_backed_marker != null and _map_object_fallback_count(visual_backed_marker) != 0:
		errors.append("runtime map object with real scene visual should not add duplicate fallback visual")
	if _map_object_fallback_count(root) <= 0:
		errors.append("runtime map objects without real scene visuals should expose fallback visuals")
	var fallback_root := Node3D.new()
	fallback_root.name = "SceneSmokeMapObjectFallbackRoot"
	get_root().add_child(fallback_root)
	WorldSceneRenderer.new().render_world(fallback_root, _fallback_visual_world(), {"load_map_visuals": false})
	var categories := {}
	var pending: Array[Node] = [fallback_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if node.name != "MapObjectFallbackVisual":
			continue
		categories[str(node.get_meta("fallback_category", ""))] = true
	for category in ["pickup", "container", "trigger"]:
		if not bool(categories.get(category, false)):
			errors.append("generated map object fallback should include %s visual" % category)
	fallback_root.queue_free()


func _map_object_fallback_count(root: Node) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.name == "MapObjectFallbackVisual":
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count


func _fallback_visual_world() -> Dictionary:
	var pickup_grid := {"x": 1, "y": 0, "z": 1}
	var container_grid := {"x": 2, "y": 0, "z": 1}
	var trigger_grid := {"x": 3, "y": 0, "z": 1}
	return {
		"map": {
			"map_id": "scene_smoke_fallback_map",
			"size": {"width": 5, "height": 4},
			"entry_points": {"default_entry": {"x": 0, "y": 0, "z": 0}},
			"interactive_objects": [{
				"object_id": "scene_smoke_container",
				"kind": "interactive",
				"anchor": container_grid,
				"footprint": {"width": 1, "height": 1},
			}],
			"trigger_objects": [{
				"object_id": "scene_smoke_trigger",
				"kind": "trigger",
				"anchor": trigger_grid,
				"footprint": {"width": 1, "height": 1},
			}],
			"pickup_objects": [{
				"object_id": "scene_smoke_pickup",
				"kind": "pickup",
				"anchor": pickup_grid,
				"footprint": {"width": 1, "height": 1},
			}],
			"interaction_targets": {
				"scene_smoke_container": {
					"target_id": "scene_smoke_container",
					"target_type": "map_object",
					"display_name": "Fallback Container",
					"kind": "container",
					"anchor": container_grid,
					"cells": [container_grid],
				},
				"scene_smoke_trigger": {
					"target_id": "scene_smoke_trigger",
					"target_type": "map_object",
					"display_name": "Fallback Trigger",
					"kind": "enter_subscene",
					"anchor": trigger_grid,
					"cells": [trigger_grid],
				},
				"scene_smoke_pickup": {
					"target_id": "scene_smoke_pickup",
					"target_type": "map_object",
					"display_name": "Fallback Pickup",
					"kind": "pickup",
					"anchor": pickup_grid,
					"cells": [pickup_grid],
				},
			},
		},
		"actors": [],
		"corpses": [],
	}


func _declared_visual_stats(root: Node, label: String, errors: Array[String]) -> Dictionary:
	var declared_count := 0
	var instantiated_count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if not node.has_method("to_object_definition"):
			continue
		var definition: Dictionary = node.call("to_object_definition")
		var props: Dictionary = _dictionary_or_empty(definition.get("props", {}))
		var visual_props: Dictionary = _dictionary_or_empty(props.get("visual", {}))
		if visual_props.is_empty():
			continue
		declared_count += 1
		var object_id := str(definition.get("object_id", ""))
		var visuals_container: Node = node.get_node_or_null("Visuals")
		if visuals_container == null:
			errors.append("%s object %s declares visual props but has no Visuals node" % [label, object_id])
			continue
		if visuals_container.get_child_count() <= 0:
			errors.append("%s object %s declares visual props but instantiated no visual children" % [label, object_id])
			continue
		instantiated_count += 1
	return {
		"declared": declared_count,
		"instantiated": instantiated_count,
	}


func _validate_imported_gltf_assets(counts: Dictionary, errors: Array[String]) -> void:
	var asset_paths: Array[String] = []
	_collect_gltf_assets("res://assets", asset_paths, errors)
	asset_paths.sort()
	var mesh_total := 0
	var material_total := 0
	var zero_bounds: Array[String] = []
	for asset_path in asset_paths:
		if not ResourceLoader.exists(asset_path):
			errors.append("gltf asset missing imported resource: %s" % asset_path)
			continue
		var packed: PackedScene = load(asset_path)
		if packed == null:
			errors.append("gltf asset failed to load as PackedScene: %s" % asset_path)
			continue
		var instance: Node = packed.instantiate()
		if instance == null:
			errors.append("gltf asset failed to instantiate: %s" % asset_path)
			continue
		var stats := _gltf_instance_stats(instance)
		var mesh_count := int(stats.get("mesh_count", 0))
		var material_count := int(stats.get("material_count", 0))
		mesh_total += mesh_count
		material_total += material_count
		if mesh_count <= 0:
			errors.append("gltf asset should contain at least one mesh: %s" % asset_path)
		var bounds: AABB = stats.get("bounds", AABB())
		if bounds.size.length() <= 0.001:
			zero_bounds.append(asset_path)
		instance.free()
	for asset_path in zero_bounds:
		errors.append("gltf asset should have non-zero visual bounds: %s" % asset_path)
	counts["gltf_asset_count"] = asset_paths.size()
	counts["gltf_mesh_count"] = mesh_total
	counts["gltf_material_count"] = material_total
	if asset_paths.is_empty():
		errors.append("scene smoke expected glTF assets under res://assets")


func _collect_gltf_assets(root_path: String, output: Array[String], errors: Array[String]) -> void:
	var dir := DirAccess.open(root_path)
	if dir == null:
		errors.append("cannot open asset directory %s" % root_path)
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		var path := "%s/%s" % [root_path, entry]
		if dir.current_is_dir():
			_collect_gltf_assets(path, output, errors)
		elif entry.ends_with(".gltf") or entry.ends_with(".glb"):
			output.append(path)
	dir.list_dir_end()


func _gltf_instance_stats(root: Node) -> Dictionary:
	var mesh_count := 0
	var material_count := 0
	var has_bounds := false
	var bounds := AABB()
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		mesh_count += 1
		var mesh_bounds := mesh_node.get_aabb()
		bounds = mesh_bounds if not has_bounds else bounds.merge(mesh_bounds)
		has_bounds = true
		for surface_index in range(mesh_node.mesh.get_surface_count()):
			if mesh_node.mesh.surface_get_material(surface_index) != null:
				material_count += 1
		if mesh_node.material_override != null:
			material_count += 1
	return {
		"mesh_count": mesh_count,
		"material_count": material_count,
		"bounds": bounds,
	}


func _interaction_target_node_count(root: Node) -> int:
	var count: int = 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.has_meta("interaction_target"):
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
