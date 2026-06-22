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
		if str(action.get("kind", "")) == "move" and int(action.get("actor_id", 0)) == actor_id:
			return _queue_move_replacement(actor_id, target_grid, topology)
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
				_advance_player_turn_boundary_phase()
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
				_advance_player_turn_boundary_phase()
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
				_advance_player_turn_boundary_phase()
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
				_advance_player_turn_boundary_phase()
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
				_advance_player_turn_boundary_phase()
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
	var actor_id := int(action.get("actor_id", 0))
	var queued_actions: Array = _array_or_empty(action.get("queued_actions", [])).duplicate(true)
	var pending_cancel_result: Dictionary = _cancel_pending_for_stable_boundary(actor_id, reason)
	active = false
	action["queued_actions"] = []
	action["phase"] = "stable_boundary"
	action["turn_phase"] = "player"
	latest_result["settle_reason"] = reason
	latest_result["cancelled_pending"] = pending_cancel_result.duplicate(true)
	latest_result["cancelled_queued_actions"] = queued_actions.duplicate(true)
	if actor_id > 0:
		_clear_actor_action_state(actor_id, reason)
	var output := snapshot()
	output["settled"] = true
	output["reason"] = reason
	output["cancelled_pending"] = pending_cancel_result.duplicate(true)
	output["cancelled_queued_actions"] = queued_actions.duplicate(true)
	_sync_host_after_step(output)
	return output


func _cancel_pending_for_stable_boundary(actor_id: int, reason: String) -> Dictionary:
	if simulation == null or actor_id <= 0:
		return {}
	if simulation.has_method("cancel_pending"):
		return _dictionary_or_empty(simulation.call("cancel_pending", reason, false, _dictionary_or_empty(action.get("topology", {}))))
	if simulation.has_method("cancel_move"):
		return _dictionary_or_empty(simulation.call("cancel_move", actor_id, reason))
	return {}


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
		"background_world_turn_active": bool(action.get("background_world_turn_active", false)),
		"background_world_turn_interrupted": bool(action.get("background_world_turn_interrupted", false)),
		"background_world_turn_interrupt": _dictionary_or_empty(action.get("background_world_turn_interrupt", {})).duplicate(true),
		"npc_queue": _array_or_empty(action.get("npc_queue", [])).duplicate(true),
		"npc_index": int(action.get("npc_index", 0)),
		"npc_results": _array_or_empty(action.get("npc_results", [])).duplicate(true),
		"presenting_npc_actor_id": int(action.get("presenting_npc_actor_id", 0)),
		"npc_phase": _npc_phase_snapshot(view_snapshot),
		"blocked_reason": str(latest_result.get("reason", "")) if not bool(latest_result.get("success", true)) else "",
		"presentation_active": bool(view_snapshot.get("active", false)),
		"actor_view": view_snapshot,
		"queued_actions": _array_or_empty(action.get("queued_actions", [])).duplicate(true),
		"latest_result": latest_result.duplicate(true),
	}


func drain_status() -> Dictionary:
	# 轻量状态：供 drain / settle 循环逐步轮询使用，避免每步都构建完整 snapshot
	# （后者含 ~10 次 .duplicate(true) 深拷贝 + 内嵌 actor_view 快照）。
	# 字段与 snapshot() 中对应项保持一致。
	var presentation_active := false
	if actor_view != null and actor_view.has_method("is_active"):
		presentation_active = bool(actor_view.call("is_active"))
	return {
		"active": active,
		"presentation_active": presentation_active,
		"presenting_npc_actor_id": int(action.get("presenting_npc_actor_id", 0)),
		"actor_id": int(action.get("actor_id", 0)),
		"phase": str(action.get("phase", "idle" if not active else "")),
		"pending_kind": str(action.get("pending_kind", "")),
	}


