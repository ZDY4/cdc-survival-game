extends RefCounted


func equip_item(item_id: String, slot_id: String, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if not submit_inventory_action.is_valid():
		var missing_result := {"success": false, "reason": "simulation_missing", "item_id": item_id, "slot_id": slot_id}
		_record(record_feedback, missing_result, "equip", slot_id, item_id)
		return _operation_result(missing_result, ["character"])
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "equip",
		"item_id": item_id,
		"slot_id": slot_id,
	})
	_record(record_feedback, result, "equip", slot_id, item_id)
	if bool(result.get("success", false)):
		return _operation_result(result, [], true)
	return _operation_result(result, ["inventory", "character"])


func unequip_slot(slot_id: String, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if not submit_inventory_action.is_valid():
		var missing_result := {"success": false, "reason": "simulation_missing", "slot_id": slot_id}
		_record(record_feedback, missing_result, "unequip", slot_id, "")
		return _operation_result(missing_result, ["character"])
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "unequip",
		"slot_id": slot_id,
	})
	_record(record_feedback, result, "unequip", slot_id, str(result.get("item_id", "")))
	if bool(result.get("success", false)):
		return _operation_result(result, [], true)
	return _operation_result(result, ["inventory", "character"])


func reload_slot(slot_id: String, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if not submit_inventory_action.is_valid():
		var missing_result := {"success": false, "reason": "simulation_missing", "slot_id": slot_id}
		_record(record_feedback, missing_result, "reload", slot_id, "")
		return _operation_result(missing_result, ["character"])
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "reload_equipped",
		"slot_id": slot_id,
	})
	_record(record_feedback, result, "reload", slot_id, str(result.get("item_id", "")))
	return _operation_result(result, ["hud", "inventory", "character"])


func allocate_attribute(attribute: String, allocate_attribute_point: Callable) -> Dictionary:
	if not allocate_attribute_point.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(allocate_attribute_point.call(attribute))
	return _operation_result(result, ["hud", "character", "skills"])


func _submit(submit_inventory_action: Callable, action: Dictionary) -> Dictionary:
	return dictionary_or_empty(submit_inventory_action.call(action))


func _record(record_feedback: Callable, result: Dictionary, action: String, slot_id: String, item_id: String) -> void:
	if record_feedback.is_valid():
		record_feedback.call(result, action, slot_id, item_id)


func _operation_result(result: Dictionary, refresh_panels: Array, rebuild_world: bool = false) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh": refresh_panels.duplicate(true),
		"rebuild_world": rebuild_world,
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
