extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, world_snapshot: Dictionary) -> Dictionary:
	var map: Dictionary = _dictionary_or_empty(world_snapshot.get("map", {}))
	var overworld: Dictionary = _dictionary_or_empty(runtime_snapshot.get("overworld", {}))
	var active_location_id := str(runtime_snapshot.get("active_location_id", ""))
	var unlocked_locations: Variant = runtime_snapshot.get("unlocked_locations", overworld.get("unlocked_locations", []))
	return {
		"active_map_id": str(runtime_snapshot.get("active_map_id", "")),
		"active_location_id": active_location_id,
		"active_location_name": _location_name(active_location_id),
		"active_entry_point_id": str(runtime_snapshot.get("active_entry_point_id", "")),
		"map_name": _map_name(str(runtime_snapshot.get("active_map_id", ""))),
		"size": _dictionary_or_empty(map.get("size", {})),
		"object_count": int(map.get("object_count", 0)),
		"occupied_cell_count": int(map.get("occupied_cell_count", 0)),
		"blocking_cell_count": int(map.get("blocking_cell_count", 0)),
		"entry_points": _entry_point_ids(map),
		"objects_by_kind": _dictionary_or_empty(map.get("objects_by_kind", {})),
		"unlocked_locations": _unlocked_location_summaries(unlocked_locations),
	}


func _map_name(map_id: String) -> String:
	if registry == null:
		return map_id
	var record: Dictionary = _dictionary_or_empty(registry.get_library("maps").get(map_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", data.get("map_name", map_id)))


func _location_name(location_id: String) -> String:
	var location: Dictionary = _location_data(location_id)
	return str(location.get("name", location_id))


func _unlocked_location_summaries(value: Variant) -> Array[String]:
	var ids := _array_of_strings(value)
	var result: Array[String] = []
	for location_id in ids:
		var name := _location_name(location_id)
		result.append("%s (%s)" % [name, location_id] if name != location_id else location_id)
	return result


func _location_data(location_id: String) -> Dictionary:
	if registry == null or location_id.is_empty():
		return {}
	for record in registry.get_library("overworld").values():
		var data: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record).get("data", record))
		for location in _array_or_empty(data.get("locations", [])):
			var location_data: Dictionary = _dictionary_or_empty(location)
			if str(location_data.get("id", "")) == location_id:
				return location_data
	return {}


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


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
