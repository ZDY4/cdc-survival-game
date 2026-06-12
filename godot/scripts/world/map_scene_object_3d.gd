@tool
class_name MapSceneObject3D
extends Node3D

const GROUP_NAME := "map_scene_object"

@export var object_id: String = ""
@export var footprint: Vector2i = Vector2i.ONE
@export_enum("north", "east", "south", "west") var grid_rotation: String = "north"
@export var blocks_movement: bool = false
@export var blocks_sight: bool = false
@export_multiline var extra_props_json: String = "{}"


func _enter_tree() -> void:
	add_to_group(GROUP_NAME)


func _ready() -> void:
	if should_have_pick_area():
		ensure_pick_area()


func get_object_kind() -> String:
	return ""


func should_have_pick_area() -> bool:
	return false


func to_object_definition() -> Dictionary:
	return {
		"object_id": object_id,
		"kind": get_object_kind(),
		"anchor": {
			"x": int(round(position.x)),
			"y": int(round(position.y)),
			"z": int(round(position.z)),
		},
		"footprint": {
			"width": max(1, footprint.x),
			"height": max(1, footprint.y),
		},
		"rotation": grid_rotation,
		"blocks_movement": blocks_movement,
		"blocks_sight": blocks_sight,
		"props": build_object_props(),
	}


func build_object_props() -> Dictionary:
	return _json_dictionary(extra_props_json, "extra_props_json")


func _json_dictionary(raw_json: String, field_name: String) -> Dictionary:
	var raw := raw_json.strip_edges()
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	push_warning("地图对象 %s 的 %s 不是合法 Dictionary" % [object_id, field_name])
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func ensure_pick_area() -> void:
	var area := get_node_or_null("PickArea") as Area3D
	if area == null:
		area = Area3D.new()
		area.name = "PickArea"
		add_child(area)
		_assign_scene_owner(area)
	var shape := area.get_node_or_null("PickShape") as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new()
		shape.name = "PickShape"
		area.add_child(shape)
		_assign_scene_owner(shape)
	var box := shape.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		shape.shape = box
	var width: int = max(1, footprint.x)
	var height: int = max(1, footprint.y)
	box.size = Vector3(width, 0.7, height)
	shape.position = Vector3((width - 1) * 0.5, 0.35, (height - 1) * 0.5)


func _assign_scene_owner(node: Node) -> void:
	if Engine.is_editor_hint() and owner != null:
		node.owner = owner
