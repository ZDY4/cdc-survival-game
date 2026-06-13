extends RefCounted


static func begin_world_turn(action: Dictionary, begin_result: Dictionary) -> void:
	action["phase"] = "npc_action"
	action["turn_phase"] = "npc_action"
	action["npc_queue"] = _array_or_empty(begin_result.get("npc_actor_ids", [])).duplicate(true)
	action["npc_index"] = 0
	action["npc_results"] = []
	action["presenting_npc_actor_id"] = 0
	action["npc_phase"] = {
		"phase": str(action.get("phase", "")),
		"turn_phase": str(action.get("turn_phase", "")),
		"npc_index": 0,
		"npc_count": _array_or_empty(action.get("npc_queue", [])).size(),
		"completed": false,
	}


static func apply_completed(action: Dictionary, phase: Dictionary) -> void:
	action["phase"] = "player_turn_start"
	action["turn_phase"] = "player_turn_start"
	action["presenting_npc_actor_id"] = 0
	action["npc_phase"] = phase.duplicate(true)


static func apply_result(action: Dictionary, npc_result: Dictionary, presentation: Dictionary, phase: Dictionary) -> void:
	var npc_results: Array = _array_or_empty(action.get("npc_results", []))
	npc_results.append(_dictionary_or_empty(npc_result.get("result", {})).duplicate(true))
	action["npc_results"] = npc_results
	action["npc_index"] = int(npc_result.get("npc_index", action.get("npc_index", 0))) + 1
	action["phase"] = "npc_action"
	action["turn_phase"] = "npc_action"
	action["presenting_npc_actor_id"] = 0
	action["npc_phase"] = phase.duplicate(true)
	if bool(presentation.get("success", false)) and bool(presentation.get("active", false)):
		action["phase"] = "npc_presentation"
		action["turn_phase"] = "npc_presentation"
		action["presenting_npc_actor_id"] = int(presentation.get("actor_id", 0))
		action["npc_phase"] = phase.duplicate(true)


static func finish_presentation(action: Dictionary) -> Dictionary:
	var npc_actor_id := int(action.get("presenting_npc_actor_id", 0))
	action["presenting_npc_actor_id"] = 0
	action["phase"] = "npc_action"
	action["turn_phase"] = "npc_action"
	var phase: Dictionary = _dictionary_or_empty(action.get("npc_phase", {})).duplicate(true)
	if not phase.is_empty():
		phase["phase"] = "npc_action"
		phase["turn_phase"] = "npc_action"
		phase["presentation_active"] = false
		phase["completed"] = true
		action["npc_phase"] = phase
	return {
		"npc_actor_id": npc_actor_id,
		"phase": phase,
	}


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
