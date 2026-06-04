extends SceneTree

const MAIN_MENU_SCENE = preload("res://scenes/boot/main_menu.tscn")
const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const SaveService = preload("res://scripts/app/save_service.gd")

const SAVE_ROOT := "user://main_menu_smoke_saves"
const SAVE_SLOT := "continue_slot"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	ProjectSettings.set_setting("cdc/save_root", SAVE_ROOT)
	ProjectSettings.set_setting("cdc/main_menu_save_slot", SAVE_SLOT)
	ProjectSettings.set_setting("cdc/startup_request", {})
	ProjectSettings.set_setting("cdc/main_menu_smoke_no_scene_change", true)
	_clear_smoke_save()

	var errors: Array[String] = []
	var menu: Control = MAIN_MENU_SCENE.instantiate()
	get_root().add_child(menu)
	await process_frame
	_assert_empty_menu_runtime(errors, menu)
	_assert_continue_disabled_without_save(errors, menu)
	_assert_new_game_request(errors, menu)
	menu.queue_free()
	await process_frame

	_write_continue_save(errors)
	var continue_menu: Control = MAIN_MENU_SCENE.instantiate()
	get_root().add_child(continue_menu)
	await process_frame
	_assert_continue_enabled_with_save(errors, continue_menu)
	_assert_continue_request(errors, continue_menu)
	continue_menu.queue_free()
	await process_frame

	var game_root: Node = GAME_ROOT_SCENE.instantiate()
	get_root().add_child(game_root)
	await process_frame
	_assert_game_root_loaded_continue_snapshot(errors, game_root)

	_clear_smoke_save()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return
	print("main_menu_smoke passed:")
	print(JSON.stringify({
		"save_root": SAVE_ROOT,
		"save_slot": SAVE_SLOT,
		"active_map_id": game_root.simulation.snapshot().get("active_map_id", ""),
		"loaded_from_continue": true,
	}, "\t"))
	quit(0)


func _assert_empty_menu_runtime(errors: Array[String], menu: Control) -> void:
	if menu.find_child("GameRoot", true, false) != null:
		errors.append("main menu should not instantiate game root before starting")
	if menu.find_child("WorldContainer", true, false) != null:
		errors.append("main menu should not render map/world before starting")


func _assert_continue_disabled_without_save(errors: Array[String], menu: Control) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(menu.call("main_menu_snapshot"))
	if bool(snapshot.get("continue_available", false)):
		errors.append("continue should be unavailable without a save: %s" % snapshot)
	var button: Button = menu.find_child("ContinueButton", true, false) as Button
	if button == null or not button.disabled:
		errors.append("continue button should be disabled when save is missing")


func _assert_new_game_request(errors: Array[String], menu: Control) -> void:
	var result: Dictionary = _dictionary_or_empty(menu.call("new_game"))
	var request: Dictionary = _dictionary_or_empty(ProjectSettings.get_setting("cdc/startup_request", {}))
	if not bool(result.get("ok", false)) or str(result.get("action", "")) != "new_game":
		errors.append("new game should report successful start request: %s" % result)
	if str(request.get("mode", "")) != "new_game":
		errors.append("new game should set startup request mode: %s" % request)
	ProjectSettings.set_setting("cdc/startup_request", {})


func _write_continue_save(errors: Array[String]) -> void:
	var registry: ContentRegistry = ContentRegistry.new()
	var load_result: RefCounted = registry.load_all()
	if load_result.has_errors():
		errors.append("content load failed before writing menu smoke save")
		return
	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var simulation: RefCounted = runtime_result.get("simulation")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player != null:
		player.grid_position.x += 1
	var saved := SaveService.new(SAVE_ROOT).save_snapshot(SAVE_SLOT, simulation.snapshot())
	if not saved:
		errors.append("failed to write continue save for main menu smoke")


func _assert_continue_enabled_with_save(errors: Array[String], menu: Control) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(menu.call("main_menu_snapshot"))
	if not bool(snapshot.get("continue_available", false)):
		errors.append("continue should be available with a save: %s" % snapshot)
	var button: Button = menu.find_child("ContinueButton", true, false) as Button
	if button == null or button.disabled:
		errors.append("continue button should be enabled when save exists")


func _assert_continue_request(errors: Array[String], menu: Control) -> void:
	var result: Dictionary = _dictionary_or_empty(menu.call("continue_game"))
	var request: Dictionary = _dictionary_or_empty(ProjectSettings.get_setting("cdc/startup_request", {}))
	if not bool(result.get("ok", false)) or str(result.get("action", "")) != "continue":
		errors.append("continue should report successful start request: %s" % result)
	if str(request.get("mode", "")) != "continue":
		errors.append("continue should set startup request mode: %s" % request)
	if _dictionary_or_empty(request.get("runtime_snapshot", {})).is_empty():
		errors.append("continue should pass a runtime snapshot to game root")


func _assert_game_root_loaded_continue_snapshot(errors: Array[String], game_root: Node) -> void:
	if game_root.simulation == null:
		errors.append("game root should create simulation from continue request")
		return
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("continued simulation should contain player actor")
		return
	if int(player.grid_position.x) != 25:
		errors.append("continued game should load saved player grid x=25, got %s" % player.grid_position.to_dictionary())
	var request: Dictionary = _dictionary_or_empty(ProjectSettings.get_setting("cdc/startup_request", {}))
	if not request.is_empty():
		errors.append("game root should consume startup request after loading: %s" % request)


func _clear_smoke_save() -> void:
	SaveService.new(SAVE_ROOT).delete_snapshot(SAVE_SLOT)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
