extends RefCounted


func drop_item(item_id: String, count: int, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if not submit_inventory_action.is_valid():
		return _missing_simulation("drop", item_id, count, record_feedback)
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "drop",
		"item_id": item_id,
		"count": count,
	})
	_record(record_feedback, result, "drop", item_id, count)
	if bool(result.get("success", false)):
		return _operation_result(result, [], true)
	return _operation_result(result, ["inventory"])


func deconstruct_item(item_id: String, count: int, crafting_context: Dictionary, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if not submit_inventory_action.is_valid():
		return _missing_simulation("deconstruct", item_id, count, record_feedback)
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "deconstruct",
		"item_id": item_id,
		"count": count,
		"crafting_context": crafting_context.duplicate(true),
	})
	_record(record_feedback, result, "deconstruct", item_id, count)
	return _operation_result(result, ["inventory", "crafting"])


func split_stack(item_id: String, count: int, source_stack_index: int, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if not submit_inventory_action.is_valid():
		return _missing_simulation("split_stack", item_id, count, record_feedback)
	var command := {
		"action": "split_stack",
		"item_id": item_id,
		"count": count,
	}
	if source_stack_index > 0:
		command["source_stack_index"] = source_stack_index
	var result: Dictionary = _submit(submit_inventory_action, command)
	_record(record_feedback, result, "split_stack", item_id, count)
	return _operation_result(result, ["inventory"])


func reorder_item(item_id: String, target_index: int, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if not submit_inventory_action.is_valid():
		var missing_result := {"success": false, "reason": "simulation_missing", "item_id": item_id, "target_index": target_index}
		_record(record_feedback, missing_result, "reorder_inventory", item_id, 1)
		return _operation_result(missing_result, ["inventory"])
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "reorder_inventory",
		"item_id": item_id,
		"target_index": target_index,
	})
	_record(record_feedback, result, "reorder_inventory", item_id, 1)
	return _operation_result(result, ["inventory"])


func use_item(item_id: String, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if not submit_inventory_action.is_valid():
		return _missing_simulation("use_item", item_id, 1, record_feedback)
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "use_item",
		"item_id": item_id,
	})
	_record(record_feedback, result, "use_item", item_id, 1)
	return _operation_result(result, ["hud", "inventory", "character"])


func _missing_simulation(action: String, item_id: String, count: int, record_feedback: Callable) -> Dictionary:
	var result := {"success": false, "reason": "simulation_missing", "item_id": item_id, "count": count}
	_record(record_feedback, result, action, item_id, count)
	return _operation_result(result, ["inventory"])


func _submit(submit_inventory_action: Callable, action: Dictionary) -> Dictionary:
	return dictionary_or_empty(submit_inventory_action.call(action))


func _record(record_feedback: Callable, result: Dictionary, action: String, item_id: String, count: int) -> void:
	if record_feedback.is_valid():
		record_feedback.call(result, action, item_id, count)


func _operation_result(result: Dictionary, refresh_panels: Array, rebuild_world: bool = false) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh": refresh_panels.duplicate(true),
		"rebuild_world": rebuild_world,
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
