# tests/functional/unit/test_gameplay_tags.gd
# Gameplay Tags 单元测试 - Functional Layer

extends Node
class_name FunctionalTest_GameplayTags

const TEMP_CONFIG_PATH: String = "user://gameplay_tags_test.ini"
const MANAGER_SCRIPT_PATH: String = "res://addons/gameplay_tags/runtime/gameplay_tags_manager.gd"
const DOCK_SCRIPT_PATH: String = "res://addons/gameplay_tags/editor/gameplay_tags_dock.gd"
const INSPECTOR_PLUGIN_SCRIPT_PATH: String = "res://addons/gameplay_tags/editor/gameplay_tag_inspector_plugin.gd"
const CHARACTER_ACTOR_SCRIPT_PATH: String = "res://systems/character_actor.gd"
const DEFAULT_CONFIG_PATH: String = "res://config/gameplay_tags.ini"
const FUNCTIONAL_LAYER: int = 1
const P0_CRITICAL: int = 0
const P1_MAJOR: int = 1

static func run_tests(runner) -> void:
	runner.register_test(
		"gameplay_tags_registry_load",
		FUNCTIONAL_LAYER,
		P0_CRITICAL,
		_test_registry_load
	)

	runner.register_test(
		"gameplay_tags_hierarchy_match",
		FUNCTIONAL_LAYER,
		P0_CRITICAL,
		_test_hierarchy_match
	)

	runner.register_test(
		"gameplay_tag_container_behavior",
		FUNCTIONAL_LAYER,
		P1_MAJOR,
		_test_container_behavior
	)

	runner.register_test(
		"gameplay_tag_query_evaluate",
		FUNCTIONAL_LAYER,
		P0_CRITICAL,
		_test_query_evaluate
	)

	runner.register_test(
		"gameplay_tag_stack_container",
		FUNCTIONAL_LAYER,
		P1_MAJOR,
		_test_stack_container
	)

	runner.register_test(
		"gameplay_tags_default_config_path",
		FUNCTIONAL_LAYER,
		P1_MAJOR,
		_test_default_config_path
	)

	runner.register_test(
		"gameplay_tags_registry_validation",
		FUNCTIONAL_LAYER,
		P1_MAJOR,
		_test_registry_validation
	)

	runner.register_test(
		"gameplay_tags_editor_reference_hits",
		FUNCTIONAL_LAYER,
		P1_MAJOR,
		_test_editor_reference_hits
	)

	runner.register_test(
		"gameplay_tags_editor_replace_and_sibling",
		FUNCTIONAL_LAYER,
		P1_MAJOR,
		_test_editor_replace_and_sibling
	)

	runner.register_test(
		"gameplay_tags_inspector_hint_markers",
		FUNCTIONAL_LAYER,
		P1_MAJOR,
		_test_inspector_hint_markers
	)

	runner.register_test(
		"gameplay_tags_inspector_opt_in_field",
		FUNCTIONAL_LAYER,
		P1_MAJOR,
		_test_inspector_opt_in_field
	)

static func _test_registry_load() -> void:
	_write_temp_config([
		"; test file",
		"[GameplayTags]",
		"+GameplayTagList=\"Status.Burning\"",
		"+GameplayTagList=\"Status.Burning\"",
		"+GameplayTagList=\"State.Combat\"",
		"+GameplayTagList=\"Bad Tag\""
	])

	var manager: Object = _new_manager()
	var loaded: bool = bool(manager.call("reload_tags", TEMP_CONFIG_PATH))
	assert(loaded, "Registry should load from temp file")

	var explicit_tags: Array = manager.call("get_explicit_tags")
	assert(explicit_tags.size() == 2, "Duplicate/invalid tags should be filtered")
	assert(bool(manager.call("is_valid_tag", &"Status.Burning")), "Explicit tag should be valid")
	assert(bool(manager.call("is_valid_tag", &"Status")), "Implicit parent tag should be valid")

	var warnings: Array = manager.call("get_parse_warnings")
	assert(warnings.size() >= 1, "Invalid declarations should produce warnings")

static func _test_hierarchy_match() -> void:
	var manager: Object = _new_manager()
	assert(bool(manager.call("matches_tag", &"Status.Burning.Intense", &"Status.Burning", false)))
	assert(bool(manager.call("matches_tag", &"Status.Burning.Intense", &"Status", false)))
	assert(not bool(manager.call("matches_tag", &"Status.Burning", &"Status.Burning.Intense", false)))
	assert(not bool(manager.call("matches_tag", &"Status.Burning.Intense", &"Status.Burning", true)))
	assert(bool(manager.call("matches_tag", &"Status.Burning", &"Status.Burning", true)))

