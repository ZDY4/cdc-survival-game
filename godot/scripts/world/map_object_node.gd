@tool
class_name MapObjectNode
extends Node3D

@export var object_id: String = ""
@export var kind: String = ""
@export var footprint: Vector2i = Vector2i.ONE
@export_enum("north", "east", "south", "west") var grid_rotation: String = "north"
@export var blocks_movement: bool = false
@export var blocks_sight: bool = false
@export_multiline var props_json: String = "{}"


func to_object_definition() -> Dictionary:
	return {
		"object_id": object_id,
		"kind": kind,
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
		"props": _props_dictionary(),
	}


func _props_dictionary() -> Dictionary:
	var raw := props_json.strip_edges()
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	push_warning("地图对象 %s 的 props_json 不是合法 Dictionary" % object_id)
	return {}
