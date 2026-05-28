extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentBasicRecordValidator = preload("res://scripts/tools/content_basic_record_validator.gd")
const NarrativeRecordValidator = preload("res://scripts/tools/narrative_record_validator.gd")
const WorldRecordValidator = preload("res://scripts/tools/world_record_validator.gd")

const EDITOR_DOMAINS := ["items", "recipes", "characters", "maps", "dialogues", "quests", "skills", "skill_trees", "settlements", "overworld"]

var basic_validator: ContentBasicRecordValidator = ContentBasicRecordValidator.new()
var narrative_validator: NarrativeRecordValidator = NarrativeRecordValidator.new()
var world_validator: WorldRecordValidator = WorldRecordValidator.new()


func supports_domain(domain: String) -> bool:
	return EDITOR_DOMAINS.has(domain)


func validate_record(domain: String, id_value: String, registry: ContentRegistry) -> Dictionary:
	var issues: Array[Dictionary] = []
	var record: Dictionary = registry.get_library(domain).get(id_value, {})
	if record.is_empty():
		return {
			"ok": false,
			"status": "not_found",
			"issues": [_issue("error", "$", "not_found", "record not found in domain %s" % domain)],
		}

	match domain:
		"items":
			basic_validator.validate_record(domain, id_value, record, registry, issues)
		"recipes":
			basic_validator.validate_record(domain, id_value, record, registry, issues)
		"characters":
			basic_validator.validate_record(domain, id_value, record, registry, issues)
		"maps":
			basic_validator.validate_record(domain, id_value, record, registry, issues)
		"dialogues", "quests", "skills", "skill_trees":
			narrative_validator.validate_record(domain, id_value, record, registry, issues)
		"settlements", "overworld":
			world_validator.validate_record(domain, id_value, record, registry, issues)
		_:
			issues.append(_issue("warning", "$", "shallow_validation", "record-level validation not implemented for domain %s" % domain))

	return {
		"ok": _error_count(issues) == 0,
		"status": "ok" if _error_count(issues) == 0 else "invalid",
		"issues": issues,
	}


func _error_count(issues: Array[Dictionary]) -> int:
	var count := 0
	for issue in issues:
		var data: Dictionary = _dictionary_or_empty(issue)
		if str(data.get("severity", "")) == "error":
			count += 1
	return count


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
