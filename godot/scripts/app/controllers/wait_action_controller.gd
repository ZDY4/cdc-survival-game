extends RefCounted


func submit_wait(simulation: RefCounted, topology: Dictionary) -> Dictionary:
	if simulation == null:
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(simulation.submit_player_command(_wait_command(topology)))
	return _operation_result(result, ["runtime", "all_panels"] if bool(result.get("success", false)) else ["all_panels"])


func auto_tick_wait(simulation: RefCounted, has_dialogue: bool, ui_blocked: bool, snapshot: Dictionary, topology: Dictionary) -> Dictionary:
	if simulation == null:
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	if has_dialogue or ui_blocked:
		return _operation_result({"success": false, "reason": "ui_blocked"}, [])
	if not dictionary_or_empty(snapshot.get("pending_movement", {})).is_empty() or not dictionary_or_empty(snapshot.get("pending_interaction", {})).is_empty():
		return _operation_result({"success": false, "reason": "pending_blocked"}, [])
	var result: Dictionary = dictionary_or_empty(simulation.submit_player_command(_wait_command(topology)))
	return _operation_result(result, ["runtime", "all_panels"] if bool(result.get("success", false)) else [])


func _wait_command(topology: Dictionary) -> Dictionary:
	return {
		"kind": "wait",
		"actor_id": 1,
		"topology": topology.duplicate(true),
	}


func _operation_result(result: Dictionary, refresh_steps: Array) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh": refresh_steps.duplicate(true),
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
