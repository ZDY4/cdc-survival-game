extends Node
class_name FunctionalTest_InteractionAttackOption

const InteractableSceneScript = preload("res://modules/interaction/interactable.gd")
const AttackInteractionOptionScript = preload("res://modules/interaction/options/attack_interaction_option.gd")
const CharacterRelationResolverScript = preload("res://systems/character_relation_resolver.gd")

static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"interaction_attack_option_neutral_sorts_last_and_marks_dangerous",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_neutral_attack_option_behavior
	)

	runner.register_test(
		"interaction_attack_option_hostile_sorts_first_and_uses_normal_color",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_hostile_attack_option_behavior
	)

	runner.register_test(
		"interaction_attack_option_reacts_to_relation_meta_changes",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_attack_option_reacts_to_relation_changes
	)

	runner.register_test(
		"character_relation_resolver_respects_forced_hostile_override",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_forced_hostile_override
	)

static func _test_neutral_attack_option_behavior() -> void:
	var fixture := _build_interactable_fixture("neutral")
	var interactable: Interactable = fixture["interactable"]
	var options: Array = interactable.get_available_options()
	assert(options.size() == 2, "Neutral fixture should expose talk and attack")
	assert(str(options[0].option_id) == "talk", "Neutral target should keep talk as primary interaction")

	var attack_option: AttackInteractionOption = _find_option(options, "attack") as AttackInteractionOption
	assert(attack_option != null, "Attack option should be present for neutral targets")
	assert(attack_option.is_dangerous(interactable), "Neutral attack option should be marked dangerous")
	assert(attack_option.get_display_color(interactable).a > 0.0, "Neutral attack option should expose a custom warning color")
	_cleanup_fixture(fixture)

static func _test_hostile_attack_option_behavior() -> void:
	var fixture := _build_interactable_fixture("hostile")
	var interactable: Interactable = fixture["interactable"]
	var options: Array = interactable.get_available_options()
	assert(options.size() >= 1, "Hostile fixture should expose at least the attack option")
	assert(str(options[0].option_id) == "attack", "Hostile target should promote attack to primary interaction")

	var attack_option: AttackInteractionOption = _find_option(options, "attack") as AttackInteractionOption
	assert(attack_option != null, "Attack option should exist for hostile targets")
	assert(not attack_option.is_dangerous(interactable), "Hostile attack option should no longer be marked dangerous")
	assert(attack_option.get_display_color(interactable).a == 0.0, "Hostile attack option should use the normal menu color")
	_cleanup_fixture(fixture)

static func _test_attack_option_reacts_to_relation_changes() -> void:
	var fixture := _build_interactable_fixture("neutral")
	var interactable: Interactable = fixture["interactable"]
	var actor: Node3D = fixture["actor"]
	var hostile_relation := _build_relation_result("hostile")
	actor.set_meta("relation_result", hostile_relation.duplicate(true))
	actor.set_meta("resolved_attitude", "hostile")
	interactable.set_meta("relation_result", hostile_relation.duplicate(true))
	interactable.set_meta("resolved_attitude", "hostile")

	var options: Array = interactable.get_available_options()
	assert(str(options[0].option_id) == "attack", "Changing relation_result to hostile should immediately reprioritize attack")
	_cleanup_fixture(fixture)

static func _test_forced_hostile_override() -> void:
	assert(GameStateManager != null, "GameStateManager autoload should exist for relation override tests")
	var character_id := "test_forced_hostile_npc"
	var resolver := CharacterRelationResolverScript.new()
	var character_data := {
		"identity": {"camp_id": "survivor"},
		"social": {}
	}

	GameStateManager.set_character_hostile(character_id, true)
	var hostile_result := resolver.resolve_for_player(character_id, character_data)
	assert(str(hostile_result.get("resolved_attitude", "")) == "hostile", "Forced hostile override should force hostile attitude")
	assert(bool(hostile_result.get("allow_attack", false)), "Forced hostile override should allow attack")

	GameStateManager.set_character_hostile(character_id, false)
	var neutral_result := resolver.resolve_for_player(character_id, character_data)
	assert(str(neutral_result.get("resolved_attitude", "")) != "hostile", "Clearing hostile override should restore normal relation resolution")

static func _build_interactable_fixture(attitude: String) -> Dictionary:
	var actor := Node3D.new()
	actor.set_meta("character_id", "doctor_chen")
	actor.set_meta("relation_result", _build_relation_result(attitude))
	actor.set_meta("resolved_attitude", attitude)

	var interactable := InteractableSceneScript.new()
	interactable.set_meta("character_id", "doctor_chen")
	interactable.set_meta("relation_result", _build_relation_result(attitude))
	interactable.set_meta("resolved_attitude", attitude)
	actor.add_child(interactable)

	var talk_option := InteractionOption.new()
	talk_option.option_id = "talk"
	talk_option.display_name = "交谈"
	talk_option.priority = 800
	var attack_option := AttackInteractionOptionScript.new()
	attack_option.enemy_id = "doctor_chen"
	attack_option.enemy_name = "陈医生"
	interactable.set_options([attack_option, talk_option])

	return {
		"actor": actor,
		"interactable": interactable
	}

static func _build_relation_result(attitude: String) -> Dictionary:
	return {
		"resolved_attitude": attitude,
		"allow_attack": attitude == "hostile",
		"allow_interaction": attitude != "hostile",
		"allow_trade": false
	}

static func _find_option(options: Array, option_id: String) -> InteractionOption:
	for option in options:
		var interaction_option := option as InteractionOption
		if interaction_option != null and interaction_option.option_id == option_id:
			return interaction_option
	return null

static func _cleanup_fixture(fixture: Dictionary) -> void:
	var actor: Node = fixture.get("actor", null)
	if actor != null:
		actor.free()
