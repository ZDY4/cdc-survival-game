@tool
class_name WorldSurfaceTileSet
extends Resource

const WorldTilePrototypeScript = preload("res://scripts/world/tiles/world_tile_prototype.gd")

@export var id: StringName
@export var display_name: String = ""
@export var flat_top: WorldTilePrototypeScript
@export var ramp_north: WorldTilePrototypeScript
@export var ramp_south: WorldTilePrototypeScript
@export var ramp_east: WorldTilePrototypeScript
@export var ramp_west: WorldTilePrototypeScript
@export var cliff_side: WorldTilePrototypeScript
@export var cliff_inner_corner: WorldTilePrototypeScript
@export var cliff_outer_corner: WorldTilePrototypeScript


func source_id() -> String:
	return str(id).strip_edges()
