extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const AiRecordValidator = preload("res://scripts/tools/ai_record_validator.gd")
const ContentBasicRecordValidator = preload("res://scripts/tools/content_basic_record_validator.gd")
const ContentSchemaMigration = preload("res://scripts/data/content_schema_migration.gd")
const JsonSourceLocator = preload("res://scripts/tools/json_source_locator.gd")
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
	var source_text := _read_source_text(path)
	var source_locator := JsonSourceLocator.new()
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
		var source_location := source_locator.locate(source_text, json_path) if not source_text.is_empty() else {}
		if not source_location.is_empty():
			data["line"] = int(source_location.get("line", 0))
			data["column"] = int(source_location.get("column", 0))
			data["line_column"] = "%d:%d" % [int(data["line"]), int(data["column"])]
		data["location"] = _format_location(relative_path, json_path, data)
		output.append(data)
	return output


func _normalize_json_path(field: String) -> String:
	var normalized := _normalize_json_path_separators(field.strip_edges())
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


func _normalize_json_path_separators(field: String) -> String:
	var output := ""
	var in_bracket := false
	var in_string := false
	var quote := ""
	var escaped := false
	for i in range(field.length()):
		var current := field[i]
		if in_string:
			output += current
			if escaped:
				escaped = false
			elif current == "\\":
				escaped = true
			elif current == quote:
				in_string = false
			continue
		if in_bracket and (current == "\"" or current == "'"):
			in_string = true
			quote = current
			output += current
			continue
		if current == "[":
			in_bracket = true
			output += current
			continue
		if current == "]":
			in_bracket = false
			output += current
			continue
		if not in_bracket and (current == "\\" or current == "/"):
			output += "."
			continue
		output += current
	return output


func _repo_relative_path(path: String) -> String:
	var normalized: String = path.replace("\\", "/")
	var marker := "/data/"
	var index := normalized.find(marker)
	if index >= 0:
		return normalized.substr(index + 1)
	return normalized


func _format_location(relative_path: String, json_path: String, issue: Dictionary) -> String:
	var line_column := str(issue.get("line_column", "")).strip_edges()
	var path_part := relative_path if not relative_path.is_empty() else "<unknown>"
	if not line_column.is_empty() and relative_path != "<unknown>":
		return "%s:%s:%s" % [path_part, line_column, json_path]
	if not relative_path.is_empty():
		return "%s:%s" % [relative_path, json_path]
	return json_path


func _read_source_text(path: String) -> String:
	if path.strip_edges().is_empty() or not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


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
	elif str(resolved_asset.get("resource_path", "")).get_extension().to_lower() == "tscn":
		_validate_sprite_rig_scene(str(resolved_asset.get("resource_path", "")), issues)


func _validate_sprite_rig_scene(scene_path: String, issues: Array[Dictionary]) -> void:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		issues.append(_issue("error", "$.base_model_asset", "sprite_rig_scene_load_failed", "sprite rig scene failed to load: %s" % scene_path))
		return
	var instance := packed.instantiate()
	if instance == null:
		issues.append(_issue("error", "$.base_model_asset", "sprite_rig_scene_instance_failed", "sprite rig scene failed to instantiate: %s" % scene_path))
		return
	var profile: Resource = instance.get("profile") if instance.get("profile") is Resource else null
	instance.free()
	if profile == null:
		issues.append(_issue("error", "$.base_model_asset", "sprite_rig_profile_missing", "sprite rig scene must expose a SpriteRigProfile in profile"))
		return
	var yaw_step := int(profile.get("yaw_step_degrees"))
	var pitch_step := int(profile.get("pitch_step_degrees"))
	if yaw_step <= 0 or 360 % yaw_step != 0:
		issues.append(_issue("error", "$.base_model_asset.profile.yaw_step_degrees", "sprite_rig_invalid_yaw_step", "yaw step must divide 360"))
	if pitch_step <= 0 or 180 % pitch_step != 0:
		issues.append(_issue("error", "$.base_model_asset.profile.pitch_step_degrees", "sprite_rig_invalid_pitch_step", "pitch step must divide 180"))
	var bones: Array = profile.get("bones") if typeof(profile.get("bones")) == TYPE_ARRAY else []
	var bone_names := {}
	for bone in bones:
		var resource := bone as Resource
		if resource == null:
			continue
		var name := str(resource.get("name")).strip_edges()
		if name.is_empty():
			continue
		bone_names[name] = true
	var sprites: Array = profile.get("sprites") if typeof(profile.get("sprites")) == TYPE_ARRAY else []
	for sprite_index in range(sprites.size()):
		var part: Resource = sprites[sprite_index] as Resource
		if part == null:
			issues.append(_issue("error", "$.base_model_asset.profile.sprites[%d]" % sprite_index, "sprite_rig_part_invalid", "sprite rig part must be a resource"))
			continue
		var part_id := str(part.get("id")).strip_edges()
		var bone_name := str(part.get("bone")).strip_edges()
		if part_id.is_empty():
			issues.append(_issue("error", "$.base_model_asset.profile.sprites[%d].id" % sprite_index, "sprite_rig_part_id_empty", "sprite rig part id is required"))
		if not bone_name.is_empty() and not bone_names.has(bone_name):
			issues.append(_issue("error", "$.base_model_asset.profile.sprites[%d].bone" % sprite_index, "sprite_rig_unknown_bone", "sprite rig part %s references unknown bone %s" % [part_id, bone_name]))
		var textures: Dictionary = part.get("angle_to_texture") if typeof(part.get("angle_to_texture")) == TYPE_DICTIONARY else {}
		for yaw in _angle_range(0, 360 - yaw_step, yaw_step):
			for pitch in _angle_range(-90, 90, pitch_step):
				var key := _sprite_rig_key(yaw, pitch)
				if not textures.has(key) or textures.get(key) == null:
					issues.append(_issue("error", "$.base_model_asset.profile.sprites[%d].angle_to_texture.%s" % [sprite_index, key], "sprite_rig_texture_missing", "sprite rig part %s missing texture %s" % [part_id, key]))


func _angle_range(start: int, end: int, step: int) -> Array[int]:
	var output: Array[int] = []
	if step <= 0:
		return output
	var value := start
	while value <= end:
		output.append(value)
		value += step
	return output


func _sprite_rig_key(yaw: int, pitch: int) -> String:
	var pitch_label := str(pitch) if pitch >= 0 else "neg%s" % abs(pitch)
	return "yaw_%03d_pitch_%s" % [yaw, pitch_label]


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
