extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentReferenceIndex = preload("res://scripts/tools/content_reference_index.gd")
const ContentRecordCliCommands = preload("res://scripts/tools/content_record_cli_commands.gd")
const ContentRecordValidator = preload("res://scripts/tools/content_record_validator.gd")
const ContentSummaryPresenter = preload("res://scripts/tools/content_summary_presenter.gd")
const MapSceneLoader = preload("res://scripts/world/map_scene_loader.gd")


func _init() -> void:
	var errors := _run()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("content_cli_smoke passed:")
	print({
		"covered_reference_domains": ["item", "recipe", "character", "dialogue", "dialogue_rule", "quest", "skill", "skill_tree", "settlement", "overworld", "map", "shop", "world_tile", "appearance", "ai", "json"],
	})
	quit(0)


func _run() -> Array[String]:
	var errors: Array[String] = []
	var registry: ContentRegistry = ContentRegistry.new()
	var result := registry.load_all()
	if result.has_errors():
		for error in result.errors:
			errors.append(str(error))
		return errors

	var index: ContentReferenceIndex = ContentReferenceIndex.new()
	_expect_min_refs(errors, index, registry, "items", "1006", 1)
	_expect_min_refs(errors, index, registry, "characters", "zombie_walker", 1)
	_expect_min_refs(errors, index, registry, "dialogues", "trader_lao_wang_intro", 1)
	_expect_min_refs(errors, index, registry, "dialogue_rules", "trader_lao_wang", 1)
	_expect_min_refs(errors, index, registry, "quests", "tutorial_survive", 1)
	_expect_min_refs(errors, index, registry, "skills", "survival", 1)
	_expect_min_refs(errors, index, registry, "skill_trees", "survival", 1)
	_expect_min_refs(errors, index, registry, "settlements", "survivor_outpost_01_settlement", 1)
	_expect_min_refs(errors, index, registry, "overworld", "main_overworld", 1)
	_expect_min_refs(errors, index, registry, "maps", "survivor_outpost_01", 1)
	_expect_min_refs(errors, index, registry, "shops", "trader_lao_wang_shop", 1)
	_expect_min_refs(errors, index, registry, "world_tiles", "surface_placeholder_basic", 1)
	_expect_min_refs(errors, index, registry, "appearance", "default_humanoid", 1)
	_expect_min_refs(errors, index, registry, "ai", "guard_settlement", 1)
	_expect_min_refs(errors, index, registry, "json", "stun", 1)
	_expect_valid_record(errors, registry, "items", "1006")
	_expect_valid_record(errors, registry, "recipes", "recipe_first_aid_kit")
	_expect_valid_record(errors, registry, "characters", "zombie_walker")
	_expect_valid_record(errors, registry, "maps", "survivor_outpost_01")
	_expect_valid_record(errors, registry, "dialogues", "trader_lao_wang_intro")
	_expect_valid_record(errors, registry, "dialogue_rules", "trader_lao_wang")
	_expect_valid_record(errors, registry, "quests", "tutorial_survive")
	_expect_valid_record(errors, registry, "skills", "survival")
	_expect_valid_record(errors, registry, "skill_trees", "survival")
	_expect_valid_record(errors, registry, "settlements", "survivor_outpost_01_settlement")
	_expect_valid_record(errors, registry, "overworld", "main_overworld")
	_expect_valid_record(errors, registry, "shops", "trader_lao_wang_shop")
	_expect_valid_record(errors, registry, "world_tiles", "surface_placeholder_basic")
	_expect_valid_record(errors, registry, "appearance", "default_humanoid")
	_expect_valid_record(errors, registry, "ai", "guard_settlement")
	_expect_valid_record(errors, registry, "json", "stun")
	_expect_validate_changed(errors, registry)
	_expect_invalid_recipe_ref(errors, registry)
	_expect_invalid_item_appearance_asset_ref(errors, registry)
	_expect_invalid_character_appearance_ref(errors, registry)
	_expect_invalid_shop_item_ref(errors, registry)
	_expect_invalid_world_tile_asset_ref(errors, registry)
	_expect_invalid_map_world_tile_ref(errors, registry)
	_expect_invalid_overworld_surface_set_ref(errors, registry)
	_expect_invalid_character_ai_ref(errors, registry)
	_expect_invalid_ai_behavior_group_ref(errors, registry)
	_expect_invalid_ai_action_executor_ref(errors, registry)
	_expect_invalid_json_item_ref(errors, registry)
	_expect_recipe_unlock_source_refs(errors, registry)
	_expect_invalid_dialogue_ref(errors, registry)
	_expect_invalid_dialogue_shop_ref(errors, registry)
	_expect_invalid_dialogue_rule_dialogue_ref(errors, registry)
	_expect_invalid_dialogue_rule_quest_ref(errors, registry)
	_expect_invalid_dialogue_rule_item_ref(errors, registry)
	_expect_invalid_settlement_anchor(errors, registry)
	_expect_invalid_overworld_entry(errors, registry)
	_expect_format_domain_support(errors, registry)
	_expect_summary_domains(errors, registry)
	_expect_map_scene_summary(errors, registry)
	return errors


