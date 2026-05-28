extends RefCounted


func decide_intent(actor: RefCounted, context: Dictionary) -> Dictionary:
	var life: Dictionary = _dictionary_or_empty(actor.life)
	var settlement: Dictionary = _settlement_data(str(life.get("settlement_id", "")), _dictionary_or_empty(context.get("settlements", {})))
	if settlement.is_empty():
		return _idle_intent(actor, "settlement_missing")

	var minute_of_day: int = posmod(int(context.get("minute_of_day", 0)), 1440)
	var day: String = str(context.get("day", "monday"))
	var schedule_block: Dictionary = _active_schedule_block(str(life.get("schedule_profile_id", "")), day, minute_of_day, _dictionary_or_empty(context.get("ai", {})))
	if not schedule_block.is_empty():
		var route: Dictionary = _route_by_id(settlement, str(life.get("duty_route_id", "")))
		if not route.is_empty():
			return {
				"success": true,
				"actor_id": actor.actor_id,
				"intent": "follow_route",
				"settlement_id": str(settlement.get("id", "")),
				"route_id": str(route.get("id", "")),
				"route_grids": _route_grids(route, settlement),
				"schedule_label": str(schedule_block.get("label", "")),
			}
		var duty_object: Dictionary = _first_accessible_smart_object(life, settlement, _dictionary_or_empty(context.get("ai", {})))
		if not duty_object.is_empty():
			return {
				"success": true,
				"actor_id": actor.actor_id,
				"intent": "use_smart_object",
				"settlement_id": str(settlement.get("id", "")),
				"smart_object_id": str(duty_object.get("id", "")),
				"target_grid": _anchor_grid(settlement, str(duty_object.get("anchor_id", ""))),
				"schedule_label": str(schedule_block.get("label", "")),
			}

	var home_anchor: String = str(life.get("home_anchor", ""))
	if not home_anchor.is_empty():
		return {
			"success": true,
			"actor_id": actor.actor_id,
			"intent": "return_home",
			"settlement_id": str(settlement.get("id", "")),
			"anchor_id": home_anchor,
			"target_grid": _anchor_grid(settlement, home_anchor),
		}
	return _idle_intent(actor, "life_no_home_anchor")


func _active_schedule_block(profile_id: String, day: String, minute_of_day: int, ai_library: Dictionary) -> Dictionary:
	for profile in _ai_collection(ai_library, "schedule_templates"):
		var profile_data: Dictionary = _dictionary_or_empty(profile)
		if str(profile_data.get("id", "")) != profile_id:
			continue
		for block in _array_or_empty(profile_data.get("blocks", [])):
			var block_data: Dictionary = _dictionary_or_empty(block)
			if not _array_or_empty(block_data.get("days", [])).has(day):
				continue
			var start_minute: int = int(block_data.get("start_minute", 0))
			var end_minute: int = int(block_data.get("end_minute", 0))
			if _minute_in_range(minute_of_day, start_minute, end_minute):
				return block_data
	return {}


func _first_accessible_smart_object(life: Dictionary, settlement: Dictionary, ai_library: Dictionary) -> Dictionary:
	var access_profile_id: String = str(life.get("smart_object_access_profile_id", ""))
	for profile in _ai_collection(ai_library, "smart_object_access_profiles"):
		var profile_data: Dictionary = _dictionary_or_empty(profile)
		if str(profile_data.get("id", "")) != access_profile_id:
			continue
		for rule in _array_or_empty(profile_data.get("rules", [])):
			var rule_data: Dictionary = _dictionary_or_empty(rule)
			var smart_object: Dictionary = _matching_smart_object(settlement, rule_data)
			if not smart_object.is_empty():
				return smart_object
	return {}


func _matching_smart_object(settlement: Dictionary, rule: Dictionary) -> Dictionary:
	var required_kind: String = str(rule.get("kind", ""))
	var preferred_tags: Array = _array_or_empty(rule.get("preferred_tags", []))
	var fallback_to_any: bool = bool(rule.get("fallback_to_any", false))
	var fallback: Dictionary = {}
	for smart_object in _array_or_empty(settlement.get("smart_objects", [])):
		var object_data: Dictionary = _dictionary_or_empty(smart_object)
		if not required_kind.is_empty() and str(object_data.get("kind", "")) != required_kind:
			continue
		if fallback.is_empty():
			fallback = object_data
		if _tags_match(_array_or_empty(object_data.get("tags", [])), preferred_tags):
			return object_data
	return fallback if fallback_to_any else {}


func _tags_match(tags: Array, preferred_tags: Array) -> bool:
	if preferred_tags.is_empty():
		return true
	for tag in preferred_tags:
		if tags.has(str(tag)):
			return true
	return false


func _route_by_id(settlement: Dictionary, route_id: String) -> Dictionary:
	for route in _array_or_empty(settlement.get("routes", [])):
		var route_data: Dictionary = _dictionary_or_empty(route)
		if str(route_data.get("id", "")) == route_id:
			return route_data
	return {}


func _route_grids(route: Dictionary, settlement: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for anchor_id in _array_or_empty(route.get("anchors", [])):
		output.append(_anchor_grid(settlement, str(anchor_id)))
	return output


func _anchor_grid(settlement: Dictionary, anchor_id: String) -> Dictionary:
	for anchor in _array_or_empty(settlement.get("anchors", [])):
		var anchor_data: Dictionary = _dictionary_or_empty(anchor)
		if str(anchor_data.get("id", "")) == anchor_id:
			return _dictionary_or_empty(anchor_data.get("grid", {})).duplicate(true)
	return {}


func _settlement_data(settlement_id: String, settlement_library: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(settlement_library.get(settlement_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _ai_collection(ai_library: Dictionary, collection_name: String) -> Array:
	for record in ai_library.values():
		var record_data: Dictionary = _dictionary_or_empty(record)
		var data: Dictionary = _dictionary_or_empty(record_data.get("data", record_data))
		if data.has(collection_name):
			return _array_or_empty(data.get(collection_name, []))
	return []


func _minute_in_range(minute: int, start_minute: int, end_minute: int) -> bool:
	if start_minute <= end_minute:
		return minute >= start_minute and minute < end_minute
	return minute >= start_minute or minute < end_minute


func _idle_intent(actor: RefCounted, reason: String) -> Dictionary:
	return {
		"success": true,
		"actor_id": actor.actor_id if actor != null else 0,
		"intent": "idle",
		"reason": reason,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
