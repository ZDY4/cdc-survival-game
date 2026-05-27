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
	if int(counts.get("lights", 0)) <= 0:
		errors.append("expected light")
	if int(counts.get("cameras", 0)) <= 0:
		errors.append("expected camera")
	return errors
