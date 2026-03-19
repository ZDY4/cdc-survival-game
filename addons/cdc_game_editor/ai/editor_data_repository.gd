@tool
extends RefCounted

const CATEGORY_SOURCES := {
	"items": {"kind": "directory", "path": "res://data/items", "id_field": "id"},
	"quests": {"kind": "directory", "path": "res://data/quests", "id_field": "quest_id"},
	"dialogues": {"kind": "directory", "path": "res://data/dialogues", "id_field": "dialog_id"},
	"characters": {"kind": "directory", "path": "res://data/characters", "id_field": "id"},
	"skills": {"kind": "directory", "path": "res://data/skills", "id_field": "id"},
	"skill_trees": {"kind": "directory", "path": "res://data/skill_trees", "id_field": "id"},
	"recipes": {"kind": "directory", "path": "res://data/recipes", "id_field": "id"},
	"effects": {"kind": "directory", "path": "res://data/json/effects", "id_field": "id"},
	"story_chapters": {"kind": "file", "path": "res://data/json/story_chapters.json"},
	"map_locations": {"kind": "file", "path": "res://data/json/map_locations.json"},
	"structures": {"kind": "file", "path": "res://data/json/structures.json"},
	"clues": {"kind": "file", "path": "res://data/json/clues.json"}
}

var _cache: Dictionary = {}


func clear_cache() -> void:
	_cache.clear()


func load_all() -> Dictionary:
	var result: Dictionary = {}
	for category in CATEGORY_SOURCES.keys():
		result[category] = load_category(category)
	return result


func load_category(category: String) -> Variant:
	var normalized_category := category.strip_edges().to_lower()
	if _cache.has(normalized_category):
		return _cache[normalized_category]

	if not CATEGORY_SOURCES.has(normalized_category):
		return {}

	var source: Dictionary = CATEGORY_SOURCES[normalized_category]
	var loaded: Variant = {}
	match str(source.get("kind", "")):
		"directory":
			loaded = _load_directory_json(
				str(source.get("path", "")),
				str(source.get("id_field", "id"))
			)
		"file":
			loaded = _load_json_file(str(source.get("path", "")))
		_:
			loaded = {}

	_cache[normalized_category] = loaded
	return loaded


func get_sorted_ids(category: String) -> Array[String]:
	var data := load_category(category)
	var result: Array[String] = []
	if data is Dictionary:
		for key in data.keys():
			var text := str(key).strip_edges()
			if not text.is_empty():
				result.append(text)
	result.sort()
	return result


func get_record(category: String, record_id: String) -> Dictionary:
	var data := load_category(category)
	if not (data is Dictionary):
		return {}
	return (data as Dictionary).get(record_id, {}).duplicate(true)


func _load_directory_json(directory_path: String, id_field: String) -> Dictionary:
	var result: Dictionary = {}
	var absolute_dir_path := ProjectSettings.globalize_path(directory_path)
	if not DirAccess.dir_exists_absolute(absolute_dir_path):
		return result

	var dir := DirAccess.open(directory_path)
	if dir == null:
		return result

	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	file_names.sort()
	for json_file in file_names:
		var path := "%s/%s" % [directory_path, json_file]
		var parsed := _load_json_file(path)
		if not (parsed is Dictionary):
			continue
		var record: Dictionary = (parsed as Dictionary).duplicate(true)
		var record_id := str(record.get(id_field, json_file.trim_suffix(".json"))).strip_edges()
		if record_id.is_empty():
			continue
		record[id_field] = record_id
		result[record_id] = record
	return result


func _load_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return {}
	var content := FileAccess.get_file_as_string(path)
	if content.is_empty():
		return {}
	var parsed := JSON.parse_string(content)
	if parsed == null:
		return {}
	return parsed
