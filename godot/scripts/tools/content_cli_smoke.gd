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
		"covered_reference_domains": ["item", "recipe", "character", "dialogue", "quest", "skill", "skill_tree", "settlement", "overworld", "map"],
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
	_expect_min_refs(errors, index, registry, "quests", "tutorial_survive", 1)
	_expect_min_refs(errors, index, registry, "skills", "survival", 1)
	_expect_min_refs(errors, index, registry, "skill_trees", "survival", 1)
	_expect_min_refs(errors, index, registry, "settlements", "survivor_outpost_01_settlement", 1)
	_expect_min_refs(errors, index, registry, "overworld", "main_overworld", 1)
	_expect_min_refs(errors, index, registry, "maps", "survivor_outpost_01", 1)
	_expect_valid_record(errors, registry, "items", "1006")
	_expect_valid_record(errors, registry, "recipes", "recipe_first_aid_kit")
	_expect_valid_record(errors, registry, "characters", "zombie_walker")
	_expect_valid_record(errors, registry, "maps", "survivor_outpost_01")
	_expect_valid_record(errors, registry, "dialogues", "trader_lao_wang_intro")
	_expect_valid_record(errors, registry, "quests", "tutorial_survive")
	_expect_valid_record(errors, registry, "skills", "survival")
	_expect_valid_record(errors, registry, "skill_trees", "survival")
	_expect_valid_record(errors, registry, "settlements", "survivor_outpost_01_settlement")
	_expect_valid_record(errors, registry, "overworld", "main_overworld")
	_expect_valid_record(errors, registry, "appearance", "default_humanoid")
	_expect_validate_changed(errors, registry)
	_expect_invalid_recipe_ref(errors, registry)
	_expect_invalid_dialogue_ref(errors, registry)
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
	for domain in ["items", "recipes", "characters", "maps", "dialogues", "quests", "skills", "skill_trees", "settlements", "overworld", "appearance"]:
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


func _expect_format_domain_support(errors: Array[String], registry: ContentRegistry) -> void:
	var supported := {
		"items": "data/items/1006.json",
		"recipes": "data/recipes/recipe_first_aid_kit.json",
		"characters": "data/characters/zombie_walker.json",
		"maps": "data/maps/survivor_outpost_01.json",
		"dialogues": "data/dialogues/trader_lao_wang_intro.json",
		"quests": "data/quests/tutorial_survive.json",
		"skills": "data/skills/survival.json",
		"skill_trees": "data/skill_trees/survival.json",
		"settlements": "data/settlements/survivor_outpost_01_settlement.json",
		"overworld": "data/overworld/main_overworld.json",
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
		{"domain": "quests", "id": "tutorial_survive", "expected": "node_types: end=1, objective=1, reward=1, start=1"},
		{"domain": "skills", "id": "survival", "expected": "activation_mode: passive"},
		{"domain": "skill_trees", "id": "survival", "expected": "skill_count: 4"},
		{"domain": "settlements", "id": "survivor_outpost_01_settlement", "expected": "smart_objects: 13"},
		{"domain": "overworld", "id": "main_overworld", "expected": "locations: 12"},
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
