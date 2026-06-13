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
	if simulation == null or not simulation.has_method("prepare_attack_for_runner"):
		return {"success": false, "reason": "simulation_attack_runner_missing"}
	action = AttackAction.create(actor_id, target_actor_id, topology, options)
	active = true
	var result := _prepare_attack_step()
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
				_prepare_attack_step()
			"attack_presentation":
				_finish_attack_presentation_phase()
			"attack_resolve":
				_resolve_attack_step()
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
	var pending := bool(craft_update.get("pending", false))
	var turn_check: Dictionary = _should_end_actor_turn(actor_id)
	if pending:
		active = true
	else:
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
		return _prepare_attack_step()
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


func _prepare_attack_step() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var target_actor_id := int(action.get("target_actor_id", 0))
	var topology: Dictionary = _dictionary_or_empty(action.get("topology", {}))
	var options: Dictionary = _dictionary_or_empty(action.get("options", {}))
	var result: Dictionary = _dictionary_or_empty(simulation.call("prepare_attack_for_runner", actor_id, target_actor_id, topology, options))
	latest_result = result.duplicate(true)
	if not bool(result.get("success", false)):
		active = false
		AttackAction.apply_failed(action, str(result.get("reason", "attack_failed")))
		_clear_actor_action_state(actor_id, "attack_failed")
		_sync_host_after_step(result)
		return result
	AttackAction.apply_result(action, result)
	var presentation: Dictionary = {}
	if actor_view != null and actor_view.has_method("play_attack"):
		presentation = _dictionary_or_empty(actor_view.call("play_attack", host, actor_id, target_actor_id, result))
	result["presentation"] = presentation
	if not bool(presentation.get("active", false)):
		_resolve_attack_step()
	else:
		_sync_host_after_step(result)
	return result


func _finish_attack_presentation_phase() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	_clear_actor_action_state(actor_id, "attack_presentation_finished")
	action["phase"] = "attack_resolve"
	action["turn_phase"] = "player_action"
	return _resolve_attack_step()


func _resolve_attack_step() -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	if simulation == null or not simulation.has_method("resolve_attack_for_runner"):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		latest_result = {"success": false, "reason": "simulation_attack_resolve_missing", "actor_id": actor_id}
		_clear_actor_action_state(actor_id, "attack_resolve_missing")
		_sync_host_after_step(latest_result)
		return latest_result
	var prepared_attack: Dictionary = _dictionary_or_empty(action.get("prepared_attack", latest_result))
	var resolve_result: Dictionary = _dictionary_or_empty(simulation.call("resolve_attack_for_runner", prepared_attack))
	latest_result = resolve_result.duplicate(true)
	if not bool(resolve_result.get("success", false)):
		active = false
		AttackAction.apply_failed(action, str(resolve_result.get("reason", "attack_resolve_failed")))
		_clear_actor_action_state(actor_id, "attack_resolve_failed")
		_sync_host_after_step(resolve_result)
		return resolve_result
	_record_attack_phase(resolve_result, "player")
	var turn_check: Dictionary = _should_end_actor_turn(actor_id)
	AttackAction.finish_presentation(action, bool(turn_check.get("should_end", false)))
	if not bool(turn_check.get("should_end", false)):
		active = false
	var output := {
		"success": true,
		"kind": "attack_resolved_for_runner",
		"actor_id": actor_id,
		"attack_result": resolve_result.duplicate(true),
		"attack_pipeline": _array_or_empty(resolve_result.get("attack_pipeline", [])).duplicate(true),
		"turn_check": turn_check.duplicate(true),
	}
	latest_result = output.duplicate(true)
	_sync_host_after_step(output)
	return output


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
		NpcAction.apply_completed(action, NpcAction.phase_from_result(action, npc_result, {}, true))
	else:
		var presentation: Dictionary = _present_npc_turn_result(npc_result)
		npc_result["presentation"] = presentation
		NpcAction.apply_result(action, npc_result, presentation, NpcAction.phase_from_result(action, npc_result, presentation, false))
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
	elif str(action.get("kind", "")) == "craft":
		_record_craft_phase(pending_result, CraftAction.phase_source(action))
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
	InteractAction.record_phase(action, result)


func _interaction_phase_snapshot(view_snapshot: Dictionary = {}) -> Dictionary:
	return InteractAction.phase_snapshot(action, latest_result, view_snapshot)


func _record_wait_phase(result: Dictionary) -> void:
	WaitAction.record_phase(action, result, _pending_kind_from_result(result))


func _wait_phase_snapshot() -> Dictionary:
	return WaitAction.phase_snapshot(action, latest_result, _pending_kind_from_result(latest_result))


func _record_craft_phase(result: Dictionary, source: String) -> void:
	CraftAction.record_phase(action, result, source)


func _craft_phase_snapshot() -> Dictionary:
	return CraftAction.phase_snapshot(action, latest_result)


func _record_attack_phase(result: Dictionary, source: String) -> void:
	AttackAction.record_phase(action, result, source)


func _attack_phase_snapshot(view_snapshot: Dictionary = {}) -> Dictionary:
	return AttackAction.phase_snapshot(action, latest_result, view_snapshot)


func _npc_phase_snapshot(view_snapshot: Dictionary = {}) -> Dictionary:
	return NpcAction.phase_snapshot(action, latest_result, view_snapshot)


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
