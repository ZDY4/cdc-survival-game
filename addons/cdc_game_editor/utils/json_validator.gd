@tool
extends RefCounted
## Shared JSON file/structure validator for CDC data editors.
## This helper only validates JSON file format and data shape.

const TYPE_DICTIONARY: String = "Dictionary"
const TYPE_ARRAY: String = "Array"

static func validate_file(path: String, format: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail(path, "File not found")

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return _fail(path, "Failed to open file")

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_text)
	if parse_result != OK:
		return _fail(path, "Parse error (line %d): %s" % [json.get_error_line(), json.get_error_message()])

	return validate_data(path, json.data, format)

static func validate_data(path: String, raw_data: Variant, format: Dictionary = {}) -> Dictionary:
	var root_type: String = str(format.get("root_type", TYPE_DICTIONARY))
	if not _matches_type(raw_data, root_type):
		return _fail(path, "Invalid structure: root must be %s" % root_type)

	var data: Variant = raw_data
	var wrapper_key: String = str(format.get("wrapper_key", ""))
	var wrapper_type: String = str(format.get("wrapper_type", TYPE_DICTIONARY))
	if not wrapper_key.is_empty():
		if not (data is Dictionary):
			return _fail(path, "Invalid structure: root must be Dictionary when wrapper_key is used")
		if data.has(wrapper_key):
			var wrapped_data: Variant = data[wrapper_key]
			if not _matches_type(wrapped_data, wrapper_type):
				return _fail(path, "Invalid structure: '%s' must be %s" % [wrapper_key, wrapper_type])
			data = wrapped_data

	var entry_type: String = str(format.get("entry_type", ""))
	if not entry_type.is_empty():
		var entry_label: String = str(format.get("entry_label", "entry"))
		if data is Dictionary:
			for entry_key in data.keys():
				if not _matches_type(data[entry_key], entry_type):
					return _fail(path, "Invalid structure: %s '%s' must be %s" % [entry_label, str(entry_key), entry_type])
		elif data is Array:
			for i in range(data.size()):
				if not _matches_type(data[i], entry_type):
					return _fail(path, "Invalid structure: %s[%d] must be %s" % [entry_label, i, entry_type])
		else:
			return _fail(path, "Invalid structure: entry check requires Dictionary or Array data")

	var fields: Variant = format.get("fields", [])
	if fields is Array and not fields.is_empty():
		if not (data is Dictionary):
			return _fail(path, "Invalid structure: fields check requires Dictionary data")
		var fields_error: String = _validate_fields(data, fields)
		if not fields_error.is_empty():
			return _fail(path, fields_error)

	return _ok(path, data)

static func _validate_fields(data: Dictionary, fields: Array) -> String:
	for field_spec_variant in fields:
		if not (field_spec_variant is Dictionary):
			return "Invalid validator format: fields entry must be Dictionary"
		var field_spec: Dictionary = field_spec_variant

		var key: String = str(field_spec.get("key", ""))
		if key.is_empty():
			return "Invalid validator format: fields entry missing 'key'"

		var required: bool = bool(field_spec.get("required", false))
		if not data.has(key):
			if required:
				return "Invalid structure: missing required field '%s'" % key
			continue

		var expected_type: String = str(field_spec.get("type", ""))
		if expected_type.is_empty():
			return "Invalid validator format: field '%s' missing 'type'" % key

		var value: Variant = data[key]
		if not _matches_type(value, expected_type):
			return "Invalid structure: field '%s' must be %s" % [key, expected_type]

		var entry_type: String = str(field_spec.get("entry_type", ""))
		var entry_label: String = str(field_spec.get("entry_label", key))
		var entry_required_keys: Variant = field_spec.get("entry_required_keys", [])

		if entry_type.is_empty():
			continue

		if value is Array:
			for i in range(value.size()):
				var entry: Variant = value[i]
				if not _matches_type(entry, entry_type):
					return "Invalid structure: %s[%d] must be %s" % [entry_label, i, entry_type]
				if entry_required_keys is Array and entry is Dictionary:
					for required_key_variant in entry_required_keys:
						var required_key: String = str(required_key_variant)
						if required_key.is_empty():
							continue
						if not entry.has(required_key):
							return "Invalid structure: %s[%d] missing '%s'" % [entry_label, i, required_key]
		elif value is Dictionary:
			for entry_key in value.keys():
				var dict_entry: Variant = value[entry_key]
				if not _matches_type(dict_entry, entry_type):
					return "Invalid structure: %s '%s' must be %s" % [entry_label, str(entry_key), entry_type]
				if entry_required_keys is Array and dict_entry is Dictionary:
					for required_key_variant in entry_required_keys:
						var required_key: String = str(required_key_variant)
						if required_key.is_empty():
							continue
						if not dict_entry.has(required_key):
							return "Invalid structure: %s '%s' missing '%s'" % [entry_label, str(entry_key), required_key]
		else:
			return "Invalid structure: field '%s' entry check requires Array or Dictionary" % key

	return ""

static func _matches_type(value: Variant, expected_type: String) -> bool:
	match expected_type:
		TYPE_DICTIONARY:
			return value is Dictionary
		TYPE_ARRAY:
			return value is Array
		_:
			return false

static func _ok(path: String, data: Variant) -> Dictionary:
	return {
		"ok": true,
		"path": path,
		"data": data,
		"message": _format_message(path, "OK")
	}

static func _fail(path: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"path": path,
		"data": null,
		"message": _format_message(path, reason)
	}

static func _format_message(path: String, detail: String) -> String:
	return "[JSON] %s | %s" % [path, detail]
