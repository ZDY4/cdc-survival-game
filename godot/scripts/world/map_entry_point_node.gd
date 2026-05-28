@tool
class_name MapEntryPointNode
extends Marker3D

@export var entry_id: String = ""
@export var facing: String = ""


func to_entry_definition() -> Dictionary:
	return {
		"id": entry_id,
		"grid": {
			"x": int(round(position.x)),
			"y": int(round(position.y)),
			"z": int(round(position.z)),
		},
		"facing": null if facing.strip_edges().is_empty() else facing,
	}
