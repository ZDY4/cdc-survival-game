@tool
class_name MapTransitionTrigger3D
extends "res://scripts/world/map_scene_object_3d.gd"

@export var display_name: String = "进入"
@export var interaction_distance: float = 1.4
@export_enum("enter_subscene", "exit_to_outdoor", "enter_outdoor_location", "enter_overworld") var interaction_kind: String = "enter_overworld"
@export var target_id: String = ""
@export var return_spawn_id: String = ""
@export var target_entry_point_id: String = ""
@export var entry_point_id: String = ""
@export var required_world_flags: Array[String] = []
@export var blocked_world_flags: Array[String] = []
@export var required_unlocked_locations: Array[String] = []
@export var blocked_unlocked_locations: Array[String] = []
@export_multiline var options_json: String = "[]"
@export_multiline var props_json: String = "{}"


func get_object_kind() -> String:
	return "trigger"


func should_have_pick_area() -> bool:
	return true


func build_object_props() -> Dictionary:
	var props := _json_dictionary(props_json, "props_json")
	var trigger := _dictionary_or_empty(props.get("trigger", {})).duplicate(true)
	trigger["display_name"] = display_name
	trigger["interaction_distance"] = interaction_distance
	trigger["interaction_kind"] = interaction_kind
	if not target_id.strip_edges().is_empty():
		trigger["target_id"] = target_id
	if not return_spawn_id.strip_edges().is_empty():
		trigger["return_spawn_id"] = return_spawn_id
	if not target_entry_point_id.strip_edges().is_empty():
		trigger["target_entry_point_id"] = target_entry_point_id
	if not entry_point_id.strip_edges().is_empty():
		trigger["entry_point_id"] = entry_point_id
	_copy_string_array(trigger, "required_world_flags", required_world_flags)
	_copy_string_array(trigger, "blocked_world_flags", blocked_world_flags)
	_copy_string_array(trigger, "required_unlocked_locations", required_unlocked_locations)
	_copy_string_array(trigger, "blocked_unlocked_locations", blocked_unlocked_locations)
	var options := _json_array(options_json, "options_json")
	if not options.is_empty():
		trigger["options"] = options
	elif not trigger.has("options"):
		trigger["options"] = []
	props["trigger"] = trigger
	return props


func _json_array(raw_json: String, field_name: String) -> Array:
	var raw := raw_json.strip_edges()
	if raw.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	push_warning("地图切换点 %s 的 %s 不是合法 Array" % [object_id, field_name])
	return []


func _copy_string_array(target: Dictionary, key: String, value: Array[String]) -> void:
	if value.is_empty():
		return
	target[key] = value.duplicate()
