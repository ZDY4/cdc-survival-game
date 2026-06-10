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


func execution_followup(result: Dictionary, executed_target: Dictionary) -> Dictionary:
	var output := {
		"reset_container_feedback": interaction_result_opens_container(result),
		"trade_target": {},
		"reset_trade_feedback": false,
		"stage_panel": interaction_result_stage_panel(result),
	}
	var trade_target: Dictionary = trade_target_after_interaction(result, executed_target)
	if not trade_target.is_empty():
		output["trade_target"] = trade_target
		output["reset_trade_feedback"] = true
	return output


func trade_target_after_interaction(result: Dictionary, executed_target: Dictionary) -> Dictionary:
	if not bool(result.get("success", false)):
		return {}
	var interaction_result: Dictionary = dictionary_or_empty(result.get("result", {}))
	var prompt: Dictionary = dictionary_or_empty(interaction_result.get("prompt", {}))
	var option_kind := ""
	var options: Array = prompt.get("options", [])
	if not options.is_empty():
		var option: Dictionary = dictionary_or_empty(options[0])
		option_kind = str(option.get("kind", ""))
	if option_kind == "talk" and executed_target.get("target_type", "") == "actor":
		return executed_target.duplicate(true)
	return {}


func interaction_result_opens_container(result: Dictionary) -> bool:
	if result.has("container"):
		return true
	var nested_result: Dictionary = dictionary_or_empty(result.get("result", {}))
	return nested_result.has("container")


func interaction_result_stage_panel(result: Dictionary) -> String:
	if not bool(result.get("success", false)):
		return ""
	var panel_id := str(result.get("open_panel", "")).strip_edges()
	if not panel_id.is_empty():
		return panel_id
	var prompt: Dictionary = dictionary_or_empty(result.get("prompt", {}))
	var option_id := str(prompt.get("primary_option_id", ""))
	for option in array_or_empty(prompt.get("options", [])):
		var option_data: Dictionary = dictionary_or_empty(option)
		if option_id.is_empty() or str(option_data.get("id", "")) == option_id:
			if str(option_data.get("kind", "")) == "open_crafting":
				return "crafting"
	return ""


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


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
