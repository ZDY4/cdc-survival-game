extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const VisionGeometry = preload("res://scripts/core/vision/vision_geometry.gd")

const DEFAULT_VISION_RADIUS := 10

var _actors: Dictionary = {}
var _geometry := VisionGeometry.new()


func set_actor_radius(actor_id: int, radius: int) -> void:
	var state: Dictionary = _actor_state(actor_id)
	state["radius"] = max(0, radius)
	_actors[actor_id] = state


func clear_actor(actor_id: int) -> void:
	_actors.erase(actor_id)


func recompute_actor(actor_id: int, active_map_id: String, center_data: Dictionary, topology: Dictionary) -> Dictionary:
	var state: Dictionary = _actor_state(actor_id)
	var center: RefCounted = GridCoord.from_dictionary(center_data)
	if active_map_id.is_empty():
		var changed: bool = not str(state.get("active_map_id", "")).is_empty() or not _array_or_empty(state.get("visible_cells", [])).is_empty()
		state["active_map_id"] = ""
		state["visible_cells"] = []
		_actors[actor_id] = state
		return _update_result(changed, actor_id, state, [])

	var visible_cells: Array[Dictionary] = _geometry.compute_visible_cells(topology, center, int(state.get("radius", DEFAULT_VISION_RADIUS)))
	var explored_by_map: Dictionary = _dictionary_or_empty(state.get("explored_by_map", {})).duplicate(true)
	var explored_map: Dictionary = _dictionary_or_empty(explored_by_map.get(active_map_id, {})).duplicate(true)
	var previous_active_map_id: String = str(state.get("active_map_id", ""))
	var previous_visible: String = JSON.stringify(_sorted_cells(_array_or_empty(state.get("visible_cells", []))))
	var previous_explored: String = JSON.stringify(_sorted_cells(_dictionary_values(explored_map)))
	for cell in visible_cells:
		explored_map[_cell_key(cell)] = cell
	explored_by_map[active_map_id] = explored_map

	state["active_map_id"] = active_map_id
	state["visible_cells"] = visible_cells
	state["explored_by_map"] = explored_by_map
	_actors[actor_id] = state

	var current_visible: String = JSON.stringify(_sorted_cells(visible_cells))
	var current_explored: String = JSON.stringify(_sorted_cells(_dictionary_values(explored_by_map.get(active_map_id, {}))))
	var changed := previous_active_map_id != active_map_id or previous_visible != current_visible or previous_explored != current_explored
	return _update_result(changed, actor_id, state, _dictionary_values(explored_by_map.get(active_map_id, {})))


func compute_visible_cells(topology: Dictionary, center: RefCounted, radius: int) -> Array[Dictionary]:
	return _geometry.compute_visible_cells(topology, center, radius)


func has_line_of_sight(from_data: Dictionary, to_data: Dictionary, topology: Dictionary) -> bool:
	return _geometry.has_line_of_sight(from_data, to_data, topology)


func snapshot() -> Dictionary:
	var actor_ids: Array = _actors.keys()
	actor_ids.sort()
	var output: Array[Dictionary] = []
	for actor_id in actor_ids:
		var state: Dictionary = _actor_state(int(actor_id))
		output.append(_state_snapshot(int(actor_id), state))
	return {"actors": output}


func load_snapshot(snapshot_data: Dictionary) -> void:
	_actors.clear()
	for actor_snapshot in _array_or_empty(snapshot_data.get("actors", [])):
		var data: Dictionary = _dictionary_or_empty(actor_snapshot)
		var actor_id: int = int(data.get("actor_id", 0))
		if actor_id <= 0:
			continue
		var explored_by_map: Dictionary = {}
		for map_snapshot in _array_or_empty(data.get("explored_maps", [])):
			var map_data: Dictionary = _dictionary_or_empty(map_snapshot)
			var map_id: String = str(map_data.get("map_id", ""))
			if map_id.is_empty():
				continue
			var explored_cells: Dictionary = {}
			for cell in _array_or_empty(map_data.get("explored_cells", [])):
				var cell_data: Dictionary = _dictionary_or_empty(cell)
				explored_cells[_cell_key(cell_data)] = _normalized_cell(cell_data)
			explored_by_map[map_id] = explored_cells
		_actors[actor_id] = {
			"radius": max(0, int(data.get("radius", DEFAULT_VISION_RADIUS))),
			"active_map_id": str(data.get("active_map_id", "")),
			"visible_cells": _sorted_cells(_array_or_empty(data.get("visible_cells", []))),
			"explored_by_map": explored_by_map,
		}


func _actor_state(actor_id: int) -> Dictionary:
	if _actors.has(actor_id):
		return _dictionary_or_empty(_actors[actor_id]).duplicate(true)
	return {
		"radius": DEFAULT_VISION_RADIUS,
		"active_map_id": "",
		"visible_cells": [],
		"explored_by_map": {},
	}


func _state_snapshot(actor_id: int, state: Dictionary) -> Dictionary:
	var explored_maps: Array[Dictionary] = []
	var explored_by_map: Dictionary = _dictionary_or_empty(state.get("explored_by_map", {}))
	var map_ids: Array = explored_by_map.keys()
	map_ids.sort()
	for map_id in map_ids:
		explored_maps.append({
			"map_id": str(map_id),
			"explored_cells": _sorted_cells(_dictionary_values(explored_by_map.get(map_id, {}))),
		})
	return {
		"actor_id": actor_id,
		"radius": max(0, int(state.get("radius", DEFAULT_VISION_RADIUS))),
		"active_map_id": str(state.get("active_map_id", "")),
		"visible_cells": _sorted_cells(_array_or_empty(state.get("visible_cells", []))),
		"explored_maps": explored_maps,
	}


func _update_result(changed: bool, actor_id: int, state: Dictionary, explored_cells: Array) -> Dictionary:
	return {
		"changed": changed,
		"actor_id": actor_id,
		"active_map_id": str(state.get("active_map_id", "")),
		"visible_cells": _sorted_cells(_array_or_empty(state.get("visible_cells", []))),
		"explored_cells": _sorted_cells(explored_cells),
	}


func _sorted_cells(cells: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for cell in cells:
		output.append(_normalized_cell(_dictionary_or_empty(cell)))
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("y", 0)) != int(b.get("y", 0)):
			return int(a.get("y", 0)) < int(b.get("y", 0))
		if int(a.get("x", 0)) != int(b.get("x", 0)):
			return int(a.get("x", 0)) < int(b.get("x", 0))
		return int(a.get("z", 0)) < int(b.get("z", 0))
	)
	return output


func _normalized_cell(cell: Dictionary) -> Dictionary:
	return {
		"x": int(cell.get("x", 0)),
		"y": int(cell.get("y", 0)),
		"z": int(cell.get("z", 0)),
	}


func _cell_key(cell: Dictionary) -> String:
	return "%d:%d:%d" % [int(cell.get("x", 0)), int(cell.get("y", 0)), int(cell.get("z", 0))]


func _dictionary_values(value: Variant) -> Array:
	var data: Dictionary = _dictionary_or_empty(value)
	var output: Array = []
	var keys: Array = data.keys()
	keys.sort()
	for key in keys:
		output.append(data[key])
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
