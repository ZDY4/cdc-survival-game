extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const AiRecordValidator = preload("res://scripts/tools/ai_record_validator.gd")
const ContentBasicRecordValidator = preload("res://scripts/tools/content_basic_record_validator.gd")
const ContentSchemaMigration = preload("res://scripts/data/content_schema_migration.gd")
const JsonRecordValidator = preload("res://scripts/tools/json_record_validator.gd")
const NarrativeRecordValidator = preload("res://scripts/tools/narrative_record_validator.gd")
const WorldRecordValidator = preload("res://scripts/tools/world_record_validator.gd")

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")

const EDITOR_DOMAINS := ["items", "recipes", "characters", "maps", "dialogues", "dialogue_rules", "quests", "skills", "skill_trees", "settlements", "overworld", "shops", "world_tiles", "appearance", "ai", "json"]

var ai_validator: AiRecordValidator = AiRecordValidator.new()
var basic_validator: ContentBasicRecordValidator = ContentBasicRecordValidator.new()
var schema_migration: ContentSchemaMigration = ContentSchemaMigration.new()
var json_validator: JsonRecordValidator = JsonRecordValidator.new()
var narrative_validator: NarrativeRecordValidator = NarrativeRecordValidator.new()
var world_validator: WorldRecordValidator = WorldRecordValidator.new()


func supports_domain(domain: String) -> bool:
	return EDITOR_DOMAINS.has(domain)


func validate_record(domain: String, id_value: String, registry: ContentRegistry) -> Dictionary:
	var issues: Array[Dictionary] = []
	var record: Dictionary = registry.get_library(domain).get(id_value, {})
	if record.is_empty():
		var not_found_issues: Array[Dictionary] = [_issue("error", "$", "not_found", "record not found in domain %s" % domain)]
		return {
			"ok": false,
			"status": "not_found",
			"schema_migration": {},
			"issues": _with_location(not_found_issues, domain, id_value, ""),
		}

	match domain:
		"items":
			basic_validator.validate_record(domain, id_value, record, registry, issues)
		"recipes":
			basic_validator.validate_record(domain, id_value, record, registry, issues)
		"characters":
			basic_validator.validate_record(domain, id_value, record, registry, issues)
			_validate_character_ai_refs(id_value, record, registry, issues)
		"maps":
			basic_validator.validate_record(domain, id_value, record, registry, issues)
		"shops":
			basic_validator.validate_record(domain, id_value, record, registry, issues)
		"world_tiles":
			basic_validator.validate_record(domain, id_value, record, registry, issues)
		"dialogues", "dialogue_rules", "quests", "skills", "skill_trees":
			narrative_validator.validate_record(domain, id_value, record, registry, issues)
		"settlements", "overworld":
			world_validator.validate_record(domain, id_value, record, registry, issues)
		"appearance":
			_validate_appearance(id_value, record, issues)
		"ai":
			ai_validator.validate_record(domain, id_value, record, registry, issues)
		"json":
			json_validator.validate_record(domain, id_value, record, registry, issues)
		_:
			issues.append(_issue("warning", "$", "shallow_validation", "record-level validation not implemented for domain %s" % domain))

	return {
		"ok": _error_count(issues) == 0,
		"status": "ok" if _error_count(issues) == 0 else "invalid",
		"schema_migration": schema_migration.diagnose(domain, id_value, record),
		"issues": _with_location(issues, domain, id_value, str(record.get("path", ""))),
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
		"json_path": _normalize_json_path(field),
		"code": code,
		"message": message,
	}


func _with_location(issues: Array[Dictionary], domain: String, id_value: String, path: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var relative_path := _repo_relative_path(path)
	for issue in issues:
		var data: Dictionary = _dictionary_or_empty(issue).duplicate(true)
		var field := str(data.get("field", "$"))
		var json_path := _normalize_json_path(str(data.get("json_path", field)))
		data["field"] = field
		data["json_path"] = json_path
		data["domain"] = domain
		data["id"] = id_value
		data["path"] = path
		data["relative_path"] = relative_path
		data["location"] = "%s:%s" % [relative_path, json_path] if not relative_path.is_empty() else json_path
		output.append(data)
	return output


func _normalize_json_path(field: String) -> String:
	var normalized := field.strip_edges().replace("\\", "/").replace("/", ".")
	while normalized.contains(".."):
		normalized = normalized.replace("..", ".")
	normalized = normalized.replace(".[", "[")
	if normalized.is_empty():
		return "$"
	if normalized.begins_with("$"):
		return normalized
	if normalized.begins_with("."):
		return "$%s" % normalized
	return "$.%s" % normalized


func _repo_relative_path(path: String) -> String:
	var normalized: String = path.replace("\\", "/")
	var marker := "/data/"
	var index := normalized.find(marker)
	if index >= 0:
		return normalized.substr(index + 1)
	return normalized


func _validate_appearance(id_value: String, record: Dictionary, issues: Array[Dictionary]) -> void:
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	if ContentRegistry.normalize_content_id(data.get("id", "")) != id_value:
		issues.append(_issue("error", "$.id", "id_mismatch", "record id must match requested id %s" % id_value))
	var base_model_asset := str(data.get("base_model_asset", "")).strip_edges()
	if base_model_asset.is_empty():
		issues.append(_issue("error", "$.base_model_asset", "missing_asset", "base model asset path is required"))
		return
	var resolved_asset := AssetPathResolver.resolve_model_asset(base_model_asset)
	if not bool(resolved_asset.get("ok", false)):
		issues.append(_issue("error", "$.base_model_asset", str(resolved_asset.get("reason", "invalid_asset_path")), str(resolved_asset.get("message", "invalid asset path"))))
	elif not bool(resolved_asset.get("exists", false)):
		issues.append(_issue("error", "$.base_model_asset", "missing_asset_file", "asset file does not exist: %s" % str(resolved_asset.get("absolute_path", ""))))


func _validate_character_ai_refs(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var life: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record.get("data", {})).get("life", {}))
	if life.is_empty():
		return
	var index := ai_validator.ai_index(registry)
	_validate_ai_ref(life.get("ai_behavior_profile_id", ""), "$.life.ai_behavior_profile_id", "behaviors", "unknown_ai_behavior", index, issues)
	_validate_ai_ref(life.get("schedule_profile_id", ""), "$.life.schedule_profile_id", "schedule_templates", "unknown_schedule_template", index, issues)
	_validate_ai_ref(life.get("personality_profile_id", ""), "$.life.personality_profile_id", "personality_profiles", "unknown_personality_profile", index, issues)
	_validate_ai_ref(life.get("need_profile_id", ""), "$.life.need_profile_id", "need_profiles", "unknown_need_profile", index, issues)
	_validate_ai_ref(life.get("smart_object_access_profile_id", ""), "$.life.smart_object_access_profile_id", "smart_object_access_profiles", "unknown_access_profile", index, issues)


func _validate_ai_ref(value: Variant, field: String, collection: String, code: String, index: Dictionary, issues: Array[Dictionary]) -> void:
	var id_value := ContentRegistry.normalize_content_id(value)
	if id_value.is_empty():
		return
	if not ai_validator.has_ai_id(index, collection, id_value):
		issues.append(_issue("error", field, code, "unknown AI %s id %s" % [collection.trim_suffix("s"), id_value]))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
