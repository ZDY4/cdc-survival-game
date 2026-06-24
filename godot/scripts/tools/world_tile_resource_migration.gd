extends SceneTree

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")
const ContentPaths = preload("res://scripts/data/content_paths.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const WorldSurfaceTileSetScript = preload("res://scripts/world/tiles/world_surface_tile_set.gd")
const WorldTilePaletteScript = preload("res://scripts/world/tiles/world_tile_palette.gd")
const WorldTilePrototypeScript = preload("res://scripts/world/tiles/world_tile_prototype.gd")
const WorldTileResourceIndex = preload("res://scripts/world/tiles/world_tile_resource_index.gd")
const WorldWallTileSetScript = preload("res://scripts/world/tiles/world_wall_tile_set.gd")

const RESOURCE_ROOT := "res://resources/world_tiles"
const PROTOTYPE_ROOT := RESOURCE_ROOT + "/prototypes"
const SET_ROOT := RESOURCE_ROOT + "/sets"
const PALETTE_ROOT := RESOURCE_ROOT + "/palettes"
const PALETTE_PATH := PALETTE_ROOT + "/default_world_tile_palette.tres"

var dry_run := false
var report: Dictionary = {
	"dry_run": false,
	"created": [],
	"updated": [],
	"skipped": [],
	"failures": [],
	"counts": {},
	"roundtrip": {},
}
var prototype_resources: Dictionary = {}
var prototype_paths: Dictionary = {}
var wall_set_resources: Array[WorldWallTileSetScript] = []
var surface_set_resources: Array[WorldSurfaceTileSetScript] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	dry_run = args.has("--dry-run")
	report["dry_run"] = dry_run

	var registry := ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		_add_failure("registry", "ContentRegistry failed to load: %s" % load_result.errors)
		_finish(1)
		return

	_ensure_directories()
	_generate_prototypes(registry)
	_generate_sets(registry)
	_generate_palette()
	_validate_roundtrip(registry)
	_write_report()

	var exit_code := 0
	if not _array_or_empty(report.get("failures", [])).is_empty():
		exit_code = 1
	print("world_tile_resource_migration finished:")
	print(report)
	quit(exit_code)


func _generate_prototypes(registry: ContentRegistry) -> void:
	var expected_count := 0
	for record_id in _sorted_keys(registry.get_library("world_tiles")):
		var record: Dictionary = registry.get_library("world_tiles")[record_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		for prototype_source in _array_or_empty(data.get("prototypes", [])):
			expected_count += 1
			var prototype_data: Dictionary = _dictionary_or_empty(prototype_source)
			var prototype_id := str(prototype_data.get("id", "")).strip_edges()
			var source: Dictionary = _dictionary_or_empty(prototype_data.get("source", {}))
			var source_path := str(source.get("path", "")).strip_edges()
			if prototype_id.is_empty():
				_add_failure("prototype", "prototype in %s has empty id" % record_id)
				continue
			if source_path.is_empty():
				_add_failure(prototype_id, "prototype has empty source.path")
				continue
			var resolved := AssetPathResolver.resolve_model_asset(source_path)
			if not bool(resolved.get("ok", false)) or not bool(resolved.get("exists", false)):
				_add_failure(prototype_id, "failed to resolve scene %s: %s" % [source_path, resolved])
				continue
			var scene: PackedScene = load(str(resolved.get("resource_path", "")))
			if scene == null:
				_add_failure(prototype_id, "failed to load PackedScene %s" % str(resolved.get("resource_path", "")))
				continue
			var prototype := WorldTilePrototypeScript.new()
			prototype.id = StringName(prototype_id)
			prototype.display_name = prototype_id
			prototype.category = _category_for_prototype(prototype_id)
			prototype.scene = scene
			prototype.footprint = Vector2i.ONE
			prototype.tags = PackedStringArray()
			var path := "%s/%s.tres" % [PROTOTYPE_ROOT, prototype_id]
			if _save_resource(prototype, path):
				prototype_resources[prototype_id] = _loaded_or_original(path, prototype)
			prototype_paths[prototype_id] = path
	report["counts"]["json_prototypes"] = expected_count
	report["counts"]["resource_prototypes"] = prototype_resources.size()


func _generate_sets(registry: ContentRegistry) -> void:
	var expected_wall_sets := 0
	var expected_surface_sets := 0
	for record_id in _sorted_keys(registry.get_library("world_tiles")):
		var record: Dictionary = registry.get_library("world_tiles")[record_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		for wall_source in _array_or_empty(data.get("wall_sets", [])):
			expected_wall_sets += 1
			_generate_wall_set(_dictionary_or_empty(wall_source))
		for surface_source in _array_or_empty(data.get("surface_sets", [])):
			expected_surface_sets += 1
			_generate_surface_set(_dictionary_or_empty(surface_source))
	report["counts"]["json_wall_sets"] = expected_wall_sets
	report["counts"]["resource_wall_sets"] = wall_set_resources.size()
	report["counts"]["json_surface_sets"] = expected_surface_sets
	report["counts"]["resource_surface_sets"] = surface_set_resources.size()


func _generate_wall_set(source: Dictionary) -> void:
	var set_id := str(source.get("id", "")).strip_edges()
	if set_id.is_empty():
		_add_failure("wall_set", "wall set has empty id")
		return
	var set := WorldWallTileSetScript.new()
	set.id = StringName(set_id)
	set.display_name = set_id
	set.corner = _prototype_or_failure(source, "corner_prototype_id", set_id)
	set.straight = _prototype_or_failure(source, "straight_prototype_id", set_id)
	set.end = _prototype_or_failure(source, "end_prototype_id", set_id)
	set.t_junction = _prototype_or_failure(source, "t_junction_prototype_id", set_id)
	set.cross = _prototype_or_failure(source, "cross_prototype_id", set_id)
	set.isolated = _prototype_or_failure(source, "isolated_prototype_id", set_id)
	var path := "%s/%s.tres" % [SET_ROOT, _resource_file_stem(set_id)]
	if _save_resource(set, path):
		wall_set_resources.append(_loaded_or_original(path, set) as WorldWallTileSetScript)


func _generate_surface_set(source: Dictionary) -> void:
	var set_id := str(source.get("id", "")).strip_edges()
	if set_id.is_empty():
		_add_failure("surface_set", "surface set has empty id")
		return
	var set := WorldSurfaceTileSetScript.new()
	set.id = StringName(set_id)
	set.display_name = set_id
	set.flat_top = _prototype_or_failure(source, "flat_top_prototype_id", set_id, true)
	var ramp_top_ids: Dictionary = _dictionary_or_empty(source.get("ramp_top_prototype_ids", {}))
	set.ramp_north = _prototype_by_id_or_failure(str(ramp_top_ids.get("north", "")).strip_edges(), set_id, "ramp_top_prototype_ids.north", true)
	set.ramp_south = _prototype_by_id_or_failure(str(ramp_top_ids.get("south", "")).strip_edges(), set_id, "ramp_top_prototype_ids.south", true)
	set.ramp_east = _prototype_by_id_or_failure(str(ramp_top_ids.get("east", "")).strip_edges(), set_id, "ramp_top_prototype_ids.east", true)
	set.ramp_west = _prototype_by_id_or_failure(str(ramp_top_ids.get("west", "")).strip_edges(), set_id, "ramp_top_prototype_ids.west", true)
	set.cliff_side = _prototype_or_failure(source, "cliff_side_prototype_id", set_id, true)
	set.cliff_inner_corner = _prototype_or_failure(source, "cliff_inner_corner_prototype_id", set_id, true)
	set.cliff_outer_corner = _prototype_or_failure(source, "cliff_outer_corner_prototype_id", set_id, true)
	var path := "%s/%s.tres" % [SET_ROOT, _resource_file_stem(set_id)]
	if _save_resource(set, path):
		surface_set_resources.append(_loaded_or_original(path, set) as WorldSurfaceTileSetScript)


func _generate_palette() -> void:
	var palette := WorldTilePaletteScript.new()
	palette.id = &"default_world_tile_palette"
	palette.display_name = "Default World Tile Palette"
	for prototype_id in _sorted_keys(prototype_resources):
		palette.prototypes.append(prototype_resources[prototype_id])
	palette.wall_sets = wall_set_resources
	palette.surface_sets = surface_set_resources
	_save_resource(palette, PALETTE_PATH)


func _validate_roundtrip(registry: ContentRegistry) -> void:
	if dry_run:
		report["roundtrip"] = {"skipped": true, "reason": "dry_run"}
		return
	var index := WorldTileResourceIndex.new()
	if not index.load_palette(PALETTE_PATH):
		report["roundtrip"] = {"ok": false, "issues": index.load_errors}
		return
	var issues: Array[String] = []
	_compare_sorted_lists(_json_prototype_ids(registry), index.sorted_prototype_ids(), "prototype ids", issues)
	_compare_dictionaries(_json_wall_sets(registry), index.wall_set_prototypes(), "wall sets", issues)
	_compare_dictionaries(_json_surface_sets(registry), index.surface_set_prototypes(), "surface sets", issues)
	for issue in index.validate():
		issues.append(str(issue))
	report["roundtrip"] = {
		"ok": issues.is_empty(),
		"issues": issues,
	}
	if not issues.is_empty():
		for issue in issues:
			_add_failure("roundtrip", issue)


func _json_prototype_ids(registry: ContentRegistry) -> Array[String]:
	var ids: Array[String] = []
	for record in registry.get_library("world_tiles").values():
		var data: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record).get("data", {}))
		for prototype in _array_or_empty(data.get("prototypes", [])):
			var prototype_id := str(_dictionary_or_empty(prototype).get("id", "")).strip_edges()
			if not prototype_id.is_empty():
				ids.append(prototype_id)
	ids.sort()
	return ids


func _json_wall_sets(registry: ContentRegistry) -> Dictionary:
	var output := {}
	for record in registry.get_library("world_tiles").values():
		var data: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record).get("data", {}))
		for wall_source in _array_or_empty(data.get("wall_sets", [])):
			var wall_set: Dictionary = _dictionary_or_empty(wall_source)
			var set_id := str(wall_set.get("id", "")).strip_edges()
			if set_id.is_empty():
				continue
			var prototypes := {}
			for key in ["corner_prototype_id", "straight_prototype_id", "end_prototype_id", "t_junction_prototype_id", "cross_prototype_id", "isolated_prototype_id"]:
				var prototype_id := str(wall_set.get(key, "")).strip_edges()
				if not prototype_id.is_empty():
					prototypes[key] = prototype_id
			output[set_id] = prototypes
	return output