func _expect_min_refs(errors: Array[String], index: ContentReferenceIndex, registry: ContentRegistry, domain: String, id_value: String, minimum: int) -> void:
	if not index.supports_domain(domain):
		errors.append("reference domain not supported: %s" % domain)
		return
	var hits := index.references_for(domain, id_value, registry)
	if hits.size() < minimum:
		errors.append("expected at least %d references for %s %s, got %d" % [minimum, domain, id_value, hits.size()])


func _expect_valid_record(errors: Array[String], registry: ContentRegistry, domain: String, id_value: String) -> void:
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var validation := validator.validate_record(domain, id_value, registry)
	if not bool(validation.get("ok", false)):
		errors.append("expected valid %s %s, got %s" % [domain, id_value, validation.get("issues", [])])


func _expect_validate_changed(errors: Array[String], registry: ContentRegistry) -> void:
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var checked := 0
	for domain in ["items", "recipes", "characters", "maps", "dialogues", "dialogue_rules", "quests", "skills", "skill_trees", "settlements", "overworld", "shops", "world_tiles", "appearance", "ai", "json"]:
		for id_value in registry.get_library(domain).keys():
			var validation := validator.validate_record(domain, str(id_value), registry)
			checked += 1
			if not bool(validation.get("ok", false)):
				errors.append("validate changed smoke failed for %s %s: %s" % [domain, id_value, validation.get("issues", [])])
	if checked < 100:
		errors.append("validate changed smoke expected broad migrated editor coverage, checked only %d records" % checked)


