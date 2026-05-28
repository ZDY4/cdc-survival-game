extends RefCounted

const ContentEditSchema = preload("res://scripts/data/content_edit_schema.gd")
const ContentRecordValidator = preload("res://scripts/tools/content_record_validator.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentWriteService = preload("res://scripts/data/content_write_service.gd")

var _schema := ContentEditSchema.new()
var _writer := ContentWriteService.new()


func supports_domain(domain: String) -> bool:
	return _schema.supports_domain(domain)


func editable_fields(domain: String) -> Array[String]:
	return _schema.editable_fields(domain)


func field_type(domain: String, field_path: String) -> String:
	return _schema.field_type(domain, field_path)


func normalize_patch(domain: String, raw_patch: Dictionary) -> Dictionary:
	var patch: Dictionary = {}
	for field in raw_patch.keys():
		var field_path := str(field)
		patch[field_path] = _coerce_value(raw_patch[field], field_type(domain, field_path))
	return patch


func save_patch(domain: String, id_value: String, patch: Dictionary, registry: ContentRegistry, options: Dictionary = {}) -> Dictionary:
	if not supports_domain(domain):
		return _failed("unsupported_domain", "content edit service does not support domain %s" % domain)
	if patch.is_empty():
		return _failed("empty_patch", "patch must contain at least one editable field")

	var record: Dictionary = registry.get_library(domain).get(id_value, {})
	if record.is_empty():
		return _failed("not_found", "record not found: %s %s" % [domain, id_value])

	var path := str(record.get("path", ""))
	var path_check := _writer.validate_path(path, {"allow_external_path": bool(options.get("allow_external_path", false))})
	if not bool(path_check.get("ok", false)):
		return path_check

	var normalized_patch := normalize_patch(domain, patch)
	var next_data: Dictionary = _dictionary_or_empty(record.get("data", {})).duplicate(true)
	var changed_fields: Array[String] = []
	for field in normalized_patch.keys():
		var field_path := str(field)
		if not _can_edit_field(domain, field_path):
			return _failed("unsupported_field", "field %s is not editable for %s" % [field_path, domain])
		var before: Variant = _get_field(next_data, field_path)
		var after: Variant = normalized_patch[field]
		if before != after:
			_set_field(next_data, field_path, after)
			changed_fields.append(field_path)

	var validation := _validate_data(domain, id_value, record, next_data, registry)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"status": "invalid",
			"code": "validation_failed",
			"message": "patched content did not pass record validation",
			"issues": validation.get("issues", []),
			"changed_fields": changed_fields,
			"path": path,
		}

	var write_result := _writer.write_json(path, next_data, options)
	if not bool(write_result.get("ok", false)):
		return write_result

	return {
		"ok": true,
		"status": "ok",
		"domain": domain,
		"id": id_value,
		"path": path,
		"relative_path": str(write_result.get("relative_path", path)),
		"changed": bool(write_result.get("changed", false)),
		"changed_fields": changed_fields,
		"dry_run": bool(options.get("dry_run", false)),
	}


func _validate_data(domain: String, id_value: String, record: Dictionary, data: Dictionary, registry: ContentRegistry) -> Dictionary:
	var copy: ContentRegistry = ContentRegistry.new()
	copy.libraries = registry.libraries.duplicate(true)
	copy.files_by_domain = registry.files_by_domain.duplicate(true)
	copy.bootstrap_config = registry.bootstrap_config.duplicate(true)
	copy.data_root = registry.data_root
	var library: Dictionary = copy.libraries.get(domain, {}).duplicate(true)
	var next_record := record.duplicate(true)
	next_record["data"] = data
	library[id_value] = next_record
	copy.libraries[domain] = library
	return ContentRecordValidator.new().validate_record(domain, id_value, copy)


func _can_edit_field(domain: String, field_path: String) -> bool:
	return _schema.can_edit_field(domain, field_path)


func _coerce_value(value: Variant, value_type: String) -> Variant:
	match value_type:
		"int":
			return int(value)
		"float":
			return float(value)
		"bool":
			if typeof(value) == TYPE_BOOL:
				return value
			var text := str(value).strip_edges().to_lower()
			return ["true", "1", "yes", "on"].has(text)
		_:
			return str(value)


func _get_field(data: Dictionary, field_path: String) -> Variant:
	var current: Variant = data
	for part in field_path.split(".", false):
		if typeof(current) != TYPE_DICTIONARY:
			return null
		var dict: Dictionary = current
		current = dict.get(part, null)
	return current


func _set_field(data: Dictionary, field_path: String, value: Variant) -> void:
	var parts := field_path.split(".", false)
	var current := data
	for i in range(parts.size()):
		var key := parts[i]
		if i == parts.size() - 1:
			current[key] = value
			return
		if typeof(current.get(key, null)) != TYPE_DICTIONARY:
			current[key] = {}
		current = current[key]


func _failed(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": "failed",
		"code": code,
		"message": message,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
