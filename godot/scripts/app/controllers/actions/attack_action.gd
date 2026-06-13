extends RefCounted


static func create(actor_id: int, target_actor_id: int, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	return {
		"kind": "attack",
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"topology": topology.duplicate(true),
		"options": options.duplicate(true),
		"phase": "attack_action",
		"turn_phase": "player_action",
		"turn_cycles": 0,
	}


static func apply_failed(action: Dictionary, reason: String = "attack_failed") -> void:
	action["phase"] = "failed"
	action["turn_phase"] = "failed"
	action["blocked_reason"] = reason


static func apply_result(action: Dictionary, result: Dictionary) -> void:
	action["ap_before"] = float(result.get("ap_before", action.get("ap_before", 0.0)))
	action["ap_after"] = float(result.get("ap_remaining", action.get("ap_after", 0.0)))
	action["phase"] = "attack_presentation"
	action["turn_phase"] = "player_presentation"


static func finish_presentation(action: Dictionary, should_end_turn: bool) -> void:
	if should_end_turn:
		action["phase"] = "player_turn_end"
		action["turn_phase"] = "player_turn_end"
	else:
		action["phase"] = "finished"
		action["turn_phase"] = "player"
	if not _dictionary_or_empty(action.get("attack_phase", {})).is_empty():
		action["attack_completed"] = true


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
