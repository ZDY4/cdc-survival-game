extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")


func supports_domain(domain: String) -> bool:
	return domain == "json"


func validate_record(_domain: String, id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	if data.has("id") and ContentRegistry.normalize_content_id(data.get("id", "")) != id_value:
		issues.append(_issue("error", "$.id", "id_mismatch", "legacy JSON id must match requested id %s" % id_value))
	if _is_effect_record(data, str(record.get("path", ""))):
		_validate_effect(id_value, data, issues)
	_validate_recursive_item_refs(data, "$", registry, issues)


func _is_effect_record(data: Dictionary, path: String) -> bool:
	return path.replace("\\", "/").contains("/json/effects/") or data.has("stat_modifiers") or data.has("special_effects") or data.has("gameplay_effect")


func _validate_effect(id_value: String, data: Dictionary, issues: Array[Dictionary]) -> void:
	if ContentRegistry.normalize_content_id(data.get("id", "")) != id_value:
		issues.append(_issue("error", "$.id", "id_mismatch", "effect id must match requested id %s" % id_value))
	_expect_non_empty_string(data, "name", "$.name", issues)
	if data.has("duration"):
		_expect_number_at_least(data, "duration", "$.duration", 0.0, issues)
	if data.has("tick_interval"):
		_expect_number_at_least(data, "tick_interval", "$.tick_interval", 0.0, issues)
	if data.has("max_stacks"):
		_expect_number_at_least(data, "max_stacks", "$.max_stacks", 1.0, issues)
	if data.has("special_effects"):
		_validate_string_array(data.get("special_effects", []), "$.special_effects", issues)
	if data.has("stat_modifiers") and typeof(data.get("stat_modifiers")) != TYPE_DICTIONARY:
		issues.append(_issue("error", "$.stat_modifiers", "expected_dictionary", "stat_modifiers must be a dictionary"))
	if data.has("gameplay_effect") and data.get("gameplay_effect") != null and typeof(data.get("gameplay_effect")) != TYPE_DICTIONARY:
		issues.append(_issue("error", "$.gameplay_effect", "expected_dictionary", "gameplay_effect must be a dictionary when present"))


func _validate_recursive_item_refs(value: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			var data: Dictionary = value
			for key in data.keys():
				var key_string := str(key)
				var child_field := field.path_join(key_string)
				var child_value: Variant = data[key]
				if ["item", "item_id", "itemId", "tool_id", "toolId"].has(key_string):
					_validate_item_ref(child_value, child_field, registry, issues)
				else:
					_validate_recursive_item_refs(child_value, child_field, registry, issues)
		TYPE_ARRAY:
			var values: Array = value
			for i in range(values.size()):
				_validate_recursive_item_refs(values[i], field.path_join("[%d]" % i), registry, issues)


func _validate_item_ref(value: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var normalized := ContentRegistry.normalize_content_id(value)
	if normalized.is_empty() or normalized == "<null>":
		issues.append(_issue("error", field, "missing_item", "item reference is required"))
		return
	if not registry.has_id("items", normalized):
		issues.append(_issue("error", field, "unknown_item", "unknown item id %s" % normalized))


func _validate_string_array(value: Variant, field: String, issues: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of strings"))
		return
	var values: Array = value
	for i in range(values.size()):
		if str(values[i]).strip_edges().is_empty():
			issues.append(_issue("error", field.path_join("[%d]" % i), "missing_text", "string value must be non-empty"))


func _expect_non_empty_string(data: Dictionary, key: String, field: String, issues: Array[Dictionary]) -> void:
	if str(data.get(key, "")).strip_edges().is_empty():
		issues.append(_issue("error", field, "missing_text", "%s must be a non-empty string" % key))


func _expect_number_at_least(data: Dictionary, key: String, field: String, minimum: float, issues: Array[Dictionary]) -> void:
	if not data.has(key):
		issues.append(_issue("error", field, "missing_number", "%s is required" % key))
		return
	if float(data.get(key, 0.0)) < minimum:
		issues.append(_issue("error", field, "number_too_small", "%s must be >= %.2f" % [key, minimum]))


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
