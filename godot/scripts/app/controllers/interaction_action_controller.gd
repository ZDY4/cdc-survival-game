extends RefCounted


func select_target(interaction_controller: RefCounted, target: Dictionary) -> Dictionary:
	if interaction_controller == null:
		return _operation_result({"success": false, "reason": "interaction_controller_missing"}, {}, false)
	var result: Dictionary = dictionary_or_empty(interaction_controller.select_target(target))
	return _selection_operation(result)


func select_node(interaction_controller: RefCounted, node: Node) -> Dictionary:
	if interaction_controller == null:
		return _operation_result({"success": false, "reason": "interaction_controller_missing"}, {}, false)
	var result: Dictionary = dictionary_or_empty(interaction_controller.select_node(node))
	return _selection_operation(result)


func clear_selection(interaction_controller: RefCounted, reason: String = "cleared", refresh_hud: bool = true) -> Dictionary:
	if interaction_controller == null:
		return _operation_result({"success": false, "reason": "interaction_controller_missing"}, {}, false)
	var result: Dictionary = dictionary_or_empty(interaction_controller.clear_selection(reason))
	return _selection_operation(result, refresh_hud)


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


func execute_move(interaction_controller: RefCounted, grid: Dictionary, blocker: Callable) -> Dictionary:
	if interaction_controller == null:
		return _operation_result({"success": false, "reason": "interaction_controller_missing"}, {}, false)
	var blocked: Dictionary = _blocked(blocker, "move")
	if not blocked.is_empty():
		return _operation_result(blocked, {}, false)
	var result: Dictionary = dictionary_or_empty(interaction_controller.execute_move_to_grid(grid))
	var operation: Dictionary = _operation_result(result, {}, true)
	operation["final_world_result"] = dictionary_or_empty(interaction_controller.world_result).duplicate(true)
	return operation


func select_grid(interaction_controller: RefCounted, grid: Dictionary) -> Dictionary:
	if interaction_controller == null:
		return _operation_result({"success": false, "reason": "interaction_controller_missing"}, {}, false)
	var result: Dictionary = dictionary_or_empty(interaction_controller.select_grid(grid))
	return _selection_operation(result)


func cancel_pending(interaction_controller: RefCounted, reason: String = "cancelled", auto_end_turn: bool = false) -> Dictionary:
	if interaction_controller == null:
		return {
			"result": {"success": false, "reason": "interaction_controller_missing"},
			"rebuild_world": false,
			"refresh_all_panels": false,
		}
	var result: Dictionary = dictionary_or_empty(interaction_controller.cancel_pending(reason, auto_end_turn))
	return {
		"result": result.duplicate(true),
		"rebuild_world": bool(result.get("had_pending", false)),
		"refresh_all_panels": true,
	}


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


func _selection_operation(result: Dictionary, refresh_hud: bool = true) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh_hud": refresh_hud,
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
