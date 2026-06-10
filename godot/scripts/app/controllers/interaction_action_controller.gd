extends RefCounted


func execute_primary(interaction_controller: RefCounted, blocker: Callable) -> Dictionary:
	if interaction_controller == null:
		return _operation_result({"success": false, "reason": "interaction_controller_missing"}, {}, false)
	var blocked: Dictionary = _blocked(blocker, "interact")
	if not blocked.is_empty():
		return _operation_result(blocked, {}, false)
	var executed_target: Dictionary = dictionary_or_empty(interaction_controller.selected_target).duplicate(true)
	var result: Dictionary = dictionary_or_empty(interaction_controller.execute_primary_interaction())
	return _operation_result(result, executed_target, true)


func execute_option(interaction_controller: RefCounted, option_id: String, blocker: Callable) -> Dictionary:
	if interaction_controller == null:
		return _operation_result({"success": false, "reason": "interaction_controller_missing"}, {}, false)
	var blocked: Dictionary = _blocked(blocker, "interact")
	if not blocked.is_empty():
		return _operation_result(blocked, {}, false)
	var executed_target: Dictionary = dictionary_or_empty(interaction_controller.selected_target).duplicate(true)
	var result: Dictionary = dictionary_or_empty(interaction_controller.execute_selected_option(option_id))
	return _operation_result(result, executed_target, true)


func _blocked(blocker: Callable, action: String) -> Dictionary:
	if not blocker.is_valid():
		return {}
	return dictionary_or_empty(blocker.call(action))


func _operation_result(result: Dictionary, executed_target: Dictionary, apply_result: bool) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"executed_target": executed_target.duplicate(true),
		"apply_result": apply_result,
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
