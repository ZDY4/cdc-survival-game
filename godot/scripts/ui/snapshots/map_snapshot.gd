extends RefCounted

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, world_snapshot: Dictionary, tracked_quest: Dictionary = {}) -> Dictionary:
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
		"entry_point_grids": _entry_point_grids(map),
		"objects_by_kind": _dictionary_or_empty(map.get("objects_by_kind", {})),
		"unlocked_locations": _unlocked_location_summaries(unlocked_locations),
		"overworld_overview": _overworld_overview(active_location_id, unlocked_locations),
		"tracked_markers": _tracked_markers(tracked_quest, runtime_snapshot, world_snapshot),
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


func _overworld_overview(active_location_id: String, unlocked_locations: Variant) -> Dictionary:
	var result: Dictionary = {
		"size": {},
		"active_location_id": active_location_id,
		"locations": [],
		"route_cells": [],
		"unlocked_count": 0,
	}
	if registry == null:
		return result
	var unlocked_ids := _string_lookup(unlocked_locations)
	var records: Dictionary = registry.get_library("overworld")
	for overworld_id in records.keys():
		var record: Dictionary = _dictionary_or_empty(records.get(overworld_id, {}))
		var data: Dictionary = _dictionary_or_empty(record.get("data", record))
		result["overworld_id"] = str(data.get("id", overworld_id))
		result["size"] = _dictionary_or_empty(data.get("size", {})).duplicate(true)
		var locations: Array[Dictionary] = []
		var unlocked_count := 0
		for location in _array_or_empty(data.get("locations", [])):
			var location_data: Dictionary = _dictionary_or_empty(location)
			var location_id := str(location_data.get("id", ""))
			if location_id.is_empty() or not bool(location_data.get("visible", true)):
				continue
			var unlocked := unlocked_ids.has(location_id) or bool(location_data.get("default_unlocked", false))
			if unlocked:
				unlocked_count += 1
			var icon_asset := AssetPathResolver.resolve_media_asset(str(location_data.get("icon", "")), "location")
			locations.append({
				"id": location_id,
				"name": str(location_data.get("name", location_id)),
				"kind": str(location_data.get("kind", "")),
				"icon": str(location_data.get("icon", "")),
				"icon_asset": icon_asset,
				"thumbnail_asset": _thumbnail_asset(icon_asset, "location"),
				"map_id": str(location_data.get("map_id", "")),
				"danger_level": int(location_data.get("danger_level", 0)),
				"grid": _dictionary_or_empty(location_data.get("overworld_cell", {})).duplicate(true),
				"unlocked": unlocked,
				"active": location_id == active_location_id,
				"parent_outdoor_location_id": str(location_data.get("parent_outdoor_location_id", "")),
			})
		result["locations"] = locations
		result["unlocked_count"] = unlocked_count
		result["route_cells"] = _overworld_route_cells(data)
		return result
	return result


func _overworld_route_cells(data: Dictionary) -> Array[Dictionary]:
	var route_cells: Array[Dictionary] = []
	for cell in _array_or_empty(data.get("cells", [])):
		var cell_data: Dictionary = _dictionary_or_empty(cell)
		var terrain := str(cell_data.get("terrain", ""))
		if terrain != "road":
			continue
		route_cells.append({
			"terrain": terrain,
			"grid": _dictionary_or_empty(cell_data.get("grid", {})).duplicate(true),
		})
	return route_cells


func _thumbnail_asset(icon_asset: Dictionary, domain: String) -> Dictionary:
	var thumbnail := icon_asset.duplicate(true)
	thumbnail["thumbnail"] = true
	thumbnail["thumbnail_domain"] = domain
	thumbnail["source"] = "icon_asset"
	return thumbnail


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


