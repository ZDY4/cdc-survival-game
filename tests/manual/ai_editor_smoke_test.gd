extends Control

const ITEM_EDITOR_SCRIPT := preload("res://addons/cdc_game_editor/editors/item_editor/item_editor.gd")
const CHARACTER_EDITOR_SCRIPT := preload("res://addons/cdc_game_editor/editors/character_data_editor/character_data_editor.gd")
const DIALOG_EDITOR_SCRIPT := preload("res://addons/cdc_game_editor/editors/dialog_editor/dialog_editor.gd")
const QUEST_EDITOR_SCRIPT := preload("res://addons/cdc_game_editor/editors/quest_editor/quest_editor.gd")
const FAKE_PROVIDER_SCRIPT := preload("res://addons/cdc_game_editor/ai/providers/fake_ai_provider.gd")


func _ready() -> void:
	var fake_provider = FAKE_PROVIDER_SCRIPT.new()
	add_child(fake_provider)
	_enqueue_fake_drafts(fake_provider)

	var editors := [
		_instantiate_editor("item_editor", ITEM_EDITOR_SCRIPT, Vector2(0, 0), Vector2(760, 420)),
		_instantiate_editor("character_editor", CHARACTER_EDITOR_SCRIPT, Vector2(760, 0), Vector2(760, 420)),
		_instantiate_editor("dialog_editor", DIALOG_EDITOR_SCRIPT, Vector2(0, 420), Vector2(760, 420)),
		_instantiate_editor("quest_editor", QUEST_EDITOR_SCRIPT, Vector2(760, 420), Vector2(760, 420))
	]

	for editor in editors:
		if editor and editor.has_method("set_ai_provider_override"):
			editor.call("set_ai_provider_override", fake_provider)

	print("[AIEditorSmoke] Editors instantiated and fake provider injected")
	await get_tree().process_frame
	for editor in editors:
		if editor and editor.has_method("_open_ai_panel"):
			editor.call("_open_ai_panel")
			await get_tree().process_frame
			if editor.get("_ai_panel"):
				var panel: Window = editor.get("_ai_panel")
				panel._main_prompt_input.text = "生成一条 smoke 草稿"
				await panel._run_generation(false)
	print("[AIEditorSmoke] AI generation triggered for all editors")
	await get_tree().create_timer(1.5).timeout
	get_tree().quit()


func _instantiate_editor(name: String, script: Script, position: Vector2, size: Vector2) -> Control:
	var instance: Variant = script.new()
	assert(instance is Control, "%s should extend Control" % name)
	var editor: Control = instance
	editor.name = name
	editor.position = position
	editor.size = size
	editor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(editor)
	return editor


func _enqueue_fake_drafts(fake_provider) -> void:
	fake_provider.enqueue_response({
		"ok": true,
		"data": {
			"record_type": "item",
			"operation": "create",
			"target_id": "",
			"summary": "Smoke item draft",
			"warnings": [],
			"record": {
				"id": 999998,
				"name": "AI Smoke Item",
				"description": "Smoke test item",
				"type": "misc",
				"rarity": "common",
				"weight": 0.1,
				"value": 1,
				"stackable": true,
				"max_stack": 1,
				"icon_path": "",
				"equippable": false,
				"level_requirement": 0,
				"durability": -1,
				"max_durability": -1,
				"repairable": false,
				"usable": false,
				"special_effects": [],
				"attributes_bonus": {}
			}
		}
	})
	fake_provider.enqueue_response({
		"ok": true,
		"data": {
			"record_type": "character",
			"operation": "create",
			"target_id": "",
			"summary": "Smoke character draft",
			"warnings": [],
			"record": {
				"id": "ai_smoke_character",
				"name": "Smoke Survivor",
				"description": "Smoke test character",
				"level": 1,
				"identity": {"camp_id": "neutral"},
				"visual": {"portrait_path": "", "avatar_path": "", "model_path": "", "placeholder": {}},
				"combat": {"stats": {}, "ai": {}, "behavior": "neutral", "loot": [], "xp": 0},
				"social": {"title": "", "dialog_id": "", "mood": {}},
				"skills": {"initial_tree_ids": [], "initial_skills_by_tree": {}}
			}
		}
	})
	fake_provider.enqueue_response({
		"ok": true,
		"data": {
			"record_type": "dialog",
			"operation": "create",
			"target_id": "",
			"summary": "Smoke dialog draft",
			"warnings": [],
			"record": {
				"dialog_id": "ai_smoke_dialog",
				"nodes": [
					{
						"id": "start",
						"type": "dialog",
						"title": "Start",
						"speaker": "NPC",
						"text": "Smoke line",
						"is_start": true,
						"next": "end_1"
					},
					{
						"id": "end_1",
						"type": "end",
						"end_type": "normal"
					}
				],
				"connections": [
					{"from": "start", "from_port": 0, "to": "end_1", "to_port": 0}
				]
			}
		}
	})
	fake_provider.enqueue_response({
		"ok": true,
		"data": {
			"record_type": "quest",
			"operation": "create",
			"target_id": "",
			"summary": "Smoke quest draft",
			"warnings": [],
			"record": {
				"quest_id": "ai_smoke_quest",
				"title": "Smoke Quest",
				"description": "Smoke test quest",
				"prerequisites": [],
				"time_limit": -1,
				"flow": {
					"start_node_id": "start",
					"nodes": {
						"start": {"id": "start", "type": "start", "position": {"x": 120, "y": 160}},
						"end": {"id": "end", "type": "end", "position": {"x": 420, "y": 160}}
					},
					"connections": [
						{"from": "start", "from_port": 0, "to": "end", "to_port": 0}
					]
				}
			}
		}
	})
