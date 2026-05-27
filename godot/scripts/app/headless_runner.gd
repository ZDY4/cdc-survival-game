extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")


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

	var bootstrap := registry.bootstrap_config
	if bootstrap.is_empty():
		printerr("new_game_smoke missing bootstrap config")
		return 1

	var spawn_entries: Array = bootstrap.get("spawnEntries", [])
	var actor_ids: Array[String] = []
	for entry in spawn_entries:
		actor_ids.append(str(entry.get("definitionId", "")))

	var startup_map := str(bootstrap.get("startupMapId", ""))
	print("new_game_smoke ok: map=%s spawns=%s" % [startup_map, ", ".join(actor_ids)])
	return 0
