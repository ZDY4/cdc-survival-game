@tool
class_name MapStaticProp3D
extends "res://scripts/world/map_scene_object_3d.gd"

@export var visual_prototype_id: String = ""
@export_multiline var props_json: String = "{}"


func get_object_kind() -> String:
	return "prop"


func build_object_props() -> Dictionary:
	var props := _json_dictionary(props_json, "props_json")
	if not visual_prototype_id.strip_edges().is_empty():
		var visual := _dictionary_or_empty(props.get("visual", {})).duplicate(true)
		visual["prototype_id"] = visual_prototype_id
		props["visual"] = visual
	return props
