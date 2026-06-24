@tool
class_name WorldTilePrototype
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export_enum("building", "surface", "prop", "marker") var category: String = "building"
@export var scene: PackedScene
@export var footprint: Vector2i = Vector2i.ONE
@export var tags: PackedStringArray = []


func source_id() -> String:
	return str(id).strip_edges()


func scene_path() -> String:
	if scene == null:
		return ""
	return scene.resource_path