func _expect_invalid_recipe_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("recipes").get("recipe_first_aid_kit", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing recipe_first_aid_kit fixture for invalid validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var output: Dictionary = data.get("output", {}).duplicate(true)
	output["item_id"] = "missing_item_for_validator_smoke"
	data["output"] = output
	source["data"] = data
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var validation := validator.validate_record("recipes", "recipe_first_aid_kit", _registry_with_override(registry, "recipes", "recipe_first_aid_kit", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid recipe reference smoke to fail")
		return
	var found_unknown_item := false
	for issue in validation.get("issues", []):
		var issue_data: Dictionary = issue
		if str(issue_data.get("code", "")) == "unknown_item":
			found_unknown_item = true
	if not found_unknown_item:
		errors.append("invalid recipe reference smoke did not report unknown_item: %s" % validation.get("issues", []))


func _expect_invalid_item_appearance_asset_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("items").get("1002", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing item 1002 fixture for invalid appearance asset smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var fragments: Array = data.get("fragments", []).duplicate(true)
	for i in range(fragments.size()):
		var fragment: Dictionary = fragments[i].duplicate(true)
		if str(fragment.get("kind", "")) != "appearance":
			continue
		var definition: Dictionary = fragment.get("definition", {}).duplicate(true)
		definition["visual_asset"] = "builtin:weapon:missing_for_validator_smoke"
		fragment["definition"] = definition
		fragments[i] = fragment
		data["fragments"] = fragments
		source["data"] = data
		var validation := ContentRecordValidator.new().validate_record("items", "1002", _registry_with_override(registry, "items", "1002", source))
		if bool(validation.get("ok", false)):
			errors.append("expected invalid item appearance asset smoke to fail")
			return
		if not _has_issue_code(validation.get("issues", []), "missing_asset_file"):
			errors.append("invalid item appearance asset smoke did not report missing_asset_file: %s" % validation.get("issues", []))
		return
	errors.append("item appearance asset smoke could not find appearance fragment")


func _expect_invalid_character_appearance_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("characters").get("player", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing player fixture for invalid appearance validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	data["appearance_profile_id"] = "missing_appearance_for_validator_smoke"
	source["data"] = data
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var validation := validator.validate_record("characters", "player", _registry_with_override(registry, "characters", "player", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid character appearance reference smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_appearance"):
		errors.append("invalid character appearance smoke did not report unknown_appearance: %s" % validation.get("issues", []))


func _expect_invalid_shop_item_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("shops").get("trader_lao_wang_shop", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing trader_lao_wang_shop fixture for invalid shop validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var inventory: Array = data.get("inventory", []).duplicate(true)
	if inventory.is_empty():
		errors.append("shop validation smoke missing inventory fixture")
		return
	var entry: Dictionary = inventory[0].duplicate(true)
	entry["item_id"] = "missing_shop_item_for_validator_smoke"
	inventory[0] = entry
	data["inventory"] = inventory
	source["data"] = data
	var validation := ContentRecordValidator.new().validate_record("shops", "trader_lao_wang_shop", _registry_with_override(registry, "shops", "trader_lao_wang_shop", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid shop item reference smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_item"):
		errors.append("invalid shop item smoke did not report unknown_item: %s" % validation.get("issues", []))


func _expect_invalid_world_tile_asset_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("world_tiles").get("surface_placeholder_basic", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing surface_placeholder_basic fixture for invalid world tile validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var prototypes: Array = data.get("prototypes", []).duplicate(true)
	if prototypes.is_empty():
		errors.append("world tile validation smoke missing prototype fixture")
		return
	var prototype: Dictionary = prototypes[0].duplicate(true)
	var prototype_source: Dictionary = prototype.get("source", {}).duplicate(true)
	prototype_source["path"] = "world_tiles/missing_for_validator_smoke.gltf"
	prototype["source"] = prototype_source
	prototypes[0] = prototype
	data["prototypes"] = prototypes
	source["data"] = data
	var validation := ContentRecordValidator.new().validate_record("world_tiles", "surface_placeholder_basic", _registry_with_override(registry, "world_tiles", "surface_placeholder_basic", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid world tile asset smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "missing_asset_file"):
		errors.append("invalid world tile asset smoke did not report missing_asset_file: %s" % validation.get("issues", []))


func _expect_invalid_map_world_tile_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("maps").get("survivor_outpost_01", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing survivor_outpost_01 fixture for map world tile validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var objects: Array = data.get("objects", []).duplicate(true)
	for i in range(objects.size()):
		var object: Dictionary = objects[i].duplicate(true)
		var props: Dictionary = object.get("props", {}).duplicate(true)
		var visual: Dictionary = props.get("visual", {}).duplicate(true)
		if visual.is_empty():
			continue
		visual["prototype_id"] = "missing_world_tile_prototype_for_validator_smoke"
		props["visual"] = visual
		object["props"] = props
		objects[i] = object
		data["objects"] = objects
		source["data"] = data
		var validation := ContentRecordValidator.new().validate_record("maps", "survivor_outpost_01", _registry_with_override(registry, "maps", "survivor_outpost_01", source))
		if bool(validation.get("ok", false)):
			errors.append("expected invalid map world tile reference smoke to fail")
			return
		if not _has_issue_code(validation.get("issues", []), "unknown_world_tile_prototype"):
			errors.append("invalid map world tile smoke did not report unknown_world_tile_prototype: %s" % validation.get("issues", []))
		return
	errors.append("map world tile validation smoke could not find visual prototype fixture")


func _expect_invalid_overworld_surface_set_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("overworld").get("main_overworld", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing main_overworld fixture for overworld surface set validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var cells: Array = data.get("cells", []).duplicate(true)
	if cells.is_empty():
		errors.append("overworld surface set validation smoke missing cell fixture")
		return
	var cell: Dictionary = cells[0].duplicate(true)
	var visual: Dictionary = cell.get("visual", {}).duplicate(true)
	visual["surface_set_id"] = "missing_surface_set_for_validator_smoke"
	cell["visual"] = visual
	cells[0] = cell
	data["cells"] = cells
	source["data"] = data
	var validation := ContentRecordValidator.new().validate_record("overworld", "main_overworld", _registry_with_override(registry, "overworld", "main_overworld", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid overworld surface set reference smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_surface_set"):
		errors.append("invalid overworld surface set smoke did not report unknown_surface_set: %s" % validation.get("issues", []))


func _expect_invalid_character_ai_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("characters").get("survivor_outpost_01_guard_liu", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing guard fixture for invalid AI profile smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var life: Dictionary = data.get("life", {}).duplicate(true)
	life["ai_behavior_profile_id"] = "missing_ai_behavior_for_validator_smoke"
	data["life"] = life
	source["data"] = data
	var validation := ContentRecordValidator.new().validate_record("characters", "survivor_outpost_01_guard_liu", _registry_with_override(registry, "characters", "survivor_outpost_01_guard_liu", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid character AI profile reference smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_ai_behavior"):
		errors.append("invalid character AI profile smoke did not report unknown_ai_behavior: %s" % validation.get("issues", []))


func _expect_invalid_ai_behavior_group_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("ai").get("guard_settlement", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing guard_settlement fixture for AI behavior validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	data["action_group_ids"] = ["missing_action_group_for_validator_smoke"]
	source["data"] = data
	var validation := ContentRecordValidator.new().validate_record("ai", "guard_settlement", _registry_with_override(registry, "ai", "guard_settlement", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid AI behavior action group smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_action_group"):
		errors.append("invalid AI behavior group smoke did not report unknown_action_group: %s" % validation.get("issues", []))


func _expect_invalid_ai_action_executor_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("ai").get("settlement_npc_modules", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing settlement_npc_modules fixture for AI action validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var actions: Array = data.get("actions", []).duplicate(true)
	if actions.is_empty():
		errors.append("AI action validation smoke missing action fixture")
		return
	var action: Dictionary = actions[0].duplicate(true)
	action["executor_binding_id"] = "missing_executor_for_validator_smoke"
	actions[0] = action
	data["actions"] = actions
	source["data"] = data
	var validation := ContentRecordValidator.new().validate_record("ai", "settlement_npc_modules", _registry_with_override(registry, "ai", "settlement_npc_modules", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid AI action executor smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_executor"):
		errors.append("invalid AI action executor smoke did not report unknown_executor: %s" % validation.get("issues", []))


func _expect_invalid_json_item_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("json").get("ammo_types", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing ammo_types fixture for legacy JSON validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var ammo: Dictionary = data.get("ammo_pistol", {}).duplicate(true)
	var recipe: Dictionary = ammo.get("craft_recipe", {}).duplicate(true)
	var materials: Array = recipe.get("materials", []).duplicate(true)
	if materials.is_empty():
		errors.append("legacy JSON validation smoke missing ammo material fixture")
		return
	var material: Dictionary = materials[0].duplicate(true)
	material["item"] = "missing_item_for_validator_smoke"
	materials[0] = material
	recipe["materials"] = materials
	ammo["craft_recipe"] = recipe
	data["ammo_pistol"] = ammo
	source["data"] = data
	var validation := ContentRecordValidator.new().validate_record("json", "ammo_types", _registry_with_override(registry, "json", "ammo_types", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid legacy JSON item reference smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_item"):
		errors.append("invalid legacy JSON item smoke did not report unknown_item: %s" % validation.get("issues", []))


func _expect_recipe_unlock_source_refs(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("recipes").get("recipe_first_aid_kit", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing recipe_first_aid_kit fixture for unlock source smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	data["id"] = "smoke_unlock_source_recipe"
	data["unlock_conditions"] = [
		{"type": "item", "id": "1104", "count": 1},
		{"type": "book", "id": "1031"},
		{"type": "world_flag", "id": "outpost_workshop_restored"},
	]
	data["is_default_unlocked"] = false
	source["data"] = data
	source["path"] = "<smoke>"
	var smoke_registry := _registry_with_override(registry, "recipes", "smoke_unlock_source_recipe", source)
	var validation := ContentRecordValidator.new().validate_record("recipes", "smoke_unlock_source_recipe", smoke_registry)
	if not bool(validation.get("ok", false)):
		errors.append("unlock source recipe should validate item/book/world_flag conditions: %s" % validation.get("issues", []))
	var index := ContentReferenceIndex.new()
	if not _has_reference_detail(index.references_for("items", "1104", smoke_registry), "unlock_conditions[0].id"):
		errors.append("item unlock condition should appear in item reference index")
	if not _has_reference_detail(index.references_for("items", "1031", smoke_registry), "unlock_conditions[1].id"):
		errors.append("book unlock condition should appear in item reference index")


func _expect_invalid_dialogue_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("dialogues").get("trader_lao_wang_intro", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing trader_lao_wang_intro fixture for dialogue validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var nodes: Array = data.get("nodes", []).duplicate(true)
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i].duplicate(true)
		if str(node.get("type", "")) == "action":
			var actions: Array = node.get("actions", []).duplicate(true)
			for action_index in range(actions.size()):
				var action: Dictionary = actions[action_index].duplicate(true)
				if str(action.get("type", "")) == "start_quest":
					action["quest_id"] = "missing_quest_for_validator_smoke"
					actions[action_index] = action
					node["actions"] = actions
					nodes[i] = node
					data["nodes"] = nodes
					source["data"] = data
					var validator: ContentRecordValidator = ContentRecordValidator.new()
					var validation := validator.validate_record("dialogues", "trader_lao_wang_intro", _registry_with_override(registry, "dialogues", "trader_lao_wang_intro", source))
					if bool(validation.get("ok", false)):
						errors.append("expected invalid dialogue quest reference smoke to fail")
						return
					if not _has_issue_code(validation.get("issues", []), "unknown_quest"):
						errors.append("invalid dialogue reference smoke did not report unknown_quest: %s" % validation.get("issues", []))
					return
	errors.append("dialogue validation smoke could not find start_quest action")


func _expect_invalid_dialogue_shop_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("dialogues").get("trader_lao_wang_intro", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing trader_lao_wang_intro fixture for dialogue shop validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var nodes: Array = data.get("nodes", []).duplicate(true)
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i].duplicate(true)
		if str(node.get("type", "")) != "action":
			continue
		var actions: Array = node.get("actions", []).duplicate(true)
		for action_index in range(actions.size()):
			var action: Dictionary = actions[action_index].duplicate(true)
			if str(action.get("type", "")) == "open_trade":
				action["shop_id"] = "missing_shop_for_validator_smoke"
				actions[action_index] = action
				node["actions"] = actions
				nodes[i] = node
				data["nodes"] = nodes
				source["data"] = data
				var validation := ContentRecordValidator.new().validate_record("dialogues", "trader_lao_wang_intro", _registry_with_override(registry, "dialogues", "trader_lao_wang_intro", source))
				if bool(validation.get("ok", false)):
					errors.append("expected invalid dialogue shop reference smoke to fail")
					return
				if not _has_issue_code(validation.get("issues", []), "unknown_shop"):
					errors.append("invalid dialogue shop smoke did not report unknown_shop: %s" % validation.get("issues", []))
				return
	errors.append("dialogue shop validation smoke could not find open_trade action")


func _expect_invalid_dialogue_rule_dialogue_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("dialogue_rules").get("trader_lao_wang", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing trader_lao_wang fixture for dialogue rule validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	data["default_dialogue_id"] = "missing_dialogue_for_validator_smoke"
	source["data"] = data
	var validation := ContentRecordValidator.new().validate_record("dialogue_rules", "trader_lao_wang", _registry_with_override(registry, "dialogue_rules", "trader_lao_wang", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid dialogue rule dialogue reference smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_dialogue"):
		errors.append("invalid dialogue rule dialogue smoke did not report unknown_dialogue: %s" % validation.get("issues", []))


func _expect_invalid_dialogue_rule_quest_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("dialogue_rules").get("trader_lao_wang", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing trader_lao_wang fixture for dialogue rule quest validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var variants: Array = data.get("variants", []).duplicate(true)
	if variants.is_empty():
		errors.append("dialogue rule quest validation smoke missing variant fixture")
		return
	var variant: Dictionary = variants[0].duplicate(true)
	var when: Dictionary = variant.get("when", {}).duplicate(true)
	when["player_active_quests_any"] = ["missing_quest_for_validator_smoke"]
	variant["when"] = when
	variants[0] = variant
	data["variants"] = variants
	source["data"] = data
	var validation := ContentRecordValidator.new().validate_record("dialogue_rules", "trader_lao_wang", _registry_with_override(registry, "dialogue_rules", "trader_lao_wang", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid dialogue rule quest reference smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_quest"):
		errors.append("invalid dialogue rule quest smoke did not report unknown_quest: %s" % validation.get("issues", []))


func _expect_invalid_dialogue_rule_item_ref(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("dialogue_rules").get("trader_lao_wang", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing trader_lao_wang fixture for dialogue rule item validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var variants: Array = data.get("variants", []).duplicate(true)
	if variants.is_empty():
		errors.append("dialogue rule item validation smoke missing variant fixture")
		return
	var variant: Dictionary = variants[0].duplicate(true)
	var when: Dictionary = variant.get("when", {}).duplicate(true)
	when["player_item_count_min"] = {"missing_item_for_validator_smoke": 1}
	variant["when"] = when
	variants[0] = variant
	data["variants"] = variants
	source["data"] = data
	var validation := ContentRecordValidator.new().validate_record("dialogue_rules", "trader_lao_wang", _registry_with_override(registry, "dialogue_rules", "trader_lao_wang", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid dialogue rule item reference smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_item"):
		errors.append("invalid dialogue rule item smoke did not report unknown_item: %s" % validation.get("issues", []))


func _expect_invalid_settlement_anchor(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("settlements").get("survivor_outpost_01_settlement", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing survivor_outpost_01_settlement fixture for settlement validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var smart_objects: Array = data.get("smart_objects", []).duplicate(true)
	if smart_objects.is_empty():
		errors.append("settlement validation smoke missing smart object fixture")
		return
	var smart_object: Dictionary = smart_objects[0].duplicate(true)
	smart_object["anchor_id"] = "missing_anchor_for_validator_smoke"
	smart_objects[0] = smart_object
	data["smart_objects"] = smart_objects
	source["data"] = data
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var validation := validator.validate_record("settlements", "survivor_outpost_01_settlement", _registry_with_override(registry, "settlements", "survivor_outpost_01_settlement", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid settlement anchor smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_anchor"):
		errors.append("invalid settlement anchor smoke did not report unknown_anchor: %s" % validation.get("issues", []))


func _expect_invalid_overworld_entry(errors: Array[String], registry: ContentRegistry) -> void:
	var source: Dictionary = registry.get_library("overworld").get("main_overworld", {}).duplicate(true)
	if source.is_empty():
		errors.append("missing main_overworld fixture for overworld validation smoke")
		return
	var data: Dictionary = source.get("data", {}).duplicate(true)
	var locations: Array = data.get("locations", []).duplicate(true)
	if locations.is_empty():
		errors.append("overworld validation smoke missing location fixture")
		return
	var location: Dictionary = locations[0].duplicate(true)
	location["entry_point_id"] = "missing_entry_for_validator_smoke"
	locations[0] = location
	data["locations"] = locations
	source["data"] = data
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var validation := validator.validate_record("overworld", "main_overworld", _registry_with_override(registry, "overworld", "main_overworld", source))
	if bool(validation.get("ok", false)):
		errors.append("expected invalid overworld entry smoke to fail")
		return
	if not _has_issue_code(validation.get("issues", []), "unknown_entry_point"):
		errors.append("invalid overworld entry smoke did not report unknown_entry_point: %s" % validation.get("issues", []))


func _has_issue_code(issues: Array, code: String) -> bool:
	for issue in issues:
		var issue_data: Dictionary = issue
		if str(issue_data.get("code", "")) == code:
			return true
	return false


func _has_reference_detail(hits: Array[Dictionary], detail: String) -> bool:
	for hit in hits:
		var hit_data: Dictionary = hit
		if str(hit_data.get("detail", "")) == detail:
			return true
	return false


func _expect_format_domain_support(errors: Array[String], registry: ContentRegistry) -> void:
	var supported := {
		"items": "data/items/1006.json",
		"recipes": "data/recipes/recipe_first_aid_kit.json",
		"characters": "data/characters/zombie_walker.json",
		"maps": "data/maps/survivor_outpost_01.json",
		"dialogues": "data/dialogues/trader_lao_wang_intro.json",
		"dialogue_rules": "data/dialogue_rules/trader_lao_wang.json",
		"quests": "data/quests/tutorial_survive.json",
		"skills": "data/skills/survival.json",
		"skill_trees": "data/skill_trees/survival.json",
		"settlements": "data/settlements/survivor_outpost_01_settlement.json",
		"overworld": "data/overworld/main_overworld.json",
		"shops": "data/shops/trader_lao_wang_shop.json",
		"world_tiles": "data/world_tiles/surface_placeholder_basic.json",
		"ai": "data/ai/behaviors/guard_settlement.json",
		"json": "data/json/effects/stun.json",
	}
	var domain_helper = load("res://scripts/tools/content_cli_domains.gd")
	for domain in supported.keys():
		if not domain_helper.supports_format_domain(domain):
			errors.append("format domain should be supported: %s" % domain)
		var relative_path := str(supported[domain])
		if domain_helper.domain_for_relative_path(relative_path) != domain:
			errors.append("format path should map to %s: %s" % [domain, relative_path])
		var record: Dictionary = registry.get_library(domain).get(relative_path.get_file().get_basename(), {})
		if record.is_empty():
			errors.append("format support smoke missing fixture for %s @ %s" % [domain, relative_path])


func _expect_summary_domains(errors: Array[String], registry: ContentRegistry) -> void:
	var presenter: ContentSummaryPresenter = ContentSummaryPresenter.new()
	var cases := [
		{"domain": "dialogues", "id": "trader_lao_wang_intro", "expected": "action_types: open_trade, start_quest"},
		{"domain": "dialogue_rules", "id": "trader_lao_wang", "expected": "variant_count: 12"},
		{"domain": "quests", "id": "tutorial_survive", "expected": "node_types: end=1, objective=1, reward=1, start=1"},
		{"domain": "skills", "id": "survival", "expected": "activation_mode: passive"},
		{"domain": "skill_trees", "id": "survival", "expected": "skill_count: 4"},
		{"domain": "settlements", "id": "survivor_outpost_01_settlement", "expected": "smart_objects: 13"},
		{"domain": "overworld", "id": "main_overworld", "expected": "locations: 12"},
		{"domain": "shops", "id": "trader_lao_wang_shop", "expected": "inventory_count: 6"},
		{"domain": "world_tiles", "id": "surface_placeholder_basic", "expected": "prototype_count: 8"},
		{"domain": "ai", "id": "guard_settlement", "expected": "action_groups: duty_travel_actions, guard_actions"},
		{"domain": "json", "id": "stun", "expected": "special_effects: stun"},
	]
	for test_case in cases:
		var domain := str(test_case["domain"])
		var id_value := str(test_case["id"])
		var record: Dictionary = registry.get_library(domain).get(id_value, {})
		var output := "\n".join(presenter.summary_lines(domain, id_value, record, _repo_relative_path(str(record.get("path", "")))))
		if not output.contains(str(test_case["expected"])):
			errors.append("summary for %s %s missing '%s': %s" % [domain, id_value, test_case["expected"], output])


func _expect_map_scene_summary(errors: Array[String], registry: ContentRegistry) -> void:
	var map_id := "survivor_outpost_01"
	var scene_result: Dictionary = MapSceneLoader.new().load_map_definition(map_id)
	if not bool(scene_result.get("ok", false)):
		errors.append("map scene summary smoke could not load %s: %s" % [map_id, scene_result.get("error", "")])
		return

	var record := {
		"path": str(scene_result.get("path", "")),
		"data": scene_result.get("data", {}),
	}
	var output := "\n".join(ContentSummaryPresenter.new().summary_lines(
		"maps",
		map_id,
		record,
		_repo_relative_path(str(record.get("path", "")))
	))
	if not output.contains("relative_path: godot/scenes/maps/survivor_outpost_01.tscn"):
		errors.append("map scene summary should report Godot scene path: %s" % output)
	var scene_object_count := _array_or_empty(_dictionary_or_empty(record.get("data", {})).get("objects", [])).size()
	if not output.contains("objects: %d" % scene_object_count):
		errors.append("map scene summary should use .tscn map definition object count: %s" % output)

	var locate := ContentRecordCliCommands.new().locate_path(["locate", "map", map_id], registry)
	if not bool(locate.get("ok", false)):
		errors.append("map locate should resolve through Godot scene for %s: %s" % [map_id, locate])
	elif str(locate.get("path", "")) != "godot/scenes/maps/survivor_outpost_01.tscn":
		errors.append("map locate should expose Godot scene path, got %s" % locate.get("path", ""))


func _repo_relative_path(path: String) -> String:
	var relative_path := path.replace("\\", "/")
	if relative_path.begins_with("res://"):
		return "godot/%s" % relative_path.substr("res://".length())
	var marker := "/data/"
	var index := relative_path.find(marker)
	if index >= 0:
		return relative_path.substr(index + 1)
	return relative_path


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _registry_with_override(registry: ContentRegistry, domain: String, id_value: String, record: Dictionary) -> ContentRegistry:
	var copy: ContentRegistry = ContentRegistry.new()
	copy.libraries = registry.libraries.duplicate(true)
	copy.files_by_domain = registry.files_by_domain.duplicate(true)
	copy.bootstrap_config = registry.bootstrap_config.duplicate(true)
	copy.data_root = registry.data_root
	var library: Dictionary = copy.libraries.get(domain, {}).duplicate(true)
	library[id_value] = record
	copy.libraries[domain] = library
	return copy
