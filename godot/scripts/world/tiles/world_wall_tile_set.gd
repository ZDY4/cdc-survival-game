@tool
class_name WorldWallTileSet
extends Resource

const WorldTilePrototypeScript = preload("res://scripts/world/tiles/world_tile_prototype.gd")

@export var id: StringName
@export var display_name: String = ""
@export var corner: WorldTilePrototypeScript
@export var straight: WorldTilePrototypeScript
@export var end: WorldTilePrototypeScript
@export var t_junction: WorldTilePrototypeScript
@export var cross: WorldTilePrototypeScript
@export var isolated: WorldTilePrototypeScript


func source_id() -> String:
	return str(id).strip_edges()
