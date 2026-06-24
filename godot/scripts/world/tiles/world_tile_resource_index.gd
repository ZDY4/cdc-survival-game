@tool
class_name WorldTileResourceIndex
extends RefCounted

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")
const WorldSurfaceTileSetScript = preload("res://scripts/world/tiles/world_surface_tile_set.gd")
const WorldTilePaletteScript = preload("res://scripts/world/tiles/world_tile_palette.gd")
const WorldTilePrototypeScript = preload("res://scripts/world/tiles/world_tile_prototype.gd")
const WorldWallTileSetScript = preload("res://scripts/world/tiles/world_wall_tile_set.gd")

const DEFAULT_PALETTE_PATH := "res://resources/world_tiles/palettes/default_world_tile_palette.tres"

var palette_path: String = DEFAULT_PALETTE_PATH
var palette: WorldTilePaletteScript
var prototypes: Dictionary = {}
var wall_sets: Dictionary = {}
var surface_sets: Dictionary = {}
var load_errors: Array[String] = []


func load_palette(path: String = DEFAULT_PALETTE_PATH) -> bool:
	palette_path = path
	palette = null
	prototypes.clear()
	wall_sets.clear()
	surface_sets.clear()
	load_errors.clear()
	if not ResourceLoader.exists(path):
		load_errors.append("world tile palette resource does not exist: %s" % path)
		return false
	var loaded := ResourceLoader.load(path)
	palette = loaded as WorldTilePaletteScript
	if palette == null:
		load_errors.append("resource is not a WorldTilePalette: %s" % path)
		return false
	_index_palette()
	return load_errors.is_empty()


func is_loaded() -> bool:
	return palette != null and load_errors.is_empty()


func prototype_source_paths() -> Dictionary:
	var output := {}
	for prototype_id in sorted_prototype_ids():
		var prototype := get_prototype(prototype_id)
		if prototype == null:
			continue
		output[prototype_id] = prototype.scene_path()
	return output


func wall_set_prototypes() -> Dictionary:
	var output := {}
	for wall_set_id in sorted_wall_set_ids():
		var set := get_wall_set(wall_set_id)
		if set == null:
			continue
		var values := {}
		_add_prototype_id(values, "corner_prototype_id", set.corner)
		_add_prototype_id(values, "straight_prototype_id", set.straight)
		_add_prototype_id(values, "end_prototype_id", set.end)
		_add_prototype_id(values, "t_junction_prototype_id", set.t_junction)
		_add_prototype_id(values, "cross_prototype_id", set.cross)
		_add_prototype_id(values, "isolated_prototype_id", set.isolated)
		output[wall_set_id] = values
	return output


func surface_set_prototypes() -> Dictionary:
	var output := {}
	for surface_set_id in sorted_surface_set_ids():
		var set := get_surface_set(surface_set_id)
		if set == null:
			continue
		var values := {}
		_add_prototype_id(values, "flat_top_prototype_id", set.flat_top)
		_add_prototype_id(values, "ramp_top_prototype_ids.north", set.ramp_north)
		_add_prototype_id(values, "ramp_top_prototype_ids.south", set.ramp_south)
		_add_prototype_id(values, "ramp_top_prototype_ids.east", set.ramp_east)
		_add_prototype_id(values, "ramp_top_prototype_ids.west", set.ramp_west)
		_add_prototype_id(values, "cliff_side_prototype_id", set.cliff_side)
		_add_prototype_id(values, "cliff_inner_corner_prototype_id", set.cliff_inner_corner)
		_add_prototype_id(values, "cliff_outer_corner_prototype_id", set.cliff_outer_corner)
		output[surface_set_id] = values
	return output


func sorted_prototype_ids() -> Array[String]:
	return _sorted_string_keys(prototypes)


func sorted_wall_set_ids() -> Array[String]:
	return _sorted_string_keys(wall_sets)


func sorted_surface_set_ids() -> Array[String]:
	return _sorted_string_keys(surface_sets)


func get_prototype(id_value: String) -> WorldTilePrototypeScript:
	return prototypes.get(id_value) as WorldTilePrototypeScript


func get_wall_set(id_value: String) -> WorldWallTileSetScript:
	return wall_sets.get(id_value) as WorldWallTileSetScript


func get_surface_set(id_value: String) -> WorldSurfaceTileSetScript:
	return surface_sets.get(id_value) as WorldSurfaceTileSetScript


func validate() -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	for error in load_errors:
		issues.append(_issue("error", palette_path, "load_failed", error))
	if palette == null:
		return issues
	_validate_palette_arrays(issues)
	for prototype_id in sorted_prototype_ids():
		_validate_prototype(prototype_id, get_prototype(prototype_id), issues)
	for wall_set_id in sorted_wall_set_ids():
		_validate_wall_set(wall_set_id, get_wall_set(wall_set_id), issues)
	for surface_set_id in sorted_surface_set_ids():
		_validate_surface_set(surface_set_id, get_surface_set(surface_set_id), issues)
	return issues


