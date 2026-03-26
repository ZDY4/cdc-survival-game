extends Node
class_name FunctionalTest_OverworldMapFlow

static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"map_module_distinguishes_outdoor_and_subscene_locations",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_map_module_distinguishes_outdoor_and_subscene_locations
	)
	runner.register_test(
		"game_state_round_trips_outdoor_and_subscene_context",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_game_state_round_trips_outdoor_and_subscene_context
	)

static func _test_map_module_distinguishes_outdoor_and_subscene_locations() -> void:
	assert(MapModule != null, "MapModule autoload should exist")
	assert(
		MapModule.get_world_root_scene_path() == "res://scenes/locations/game_world_root.tscn",
		"Outdoor runtime should enter through game_world_root"
	)
	assert(
		MapModule.is_outdoor_location("survivor_outpost_01"),
		"survivor_outpost_01 should be an outdoor location"
	)
	assert(
		MapModule.is_subscene_location("survivor_outpost_01_interior"),
		"survivor_outpost_01_interior should be treated as a subscene location"
	)
	assert(
		MapModule.get_parent_outdoor_location_id("survivor_outpost_01_interior") == "survivor_outpost_01",
		"Subscene locations should expose their parent outdoor location"
	)
	assert(
		MapModule.get_location_scene_path("survivor_outpost_01_interior") == "res://scenes/interiors/survivor_outpost_01_interior.tscn",
		"Subscene locations should expose their own scene path"
	)
	assert(
		MapModule.get_location_world_origin_cell("survivor_outpost_01") == Vector2i(0, 0),
		"Outdoor locations should expose their runtime world origin"
	)
	assert(
		MapModule.get_reachable_outdoor_locations("survivor_outpost_01").has("street_a"),
		"Outdoor travel should still resolve reachable outdoor destinations"
	)

static func _test_game_state_round_trips_outdoor_and_subscene_context() -> void:
	assert(GameState != null, "GameState autoload should exist")
	GameState.reset_world_runtime("survivor_outpost_01", "default_spawn")
	GameState.set_active_outdoor_context("survivor_outpost_01", "default_spawn")
	GameState.set_world_mode(GameState.WORLD_MODE_LOCAL)
	GameState.set_active_subscene_context(
		"survivor_outpost_01_interior",
		GameState.SCENE_KIND_INTERIOR,
		"survivor_outpost_01",
		"survivor_outpost_01_house_exit"
	)
	assert(
		GameState.active_scene_kind == GameState.SCENE_KIND_INTERIOR,
		"Entering a subscene should switch GameState to the subscene kind"
	)
	assert(
		GameState.current_subscene_location_id == "survivor_outpost_01_interior",
		"GameState should remember the active subscene id"
	)
	assert(
		GameState.return_outdoor_spawn_id == "survivor_outpost_01_house_exit",
		"GameState should remember the outdoor return spawn id"
	)
	GameState.restore_outdoor_from_subscene()
	assert(
		GameState.active_scene_kind == GameState.SCENE_KIND_OUTDOOR_ROOT,
		"Returning from subscene should restore outdoor_root as the active scene kind"
	)
	assert(
		GameState.active_outdoor_location_id == "survivor_outpost_01",
		"Returning from subscene should restore the parent outdoor location"
	)
