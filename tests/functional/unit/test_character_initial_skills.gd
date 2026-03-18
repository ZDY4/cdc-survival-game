extends Node
class_name FunctionalTest_CharacterInitialSkills

const CharacterSkillRuntimeScript = preload("res://systems/character_skill_runtime.gd")
const CharacterDataEditorScript = preload("res://addons/cdc_game_editor/editors/character_data_editor/character_data_editor.gd")
const AIControllerScript = preload("res://systems/ai/ai_controller.gd")


static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"character_data_round_trip_preserves_initial_skills",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_character_data_round_trip
	)
	runner.register_test(
		"character_editor_initial_skills_enforce_prerequisites",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_character_editor_initial_skills
	)
	runner.register_test(
		"character_skill_runtime_applies_initial_effects_and_ai_uses_active_skill",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_character_skill_runtime_and_ai
	)


static func _test_character_data_round_trip() -> void:
	var data := CharacterData.new()
	data.deserialize({
		"id": "test_actor",
		"name": "测试敌人",
		"skills": {
			"initial_tree_ids": ["combat", "survival"],
			"initial_skills_by_tree": {
				"combat": ["combat", "adrenaline_rush"],
				"survival": ["survival", "low_profile"]
			}
		}
	})

	var serialized: Dictionary = data.serialize()
	assert(serialized.has("skills"), "CharacterData serialization should include skills block")
	assert(
		serialized["skills"]["initial_tree_ids"] == ["combat", "survival"],
		"CharacterData should preserve selected initial tree ids"
	)
	assert(
		serialized["skills"]["initial_skills_by_tree"]["combat"] == ["combat", "adrenaline_rush"],
		"CharacterData should preserve initial unlocked combat skills"
	)
	assert(
		serialized["skills"]["initial_skills_by_tree"]["survival"] == ["survival", "low_profile"],
		"CharacterData should preserve initial unlocked survival skills"
	)


static func _test_character_editor_initial_skills() -> void:
	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	var tree: SceneTree = loop

	var editor := CharacterDataEditorScript.new()
	tree.root.add_child(editor)
	await tree.process_frame

	var record: Dictionary = editor._create_default_character("editor_initial_skills_test")
	editor.characters.clear()
	editor.characters[record["id"]] = record
	editor._update_character_list()
	editor._select_character(record["id"])
	await tree.process_frame

	editor._on_initial_tree_toggled(true, "combat")
	await tree.process_frame

	var adrenaline_checkbox := editor._skill_checkbox_map.get("combat::adrenaline_rush", null) as CheckBox
	assert(adrenaline_checkbox != null, "Selecting the combat tree should build combat skill checkboxes")
	assert(adrenaline_checkbox.disabled, "Downstream combat skill should stay disabled until its prerequisite is selected")

	editor._on_initial_skill_toggled(true, "combat", "combat")
	await tree.process_frame

	adrenaline_checkbox = editor._skill_checkbox_map.get("combat::adrenaline_rush", null) as CheckBox
	assert(adrenaline_checkbox != null, "Combat skill checkbox should remain available after refresh")
	assert(not adrenaline_checkbox.disabled, "Unlocking the prerequisite should enable the downstream skill checkbox")

	editor._on_initial_skill_toggled(true, "combat", "adrenaline_rush")
	await tree.process_frame
	assert(editor.get_validation_errors().is_empty(), "A valid prerequisite chain should pass editor validation")

	editor._on_initial_skill_toggled(false, "combat", "combat")
	await tree.process_frame

	var stored_skills: Dictionary = editor.characters[record["id"]]["skills"]
	var combat_skills: Array[String] = stored_skills["initial_skills_by_tree"].get("combat", [])
	assert(not combat_skills.has("adrenaline_rush"), "Removing a prerequisite should automatically remove dependent initial skills")

	editor.queue_free()
	await tree.process_frame


static func _test_character_skill_runtime_and_ai() -> void:
	assert(SkillModule != null, "SkillModule autoload should exist")
	assert(EffectSystem != null, "EffectSystem autoload should exist")
	assert(CombatSystem != null, "CombatSystem autoload should exist")

	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	var tree: SceneTree = loop

	var actor := Node3D.new()
	actor.name = "RuntimeSkillActor"
	actor.set_meta("character_id", "runtime_skill_test")
	tree.root.add_child(actor)

	var runtime := CharacterSkillRuntimeScript.new()
	runtime.name = "CharacterSkillRuntime"
	actor.add_child(runtime)
	runtime.initialize(
		actor,
		"runtime_skill_spawn",
		{
			"initial_tree_ids": ["combat", "survival"],
			"initial_skills_by_tree": {
				"combat": ["combat", "adrenaline_rush"],
				"survival": ["survival", "low_profile"]
			}
		},
		SkillModule,
		EffectSystem
	)

	var entity_id: String = runtime.get_entity_id()
	assert(EffectSystem.has_effect("character_skill_combat", entity_id), "Initial passive skill should apply immediately")
	assert(EffectSystem.has_effect("character_skill_toggle_low_profile", entity_id), "Initial toggle skill should auto-activate on spawn")

	CombatSystem._runtime_actor_states[str(actor.get_instance_id())] = {
		"id": "runtime_skill_test",
		"name": "Runtime Skill Test",
		"stats": {
			"hp": 30,
			"max_hp": 30,
			"damage": 20,
			"defense": 2,
			"speed": 5,
			"accuracy": 70,
			"crit_chance": 0.1,
			"crit_damage": 1.5,
			"evasion": 0.05
		},
		"current_hp": 30,
		"behavior": "aggressive",
		"loot": [],
		"xp": 10
	}

	var passive_stats: Dictionary = CombatSystem._get_effective_actor_stats(actor)
	assert(int(passive_stats.get("damage", 0)) > 20, "Passive combat bonuses should affect actor combat stats")

	var player := Node3D.new()
	player.name = "RuntimeSkillTarget"
	player.add_to_group("player")
	player.position = Vector3(0.5, 0.0, 0.0)
	tree.root.add_child(player)

	var ai_controller := AIControllerScript.new()
	actor.add_child(ai_controller)
	ai_controller.initialize(actor, Node.new(), Vector3.ZERO, "runtime_skill_test", {"allow_attack": true}, runtime)
	actor.position = Vector3.ZERO

	var step_result: Dictionary = await ai_controller.execute_turn_step()
	assert(bool(step_result.get("performed", false)), "AI attack step should perform an action when an active skill is available")
	assert(str(step_result.get("type", "")) == "skill", "AI should spend its attack step on the active skill before normal attacks")
	assert(EffectSystem.has_effect("character_skill_active_adrenaline_rush", entity_id), "AI-triggered active skill should apply its runtime effect")

	var active_stats: Dictionary = CombatSystem._get_effective_actor_stats(actor)
	assert(
		int(active_stats.get("damage", 0)) > int(passive_stats.get("damage", 0)),
		"Active skill bonuses should further increase runtime combat stats"
	)

	actor.queue_free()
	player.queue_free()
	await tree.process_frame

	assert(not EffectSystem.has_effect("character_skill_combat", entity_id), "Actor cleanup should remove passive runtime skill effects")
	assert(not EffectSystem.has_effect("character_skill_toggle_low_profile", entity_id), "Actor cleanup should remove toggle runtime skill effects")
	CombatSystem._runtime_actor_states.erase(str(actor.get_instance_id()))
