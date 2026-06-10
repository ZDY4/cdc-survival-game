extends RefCounted


func take_item(container_id: String, item_id: String, count: int, stack_index: int, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if container_id.is_empty():
		return _missing_container("take_container", "", item_id, count, record_feedback)
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "take_container",
		"container_id": container_id,
		"item_id": item_id,
		"count": count,
		"stack_index": stack_index,
	})
	_record(record_feedback, result, "take_container", container_id, item_id, count)
	return _operation_result(result, ["inventory", "container", "journal"])


func take_money(container_id: String, count: int, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if container_id.is_empty():
		return _missing_container("take_container_money", "", "money", count, record_feedback)
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "take_container_money",
		"container_id": container_id,
		"count": count,
	})
	_record(record_feedback, result, "take_container_money", container_id, "money", count)
	return _operation_result(result, ["inventory", "container", "hud"])


func take_all(container_id: String, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if container_id.is_empty():
		return _missing_container("take_all_container", "", "", 0, record_feedback)
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "take_all_container",
		"container_id": container_id,
		"include_money": true,
	})
	_record(record_feedback, result, "take_all_container", container_id, str(result.get("item_id", "")), int(result.get("count", 0)))
	return _operation_result(result, ["inventory", "container", "journal", "hud"])


func store_item(container_id: String, item_id: String, count: int, stack_index: int, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if container_id.is_empty():
		return _missing_container("store_container", "", item_id, count, record_feedback)
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "store_container",
		"container_id": container_id,
		"item_id": item_id,
		"count": count,
		"stack_index": stack_index,
	})
	_record(record_feedback, result, "store_container", container_id, item_id, count)
	return _operation_result(result, ["inventory", "container"])


func store_all(container_id: String, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if container_id.is_empty():
		return _missing_container("store_all_container", "", "", 0, record_feedback)
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "store_all_container",
		"container_id": container_id,
	})
	_record(record_feedback, result, "store_all_container", container_id, str(result.get("item_id", "")), int(result.get("count", 0)))
	return _operation_result(result, ["inventory", "container"])


func transfer_item(source: String, container_id: String, item_id: String, count: int, stack_index: int, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	match source:
		"container":
			if str(item_id) == "money":
				return take_money(container_id, count, submit_inventory_action, record_feedback)
			return take_item(container_id, item_id, count, stack_index, submit_inventory_action, record_feedback)
		"player":
			return store_item(container_id, item_id, count, stack_index, submit_inventory_action, record_feedback)
		_:
			return _operation_result({"success": false, "reason": "unknown_container_transfer_source", "source": source}, [])


func transfer_all(source: String, container_id: String, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	match source:
		"container":
			return take_all(container_id, submit_inventory_action, record_feedback)
		"player":
			return store_all(container_id, submit_inventory_action, record_feedback)
		_:
			return _operation_result({"success": false, "reason": "unknown_container_transfer_source", "source": source}, [])


func close_container(simulation: RefCounted, reason: String) -> Dictionary:
	if simulation == null:
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(simulation.close_container(1, reason))
	return _operation_result(result, ["container", "hud"] if bool(result.get("success", false)) else [])


func _missing_container(action: String, container_id: String, item_id: String, count: int, record_feedback: Callable) -> Dictionary:
	var result := {"success": false, "reason": "active_container_missing"}
	_record(record_feedback, result, action, container_id, item_id, count)
	return _operation_result(result, [])


func _submit(submit_inventory_action: Callable, action: Dictionary) -> Dictionary:
	if not submit_inventory_action.is_valid():
		return {"success": false, "reason": "submit_inventory_action_missing"}
	return dictionary_or_empty(submit_inventory_action.call(action))


func _record(record_feedback: Callable, result: Dictionary, action: String, container_id: String, item_id: String, count: int) -> void:
	if record_feedback.is_valid():
		record_feedback.call(result, action, container_id, item_id, count)


func _operation_result(result: Dictionary, refresh_panels: Array) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh": refresh_panels.duplicate(true),
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
