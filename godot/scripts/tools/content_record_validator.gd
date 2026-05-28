extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentBasicRecordValidator = preload("res://scripts/tools/content_basic_record_validator.gd")
const NarrativeRecordValidator = preload("res://scripts/tools/narrative_record_validator.gd")
const WorldRecordValidator = preload("res://scripts/tools/world_record_validator.gd")

const ContentPaths = preload("res://scripts/data/content_paths.gd")

const EDITOR_DOMAINS := ["items", "recipes", "characters", "maps", "dialogues", "quests", "skills", "skill_trees", "settlements", "overworld", "appearance"]

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
		"appearance":
			_validate_appearance(id_value, record, issues)
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


func _validate_appearance(id_value: String, record: Dictionary, issues: Array[Dictionary]) -> void:
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	if ContentRegistry.normalize_content_id(data.get("id", "")) != id_value:
		issues.append(_issue("error", "$.id", "id_mismatch", "record id must match requested id %s" % id_value))
	var base_model_asset := str(data.get("base_model_asset", "")).strip_edges()
	if base_model_asset.is_empty():
		issues.append(_issue("error", "$.base_model_asset", "missing_asset", "base model asset path is required"))
		return
	if not base_model_asset.ends_with(".gltf"):
		issues.append(_issue("error", "$.base_model_asset", "invalid_asset_format", "base model asset must reference a .gltf file"))
		return
	var full_path := ContentPaths.assets_root().path_join(base_model_asset).simplify_path()
	if not FileAccess.file_exists(full_path):
		issues.append(_issue("error", "$.base_model_asset", "missing_asset_file", "asset file does not exist: %s" % full_path))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
