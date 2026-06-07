extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")

const COLLECTIONS := [
	"conditions",
	"facts",
	"fact_groups",
	"score_rules",
	"goals",
	"goal_groups",
	"actions",
	"action_groups",
	"executors",
	"behaviors",
	"schedule_templates",
	"need_profiles",
	"personality_profiles",
	"smart_object_access_profiles",
]
const DAYS := ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


func supports_domain(domain: String) -> bool:
	return domain == "ai"


func validate_record(_domain: String, id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var index := ai_index(registry)
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	_validate_record_shape(id_value, data, index, issues)
	_validate_cross_references(index, issues)
	_validate_character_life_refs(index, registry, issues)


func ai_index(registry: ContentRegistry) -> Dictionary:
	var index := {}
	for collection in COLLECTIONS:
		index[collection] = {}
	for record_id in registry.get_library("ai").keys():
		var record: Dictionary = _dictionary_or_empty(registry.get_library("ai").get(record_id, {}))
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var path := str(record.get("path", ""))
		if data.has("id"):
			_add_index_record(index, "behaviors", data, path, "$")
		for collection in COLLECTIONS:
			if collection == "behaviors":
				continue
			for i in range(_array_or_empty(data.get(collection, [])).size()):
				_add_index_record(index, collection, _dictionary_or_empty(data[collection][i]), path, "$.%s[%d]" % [collection, i])
	return index


func has_ai_id(index: Dictionary, collection: String, id_value: Variant) -> bool:
	var normalized := ContentRegistry.normalize_content_id(id_value)
	return not normalized.is_empty() and _dictionary_or_empty(index.get(collection, {})).has(normalized)


func _validate_record_shape(id_value: String, data: Dictionary, index: Dictionary, issues: Array[Dictionary]) -> void:
	if data.has("id"):
		if ContentRegistry.normalize_content_id(data.get("id", "")) != id_value:
			issues.append(_issue("error", "$.id", "id_mismatch", "AI behavior id must match requested id %s" % id_value))
		_validate_behavior(data, "$", index, issues)
		return
	var known_collection := false
	for collection in COLLECTIONS:
		if collection == "behaviors":
			continue
		if not data.has(collection):
			continue
		known_collection = true
		if typeof(data.get(collection)) != TYPE_ARRAY:
			issues.append(_issue("error", "$.%s" % collection, "expected_array", "%s must be an array" % collection))
			continue
		var values: Array = data.get(collection, [])
		for i in range(values.size()):
			var entry := _dictionary_or_empty(values[i])
			var field := "$.%s[%d]" % [collection, i]
			_validate_collection_entry(collection, entry, field, index, issues)
	if not known_collection:
		issues.append(_issue("warning", "$", "unknown_ai_pack", "AI file does not define a known AI content collection"))


func _validate_collection_entry(collection: String, entry: Dictionary, field: String, index: Dictionary, issues: Array[Dictionary]) -> void:
	_expect_non_empty_id(entry, field, issues)
	match collection:
		"conditions":
			_validate_condition(_dictionary_or_empty(entry.get("condition", {})), field.path_join("condition"), index, issues)
		"facts":
			_validate_condition(_dictionary_or_empty(entry.get("condition", {})), field.path_join("condition"), index, issues)
		"fact_groups":
			_validate_id_array(entry.get("fact_ids", []), field.path_join("fact_ids"), "facts", "unknown_fact", index, issues)
		"score_rules":
			if entry.has("when"):
				_validate_condition(_dictionary_or_empty(entry.get("when", {})), field.path_join("when"), index, issues)
			if not entry.has("score_delta"):
				issues.append(_issue("error", field.path_join("score_delta"), "missing_number", "score_delta is required"))
		"goals":
			_validate_id_array(entry.get("score_rule_ids", []), field.path_join("score_rule_ids"), "score_rules", "unknown_score_rule", index, issues)
			_validate_planner_assignments(entry.get("planner_requirements", []), field.path_join("planner_requirements"), issues)
			for i in range(_array_or_empty(entry.get("conditional_requirements", [])).size()):
				var conditional := _dictionary_or_empty(entry["conditional_requirements"][i])
				var conditional_field := field.path_join("conditional_requirements[%d]" % i)
				if conditional.has("when"):
					_validate_condition(_dictionary_or_empty(conditional.get("when", {})), conditional_field.path_join("when"), index, issues)
				_validate_planner_assignments(conditional.get("requirements", []), conditional_field.path_join("requirements"), issues)
		"goal_groups":
			_validate_id_array(entry.get("goal_ids", []), field.path_join("goal_ids"), "goals", "unknown_goal", index, issues)
		"actions":
			_validate_action(entry, field, index, issues)
		"action_groups":
			_validate_id_array(entry.get("action_ids", []), field.path_join("action_ids"), "actions", "unknown_action", index, issues)
		"executors":
			_expect_non_empty_string(entry, "kind", field.path_join("kind"), issues)
		"schedule_templates":
			_validate_schedule_template(entry, field, issues)
		"need_profiles":
			for key in ["hunger_decay_per_hour", "energy_decay_per_hour", "morale_decay_per_hour", "safety_bias"]:
				if entry.has(key):
					_expect_number_at_least(entry, key, field.path_join(key), 0.0, issues)
		"personality_profiles":
			for key in ["safety_bias", "social_bias", "duty_bias", "comfort_bias", "alertness_bias"]:
				if entry.has(key):
					_expect_number_at_least(entry, key, field.path_join(key), 0.0, issues)
		"smart_object_access_profiles":
			_validate_access_profile(entry, field, issues)


func _validate_behavior(entry: Dictionary, field: String, index: Dictionary, issues: Array[Dictionary]) -> void:
	_expect_non_empty_id(entry, field, issues)
	_validate_id_array(entry.get("included_behavior_ids", []), field.path_join("included_behavior_ids"), "behaviors", "unknown_behavior", index, issues)
	_validate_id_array(entry.get("fact_group_ids", []), field.path_join("fact_group_ids"), "fact_groups", "unknown_fact_group", index, issues)
	_validate_id_array(entry.get("fact_ids", []), field.path_join("fact_ids"), "facts", "unknown_fact", index, issues)
	_validate_id_array(entry.get("goal_group_ids", []), field.path_join("goal_group_ids"), "goal_groups", "unknown_goal_group", index, issues)
	_validate_id_array(entry.get("goal_ids", []), field.path_join("goal_ids"), "goals", "unknown_goal", index, issues)
	_validate_id_array(entry.get("action_group_ids", []), field.path_join("action_group_ids"), "action_groups", "unknown_action_group", index, issues)
	_validate_id_array(entry.get("action_ids", []), field.path_join("action_ids"), "actions", "unknown_action", index, issues)
	_validate_optional_id_ref(entry.get("default_goal_id", ""), field.path_join("default_goal_id"), "goals", "unknown_goal", index, issues)
	_validate_optional_id_ref(entry.get("alert_goal_id", ""), field.path_join("alert_goal_id"), "goals", "unknown_goal", index, issues)


func _validate_action(entry: Dictionary, field: String, index: Dictionary, issues: Array[Dictionary]) -> void:
	_validate_planner_assignments(entry.get("preconditions", []), field.path_join("preconditions"), issues)
	_validate_planner_assignments(entry.get("effects", []), field.path_join("effects"), issues)
	_expect_number_at_least(entry, "planner_cost", field.path_join("planner_cost"), 0.0, issues)
	_validate_optional_id_ref(entry.get("executor_binding_id", ""), field.path_join("executor_binding_id"), "executors", "unknown_executor", index, issues, false)
	_validate_id_array(entry.get("expected_fact_ids", []), field.path_join("expected_fact_ids"), "facts", "unknown_fact", index, issues)
	for key in ["default_travel_minutes", "perform_minutes"]:
		if entry.has(key):
			_expect_number_at_least(entry, key, field.path_join(key), 0.0, issues)


func _validate_condition(condition: Dictionary, field: String, index: Dictionary, issues: Array[Dictionary]) -> void:
	if condition.is_empty():
		issues.append(_issue("error", field, "missing_condition", "AI condition is required"))
		return
	match str(condition.get("kind", "")):
		"condition_ref":
			_validate_optional_id_ref(condition.get("condition_id", ""), field.path_join("condition_id"), "conditions", "unknown_condition", index, issues, false)
		"fact_true":
			_validate_optional_id_ref(condition.get("fact_id", ""), field.path_join("fact_id"), "facts", "unknown_fact", index, issues, false)
		"bool_equals":
			_expect_non_empty_string(condition, "key", field.path_join("key"), issues)
			if typeof(condition.get("value")) != TYPE_BOOL:
				issues.append(_issue("error", field.path_join("value"), "expected_bool", "bool_equals value must be a boolean"))
		"number_compare":
			_expect_non_empty_string(condition, "key", field.path_join("key"), issues)
			if not ["less_than", "less_than_or_equal", "equal", "greater_than_or_equal", "greater_than"].has(str(condition.get("op", ""))):
				issues.append(_issue("error", field.path_join("op"), "unknown_compare_op", "unsupported number compare op %s" % condition.get("op", "")))
			if not condition.has("value"):
				issues.append(_issue("error", field.path_join("value"), "missing_number", "number_compare value is required"))
		"text_equals":
			_expect_non_empty_string(condition, "key", field.path_join("key"), issues)
			_expect_non_empty_string(condition, "value", field.path_join("value"), issues)
		"text_key_equals":
			_expect_non_empty_string(condition, "left_key", field.path_join("left_key"), issues)
			_expect_non_empty_string(condition, "right_key", field.path_join("right_key"), issues)
		"role_is":
			_expect_non_empty_string(condition, "role", field.path_join("role"), issues)
		"all_of", "any_of":
			var conditions := _array_or_empty(condition.get("conditions", []))
			if conditions.is_empty():
				issues.append(_issue("error", field.path_join("conditions"), "missing_condition", "compound condition must contain children"))
			for i in range(conditions.size()):
				_validate_condition(_dictionary_or_empty(conditions[i]), field.path_join("conditions[%d]" % i), index, issues)
		"not":
			_validate_condition(_dictionary_or_empty(condition.get("condition", {})), field.path_join("condition"), index, issues)
		_:
			issues.append(_issue("error", field.path_join("kind"), "unknown_condition_kind", "unsupported AI condition kind %s" % condition.get("kind", "")))


func _validate_schedule_template(entry: Dictionary, field: String, issues: Array[Dictionary]) -> void:
	for i in range(_array_or_empty(entry.get("blocks", [])).size()):
		var block := _dictionary_or_empty(entry["blocks"][i])
		var block_field := field.path_join("blocks[%d]" % i)
		var days := _array_or_empty(block.get("days", []))
		for day_index in range(days.size()):
			if not DAYS.has(str(days[day_index])):
				issues.append(_issue("error", block_field.path_join("days[%d]" % day_index), "unknown_day", "unknown schedule day %s" % days[day_index]))
		_expect_number_range(block, "start_minute", block_field.path_join("start_minute"), 0.0, 1440.0, issues)
		_expect_number_range(block, "end_minute", block_field.path_join("end_minute"), 0.0, 1440.0, issues)


func _validate_access_profile(entry: Dictionary, field: String, issues: Array[Dictionary]) -> void:
	for i in range(_array_or_empty(entry.get("rules", [])).size()):
		var rule := _dictionary_or_empty(entry["rules"][i])
		var rule_field := field.path_join("rules[%d]" % i)
		_expect_non_empty_string(rule, "kind", rule_field.path_join("kind"), issues)
		if rule.has("preferred_tags"):
			_validate_string_array(rule.get("preferred_tags", []), rule_field.path_join("preferred_tags"), issues)
		if rule.has("fallback_to_any") and typeof(rule.get("fallback_to_any")) != TYPE_BOOL:
			issues.append(_issue("error", rule_field.path_join("fallback_to_any"), "expected_bool", "fallback_to_any must be a boolean"))


func _validate_cross_references(index: Dictionary, issues: Array[Dictionary]) -> void:
	for collection in COLLECTIONS:
		var ids := {}
		for id_value in _dictionary_or_empty(index.get(collection, {})).keys():
			var entries: Array = _dictionary_or_empty(index.get(collection, {})).get(id_value, [])
			if entries.size() > 1:
				var first: Dictionary = _dictionary_or_empty(entries[0])
				issues.append(_issue("error", str(first.get("field", "$")).path_join("id"), "duplicate_ai_id", "duplicate AI %s id %s" % [collection.trim_suffix("s"), id_value]))
			ids[id_value] = true


func _validate_character_life_refs(index: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	for character_id in registry.get_library("characters").keys():
		var record: Dictionary = _dictionary_or_empty(registry.get_library("characters").get(character_id, {}))
		var life: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record.get("data", {})).get("life", {}))
		if life.is_empty():
			continue
		_validate_optional_id_ref(life.get("ai_behavior_profile_id", ""), "$.characters.%s.life.ai_behavior_profile_id" % character_id, "behaviors", "unknown_ai_behavior", index, issues, false)
		_validate_optional_id_ref(life.get("schedule_profile_id", ""), "$.characters.%s.life.schedule_profile_id" % character_id, "schedule_templates", "unknown_schedule_template", index, issues, false)
		_validate_optional_id_ref(life.get("personality_profile_id", ""), "$.characters.%s.life.personality_profile_id" % character_id, "personality_profiles", "unknown_personality_profile", index, issues, false)
		_validate_optional_id_ref(life.get("need_profile_id", ""), "$.characters.%s.life.need_profile_id" % character_id, "need_profiles", "unknown_need_profile", index, issues, false)
		_validate_optional_id_ref(life.get("smart_object_access_profile_id", ""), "$.characters.%s.life.smart_object_access_profile_id" % character_id, "smart_object_access_profiles", "unknown_access_profile", index, issues, false)


