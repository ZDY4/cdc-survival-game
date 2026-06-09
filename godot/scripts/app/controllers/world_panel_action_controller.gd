extends RefCounted


func turn_in_quest(quest_id: String, turn_in: Callable) -> Dictionary:
	if not turn_in.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(turn_in.call(quest_id))
	return _operation_result(result, ["inventory", "journal", "skills", "crafting"])


func enter_overworld_location(location_id: String, enter_location: Callable) -> Dictionary:
	if not enter_location.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing", "location_id": location_id}, [])
	var result: Dictionary = dictionary_or_empty(enter_location.call(location_id))
	if bool(result.get("success", false)):
		var operation: Dictionary = _operation_result(result, [])
		operation["rebuild_world"] = true
		return operation
	return _operation_result(result, ["hud", "map"])


func _operation_result(result: Dictionary, refresh_panels: Array) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh": refresh_panels.duplicate(true),
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
