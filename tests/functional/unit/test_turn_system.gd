extends Node
class_name FunctionalTest_TurnSystem

const PlayerControllerScript = preload("res://systems/player_controller.gd")
const CharacterActorScript = preload("res://systems/character_actor.gd")

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

class NonBlockingPresentationAIController extends Node:
	var performed_actions: int = 0
	var presentation_job_id: String = ""

	func execute_turn_step() -> Dictionary:
		performed_actions += 1
		var actor := get_parent() as Node3D
		var start_result: Dictionary = TurnSystem.request_action(actor, TurnSystem.ACTION_TYPE_INTERACT, {
			"phase": TurnSystem.ACTION_PHASE_START
		})
		if not bool(start_result.get("success", false)):
			return {"performed": false}

		var from_pos := actor.global_position
		var to_pos := actor.global_position + Vector3(1.0, 0.0, 0.0)
		actor.global_position = to_pos
		if ActionPresentationSystem != null:
			var handle: Variant = ActionPresentationSystem.play({
				"actor": actor,
				"action_type": "move",
				"mode": "noncombat",
				"wait_for_presentation": false,
				"presentation_policy": "FULL_NONBLOCKING",
				"from_pos": from_pos,
				"to_pos": to_pos,
				"path": [to_pos]
			})
			if handle is Dictionary:
				presentation_job_id = str((handle as Dictionary).get("job_id", ""))

		TurnSystem.request_action(actor, TurnSystem.ACTION_TYPE_INTERACT, {
			"phase": TurnSystem.ACTION_PHASE_COMPLETE,
			"success": true
		})
		return {"performed": true, "presentation_job_id": presentation_job_id}

class AsyncDummyAIController extends Node:
	var performed_actions: int = 0

	func execute_turn_step() -> Dictionary:
		performed_actions += 1
		await get_tree().process_frame
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
		"turn_system_starts_initial_player_turn_on_registration",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_initial_player_turn_starts_on_registration
	)
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
		"turn_system_reopens_player_turn_after_noncombat_world_cycle",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_world_cycle_reopens_player_turn
	)
	runner.register_test(
		"turn_system_noncombat_world_cycle_does_not_wait_for_presentation_jobs",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_noncombat_world_cycle_does_not_wait_for_presentation
	)
	runner.register_test(
		"turn_system_awaits_async_actor_turn_steps",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_world_cycle_awaits_async_actor_turn_steps
	)
	runner.register_test(
		"turn_system_combat_waits_for_blocking_presentation_before_advancing_turn",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_combat_waits_for_blocking_presentation
	)
	runner.register_test(
		"turn_system_rejects_non_current_combat_actor_and_enforces_attack_limit",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_combat_turn_gating_and_attack_limit
	)
	runner.register_test(
		"turn_system_debug_console_command_toggles_overlay",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P2_NORMAL,
		_test_debug_console_command_toggles_overlay
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
	TurnSystem.set_actor_ap(player, 1.5)

	var start_result: Dictionary = TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_INTERACT, {
		"phase": TurnSystem.ACTION_PHASE_START
	})
	assert(bool(start_result.get("success", false)), "Player should be able to start an AP-governed action")
	assert(is_equal_approx(float(start_result.get("ap_before", 0.0)), 1.5), "An already-open player turn should expose the stored AP without adding another grant")

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

static func _test_initial_player_turn_starts_on_registration() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	TurnSystem.reset_runtime_state()

	var tree := _get_tree()
	var player := Node3D.new()
	player.name = "InitialTurnPlayer"
	player.add_to_group("player")
	tree.root.add_child(player)
	await tree.process_frame

	TurnSystem.register_group("player", 0)
	TurnSystem.register_actor(player, "player", "player")

	assert(is_equal_approx(TurnSystem.get_actor_ap(player), 1.0), "Registering the player should immediately open the first non-combat turn and grant 1 AP")
	assert(TurnSystem.get_actor_available_steps(player) == 1, "The opened initial turn should make one 1-AP action available immediately")

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

static func _test_world_cycle_reopens_player_turn() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	TurnSystem.reset_runtime_state()

	var tree := _get_tree()
	var player := Node3D.new()
	player.name = "ReopenPlayer"
	player.add_to_group("player")
	tree.root.add_child(player)
	await tree.process_frame

	TurnSystem.register_group("player", 0)
	TurnSystem.register_actor(player, "player", "player")

	var start_result: Dictionary = TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_INTERACT, {
		"phase": TurnSystem.ACTION_PHASE_START
	})
	assert(bool(start_result.get("success", false)), "Player should be able to start a non-combat action")
	TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_INTERACT, {
		"phase": TurnSystem.ACTION_PHASE_COMPLETE,
		"success": true
	})

	await tree.process_frame
	await tree.process_frame

	var snapshot: Dictionary = TurnSystem.get_debug_snapshot()
	var actor_entries: Array = snapshot.get("actors", [])
	var found_player_turn: bool = false
	for actor_entry_variant in actor_entries:
		var actor_entry: Dictionary = actor_entry_variant
		if actor_entry.get("actor", null) != player:
			continue
		found_player_turn = bool(actor_entry.get("turn_open", false))
		assert(is_equal_approx(float(actor_entry.get("ap", 0.0)), 1.0), "The reopened player turn should restore 1 AP after a successful non-combat action")
		break

	assert(found_player_turn, "The player turn should be reopened automatically after the non-combat world cycle finishes")

	player.queue_free()
	await tree.process_frame

