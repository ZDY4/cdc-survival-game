extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")


func _init() -> void:
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

	var counts: Dictionary = WorldSceneRenderer.new().render_world(root, world_result)
	var errors := _validate_scene(root, counts)
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
	if int(counts.get("colliders", 0)) <= int(counts.get("actors", 0)):
		errors.append("expected pickable colliders for ground, actors and objects")
	if _interaction_target_node_count(root) <= 0:
		errors.append("expected interaction target metadata on generated nodes")
	if int(counts.get("lights", 0)) <= 0:
		errors.append("expected light")
	if int(counts.get("cameras", 0)) <= 0:
		errors.append("expected camera")
	else:
		_validate_player_camera_focus(root, errors)
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
	var focus: Variant = camera.get_meta("focus_position", Vector3.ZERO)
	if typeof(focus) != TYPE_VECTOR3 or (focus as Vector3).distance_to(Vector3(24.0, 0.0, 39.0)) > 0.1:
		errors.append("WorldCamera should focus the player/default entry at startup")


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
