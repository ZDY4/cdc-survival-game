extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentReferenceIndex = preload("res://scripts/tools/content_reference_index.gd")
const ContentRecordValidator = preload("res://scripts/tools/content_record_validator.gd")


func _init() -> void:
	var errors := _run()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("content_cli_smoke passed:")
	print({
		"covered_reference_domains": ["item", "recipe", "character", "dialogue", "quest", "skill", "settlement", "overworld", "map"],
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
	_expect_validate_changed(errors, registry)
	_expect_invalid_recipe_ref(errors, registry)
	_expect_invalid_dialogue_ref(errors, registry)
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
	for domain in ["items", "recipes", "characters", "maps", "dialogues", "quests", "skills", "skill_trees"]:
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


func _has_issue_code(issues: Array, code: String) -> bool:
	for issue in issues:
		var issue_data: Dictionary = issue
		if str(issue_data.get("code", "")) == code:
			return true
	return false


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
