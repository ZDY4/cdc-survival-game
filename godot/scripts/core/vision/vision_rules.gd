extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")

const DEFAULT_VISION_RADIUS := 10

var _actors: Dictionary = {}


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

	var visible_cells: Array[Dictionary] = compute_visible_cells(topology, center, int(state.get("radius", DEFAULT_VISION_RADIUS)))
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
	var normalized_radius: int = max(0, radius)
	var bounds: Dictionary = _vision_bounds(topology, center, normalized_radius)
	var blockers: Dictionary = _dictionary_or_empty(topology.get("sight_blocking_cells", {}))
	var visible: Array[Dictionary] = []
	for x in range(int(bounds.get("min_x", center.x)), int(bounds.get("max_x", center.x)) + 1):
		var dx: int = x - center.x
		for z in range(int(bounds.get("min_z", center.z)), int(bounds.get("max_z", center.z)) + 1):
			var dz: int = z - center.z
			if not _cell_intersects_vision_circle(dx, dz, float(normalized_radius)):
				continue
			var target := GridCoord.new(x, center.y, z)
			if _has_line_of_sight(center, target, blockers):
				visible.append(target.to_dictionary())
	return _sorted_cells(visible)


func has_line_of_sight(from_data: Dictionary, to_data: Dictionary, topology: Dictionary) -> bool:
	var from: RefCounted = GridCoord.from_dictionary(from_data)
	var to: RefCounted = GridCoord.from_dictionary(to_data)
	if from.y != to.y:
		return false
	return _has_line_of_sight(from, to, _dictionary_or_empty(topology.get("sight_blocking_cells", {})))


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


func _vision_bounds(topology: Dictionary, center: RefCounted, radius: int) -> Dictionary:
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	return {
		"min_x": max(int(bounds.get("min_x", center.x - radius)), center.x - radius),
		"max_x": min(int(bounds.get("max_x", center.x + radius)), center.x + radius),
		"min_z": max(int(bounds.get("min_z", center.z - radius)), center.z - radius),
		"max_z": min(int(bounds.get("max_z", center.z + radius)), center.z + radius),
	}


func _has_line_of_sight(from: RefCounted, to: RefCounted, blockers: Dictionary) -> bool:
	if from.x == to.x and from.y == to.y and from.z == to.z:
		return true
	var x: int = from.x
	var z: int = from.z
	var dx: int = abs(to.x - x)
	var dz: int = abs(to.z - z)
	var sx: int = 1 if x < to.x else -1
	var sz: int = 1 if z < to.z else -1
	var err: int = dx - dz
	while true:
		if x == to.x and z == to.z:
			return true
		var e2: int = err * 2
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
		if x == to.x and z == to.z:
			return true
		if blockers.has(GridCoord.new(x, from.y, z).key()):
			return false
	return true


func _cell_intersects_vision_circle(dx: int, dz: int, radius: float) -> bool:
	if radius <= 0.0:
		return dx == 0 and dz == 0
	var qx: float = max(0.0, float(abs(dx)) - 0.5)
	var qz: float = max(0.0, float(abs(dz)) - 0.5)
	return qx * qx + qz * qz <= radius * radius


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
