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


static func record_phase(action: Dictionary, result: Dictionary, pending_kind: String) -> void:
	if str(action.get("kind", "")) != "wait":
		return
	var phase: Dictionary = phase_from_result(action, result, pending_kind)
	if phase.is_empty():
		return
	action["wait_phase"] = phase
	action["wait_completed"] = bool(phase.get("completed", false))


static func phase_snapshot(action: Dictionary, latest_result: Dictionary, pending_kind: String) -> Dictionary:
	if str(action.get("kind", "")) != "wait" and _dictionary_or_empty(action.get("wait_phase", {})).is_empty():
		return {}
	var phase: Dictionary = _dictionary_or_empty(action.get("wait_phase", {})).duplicate(true)
	if phase.is_empty():
		phase = phase_from_result(action, latest_result, pending_kind)
	if phase.is_empty():
		phase = {
			"actor_id": int(action.get("actor_id", 0)),
			"reason": str(_dictionary_or_empty(action.get("options", {})).get("reason", "wait")),
		}
	phase["phase"] = str(action.get("phase", ""))
	phase["turn_phase"] = str(action.get("turn_phase", ""))
	phase["completed"] = bool(action.get("wait_completed", phase.get("completed", false))) or str(action.get("phase", "")) == "finished"
	return phase


static func phase_from_result(action: Dictionary, result: Dictionary, pending_kind: String) -> Dictionary:
	if result.is_empty():
		return {}
	return {
		"actor_id": int(result.get("actor_id", action.get("actor_id", 0))),
		"reason": str(result.get("reason", _dictionary_or_empty(action.get("options", {})).get("reason", "wait"))),
		"waited": bool(result.get("waited", false)),
		"ap_before": float(result.get("ap_before", action.get("ap_before", 0.0))),
		"pending_kind": pending_kind,
		"resumed_pending": not _dictionary_or_empty(result.get("pending_result", {})).is_empty(),
		"completed": bool(result.get("success", false)),
		"result_kind": str(result.get("kind", "wait")),
	}


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
