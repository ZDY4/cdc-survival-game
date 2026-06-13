extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const WorldRuntimeRoot = preload("res://scripts/world/runtime/world_runtime_root.gd")
const WorldRuntimeRootScene = preload("res://scenes/world/world_runtime_root.tscn")
const MAP_SCENE_DIR := "res://scenes/maps"


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

	var runtime_root := WorldRuntimeRootScene.instantiate() as WorldRuntimeRoot
	if runtime_root == null:
		printerr("WorldRuntimeRoot scene should instantiate as WorldRuntimeRoot")
		quit(1)
		return
	get_root().add_child(runtime_root)
	await process_frame
	var counts := runtime_root.sync_world(world_result, runtime_snapshot)
	await process_frame

	var errors: Array[String] = []
	errors.append_array(_validate_runtime_root(runtime_root, world_result, counts))
	errors.append_array(await _validate_all_map_scenes(registry))
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("scene_smoke passed:")
	print(JSON.stringify(counts, "\t"))
	quit(0)


func _validate_runtime_root(runtime_root: WorldRuntimeRoot, world_result: Dictionary, counts: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if runtime_root.current_map() == null:
		errors.append("WorldRuntimeRoot should hold CurrentMap")
	else:
		if runtime_root.current_map().name != "CurrentMap":
			errors.append("current map scene should be named CurrentMap")
		if runtime_root.current_map().get_parent() != runtime_root:
			errors.append("CurrentMap should be a direct WorldRuntimeRoot child")
	if runtime_root.find_child("GeneratedWorld", true, false) != null:
		errors.append("new runtime path should not create GeneratedWorld")
	if int(counts.get("map_scene", 0)) != 1:
		errors.append("WorldRuntimeRoot should load exactly one map scene")
	if int(counts.get("actors", 0)) != 3:
		errors.append("WorldRuntimeRoot should sync 3 startup actors")
	if int(counts.get("cameras", 0)) != 1:
		errors.append("WorldRuntimeRoot should expose one WorldCamera")
	if int(counts.get("lights", 0)) != 1:
		errors.append("WorldRuntimeRoot should expose one LightRig light")
	if int(counts.get("interaction_targets", 0)) <= 0:
		errors.append("WorldRuntimeRoot should bind interaction metadata to scene nodes")
	var camera := runtime_root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("WorldRuntimeRoot should contain WorldCamera")
	elif not camera.current:
		errors.append("WorldCamera should be current")
	var player := runtime_root.find_child("Actor_player_1", true, false) as Node3D
	if player == null:
		errors.append("WorldRuntimeRoot should contain stable player actor view")
	else:
		if int(player.get_meta("actor_id", 0)) != 1:
			errors.append("player actor view should expose actor_id metadata")
		if player.find_child("ActorModel", true, false) == null:
			errors.append("player actor view should use a real ActorModel")
		if player.find_child("PickableBody", true, false) == null:
			errors.append("player actor view should expose a pickable body")
	var target_nodes := _nodes_with_interaction_target(runtime_root)
	if target_nodes.is_empty():
		errors.append("runtime tree should expose interaction_target metadata")
	_validate_actor_stability(runtime_root, world_result, errors)
	return errors


func _validate_actor_stability(runtime_root: WorldRuntimeRoot, world_result: Dictionary, errors: Array[String]) -> void:
	var player := runtime_root.find_child("Actor_player_1", true, false) as Node3D
	if player == null:
		return
	var before := player.get_instance_id()
	runtime_root.sync_world(world_result, {})
	var after_player := runtime_root.find_child("Actor_player_1", true, false) as Node3D
	if after_player == null:
		errors.append("player actor should still exist after second sync")
	elif after_player.get_instance_id() != before:
		errors.append("actor views should be stable across runtime sync")


func _validate_all_map_scenes(registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var ids := _map_scene_ids(registry)
	if ids.is_empty():
		errors.append("no map scenes found")
	for map_id in ids:
		var scene_path := "%s/%s.tscn" % [MAP_SCENE_DIR, map_id]
		if not ResourceLoader.exists(scene_path):
			errors.append("map scene missing: %s" % scene_path)
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			errors.append("map scene failed to load: %s" % scene_path)
			continue
		var root := packed.instantiate() as Node3D
		if root == null:
			errors.append("map scene root should be Node3D: %s" % scene_path)
			continue
		get_root().add_child(root)
		await process_frame
		if not root.has_method("to_definition"):
			errors.append("map scene root should expose to_definition: %s" % scene_path)
		if root.get_node_or_null("Ground") == null:
			errors.append("map scene should contain real Ground: %s" % scene_path)
		if root.get_node_or_null("GroundPicker") == null:
			errors.append("map scene should contain GroundPicker: %s" % scene_path)
		if root.get_node_or_null("Objects") == null:
			errors.append("map scene should contain Objects: %s" % scene_path)
		if root.get_node_or_null("EntryPoints") == null:
			errors.append("map scene should contain EntryPoints: %s" % scene_path)
		_validate_map_object_pick_areas(root, scene_path, errors)
		root.queue_free()
	return errors


func _validate_map_object_pick_areas(root: Node, scene_path: String, errors: Array[String]) -> void:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if not node.has_method("to_object_definition"):
			continue
		var definition: Dictionary = _dictionary_or_empty(node.call("to_object_definition"))
		var object_id := str(definition.get("object_id", ""))
		var kind := str(definition.get("kind", ""))
		if object_id.is_empty():
			continue
		if kind in ["trigger", "pickup", "interactive"] and not _has_pickable_child(node):
			errors.append("%s object %s should provide PickArea or CollisionObject3D" % [scene_path, object_id])


func _has_pickable_child(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	if node.get_node_or_null("PickArea") is Area3D:
		return true
	if node.get_node_or_null("PickableBody") is CollisionObject3D:
		return true
	return false


func _nodes_with_interaction_target(root: Node) -> Array[Node]:
	var output: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.has_meta("interaction_target"):
			output.append(node)
		for child in node.get_children():
			pending.append(child)
	return output


func _map_scene_ids(registry: RefCounted) -> Array[String]:
	var ids: Dictionary = {}
	for map_id in registry.get_library("maps").keys():
		ids[str(map_id)] = true
	var dir := DirAccess.open(MAP_SCENE_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				ids[file_name.get_basename()] = true
			file_name = dir.get_next()
	var output: Array[String] = []
	for key in ids.keys():
		output.append(str(key))
	output.sort()
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
