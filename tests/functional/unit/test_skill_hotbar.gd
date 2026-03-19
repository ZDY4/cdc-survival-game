extends Node
class_name FunctionalTest_SkillHotbar

class SkillHotbarTestFixture extends RefCounted:
	var module: Node = null
	var snapshot: Dictionary = {}
	var player_anchor: Node3D = null
	const TARGETED_SKILL_ID: String = "targeted_test_skill"

	func setup() -> void:
		module = _get_skill_module()
		assert(module != null, "SkillModule autoload should exist")
		snapshot = module.serialize()
		_ensure_player_anchor()
		module.reset_skills()
		module.set_skill_points(20)
		assert(module.learn_skill("combat"), "combat should be learnable in fixture")
		assert(module.learn_skill("adrenaline_rush"), "adrenaline_rush should be learnable in fixture")
		assert(module.learn_skill("survival"), "survival should be learnable in fixture")
		assert(module.learn_skill("low_profile"), "low_profile should be learnable in fixture")
		_register_targeted_skill()

	func teardown() -> void:
		if module != null:
			module.deserialize(snapshot)
		if player_anchor != null and is_instance_valid(player_anchor):
			player_anchor.queue_free()
			player_anchor = null

	func _ensure_player_anchor() -> void:
		var loop := Engine.get_main_loop()
		assert(loop is SceneTree, "Main loop should be a SceneTree")
		var tree: SceneTree = loop
		player_anchor = Node3D.new()
		player_anchor.name = "SkillHotbarTestPlayer"
		player_anchor.add_to_group("player")
		player_anchor.position = Vector3(0.5, 0.0, 0.5)
		tree.root.add_child(player_anchor)

	func _register_targeted_skill() -> void:
		assert(module != null, "SkillModule should exist before registering targeted skill")
		var skill_definition: Dictionary = module._normalize_skill(TARGETED_SKILL_ID, {
			"name": "战术专注",
			"tree_id": "combat",
			"max_level": 1,
			"prerequisites": ["combat"],
			"activation": {
				"mode": "active",
				"cooldown": 6.0,
				"effect": {
					"duration": 4.0,
					"is_infinite": false,
					"category": "buff",
					"modifiers": {
						"damage_bonus": {
							"base": 0.10
						}
					}
				},
				"targeting": {
					"enabled": true,
					"range_cells": 3,
					"shape": "single",
					"radius": 0,
					"handler_script": ""
				}
			}
		})
		module._skills[TARGETED_SKILL_ID] = skill_definition
		module.learned_skills[TARGETED_SKILL_ID] = 1

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
	runner.register_test(
		"skill_hotbar_targeted_skill_waits_for_confirm_before_cooldown",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		func() -> void:
			_test_targeted_skill_activation_flow(fixture),
		Callable(fixture, "setup"),
		Callable(fixture, "teardown")
	)
	runner.register_test(
		"skill_hotbar_layout_is_bottom_aligned_and_slots_are_square",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P2_MINOR,
		_test_hotbar_layout_geometry
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


static func _test_targeted_skill_activation_flow(fixture: SkillHotbarTestFixture) -> void:
	var module := fixture.module
	assert(module != null, "Fixture should provide SkillModule")
	var effect_system := _get_autoload("EffectSystem")
	assert(effect_system != null, "EffectSystem autoload should exist")
	assert(bool(module.assign_skill_to_hotbar(fixture.TARGETED_SKILL_ID, 0, 2).get("success", false)), "Targeted skill should be assignable")

	var activation_result: Dictionary = module.activate_hotbar_slot(2)
	assert(bool(activation_result.get("success", false)), "Targeted skill should start targeting from hotbar")
	assert(str(activation_result.get("state", "")) == "targeting_started", "Targeted skill should enter targeting state instead of firing immediately")
	assert(is_zero_approx(module.get_skill_cooldown_remaining(fixture.TARGETED_SKILL_ID)), "Targeted skill should not enter cooldown before confirm")
	assert(not effect_system.has_effect("skill_activation_%s" % fixture.TARGETED_SKILL_ID, "player"), "Targeted skill effect should not apply before confirm")

	var handler: TargetSkillBase = module.get_targeted_skill_handler(fixture.TARGETED_SKILL_ID)
	assert(handler != null, "Targeted skill should expose a targeting handler")
	var preview: Dictionary = handler.build_preview(
		fixture.player_anchor,
		Vector3i(1, 0, 0),
		{
			"caster": fixture.player_anchor,
			"skill_id": fixture.TARGETED_SKILL_ID,
			"handler": handler
		}
	)
	assert(bool(preview.get("valid", false)), "Preview should be valid inside targeting range")

	var cast_result: Dictionary = module.cast_targeted_skill(fixture.TARGETED_SKILL_ID, preview)
	assert(bool(cast_result.get("success", false)), "Targeted skill should cast after confirm")
	assert(float(module.get_skill_cooldown_remaining(fixture.TARGETED_SKILL_ID)) > 0.0, "Cooldown should start only after confirm")
	assert(effect_system.has_effect("skill_activation_%s" % fixture.TARGETED_SKILL_ID, "player"), "Targeted skill effect should apply after confirm")


static func _test_hotbar_layout_geometry() -> void:
	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	var tree: SceneTree = loop

	var hotbar := SkillHotbar.new()
	tree.root.add_child(hotbar)
	await tree.process_frame
	await tree.process_frame

	var viewport_size: Vector2 = tree.root.get_viewport().get_visible_rect().size
	var hotbar_rect: Rect2 = hotbar.get_global_rect()
	assert(absf(hotbar_rect.end.y - viewport_size.y) <= 1.0, "Hotbar should stay attached to the bottom edge")
	assert(absf(hotbar.offset_bottom) <= 0.01, "Hotbar bottom offset should be flush with the screen edge")

	for slot_variant in hotbar._slots:
		var slot: SkillHotbarSlot = slot_variant
		assert(
			absf(slot.custom_minimum_size.x - slot.custom_minimum_size.y) <= 0.01,
			"Each hotbar slot minimum size should stay square"
		)
		assert(absf(slot.size.x - slot.size.y) <= 1.0, "Each hotbar slot should render as a square")

	hotbar.queue_free()
	await tree.process_frame


static func _get_autoload(node_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree: SceneTree = loop
	if tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
