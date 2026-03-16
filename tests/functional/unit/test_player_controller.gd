extends Node
class_name FunctionalTest_PlayerController

const PlayerController = preload("res://systems/player_controller.gd")

static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"player_controller_blocks_character_input_when_console_visible",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_console_visibility_blocks_character_input
	)
	runner.register_test(
		"player_controller_blocks_world_input_when_menu_is_open",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_menu_block_only_blocks_world_input
	)

static func _test_console_visibility_blocks_character_input() -> void:
	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	var tree: SceneTree = loop
	assert(tree.root != null, "SceneTree root should exist")

	var player := PlayerController.new()
	tree.root.add_child(player)
	await tree.process_frame

	player._is_dialog_active = false
	player._set_interaction_in_progress(false)
	player._on_console_visibility_changed(false)
	assert(not player.is_movement_input_blocked(), "Player input should be enabled before console opens")

	player._on_console_visibility_changed(true)
	assert(player.is_movement_input_blocked(), "Console should block player character input")
	assert(player.is_console_input_blocked(), "Console visibility flag should be exposed for shared input routing")

	player._on_console_visibility_changed(false)
	assert(not player.is_movement_input_blocked(), "Closing console should restore player character input")

	player.queue_free()
	await tree.process_frame

static func _test_menu_block_only_blocks_world_input() -> void:
	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	var tree: SceneTree = loop
	assert(tree.root != null, "SceneTree root should exist")

	var player := PlayerController.new()
	tree.root.add_child(player)
	await tree.process_frame

	player._on_console_visibility_changed(false)
	player._set_interaction_in_progress(false)
	player.set_menu_input_blocked(true)
	assert(not player.is_movement_input_blocked(), "Menu should not mark the player as movement-blocked")
	assert(player.is_world_input_blocked(), "Menu should block world input routing")

	player.set_menu_input_blocked(false)
	assert(not player.is_world_input_blocked(), "Closing menu should restore world input routing")

	player.queue_free()
	await tree.process_frame