static func _test_container_behavior() -> void:
	var container: GameplayTagContainer = GameplayTagContainer.new()
	container.add_tag(&"Status.Burning.Intense")
	container.add_tag(&"State.Combat")
	container.add_tag(&"State.Combat")

	assert(container.has_tag(&"Status", false), "Parent tag should match in non-exact mode")
	assert(container.has_tag(&"Status.Burning.Intense", true), "Exact tag should match")
	assert(not container.has_tag(&"Status.Burning", true), "Parent should not match exact mode")
	assert(container.has_any([&"State", &"Missing.Tag"], false), "has_any should match at least one")
	assert(container.has_all([&"Status.Burning", &"State.Combat"], false), "has_all should match all")

	var explicit_tags: Array[StringName] = container.get_explicit_tags()
	assert(explicit_tags.size() == 2, "Container should deduplicate explicit tags")

static func _test_query_evaluate() -> void:
	var container: GameplayTagContainer = GameplayTagContainer.new()
	container.add_tag(&"State.Combat")
	container.add_tag(&"Status.Burning")

	var all_conditions: Array[GameplayTagQuery] = []
	all_conditions.append(GameplayTagQuery.any_tags_match([&"State"]))
	all_conditions.append(GameplayTagQuery.no_tags_match([&"State.Dead"]))

	var query: GameplayTagQuery = GameplayTagQuery.all_expr_match(all_conditions)
	assert(query.evaluate(container), "Nested all_expr query should pass")

	var dict_query: Dictionary = {
		"type": "any_expr",
		"tags": [],
		"expressions": [
			{
				"type": "all_tags",
				"tags": ["Status.Burning", "State.Combat"],
				"expressions": []
			},
			{
				"type": "all_tags",
				"tags": ["Status.Poisoned"],
				"expressions": []
			}
		]
	}
	var query_from_dict: GameplayTagQuery = GameplayTagQuery.from_dict(dict_query)
	assert(query_from_dict.evaluate(container), "Dictionary-built query should pass")

static func _test_stack_container() -> void:
	var stack_container: GameplayTagStackContainer = GameplayTagStackContainer.new()
	var new_count: int = stack_container.add_stack(&"Status.Burning.Intense", 3)
	assert(new_count == 3, "Stack add should return new count")
	assert(stack_container.has_tag(&"Status", false), "Stack container should support hierarchy checks")

	var reduced_count: int = stack_container.remove_stack(&"Status.Burning.Intense", 2)
	assert(reduced_count == 1, "Stack remove should decrement count")
	assert(stack_container.get_stack_count(&"Status.Burning.Intense") == 1)

	var final_count: int = stack_container.remove_stack(&"Status.Burning.Intense", 1)
	assert(final_count == 0, "Removing final stack should clear tag")
	assert(not stack_container.has_tag(&"Status.Burning.Intense", true))

	var converted: GameplayTagContainer = stack_container.to_container()
	assert(converted.is_empty(), "Converted container should be empty after stack clears")

static func _test_default_config_path() -> void:
	var manager: Object = _new_manager()
	assert(
		str(manager.call("get_default_config_path")) == DEFAULT_CONFIG_PATH,
		"GameplayTags should default to the project config directory"
	)

static func _test_registry_validation() -> void:
	var manager: Object = _new_manager()
	manager.set("_explicit_tags", {&"Status.Burning": true, &"Bad Tag": true})

	var issues: Array = manager.call("validate_registry")
	assert(issues.size() == 1, "Validation should report malformed explicit tags")
	assert(String(issues[0]).contains("Bad Tag"), "Validation should include the malformed tag name")

static func _test_editor_reference_hits() -> void:
	var dock: Object = _new_dock()
	var hits: Array = dock.call(
		"_extract_reference_hits_from_text",
		"res://tests/mock_reference.gd",
		["Status", "Status.Burning"],
		"tag = &\"Status.Burning\"\ncheck_parent = &\"Status\"\nignore = &\"Status.BurningExtra\""
	)

	assert(hits.size() == 2, "Reference scan should keep exact tag hits and ignore embedded suffixes")
	assert(String((hits[0] as Dictionary).get("matched_tag", "")) == "Status.Burning")
	assert(int((hits[0] as Dictionary).get("line", 0)) == 1)
	assert(String((hits[1] as Dictionary).get("matched_tag", "")) == "Status")
	assert(int((hits[1] as Dictionary).get("line", 0)) == 2)

