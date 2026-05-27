extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")


func _init() -> void:
	var scenario := _read_scenario()
	var exit_code := 0
	match scenario:
		"new_game_smoke":
			exit_code = _run_new_game_smoke()
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
	var registry := ContentRegistry.new()
	var result := registry.load_all()
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
