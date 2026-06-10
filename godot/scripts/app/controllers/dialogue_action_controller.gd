extends RefCounted


func choose_option(simulation: RefCounted, option_ref: Variant, dialogue_library: Dictionary) -> Dictionary:
	if simulation == null:
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(simulation.advance_dialogue(1, option_ref, dialogue_library))
	return _operation_result(result, ["dialogue", "inventory", "trade", "journal", "skills", "crafting"])


func continue_without_choice(simulation: RefCounted, dialogue_snapshot: Dictionary, dialogue_library: Dictionary) -> Dictionary:
	if simulation == null:
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	if not bool(dialogue_snapshot.get("active", false)):
		return _operation_result({"success": false, "reason": "dialogue_session_missing"}, [])
	if not array_or_empty(dialogue_snapshot.get("options", [])).is_empty():
		return _operation_result({
			"success": false,
			"reason": "dialogue_choice_required",
			"active_dialogue": true,
		}, [])
	var result: Dictionary = dictionary_or_empty(simulation.advance_dialogue_without_choice(1, dialogue_library))
	return _operation_result(result, ["dialogue", "inventory", "trade", "journal", "skills", "crafting", "hud"])


func close_dialogue(simulation: RefCounted, reason: String) -> Dictionary:
	if simulation == null:
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(simulation.close_dialogue(1, reason))
	return _operation_result(result, ["dialogue", "hud"] if bool(result.get("success", false)) else [])


func _operation_result(result: Dictionary, refresh_panels: Array) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh": refresh_panels.duplicate(true),
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