static func _test_editor_replace_and_sibling() -> void:
	var dock: Object = _new_dock()
	var replacement: Dictionary = dock.call(
		"_replace_tag_references_in_text",
		"value = &\"Status.Burning\"\nparent = &\"Status\"\nignore = &\"Status.BurningExtra\"",
		[
			{"old": "Status.Burning", "new": "Condition.Burning"},
			{"old": "Status", "new": "Condition"}
		]
	)

	assert(int(replacement.get("count", 0)) == 2, "Replace should only touch exact tag references")
	assert(String(replacement.get("text", "")).contains("Condition.Burning"))
	assert(String(replacement.get("text", "")).contains("Condition\""))
	assert(String(replacement.get("text", "")).contains("Status.BurningExtra"))
	assert(str(dock.call("_get_sibling_prefix", "Status.Burning")) == "Status.")
	assert(str(dock.call("_get_sibling_prefix", "Status")) == "")

static func _test_inspector_hint_markers() -> void:
	var inspector_plugin: Object = _new_inspector_plugin()
	assert(
		str(inspector_plugin.call("_resolve_property_mode", TYPE_STRING_NAME, "gameplay_tag")) == "gameplay_tag"
	)
	assert(
		str(inspector_plugin.call("_resolve_property_mode", TYPE_STRING, "gameplay_tag")) == "gameplay_tag"
	)
	assert(
		str(inspector_plugin.call("_resolve_property_mode", TYPE_ARRAY, "gameplay_tags")) == "gameplay_tags"
	)
	assert(str(inspector_plugin.call("_extract_marker", "gameplay_tags,unused")) == "gameplay_tags")
	assert(str(inspector_plugin.call("_resolve_property_mode", TYPE_ARRAY, "gameplay_tag")).is_empty())

static func _test_inspector_opt_in_field() -> void:
	var actor_script: Script = load(CHARACTER_ACTOR_SCRIPT_PATH)
	assert(actor_script != null, "CharacterActor script should exist")
	var actor_instance: Variant = actor_script.new()
	assert(actor_instance != null, "CharacterActor instance should be creatable")

	var found_property: bool = false
	for property_info_variant in actor_instance.get_property_list():
		if not (property_info_variant is Dictionary):
			continue
		var property_info: Dictionary = property_info_variant
		if str(property_info.get("name", "")) != "interaction_state_tag":
			continue
		found_property = true
		assert(
			int(property_info.get("type", TYPE_NIL)) == TYPE_STRING_NAME,
			"interaction_state_tag should remain a StringName export"
		)
		assert(
			str(property_info.get("hint_string", "")) == "gameplay_tag",
			"interaction_state_tag should opt into the gameplay tag inspector picker"
		)
		break

	assert(found_property, "interaction_state_tag should be exposed in the inspector")

static func _new_manager() -> Object:
	var manager_script: Script = load(MANAGER_SCRIPT_PATH)
	assert(manager_script != null, "GameplayTags manager script should exist")
	var manager_instance: Variant = manager_script.new()
	assert(manager_instance != null, "GameplayTags manager instance should be creatable")
	return manager_instance

static func _new_dock() -> Object:
	var dock_script: Script = load(DOCK_SCRIPT_PATH)
	assert(dock_script != null, "GameplayTags dock script should exist")
	var dock_instance: Variant = dock_script.new()
	assert(dock_instance != null, "GameplayTags dock instance should be creatable")
	return dock_instance

static func _new_inspector_plugin() -> Object:
	var inspector_plugin_script: Script = load(INSPECTOR_PLUGIN_SCRIPT_PATH)
	assert(inspector_plugin_script != null, "GameplayTags inspector plugin script should exist")
	var inspector_plugin_instance: Variant = inspector_plugin_script.new()
	assert(inspector_plugin_instance != null, "GameplayTags inspector plugin instance should be creatable")
	return inspector_plugin_instance

static func _write_temp_config(lines: Array[String]) -> void:
	var file: FileAccess = FileAccess.open(TEMP_CONFIG_PATH, FileAccess.WRITE)
	assert(file != null, "Temp config should be writable")
	for line in lines:
		file.store_line(line)
