extends Node
class_name FunctionalTest_CdcAiGeneration

const ITEM_EDITOR_SCRIPT := preload("res://addons/cdc_game_editor/editors/item_editor/item_editor.gd")
const CHARACTER_EDITOR_SCRIPT := preload("res://addons/cdc_game_editor/editors/character_data_editor/character_data_editor.gd")
const DIALOG_EDITOR_SCRIPT := preload("res://addons/cdc_game_editor/editors/dialog_editor/dialog_editor.gd")
const QUEST_EDITOR_SCRIPT := preload("res://addons/cdc_game_editor/editors/quest_editor/quest_editor.gd")
const AI_PANEL_SCRIPT := preload("res://addons/cdc_game_editor/ai/ai_generate_panel.gd")
const FAKE_PROVIDER_SCRIPT := preload("res://addons/cdc_game_editor/ai/providers/fake_ai_provider.gd")
const REPOSITORY_SCRIPT := preload("res://addons/cdc_game_editor/ai/editor_data_repository.gd")
const CONTEXT_BUILDER_SCRIPT := preload("res://addons/cdc_game_editor/ai/context_builder.gd")
const PROVIDER_SCRIPT := preload("res://addons/cdc_game_editor/ai/providers/openai_compatible_provider.gd")
const CHARACTER_ADAPTER_SCRIPT := preload("res://addons/cdc_game_editor/ai/adapters/character_ai_editor_adapter.gd")
const DIALOG_ADAPTER_SCRIPT := preload("res://addons/cdc_game_editor/ai/adapters/dialog_ai_editor_adapter.gd")


static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"cdc_ai_context_builder_loads_editor_data",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_context_builder_loads_editor_data
	)
	runner.register_test(
		"cdc_ai_provider_parses_json_and_http_errors",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_provider_parsing_helpers
	)
	runner.register_test(
		"cdc_ai_item_panel_generates_and_applies_draft",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_item_panel_generates_and_applies_draft
	)
	runner.register_test(
		"cdc_ai_character_validation_rejects_invalid_skill_setup",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_character_validation_rejects_invalid_skill_setup
	)
	runner.register_test(
		"cdc_ai_dialog_validation_rejects_inconsistent_connections",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_dialog_validation_rejects_inconsistent_connections
	)
	runner.register_test(
		"cdc_ai_quest_validation_rejects_missing_end_and_bad_refs",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_quest_validation_rejects_missing_end_and_bad_refs
	)
	runner.register_test(
		"cdc_ai_panel_diff_preview_marks_high_risk_revise_changes",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_panel_diff_preview_marks_high_risk_revise_changes
	)
	runner.register_test(
		"cdc_ai_panel_rejects_empty_record_draft",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_panel_rejects_empty_record_draft
	)
	runner.register_test(
		"cdc_ai_context_builder_prioritizes_relevant_examples_and_emits_refs",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_context_builder_prioritizes_relevant_examples_and_emits_refs
	)
	runner.register_test(
		"cdc_ai_adapters_summarize_structural_changes",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_adapters_summarize_structural_changes
	)


static func _test_context_builder_loads_editor_data() -> void:
	var repository := REPOSITORY_SCRIPT.new()
	var context_builder := CONTEXT_BUILDER_SCRIPT.new(repository)
	var context := context_builder.build_context(
		"item",
		{
			"mode": "create",
			"target_id": "",
			"current_record": {}
		},
		{},
		12
	)
	assert(not context.is_empty(), "Context should not be empty")
	assert(context.get("project_counts", {}).has("items"), "Context should include item counts")
	assert(context.get("same_type_index", []).size() > 0, "Context should include same-type index")
	assert(context.get("related_indexes", {}).has("effects"), "Context should include related indexes")


static func _test_provider_parsing_helpers() -> void:
	var direct := PROVIDER_SCRIPT.extract_json_payload("{\"record_type\":\"item\",\"record\":{}}")
	assert(bool(direct.get("ok", false)), "Direct JSON payload should parse")

	var wrapped := PROVIDER_SCRIPT.extract_json_payload("Answer:\n{\"record_type\":\"item\",\"record\":{}}\nDone")
	assert(bool(wrapped.get("ok", false)), "Wrapped JSON payload should parse")

	var invalid := PROVIDER_SCRIPT.extract_json_payload("no json here")
	assert(not bool(invalid.get("ok", false)), "Invalid payload should fail")

	var mapped := PROVIDER_SCRIPT.map_http_error(401, "")
	assert(mapped.contains("401"), "HTTP error mapping should preserve status code")


