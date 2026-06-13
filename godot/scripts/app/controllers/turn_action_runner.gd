extends RefCounted

const AUTO_TURN_ADVANCE_LIMIT := 8

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
		"turn_cycles": 0,
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
			action["turn_phase"] = "player"
			_clear_actor_action_state(int(action.get("actor_id", 0)), "finished")
			_sync_host_after_step(latest_result)
			return
		match str(action.get("phase", "")):
			"player_turn_end":
				_begin_world_turn_phase()
			"npc_action":
				_advance_npc_turn_phase()
			"npc_presentation":
				_finish_npc_presentation_phase()
			"player_turn_start":
				_finish_world_turn_phase()
			"pending_resume":
				_advance_move_step()
			_:
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
		"turn_cycles": int(action.get("turn_cycles", 0)),
		"auto_turn_limit": AUTO_TURN_ADVANCE_LIMIT,
		"npc_queue": _array_or_empty(action.get("npc_queue", [])).duplicate(true),
		"npc_index": int(action.get("npc_index", 0)),
		"npc_results": _array_or_empty(action.get("npc_results", [])).duplicate(true),
		"presenting_npc_actor_id": int(action.get("presenting_npc_actor_id", 0)),
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
		action["turn_phase"] = "failed"
		_clear_actor_action_state(actor_id, "failed")
		_sync_host_after_step(step)
		return step
	if _step_waits_for_player_turn(step):
		action["phase"] = "player_turn_end"
		action["turn_phase"] = "player_turn_end"
		action["pending_kind"] = "movement"
		action["blocked_reason"] = str(step.get("reason", "ap_insufficient_movement_pending"))
		action["ap_after"] = float(step.get("ap_remaining", action.get("ap_after", 0.0)))
		_sync_host_after_step(step)
		return step
	var has_visual_step := not _dictionary_or_empty(step.get("from", {})).is_empty() and not _dictionary_or_empty(step.get("to", {})).is_empty()
	action["phase"] = "move_step"
	action["turn_phase"] = "player_action"
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
		action["turn_phase"] = "player"
		_clear_actor_action_state(actor_id, str(step.get("reason", "finished")))
	_sync_host_after_step(step)
	return step


func _begin_world_turn_phase() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var cycles := int(action.get("turn_cycles", 0))
	if cycles >= AUTO_TURN_ADVANCE_LIMIT:
		active = false
		action["phase"] = "blocked"
		action["turn_phase"] = "blocked"
		_clear_actor_action_state(actor_id, "auto_turn_limit_reached")
		latest_result = {
			"success": false,
			"reason": "auto_turn_limit_reached",
			"actor_id": actor_id,
			"limit": AUTO_TURN_ADVANCE_LIMIT,
			"turn_cycles": cycles,
		}
		_sync_host_after_step(latest_result)
		return latest_result
	if simulation == null or not simulation.has_method("begin_world_turn_for_runner"):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		latest_result = {"success": false, "reason": "runner_world_turn_api_missing", "actor_id": actor_id}
		_clear_actor_action_state(actor_id, "runner_turn_api_missing")
		_sync_host_after_step(latest_result)
		return latest_result
	action["turn_cycles"] = cycles + 1
	action["phase"] = "npc_action"
	action["turn_phase"] = "npc_action"
	var topology: Dictionary = _dictionary_or_empty(action.get("topology", {}))
	var begin_result: Dictionary = _dictionary_or_empty(simulation.call("begin_world_turn_for_runner", actor_id, topology, "pending_movement"))
	latest_result = begin_result.duplicate(true)
	if not bool(begin_result.get("success", false)):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		_clear_actor_action_state(actor_id, str(begin_result.get("reason", "turn_failed")))
		_sync_host_after_step(begin_result)
		return begin_result
	action["npc_queue"] = _array_or_empty(begin_result.get("npc_actor_ids", [])).duplicate(true)
	action["npc_index"] = 0
	action["npc_results"] = []
	_sync_host_after_step(begin_result)
	return begin_result


func _advance_npc_turn_phase() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	if simulation == null or not simulation.has_method("advance_next_npc_turn_for_runner"):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		latest_result = {"success": false, "reason": "runner_npc_turn_api_missing", "actor_id": actor_id}
		_clear_actor_action_state(actor_id, "runner_npc_turn_api_missing")
		_sync_host_after_step(latest_result)
		return latest_result
	var npc_result: Dictionary = _dictionary_or_empty(simulation.call("advance_next_npc_turn_for_runner"))
	latest_result = npc_result.duplicate(true)
	if not bool(npc_result.get("success", false)):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		_clear_actor_action_state(actor_id, str(npc_result.get("reason", "npc_turn_failed")))
		_sync_host_after_step(npc_result)
		return npc_result
	if bool(npc_result.get("completed", false)):
		action["phase"] = "player_turn_start"
		action["turn_phase"] = "player_turn_start"
	else:
		var npc_results: Array = _array_or_empty(action.get("npc_results", []))
		npc_results.append(_dictionary_or_empty(npc_result.get("result", {})).duplicate(true))
		action["npc_results"] = npc_results
		action["npc_index"] = int(npc_result.get("npc_index", action.get("npc_index", 0))) + 1
		action["turn_phase"] = "npc_action"
		var presentation: Dictionary = _present_npc_turn_result(npc_result)
		npc_result["presentation"] = presentation
		if bool(presentation.get("success", false)) and bool(presentation.get("active", false)):
			action["phase"] = "npc_presentation"
			action["turn_phase"] = "npc_presentation"
			action["presenting_npc_actor_id"] = int(presentation.get("actor_id", 0))
	_sync_host_after_step(npc_result)
	return npc_result


