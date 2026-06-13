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


static func record_phase(action: Dictionary, result: Dictionary) -> void:
	if str(action.get("kind", "")) != "interact":
		return
	var phase: Dictionary = phase_from_result(action, result)
	if phase.is_empty():
		return
	action["interaction_phase"] = phase
	action["interaction_action_kind"] = str(phase.get("option_kind", ""))
	action["interaction_visual_kind"] = str(phase.get("visual_kind", ""))
	action["interaction_target_id"] = str(phase.get("target_id", ""))
	if bool(phase.get("completed", false)):
		action["interaction_completed"] = true


static func phase_snapshot(action: Dictionary, latest_result: Dictionary, view_snapshot: Dictionary = {}) -> Dictionary:
	if str(action.get("kind", "")) != "interact":
		return {}
	var phase: Dictionary = _dictionary_or_empty(action.get("interaction_phase", {})).duplicate(true)
	if phase.is_empty():
		phase = phase_from_result(action, latest_result)
	if phase.is_empty():
		phase = phase_from_target(action)
	phase["phase"] = str(action.get("phase", ""))
	phase["turn_phase"] = str(action.get("turn_phase", ""))
	phase["approach_active"] = str(action.get("phase", "")) == "approach_move_step"
	phase["approach_node"] = _actor_node_phase_snapshot(view_snapshot, int(action.get("actor_id", 0))) if bool(phase.get("approach_active", false)) else {}
	phase["approach_from_grid"] = _dictionary_or_empty(action.get("current_grid", {})).duplicate(true)
	phase["approach_to_grid"] = _dictionary_or_empty(action.get("next_grid", {})).duplicate(true)
	phase["approach_step_index"] = int(action.get("step_index", 0))
	phase["approach_total_steps"] = max(0, _array_or_empty(action.get("path", [])).size() - 1)
	phase["pending_kind"] = str(action.get("pending_kind", ""))
	phase["completed"] = bool(action.get("interaction_completed", phase.get("completed", false))) or str(action.get("phase", "")) == "finished"
	return phase


static func phase_from_result(action: Dictionary, result: Dictionary) -> Dictionary:
	if result.is_empty():
		return {}
	var direct: Dictionary = result
	if not _dictionary_or_empty(result.get("pending_result", {})).is_empty():
		direct = _dictionary_or_empty(result.get("pending_result", {}))
	var prompt: Dictionary = _dictionary_or_empty(direct.get("prompt", result.get("prompt", {})))
	var option: Dictionary = interaction_option_from_prompt(prompt, str(action.get("option_id", "")))
	var target: Dictionary = _dictionary_or_empty(prompt.get("target", action.get("target", {})))
	var option_kind := str(direct.get("option_kind", option.get("kind", direct.get("kind", "")))).strip_edges()
	if option_kind.is_empty() and direct.has("consumed_target"):
		option_kind = "pickup"
	if option_kind.is_empty() and direct.has("container"):
		option_kind = "open_container"
	if option_kind.is_empty() and direct.has("dialogue_id"):
		option_kind = "talk"
	if option_kind.is_empty() and bool(direct.get("door_toggled", false)):
		option_kind = "door_toggle"
	if option_kind.is_empty() and direct.has("context_snapshot"):
		option_kind = "scene_transition"
	if option_kind.is_empty():
		option_kind = str(option.get("kind", "interact"))
	var target_id := str(direct.get("target_id", option.get("target_id", target.get("target_id", target.get("actor_id", "")))))
	return {
		"option_id": str(direct.get("option_id", option.get("id", action.get("option_id", "")))),
		"option_kind": option_kind,
		"visual_kind": interaction_visual_kind(option_kind, direct),
		"target_id": target_id,
		"target_type": str(target.get("target_type", "")),
		"target_name": str(direct.get("target_name", prompt.get("target_name", target.get("display_name", target_id)))),
		"target_grid": interaction_target_grid(target),
		"open_panel": str(direct.get("open_panel", "")),
		"completed": interaction_result_completed(direct),
		"result_kind": str(direct.get("kind", "")),
	}


static func phase_from_target(action: Dictionary) -> Dictionary:
	var target: Dictionary = _dictionary_or_empty(action.get("target", {}))
	if target.is_empty():
		return {}
	return {
		"option_id": str(action.get("option_id", "")),
		"option_kind": "",
		"visual_kind": "",
		"target_id": str(target.get("target_id", target.get("actor_id", ""))),
		"target_type": str(target.get("target_type", "")),
		"target_name": str(target.get("target_name", target.get("display_name", ""))),
		"target_grid": interaction_target_grid(target),
		"open_panel": "",
		"completed": false,
		"result_kind": "",
	}


static func interaction_option_from_prompt(prompt: Dictionary, option_id: String) -> Dictionary:
	for value in _array_or_empty(prompt.get("options", [])):
		var option: Dictionary = _dictionary_or_empty(value)
		if option_id.is_empty() or str(option.get("id", "")) == option_id:
			return option
	return {}


static func interaction_visual_kind(option_kind: String, result: Dictionary) -> String:
	match option_kind:
		"pickup":
			return "item_pickup"
		"open_container":
			return "container_open"
		"door_toggle":
			return "door_toggle"
		"talk":
			return "dialogue_start"
		"open_trade":
			return "trade_open"
		"open_crafting":
			return "crafting_station"
		"enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor", "scene_transition":
			return "scene_transition"
		"wait":
			return "wait"
		"attack":
			return "attack"
	if result.has("context_snapshot"):
		return "scene_transition"
	return "interaction"


static func interaction_result_completed(result: Dictionary) -> bool:
	if result.is_empty() or not bool(result.get("success", false)):
		return false
	return bool(result.get("consumed_target", false)) \
		or result.has("dialogue_id") \
		or result.has("container") \
		or result.has("context_snapshot") \
		or bool(result.get("door_toggled", false)) \
		or bool(result.get("waited", false)) \
		or bool(result.get("interaction_completed", false)) \
		or not str(result.get("open_panel", "")).is_empty()


static func interaction_target_grid(target: Dictionary) -> Dictionary:
	for key in ["grid_position", "anchor", "grid"]:
		var grid: Dictionary = _dictionary_or_empty(target.get(key, {}))
		if not grid.is_empty():
			return grid.duplicate(true)
	return {}


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