func _runner_pending_movement_snapshot() -> Dictionary:
	var pending: Dictionary = _dictionary_or_empty(action.get("pending_movement", {}))
	if pending.is_empty():
		pending = _dictionary_or_empty(latest_result.get("pending_movement", {}))
	if pending.is_empty() and simulation != null and simulation.has_method("pending_move_snapshot"):
		pending = _dictionary_or_empty(simulation.call("pending_move_snapshot", int(action.get("actor_id", 0))))
	return pending.duplicate(true)


func _advance_move_step() -> Dictionary:
	if _move_replacement_ready_to_start():
		return _start_queued_move_replacement()
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


func _queue_move_replacement(actor_id: int, target_grid: Dictionary, topology: Dictionary) -> Dictionary:
	var queued_actions: Array = _array_or_empty(action.get("queued_actions", [])).duplicate(true)
	var replacement := {
		"kind": "move",
		"replacement": true,
		"actor_id": actor_id,
		"target_grid": target_grid.duplicate(true),
		"topology": topology.duplicate(true),
		"requested_phase": str(action.get("phase", "")),
		"requested_step_index": int(action.get("step_index", 0)),
		"replace_after": "current_step_presentation",
	}
	if queued_actions.is_empty():
		queued_actions.append(replacement)
	else:
		queued_actions[queued_actions.size() - 1] = replacement
	action["queued_actions"] = queued_actions
	latest_result = {
		"success": true,
		"kind": "move_replacement_queued",
		"actor_id": actor_id,
		"target_position": target_grid.duplicate(true),
		"queued_actions": queued_actions.duplicate(true),
		"replace_after": "current_step_presentation",
	}
	return latest_result.duplicate(true)


func _move_replacement_ready_to_start() -> bool:
	if str(action.get("kind", "")) != "move":
		return false
	if _array_or_empty(action.get("queued_actions", [])).is_empty():
		return false
	if actor_view != null and actor_view.has_method("is_active") and bool(actor_view.call("is_active")):
		return false
	return true


func _start_queued_move_replacement() -> Dictionary:
	var queued_actions: Array = _array_or_empty(action.get("queued_actions", [])).duplicate(true)
	if queued_actions.is_empty():
		return {"success": false, "reason": "queued_move_replacement_missing"}
	var queued: Dictionary = _dictionary_or_empty(queued_actions.pop_front())
	var actor_id := int(queued.get("actor_id", action.get("actor_id", 0)))
	var target_grid: Dictionary = _dictionary_or_empty(queued.get("target_grid", {}))
	var topology: Dictionary = _dictionary_or_empty(queued.get("topology", action.get("topology", {})))
	var cancelled: Dictionary = {}
	if simulation != null and simulation.has_method("cancel_move"):
		cancelled = _dictionary_or_empty(simulation.call("cancel_move", actor_id, "move_replacement"))
	if simulation == null or not simulation.has_method("begin_move"):
		active = false
		latest_result = {"success": false, "reason": "simulation_step_move_missing", "actor_id": actor_id}
		_sync_host_after_step(latest_result)
		return latest_result
	var begin: Dictionary = _dictionary_or_empty(simulation.call("begin_move", actor_id, target_grid, topology))
	if not bool(begin.get("success", false)):
		active = false
		action["queued_actions"] = queued_actions
		latest_result = begin.duplicate(true)
		latest_result["replacement_failed"] = true
		latest_result["cancelled_pending"] = cancelled.duplicate(true)
		_sync_host_after_step(latest_result)
		return latest_result
	action = MoveAction.create(actor_id, target_grid, topology, begin)
	action["queued_actions"] = queued_actions
	action["replacement_started"] = true
	action["replacement_cancelled_pending"] = cancelled.duplicate(true)
	active = true
	latest_result = begin.duplicate(true)
	latest_result["replacement_started"] = true
	latest_result["cancelled_pending"] = cancelled.duplicate(true)
	return _advance_move_step()


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


func _advance_player_turn_boundary_phase() -> Dictionary:
	if _should_use_background_world_turn():
		return _advance_background_world_turn_phase()
	return _begin_world_turn_phase()


