extends RefCounted


static func create(actor_id: int, target: Dictionary, option_id: String, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	return {
		"kind": "interact",
		"actor_id": actor_id,
		"target": target.duplicate(true),
		"option_id": option_id,
		"topology": topology.duplicate(true),
		"options": options.duplicate(true),
		"phase": "interact_action",
		"turn_phase": "player_action",
		"turn_cycles": 0,
		"completed_after_presentation": false,
	}


static func apply_failed(action: Dictionary, reason: String = "interaction_failed") -> void:
	action["phase"] = "failed"
	action["turn_phase"] = "failed"
	action["blocked_reason"] = reason


static func redirect_to_attack(action: Dictionary, target_actor_id: int) -> void:
	action["target_actor_id"] = target_actor_id
	action["kind"] = "attack"
	action["phase"] = "attack_action"
	action["turn_phase"] = "player_action"


static func begin_approach(action: Dictionary, result: Dictionary) -> void:
	action["runner_keeps_active"] = true
	action["phase"] = "approach_move_step"
	action["turn_phase"] = "player_action"
	action["path"] = _array_or_empty(result.get("path", [])).duplicate(true)
	action["target_grid"] = _dictionary_or_empty(result.get("target_position", {})).duplicate(true)
	action["pending_kind"] = "interaction"
	action["step_index"] = 0


static func finish_immediate(action: Dictionary) -> void:
	action["runner_keeps_active"] = false
	action["phase"] = "finished"
	action["turn_phase"] = "player"


static func apply_approach_turn_wait(action: Dictionary, step: Dictionary) -> void:
	action["phase"] = "player_turn_end"
	action["turn_phase"] = "player_turn_end"
	action["pending_kind"] = "interaction"
	action["blocked_reason"] = str(step.get("reason", "ap_insufficient_movement_pending"))
	action["ap_after"] = float(step.get("ap_remaining", action.get("ap_after", 0.0)))


static func apply_approach_step(action: Dictionary, step: Dictionary) -> Dictionary:
	var has_visual_step := _has_visual_step(step)
	action["phase"] = "approach_move_step"
	action["turn_phase"] = "player_action"
	action["step_index"] = int(action.get("step_index", 0)) + 1
	action["current_grid"] = _dictionary_or_empty(step.get("from", {})).duplicate(true)
	action["next_grid"] = _dictionary_or_empty(step.get("to", {})).duplicate(true)
	action["ap_after"] = float(step.get("ap_remaining", 0.0))
	action["pending_kind"] = "interaction"
	action["completed_after_presentation"] = bool(step.get("completed", false)) and has_visual_step
	return {
		"has_visual_step": has_visual_step,
		"completed_after_presentation": bool(action.get("completed_after_presentation", false)),
	}


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
