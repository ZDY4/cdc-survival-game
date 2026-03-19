extends Node
class_name FunctionalTest_PlayerController

const PlayerController = preload("res://systems/player_controller.gd")

class ProximityInteractionOption extends InteractionOption:
	var execute_count: int = 0

	func requires_proximity(_interactable: Node) -> bool:
		return true

	func get_required_distance(_interactable: Node) -> float:
		return 1.05

	func execute(interactable: Node) -> void:
		execute_count += 1
		interactable.set_meta("interaction_executed", execute_count)

class DummyInteractable extends Node3D:
	var option: InteractionOption = null

	func get_primary_option() -> InteractionOption:
		return option

	func get_available_options() -> Array:
		if option == null:
			return []
		return [option]

	func execute_option(selected_option: InteractionOption) -> void:
		if selected_option != null:
			selected_option.execute(self)

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
	runner.register_test(
		"player_controller_routes_move_presentation_through_action_presentation_system",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_player_move_uses_action_presentation_system
	)
	runner.register_test(
		"player_controller_advances_ground_navigation_intent_across_turns",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_ground_navigation_advances_across_turns
	)
	runner.register_test(
		"player_controller_clears_navigation_intent_when_combat_starts",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_navigation_intent_clears_on_combat_start
	)
	runner.register_test(
		"player_controller_auto_executes_interaction_navigation_intent",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_interaction_navigation_auto_executes
	)
	runner.register_test(
		"player_controller_blocks_world_input_while_ability_targeting_is_active",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_targeting_blocks_world_input
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

	var start_result: Dictionary = TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_ITEM, {
		"phase": TurnSystem.ACTION_PHASE_START
	})
	assert(bool(start_result.get("success", false)), "Player should be able to finish their combat turn")
	TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_ITEM, {
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
	assert(is_equal_approx(TurnSystem.get_actor_ap(player), 1.0), "Freshly registered player should begin with an opened first turn worth 1 AP")
	assert(TurnSystem.get_actor_available_steps(player) == 1, "The opened first turn should immediately expose one movable step")
	var started := player.move_to(target)
	assert(started, "The first move should start immediately from the opened initial turn")

	await tree.create_timer(0.8).timeout

	assert(player.global_position.distance_to(Vector3(1.5, 0.0, 0.5)) < 0.2, "Player should only advance one grid step with 1 AP")
	assert(player.global_position.distance_to(target) > 0.5, "Player should not reach the full target path in one turn")
	assert(is_equal_approx(TurnSystem.get_actor_ap(player), 0.0), "Movement should consume the available AP after the completed step")

	player.queue_free()
	await tree.process_frame

static func _test_player_move_uses_action_presentation_system() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	assert(ActionPresentationSystem != null, "ActionPresentationSystem autoload should exist")
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

	var target := Vector3(1.5, 0.0, 0.5)
	var started := player.move_to(target)
	assert(started, "Player movement should start successfully when AP is available")
	assert(player.global_position.distance_to(target) < 0.01, "Move logic should commit the authoritative position before presentation finishes")

	var pending_job_ids: Array[String] = ActionPresentationSystem.get_pending_job_ids_for_actor(player)
	assert(pending_job_ids.size() == 1, "Player movement should submit a unified presentation job")
	assert(player.is_moving(), "The player should remain in a moving state while the presentation job is active")

	await tree.create_timer(0.35).timeout

	assert(ActionPresentationSystem.get_pending_job_ids_for_actor(player).is_empty(), "The movement presentation job should complete after its visual playback")
	assert(not player.is_moving(), "Movement completion should wait for the shared presentation job to finish")

	player.queue_free()
	await tree.process_frame

static func _test_ground_navigation_advances_across_turns() -> void:
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
	var queued := player._queue_ground_navigation_intent(target)
	assert(queued, "Ground clicks should queue a navigation intent in non-combat")
	assert(player.has_navigation_intent(), "Queued ground navigation should remain active until the destination is reached or cancelled")
	assert(player.get_navigation_intent_path().size() == 2, "The queued navigation should retain the remaining path for preview and future turns")

	await tree.process_frame
	await tree.process_frame
	assert(player.global_position.distance_to(Vector3(1.5, 0.0, 0.5)) < 0.2, "Queued ground navigation should immediately commit the first step's logical destination")
	assert(player.global_position.distance_to(target) > 0.3, "Queued ground navigation should still require another turn to reach the final target")

	await tree.create_timer(1.0).timeout
	assert(player.global_position.distance_to(target) < 0.2, "Queued ground navigation should continue across non-combat turns until the destination is reached")
	assert(not player.has_navigation_intent(), "The navigation intent should clear after the player reaches the queued ground destination")

	player.queue_free()
	await tree.process_frame

static func _test_navigation_intent_clears_on_combat_start() -> void:
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
	assert(player._queue_ground_navigation_intent(Vector3(3.5, 0.0, 0.5)), "Ground navigation should be queueable before combat starts")

	var hostile := Node3D.new()
	hostile.name = "QueuedPathHostile"
	tree.root.add_child(hostile)
	await tree.process_frame

	TurnSystem.register_group("hostile:queued", 100)
	TurnSystem.register_actor(hostile, "hostile:queued", "hostile")
	TurnSystem.enter_combat(player, hostile)
	await tree.process_frame

	assert(not player.has_navigation_intent(), "Entering combat should clear any queued non-combat navigation intent")
	assert(not player.is_moving(), "Entering combat should stop any in-progress automatic non-combat movement")
	if ActionPresentationSystem != null:
		assert(ActionPresentationSystem.get_pending_job_ids_for_actor(player).is_empty(), "Entering combat should also cancel any queued non-combat movement presentation jobs")

	TurnSystem.force_end_combat()
	hostile.queue_free()
	player.queue_free()
	await tree.process_frame

static func _test_interaction_navigation_auto_executes() -> void:
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

	var interactable := DummyInteractable.new()
	interactable.name = "AutoInteractDummy"
	interactable.position = Vector3(2.5, 0.0, 0.5)
	var option := ProximityInteractionOption.new()
	interactable.option = option
	tree.root.add_child(interactable)
	await tree.process_frame

	var started := player._begin_option_execution(interactable, option)
	assert(started, "Clicking a distant interactable should start a queued interaction navigation intent in non-combat")
	assert(player.has_navigation_intent(), "Auto-interaction should keep the navigation intent active while the player is approaching the target")

	await tree.create_timer(1.1).timeout

	assert(int(interactable.get_meta("interaction_executed", 0)) == 1, "The interaction should execute automatically once the queued navigation reaches interaction range")
	assert(player.global_position.distance_to(Vector3(1.5, 0.0, 0.5)) < 0.2, "The player should stop at the interaction approach cell rather than walking onto the interactable")
	assert(not player.has_navigation_intent(), "The interaction navigation intent should clear after the interaction executes")

	interactable.queue_free()
	player.queue_free()
	await tree.process_frame

static func _test_targeting_blocks_world_input() -> void:
	assert(SkillModule != null, "SkillModule autoload should exist")
	assert(AbilityTargetingSystem != null, "AbilityTargetingSystem autoload should exist")

	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	var tree: SceneTree = loop
	assert(tree.root != null, "SceneTree root should exist")

	var snapshot: Dictionary = SkillModule.serialize()
	var player := PlayerController.new()
	tree.root.add_child(player)
	await tree.process_frame
	await tree.process_frame
	player.set_interaction_context(tree.root)

	SkillModule.reset_skills()
	SkillModule.set_skill_points(20)
	assert(SkillModule.learn_skill("combat"), "combat should be learnable for targeting test")
	SkillModule._skills["targeted_player_controller_test"] = SkillModule._normalize_skill("targeted_player_controller_test", {
		"name": "测试锁定技",
		"tree_id": "combat",
		"max_level": 1,
		"prerequisites": ["combat"],
		"activation": {
			"mode": "active",
			"cooldown": 3.0,
			"effect": {
				"duration": 2.0,
				"is_infinite": false,
				"category": "buff",
				"modifiers": {
					"damage_bonus": {
						"base": 0.05
					}
				}
			},
			"targeting": {
				"enabled": true,
				"range_cells": 2,
				"shape": "single",
				"radius": 0,
				"handler_script": ""
			}
		}
	})
	SkillModule.learned_skills["targeted_player_controller_test"] = 1
	assert(bool(SkillModule.assign_skill_to_hotbar("targeted_player_controller_test", 0, 0).get("success", false)), "Targeted test skill should be assignable")

	var activation_result: Dictionary = SkillModule.activate_hotbar_slot(0)
	assert(bool(activation_result.get("success", false)), "Activating targeted test skill should start targeting")
	assert(player.is_world_input_blocked(), "Player world input should be blocked while targeting is active")

	AbilityTargetingSystem.cancel_targeting()
	await tree.process_frame
	assert(not player.is_world_input_blocked(), "Cancelling targeting should restore player world input")

	SkillModule.deserialize(snapshot)
	player.queue_free()
	await tree.process_frame
