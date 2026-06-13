extends RefCounted

const PIPELINE_STEP_IDS: Array[String] = [
	"validate",
	"preflight",
	"ammo",
	"durability",
	"consume",
	"apply_result",
	"presentation",
	"refresh",
]


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
		"attack_pipeline": [],
	}


static func apply_failed(action: Dictionary, reason: String = "attack_failed") -> void:
	action["phase"] = "failed"
	action["turn_phase"] = "failed"
	action["blocked_reason"] = reason


static func apply_result(action: Dictionary, result: Dictionary) -> void:
	action["ap_before"] = float(result.get("ap_before", action.get("ap_before", 0.0)))
	action["ap_after"] = float(result.get("ap_remaining", action.get("ap_after", 0.0)))
	action["attack_pipeline"] = _array_or_empty(result.get("attack_pipeline", [])).duplicate(true)
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


static func record_phase(action: Dictionary, result: Dictionary, source: String) -> void:
	var phase: Dictionary = phase_from_result(action, result, source)
	if phase.is_empty():
		return
	action["attack_phase"] = phase
	action["attack_source"] = source
	action["attack_actor_id"] = int(phase.get("actor_id", action.get("actor_id", 0)))
	action["attack_target_actor_id"] = int(phase.get("target_actor_id", action.get("target_actor_id", 0)))
	action["attack_completed"] = bool(phase.get("completed", false))
	action["attack_pipeline"] = _array_or_empty(result.get("attack_pipeline", action.get("attack_pipeline", []))).duplicate(true)


static func phase_snapshot(action: Dictionary, latest_result: Dictionary, view_snapshot: Dictionary = {}) -> Dictionary:
	if str(action.get("kind", "")) != "attack" and _dictionary_or_empty(action.get("attack_phase", {})).is_empty():
		return {}
	var phase: Dictionary = _dictionary_or_empty(action.get("attack_phase", {})).duplicate(true)
	if phase.is_empty():
		phase = phase_from_result(action, latest_result, str(action.get("attack_source", "player")))
	if phase.is_empty():
		phase = {
			"source": str(action.get("attack_source", "player")),
			"actor_id": int(action.get("actor_id", action.get("attack_actor_id", 0))),
			"target_actor_id": int(action.get("target_actor_id", action.get("attack_target_actor_id", 0))),
		}
	phase["phase"] = str(action.get("phase", ""))
	phase["turn_phase"] = str(action.get("turn_phase", ""))
	phase["presentation_active"] = bool(view_snapshot.get("active", false)) and str(view_snapshot.get("kind", "")) == "attack"
	var presentation_bound := str(view_snapshot.get("kind", "")) == "attack" and int(view_snapshot.get("actor_id", 0)) == int(phase.get("actor_id", 0))
	phase["presentation_actor_id"] = int(view_snapshot.get("actor_id", 0)) if presentation_bound else 0
	phase["presentation_node_instance_id"] = int(view_snapshot.get("node_instance_id", 0)) if presentation_bound else 0
	phase["attacker_node"] = _actor_node_phase_snapshot(view_snapshot, int(phase.get("actor_id", 0)))
	phase["target_node"] = _actor_node_phase_snapshot(view_snapshot, int(phase.get("target_actor_id", 0)))
	phase["completed"] = bool(action.get("attack_completed", phase.get("completed", false))) or str(action.get("phase", "")) == "finished"
	phase["phase_steps"] = _pipeline_steps_snapshot(action, latest_result, phase)
	phase["pipeline_phase"] = _current_pipeline_phase(action, phase)
	phase["rules_resolved"] = _rules_resolved(phase["phase_steps"])
	return phase


static func phase_from_result(action: Dictionary, result: Dictionary, source: String) -> Dictionary:
	if result.is_empty():
		return {}
	var actor_id := int(result.get("actor_id", action.get("actor_id", 0)))
	var target_actor_id := int(result.get("target_actor_id", action.get("target_actor_id", 0)))
	if actor_id <= 0 and target_actor_id <= 0:
		return {}
	var weapon_profile: Dictionary = _dictionary_or_empty(result.get("weapon_profile", {}))
	var damage := float(result.get("damage", 0.0))
	var hit_kind := str(result.get("hit_kind", ""))
	var hit := bool(result.get("hit", damage > 0.0 or hit_kind == "hit" or hit_kind == "crit"))
	return {
		"source": source,
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"target_grid": _dictionary_or_empty(result.get("target_grid", {})).duplicate(true),
		"attacker_grid": _dictionary_or_empty(result.get("attacker_grid", {})).duplicate(true),
		"range": int(result.get("range", weapon_profile.get("range", 0))),
		"weapon_item_id": str(weapon_profile.get("item_id", result.get("weapon_item_id", ""))),
		"hit": hit,
		"hit_kind": hit_kind,
		"damage": damage,
		"crit": bool(result.get("crit", hit_kind == "crit")),
		"defeated": bool(result.get("defeated", false)),
		"ap_before": float(result.get("ap_before", action.get("ap_before", 0.0))),
		"ap_after": float(result.get("ap_remaining", action.get("ap_after", 0.0))),
		"completed": bool(result.get("success", false)),
		"result_kind": str(result.get("kind", "attack")),
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


static func _pipeline_steps_snapshot(action: Dictionary, latest_result: Dictionary, phase: Dictionary) -> Array[Dictionary]:
	var recorded: Array = _array_or_empty(action.get("attack_pipeline", latest_result.get("attack_pipeline", [])))
	var by_id: Dictionary = {}
	for step_value in recorded:
		var step: Dictionary = _dictionary_or_empty(step_value)
		var step_id := str(step.get("id", ""))
		if step_id.is_empty():
			continue
		by_id[step_id] = step.duplicate(true)
	var output: Array[Dictionary] = []
	for step_id in PIPELINE_STEP_IDS:
		var step: Dictionary = _dictionary_or_empty(by_id.get(step_id, {})).duplicate(true)
		if step.is_empty():
			step = {"id": step_id, "success": false, "reason": ""}
		step["completed"] = _pipeline_step_completed(step_id, action, phase, step)
		if not step.has("success"):
			step["success"] = bool(step.get("completed", false))
		output.append(step)
	return output


static func _pipeline_step_completed(step_id: String, action: Dictionary, phase: Dictionary, recorded_step: Dictionary) -> bool:
	if not recorded_step.is_empty() and (bool(recorded_step.get("success", false)) or not str(recorded_step.get("reason", "")).is_empty()):
		return true
	match step_id:
		"presentation":
			return str(action.get("phase", "")) == "attack_presentation" or bool(action.get("attack_completed", false)) or str(action.get("phase", "")) == "finished"
		"refresh":
			return bool(action.get("attack_completed", false)) or str(action.get("phase", "")) == "finished"
	return bool(phase.get("completed", false))


static func _current_pipeline_phase(action: Dictionary, phase: Dictionary) -> String:
	if str(action.get("phase", "")) == "attack_presentation":
		return "presentation"
	if bool(action.get("attack_completed", false)) or str(action.get("phase", "")) == "finished":
		return "refresh"
	if bool(phase.get("completed", false)):
		return "apply_result"
	return "validate"


static func _rules_resolved(steps: Array) -> bool:
	for step_value in steps:
		var step: Dictionary = _dictionary_or_empty(step_value)
		var step_id := str(step.get("id", ""))
		if step_id == "presentation" or step_id == "refresh":
			continue
		if not bool(step.get("completed", false)):
			return false
	return true


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
