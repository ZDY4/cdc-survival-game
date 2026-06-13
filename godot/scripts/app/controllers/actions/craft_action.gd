extends RefCounted


static func create(actor_id: int, command: Dictionary, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	var craft_command: Dictionary = command.duplicate(true)
	craft_command["kind"] = "craft"
	craft_command["actor_id"] = actor_id
	craft_command["topology"] = topology.duplicate(true)
	return {
		"kind": "craft",
		"actor_id": actor_id,
		"recipe_id": str(craft_command.get("recipe_id", "")),
		"count": max(1, int(craft_command.get("count", 1))),
		"command": craft_command.duplicate(true),
		"topology": topology.duplicate(true),
		"options": options.duplicate(true),
		"phase": "craft_action",
		"turn_phase": "player_action",
		"turn_cycles": 0,
	}


static func apply_failed(action: Dictionary, reason: String = "craft_failed") -> void:
	action["phase"] = "failed"
	action["turn_phase"] = "failed"
	action["blocked_reason"] = reason


static func apply_result(action: Dictionary, result: Dictionary, pending_kind: String) -> Dictionary:
	var turn_policy: Dictionary = _dictionary_or_empty(result.get("turn_policy", {}))
	action["ap_before"] = float(result.get("ap_before", action.get("ap_before", 0.0)))
	action["ap_after"] = float(result.get("ap_remaining", turn_policy.get("ap_after_action", action.get("ap_after", 0.0))))
	action["pending_kind"] = pending_kind
	action["phase"] = "finished"
	action["turn_phase"] = "player"
	var pending := not _dictionary_or_empty(result.get("pending_crafting", {})).is_empty()
	action["craft_completed"] = not pending
	return {
		"pending": pending,
		"finish_reason": "craft_pending" if pending else "craft_finished",
	}


static func phase_source(action: Dictionary) -> String:
	return "confirm_queue" if bool(_dictionary_or_empty(action.get("options", {})).get("crafting_queue_active", false)) else "craft"


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
