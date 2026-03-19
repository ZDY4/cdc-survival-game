# tests/functional/unit/test_gameplay_tags.gd
# Gameplay Tags 单元测试 - Functional Layer

extends Node
class_name FunctionalTest_GameplayTags

const TEMP_CONFIG_PATH: String = "user://gameplay_tags_test.ini"
const MANAGER_SCRIPT_PATH: String = "res://addons/gameplay_tags/runtime/gameplay_tags_manager.gd"
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

static func _new_manager() -> Object:
	var manager_script: Script = load(MANAGER_SCRIPT_PATH)
	assert(manager_script != null, "GameplayTags manager script should exist")
	var manager_instance: Variant = manager_script.new()
	assert(manager_instance != null, "GameplayTags manager instance should be creatable")
	return manager_instance

static func _write_temp_config(lines: Array[String]) -> void:
	var file: FileAccess = FileAccess.open(TEMP_CONFIG_PATH, FileAccess.WRITE)
	assert(file != null, "Temp config should be writable")
	for line in lines:
		file.store_line(line)
