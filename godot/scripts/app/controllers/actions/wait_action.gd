extends RefCounted


static func create(actor_id: int, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	return {
		"kind": "wait",
		"actor_id": actor_id,
		"topology": topology.duplicate(true),
		"options": options.duplicate(true),
		"phase": "wait_action",
		"turn_phase": "player_action",
		"turn_cycles": 0,
	}


static func apply_failed(action: Dictionary, reason: String = "wait_failed") -> void:
	action["phase"] = "failed"
	action["turn_phase"] = "failed"
	action["blocked_reason"] = reason


static func apply_result(action: Dictionary, result: Dictionary, pending_kind: String) -> void:
	action["ap_before"] = float(result.get("ap_before", action.get("ap_before", 0.0)))
	action["ap_after"] = float(result.get("ap_before", action.get("ap_after", 0.0)))
	action["phase"] = "player_turn_end"
	action["turn_phase"] = "player_turn_end"
	action["pending_kind"] = pending_kind