func _json_surface_sets(registry: ContentRegistry) -> Dictionary:
	var output := {}
	for record in registry.get_library("world_tiles").values():
		var data: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record).get("data", {}))
		for surface_source in _array_or_empty(data.get("surface_sets", [])):
			var surface_set: Dictionary = _dictionary_or_empty(surface_source)
			var set_id := str(surface_set.get("id", "")).strip_edges()
			if set_id.is_empty():
				continue
			var prototypes := {}
			for key in ["flat_top_prototype_id", "cliff_side_prototype_id", "cliff_inner_corner_prototype_id", "cliff_outer_corner_prototype_id"]:
				var prototype_id := str(surface_set.get(key, "")).strip_edges()
				if not prototype_id.is_empty():
					prototypes[key] = prototype_id
			var ramp_top_ids: Dictionary = _dictionary_or_empty(surface_set.get("ramp_top_prototype_ids", {}))
			for direction in _sorted_keys(ramp_top_ids):
				var prototype_id := str(ramp_top_ids.get(direction, "")).strip_edges()
				if not prototype_id.is_empty():
					prototypes["ramp_top_prototype_ids.%s" % direction] = prototype_id
			output[set_id] = prototypes
	return output


func _prototype_or_failure(source: Dictionary, key: String, set_id: String, allow_empty: bool = false) -> WorldTilePrototypeScript:
	return _prototype_by_id_or_failure(str(source.get(key, "")).strip_edges(), set_id, key, allow_empty)


