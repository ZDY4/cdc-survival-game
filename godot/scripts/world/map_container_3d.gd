@tool
class_name MapContainer3D
extends "res://scripts/world/map_scene_object_3d.gd"

@export var display_name: String = ""
@export var interaction_kind: String = "container"
@export var interaction_distance: float = 1.4
@export var target_id: String = ""
@export var container_type: String = "map"
@export var container_origin: String = "map_scene"
@export var visual_id: String = ""
@export_multiline var initial_inventory_json: String = "[]"
@export_multiline var props_json: String = "{}"


func get_object_kind() -> String:
	return "interactive"


func should_have_pick_area() -> bool:
	return true


func build_object_props() -> Dictionary:
	var props := _json_dictionary(props_json, "props_json")
	var interactive := _dictionary_or_empty(props.get("interactive", {})).duplicate(true)
	if not display_name.strip_edges().is_empty():
		interactive["display_name"] = display_name
	interactive["interaction_distance"] = interaction_distance
	interactive["interaction_kind"] = interaction_kind
	if not target_id.strip_edges().is_empty():
		interactive["target_id"] = target_id
	props["interactive"] = interactive

	var container := _dictionary_or_empty(props.get("container", {})).duplicate(true)
	if not display_name.strip_edges().is_empty():
		container["display_name"] = display_name
	if not container_type.strip_edges().is_empty():
		container["container_type"] = container_type
	if not container_origin.strip_edges().is_empty():
		container["container_origin"] = container_origin
	if not visual_id.strip_edges().is_empty():
		container["visual_id"] = visual_id
	var inventory := _json_array(initial_inventory_json, "initial_inventory_json")
	if not inventory.is_empty():
		container["initial_inventory"] = inventory
	if not container.is_empty():
		props["container"] = container
	return props


func _json_array(raw_json: String, field_name: String) -> Array:
	var raw := raw_json.strip_edges()
	if raw.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	push_warning("地图容器 %s 的 %s 不是合法 Array" % [object_id, field_name])
	return []
