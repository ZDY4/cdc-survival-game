extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const MapTopology = preload("res://scripts/world/map_topology.gd")


func build_from_definition(map_definition: Dictionary) -> MapTopology:
	var topology: MapTopology = MapTopology.new()
	topology.map_id = str(map_definition.get("id", ""))
	topology.name = str(map_definition.get("name", topology.map_id))
	topology.size = _dictionary_or_empty(map_definition.get("size", {}))
	topology.default_level = int(map_definition.get("default_level", 0))
	topology.bounds = _bounds_from_size(topology.size)
	_collect_entry_points(topology, _array_or_empty(map_definition.get("entry_points", [])))
	_collect_objects(topology, _array_or_empty(map_definition.get("objects", [])))
	return topology


func _bounds_from_size(size: Dictionary) -> Dictionary:
	var width: int = int(size.get("width", 0))
	var height: int = int(size.get("height", 0))
	return {
		"min_x": 0,
		"max_x": max(0, width - 1),
		"min_z": 0,
		"max_z": max(0, height - 1),
	}


func _collect_entry_points(topology: MapTopology, entry_points: Array) -> void:
	for entry in entry_points:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var entry_id: String = str(entry_data.get("id", ""))
		if entry_id.is_empty():
			continue
		var grid: Dictionary = _dictionary_or_empty(entry_data.get("grid", {}))
		topology.entry_points[entry_id] = GridCoord.from_dictionary(grid).to_dictionary()


func _collect_objects(topology: MapTopology, objects: Array) -> void:
	for object in objects:
		var object_data: Dictionary = _dictionary_or_empty(object)
		var object_id: String = str(object_data.get("object_id", ""))
		var kind: String = str(object_data.get("kind", ""))
		if object_id.is_empty() or kind.is_empty():
			continue

		topology.object_count += 1
		topology.objects_by_kind[kind] = int(topology.objects_by_kind.get(kind, 0)) + 1

		var cells: Array[RefCounted] = expand_object_footprint(object_data)
		for cell in cells:
			var cell_key: String = cell.key()
			topology.occupied_cells[cell_key] = object_id
			if object_effectively_blocks_movement(object_data):
				topology.blocking_cells[cell_key] = object_id
			if object_effectively_blocks_sight(object_data):
				topology.sight_blocking_cells[cell_key] = object_id

		var summary: Dictionary = _object_summary(object_data, cells)
		match kind:
			"interactive":
				topology.interactive_objects.append(summary)
			"trigger":
				topology.trigger_objects.append(summary)
			"pickup":
				topology.pickup_objects.append(summary)
			"ai_spawn":
				topology.ai_spawn_objects.append(summary)


func expand_object_footprint(object: Dictionary) -> Array[RefCounted]:
	var anchor: RefCounted = GridCoord.from_dictionary(_dictionary_or_empty(object.get("anchor", {})))
	var size: Dictionary = rotated_footprint_size(_dictionary_or_empty(object.get("footprint", {})), str(object.get("rotation", "north")))
	var cells: Array[RefCounted] = []
	for dz in range(int(size["height"])):
		for dx in range(int(size["width"])):
			cells.append(GridCoord.new(anchor.x + dx, anchor.y, anchor.z + dz))
	return cells


func rotated_footprint_size(footprint: Dictionary, rotation: String) -> Dictionary:
	var width: int = int(footprint.get("width", 1))
	var height: int = int(footprint.get("height", 1))
	match rotation:
		"east", "west":
			return {"width": height, "height": width}
		_:
			return {"width": width, "height": height}


func object_effectively_blocks_movement(object: Dictionary) -> bool:
	if bool(object.get("blocks_movement", false)):
		return true
	if str(object.get("kind", "")) != "building":
		return false
	return not _building_has_layout(object)


func object_effectively_blocks_sight(object: Dictionary) -> bool:
	if bool(object.get("blocks_sight", false)):
		return true
	if str(object.get("kind", "")) != "building":
		return false
	return not _building_has_layout(object)


func _building_has_layout(object: Dictionary) -> bool:
	var props: Dictionary = _dictionary_or_empty(object.get("props", {}))
	var building: Variant = props.get("building", null)
	if typeof(building) != TYPE_DICTIONARY:
		return false
	return not (building as Dictionary).get("layout", {}).is_empty()


func _object_summary(object: Dictionary, cells: Array[RefCounted]) -> Dictionary:
	var cell_output: Array[Dictionary] = []
	for cell in cells:
		cell_output.append(cell.to_dictionary())
	return {
		"object_id": str(object.get("object_id", "")),
		"kind": str(object.get("kind", "")),
		"anchor": GridCoord.from_dictionary(_dictionary_or_empty(object.get("anchor", {}))).to_dictionary(),
		"footprint": _dictionary_or_empty(object.get("footprint", {})),
		"rotation": str(object.get("rotation", "north")),
		"cells": cell_output,
		"props": _dictionary_or_empty(object.get("props", {})),
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
