extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


func _init() -> void:
	var scenario := _read_scenario()
	var exit_code := 0
	match scenario:
		"new_game_smoke":
			exit_code = _run_new_game_smoke()
		"world_smoke":
			exit_code = _run_world_smoke()
		_:
			printerr("unknown headless scenario: %s" % scenario)
			exit_code = 2
	quit(exit_code)


func _read_scenario() -> String:
	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--scenario" and i + 1 < args.size():
			return args[i + 1]
	return "new_game_smoke"


func _run_new_game_smoke() -> int:
	var registry: ContentRegistry = ContentRegistry.new()
	var result: RefCounted = registry.load_all()
	if result.has_errors():
		printerr("content load failed before new_game_smoke")
		for error in result.errors:
			printerr(error)
		return 1

	if registry.bootstrap_config.is_empty():
		printerr("new_game_smoke missing bootstrap config")
		return 1

	var runtime_bootstrap := CoreRuntimeBootstrap.new(registry)
	var runtime_result: Dictionary = runtime_bootstrap.build_new_game_runtime()
	var snapshot: Dictionary = runtime_result.get("snapshot", {})
	var actors: Array = snapshot.get("actors", [])
	if actors.is_empty():
		printerr("new_game_smoke produced no actors")
		return 1

	var actor_labels: Array[String] = []
	for actor in actors:
		actor_labels.append("%s#%d@%s" % [
			actor.get("definition_id", ""),
			int(actor.get("actor_id", 0)),
			actor.get("grid_position", {}),
		])

	print("new_game_smoke ok:")
	print(JSON.stringify({
		"active_map_id": snapshot.get("active_map_id", ""),
		"actor_count": actors.size(),
		"event_count": snapshot.get("events", []).size(),
		"actors": actor_labels,
	}, "\t"))
	return 0


func _run_world_smoke() -> int:
	var registry: ContentRegistry = ContentRegistry.new()
	var result: RefCounted = registry.load_all()
	if result.has_errors():
		printerr("content load failed before world_smoke")
		for error in result.errors:
			printerr(error)
		return 1

	var runtime_snapshot: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("snapshot", {})
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(runtime_snapshot)
	if not bool(world_result.get("ok", false)):
		printerr(world_result.get("error", "world build failed"))
		return 1

	var map: Dictionary = world_result.get("map", {})
	print("world_smoke ok:")
	print(JSON.stringify({
		"map_id": map.get("map_id", ""),
		"object_count": map.get("object_count", 0),
		"occupied_cell_count": map.get("occupied_cell_count", 0),
		"actor_count": world_result.get("actors", []).size(),
	}, "\t"))
	return 0
