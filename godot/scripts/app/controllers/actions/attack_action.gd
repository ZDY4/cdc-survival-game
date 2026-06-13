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


static func record_phase(action: Dictionary, result: Dictionary, source: String) -> void:
	var phase: Dictionary = phase_from_result(action, result, source)
	if phase.is_empty():
		return
	action["attack_phase"] = phase
	action["attack_source"] = source
	action["attack_actor_id"] = int(phase.get("actor_id", action.get("actor_id", 0)))
	action["attack_target_actor_id"] = int(phase.get("target_actor_id", action.get("target_actor_id", 0)))
	action["attack_completed"] = bool(phase.get("completed", false))


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


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