static func _test_item_panel_generates_and_applies_draft() -> void:
	var editor: Control = ITEM_EDITOR_SCRIPT.new()
	Engine.get_main_loop().root.add_child(editor)
	await Engine.get_main_loop().process_frame

	var fake_provider = FAKE_PROVIDER_SCRIPT.new()
	Engine.get_main_loop().root.add_child(fake_provider)
	fake_provider.enqueue_response({
		"ok": true,
		"data": {
			"record_type": "item",
			"operation": "create",
			"target_id": "",
			"summary": "生成了一个测试用医疗物品",
			"warnings": [],
			"record": {
				"id": 999001,
				"name": "测试医疗包",
				"description": "用于测试 AI 编辑器流程。",
				"type": "consumable",
				"rarity": "common",
				"weight": 0.2,
				"value": 25,
				"stackable": true,
				"max_stack": 10,
				"icon_path": "res://assets/images/items/bandage.png",
				"equippable": false,
				"level_requirement": 0,
				"durability": -1,
				"max_durability": -1,
				"repairable": false,
				"usable": true,
				"consumable_data": {
					"hp_restore": 10,
					"stamina_restore": 0,
					"duration": 0
				},
				"special_effects": [],
				"attributes_bonus": {}
			}
		}
	})

	var panel: Window = AI_PANEL_SCRIPT.new()
	Engine.get_main_loop().root.add_child(panel)
	await Engine.get_main_loop().process_frame
	panel.configure(editor, null, "item", fake_provider)
	panel._main_prompt_input.text = "生成一个测试物品"
	await panel._run_generation(false)

	assert(not panel._current_draft.is_empty(), "Panel should store generated draft")
	assert(panel._validation_output.text == "校验通过", "Draft should pass validation")

	var applied := editor.apply_ai_draft(panel._current_draft)
	assert(applied, "Draft should apply successfully")
	assert(editor.items.has("999001"), "Applied item should exist in editor data")

	panel.queue_free()
	fake_provider.queue_free()
	editor.queue_free()
	await Engine.get_main_loop().process_frame


static func _test_character_validation_rejects_invalid_skill_setup() -> void:
	var editor: Control = CHARACTER_EDITOR_SCRIPT.new()
	Engine.get_main_loop().root.add_child(editor)
	await Engine.get_main_loop().process_frame

	var errors := editor.get_ai_validation_errors({
		"record_type": "character",
		"operation": "create",
		"target_id": "",
		"record": {
			"id": "ai_invalid_character",
			"name": "测试角色",
			"description": "",
			"level": 1,
			"identity": {"camp_id": "neutral"},
			"visual": {},
			"combat": {"stats": {}, "ai": {}, "behavior": "neutral", "loot": [], "xp": 0},
			"social": {"title": "", "dialog_id": "", "mood": {}},
			"skills": {
				"initial_tree_ids": ["survival"],
				"initial_skills_by_tree": {
					"survival": ["not_existing_skill"]
				}
			}
		}
	})
	assert(not errors.is_empty(), "Invalid character skill setup should fail validation")

	editor.queue_free()
	await Engine.get_main_loop().process_frame


static func _test_dialog_validation_rejects_inconsistent_connections() -> void:
	var editor: Control = DIALOG_EDITOR_SCRIPT.new()
	Engine.get_main_loop().root.add_child(editor)
	await Engine.get_main_loop().process_frame

	var errors := editor.get_ai_validation_errors({
		"record_type": "dialog",
		"operation": "create",
		"target_id": "",
		"record": {
			"dialog_id": "ai_invalid_dialog",
			"nodes": [
				{
					"id": "start",
					"type": "dialog",
					"title": "Start",
					"speaker": "NPC",
					"text": "hello",
					"is_start": true,
					"next": "end_1"
				},
				{
					"id": "end_1",
					"type": "end",
					"end_type": "normal"
				}
			],
			"connections": []
		}
	})
	assert(not errors.is_empty(), "Dialog with inconsistent next/connections should fail validation")

	editor.queue_free()
	await Engine.get_main_loop().process_frame


