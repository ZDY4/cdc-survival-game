extends RefCounted

var map_id: String = ""
var name: String = ""
var size: Dictionary = {}
var default_level: int = 0
var bounds: Dictionary = {}
var entry_points: Dictionary = {}
var object_count: int = 0
var objects_by_kind: Dictionary = {}
var occupied_cells: Dictionary = {}
var blocking_cells: Dictionary = {}
var sight_blocking_cells: Dictionary = {}
var interactive_objects: Array[Dictionary] = []
var trigger_objects: Array[Dictionary] = []
var pickup_objects: Array[Dictionary] = []
var ai_spawn_objects: Array[Dictionary] = []
var interaction_targets: Dictionary = {}


func to_dictionary() -> Dictionary:
	return {
		"map_id": map_id,
		"name": name,
		"size": size,
		"default_level": default_level,
		"bounds": bounds,
		"entry_points": entry_points,
		"object_count": object_count,
		"objects_by_kind": objects_by_kind,
		"occupied_cells": occupied_cells,
		"blocking_cells": blocking_cells,
		"sight_blocking_cells": sight_blocking_cells,
		"occupied_cell_count": occupied_cells.size(),
		"blocking_cell_count": blocking_cells.size(),
		"sight_blocking_cell_count": sight_blocking_cells.size(),
		"interactive_objects": interactive_objects,
		"trigger_objects": trigger_objects,
		"pickup_objects": pickup_objects,
		"ai_spawn_objects": ai_spawn_objects,
		"interaction_targets": interaction_targets,
	}
