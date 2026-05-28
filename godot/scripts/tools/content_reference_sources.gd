extends RefCounted

const ContentPaths = preload("res://scripts/data/content_paths.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const JsonLoader = preload("res://scripts/data/json_loader.gd")


func dialogue_rule_records() -> Dictionary:
	var output: Dictionary = {}
	var root := ContentPaths.domain_path("dialogue_rules")
	for path in JsonLoader.list_json_files(root, false):
		var parsed: Variant = JsonLoader.read_json_file(path)
		if typeof(parsed) != TYPE_DICTIONARY or parsed.has("__error"):
			continue
		var data: Dictionary = parsed
		var id_value: String = str(data.get("dialogue_key", path.get_file().get_basename()))
		output[id_value] = {
			"path": path,
			"data": data,
		}
	return output


func collect_legacy_json_refs(hits: Array[Dictionary], target_id: String, target_kind: String, field_names: Array[String], contextual_parent_names: Array[String]) -> void:
	for record in _legacy_json_records():
		_collect_recursive_refs(hits, target_id, target_kind, record, field_names, contextual_parent_names)


func reference_hit(source_kind: String, source_id: String, path: String, detail: String) -> Dictionary:
	return {
		"source_kind": source_kind,
		"source_id": source_id,
		"path": path,
		"detail": detail,
	}


func _legacy_json_records() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var root := ContentPaths.domain_path("json")
	for path in JsonLoader.list_json_files(root, true):
		var parsed: Variant = JsonLoader.read_json_file(path)
		if typeof(parsed) != TYPE_DICTIONARY or parsed.has("__error"):
			continue
		output.append({
			"id": path.get_file().get_basename(),
			"path": path,
			"data": parsed,
		})
	return output


func _collect_recursive_refs(hits: Array[Dictionary], target_id: String, target_kind: String, record: Dictionary, field_names: Array[String], contextual_parent_names: Array[String]) -> void:
	_walk_recursive_refs(hits, target_id, target_kind, record, _dictionary_or_empty(record.get("data", {})), "$", "", field_names, contextual_parent_names)


func _walk_recursive_refs(hits: Array[Dictionary], target_id: String, target_kind: String, record: Dictionary, value: Variant, path: String, parent_key: String, field_names: Array[String], contextual_parent_names: Array[String]) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		for key in dict.keys():
			var key_string := str(key)
			var next_path := "%s.%s" % [path, key_string]
			var next_value: Variant = dict[key]
			if field_names.has(key_string) and _normalize_id(next_value) == target_id:
				hits.append(reference_hit("json", record.get("id", ""), record.get("path", ""), "%s -> %s" % [next_path, target_kind]))
			elif key_string == "id" and contextual_parent_names.has(parent_key) and _normalize_id(next_value) == target_id:
				hits.append(reference_hit("json", record.get("id", ""), record.get("path", ""), "%s -> %s" % [next_path, target_kind]))
			_walk_recursive_refs(hits, target_id, target_kind, record, next_value, next_path, key_string, field_names, contextual_parent_names)
	elif typeof(value) == TYPE_ARRAY:
		var values: Array = value
		for i in range(values.size()):
			var next_path := "%s[%d]" % [path, i]
			var next_value: Variant = values[i]
			if contextual_parent_names.has(parent_key) and _normalize_id(next_value) == target_id:
				hits.append(reference_hit("json", record.get("id", ""), record.get("path", ""), "%s -> %s" % [next_path, target_kind]))
			_walk_recursive_refs(hits, target_id, target_kind, record, next_value, next_path, parent_key, field_names, contextual_parent_names)


func _normalize_id(id_value: Variant) -> String:
	return ContentRegistry.normalize_content_id(id_value)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
