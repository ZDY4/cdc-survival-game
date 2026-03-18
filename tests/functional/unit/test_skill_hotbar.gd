extends Node
class_name FunctionalTest_SkillHotbar

class SkillHotbarTestFixture extends RefCounted:
	var module: Node = null
	var snapshot: Dictionary = {}

	func setup() -> void:
		module = _get_skill_module()
		assert(module != null, "SkillModule autoload should exist")
		snapshot = module.serialize()
		module.reset_skills()
		module.set_skill_points(20)
		assert(module.learn_skill("combat"), "combat should be learnable in fixture")
		assert(module.learn_skill("adrenaline_rush"), "adrenaline_rush should be learnable in fixture")
		assert(module.learn_skill("survival"), "survival should be learnable in fixture")
		assert(module.learn_skill("low_profile"), "low_profile should be learnable in fixture")

	func teardown() -> void:
		if module != null:
			module.deserialize(snapshot)

	static func _get_skill_module() -> Node:
		var loop := Engine.get_main_loop()
		if not (loop is SceneTree):
			return null
		var tree: SceneTree = loop
		if tree.root == null:
			return null
		return tree.root.get_node_or_null("SkillModule")


static func run_tests(runner: TestRunner) -> void:
	var fixture := SkillHotbarTestFixture.new()
	runner.register_test(
		"skill_hotbar_enforces_eligibility_and_group_rules",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		func() -> void:
			_test_hotbar_assignment_rules(fixture),
		Callable(fixture, "setup"),
		Callable(fixture, "teardown")
	)
	runner.register_test(
		"skill_hotbar_activation_and_serialize_restore_runtime_state",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		func() -> void:
			_test_hotbar_activation_serialize(fixture),
		Callable(fixture, "setup"),
		Callable(fixture, "teardown")
	)


static func _test_hotbar_assignment_rules(fixture: SkillHotbarTestFixture) -> void:
	var module := fixture.module
	assert(module != null, "Fixture should provide SkillModule")

	var passive_result: Dictionary = module.assign_skill_to_hotbar("combat", 0, 0)
	assert(not bool(passive_result.get("success", false)), "Passive skill should not be assignable to hotbar")

	var adrenaline_result: Dictionary = module.assign_skill_to_hotbar("adrenaline_rush", 0, 0)
	assert(bool(adrenaline_result.get("success", false)), "Active skill should be assignable to hotbar")
	var toggle_result: Dictionary = module.assign_skill_to_hotbar("low_profile", 0, 1)
	assert(bool(toggle_result.get("success", false)), "Toggle skill should be assignable to hotbar")

	var move_result: Dictionary = module.assign_skill_to_hotbar("adrenaline_rush", 0, 1)
	assert(bool(move_result.get("success", false)), "Reassigning same skill in same group should move/swap it")
	assert(str(module.get_hotbar_groups()[0][0]) == "low_profile", "Occupied target should swap with existing slot")
	assert(str(module.get_hotbar_groups()[0][1]) == "adrenaline_rush", "Moved skill should end up in target slot")

	assert(int(module.cycle_hotbar_group(1)) == 1, "Hotbar group should cycle forward")
	var second_group_result: Dictionary = module.assign_skill_to_hotbar("adrenaline_rush", 1, 0)
	assert(bool(second_group_result.get("success", false)), "Same skill should be reusable in another group")


static func _test_hotbar_activation_serialize(fixture: SkillHotbarTestFixture) -> void:
	var module := fixture.module
	assert(module != null, "Fixture should provide SkillModule")
	var effect_system := _get_autoload("EffectSystem")
	assert(effect_system != null, "EffectSystem autoload should exist")

	assert(bool(module.assign_skill_to_hotbar("adrenaline_rush", 0, 0).get("success", false)), "Should assign adrenaline_rush")
	assert(bool(module.assign_skill_to_hotbar("low_profile", 0, 1).get("success", false)), "Should assign low_profile")

	var active_result: Dictionary = module.activate_hotbar_slot(0)
	assert(bool(active_result.get("success", false)), "Active skill should trigger from hotbar")
	assert(float(module.get_skill_cooldown_remaining("adrenaline_rush")) > 0.0, "Active skill should start cooldown")
	assert(effect_system.has_effect("skill_activation_adrenaline_rush", "player"), "Active effect should be applied to player")

	var toggle_result: Dictionary = module.activate_hotbar_slot(1)
	assert(bool(toggle_result.get("success", false)), "Toggle skill should trigger from hotbar")
	assert(bool(module.is_skill_toggle_active("low_profile")), "Toggle skill should remain active")
	assert(effect_system.has_effect("skill_activation_low_profile", "player"), "Toggle effect should be applied to player")

	var serialized: Dictionary = module.serialize()
	module.reset_skills()
	module.deserialize(serialized)

	var groups: Array = module.get_hotbar_groups()
	assert(str(groups[0][0]) == "adrenaline_rush", "Serialized hotbar should restore active skill slot")
	assert(str(groups[0][1]) == "low_profile", "Serialized hotbar should restore toggle skill slot")
	assert(float(module.get_skill_cooldown_remaining("adrenaline_rush")) > 0.0, "Cooldown should restore from serialization")
	assert(bool(module.is_skill_toggle_active("low_profile")), "Toggle active state should restore from serialization")
	assert(effect_system.has_effect("skill_activation_low_profile", "player"), "Toggle effect should reapply after deserialize")


static func _get_autoload(node_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree: SceneTree = loop
	if tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
