extends RefCounted

const MoveAction = preload("res://scripts/app/controllers/actions/move_action.gd")
const InteractAction = preload("res://scripts/app/controllers/actions/interact_action.gd")
const AttackAction = preload("res://scripts/app/controllers/actions/attack_action.gd")
const WaitAction = preload("res://scripts/app/controllers/actions/wait_action.gd")
const CraftAction = preload("res://scripts/app/controllers/actions/craft_action.gd")
const NpcAction = preload("res://scripts/app/controllers/actions/npc_action.gd")
const NpcActionPresenter = preload("res://scripts/app/controllers/actions/npc_action_presenter.gd")

const AUTO_TURN_ADVANCE_LIMIT := 8
const PENDING_CRAFTING_TURN_ADVANCE_LIMIT := 64

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
	action = MoveAction.create(actor_id, target_grid, topology, begin)
	active = true
	latest_result = begin.duplicate(true)
	var step_result := _advance_move_step()
	if not bool(step_result.get("success", false)):
		active = false
	return step_result


func request_attack(actor_id: int, target_actor_id: int, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	if active:
		return {"success": false, "reason": "turn_action_runner_active", "snapshot": snapshot()}
	if simulation == null or not simulation.has_method("submit_attack_for_runner"):
		return {"success": false, "reason": "simulation_attack_runner_missing"}
	action = AttackAction.create(actor_id, target_actor_id, topology, options)
	active = true
	var result := _advance_attack_step()
	if not bool(result.get("success", false)):
		active = false
	return result


func request_interact(actor_id: int, target: Dictionary, option_id: String, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	if active:
		return {"success": false, "reason": "turn_action_runner_active", "snapshot": snapshot()}
	if simulation == null or not simulation.has_method("begin_interaction_for_runner"):
		return {"success": false, "reason": "simulation_interaction_runner_missing"}
	action = InteractAction.create(actor_id, target, option_id, topology, options)
	active = true
	var result := _begin_interaction_action()
	if not bool(result.get("success", false)) or not bool(action.get("runner_keeps_active", false)):
		active = false
	return result


func request_wait(actor_id: int, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	if active:
		return {"success": false, "reason": "turn_action_runner_active", "snapshot": snapshot()}
	if simulation == null or not simulation.has_method("submit_wait_for_runner"):
		return {"success": false, "reason": "simulation_wait_runner_missing"}
	action = WaitAction.create(actor_id, topology, options)
	active = true
	var result := _advance_wait_step()
	if not bool(result.get("success", false)):
		active = false
	return result


func request_craft(actor_id: int, command: Dictionary, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	if active:
		return {"success": false, "reason": "turn_action_runner_active", "snapshot": snapshot()}
	if simulation == null or not simulation.has_method("submit_craft_for_runner"):
		return {"success": false, "reason": "simulation_craft_runner_missing"}
	action = CraftAction.create(actor_id, command, topology, options)
	active = true
	var result := _advance_craft_step()
	if not bool(result.get("success", false)):
		active = false
	return result


func process() -> void:
	if not active:
		return
	if actor_view != null and actor_view.has_method("is_active") and bool(actor_view.call("is_active")):
		return
	var action_kind := str(action.get("kind", ""))
	if action_kind == "move":
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
	elif action_kind == "attack":
		match str(action.get("phase", "")):
			"attack_action":
				_advance_attack_step()
			"attack_presentation":
				_finish_attack_presentation_phase()
			"player_turn_end":
				_begin_world_turn_phase()
			"npc_action":
				_advance_npc_turn_phase()
			"npc_presentation":
				_finish_npc_presentation_phase()
			"player_turn_start":
				_finish_world_turn_phase()
	elif action_kind == "interact":
		if bool(action.get("completed_after_presentation", false)):
			_resume_interaction_after_approach()
			return
		match str(action.get("phase", "")):
			"interact_action":
				_resume_interaction_after_approach()
			"approach_move_step":
				_advance_interaction_approach_step()
			"player_turn_end":
				_begin_world_turn_phase()
			"npc_action":
				_advance_npc_turn_phase()
			"npc_presentation":
				_finish_npc_presentation_phase()
			"player_turn_start":
				_finish_world_turn_phase()
			"pending_resume":
				_resume_pending_interaction_turn()
	elif action_kind == "wait":
		match str(action.get("phase", "")):
			"wait_action":
				_advance_wait_step()
			"player_turn_end":
				_begin_world_turn_phase()
			"npc_action":
				_advance_npc_turn_phase()
			"npc_presentation":
				_finish_npc_presentation_phase()
			"player_turn_start":
				_finish_world_turn_phase()
			"pending_resume":
				_resume_pending_after_world_turn()
	elif action_kind == "craft":
		match str(action.get("phase", "")):
			"craft_action":
				_advance_craft_step()
			"player_turn_end":
				_begin_world_turn_phase()
			"npc_action":
				_advance_npc_turn_phase()
			"npc_presentation":
				_finish_npc_presentation_phase()
			"player_turn_start":
				_finish_world_turn_phase()
			"pending_resume":
				_resume_pending_after_world_turn()


func finish_active(reason: String = "fast_forward") -> Dictionary:
	if actor_view != null and actor_view.has_method("finish_active_actor_presentation"):
		actor_view.call("finish_active_actor_presentation", int(action.get("actor_id", 0)))
	active = false
	action["phase"] = "finished"
	latest_result["finish_reason"] = reason
	var output := snapshot()
	_sync_host_after_step(output)
	return output


func settle_stable_boundary(reason: String = "stable_boundary") -> Dictionary:
	if actor_view != null and actor_view.has_method("finish_active_actor_presentation"):
		actor_view.call("finish_active_actor_presentation", int(action.get("presenting_npc_actor_id", action.get("actor_id", 0))))
	active = false
	action["phase"] = "stable_boundary"
	action["turn_phase"] = "player"
	latest_result["settle_reason"] = reason
	var actor_id := int(action.get("actor_id", 0))
	if actor_id > 0:
		_clear_actor_action_state(actor_id, reason)
	var output := snapshot()
	output["settled"] = true
	output["reason"] = reason
	_sync_host_after_step(output)
	return output


func snapshot() -> Dictionary:
	var view_snapshot: Dictionary = _dictionary_or_empty(actor_view.call("snapshot")) if actor_view != null and actor_view.has_method("snapshot") else {}
	var path: Array = _array_or_empty(action.get("path", [])).duplicate(true)
	var step_index: int = int(action.get("step_index", 0))
	var path_length: int = path.size()
	var total_steps: int = max(0, path_length - 1)
	var pending_movement: Dictionary = _runner_pending_movement_snapshot()
	var remaining_steps: int = max(0, total_steps - step_index)
	if not pending_movement.is_empty() and pending_movement.has("remaining_steps"):
		remaining_steps = max(0, int(pending_movement.get("remaining_steps", remaining_steps)))
	var ap_before: float = float(action.get("ap_before", 0.0))
	var ap_after: float = float(action.get("ap_after", 0.0))
	return {
		"active": active,
		"phase": str(action.get("phase", "idle" if not active else "")),
		"action_kind": str(action.get("kind", "")),
		"actor_id": int(action.get("actor_id", 0)),
		"options": _dictionary_or_empty(action.get("options", {})).duplicate(true),
		"target": _dictionary_or_empty(action.get("target", action.get("target_grid", {}))).duplicate(true),
		"option_id": str(action.get("option_id", "")),
		"target_actor_id": int(action.get("target_actor_id", 0)),
		"path": path,
		"path_length": path_length,
		"total_steps": total_steps,
		"step_index": step_index,
		"completed_steps": min(step_index, total_steps),
		"remaining_steps": remaining_steps,
		"current_grid": _dictionary_or_empty(action.get("current_grid", {})).duplicate(true),
		"next_grid": _dictionary_or_empty(action.get("next_grid", {})).duplicate(true),
		"ap_before": ap_before,
		"ap_after": ap_after,
		"ap_delta": ap_after - ap_before,
		"turn_phase": str(action.get("turn_phase", "")),
		"pending_kind": str(action.get("pending_kind", "")),
		"pending_movement": pending_movement,
		"interaction_phase": _interaction_phase_snapshot(view_snapshot),
		"attack_phase": _attack_phase_snapshot(view_snapshot),
		"wait_phase": _wait_phase_snapshot(),
		"craft_phase": _craft_phase_snapshot(),
		"turn_cycles": int(action.get("turn_cycles", 0)),
		"auto_turn_limit": _auto_turn_limit(),
		"npc_queue": _array_or_empty(action.get("npc_queue", [])).duplicate(true),
		"npc_index": int(action.get("npc_index", 0)),
		"npc_results": _array_or_empty(action.get("npc_results", [])).duplicate(true),
		"presenting_npc_actor_id": int(action.get("presenting_npc_actor_id", 0)),
		"npc_phase": _npc_phase_snapshot(view_snapshot),
		"blocked_reason": str(latest_result.get("reason", "")) if not bool(latest_result.get("success", true)) else "",
		"presentation_active": bool(view_snapshot.get("active", false)),
		"actor_view": view_snapshot,
		"queued_actions": [],
		"latest_result": latest_result.duplicate(true),
	}


func _runner_pending_movement_snapshot() -> Dictionary:
	var pending: Dictionary = _dictionary_or_empty(action.get("pending_movement", {}))
	if pending.is_empty():
		pending = _dictionary_or_empty(latest_result.get("pending_movement", {}))
	if pending.is_empty() and simulation != null and simulation.has_method("pending_move_snapshot"):
		pending = _dictionary_or_empty(simulation.call("pending_move_snapshot", int(action.get("actor_id", 0))))
	return pending.duplicate(true)


func _advance_move_step() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var topology: Dictionary = _dictionary_or_empty(action.get("topology", {}))
	var step: Dictionary = _dictionary_or_empty(simulation.call("step_move", actor_id, topology))
	latest_result = step.duplicate(true)
	if not bool(step.get("success", false)):
		active = false
		MoveAction.apply_failed(action, str(step.get("reason", "failed")))
		_clear_actor_action_state(actor_id, "failed")
		_sync_host_after_step(step)
		return step
	if _step_waits_for_player_turn(step):
		MoveAction.apply_turn_wait(action, step)
		_sync_host_after_step(step)
		return step
	var phase_update: Dictionary = MoveAction.apply_step(action, step)
	var has_visual_step := bool(phase_update.get("has_visual_step", false))
	var presentation: Dictionary = {}
	if has_visual_step and actor_view != null and actor_view.has_method("move_actor_step"):
		presentation = _dictionary_or_empty(actor_view.call("move_actor_step", host, actor_id, _dictionary_or_empty(step.get("from", {})), _dictionary_or_empty(step.get("to", {}))))
	step["presentation"] = presentation
	if bool(step.get("completed", false)) and not has_visual_step:
		active = false
		MoveAction.finish_without_visual(action, str(step.get("reason", "finished")))
		_clear_actor_action_state(actor_id, str(step.get("reason", "finished")))
	_sync_host_after_step(step)
	return step


func _advance_wait_step() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var topology: Dictionary = _dictionary_or_empty(action.get("topology", {}))
	var options: Dictionary = _dictionary_or_empty(action.get("options", {}))
	var reason := str(options.get("reason", "wait"))
	var result: Dictionary = _dictionary_or_empty(simulation.call("submit_wait_for_runner", actor_id, topology, reason))
	latest_result = result.duplicate(true)
	if not bool(result.get("success", false)):
		active = false
		WaitAction.apply_failed(action, str(result.get("reason", "wait_failed")))
		_clear_actor_action_state(actor_id, "wait_failed")
		_sync_host_after_step(result)
		return result
	WaitAction.apply_result(action, result, _pending_kind_from_result(result))
	_record_wait_phase(result)
	_sync_host_after_step(result)
	return result


func _advance_craft_step() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var command: Dictionary = _dictionary_or_empty(action.get("command", {})).duplicate(true)
	var result: Dictionary = _dictionary_or_empty(simulation.call("submit_craft_for_runner", actor_id, command))
	latest_result = result.duplicate(true)
	if not bool(result.get("success", false)):
		active = false
		CraftAction.apply_failed(action, str(result.get("reason", "craft_failed")))
		_clear_actor_action_state(actor_id, "craft_failed")
		_sync_host_after_step(result)
		return result
	var craft_update: Dictionary = CraftAction.apply_result(action, result, _pending_kind_from_result(result))
	_record_craft_phase(result, CraftAction.phase_source(action))
	var turn_check: Dictionary = _should_end_actor_turn(actor_id)
	active = false
	_clear_actor_action_state(actor_id, str(craft_update.get("finish_reason", "craft_finished")))
	result["runner_active_after"] = active
	result["turn_check"] = turn_check.duplicate(true)
	latest_result = result.duplicate(true)
	_sync_host_after_step(result)
	return result


func _begin_interaction_action() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var target: Dictionary = _dictionary_or_empty(action.get("target", {}))
	var option_id := str(action.get("option_id", ""))
	var topology: Dictionary = _dictionary_or_empty(action.get("topology", {}))
	var result: Dictionary = _dictionary_or_empty(simulation.call("begin_interaction_for_runner", actor_id, target, option_id, topology))
	latest_result = result.duplicate(true)
	_record_interaction_phase(result)
	if not bool(result.get("success", false)):
		InteractAction.apply_failed(action, str(result.get("reason", "interaction_failed")))
		_clear_actor_action_state(actor_id, "interaction_failed")
		_sync_host_after_step(result)
		return result
	if str(result.get("kind", "")) == "attack_required":
		InteractAction.redirect_to_attack(action, int(result.get("target_actor_id", 0)))
		return _advance_attack_step()
	if bool(result.get("approach_required", false)):
		InteractAction.begin_approach(action, result)
		return _advance_interaction_approach_step()
	InteractAction.finish_immediate(action)
	_sync_host_after_step(result)
	return result


func _advance_interaction_approach_step() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var topology: Dictionary = _dictionary_or_empty(action.get("topology", {}))
	var step: Dictionary = _dictionary_or_empty(simulation.call("step_move", actor_id, topology))
	latest_result = step.duplicate(true)
	if not bool(step.get("success", false)):
		active = false
		InteractAction.apply_failed(action, str(step.get("reason", "interaction_approach_failed")))
		_clear_actor_action_state(actor_id, "interaction_approach_failed")
		_sync_host_after_step(step)
		return step
	if _step_waits_for_player_turn(step):
		InteractAction.apply_approach_turn_wait(action, step)
		_sync_host_after_step(step)
		return step
	var phase_update: Dictionary = InteractAction.apply_approach_step(action, step)
	var has_visual_step := bool(phase_update.get("has_visual_step", false))
	var presentation: Dictionary = {}
	if has_visual_step and actor_view != null and actor_view.has_method("move_actor_step"):
		presentation = _dictionary_or_empty(actor_view.call("move_actor_step", host, actor_id, _dictionary_or_empty(step.get("from", {})), _dictionary_or_empty(step.get("to", {})), {
			"source": "interaction_approach",
		}))
	step["presentation"] = presentation
	if bool(step.get("completed", false)) and not has_visual_step:
		return _resume_interaction_after_approach()
	_sync_host_after_step(step)
	return step


func _resume_interaction_after_approach() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var topology: Dictionary = _dictionary_or_empty(action.get("topology", {}))
	action["completed_after_presentation"] = false
	action["phase"] = "interact_action"
	action["turn_phase"] = "player_action"
	var pending_result: Dictionary = _dictionary_or_empty(simulation.call("resume_pending_for_runner", actor_id, topology, "interact"))
	_record_interaction_phase(pending_result)
	var result: Dictionary = {
		"success": bool(pending_result.get("success", false)),
		"kind": "interaction_finished",
		"actor_id": actor_id,
		"pending_result": pending_result.duplicate(true),
		"pending_movement": _dictionary_or_empty(pending_result.get("pending_movement", {})).duplicate(true),
		"pending_interaction": _dictionary_or_empty(pending_result.get("pending_interaction", {})).duplicate(true),
		"turn_state": _dictionary_or_empty(pending_result.get("turn_state", {})).duplicate(true),
	}
	latest_result = result.duplicate(true)
	if not bool(result.get("success", false)):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		_clear_actor_action_state(actor_id, str(pending_result.get("reason", "interaction_failed")))
		_sync_host_after_step(result)
		return result
	if not _dictionary_or_empty(result.get("pending_interaction", {})).is_empty():
		action["phase"] = "player_turn_end"
		action["turn_phase"] = "player_turn_end"
		action["pending_kind"] = "interaction"
	else:
		active = false
		action["phase"] = "finished"
		action["turn_phase"] = "player"
		action["pending_kind"] = ""
		_clear_actor_action_state(actor_id, "interaction_finished")
	_sync_host_after_step(result)
	return result


func _resume_pending_interaction_turn() -> Dictionary:
	if not _dictionary_or_empty(latest_result.get("pending_movement", {})).is_empty():
		return _advance_interaction_approach_step()
	return _resume_interaction_after_approach()


func _advance_attack_step() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var target_actor_id := int(action.get("target_actor_id", 0))
	var topology: Dictionary = _dictionary_or_empty(action.get("topology", {}))
	var options: Dictionary = _dictionary_or_empty(action.get("options", {}))
	var result: Dictionary = _dictionary_or_empty(simulation.call("submit_attack_for_runner", actor_id, target_actor_id, topology, options))
	latest_result = result.duplicate(true)
	if not bool(result.get("success", false)):
		active = false
		AttackAction.apply_failed(action, str(result.get("reason", "attack_failed")))
		_clear_actor_action_state(actor_id, "attack_failed")
		_sync_host_after_step(result)
		return result
	_record_attack_phase(result, "player")
	AttackAction.apply_result(action, result)
	var presentation: Dictionary = {}
	if actor_view != null and actor_view.has_method("play_attack"):
		presentation = _dictionary_or_empty(actor_view.call("play_attack", host, actor_id, target_actor_id, result))
	result["presentation"] = presentation
	if not bool(presentation.get("active", false)):
		_finish_attack_presentation_phase()
	else:
		_sync_host_after_step(result)
	return result


func _finish_attack_presentation_phase() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	_clear_actor_action_state(actor_id, "attack_presentation_finished")
	var turn_check: Dictionary = _should_end_actor_turn(actor_id)
	AttackAction.finish_presentation(action, bool(turn_check.get("should_end", false)))
	if not bool(turn_check.get("should_end", false)):
		active = false
	var result := {
		"success": true,
		"kind": "attack_presentation_finished",
		"actor_id": actor_id,
		"turn_check": turn_check.duplicate(true),
	}
	latest_result = result.duplicate(true)
	_sync_host_after_step(result)
	return result


func _begin_world_turn_phase() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var cycles := int(action.get("turn_cycles", 0))
	var limit := _auto_turn_limit()
	if cycles >= limit:
		active = false
		action["phase"] = "blocked"
		action["turn_phase"] = "blocked"
		_clear_actor_action_state(actor_id, "auto_turn_limit_reached")
		latest_result = {
			"success": false,
			"reason": "auto_turn_limit_reached",
			"actor_id": actor_id,
			"limit": limit,
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
	var begin_result: Dictionary = _dictionary_or_empty(simulation.call("begin_world_turn_for_runner", actor_id, topology, _world_turn_reason()))
	latest_result = begin_result.duplicate(true)
	if not bool(begin_result.get("success", false)):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		_clear_actor_action_state(actor_id, str(begin_result.get("reason", "turn_failed")))
		_sync_host_after_step(begin_result)
		return begin_result
	NpcAction.begin_world_turn(action, begin_result)
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
		NpcAction.apply_completed(action, _npc_phase_from_result(npc_result, {}, true))
	else:
		var presentation: Dictionary = _present_npc_turn_result(npc_result)
		npc_result["presentation"] = presentation
		NpcAction.apply_result(action, npc_result, presentation, _npc_phase_from_result(npc_result, presentation, false))
	_sync_host_after_step(npc_result)
	return npc_result


func _finish_npc_presentation_phase() -> Dictionary:
	var npc_actor_id := int(action.get("presenting_npc_actor_id", 0))
	_clear_actor_action_state(npc_actor_id, "npc_presentation_finished")
	NpcAction.finish_presentation(action)
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
	var finish_result: Dictionary = _dictionary_or_empty(simulation.call("finish_world_turn_for_runner", actor_id, _world_turn_reason()))
	latest_result = finish_result.duplicate(true)
	if not bool(finish_result.get("success", false)):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		_clear_actor_action_state(actor_id, str(finish_result.get("reason", "world_turn_finish_failed")))
		_sync_host_after_step(finish_result)
		return finish_result
	action["ap_after"] = float(finish_result.get("ap_after", action.get("ap_after", 0.0)))
	if _action_should_resume_pending(finish_result):
		action["phase"] = "pending_resume"
		action["turn_phase"] = "pending_resume"
		action["pending_kind"] = _pending_kind_from_result(finish_result)
	else:
		active = false
		action["phase"] = "finished"
		action["turn_phase"] = "player"
		_clear_actor_action_state(actor_id, "world_turn_finished")
	_sync_host_after_step(finish_result)
	return finish_result


func _resume_pending_after_world_turn() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var topology: Dictionary = _dictionary_or_empty(action.get("topology", {}))
	if simulation == null or not simulation.has_method("resume_pending_for_runner"):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		latest_result = {"success": false, "reason": "runner_pending_resume_api_missing", "actor_id": actor_id}
		_clear_actor_action_state(actor_id, "runner_pending_resume_api_missing")
		_sync_host_after_step(latest_result)
		return latest_result
	var pending_result: Dictionary = _dictionary_or_empty(simulation.call("resume_pending_for_runner", actor_id, topology, str(action.get("kind", "turn_action_runner"))))
	var result: Dictionary = {
		"success": bool(pending_result.get("success", false)),
		"kind": "pending_resume",
		"actor_id": actor_id,
		"pending_result": pending_result.duplicate(true),
		"pending_movement": _dictionary_or_empty(pending_result.get("pending_movement", {})).duplicate(true),
		"pending_interaction": _dictionary_or_empty(pending_result.get("pending_interaction", {})).duplicate(true),
		"pending_crafting": _dictionary_or_empty(pending_result.get("pending_crafting", {})).duplicate(true),
		"turn_state": _dictionary_or_empty(pending_result.get("turn_state", {})).duplicate(true),
	}
	latest_result = result.duplicate(true)
	if str(action.get("kind", "")) == "wait" and not _dictionary_or_empty(pending_result.get("resumed_pending_crafting", {})).is_empty():
		_record_craft_phase(pending_result, "wait_resume")
	elif str(action.get("kind", "")) == "wait" and not _dictionary_or_empty(pending_result.get("pending_crafting", {})).is_empty():
		_record_craft_phase(pending_result, "wait_resume")
	if not bool(result.get("success", false)):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		_clear_actor_action_state(actor_id, str(pending_result.get("reason", "pending_resume_failed")))
		_sync_host_after_step(result)
		return result
	if str(action.get("kind", "")) == "move" and not _dictionary_or_empty(result.get("pending_movement", {})).is_empty():
		action["phase"] = "pending_resume"
		action["turn_phase"] = "pending_resume"
		action["pending_kind"] = "movement"
	elif str(action.get("kind", "")) == "wait" and not _dictionary_or_empty(result.get("pending_crafting", {})).is_empty():
		action["phase"] = "player_turn_end"
		action["turn_phase"] = "player_turn_end"
		action["pending_kind"] = "crafting"
	elif str(action.get("kind", "")) == "craft" and not _dictionary_or_empty(result.get("pending_crafting", {})).is_empty():
		action["phase"] = "player_turn_end"
		action["turn_phase"] = "player_turn_end"
		action["pending_kind"] = "crafting"
	else:
		active = false
		action["phase"] = "finished"
		action["turn_phase"] = "player"
		action["pending_kind"] = _pending_kind_from_result(result)
		_clear_actor_action_state(actor_id, "pending_resume_finished")
	_sync_host_after_step(result)
	return result


func _sync_host_after_step(step_result: Dictionary) -> void:
	if host != null and host.has_method("sync_after_turn_action_step"):
		host.call("sync_after_turn_action_step", step_result.duplicate(true), snapshot())


func _clear_actor_action_state(actor_id: int, reason: String) -> void:
	if actor_view != null and actor_view.has_method("clear_actor_action_state"):
		actor_view.call("clear_actor_action_state", actor_id, reason)


func _step_waits_for_player_turn(step: Dictionary) -> bool:
	return bool(step.get("pending", false)) and str(step.get("reason", "")) == "ap_insufficient_movement_pending"


func _should_end_actor_turn(actor_id: int) -> Dictionary:
	if simulation != null and simulation.has_method("should_end_actor_turn"):
		return _dictionary_or_empty(simulation.call("should_end_actor_turn", actor_id))
	return {"success": false, "reason": "turn_check_missing", "actor_id": actor_id}


func _world_turn_reason() -> String:
	match str(action.get("kind", "")):
		"move":
			return "pending_movement"
		"attack":
			return "attack"
		"interact":
			return "interact"
		"wait":
			return str(_dictionary_or_empty(action.get("options", {})).get("reason", "wait"))
		"craft":
			return "craft"
	return str(action.get("kind", "turn_action_runner"))


func _auto_turn_limit() -> int:
	var options: Dictionary = _dictionary_or_empty(action.get("options", {}))
	if options.has("max_turn_cycles"):
		return max(1, int(options.get("max_turn_cycles", AUTO_TURN_ADVANCE_LIMIT)))
	if str(action.get("pending_kind", "")) == "crafting" or not _dictionary_or_empty(action.get("pending_crafting", {})).is_empty():
		return PENDING_CRAFTING_TURN_ADVANCE_LIMIT
	return AUTO_TURN_ADVANCE_LIMIT


func _action_should_resume_pending(result: Dictionary) -> bool:
	if str(action.get("kind", "")) == "move":
		return not _dictionary_or_empty(result.get("pending_movement", {})).is_empty()
	if str(action.get("kind", "")) == "interact":
		return not _dictionary_or_empty(result.get("pending_movement", {})).is_empty() \
			or not _dictionary_or_empty(result.get("pending_interaction", {})).is_empty()
	if str(action.get("kind", "")) == "wait":
		return not _dictionary_or_empty(result.get("pending_movement", {})).is_empty() \
			or not _dictionary_or_empty(result.get("pending_interaction", {})).is_empty() \
			or not _dictionary_or_empty(result.get("pending_crafting", {})).is_empty()
	if str(action.get("kind", "")) == "craft":
		return not _dictionary_or_empty(result.get("pending_crafting", {})).is_empty()
	return false


func _pending_kind_from_result(result: Dictionary) -> String:
	if not _dictionary_or_empty(result.get("pending_movement", {})).is_empty():
		return "movement"
	if not _dictionary_or_empty(result.get("pending_interaction", {})).is_empty():
		return "interaction"
	if not _dictionary_or_empty(result.get("pending_crafting", {})).is_empty():
		return "crafting"
	if not _dictionary_or_empty(result.get("pending_result", {})).is_empty():
		return _pending_kind_from_result(_dictionary_or_empty(result.get("pending_result", {})))
	return ""


func _record_interaction_phase(result: Dictionary) -> void:
	if str(action.get("kind", "")) != "interact":
		return
	var phase: Dictionary = _interaction_phase_from_result(result)
	if phase.is_empty():
		return
	action["interaction_phase"] = phase
	action["interaction_action_kind"] = str(phase.get("option_kind", ""))
	action["interaction_visual_kind"] = str(phase.get("visual_kind", ""))
	action["interaction_target_id"] = str(phase.get("target_id", ""))
	if bool(phase.get("completed", false)):
		action["interaction_completed"] = true


func _interaction_phase_snapshot(view_snapshot: Dictionary = {}) -> Dictionary:
	if str(action.get("kind", "")) != "interact":
		return {}
	var phase: Dictionary = _dictionary_or_empty(action.get("interaction_phase", {})).duplicate(true)
	if phase.is_empty():
		phase = _interaction_phase_from_result(latest_result)
	if phase.is_empty():
		phase = _interaction_phase_from_target()
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


func _interaction_phase_from_result(result: Dictionary) -> Dictionary:
	if result.is_empty():
		return {}
	var direct: Dictionary = result
	if not _dictionary_or_empty(result.get("pending_result", {})).is_empty():
		direct = _dictionary_or_empty(result.get("pending_result", {}))
	var prompt: Dictionary = _dictionary_or_empty(direct.get("prompt", result.get("prompt", {})))
	var option: Dictionary = _interaction_option_from_prompt(prompt, str(action.get("option_id", "")))
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
		"visual_kind": _interaction_visual_kind(option_kind, direct),
		"target_id": target_id,
		"target_type": str(target.get("target_type", "")),
		"target_name": str(direct.get("target_name", prompt.get("target_name", target.get("display_name", target_id)))),
		"target_grid": _interaction_target_grid(target),
		"open_panel": str(direct.get("open_panel", "")),
		"completed": _interaction_result_completed(direct),
		"result_kind": str(direct.get("kind", "")),
	}


func _interaction_phase_from_target() -> Dictionary:
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
		"target_grid": _interaction_target_grid(target),
		"open_panel": "",
		"completed": false,
		"result_kind": "",
	}


func _interaction_option_from_prompt(prompt: Dictionary, option_id: String) -> Dictionary:
	for value in _array_or_empty(prompt.get("options", [])):
		var option: Dictionary = _dictionary_or_empty(value)
		if option_id.is_empty() or str(option.get("id", "")) == option_id:
			return option
	return {}


func _interaction_visual_kind(option_kind: String, result: Dictionary) -> String:
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


func _interaction_result_completed(result: Dictionary) -> bool:
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


func _interaction_target_grid(target: Dictionary) -> Dictionary:
	for key in ["grid_position", "anchor", "grid"]:
		var grid: Dictionary = _dictionary_or_empty(target.get(key, {}))
		if not grid.is_empty():
			return grid.duplicate(true)
	return {}


func _record_wait_phase(result: Dictionary) -> void:
	if str(action.get("kind", "")) != "wait":
		return
	var phase: Dictionary = _wait_phase_from_result(result)
	if phase.is_empty():
		return
	action["wait_phase"] = phase
	action["wait_completed"] = bool(phase.get("completed", false))


func _wait_phase_snapshot() -> Dictionary:
	if str(action.get("kind", "")) != "wait" and _dictionary_or_empty(action.get("wait_phase", {})).is_empty():
		return {}
	var phase: Dictionary = _dictionary_or_empty(action.get("wait_phase", {})).duplicate(true)
	if phase.is_empty():
		phase = _wait_phase_from_result(latest_result)
	if phase.is_empty():
		phase = {
			"actor_id": int(action.get("actor_id", 0)),
			"reason": str(_dictionary_or_empty(action.get("options", {})).get("reason", "wait")),
		}
	phase["phase"] = str(action.get("phase", ""))
	phase["turn_phase"] = str(action.get("turn_phase", ""))
	phase["completed"] = bool(action.get("wait_completed", phase.get("completed", false))) or str(action.get("phase", "")) == "finished"
	return phase


func _wait_phase_from_result(result: Dictionary) -> Dictionary:
	if result.is_empty():
		return {}
	return {
		"actor_id": int(result.get("actor_id", action.get("actor_id", 0))),
		"reason": str(result.get("reason", _dictionary_or_empty(action.get("options", {})).get("reason", "wait"))),
		"waited": bool(result.get("waited", false)),
		"ap_before": float(result.get("ap_before", action.get("ap_before", 0.0))),
		"pending_kind": _pending_kind_from_result(result),
		"resumed_pending": not _dictionary_or_empty(result.get("pending_result", {})).is_empty(),
		"completed": bool(result.get("success", false)),
		"result_kind": str(result.get("kind", "wait")),
	}


func _record_craft_phase(result: Dictionary, source: String) -> void:
	var phase: Dictionary = _craft_phase_from_result(result, source)
	if phase.is_empty():
		return
	action["craft_phase"] = phase
	action["craft_completed"] = bool(phase.get("completed", false))


func _craft_phase_snapshot() -> Dictionary:
	if str(action.get("kind", "")) != "craft" and _dictionary_or_empty(action.get("craft_phase", {})).is_empty():
		return {}
	var phase: Dictionary = _dictionary_or_empty(action.get("craft_phase", {})).duplicate(true)
	if phase.is_empty():
		phase = _craft_phase_from_result(latest_result, str(action.get("kind", "craft")))
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


func _craft_phase_from_result(result: Dictionary, source: String) -> Dictionary:
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


func _record_attack_phase(result: Dictionary, source: String) -> void:
	var phase: Dictionary = _attack_phase_from_result(result, source)
	if phase.is_empty():
		return
	action["attack_phase"] = phase
	action["attack_source"] = source
	action["attack_actor_id"] = int(phase.get("actor_id", action.get("actor_id", 0)))
	action["attack_target_actor_id"] = int(phase.get("target_actor_id", action.get("target_actor_id", 0)))
	action["attack_completed"] = bool(phase.get("completed", false))


func _attack_phase_snapshot(view_snapshot: Dictionary = {}) -> Dictionary:
	if str(action.get("kind", "")) != "attack" and _dictionary_or_empty(action.get("attack_phase", {})).is_empty():
		return {}
	var phase: Dictionary = _dictionary_or_empty(action.get("attack_phase", {})).duplicate(true)
	if phase.is_empty():
		phase = _attack_phase_from_result(latest_result, str(action.get("attack_source", "player")))
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


func _attack_phase_from_result(result: Dictionary, source: String) -> Dictionary:
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


func _npc_phase_snapshot(view_snapshot: Dictionary = {}) -> Dictionary:
	var phase: Dictionary = _dictionary_or_empty(action.get("npc_phase", {})).duplicate(true)
	if phase.is_empty():
		phase = _npc_phase_from_result(latest_result, _dictionary_or_empty(latest_result.get("presentation", {})), bool(latest_result.get("completed", false)))
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


func _npc_phase_from_result(npc_result: Dictionary, presentation: Dictionary = {}, completed: bool = false) -> Dictionary:
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
		"completed": completed or bool(npc_result.get("completed", false)),
	}


func _actor_node_phase_snapshot(view_snapshot: Dictionary, actor_id: int) -> Dictionary:
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


func _present_npc_turn_result(npc_result: Dictionary) -> Dictionary:
	var presentation: Dictionary = NpcActionPresenter.present(host, actor_view, npc_result)
	var attack: Dictionary = NpcActionPresenter.attack_from_result(npc_result)
	if not attack.is_empty():
		_record_attack_phase(attack, "npc")
	return presentation


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
