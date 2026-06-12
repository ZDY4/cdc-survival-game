@tool
class_name MapDoor3D
extends "res://scripts/world/map_scene_object_3d.gd"

@export var display_name: String = "门"
@export var is_open: bool = false
@export var locked: bool = false
@export var blocks_sight_when_closed: bool = true
@export_multiline var props_json: String = "{}"


func get_object_kind() -> String:
	return "interactive"


func build_object_props() -> Dictionary:
	var props := _json_dictionary(props_json, "props_json")
	var door := _dictionary_or_empty(props.get("door", {})).duplicate(true)
	door["door_id"] = object_id
	door["display_name"] = display_name
	door["is_open"] = is_open
	door["locked"] = locked
	door["blocks_sight_when_closed"] = blocks_sight_when_closed
	props["door"] = door
	return props
