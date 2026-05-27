extends RefCounted

const ContentPaths = preload("res://scripts/data/content_paths.gd")
const ContentRecordValidator = preload("res://scripts/tools/content_record_validator.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")

const SUPPORTED_DOMAINS := ["items", "recipes", "characters", "maps"]
const MAP_OBJECT_FIELD_TYPES := {
	"anchor.x": "int",
	"anchor.y": "int",
	"anchor.z": "int",
	"footprint.width": "int",
	"footprint.height": "int",
	"rotation": "string",
	"blocks_movement": "bool",
	"blocks_sight": "bool",
}

const EDITABLE_FIELDS := {
	"items": [
		"name",
		"description",
		"icon_path",
		"value",
		"weight",
	],
	"recipes": [
		"name",
		"description",
		"category",
		"craft_time",
		"experience_reward",
		"is_default_unlocked",
	],
	"characters": [
		"identity.display_name",
		"identity.description",
		"faction.camp_id",
		"faction.disposition",
		"combat.behavior",
	],
	"maps": [
		"name",
	],
}

const FIELD_TYPES := {
	"items": {
		"name": "string",
		"description": "string",
		"icon_path": "string",
		"value": "int",
		"weight": "float",
	},
	"recipes": {
		"name": "string",
		"description": "string",
		"category": "string",
		"craft_time": "float",
		"experience_reward": "int",
		"is_default_unlocked": "bool",
	},
	"characters": {
		"identity.display_name": "string",
		"identity.description": "string",
		"faction.camp_id": "string",
		"faction.disposition": "string",
		"combat.behavior": "string",
	},
	"maps": {
		"name": "string",
	},
}


func supports_domain(domain: String) -> bool:
	return SUPPORTED_DOMAINS.has(domain)


func editable_fields(domain: String) -> Array[String]:
	var fields: Array[String] = []
	for field in EDITABLE_FIELDS.get(domain, []):
		fields.append(str(field))
	return fields


func field_type(domain: String, field_path: String) -> String:
	return str(_dictionary_or_empty(FIELD_TYPES.get(domain, {})).get(field_path, "string"))


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
	if path.is_empty():
		return _failed("missing_path", "record has no source path")
	if not bool(options.get("allow_external_path", false)) and not _is_under_data_root(path):
		return _failed("path_outside_data", "refusing to write outside data root: %s" % path)

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

	var formatted := JSON.stringify(next_data, "  ") + "\n"
	if formatted.strip_edges().is_empty():
		return _failed("serialize_failed", "failed to serialize patched content")

	var before_text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var changed := before_text != formatted
	if not bool(options.get("dry_run", false)) and changed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return _failed("write_failed", "failed to open %s for write: %s" % [path, error_string(FileAccess.get_open_error())])
		file.store_string(formatted)

	return {
		"ok": true,
		"status": "ok",
		"domain": domain,
		"id": id_value,
		"path": path,
		"relative_path": _repo_relative_path(path),
		"changed": changed,
		"changed_fields": changed_fields,
		"dry_run": bool(options.get("dry_run", false)),
	}


func map_object_editable_fields() -> Array[String]:
	var fields: Array[String] = []
	for field in MAP_OBJECT_FIELD_TYPES.keys():
		fields.append(str(field))
	fields.sort()
	return fields


func map_object_field_type(field_path: String) -> String:
	return str(MAP_OBJECT_FIELD_TYPES.get(field_path, "string"))


func normalize_map_object_patch(raw_patch: Dictionary) -> Dictionary:
	var patch: Dictionary = {}
	for field in raw_patch.keys():
		var field_path := str(field)
		patch[field_path] = _coerce_value(raw_patch[field], map_object_field_type(field_path))
	return patch


func save_map_object_patch(map_id: String, object_id: String, patch: Dictionary, registry: ContentRegistry, options: Dictionary = {}) -> Dictionary:
	if patch.is_empty():
		return _failed("empty_patch", "patch must contain at least one editable map object field")

	var record: Dictionary = registry.get_library("maps").get(map_id, {})
	if record.is_empty():
		return _failed("not_found", "map record not found: %s" % map_id)

	var path := str(record.get("path", ""))
	if path.is_empty():
		return _failed("missing_path", "map record has no source path")
	if not bool(options.get("allow_external_path", false)) and not _is_under_data_root(path):
		return _failed("path_outside_data", "refusing to write outside data root: %s" % path)

	var next_data: Dictionary = _dictionary_or_empty(record.get("data", {})).duplicate(true)
	var objects: Array = _array_or_empty(next_data.get("objects", []))
	var object_index := _map_object_index(objects, object_id)
	if object_index < 0:
		return _failed("object_not_found", "map object not found: %s in %s" % [object_id, map_id])

	var normalized_patch := normalize_map_object_patch(patch)
	var object_data: Dictionary = _dictionary_or_empty(objects[object_index]).duplicate(true)
	var changed_fields: Array[String] = []
	for field in normalized_patch.keys():
		var field_path := str(field)
		if not MAP_OBJECT_FIELD_TYPES.has(field_path):
			return _failed("unsupported_field", "field %s is not editable for map objects" % field_path)
		var before: Variant = _get_field(object_data, field_path)
		var after: Variant = normalized_patch[field]
		if before != after:
			_set_field(object_data, field_path, after)
			changed_fields.append(field_path)
	objects[object_index] = object_data
	next_data["objects"] = objects

	var validation := _validate_data("maps", map_id, record, next_data, registry)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"status": "invalid",
			"code": "validation_failed",
			"message": "patched map object did not pass record validation",
			"issues": validation.get("issues", []),
			"changed_fields": changed_fields,
			"path": path,
			"map_id": map_id,
			"object_id": object_id,
		}

	var formatted := JSON.stringify(next_data, "  ") + "\n"
	var before_text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var changed := before_text != formatted
	if not bool(options.get("dry_run", false)) and changed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return _failed("write_failed", "failed to open %s for write: %s" % [path, error_string(FileAccess.get_open_error())])
		file.store_string(formatted)

	return {
		"ok": true,
		"status": "ok",
		"domain": "maps",
		"id": map_id,
		"map_id": map_id,
		"object_id": object_id,
		"path": path,
		"relative_path": _repo_relative_path(path),
		"changed": changed,
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
	return editable_fields(domain).has(field_path)


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


func _map_object_index(objects: Array, object_id: String) -> int:
	for i in range(objects.size()):
		var object: Dictionary = _dictionary_or_empty(objects[i])
		if str(object.get("object_id", "")) == object_id:
			return i
	return -1


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


func _is_under_data_root(path: String) -> bool:
	var normalized := path.replace("\\", "/").simplify_path()
	var root := ContentPaths.data_root().replace("\\", "/").simplify_path()
	return normalized == root or normalized.begins_with(root + "/")


func _repo_relative_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	var repo_root := ContentPaths.repo_root().replace("\\", "/")
	if normalized.begins_with(repo_root + "/"):
		return normalized.substr(repo_root.length() + 1)
	return normalized


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


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
