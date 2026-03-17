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
	runner.register_test(
		"player_controller_blocks_world_input_when_combat_turn_is_not_player",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_combat_turn_blocks_world_input
	)
	runner.register_test(
		"player_controller_truncates_movement_to_available_ap",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_movement_truncates_to_available_ap
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

static func _test_combat_turn_blocks_world_input() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	TurnSystem.reset_runtime_state()

	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	var tree: SceneTree = loop
	assert(tree.root != null, "SceneTree root should exist")

	var player := PlayerController.new()
	tree.root.add_child(player)
	await tree.process_frame
	await tree.process_frame

	var hostile := Node3D.new()
	hostile.name = "HostileDummy"
	tree.root.add_child(hostile)
	await tree.process_frame

	TurnSystem.register_group("hostile:test", 100)
	TurnSystem.register_actor(hostile, "hostile:test", "hostile")
	TurnSystem.enter_combat(player, hostile)
	assert(not player.is_world_input_blocked(), "Player turn should remain interactive right after entering combat")

	var start_result: Dictionary = TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_DEFEND, {
		"phase": TurnSystem.ACTION_PHASE_START
	})
	assert(bool(start_result.get("success", false)), "Player should be able to finish their combat turn")
	TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_DEFEND, {
		"phase": TurnSystem.ACTION_PHASE_COMPLETE,
		"success": true
	})

	assert(TurnSystem.is_actor_current_turn(hostile), "Hostile actor should receive the next combat turn")
	assert(player.is_world_input_blocked(), "World input should be blocked when another combat actor owns the turn")

	TurnSystem.force_end_combat()
	await tree.process_frame
	assert(not player.is_world_input_blocked(), "Leaving combat should restore world input")

	hostile.queue_free()
	player.queue_free()
	await tree.process_frame

static func _test_movement_truncates_to_available_ap() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	TurnSystem.reset_runtime_state()

	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	var tree: SceneTree = loop
	assert(tree.root != null, "SceneTree root should exist")

	var player := PlayerController.new()
	tree.root.add_child(player)
	await tree.process_frame
	await tree.process_frame

	player.global_position = Vector3(0.5, 0.0, 0.5)
	await tree.process_frame

	var target := Vector3(2.5, 0.0, 0.5)
	var started := player.move_to(target)
	assert(started, "Movement should start when at least 1 AP is available")

	await tree.create_timer(0.8).timeout

	assert(player.global_position.distance_to(Vector3(1.5, 0.0, 0.5)) < 0.2, "Player should only advance one grid step with 1 AP")
	assert(player.global_position.distance_to(target) > 0.5, "Player should not reach the full target path in one turn")
	assert(is_equal_approx(TurnSystem.get_actor_ap(player), 0.0), "Movement should consume the available AP after the completed step")

	player.queue_free()
	await tree.process_frame