func _finish_npc_presentation_phase() -> Dictionary:
	var npc_actor_id := int(action.get("presenting_npc_actor_id", 0))
	_clear_actor_action_state(npc_actor_id, "npc_presentation_finished")
	action["presenting_npc_actor_id"] = 0
	action["phase"] = "npc_action"
	action["turn_phase"] = "npc_action"
	var result := {
		"success": true,
		"kind": "npc_presentation_finished",
		"actor_id": npc_actor_id,
	}
	latest_result = result.duplicate(true)
	_sync_host_after_step(result)
	return result


func _finish_world_turn_phase() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	if simulation == null or not simulation.has_method("finish_world_turn_for_runner"):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		latest_result = {"success": false, "reason": "runner_world_finish_api_missing", "actor_id": actor_id}
		_clear_actor_action_state(actor_id, "runner_world_finish_api_missing")
		_sync_host_after_step(latest_result)
		return latest_result
	var finish_result: Dictionary = _dictionary_or_empty(simulation.call("finish_world_turn_for_runner", actor_id, "pending_movement"))
	latest_result = finish_result.duplicate(true)
	if not bool(finish_result.get("success", false)):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		_clear_actor_action_state(actor_id, str(finish_result.get("reason", "world_turn_finish_failed")))
		_sync_host_after_step(finish_result)
		return finish_result
	action["ap_after"] = float(finish_result.get("ap_after", action.get("ap_after", 0.0)))
	action["phase"] = "pending_resume"
	action["turn_phase"] = "pending_resume"
	action["pending_kind"] = "movement"
	_sync_host_after_step(finish_result)
	return finish_result


func _sync_host_after_step(step_result: Dictionary) -> void:
	if host != null and host.has_method("sync_after_turn_action_step"):
		host.call("sync_after_turn_action_step", step_result.duplicate(true), snapshot())


func _clear_actor_action_state(actor_id: int, reason: String) -> void:
	if actor_view != null and actor_view.has_method("clear_actor_action_state"):
		actor_view.call("clear_actor_action_state", actor_id, reason)


func _step_waits_for_player_turn(step: Dictionary) -> bool:
	return bool(step.get("pending", false)) and str(step.get("reason", "")) == "ap_insufficient_movement_pending"


func _present_npc_turn_result(npc_result: Dictionary) -> Dictionary:
	if actor_view == null or not actor_view.has_method("move_actor_step"):
		return {"success": false, "active": false, "reason": "actor_view_missing"}
	var step: Dictionary = _npc_move_step_from_result(npc_result)
	if step.is_empty():
		return {"success": false, "active": false, "reason": "npc_move_step_missing"}
	var actor_id := int(step.get("actor_id", 0))
	if actor_id <= 0:
		return {"success": false, "active": false, "reason": "npc_actor_id_missing"}
	var from_grid: Dictionary = _dictionary_or_empty(step.get("from", {}))
	var to_grid: Dictionary = _dictionary_or_empty(step.get("to", {}))
	if from_grid.is_empty() or to_grid.is_empty():
		return {"success": false, "active": false, "reason": "npc_move_grid_missing", "actor_id": actor_id}
	var presentation: Dictionary = _dictionary_or_empty(actor_view.call("move_actor_step", host, actor_id, from_grid, to_grid, {
		"duration_sec": 0.08,
		"source": "npc_action",
	}))
	presentation["source"] = "npc_action"
	return presentation


func _npc_move_step_from_result(npc_result: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(npc_result.get("result", {}))
	var actor_id := int(result.get("actor_id", npc_result.get("actor_id", 0)))
	var from_grid: Dictionary = _dictionary_or_empty(result.get("from", {})).duplicate(true)
	var to_grid: Dictionary = _dictionary_or_empty(result.get("to", {})).duplicate(true)
	if not from_grid.is_empty() and not to_grid.is_empty():
		return {"actor_id": actor_id, "from": from_grid, "to": to_grid}
	for event in _array_or_empty(npc_result.get("events", [])):
		var event_data: Dictionary = _dictionary_or_empty(event)
		if str(event_data.get("kind", "")) != "movement_step":
			continue
		var payload: Dictionary = _dictionary_or_empty(event_data.get("payload", event_data))
		var event_actor_id := int(payload.get("actor_id", actor_id))
		if actor_id > 0 and event_actor_id != actor_id:
			continue
		from_grid = _dictionary_or_empty(payload.get("from", {})).duplicate(true)
		to_grid = _dictionary_or_empty(payload.get("to", {})).duplicate(true)
		if not from_grid.is_empty() and not to_grid.is_empty():
			return {"actor_id": event_actor_id, "from": from_grid, "to": to_grid}
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
