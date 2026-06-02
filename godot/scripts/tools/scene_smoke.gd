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