func _prototype_by_id_or_failure(prototype_id: String, set_id: String, key: String, allow_empty: bool = false) -> WorldTilePrototypeScript:
	if prototype_id.is_empty():
		if not allow_empty:
			_add_failure(set_id, "missing %s" % key)
		return null
	if not prototype_resources.has(prototype_id):
		_add_failure(set_id, "unknown prototype %s in %s" % [prototype_id, key])
		return null
	return prototype_resources[prototype_id] as WorldTilePrototypeScript


func _category_for_prototype(prototype_id: String) -> String:
	if prototype_id.begins_with("building_wall/"):
		return "building"
	if prototype_id.begins_with("surface_placeholder_basic/"):
		return "surface"
	if prototype_id.begins_with("props/"):
		return "prop"
	return "prop"


func _save_resource(resource: Resource, resource_path: String) -> bool:
	var absolute := _absolute_path_from_resource(resource_path)
	var existed := FileAccess.file_exists(absolute)
	if dry_run:
		report["skipped"].append({"path": resource_path, "reason": "dry_run"})
		return true
	var dir := absolute.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var error := ResourceSaver.save(resource, resource_path)
	if error != OK:
		_add_failure(resource_path, "ResourceSaver.save failed with code %d" % error)
		return false
	if existed:
		report["updated"].append(resource_path)
	else:
		report["created"].append(resource_path)
	return true