func _advance_background_world_turn_phase() -> Dictionary:
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
			"background_world_turn": true,
		}
		_sync_host_after_step(latest_result)
		return latest_result
	if simulation == null or not simulation.has_method("begin_world_turn_for_runner") or not simulation.has_method("advance_next_npc_turn_for_runner") or not simulation.has_method("finish_world_turn_for_runner"):
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		latest_result = {"success": false, "reason": "runner_background_world_turn_api_missing", "actor_id": actor_id}
		_clear_actor_action_state(actor_id, "runner_background_world_turn_api_missing")
		_sync_host_after_step(latest_result)
		return latest_result
	action["turn_cycles"] = cycles + 1
	action["phase"] = "background_world_turn"
	action["turn_phase"] = "background_world_turn"
	action["background_world_turn_active"] = true
	var topology: Dictionary = _dictionary_or_empty(action.get("topology", {}))
	var begin_result: Dictionary = _dictionary_or_empty(simulation.call("begin_world_turn_for_runner", actor_id, topology, _world_turn_reason()))
	begin_result["background_world_turn"] = true
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
	var interrupt: Dictionary = _background_world_turn_interrupt_from_result(begin_result)
	if not interrupt.is_empty():
		return _finish_background_world_turn_without_resume(begin_result, interrupt)
	var guard := 0
	var completed := false
	while guard < 512:
		guard += 1
		var npc_result: Dictionary = _dictionary_or_empty(simulation.call("advance_next_npc_turn_for_runner"))
		npc_result["background_world_turn"] = true
		latest_result = npc_result.duplicate(true)
		if not bool(npc_result.get("success", false)):
			active = false
			action["phase"] = "failed"
			action["turn_phase"] = "failed"
			_clear_actor_action_state(actor_id, str(npc_result.get("reason", "npc_turn_failed")))
			_sync_host_after_step(npc_result)
			return npc_result
		if bool(npc_result.get("completed", false)):
			completed = true
			break
		var npc_results: Array = _array_or_empty(action.get("npc_results", []))
		npc_results.append(_dictionary_or_empty(npc_result.get("result", {})).duplicate(true))
		action["npc_results"] = npc_results
		action["npc_index"] = int(npc_result.get("npc_index", action.get("npc_index", 0))) + 1
		interrupt = _background_world_turn_interrupt_from_result(npc_result)
		if not interrupt.is_empty():
			return _interrupt_background_world_turn(npc_result, interrupt)
		var background_presentation: Dictionary = _present_background_npc_turn_result(npc_result)
		if not background_presentation.is_empty():
			npc_result["background_presentation"] = background_presentation.duplicate(true)
	if not completed:
		active = false
		action["phase"] = "failed"
		action["turn_phase"] = "failed"
		latest_result = {
			"success": false,
			"reason": "background_world_turn_guard_reached",
			"actor_id": actor_id,
			"guard": guard,
		}
		_clear_actor_action_state(actor_id, "background_world_turn_guard_reached")
		_sync_host_after_step(latest_result)
		return latest_result
	var finish_result: Dictionary = _finish_world_turn_phase()
	finish_result["background_world_turn"] = true
	action["background_world_turn_active"] = false
	if not bool(finish_result.get("success", false)):
		return finish_result
	return _advance_after_background_world_turn(finish_result)


func _advance_after_background_world_turn(finish_result: Dictionary) -> Dictionary:
	if not active:
		return finish_result
	if str(action.get("phase", "")) != "pending_resume":
		return finish_result
	match str(action.get("kind", "")):
		"move":
			return _advance_move_step()
		"interact":
			return _resume_pending_interaction_turn()
		"wait", "craft":
			return _resume_pending_after_world_turn()
	return finish_result


