extends RefCounted

const MAP_SCENE_DIR := "res://scenes/maps"


func load_map_definition(map_id: String) -> Dictionary:
	var path := scene_path(map_id)
	if not ResourceLoader.exists(path):
		return {
			"ok": false,
			"reason": "map_scene_missing",
			"error": "map scene not found: %s" % path,
			"path": path,
		}

	var packed: PackedScene = load(path)
	if packed == null:
		return {
			"ok": false,
			"reason": "map_scene_load_failed",
			"error": "failed to load map scene: %s" % path,
			"path": path,
		}

	var root := packed.instantiate()
	if root == null or not root.has_method("to_definition"):
		if root != null:
			root.free()
		return {
			"ok": false,
			"reason": "map_scene_root_invalid",
			"error": "map scene root does not expose to_definition: %s" % path,
			"path": path,
		}

	var definition: Dictionary = root.to_definition()
	root.free()
	return {
		"ok": true,
		"path": path,
		"data": definition,
	}


func scene_path(map_id: String) -> String:
	return "%s/%s.tscn" % [MAP_SCENE_DIR, map_id]