func _add_index_record(index: Dictionary, collection: String, data: Dictionary, path: String, field: String) -> void:
	var id_value := ContentRegistry.normalize_content_id(data.get("id", ""))
	if id_value.is_empty():
		return
	var entries: Array = _dictionary_or_empty(index.get(collection, {})).get(id_value, [])
	entries.append({
		"path": path,
		"field": field,
		"data": data,
	})
	index[collection][id_value] = entries


func _validate_id_array(values: Variant, field: String, collection: String, code: String, index: Dictionary, issues: Array[Dictionary]) -> void:
	if values == null:
		return
	if typeof(values) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of AI ids"))
		return
	var array: Array = values
	for i in range(array.size()):
		_validate_optional_id_ref(array[i], field.path_join("[%d]" % i), collection, code, index, issues, false)


func _validate_optional_id_ref(value: Variant, field: String, collection: String, code: String, index: Dictionary, issues: Array[Dictionary], allow_empty: bool = true) -> void:
	var id_value := ContentRegistry.normalize_content_id(value)
	if id_value.is_empty():
		if not allow_empty:
			issues.append(_issue("error", field, "missing_ai_ref", "AI reference is required"))
		return
	if not has_ai_id(index, collection, id_value):
		issues.append(_issue("error", field, code, "unknown AI %s id %s" % [collection.trim_suffix("s"), id_value]))


