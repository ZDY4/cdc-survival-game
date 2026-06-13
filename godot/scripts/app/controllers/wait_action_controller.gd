extends RefCounted


func press_space_action(has_dialogue: bool, observe_mode: bool, advance_dialogue: Callable, toggle_observe: Callable, cancel_pending: Callable, simulation: RefCounted, topology: Dictionary) -> Dictionary:
	if has_dialogue:
		if not advance_dialogue.is_valid():
			return _operation_result({"success": false, "reason": "dialogue_action_missing"}, [])
		return _operation_result(dictionary_or_empty(advance_dialogue.call()), [])
	if observe_mode:
		if not toggle_observe.is_valid():
			return _operation_result({"success": false, "reason": "observe_action_missing"}, [])
		return _operation_result(dictionary_or_empty(toggle_observe.call()), [])
	if cancel_pending.is_valid():
		var pending_result: Dictionary = dictionary_or_empty(cancel_pending.call("keyboard", true))
		if bool(pending_result.get("had_pending", false)):
			return _operation_result(pending_result, [])
	return submit_wait(simulation, topology)


func submit_wait(simulation: RefCounted, topology: Dictionary) -> Dictionary:
	return _operation_result(_validate_wait_context(simulation, topology), [])


func auto_tick_wait(simulation: RefCounted, has_dialogue: bool, ui_blocked: bool, snapshot: Dictionary, topology: Dictionary) -> Dictionary:
	if simulation == null:
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	if has_dialogue or ui_blocked:
		return _operation_result({"success": false, "reason": "ui_blocked"}, [])
	if not dictionary_or_empty(snapshot.get("pending_movement", {})).is_empty() or not dictionary_or_empty(snapshot.get("pending_interaction", {})).is_empty():
		return _operation_result({"success": false, "reason": "pending_blocked"}, [])
	return _operation_result(_validate_wait_context(simulation, topology), [])


func _validate_wait_context(simulation: RefCounted, topology: Dictionary) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if topology.is_empty():
		return {"success": false, "reason": "wait_topology_missing"}
	return {"success": true, "kind": "wait_ready"}


func _operation_result(result: Dictionary, refresh_steps: Array) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh": refresh_steps.duplicate(true),
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
