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
	var pending := not _dictionary_or_empty(result.get("pending_crafting", {})).is_empty()
	action["pending_crafting"] = _dictionary_or_empty(result.get("pending_crafting", {})).duplicate(true)
	if pending:
		action["phase"] = "player_turn_end"
		action["turn_phase"] = "player_turn_end"
		action["pending_kind"] = "crafting"
	else:
		action["phase"] = "finished"
		action["turn_phase"] = "player"
	action["craft_completed"] = not pending
	return {
		"pending": pending,
		"finish_reason": "craft_pending" if pending else "craft_finished",
	}


static func phase_source(action: Dictionary) -> String:
	return "confirm_queue" if bool(_dictionary_or_empty(action.get("options", {})).get("crafting_queue_active", false)) else "craft"


static func record_phase(action: Dictionary, result: Dictionary, source: String) -> void:
	var phase: Dictionary = phase_from_result(action, result, source)
	if phase.is_empty():
		return
	action["craft_phase"] = phase
	action["craft_completed"] = bool(phase.get("completed", false))


static func phase_snapshot(action: Dictionary, latest_result: Dictionary) -> Dictionary:
	if str(action.get("kind", "")) != "craft" and _dictionary_or_empty(action.get("craft_phase", {})).is_empty():
		return {}
	var phase: Dictionary = _dictionary_or_empty(action.get("craft_phase", {})).duplicate(true)
	if phase.is_empty():
		phase = phase_from_result(action, latest_result, str(action.get("kind", "craft")))
	if phase.is_empty():
		phase = {
			"source": str(action.get("kind", "craft")),
			"actor_id": int(action.get("actor_id", 0)),
			"recipe_id": str(action.get("recipe_id", "")),
			"count": int(action.get("count", 0)),
		}
	phase["phase"] = str(action.get("phase", ""))
	phase["turn_phase"] = str(action.get("turn_phase", ""))
	phase["pending"] = not _dictionary_or_empty(phase.get("pending_crafting", {})).is_empty() or str(phase.get("result_kind", "")) == "pending_crafting"
	phase["completed"] = bool(action.get("craft_completed", phase.get("completed", false))) or (str(action.get("phase", "")) == "finished" and not bool(phase.get("pending", false)))
	return phase


static func phase_from_result(action: Dictionary, result: Dictionary, source: String) -> Dictionary:
	if result.is_empty():
		return {}
	var direct: Dictionary = result
	var pending_result: Dictionary = _dictionary_or_empty(result.get("pending_result", {}))
	if not pending_result.is_empty():
		direct = pending_result
	var pending_crafting: Dictionary = _dictionary_or_empty(direct.get("pending_crafting", result.get("pending_crafting", {})))
	var resumed: Dictionary = _dictionary_or_empty(direct.get("resumed_pending_crafting", result.get("resumed_pending_crafting", {})))
	var recipe_id := str(direct.get("recipe_id", result.get("recipe_id", action.get("recipe_id", ""))))
	var count := int(direct.get("count", result.get("count", action.get("count", 0))))
	if recipe_id.is_empty() and not pending_crafting.is_empty():
		recipe_id = str(pending_crafting.get("recipe_id", ""))
		count = int(pending_crafting.get("count", count))
	if recipe_id.is_empty() and not resumed.is_empty():
		recipe_id = str(resumed.get("recipe_id", ""))
		count = int(resumed.get("count", count))
	if recipe_id.is_empty():
		return {}
	var required_ap := float(direct.get("required_ap", pending_crafting.get("required_ap", resumed.get("required_ap", 0.0))))
	if required_ap <= 0.0:
		required_ap = float(direct.get("ap_cost", result.get("ap_cost", 0.0)))
	var progress_ap := float(pending_crafting.get("progress_ap", required_ap if bool(direct.get("success", false)) and str(direct.get("kind", "")) != "pending_crafting" else 0.0))
	var remaining_ap := float(direct.get("remaining_ap", pending_crafting.get("remaining_ap", max(0.0, required_ap - progress_ap))))
	var command_data: Dictionary = _dictionary_or_empty(direct.get("command", result.get("command", pending_crafting.get("command", resumed.get("command", {})))))
	return {
		"source": source,
		"actor_id": int(direct.get("actor_id", result.get("actor_id", action.get("actor_id", 0)))),
		"recipe_id": recipe_id,
		"count": max(1, count),
		"result_kind": str(direct.get("kind", result.get("kind", ""))),
		"pending_crafting": pending_crafting.duplicate(true),
		"resumed_pending_crafting": resumed.duplicate(true),
		"required_ap": required_ap,
		"progress_ap": progress_ap,
		"remaining_ap": remaining_ap,
		"ap_cost": float(direct.get("ap_cost", result.get("ap_cost", 0.0))),
		"ap_after": float(direct.get("ap_remaining", result.get("ap_remaining", action.get("ap_after", 0.0)))),
		"queue_active": bool(command_data.get("crafting_queue_active", false)),
		"completed": bool(direct.get("success", false)) and pending_crafting.is_empty() and str(direct.get("kind", "")) != "pending_crafting",
	}


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
