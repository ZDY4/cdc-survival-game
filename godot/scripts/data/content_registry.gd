extends RefCounted

const ContentPaths = preload("res://scripts/data/content_paths.gd")
const JsonLoader = preload("res://scripts/data/json_loader.gd")
const ValidationResult = preload("res://scripts/data/validation_result.gd")

const DOMAIN_SPECS := [
	{"domain": "items", "dir": "items", "id_field": "id", "required": ["id", "name", "fragments"], "recursive": false},
	{"domain": "characters", "dir": "characters", "id_field": "id", "required": ["id", "archetype", "identity", "faction", "attributes"], "recursive": false},
	{"domain": "maps", "dir": "maps", "id_field": "id", "required": ["id", "size", "levels", "entry_points", "objects"], "recursive": false},
	{"domain": "recipes", "dir": "recipes", "id_field": "id", "required": ["id", "name", "output", "materials"], "recursive": false},
	{"domain": "quests", "dir": "quests", "id_field": "quest_id", "required": ["quest_id", "title", "flow"], "recursive": false},
	{"domain": "dialogues", "dir": "dialogues", "id_field": "dialog_id", "required": ["dialog_id", "nodes"], "recursive": false},
	{"domain": "dialogue_rules", "dir": "dialogue_rules", "id_field": "dialogue_key", "required": ["dialogue_key", "default_dialogue_id"], "recursive": false},
	{"domain": "skills", "dir": "skills", "id_field": "id", "required": ["id", "name"], "recursive": false},
	{"domain": "skill_trees", "dir": "skill_trees", "id_field": "id", "required": ["id"], "recursive": false},
	{"domain": "world_tiles", "dir": "world_tiles", "id_field": "", "required": ["prototypes"], "recursive": false},
	{"domain": "settlements", "dir": "settlements", "id_field": "id", "required": ["id"], "recursive": false},
	{"domain": "shops", "dir": "shops", "id_field": "id", "required": ["id"], "recursive": false},
	{"domain": "overworld", "dir": "overworld", "id_field": "id", "required": ["id"], "recursive": false},
	{"domain": "appearance", "dir": "appearance", "id_field": "id", "required": ["id"], "recursive": true},
	{"domain": "ai", "dir": "ai", "id_field": "", "required": [], "recursive": true},
	{"domain": "json", "dir": "json", "id_field": "id", "required": [], "recursive": true},
]

var libraries: Dictionary = {}
var files_by_domain: Dictionary = {}
var bootstrap_config: Dictionary = {}
var data_root: String = ""


func load_all() -> ValidationResult:
	var result := ValidationResult.new()
	libraries.clear()
	files_by_domain.clear()
	bootstrap_config.clear()
	data_root = ContentPaths.data_root()

	for spec in DOMAIN_SPECS:
		_load_domain(spec, result)

	_load_bootstrap(result)
	_validate_references(result)
	return result


func get_library(domain: String) -> Dictionary:
	return libraries.get(domain, {})


func has_id(domain: String, id_value: Variant) -> bool:
	return get_library(domain).has(normalize_content_id(id_value))


static func normalize_content_id(id_value: Variant) -> String:
	match typeof(id_value):
		TYPE_FLOAT:
			var float_value: float = id_value
			if is_equal_approx(float_value, roundf(float_value)):
				return str(int(float_value))
			return str(float_value)
		TYPE_INT:
			return str(id_value)
		_:
			return str(id_value)


func summary() -> Dictionary:
	var output: Dictionary = {
		"data_root": data_root,
		"domains": {},
		"bootstrap_loaded": not bootstrap_config.is_empty(),
	}
	for spec in DOMAIN_SPECS:
		var domain: String = spec["domain"]
		output["domains"][domain] = {
			"files": files_by_domain.get(domain, []).size(),
			"records": get_library(domain).size(),
		}
	return output


func _load_domain(spec: Dictionary, result: ValidationResult) -> void:
	var domain: String = spec["domain"]
	var root: String = ContentPaths.domain_path(str(spec["dir"]))
	var files: Array[String] = JsonLoader.list_json_files(root, bool(spec.get("recursive", false)))
	files_by_domain[domain] = files
	libraries[domain] = {}

	if files.is_empty():
		result.add_warning(root, domain, "path", "no JSON files found")
		return

	for path in files:
		var parsed: Variant = JsonLoader.read_json_file(path)
		if typeof(parsed) != TYPE_DICTIONARY:
			result.add_error(path, "", "$", "top-level JSON value must be an object")
			continue
		if parsed.has("__error"):
			result.add_error(path, "", "$", str(parsed.get("message", "failed to read JSON")))
			continue

		var parsed_data: Dictionary = parsed
		var content_id := _read_content_id(parsed_data, spec, path)
		_validate_required_fields(parsed, spec.get("required", []), path, content_id, result)
		if get_library(domain).has(content_id):
			result.add_error(path, content_id, str(spec.get("id_field", "id")), "duplicate id in domain %s" % domain)
			continue

		get_library(domain)[content_id] = {
			"path": path,
			"data": parsed_data,
		}


