extends Node
class_name FunctionalTest_TurnSystem

class DummyAIController extends Node:
	var performed_actions: int = 0

	func execute_turn_step() -> Dictionary:
		performed_actions += 1
		var actor := get_parent()
		var start_result: Dictionary = TurnSystem.request_action(actor, TurnSystem.ACTION_TYPE_INTERACT, {
			"phase": TurnSystem.ACTION_PHASE_START
		})
		if not bool(start_result.get("success", false)):
			return {"performed": false}
		TurnSystem.request_action(actor, TurnSystem.ACTION_TYPE_INTERACT, {
			"phase": TurnSystem.ACTION_PHASE_COMPLETE,
			"success": true
		})
		return {"performed": true}

static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"turn_system_caps_and_carries_actor_ap",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_ap_cap_and_carry
	)
	runner.register_test(
		"turn_system_runs_world_cycle_for_registered_non_player_actors",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_world_cycle_runs_other_actor_turns
	)
	runner.register_test(
		"turn_system_rejects_non_current_combat_actor_and_enforces_attack_limit",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_combat_turn_gating_and_attack_limit
	)

static func _test_ap_cap_and_carry() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	TurnSystem.reset_runtime_state()

	var tree := _get_tree()
	var player := Node3D.new()
	player.name = "TurnTestPlayer"
	player.add_to_group("player")
	tree.root.add_child(player)
	await tree.process_frame

	TurnSystem.register_group("player", 0)
	TurnSystem.register_actor(player, "player", "player")
	TurnSystem.set_actor_ap(player, 0.5)

	var start_result: Dictionary = TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_INTERACT, {
		"phase": TurnSystem.ACTION_PHASE_START
	})
	assert(bool(start_result.get("success", false)), "Player should be able to start an AP-governed action")
	assert(is_equal_approx(float(start_result.get("ap_before", 0.0)), 1.5), "Turn AP gain should cap at 1.5 AP")

	var complete_result: Dictionary = TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_INTERACT, {
		"phase": TurnSystem.ACTION_PHASE_COMPLETE,
		"success": true
	})
	assert(is_equal_approx(float(complete_result.get("ap_after", 0.0)), 0.5), "Remaining AP should carry over after consuming one action")

	await tree.process_frame
	await tree.process_frame

	var second_start: Dictionary = TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_INTERACT, {
		"phase": TurnSystem.ACTION_PHASE_START
	})
	assert(is_equal_approx(float(second_start.get("ap_before", 0.0)), 1.5), "Carried AP should combine with the next turn gain and clamp to the AP cap")

	TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_INTERACT, {
		"phase": TurnSystem.ACTION_PHASE_COMPLETE,
		"success": true
	})
	player.queue_free()
	await tree.process_frame

static func _test_world_cycle_runs_other_actor_turns() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	TurnSystem.reset_runtime_state()

	var tree := _get_tree()
	var player := Node3D.new()
	player.name = "WorldCyclePlayer"
	player.add_to_group("player")
	tree.root.add_child(player)

	var friendly := Node3D.new()
	friendly.name = "FriendlyDummy"
	var ai_controller := DummyAIController.new()
	friendly.add_child(ai_controller)
	tree.root.add_child(friendly)
	await tree.process_frame

	TurnSystem.register_group("player", 0)
	TurnSystem.register_actor(player, "player", "player")
	TurnSystem.register_group("friendly", 10)
	TurnSystem.register_actor(friendly, "friendly", "friendly")

	var start_result: Dictionary = TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_INTERACT, {
		"phase": TurnSystem.ACTION_PHASE_START
	})
	assert(bool(start_result.get("success", false)), "Player should be able to start the non-combat cycle")
	TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_INTERACT, {
		"phase": TurnSystem.ACTION_PHASE_COMPLETE,
		"success": true
	})

	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	assert(ai_controller.performed_actions == 1, "The registered friendly actor should execute its world-cycle turn after the player's action")
	assert(is_equal_approx(TurnSystem.get_actor_ap(friendly), 0.0), "The friendly actor should consume its granted AP during the auto turn")

	friendly.queue_free()
	player.queue_free()
	await tree.process_frame

static func _test_combat_turn_gating_and_attack_limit() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	TurnSystem.reset_runtime_state()

	var tree := _get_tree()
	var player := Node3D.new()
	player.name = "CombatPlayer"
	player.add_to_group("player")
	tree.root.add_child(player)

	var hostile_one := Node3D.new()
	hostile_one.name = "HostileOne"
	tree.root.add_child(hostile_one)

	var hostile_two := Node3D.new()
	hostile_two.name = "HostileTwo"
	tree.root.add_child(hostile_two)
	await tree.process_frame

	TurnSystem.register_group("player", 0)
	TurnSystem.register_actor(player, "player", "player")
	TurnSystem.register_group("hostile:one", 100)
	TurnSystem.register_group("hostile:two", 101)
	TurnSystem.register_actor(hostile_one, "hostile:one", "hostile")
	TurnSystem.register_actor(hostile_two, "hostile:two", "hostile")

	TurnSystem.enter_combat(player, hostile_one)

	var hostile_start: Dictionary = TurnSystem.request_action(hostile_one, TurnSystem.ACTION_TYPE_INTERACT, {
		"phase": TurnSystem.ACTION_PHASE_START
	})
	assert(not bool(hostile_start.get("success", true)), "A non-current combat actor should be rejected before its turn")
	assert(str(hostile_start.get("reason", "")) == "not_actor_turn", "Combat rejection should explain that the actor does not own the current turn")

	var attack_start: Dictionary = TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_ATTACK, {
		"phase": TurnSystem.ACTION_PHASE_START,
		"target_actor": hostile_one
	})
	assert(bool(attack_start.get("success", false)), "Current actor should be able to claim the global attack slot")

	var second_attack: Dictionary = TurnSystem.request_action(hostile_two, TurnSystem.ACTION_TYPE_ATTACK, {
		"phase": TurnSystem.ACTION_PHASE_START,
		"target_actor": player
	})
	assert(not bool(second_attack.get("success", true)), "Another actor should not be able to start an attack while the slot is occupied")

	TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_ATTACK, {
		"phase": TurnSystem.ACTION_PHASE_COMPLETE,
		"success": true
	})

	assert(TurnSystem.is_actor_current_turn(hostile_one), "Combat should advance to the next hostile actor after the player action resolves")

	TurnSystem.force_end_combat()
	hostile_two.queue_free()
	hostile_one.queue_free()
	player.queue_free()
	await tree.process_frame

static func _get_tree() -> SceneTree:
	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	return loop as SceneTree