static func _test_quest_validation_rejects_missing_end_and_bad_refs() -> void:
	var editor: Control = QUEST_EDITOR_SCRIPT.new()
	Engine.get_main_loop().root.add_child(editor)
	await Engine.get_main_loop().process_frame

	var errors := editor.get_ai_validation_errors({
		"record_type": "quest",
		"operation": "create",
		"target_id": "",
		"record": {
			"quest_id": "ai_invalid_quest",
			"title": "测试任务",
			"description": "用于测试 AI 校验。",
			"prerequisites": [],
			"time_limit": -1,
			"flow": {
				"start_node_id": "start",
				"nodes": {
					"start": {
						"id": "start",
						"type": "start",
						"position": {"x": 120, "y": 160}
					},
					"step_1": {
						"id": "step_1",
						"type": "objective",
						"position": {"x": 420, "y": 160},
						"objective_type": "collect",
						"description": "拾取不存在的物品",
						"item_id": 999999,
						"count": 1
					}
				},
				"connections": [
					{"from": "start", "to": "step_1", "from_port": 0, "to_port": 0}
				]
			}
		}
	})
	assert(not errors.is_empty(), "Quest missing end node and valid refs should fail validation")

	editor.queue_free()
	await Engine.get_main_loop().process_frame


static func _test_panel_diff_preview_marks_high_risk_revise_changes() -> void:
	var editor: Control = ITEM_EDITOR_SCRIPT.new()
	Engine.get_main_loop().root.add_child(editor)
	await Engine.get_main_loop().process_frame
	editor._select_item("2023")
	await Engine.get_main_loop().process_frame

	var revised_record: Dictionary = editor.items.get("2023", {}).duplicate(true)
	revised_record["description"] = "微调后的说明文本"
	revised_record.erase("special_effects")

	var fake_provider = FAKE_PROVIDER_SCRIPT.new()
	Engine.get_main_loop().root.add_child(fake_provider)
	fake_provider.enqueue_response({
		"ok": true,
		"data": {
			"record_type": "item",
			"operation": "revise",
			"target_id": "2023",
			"summary": "微调了描述，但同时移除了一个字段。",
			"warnings": [],
			"record": revised_record
		}
	})

	var panel: Window = AI_PANEL_SCRIPT.new()
	Engine.get_main_loop().root.add_child(panel)
	await Engine.get_main_loop().process_frame
	panel.configure(editor, null, "item", fake_provider)
	panel._mode_option.selected = 1
	panel._main_prompt_input.text = "微调一下描述文案"
	await panel._run_generation(false)

	assert(str(panel.diff_summary.get("risk_level", "")) == "high", "Removed field should be marked high risk")
	assert((panel.diff_summary.get("changed_paths", []) as Array).has("description"), "Diff should include the changed description path")
	assert((panel.diff_summary.get("removed_paths", []) as Array).has("special_effects"), "Diff should include removed field path")
	assert(panel._apply_button.text.contains("高风险"), "Apply button should warn about high-risk changes")
	assert(not panel._apply_button.disabled, "High-risk changes should still be applicable after review")

	panel.queue_free()
	fake_provider.queue_free()
	editor.queue_free()
	await Engine.get_main_loop().process_frame