func _load_bootstrap(result: ValidationResult) -> void:
	var path := ContentPaths.domain_path("bootstrap").path_join("new_game_default.json")
	var parsed: Variant = JsonLoader.read_json_file(path)
	if typeof(parsed) != TYPE_DICTIONARY or parsed.has("__error"):
		result.add_error(path, "new_game_default", "$", "failed to load new game bootstrap")
		return
	bootstrap_config = parsed


func _read_content_id(data: Dictionary, spec: Dictionary, path: String) -> String:
	var id_field: String = str(spec.get("id_field", "id"))
	if not id_field.is_empty() and data.has(id_field):
		return normalize_content_id(data[id_field])
	return path.get_file().get_basename()


func _validate_required_fields(data: Dictionary, required: Array, path: String, content_id: String, result: ValidationResult) -> void:
	for field in required:
		if not data.has(field):
			result.add_error(path, content_id, str(field), "required field is missing")


func _validate_references(result: ValidationResult) -> void:
	_validate_recipe_item_refs(result)
	_validate_bootstrap_refs(result)
	_validate_appearance_asset_refs(result)


func _validate_recipe_item_refs(result: ValidationResult) -> void:
	for recipe_id in get_library("recipes").keys():
		var record: Dictionary = get_library("recipes")[recipe_id]
		var path: String = record["path"]
		var data: Dictionary = record["data"]
		var output: Dictionary = data.get("output", {})
		_validate_item_ref(output.get("item_id", null), path, recipe_id, "output.item_id", result)
		for i in range(data.get("materials", []).size()):
			var material: Dictionary = data["materials"][i]
			_validate_item_ref(material.get("item_id", null), path, recipe_id, "materials[%d].item_id" % i, result)


func _validate_bootstrap_refs(result: ValidationResult) -> void:
	if bootstrap_config.is_empty():
		return
	var path := ContentPaths.domain_path("bootstrap").path_join("new_game_default.json")
	var startup_map_id: String = str(bootstrap_config.get("startupMapId", ""))
	if not has_id("maps", startup_map_id):
		result.add_error(path, "new_game_default", "startupMapId", "unknown map id %s" % startup_map_id)

	for section in ["items", "ammo"]:
		var entries: Array = bootstrap_config.get(section, [])
		for i in range(entries.size()):
			_validate_item_ref(entries[i].get("itemId", null), path, "new_game_default", "%s[%d].itemId" % [section, i], result)

	var equipment: Array = bootstrap_config.get("equipment", [])
	for i in range(equipment.size()):
		_validate_item_ref(equipment[i].get("itemId", null), path, "new_game_default", "equipment[%d].itemId" % i, result)

	var spawn_entries: Array = bootstrap_config.get("spawnEntries", [])
	for i in range(spawn_entries.size()):
		var character_id: String = str(spawn_entries[i].get("definitionId", ""))
		if not has_id("characters", character_id):
			result.add_error(path, "new_game_default", "spawnEntries[%d].definitionId" % i, "unknown character id %s" % character_id)


func _validate_appearance_asset_refs(result: ValidationResult) -> void:
	var assets_root := ContentPaths.assets_root()
	for appearance_id in get_library("appearance").keys():
		var record: Dictionary = get_library("appearance")[appearance_id]
		var path: String = record["path"]
		var data: Dictionary = record["data"]
		var base_model_asset := str(data.get("base_model_asset", "")).strip_edges()
		if base_model_asset.is_empty():
			result.add_error(path, appearance_id, "base_model_asset", "missing base model asset path")
			continue
		if not base_model_asset.ends_with(".gltf"):
			result.add_error(path, appearance_id, "base_model_asset", "base model asset must reference a .gltf file")
			continue
		var full_path := assets_root.path_join(base_model_asset).simplify_path()
		if not FileAccess.file_exists(full_path):
			result.add_error(path, appearance_id, "base_model_asset", "asset file does not exist: %s" % full_path)


func _validate_item_ref(item_id: Variant, path: String, content_id: String, field: String, result: ValidationResult) -> void:
	if item_id == null:
		result.add_error(path, content_id, field, "missing item id")
		return
	if not has_id("items", item_id):
		result.add_error(path, content_id, field, "unknown item id %s" % item_id)
