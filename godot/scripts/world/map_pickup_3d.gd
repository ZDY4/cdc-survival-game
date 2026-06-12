@tool
class_name MapPickup3D
extends "res://scripts/world/map_scene_object_3d.gd"

@export var item_id: String = ""
@export var min_count: int = 1
@export var max_count: int = 1
@export_multiline var props_json: String = "{}"


func get_object_kind() -> String:
	return "pickup"


func should_have_pick_area() -> bool:
	return true


func build_object_props() -> Dictionary:
	var props := _json_dictionary(props_json, "props_json")
	var pickup := _dictionary_or_empty(props.get("pickup", {})).duplicate(true)
	if not item_id.strip_edges().is_empty():
		pickup["item_id"] = item_id
	pickup["min_count"] = max(1, min_count)
	pickup["max_count"] = max(max(1, min_count), max_count)
	props["pickup"] = pickup
	return props