static func _test_panel_rejects_empty_record_draft() -> void:
	var editor: Control = ITEM_EDITOR_SCRIPT.new()
	Engine.get_main_loop().root.add_child(editor)
	await Engine.get_main_loop().process_frame

	var fake_provider = FAKE_PROVIDER_SCRIPT.new()
	Engine.get_main_loop().root.add_child(fake_provider)
	fake_provider.enqueue_response({
		"ok": true,
		"data": {
			"record_type": "item",
			"operation": "create",
			"target_id": "",
			"summary": "返回了空草稿",
			"warnings": [],
			"record": {}
		}
	})

	var panel: Window = AI_PANEL_SCRIPT.new()
	Engine.get_main_loop().root.add_child(panel)
	await Engine.get_main_loop().process_frame
	panel.configure(editor, null, "item", fake_provider)
	panel._main_prompt_input.text = "生成一个测试物品"
	await panel._run_generation(false)

	assert(panel._apply_button.disabled, "Empty record drafts should not be applicable")
	assert(panel.validation_errors.has("record 不能为空对象"), "Empty record should fail validation")
	assert(panel._review_tags_label.text.contains("空草稿"), "Review tags should expose the empty-draft state")

	panel.queue_free()
	fake_provider.queue_free()
	editor.queue_free()
	await Engine.get_main_loop().process_frame


static func _test_context_builder_prioritizes_relevant_examples_and_emits_refs() -> void:
	var repository := REPOSITORY_SCRIPT.new()
	var context_builder := CONTEXT_BUILDER_SCRIPT.new(repository)
	var context := context_builder.build_context(
		"item",
		{
			"mode": "revise",
			"target_id": "2023",
			"user_prompt": "生成一个史诗级配饰，偏生存辅助",
			"adjustment_prompt": "",
			"current_record": repository.get_record("items", "2023")
		},
		{"current_type": "accessory"},
		6
	)

	var same_type_index: Array = context.get("same_type_index", [])
	assert(not same_type_index.is_empty(), "Context should still include same-type examples")
	var first_item_id := str((same_type_index[0] as Dictionary).get("id", ""))
	var first_item := repository.get_record("items", first_item_id)
	assert(str(first_item.get("type", "")) == "accessory", "Prioritized item example should match the current type")
	assert((context.get("allowed_reference_ids", {}) as Dictionary).has("items"), "Context should expose allowed reference ids")
	assert((context.get("suggested_reference_ids", {}) as Dictionary).has("items"), "Context should expose suggested reference ids")
	assert((context.get("context_stats", {}).get("truncated_categories", []) as Array).size() > 0, "Context should report truncation metadata when limited")


static func _test_adapters_summarize_structural_changes() -> void:
	var dialog_adapter = DIALOG_ADAPTER_SCRIPT.new()
	var dialog_summary := dialog_adapter.summarize_record_changes(
		{
			"dialog_id": "test_dialog",
			"nodes": [
				{"id": "start", "type": "dialog", "is_start": true, "next": "end"},
				{"id": "end", "type": "end", "end_type": "normal"}
			],
			"connections": [{"from": "start", "to": "end", "from_port": 0, "to_port": 0}]
		},
		{
			"dialog_id": "test_dialog",
			"nodes": [
				{"id": "start", "type": "dialog", "is_start": true, "next": "choice_1"},
				{"id": "choice_1", "type": "choice", "options": [{"text": "继续", "next": "end"}]},
				{"id": "end", "type": "end", "end_type": "quest"}
			],
			"connections": [
				{"from": "start", "to": "choice_1", "from_port": 0, "to_port": 0},
				{"from": "choice_1", "to": "end", "from_port": 0, "to_port": 0}
			]
		}
	)
	assert("\n".join(dialog_summary.get("summary_lines", [])).contains("节点数量"), "Dialog summary should describe node-count changes")

	var character_adapter = CHARACTER_ADAPTER_SCRIPT.new()
	var character_summary := character_adapter.summarize_record_changes(
		{
			"id": "test_character",
			"identity": {"camp_id": "survivor"},
			"visual": {},
			"combat": {},
			"social": {"dialog_id": "doctor_chen"},
			"skills": {
				"initial_tree_ids": ["survival"],
				"initial_skills_by_tree": {"survival": ["foraging"]}
			}
		},
		{
			"id": "test_character",
			"identity": {"camp_id": "survivor"},
			"visual": {},
			"combat": {},
			"social": {"dialog_id": "doctor_chen"},
			"skills": {
				"initial_tree_ids": ["survival", "combat"],
				"initial_skills_by_tree": {"survival": ["foraging"], "combat": ["aim_shot"]}
			}
		}
	)
	assert("\n".join(character_summary.get("summary_lines", [])).contains("技能树"), "Character summary should describe skill changes")
