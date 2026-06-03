extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, world_snapshot: Dictionary) -> Dictionary:
	var map: Dictionary = _dictionary_or_empty(world_snapshot.get("map", {}))
	var overworld: Dictionary = _dictionary_or_empty(runtime_snapshot.get("overworld", {}))
	return {
		"active_map_id": str(runtime_snapshot.get("active_map_id", "")),
		"active_location_id": str(runtime_snapshot.get("active_location_id", "")),
		"active_entry_point_id": str(runtime_snapshot.get("active_entry_point_id", "")),
		"map_name": _map_name(str(runtime_snapshot.get("active_map_id", ""))),
		"size": _dictionary_or_empty(map.get("size", {})),
		"object_count": int(map.get("object_count", 0)),
		"occupied_cell_count": int(map.get("occupied_cell_count", 0)),
		"blocking_cell_count": int(map.get("blocking_cell_count", 0)),
		"entry_points": _entry_point_ids(map),
		"objects_by_kind": _dictionary_or_empty(map.get("objects_by_kind", {})),
		"unlocked_locations": _array_of_strings(overworld.get("unlocked_locations", [])),
	}


func _map_name(map_id: String) -> String:
	if registry == null:
		return map_id
	var record: Dictionary = _dictionary_or_empty(registry.get_library("maps").get(map_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", data.get("map_name", map_id)))


func _entry_point_ids(map: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var entry_points: Variant = map.get("entry_points", {})
	if typeof(entry_points) == TYPE_DICTIONARY:
		for key in (entry_points as Dictionary).keys():
			ids.append(str(key))
	elif typeof(entry_points) == TYPE_ARRAY:
		for item in entry_points:
			var data: Dictionary = _dictionary_or_empty(item)
			ids.append(str(data.get("id", "")))
	ids.sort()
	return ids


func _array_of_strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(str(item))
	result.sort()
	return result


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