func _finish_background_world_turn_without_resume(source_result: Dictionary, interrupt: Dictionary) -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	var finish_result: Dictionary = {}
	if simulation != null and simulation.has_method("finish_world_turn_for_runner"):
		finish_result = _dictionary_or_empty(simulation.call("finish_world_turn_for_runner", actor_id, _world_turn_reason()))
	action["background_world_turn_active"] = false
	action["background_world_turn_interrupted"] = true
	action["background_world_turn_interrupt"] = interrupt.duplicate(true)
	active = false
	action["phase"] = "blocked"
	action["turn_phase"] = "blocked"
	latest_result = source_result.duplicate(true)
	latest_result["background_world_turn_interrupted"] = true
	latest_result["interrupt"] = interrupt.duplicate(true)
	latest_result["finish_result"] = finish_result.duplicate(true)
	_clear_actor_action_state(actor_id, str(interrupt.get("reason", "background_world_turn_interrupted")))
	_sync_host_after_step(latest_result)
	return latest_result


func _interrupt_background_world_turn(npc_result: Dictionary, interrupt: Dictionary) -> Dictionary:
	action["background_world_turn_active"] = false
	action["background_world_turn_interrupted"] = true
	action["background_world_turn_interrupt"] = interrupt.duplicate(true)
	var presentation: Dictionary = _present_npc_turn_result(npc_result)
	npc_result["presentation"] = presentation.duplicate(true)
	npc_result["background_world_turn_interrupted"] = true
	npc_result["interrupt"] = interrupt.duplicate(true)
	NpcAction.apply_result(action, npc_result, presentation, NpcAction.phase_from_result(action, npc_result, presentation, false))
	if not bool(presentation.get("active", false)):
		var attack: Dictionary = NpcActionPresenter.attack_from_result(npc_result)
		if bool(attack.get("attack_prepared", false)):
			action["presenting_npc_prepared_attack"] = attack.duplicate(true)
			var resolved: Dictionary = _resolve_presented_npc_attack()
			if not resolved.is_empty():
				npc_result["npc_attack_result"] = resolved.duplicate(true)
	latest_result = npc_result.duplicate(true)
	_sync_host_after_step(npc_result)
	return npc_result


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
	var resolve_result: Dictionary = _resolve_presented_npc_attack()
	NpcAction.finish_presentation(action)
	var result := {
		"success": true,
		"kind": "npc_presentation_finished",
		"actor_id": npc_actor_id,
	}
	if not resolve_result.is_empty():
		result["npc_attack_result"] = resolve_result.duplicate(true)
	latest_result = result.duplicate(true)
	_sync_host_after_step(result)
	return result


func _resolve_presented_npc_attack() -> Dictionary:
	var prepared_attack: Dictionary = _dictionary_or_empty(action.get("presenting_npc_prepared_attack", {}))
	if prepared_attack.is_empty():
		return {}
	var npc_phase: Dictionary = _dictionary_or_empty(action.get("npc_phase", {}))
	if str(npc_phase.get("intent", "")) != "attack" and str(prepared_attack.get("intent", "")) != "attack":
		return {}
	if prepared_attack.is_empty() or simulation == null or not simulation.has_method("resolve_npc_attack_for_runner"):
		return {}
	var resolved: Dictionary = _dictionary_or_empty(simulation.call("resolve_npc_attack_for_runner", prepared_attack))
	if bool(resolved.get("success", false)):
		_record_attack_phase(resolved, "npc")
		NpcAction.apply_resolved_attack(action, resolved)
	return resolved


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
	if bool(action.get("background_world_turn_interrupted", false)):
		active = false
		action["phase"] = "finished"
		action["turn_phase"] = "player"
		action["pending_kind"] = _pending_kind_from_result(finish_result)
		finish_result["background_world_turn_interrupted"] = true
		finish_result["interrupt"] = _dictionary_or_empty(action.get("background_world_turn_interrupt", {})).duplicate(true)
		_clear_actor_action_state(actor_id, "background_world_turn_interrupted")
		_sync_host_after_step(finish_result)
		return finish_result
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


func _present_background_npc_turn_result(npc_result: Dictionary) -> Dictionary:
	if actor_view == null or not actor_view.has_method("move_actor_background_step"):
		return {}
	var step: Dictionary = NpcActionPresenter.move_step_from_result(npc_result)
	if step.is_empty():
		return {}
	var actor_id := int(step.get("actor_id", 0))
	if actor_id <= 0:
		return {}
	return _dictionary_or_empty(actor_view.call(
		"move_actor_background_step",
		host,
		actor_id,
		_dictionary_or_empty(step.get("from", {})),
		_dictionary_or_empty(step.get("to", {})),
		{
			"duration_sec": 0.08,
			"source": "background_npc_action",
		}
	))


