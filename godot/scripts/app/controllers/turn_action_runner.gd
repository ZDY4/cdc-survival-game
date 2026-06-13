extends RefCounted

var simulation: RefCounted
var actor_view: RefCounted
var host: Node
var world_result: Dictionary = {}
var active := false
var action: Dictionary = {}
var latest_result: Dictionary = {}


func configure(p_simulation: RefCounted, p_actor_view: RefCounted, p_host: Node, p_world_result: Dictionary) -> void:
	simulation = p_simulation
	actor_view = p_actor_view
	host = p_host
	world_result = p_world_result


func request_move(actor_id: int, target_grid: Dictionary, topology: Dictionary) -> Dictionary:
	if active:
		return {"success": false, "reason": "turn_action_runner_active", "snapshot": snapshot()}
	if simulation == null or not simulation.has_method("begin_move"):
		return {"success": false, "reason": "simulation_step_move_missing"}
	var begin: Dictionary = _dictionary_or_empty(simulation.call("begin_move", actor_id, target_grid, topology))
	if not bool(begin.get("success", false)):
		latest_result = begin.duplicate(true)
		return begin
	action = {
		"kind": "move",
		"actor_id": actor_id,
		"target_grid": target_grid.duplicate(true),
		"topology": topology.duplicate(true),
		"path": _array_or_empty(begin.get("path", [])).duplicate(true),
		"step_index": 0,
		"phase": "move_step",
		"ap_before": float(begin.get("ap", 0.0)),
		"completed_after_presentation": false,
	}
	active = true
	latest_result = begin.duplicate(true)
	var step_result := _advance_move_step()
	if not bool(step_result.get("success", false)):
		active = false
	return step_result


func process() -> void:
	if not active:
		return
	if actor_view != null and actor_view.has_method("is_active") and bool(actor_view.call("is_active")):
		return
	if str(action.get("kind", "")) == "move":
		if bool(action.get("completed_after_presentation", false)):
			active = false
			action["phase"] = "finished"
			_clear_actor_action_state(int(action.get("actor_id", 0)), "finished")
			_sync_host_after_step(latest_result)
			return
		_advance_move_step()


func finish_active(reason: String = "fast_forward") -> Dictionary:
	if actor_view != null and actor_view.has_method("finish_active_actor_presentation"):
		actor_view.call("finish_active_actor_presentation", int(action.get("actor_id", 0)))
	active = false
	action["phase"] = "finished"
	latest_result["finish_reason"] = reason
	var output := snapshot()
	_sync_host_after_step(output)
	return output


func snapshot() -> Dictionary:
	var view_snapshot: Dictionary = _dictionary_or_empty(actor_view.call("snapshot")) if actor_view != null and actor_view.has_method("snapshot") else {}
	return {
		"active": active,
		"phase": str(action.get("phase", "idle" if not active else "")),
		"action_kind": str(action.get("kind", "")),
		"actor_id": int(action.get("actor_id", 0)),
		"target": _dictionary_or_empty(action.get("target_grid", {})).duplicate(true),
		"path": _array_or_empty(action.get("path", [])).duplicate(true),
		"step_index": int(action.get("step_index", 0)),
		"current_grid": _dictionary_or_empty(action.get("current_grid", {})).duplicate(true),
		"next_grid": _dictionary_or_empty(action.get("next_grid", {})).duplicate(true),
		"ap_before": float(action.get("ap_before", 0.0)),
		"ap_after": float(action.get("ap_after", 0.0)),
		"turn_phase": str(action.get("turn_phase", "")),
		"pending_kind": str(action.get("pending_kind", "")),
		"blocked_reason": str(latest_result.get("reason", "")) if not bool(latest_result.get("success", true)) else "",
		"presentation_active": bool(view_snapshot.get("active", false)),
		"actor_view": view_snapshot,
		"queued_actions": [],
		"latest_result": latest_result.duplicate(true),
	}


func _advance_move_step() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var topology: Dictionary = _dictionary_or_empty(action.get("topology", {}))
	var step: Dictionary = _dictionary_or_empty(simulation.call("step_move", actor_id, topology))
	latest_result = step.duplicate(true)
	if not bool(step.get("success", false)):
		active = false
		action["phase"] = "failed"
		_clear_actor_action_state(actor_id, "failed")
		_sync_host_after_step(step)
		return step
	var has_visual_step := not _dictionary_or_empty(step.get("from", {})).is_empty() and not _dictionary_or_empty(step.get("to", {})).is_empty()
	action["phase"] = "move_step"
	action["step_index"] = int(action.get("step_index", 0)) + 1
	action["current_grid"] = _dictionary_or_empty(step.get("from", {})).duplicate(true)
	action["next_grid"] = _dictionary_or_empty(step.get("to", {})).duplicate(true)
	action["ap_after"] = float(step.get("ap_remaining", 0.0))
	if bool(step.get("pending", false)):
		action["pending_kind"] = "movement"
	action["completed_after_presentation"] = bool(step.get("completed", false)) and has_visual_step
	var presentation: Dictionary = {}
	if has_visual_step and actor_view != null and actor_view.has_method("move_actor_step"):
		presentation = _dictionary_or_empty(actor_view.call("move_actor_step", host, actor_id, _dictionary_or_empty(step.get("from", {})), _dictionary_or_empty(step.get("to", {}))))
	step["presentation"] = presentation
	if bool(step.get("completed", false)) and not has_visual_step:
		active = false
		action["phase"] = "finished"
		_clear_actor_action_state(actor_id, str(step.get("reason", "finished")))
	_sync_host_after_step(step)
	return step


func _sync_host_after_step(step_result: Dictionary) -> void:
	if host != null and host.has_method("sync_after_turn_action_step"):
		host.call("sync_after_turn_action_step", step_result.duplicate(true), snapshot())


func _clear_actor_action_state(actor_id: int, reason: String) -> void:
	if actor_view != null and actor_view.has_method("clear_actor_action_state"):
		actor_view.call("clear_actor_action_state", actor_id, reason)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
