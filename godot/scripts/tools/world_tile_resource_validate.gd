extends SceneTree

const WorldTileResourceIndex = preload("res://scripts/world/tiles/world_tile_resource_index.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var index := WorldTileResourceIndex.new()
	index.load_palette()
	var issues := index.validate()
	if not issues.is_empty():
		for issue in issues:
			printerr(issue)
		quit(1)
		return
	print("world_tile_resource_validate passed:")
	print({
		"prototype_count": index.sorted_prototype_ids().size(),
		"wall_set_count": index.sorted_wall_set_ids().size(),
		"surface_set_count": index.sorted_surface_set_ids().size(),
	})
	quit(0)
