extends RefCounted


func learn_skill(skill_id: String, submit_command: Callable, skill_library: Dictionary) -> Dictionary:
	if not submit_command.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(submit_command.call({
		"kind": "learn_skill",
		"actor_id": 1,
		"skill_id": skill_id,
		"skill_library": skill_library,
	}))
	return _operation_result(result, ["character", "skills"])


func bind_skill_to_hotbar(slot_id: String, skill_id: String, submit_command: Callable, skill_library: Dictionary) -> Dictionary:
	if not submit_command.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(submit_command.call({
		"kind": "bind_hotbar",
		"actor_id": 1,
		"slot_id": slot_id,
		"skill_id": skill_id,
		"skill_library": skill_library,
	}))
	return _operation_result(result, ["hud", "skills"])


func bind_item_to_hotbar(slot_id: String, item_id: String, submit_command: Callable, item_library: Dictionary, effect_library: Dictionary) -> Dictionary:
	if not submit_command.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(submit_command.call({
		"kind": "bind_hotbar",
		"actor_id": 1,
		"slot_id": slot_id,
		"hotbar_kind": "item",
		"item_id": item_id,
		"item_library": item_library,
		"effect_library": effect_library,
	}))
	return _operation_result(result, ["hud", "inventory"])


func set_hotbar_group(group_id: String, set_group: Callable) -> Dictionary:
	if not set_group.is_valid():
		return _operation_result({"success": false, "reason": "hotbar_group_unsupported"}, [])
	return _operation_result(dictionary_or_empty(set_group.call(group_id)), ["hud", "skills", "inventory"])


func set_hotbar_group_label(group_id: String, label: String, set_label: Callable) -> Dictionary:
	if not set_label.is_valid():
		return _operation_result({"success": false, "reason": "hotbar_group_label_unsupported"}, [])
	return _operation_result(dictionary_or_empty(set_label.call(group_id, label)), ["hud", "skills"])


func cycle_hotbar_group(direction: int, cycle_group: Callable) -> Dictionary:
	if not cycle_group.is_valid():
		return _operation_result({"success": false, "reason": "hotbar_group_unsupported"}, [])
	return _operation_result(dictionary_or_empty(cycle_group.call(direction)), ["hud", "skills", "inventory"])


func _operation_result(result: Dictionary, refresh_panels: Array) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh": refresh_panels.duplicate(true),
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
