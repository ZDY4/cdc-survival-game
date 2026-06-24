@tool
class_name WorldTilePalette
extends Resource

const WorldSurfaceTileSetScript = preload("res://scripts/world/tiles/world_surface_tile_set.gd")
const WorldTilePrototypeScript = preload("res://scripts/world/tiles/world_tile_prototype.gd")
const WorldWallTileSetScript = preload("res://scripts/world/tiles/world_wall_tile_set.gd")

@export var id: StringName
@export var display_name: String = ""
@export var prototypes: Array[WorldTilePrototypeScript] = []
@export var wall_sets: Array[WorldWallTileSetScript] = []
@export var surface_sets: Array[WorldSurfaceTileSetScript] = []


func source_id() -> String:
	return str(id).strip_edges()
