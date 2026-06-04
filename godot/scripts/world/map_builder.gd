extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const MapTopology = preload("res://scripts/world/map_topology.gd")


func build_from_definition(map_definition: Dictionary) -> MapTopology:
	var topology: MapTopology = MapTopology.new()
	topology.map_id = str(map_definition.get("id", ""))
	topology.name = str(map_definition.get("name", topology.map_id))
	topology.size = _dictionary_or_empty(map_definition.get("size", {}))
	topology.default_level = int(map_definition.get("default_level", 0))
	topology.levels = _map_levels(map_definition, topology.default_level)
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


func _map_levels(map_definition: Dictionary, default_level: int) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for level in _array_or_empty(map_definition.get("levels", [])):
		var level_data: Dictionary = _dictionary_or_empty(level)
		if level_data.is_empty():
			continue
		output.append({
			"y": int(level_data.get("y", default_level)),
			"cells": _array_or_empty(level_data.get("cells", [])).duplicate(true),
		})
	if output.is_empty():
		output.append({"y": default_level, "cells": []})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("y", 0)) < int(b.get("y", 0))
	)
	return output


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
		var door_summary: Dictionary = _door_summary(summary)
		if not door_summary.is_empty():
			topology.door_objects.append(door_summary)
		var station_summary: Dictionary = _crafting_station_summary(summary)
		if not station_summary.is_empty():
			topology.crafting_stations.append(station_summary)
		match kind:
			"interactive":
				topology.interactive_objects.append(summary)
				topology.interaction_targets[object_id] = _interaction_target(summary, "container")
			"trigger":
				topology.trigger_objects.append(summary)
				topology.interaction_targets[object_id] = _interaction_target(summary, "scene_transition")
			"pickup":
				topology.pickup_objects.append(summary)
				topology.interaction_targets[object_id] = _interaction_target(summary, "pickup")
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
	var door: Dictionary = _door_props(object)
	if not door.is_empty():
		return not bool(door.get("is_open", door.get("open", false)))
	if str(object.get("kind", "")) != "building":
		return false
	return not _building_has_layout(object)


func object_effectively_blocks_sight(object: Dictionary) -> bool:
	if bool(object.get("blocks_sight", false)):
		return true
	var door: Dictionary = _door_props(object)
	if not door.is_empty():
		return not bool(door.get("is_open", door.get("open", false))) and bool(door.get("blocks_sight_when_closed", true))
	if str(object.get("kind", "")) != "building":
		return false
	return not _building_has_layout(object)


func _door_props(object: Dictionary) -> Dictionary:
	var props: Dictionary = _dictionary_or_empty(object.get("props", {}))
	return _dictionary_or_empty(props.get("door", {}))


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


func _interaction_target(object_summary: Dictionary, fallback_kind: String) -> Dictionary:
	var props: Dictionary = _dictionary_or_empty(object_summary.get("props", {}))
	var interaction_props: Dictionary = _dictionary_or_empty(props.get("interactive", {}))
	var trigger_props: Dictionary = _dictionary_or_empty(props.get("trigger", {}))
	var door_props: Dictionary = _dictionary_or_empty(props.get("door", {}))
	var trigger_options: Array = _array_or_empty(trigger_props.get("options", []))
	var primary_trigger_option: Dictionary = {}
	if not trigger_options.is_empty():
		primary_trigger_option = _dictionary_or_empty(trigger_options[0])
	var pickup_props: Dictionary = _dictionary_or_empty(props.get("pickup", {}))
	var container_props: Dictionary = _dictionary_or_empty(props.get("container", {}))
	var interaction_kind: String = str(interaction_props.get("interaction_kind", ""))
	if interaction_kind.is_empty():
		interaction_kind = str(trigger_props.get("interaction_kind", ""))
	if interaction_kind.is_empty():
		interaction_kind = str(primary_trigger_option.get("kind", ""))
	if interaction_kind.is_empty():
		interaction_kind = str(door_props.get("interaction_kind", ""))
	if interaction_kind.is_empty() and not door_props.is_empty():
		interaction_kind = "door"
	if interaction_kind.is_empty():
		interaction_kind = fallback_kind

	var display_name: String = str(interaction_props.get("display_name", ""))
	if display_name.is_empty():
		display_name = str(trigger_props.get("display_name", ""))
	if display_name.is_empty():
		display_name = str(primary_trigger_option.get("display_name", ""))
	if display_name.is_empty():
		display_name = str(door_props.get("display_name", ""))
	if display_name.is_empty():
		display_name = str(container_props.get("display_name", ""))
	if display_name.is_empty():
		display_name = str(object_summary.get("object_id", ""))

	return {
		"target_id": object_summary.get("object_id", ""),
		"target_type": "map_object",
		"display_name": display_name,
		"kind": interaction_kind,
		"anchor": object_summary.get("anchor", {}),
		"cells": object_summary.get("cells", []),
		"item_id": str(pickup_props.get("item_id", "")),
		"min_count": int(pickup_props.get("min_count", 1)),
		"max_count": int(pickup_props.get("max_count", pickup_props.get("min_count", 1))),
		"target_map_id": str(primary_trigger_option.get("target_id", trigger_props.get("target_id", interaction_props.get("target_id", "")))),
		"return_spawn_id": str(primary_trigger_option.get("return_spawn_id", trigger_props.get("return_spawn_id", ""))),
		"target_entry_point_id": str(primary_trigger_option.get("target_entry_point_id", trigger_props.get("target_entry_point_id", ""))),
		"entry_point_id": str(primary_trigger_option.get("entry_point_id", trigger_props.get("entry_point_id", ""))),
		"container_inventory": _array_or_empty(container_props.get("initial_inventory", [])),
		"door": _door_summary(object_summary),
	}


func _door_summary(object_summary: Dictionary) -> Dictionary:
	var props: Dictionary = _dictionary_or_empty(object_summary.get("props", {}))
	var door_props: Dictionary = _dictionary_or_empty(props.get("door", {}))
	if door_props.is_empty():
		return {}
	var is_open: bool = bool(door_props.get("is_open", door_props.get("open", false)))
	var locked: bool = bool(door_props.get("locked", false))
	var blocks_sight_when_closed: bool = bool(door_props.get("blocks_sight_when_closed", true))
	return {
		"door_id": str(door_props.get("door_id", object_summary.get("object_id", ""))),
		"object_id": str(object_summary.get("object_id", "")),
		"display_name": str(door_props.get("display_name", object_summary.get("object_id", ""))),
		"anchor": _dictionary_or_empty(object_summary.get("anchor", {})).duplicate(true),
		"cells": _array_or_empty(object_summary.get("cells", [])).duplicate(true),
		"is_open": is_open,
		"locked": locked,
		"blocks_movement": not is_open,
		"blocks_sight": not is_open and blocks_sight_when_closed,
		"blocks_sight_when_closed": blocks_sight_when_closed,
	}


func _crafting_station_summary(object_summary: Dictionary) -> Dictionary:
	var props: Dictionary = _dictionary_or_empty(object_summary.get("props", {}))
	var station_props: Dictionary = _dictionary_or_empty(props.get("crafting_station", {}))
	var station_id := str(station_props.get("station_id", station_props.get("id", "")))
	if station_id.is_empty():
		return {}
	return {
		"station_id": station_id,
		"object_id": str(object_summary.get("object_id", "")),
		"display_name": str(station_props.get("display_name", station_id)),
		"anchor": _dictionary_or_empty(object_summary.get("anchor", {})).duplicate(true),
		"cells": _array_or_empty(object_summary.get("cells", [])).duplicate(true),
		"range": max(0, int(station_props.get("range", 1))),
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
