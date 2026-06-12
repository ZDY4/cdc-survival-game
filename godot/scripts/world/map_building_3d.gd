@tool
class_name MapBuilding3D
extends "res://scripts/world/map_scene_object_3d.gd"

@export var prefab_id: String = ""
@export var wall_set_id: String = ""
@export var floor_surface_set_id: String = ""
@export_multiline var props_json: String = "{}"


func get_object_kind() -> String:
	return "building"


func build_object_props() -> Dictionary:
	var props := _json_dictionary(props_json, "props_json")
	var building := _dictionary_or_empty(props.get("building", {})).duplicate(true)
	if not prefab_id.strip_edges().is_empty():
		building["prefab_id"] = prefab_id
	var tile_set := _dictionary_or_empty(building.get("tile_set", {})).duplicate(true)
	if not wall_set_id.strip_edges().is_empty():
		tile_set["wall_set_id"] = wall_set_id
	if not floor_surface_set_id.strip_edges().is_empty():
		tile_set["floor_surface_set_id"] = floor_surface_set_id
	if not tile_set.is_empty():
		building["tile_set"] = tile_set
	if not building.is_empty():
		props["building"] = building
	return props