static func _test_noncombat_world_cycle_does_not_wait_for_presentation() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	assert(ActionPresentationSystem != null, "ActionPresentationSystem autoload should exist")
	TurnSystem.reset_runtime_state()

	var tree := _get_tree()
	var player := Node3D.new()
	player.name = "NonBlockingPresentationPlayer"
	player.add_to_group("player")
	tree.root.add_child(player)

	var friendly := CharacterActorScript.new()
	friendly.name = "PresentingFriendly"
	var ai_controller := NonBlockingPresentationAIController.new()
	friendly.add_child(ai_controller)
	tree.root.add_child(friendly)
	await tree.process_frame
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

	assert(ai_controller.performed_actions == 1, "Friendly AI should still execute its non-combat turn")
	assert(not ai_controller.presentation_job_id.is_empty(), "The non-combat AI turn should submit a presentation job")
	assert(ActionPresentationSystem.is_job_pending(ai_controller.presentation_job_id), "The presentation job should still be running while the non-combat world cycle continues")
	assert(is_equal_approx(TurnSystem.get_actor_ap(player), 1.0), "The player should already have their next non-combat turn while the AI presentation is still playing")

	await tree.create_timer(0.35).timeout

	assert(not ActionPresentationSystem.is_job_pending(ai_controller.presentation_job_id), "The non-combat presentation job should eventually complete in the background")

	friendly.queue_free()
	player.queue_free()
	await tree.process_frame

static func _test_world_cycle_awaits_async_actor_turn_steps() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	TurnSystem.reset_runtime_state()

	var tree := _get_tree()
	var player := Node3D.new()
	player.name = "AsyncWorldCyclePlayer"
	player.add_to_group("player")
	tree.root.add_child(player)

	var friendly := Node3D.new()
	friendly.name = "AsyncFriendlyDummy"
	var ai_controller := AsyncDummyAIController.new()
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
	assert(bool(start_result.get("success", false)), "Player should be able to start the non-combat cycle for async AI turns")
	TurnSystem.request_action(player, TurnSystem.ACTION_TYPE_INTERACT, {
		"phase": TurnSystem.ACTION_PHASE_COMPLETE,
		"success": true
	})

	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	assert(ai_controller.performed_actions == 1, "The registered friendly actor should complete an async world-cycle turn after the player's action")
	assert(is_equal_approx(TurnSystem.get_actor_ap(friendly), 0.0), "The async friendly actor should consume its granted AP during the auto turn")

	friendly.queue_free()
	player.queue_free()
	await tree.process_frame

static func _test_combat_waits_for_blocking_presentation() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	assert(CombatSystem != null, "CombatSystem autoload should exist")
	TurnSystem.reset_runtime_state()
	CombatSystem._action_in_progress = false
	CombatSystem._runtime_actor_states.clear()

	var tree := _get_tree()
	var player := PlayerControllerScript.new()
	player.name = "PresentationCombatPlayer"
	tree.root.add_child(player)
	await tree.process_frame
	await tree.process_frame

	var hostile := CharacterActorScript.new()
	hostile.name = "PresentationCombatHostile"
	tree.root.add_child(hostile)
	await tree.process_frame

	TurnSystem.register_group("hostile:presentation", 100)
	TurnSystem.register_actor(hostile, "hostile:presentation", "hostile")
	CombatSystem._runtime_actor_states[str(hostile.get_instance_id())] = {
		"id": "presentation_hostile",
		"name": "Presentation Hostile",
		"stats": {
			"hp": 50,
			"max_hp": 50,
			"damage": 1,
			"defense": 0,
			"speed": 1,
			"accuracy": 60,
			"crit_chance": 0.0,
			"crit_damage": 1.5
		},
		"current_hp": 50,
		"behavior": "hostile",
		"loot": [],
		"xp": 0
	}

	TurnSystem.enter_combat(player, hostile)
	assert(TurnSystem.is_actor_current_turn(player), "The player should own the first combat turn")

	var attack_result: Dictionary = CombatSystem.perform_attack(player, hostile)
	assert(bool(attack_result.get("success", false)), "The combat attack should resolve successfully")
	assert(TurnSystem.is_actor_current_turn(player), "Combat turn advance should wait until the blocking presentation finishes")

	await tree.create_timer(0.35).timeout

	assert(TurnSystem.is_actor_current_turn(hostile), "After the blocking presentation completes, combat should advance to the next actor")

	TurnSystem.force_end_combat()
	hostile.queue_free()
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

static func _test_debug_console_command_toggles_overlay() -> void:
	assert(TurnSystem != null, "TurnSystem autoload should exist")
	assert(DebugModule != null, "DebugModule autoload should exist")
	TurnSystem.reset_runtime_state()

	var off_result: Dictionary = DebugModule.execute_command("turn_debug off")
	assert(bool(off_result.get("success", false)), "turn_debug off should execute successfully")
	assert(not TurnSystem.is_debug_visible(), "turn_debug off should hide the TurnSystem debug overlay")

	var on_result: Dictionary = DebugModule.execute_command("turn_debug on")
	assert(bool(on_result.get("success", false)), "turn_debug on should execute successfully")
	assert(TurnSystem.is_debug_visible(), "turn_debug on should show the TurnSystem debug overlay")

	var status_result: Dictionary = DebugModule.get_debug_variable("turn.debug_visible")
	assert(bool(status_result.get("success", false)), "The TurnSystem debug visibility variable should be registered")
	assert(bool(status_result.get("value", false)), "The debug visibility variable should reflect the command result")

	DebugModule.execute_command("turn_debug off")

static func _get_tree() -> SceneTree:
	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	return loop as SceneTree