func _entry_point_grids(map: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var entry_points: Variant = map.get("entry_points", {})
	if typeof(entry_points) == TYPE_DICTIONARY:
		for key in (entry_points as Dictionary).keys():
			result[str(key)] = _dictionary_or_empty((entry_points as Dictionary).get(key, {})).duplicate(true)
	elif typeof(entry_points) == TYPE_ARRAY:
		for item in entry_points:
			var data: Dictionary = _dictionary_or_empty(item)
			var entry_id := str(data.get("id", ""))
			if entry_id.is_empty():
				continue
			result[entry_id] = _dictionary_or_empty(data.get("grid", {})).duplicate(true)
	return result


func _tracked_markers(tracked_quest: Dictionary, runtime_snapshot: Dictionary, world_snapshot: Dictionary) -> Array[Dictionary]:
	if not bool(tracked_quest.get("active", false)):
		return []
	var objective: Dictionary = _dictionary_or_empty(tracked_quest.get("objective", {}))
	var objective_type := str(tracked_quest.get("objective_type", objective.get("type", "")))
	match objective_type:
		"collect":
			return _collect_markers(tracked_quest, objective, world_snapshot)
		"kill":
			return _kill_markers(tracked_quest, objective, runtime_snapshot, world_snapshot)
		_:
			return [_unresolved_marker(tracked_quest, objective, "unsupported_objective")]


func _collect_markers(tracked_quest: Dictionary, objective: Dictionary, world_snapshot: Dictionary) -> Array[Dictionary]:
	var item_id := _normalize_content_id(objective.get("item_id", ""))
	if item_id.is_empty():
		return [_unresolved_marker(tracked_quest, objective, "item_id_missing")]
	var markers: Array[Dictionary] = []
	var map: Dictionary = _dictionary_or_empty(world_snapshot.get("map", {}))
	for pickup in _array_or_empty(map.get("pickup_objects", [])):
		var pickup_data: Dictionary = _dictionary_or_empty(pickup)
		var pickup_props: Dictionary = _dictionary_or_empty(_dictionary_or_empty(pickup_data.get("props", {})).get("pickup", {}))
		if _normalize_content_id(pickup_props.get("item_id", pickup_data.get("item_id", ""))) != item_id:
			continue
		markers.append(_object_marker(tracked_quest, objective, pickup_data, "pickup"))
	for object in _array_or_empty(map.get("interactive_objects", [])):
		var object_data: Dictionary = _dictionary_or_empty(object)
		var container: Dictionary = _dictionary_or_empty(_dictionary_or_empty(object_data.get("props", {})).get("container", {}))
		if not _container_has_item(container, item_id):
			continue
		markers.append(_object_marker(tracked_quest, objective, object_data, "container"))
	if markers.is_empty():
		markers.append(_unresolved_marker(tracked_quest, objective, "target_not_on_current_map"))
	return markers


func _kill_markers(tracked_quest: Dictionary, objective: Dictionary, runtime_snapshot: Dictionary, world_snapshot: Dictionary) -> Array[Dictionary]:
	var enemy_type := str(objective.get("enemy_type", ""))
	if enemy_type.is_empty():
		return [_unresolved_marker(tracked_quest, objective, "enemy_type_missing")]
	var active_map_id := str(runtime_snapshot.get("active_map_id", ""))
	var markers: Array[Dictionary] = []
	for actor in _array_or_empty(world_snapshot.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if not str(actor_data.get("map_id", active_map_id)).is_empty() and str(actor_data.get("map_id", active_map_id)) != active_map_id:
			continue
		if not _enemy_matches_marker(actor_data, enemy_type):
			continue
		markers.append({
			"kind": "quest_objective",
			"target_kind": "actor",
			"target_id": str(actor_data.get("actor_id", "")),
			"display_name": str(actor_data.get("display_name", actor_data.get("definition_id", enemy_type))),
			"quest_id": str(tracked_quest.get("quest_id", "")),
			"quest_title": str(tracked_quest.get("title", "")),
			"objective_type": "kill",
			"requirement_text": str(objective.get("requirement_text", tracked_quest.get("objective_text", ""))),
			"grid": _dictionary_or_empty(actor_data.get("grid_position", {})).duplicate(true),
			"status": "located",
		})
	if markers.is_empty():
		markers.append(_unresolved_marker(tracked_quest, objective, "target_not_on_current_map"))
	return markers


func _object_marker(tracked_quest: Dictionary, objective: Dictionary, object_data: Dictionary, target_kind: String) -> Dictionary:
	return {
		"kind": "quest_objective",
		"target_kind": target_kind,
		"target_id": str(object_data.get("object_id", "")),
		"display_name": _object_display_name(object_data),
		"quest_id": str(tracked_quest.get("quest_id", "")),
		"quest_title": str(tracked_quest.get("title", "")),
		"objective_type": str(objective.get("type", "collect")),
		"requirement_text": str(objective.get("requirement_text", tracked_quest.get("objective_text", ""))),
		"grid": _dictionary_or_empty(object_data.get("anchor", {})).duplicate(true),
		"status": "located",
	}


func _unresolved_marker(tracked_quest: Dictionary, objective: Dictionary, reason: String) -> Dictionary:
	return {
		"kind": "quest_objective",
		"target_kind": "objective",
		"target_id": str(tracked_quest.get("quest_id", "")),
		"display_name": str(tracked_quest.get("title", tracked_quest.get("quest_id", ""))),
		"quest_id": str(tracked_quest.get("quest_id", "")),
		"quest_title": str(tracked_quest.get("title", "")),
		"objective_type": str(objective.get("type", tracked_quest.get("objective_type", ""))),
		"requirement_text": str(objective.get("requirement_text", tracked_quest.get("objective_text", ""))),
		"grid": {},
		"status": "unresolved",
		"reason": reason,
	}


func _container_has_item(container: Dictionary, item_id: String) -> bool:
	for entry in _array_or_empty(container.get("initial_inventory", container.get("inventory", []))):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if _normalize_content_id(entry_data.get("item_id", entry_data.get("id", ""))) == item_id and int(entry_data.get("count", 1)) > 0:
			return true
	return false


func _enemy_matches_marker(actor_data: Dictionary, enemy_type: String) -> bool:
	var definition_id := str(actor_data.get("definition_id", ""))
	var kind := str(actor_data.get("kind", ""))
	var side := str(actor_data.get("side", ""))
	if enemy_type == definition_id or enemy_type == kind or enemy_type == side:
		return true
	return enemy_type == "zombie" and definition_id.begins_with("zombie_")


func _object_display_name(object_data: Dictionary) -> String:
	var props: Dictionary = _dictionary_or_empty(object_data.get("props", {}))
	for key in ["pickup", "container", "interactive", "trigger"]:
		var value: Dictionary = _dictionary_or_empty(props.get(key, {}))
		var display_name := str(value.get("display_name", ""))
		if not display_name.is_empty():
			return display_name
	return str(object_data.get("object_id", ""))


func _normalize_content_id(value: Variant) -> String:
	if value == null:
		return ""
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	if typeof(value) == TYPE_INT:
		return str(value)
	var text := str(value).strip_edges()
	return "" if text == "<null>" else text


func _array_of_strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(str(item))
	result.sort()
	return result


func _string_lookup(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	for item in _array_or_empty(value):
		result[str(item)] = true
	return result


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
