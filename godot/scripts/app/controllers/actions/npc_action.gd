extends RefCounted

const NpcActionPresenter = preload("res://scripts/app/controllers/actions/npc_action_presenter.gd")


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
		if str(phase.get("intent", "")) == "attack" and bool(phase.get("prepared", false)):
			action["presenting_npc_prepared_attack"] = _dictionary_or_empty(npc_result.get("result", {})).duplicate(true)


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


static func apply_resolved_attack(action: Dictionary, resolved: Dictionary) -> void:
	var phase: Dictionary = _dictionary_or_empty(action.get("npc_phase", {})).duplicate(true)
	if phase.is_empty():
		return
	phase["prepared"] = false
	phase["completed"] = bool(resolved.get("success", false))
	phase["result_kind"] = str(resolved.get("kind", "attack"))
	phase["damage"] = float(resolved.get("damage", 0.0))
	phase["hit_kind"] = str(resolved.get("hit_kind", ""))
	phase["defeated"] = bool(resolved.get("defeated", false))
	phase["resolved_after_presentation"] = bool(resolved.get("npc_attack_resolved_after_presentation", true))
	action["npc_phase"] = phase
	action["presenting_npc_prepared_attack"] = {}
	var npc_results: Array = _array_or_empty(action.get("npc_results", []))
	for index in range(npc_results.size() - 1, -1, -1):
		var existing: Dictionary = _dictionary_or_empty(npc_results[index])
		if int(existing.get("actor_id", 0)) == int(resolved.get("actor_id", 0)) and str(existing.get("intent", "")) == "attack":
			var updated := existing.duplicate(true)
			for key in resolved.keys():
				updated[key] = resolved[key]
			npc_results[index] = updated
			action["npc_results"] = npc_results
			return


static func phase_snapshot(action: Dictionary, latest_result: Dictionary, view_snapshot: Dictionary = {}) -> Dictionary:
	var phase: Dictionary = _dictionary_or_empty(action.get("npc_phase", {})).duplicate(true)
	if phase.is_empty():
		phase = phase_from_result(action, latest_result, _dictionary_or_empty(latest_result.get("presentation", {})), bool(latest_result.get("completed", false)))
	if phase.is_empty() and (str(action.get("phase", "")) == "npc_action" or str(action.get("phase", "")) == "npc_presentation"):
		phase = {
			"phase": str(action.get("phase", "")),
			"turn_phase": str(action.get("turn_phase", "")),
			"npc_index": int(action.get("npc_index", 0)),
			"npc_count": _array_or_empty(action.get("npc_queue", [])).size(),
			"presenting_actor_id": int(action.get("presenting_npc_actor_id", 0)),
			"completed": false,
		}
	if phase.is_empty():
		return {}
	phase["phase"] = str(action.get("phase", phase.get("phase", "")))
	phase["turn_phase"] = str(action.get("turn_phase", phase.get("turn_phase", "")))
	phase["npc_index"] = int(action.get("npc_index", phase.get("npc_index", 0)))
	phase["npc_count"] = _array_or_empty(action.get("npc_queue", [])).size()
	phase["presenting_actor_id"] = int(action.get("presenting_npc_actor_id", phase.get("presenting_actor_id", 0)))
	phase["presentation_active"] = str(action.get("phase", "")) == "npc_presentation" and (int(phase.get("presenting_actor_id", 0)) > 0 or bool(view_snapshot.get("active", false)))
	phase["presenting_node"] = _actor_node_phase_snapshot(view_snapshot, int(phase.get("presenting_actor_id", 0)))
	phase["actor_node"] = _actor_node_phase_snapshot(view_snapshot, int(phase.get("actor_id", 0)))
	phase["target_node"] = _actor_node_phase_snapshot(view_snapshot, int(phase.get("target_actor_id", 0)))
	if str(action.get("phase", "")) == "player_turn_start":
		phase["completed"] = true
	return phase


static func phase_from_result(action: Dictionary, npc_result: Dictionary, presentation: Dictionary = {}, completed: bool = false) -> Dictionary:
	if npc_result.is_empty() and presentation.is_empty():
		return {}
	var result: Dictionary = _dictionary_or_empty(npc_result.get("result", {}))
	var attack: Dictionary = NpcActionPresenter.attack_from_result(npc_result)
	var step: Dictionary = NpcActionPresenter.move_step_from_result(npc_result)
	var intent := str(presentation.get("npc_intent", result.get("intent", ""))).strip_edges()
	if intent.is_empty() and not attack.is_empty():
		intent = "attack"
	if intent.is_empty() and not step.is_empty():
		intent = "move"
	if intent.is_empty() and completed:
		intent = "complete"
	var actor_id := int(presentation.get("actor_id", result.get("actor_id", npc_result.get("actor_id", step.get("actor_id", attack.get("actor_id", 0))))))
	var target_actor_id := int(attack.get("target_actor_id", result.get("target_actor_id", 0)))
	return {
		"phase": str(action.get("phase", "")),
		"turn_phase": str(action.get("turn_phase", "")),
		"npc_index": int(npc_result.get("npc_index", action.get("npc_index", 0))),
		"npc_count": _array_or_empty(action.get("npc_queue", [])).size(),
		"presenting_actor_id": int(presentation.get("actor_id", action.get("presenting_npc_actor_id", 0))),
		"intent": intent,
		"result_kind": str(result.get("kind", npc_result.get("kind", ""))),
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"from_grid": _dictionary_or_empty(step.get("from", {})).duplicate(true),
		"to_grid": _dictionary_or_empty(step.get("to", {})).duplicate(true),
		"presentation_active": bool(presentation.get("active", false)),
		"prepared": bool(result.get("attack_prepared", false)),
		"prepared_attack": result.duplicate(true) if bool(result.get("attack_prepared", false)) else {},
		"completed": completed or bool(npc_result.get("completed", false)),
	}


static func _actor_node_phase_snapshot(view_snapshot: Dictionary, actor_id: int) -> Dictionary:
	if actor_id <= 0:
		return {}
	var actor_nodes: Dictionary = _dictionary_or_empty(view_snapshot.get("actor_nodes", {}))
	var node: Dictionary = _dictionary_or_empty(actor_nodes.get(str(actor_id), {}))
	if node.is_empty():
		return {}
	return {
		"actor_id": actor_id,
		"node_path": str(node.get("node_path", "")),
		"node_instance_id": int(node.get("node_instance_id", 0)),
		"action_runner_active": bool(node.get("action_runner_active", false)),
		"action_runner_step_active": bool(node.get("action_runner_step_active", false)),
		"action_runner_kind": str(node.get("action_runner_kind", "")),
	}


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
