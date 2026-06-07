extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")


func supports_domain(domain: String) -> bool:
	return ["settlements", "overworld"].has(domain)


func validate_record(domain: String, id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	match domain:
		"settlements":
			_validate_settlement(id_value, record, registry, issues)
		"overworld":
			_validate_overworld(id_value, record, registry, issues)


func _validate_settlement(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data := _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("id", ""), id_value, "$.id")
	var map_id := ContentRegistry.normalize_content_id(data.get("map_id", ""))
	var map_data := _map_data(map_id, registry)
	if map_data.is_empty():
		issues.append(_issue("error", "$.map_id", "unknown_map", "unknown map id %s" % map_id))
		return

	var bounds := _map_bounds(map_data)
	var anchor_ids := {}
	var anchors := _array_or_empty(data.get("anchors", []))
	if anchors.is_empty():
		issues.append(_issue("error", "$.anchors", "missing_anchors", "settlement must define at least one anchor"))
	for i in range(anchors.size()):
		var anchor := _dictionary_or_empty(anchors[i])
		var field := "$.anchors[%d]" % i
		var anchor_id := str(anchor.get("id", ""))
		if anchor_id.is_empty():
			issues.append(_issue("error", field.path_join("id"), "missing_anchor_id", "settlement anchor id is required"))
		elif anchor_ids.has(anchor_id):
			issues.append(_issue("error", field.path_join("id"), "duplicate_anchor_id", "duplicate settlement anchor id %s" % anchor_id))
		anchor_ids[anchor_id] = true
		_validate_grid(_dictionary_or_empty(anchor.get("grid", {})), field.path_join("grid"), bounds, issues)

	for i in range(_array_or_empty(data.get("routes", [])).size()):
		var route := _dictionary_or_empty(data["routes"][i])
		var field := "$.routes[%d]" % i
		_expect_non_empty_string(issues, route, "id", field.path_join("id"))
		var route_anchors := _array_or_empty(route.get("anchors", []))
		if route_anchors.is_empty():
			issues.append(_issue("error", field.path_join("anchors"), "missing_route_anchors", "settlement route must reference anchors"))
		for anchor_index in range(route_anchors.size()):
			_validate_anchor_ref(route_anchors[anchor_index], field.path_join("anchors[%d]" % anchor_index), anchor_ids, issues)

	var smart_object_ids := {}
	for i in range(_array_or_empty(data.get("smart_objects", [])).size()):
		var smart_object := _dictionary_or_empty(data["smart_objects"][i])
		var field := "$.smart_objects[%d]" % i
		var smart_object_id := str(smart_object.get("id", ""))
		if smart_object_id.is_empty():
			issues.append(_issue("error", field.path_join("id"), "missing_smart_object_id", "settlement smart object id is required"))
		elif smart_object_ids.has(smart_object_id):
			issues.append(_issue("error", field.path_join("id"), "duplicate_smart_object_id", "duplicate settlement smart object id %s" % smart_object_id))
		smart_object_ids[smart_object_id] = true
		_expect_non_empty_string(issues, smart_object, "kind", field.path_join("kind"))
		_validate_anchor_ref(smart_object.get("anchor_id", null), field.path_join("anchor_id"), anchor_ids, issues)
		_expect_number_at_least(issues, smart_object, "capacity", field.path_join("capacity"), 1.0)

	var service_rules := _dictionary_or_empty(data.get("service_rules", {}))
	if not service_rules.is_empty():
		if service_rules.has("min_guard_on_duty"):
			_expect_number_at_least(issues, service_rules, "min_guard_on_duty", "$.service_rules.min_guard_on_duty", 0.0)
		for i in range(_array_or_empty(service_rules.get("meal_windows", [])).size()):
			_validate_minute_window(_dictionary_or_empty(service_rules["meal_windows"][i]), "$.service_rules.meal_windows[%d]" % i, issues)
		if service_rules.has("quiet_hours"):
			_validate_minute_window(_dictionary_or_empty(service_rules.get("quiet_hours", {})), "$.service_rules.quiet_hours", issues)


func _validate_overworld(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data := _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("id", ""), id_value, "$.id")
	var size := _dictionary_or_empty(data.get("size", {}))
	var width := int(size.get("width", 0))
	var height := int(size.get("height", 0))
	if width <= 0:
		issues.append(_issue("error", "$.size.width", "invalid_size", "overworld width must be greater than 0"))
	if height <= 0:
		issues.append(_issue("error", "$.size.height", "invalid_size", "overworld height must be greater than 0"))

	var locations := _array_or_empty(data.get("locations", []))
	var location_ids := {}
	if locations.is_empty():
		issues.append(_issue("error", "$.locations", "missing_locations", "overworld must define at least one location"))
	for i in range(locations.size()):
		var location := _dictionary_or_empty(locations[i])
		var field := "$.locations[%d]" % i
		var location_id := str(location.get("id", ""))
		if location_id.is_empty():
			issues.append(_issue("error", field.path_join("id"), "missing_location_id", "overworld location id is required"))
		elif location_ids.has(location_id):
			issues.append(_issue("error", field.path_join("id"), "duplicate_location_id", "duplicate overworld location id %s" % location_id))
		location_ids[location_id] = true
		_validate_location(location, field, width, height, registry, issues)

	for i in range(locations.size()):
		var location := _dictionary_or_empty(locations[i])
		var parent_id := ContentRegistry.normalize_content_id(location.get("parent_outdoor_location_id", ""))
		if not parent_id.is_empty() and parent_id != "<null>" and not location_ids.has(parent_id):
			issues.append(_issue("error", "$.locations[%d].parent_outdoor_location_id" % i, "unknown_location", "unknown parent location id %s" % parent_id))

	var travel_rules := _dictionary_or_empty(data.get("travel_rules", {}))
	if not travel_rules.is_empty():
		_validate_ref(travel_rules.get("food_item_id", null), "$.travel_rules.food_item_id", "items", "unknown_item", registry, issues)
		if travel_rules.has("night_minutes_multiplier"):
			_expect_number_at_least(issues, travel_rules, "night_minutes_multiplier", "$.travel_rules.night_minutes_multiplier", 0.0)
		if travel_rules.has("risk_multiplier"):
			_expect_number_at_least(issues, travel_rules, "risk_multiplier", "$.travel_rules.risk_multiplier", 0.0)

	var world_tile_index := _world_tile_index(registry)
	for i in range(_array_or_empty(data.get("cells", [])).size()):
		var cell := _dictionary_or_empty(data["cells"][i])
		var visual := _dictionary_or_empty(cell.get("visual", {}))
		if visual.is_empty():
			continue
		var surface_set_id := ContentRegistry.normalize_content_id(visual.get("surface_set_id", ""))
		if not surface_set_id.is_empty() and not _dictionary_or_empty(world_tile_index.get("surface_sets", {})).has(surface_set_id):
			issues.append(_issue("error", "$.cells[%d].visual.surface_set_id" % i, "unknown_surface_set", "unknown surface set id %s" % surface_set_id))


func _validate_location(location: Dictionary, field: String, width: int, height: int, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	_expect_non_empty_string(issues, location, "name", field.path_join("name"))
	_expect_non_empty_string(issues, location, "kind", field.path_join("kind"))
	var map_id := ContentRegistry.normalize_content_id(location.get("map_id", ""))
	var map_data := _map_data(map_id, registry)
	if map_data.is_empty():
		issues.append(_issue("error", field.path_join("map_id"), "unknown_map", "unknown map id %s" % map_id))
	else:
		_validate_entry_point(location.get("entry_point_id", null), field.path_join("entry_point_id"), map_data, issues)
		var return_entry := ContentRegistry.normalize_content_id(location.get("return_entry_point_id", ""))
		if not return_entry.is_empty() and return_entry != "<null>":
			_validate_entry_point(return_entry, field.path_join("return_entry_point_id"), map_data, issues)
	var cell := _dictionary_or_empty(location.get("overworld_cell", {}))
	_validate_overworld_cell(cell, field.path_join("overworld_cell"), width, height, issues)
	if location.has("danger_level"):
		_expect_number_at_least(issues, location, "danger_level", field.path_join("danger_level"), 0.0)


func _map_data(map_id: String, registry: ContentRegistry) -> Dictionary:
	var record := _dictionary_or_empty(registry.get_library("maps").get(map_id, {}))
	return _dictionary_or_empty(record.get("data", {}))


func _map_bounds(map_data: Dictionary) -> Dictionary:
	var size := _dictionary_or_empty(map_data.get("size", {}))
	var level_ids := {}
	for level in _array_or_empty(map_data.get("levels", [])):
		var level_data := _dictionary_or_empty(level)
		level_ids[ContentRegistry.normalize_content_id(level_data.get("y", ""))] = true
	return {
		"width": int(size.get("width", 0)),
		"height": int(size.get("height", 0)),
		"level_ids": level_ids,
	}


func _world_tile_index(registry: ContentRegistry) -> Dictionary:
	var output := {
		"surface_sets": {},
	}
	for record in registry.get_library("world_tiles").values():
		var data := _dictionary_or_empty(_dictionary_or_empty(record).get("data", {}))
		for surface_set in _array_or_empty(data.get("surface_sets", [])):
			var surface_set_id := ContentRegistry.normalize_content_id(_dictionary_or_empty(surface_set).get("id", ""))
			if not surface_set_id.is_empty():
				output["surface_sets"][surface_set_id] = true
	return output


func _validate_grid(grid: Dictionary, field: String, bounds: Dictionary, issues: Array[Dictionary]) -> void:
	if grid.is_empty():
		issues.append(_issue("error", field, "missing_grid", "grid coordinate is required"))
		return
	var x := int(grid.get("x", -1))
	var y := int(grid.get("y", 0))
	var z := int(grid.get("z", -1))
	var width := int(bounds.get("width", 0))
	var height := int(bounds.get("height", 0))
	var level_ids := _dictionary_or_empty(bounds.get("level_ids", {}))
	if x < 0 or x >= width:
		issues.append(_issue("error", field.path_join("x"), "grid_out_of_bounds", "x %d outside width %d" % [x, width]))
	if z < 0 or z >= height:
		issues.append(_issue("error", field.path_join("z"), "grid_out_of_bounds", "z %d outside height %d" % [z, height]))
	if not level_ids.has(ContentRegistry.normalize_content_id(y)):
		issues.append(_issue("error", field.path_join("y"), "unknown_level", "y %d does not match a map level" % y))


func _validate_overworld_cell(cell: Dictionary, field: String, width: int, height: int, issues: Array[Dictionary]) -> void:
	if cell.is_empty():
		issues.append(_issue("error", field, "missing_overworld_cell", "overworld location cell is required"))
		return
	var x := int(cell.get("x", -1))
	var z := int(cell.get("z", -1))
	if x < 0 or x >= width:
		issues.append(_issue("error", field.path_join("x"), "cell_out_of_bounds", "x %d outside overworld width %d" % [x, width]))
	if z < 0 or z >= height:
		issues.append(_issue("error", field.path_join("z"), "cell_out_of_bounds", "z %d outside overworld height %d" % [z, height]))


func _validate_minute_window(window: Dictionary, field: String, issues: Array[Dictionary]) -> void:
	if window.is_empty():
		issues.append(_issue("error", field, "missing_minute_window", "minute window is required"))
		return
	if not window.has("start_minute"):
		issues.append(_issue("error", field.path_join("start_minute"), "missing_minute", "start_minute is required"))
	if not window.has("end_minute"):
		issues.append(_issue("error", field.path_join("end_minute"), "missing_minute", "end_minute is required"))
	if not window.has("start_minute") or not window.has("end_minute"):
		return
	var start_minute := int(window.get("start_minute", 0))
	var end_minute := int(window.get("end_minute", 0))
	_validate_day_minute(start_minute, field.path_join("start_minute"), true, issues)
	_validate_day_minute(end_minute, field.path_join("end_minute"), false, issues)
	if end_minute <= start_minute:
		issues.append(_issue("error", field, "invalid_minute_window", "end_minute must be greater than start_minute"))


func _validate_day_minute(value: int, field: String, allow_zero: bool, issues: Array[Dictionary]) -> void:
	var minimum := 0 if allow_zero else 1
	if value < minimum or value > 1440:
		issues.append(_issue("error", field, "minute_out_of_range", "minute %d must be between %d and 1440" % [value, minimum]))


func _validate_entry_point(entry_point_id: Variant, field: String, map_data: Dictionary, issues: Array[Dictionary]) -> void:
	var normalized := ContentRegistry.normalize_content_id(entry_point_id)
	if normalized.is_empty() or normalized == "<null>":
		issues.append(_issue("error", field, "missing_entry_point", "map entry point id is required"))
		return
	for entry_point in _array_or_empty(map_data.get("entry_points", [])):
		if ContentRegistry.normalize_content_id(_dictionary_or_empty(entry_point).get("id", "")) == normalized:
			return
	issues.append(_issue("error", field, "unknown_entry_point", "unknown map entry point id %s" % normalized))


func _validate_anchor_ref(anchor_id: Variant, field: String, anchor_ids: Dictionary, issues: Array[Dictionary]) -> void:
	var normalized := ContentRegistry.normalize_content_id(anchor_id)
	if normalized.is_empty() or not anchor_ids.has(normalized):
		issues.append(_issue("error", field, "unknown_anchor", "unknown settlement anchor id %s" % normalized))


func _validate_ref(value: Variant, field: String, domain: String, code: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var normalized := ContentRegistry.normalize_content_id(value)
	if normalized.is_empty() or normalized == "<null>" or not registry.has_id(domain, normalized):
		issues.append(_issue("error", field, code, "unknown %s id %s" % [domain, normalized]))


func _expect_id_matches(issues: Array[Dictionary], value: Variant, expected: String, field: String) -> void:
	if ContentRegistry.normalize_content_id(value) != expected:
		issues.append(_issue("error", field, "id_mismatch", "record id must match requested id %s" % expected))


func _expect_non_empty_string(issues: Array[Dictionary], data: Dictionary, key: String, field: String) -> void:
	if str(data.get(key, "")).strip_edges().is_empty():
		issues.append(_issue("error", field, "missing_text", "%s must be a non-empty string" % key))


func _expect_number_at_least(issues: Array[Dictionary], data: Dictionary, key: String, field: String, minimum: float) -> void:
	if not data.has(key):
		issues.append(_issue("error", field, "missing_number", "%s is required" % key))
		return
	if float(data.get(key, 0.0)) < minimum:
		issues.append(_issue("error", field, "number_too_small", "%s must be >= %.2f" % [key, minimum]))


func _issue(severity: String, field: String, code: String, message: String) -> Dictionary:
	return {
		"severity": severity,
		"field": field,
		"code": code,
		"message": message,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