func _validate_planner_assignments(values: Variant, field: String, issues: Array[Dictionary]) -> void:
	if values == null:
		return
	if typeof(values) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of planner assignments"))
		return
	var array: Array = values
	for i in range(array.size()):
		var entry := _dictionary_or_empty(array[i])
		var entry_field := field.path_join("[%d]" % i)
		_expect_non_empty_string(entry, "key", entry_field.path_join("key"), issues)
		if not entry.has("value") or typeof(entry.get("value")) != TYPE_BOOL:
			issues.append(_issue("error", entry_field.path_join("value"), "expected_bool", "planner assignment value must be a boolean"))


func _validate_string_array(values: Variant, field: String, issues: Array[Dictionary]) -> void:
	if typeof(values) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of strings"))
		return
	var array: Array = values
	for i in range(array.size()):
		if str(array[i]).strip_edges().is_empty():
			issues.append(_issue("error", field.path_join("[%d]" % i), "missing_text", "string value must be non-empty"))


func _expect_non_empty_id(data: Dictionary, field: String, issues: Array[Dictionary]) -> void:
	if ContentRegistry.normalize_content_id(data.get("id", "")).is_empty():
		issues.append(_issue("error", field.path_join("id"), "missing_id", "AI record id is required"))


func _expect_non_empty_string(data: Dictionary, key: String, field: String, issues: Array[Dictionary]) -> void:
	if str(data.get(key, "")).strip_edges().is_empty():
		issues.append(_issue("error", field, "missing_text", "%s must be a non-empty string" % key))


func _expect_number_at_least(data: Dictionary, key: String, field: String, minimum: float, issues: Array[Dictionary]) -> void:
	if not data.has(key):
		issues.append(_issue("error", field, "missing_number", "%s is required" % key))
		return
	if float(data.get(key, 0.0)) < minimum:
		issues.append(_issue("error", field, "number_too_small", "%s must be >= %.2f" % [key, minimum]))


func _expect_number_range(data: Dictionary, key: String, field: String, minimum: float, maximum: float, issues: Array[Dictionary]) -> void:
	if not data.has(key):
		issues.append(_issue("error", field, "missing_number", "%s is required" % key))
		return
	var value := float(data.get(key, 0.0))
	if value < minimum or value > maximum:
		issues.append(_issue("error", field, "number_out_of_range", "%s must be between %.0f and %.0f" % [key, minimum, maximum]))


func _issue(severity: String, field: String, code: String, message: String) -> Dictionary:
	return {
		"severity": severity,
		"field": field,
		"code": code,
		"message": message,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