func _index_palette() -> void:
	for value in palette.prototypes:
		var prototype := value as WorldTilePrototypeScript
		if prototype == null:
			load_errors.append("palette contains a non-WorldTilePrototype entry")
			continue
		var prototype_id := prototype.source_id()
		if prototype_id.is_empty():
			load_errors.append("palette contains prototype with empty id")
			continue
		if prototypes.has(prototype_id):
			load_errors.append("duplicate world tile prototype id: %s" % prototype_id)
		prototypes[prototype_id] = prototype
	for value in palette.wall_sets:
		var set := value as WorldWallTileSetScript
		if set == null:
			load_errors.append("palette contains a non-WorldWallTileSet entry")
			continue
		var set_id := set.source_id()
		if set_id.is_empty():
			load_errors.append("palette contains wall set with empty id")
			continue
		if wall_sets.has(set_id):
			load_errors.append("duplicate world wall set id: %s" % set_id)
		wall_sets[set_id] = set
	for value in palette.surface_sets:
		var set := value as WorldSurfaceTileSetScript
		if set == null:
			load_errors.append("palette contains a non-WorldSurfaceTileSet entry")
			continue
		var set_id := set.source_id()
		if set_id.is_empty():
			load_errors.append("palette contains surface set with empty id")
			continue
		if surface_sets.has(set_id):
			load_errors.append("duplicate world surface set id: %s" % set_id)
		surface_sets[set_id] = set


func _validate_palette_arrays(issues: Array[Dictionary]) -> void:
	if prototypes.is_empty():
		issues.append(_issue("error", palette_path, "missing_prototypes", "WorldTilePalette must contain prototypes"))


func _validate_prototype(prototype_id: String, prototype: WorldTilePrototypeScript, issues: Array[Dictionary]) -> void:
	if prototype == null:
		issues.append(_issue("error", palette_path, "invalid_prototype", "prototype %s is not loadable" % prototype_id))
		return
	if not ["building", "surface", "prop", "marker"].has(prototype.category):
		issues.append(_issue("error", prototype.resource_path, "invalid_category", "prototype %s has invalid category %s" % [prototype_id, prototype.category]))
	if prototype.scene == null:
		issues.append(_issue("error", prototype.resource_path, "missing_scene", "prototype %s has no scene" % prototype_id))
		return
	var scene_path := prototype.scene_path()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		issues.append(_issue("error", prototype.resource_path, "missing_scene_file", "prototype %s scene does not exist: %s" % [prototype_id, scene_path]))


func _validate_wall_set(wall_set_id: String, set: WorldWallTileSetScript, issues: Array[Dictionary]) -> void:
	if set == null:
		issues.append(_issue("error", palette_path, "invalid_wall_set", "wall set %s is not loadable" % wall_set_id))
		return
	for slot in ["corner", "straight", "end", "t_junction", "cross", "isolated"]:
		var prototype := set.get(slot) as WorldTilePrototypeScript
		if prototype == null:
			issues.append(_issue("error", set.resource_path, "missing_wall_set_slot", "wall set %s has empty %s slot" % [wall_set_id, slot]))
			continue
		if not prototypes.has(prototype.source_id()):
			issues.append(_issue("error", set.resource_path, "unknown_wall_set_prototype", "wall set %s references prototype outside palette: %s" % [wall_set_id, prototype.source_id()]))


func _validate_surface_set(surface_set_id: String, set: WorldSurfaceTileSetScript, issues: Array[Dictionary]) -> void:
	if set == null:
		issues.append(_issue("error", palette_path, "invalid_surface_set", "surface set %s is not loadable" % surface_set_id))
		return
	if set.flat_top == null:
		issues.append(_issue("error", set.resource_path, "missing_surface_set_slot", "surface set %s has empty flat_top slot" % surface_set_id))
	for slot in ["flat_top", "ramp_north", "ramp_south", "ramp_east", "ramp_west", "cliff_side", "cliff_inner_corner", "cliff_outer_corner"]:
		var prototype := set.get(slot) as WorldTilePrototypeScript
		if prototype == null:
			continue
		if not prototypes.has(prototype.source_id()):
			issues.append(_issue("error", set.resource_path, "unknown_surface_set_prototype", "surface set %s references prototype outside palette: %s" % [surface_set_id, prototype.source_id()]))


func _add_prototype_id(output: Dictionary, key: String, prototype: WorldTilePrototypeScript) -> void:
	if prototype == null:
		return
	var prototype_id := prototype.source_id()
	if not prototype_id.is_empty():
		output[key] = prototype_id


func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in source.keys():
		keys.append(str(key))
	keys.sort()
	return keys


func _issue(severity: String, path: String, code: String, message: String) -> Dictionary:
	return {
		"severity": severity,
		"path": path,
		"code": code,
		"message": message,
	}