func _should_use_background_world_turn() -> bool:
	if str(action.get("phase", "")) != "player_turn_end":
		return false
	if str(action.get("kind", "")) == "attack":
		return false
	return _is_noncombat_player_context(int(action.get("actor_id", 0)))


func _is_noncombat_player_context(actor_id: int) -> bool:
	if simulation == null or actor_id <= 0:
		return false
	if _simulation_combat_active():
		return false
	var actor: RefCounted = _actor_by_id(actor_id)
	if actor == null:
		return false
	return not bool(actor.in_combat)


func _simulation_combat_active() -> bool:
	if simulation == null or not simulation.has_method("snapshot"):
		return false
	var runtime_snapshot: Dictionary = _dictionary_or_empty(simulation.call("snapshot"))
	return bool(_dictionary_or_empty(runtime_snapshot.get("combat_state", {})).get("active", false))


func _actor_by_id(actor_id: int) -> RefCounted:
	if simulation == null or actor_id <= 0:
		return null
	if simulation.actor_registry == null:
		return null
	return simulation.actor_registry.get_actor(actor_id)


func _background_world_turn_interrupt_from_result(step_result: Dictionary) -> Dictionary:
	var actor_id := int(action.get("actor_id", 0))
	if _simulation_combat_active():
		return {"reason": "combat_active", "actor_id": actor_id}
	var actor: RefCounted = _actor_by_id(actor_id)
	if actor != null and actor.hp <= 0.0:
		return {"reason": "player_defeated", "actor_id": actor_id}
	var direct: Dictionary = _dictionary_or_empty(step_result.get("result", step_result))
	var attack: Dictionary = NpcActionPresenter.attack_from_result(step_result)
	if _result_is_prepared_or_resolved_attack(direct) or not attack.is_empty():
		return {
			"reason": "npc_attack",
			"actor_id": int(direct.get("actor_id", step_result.get("actor_id", 0))),
			"target_actor_id": int(direct.get("target_actor_id", attack.get("target_actor_id", 0))),
		}
	for action_value in _array_or_empty(direct.get("actions", [])):
		var action_result: Dictionary = _dictionary_or_empty(action_value)
		if _result_is_prepared_or_resolved_attack(action_result):
			return {
				"reason": "npc_attack",
				"actor_id": int(action_result.get("actor_id", direct.get("actor_id", 0))),
				"target_actor_id": int(action_result.get("target_actor_id", 0)),
			}
	for event_value in _array_or_empty(step_result.get("events", [])):
		var event: Dictionary = _dictionary_or_empty(event_value)
		var kind := str(event.get("kind", ""))
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", event))
		if ["combat_started", "attack_resolved", "actor_defeated", "active_effect_defeated_actor"].has(kind):
			return {
				"reason": kind,
				"actor_id": int(payload.get("actor_id", payload.get("source_actor_id", 0))),
				"target_actor_id": int(payload.get("target_actor_id", payload.get("defeated_actor_id", 0))),
			}
		if int(payload.get("target_actor_id", 0)) == actor_id and (payload.has("damage") or bool(payload.get("defeated", false))):
			return {
				"reason": kind if not kind.is_empty() else "player_affected",
				"actor_id": int(payload.get("actor_id", payload.get("source_actor_id", 0))),
				"target_actor_id": actor_id,
			}
	return {}


func _result_is_prepared_or_resolved_attack(result: Dictionary) -> bool:
	if result.is_empty():
		return false
	if bool(result.get("attack_prepared", false)) or bool(result.get("npc_attack_prepared", false)):
		return true
	if str(result.get("kind", "")) == "npc_attack_prepared":
		return true
	return str(result.get("intent", "")) == "attack" and (result.has("damage") or result.has("hit_kind") or bool(result.get("defeated", false)))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
