extends RefCounted


static func create(actor_id: int, target_grid: Dictionary, topology: Dictionary, begin_result: Dictionary) -> Dictionary:
	return {
		"kind": "move",
		"actor_id": actor_id,
		"target_grid": target_grid.duplicate(true),
		"topology": topology.duplicate(true),
		"path": _array_or_empty(begin_result.get("path", [])).duplicate(true),
		"step_index": 0,
		"phase": "move_step",
		"ap_before": float(begin_result.get("ap", 0.0)),
		"completed_after_presentation": false,
		"turn_cycles": 0,
	}


static func apply_failed(action: Dictionary, reason: String = "failed") -> void:
	action["phase"] = "failed"
	action["turn_phase"] = "failed"
	action["blocked_reason"] = reason


static func apply_turn_wait(action: Dictionary, step: Dictionary) -> void:
	action["phase"] = "player_turn_end"
	action["turn_phase"] = "player_turn_end"
	action["pending_kind"] = "movement"
	action["blocked_reason"] = str(step.get("reason", "ap_insufficient_movement_pending"))
	action["ap_after"] = float(step.get("ap_remaining", action.get("ap_after", 0.0)))


static func apply_step(action: Dictionary, step: Dictionary) -> Dictionary:
	var has_visual_step := _has_visual_step(step)
	action["phase"] = "move_step"
	action["turn_phase"] = "player_action"
	action["step_index"] = int(action.get("step_index", 0)) + 1
	action["current_grid"] = _dictionary_or_empty(step.get("from", {})).duplicate(true)
	action["next_grid"] = _dictionary_or_empty(step.get("to", {})).duplicate(true)
	action["ap_after"] = float(step.get("ap_remaining", 0.0))
	if bool(step.get("pending", false)):
		action["pending_kind"] = "movement"
	action["completed_after_presentation"] = bool(step.get("completed", false)) and has_visual_step
	return {
		"has_visual_step": has_visual_step,
		"completed_after_presentation": bool(action.get("completed_after_presentation", false)),
	}


static func finish_without_visual(action: Dictionary, reason: String = "finished") -> void:
	action["phase"] = "finished"
	action["turn_phase"] = "player"
	action["finish_reason"] = reason


static func _has_visual_step(step: Dictionary) -> bool:
	return not _dictionary_or_empty(step.get("from", {})).is_empty() and not _dictionary_or_empty(step.get("to", {})).is_empty()


static func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