func _loaded_or_original(resource_path: String, fallback: Resource) -> Resource:
	if dry_run:
		return fallback
	var loaded := ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if loaded is Resource:
		return loaded
	_add_failure(resource_path, "failed to reload saved resource for external reference wiring")
	return fallback


func _ensure_directories() -> void:
	if dry_run:
		return
	for path in [PROTOTYPE_ROOT, SET_ROOT, PALETTE_ROOT]:
		DirAccess.make_dir_recursive_absolute(_absolute_path_from_resource(path))


func _write_report() -> void:
	var output_root := ContentPaths.repo_root().path_join(".local/agent-reports/world_tile_resource_migration")
	DirAccess.make_dir_recursive_absolute(output_root)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace("T", "-")
	var path := output_root.path_join("%s.json" % stamp)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("failed to write world tile migration report: %s" % path)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	report["report_path"] = path


func _finish(exit_code: int) -> void:
	_write_report()
	print(report)
	quit(exit_code)


func _add_failure(path: String, message: String) -> void:
	report["failures"].append({"path": path, "message": message})


func _compare_sorted_lists(expected: Array[String], actual: Array[String], label: String, issues: Array[String]) -> void:
	if expected != actual:
		issues.append("%s mismatch expected=%s actual=%s" % [label, expected, actual])


func _compare_dictionaries(expected: Dictionary, actual: Dictionary, label: String, issues: Array[String]) -> void:
	var expected_text := JSON.stringify(_sorted_dictionary(expected))
	var actual_text := JSON.stringify(_sorted_dictionary(actual))
	if expected_text != actual_text:
		issues.append("%s mismatch expected=%s actual=%s" % [label, expected_text, actual_text])


func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var output := {}
	for key in _sorted_keys(source):
		var value: Variant = source[key]
		if typeof(value) == TYPE_DICTIONARY:
			output[key] = _sorted_dictionary(value)
		else:
			output[key] = value
	return output


func _resource_file_stem(id_value: String) -> String:
	return id_value.replace("/", "__")


func _absolute_path_from_resource(resource_path: String) -> String:
	return ProjectSettings.globalize_path(resource_path).simplify_path()


func _sorted_keys(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in source.keys():
		keys.append(str(key))
	keys.sort()
	return keys


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
