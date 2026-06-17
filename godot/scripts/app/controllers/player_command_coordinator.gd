extends RefCounted

var host


func configure(p_host) -> void:
	host = p_host


func turn_action_runner_snapshot() -> Dictionary:
	if host.turn_action_runner == null or not host.turn_action_runner.has_method("snapshot"):
		return {"active": false, "phase": "missing"}
	return dictionary_or_empty(host.turn_action_runner.call("snapshot"))


func drain_turn_action_runner(max_steps: int = 240) -> Dictionary:
	if host.turn_action_runner == null or not host.turn_action_runner.has_method("snapshot"):
		return {"active": false, "phase": "missing", "drained": false}
	var steps := 0
	var runner: Dictionary = turn_action_runner_snapshot()
	while steps < max_steps and bool(runner.get("active", false)):
		steps += 1
		if bool(runner.get("presentation_active", false)) and host.actor_view_controller != null and host.actor_view_controller.has_method("finish_active_actor_presentation"):
			host.actor_view_controller.call("finish_active_actor_presentation", int(runner.get("presenting_npc_actor_id", runner.get("actor_id", 0))))
		if host.turn_action_runner.has_method("process"):
			host.turn_action_runner.call("process")
		runner = turn_action_runner_snapshot()
	runner["drained"] = not bool(runner.get("active", false))
	runner["drain_steps"] = steps
	runner["drain_limit"] = max_steps
	return runner


func settle_turn_action_runner_boundary(reason: String = "stable_boundary", max_steps: int = 8) -> Dictionary:
	if host.turn_action_runner == null or not host.turn_action_runner.has_method("snapshot"):
		return {"active": false, "phase": "missing", "settled": false}
	var before: Dictionary = turn_action_runner_snapshot()
	if bool(before.get("active", false)) or bool(before.get("presentation_active", false)):
		if host.turn_action_runner.has_method("settle_stable_boundary"):
			var settled: Dictionary = dictionary_or_empty(host.turn_action_runner.call("settle_stable_boundary", reason))
			settled["before"] = before.duplicate(true)
			settled["settle_steps"] = 1
			settled["settle_limit"] = max_steps
			settled["settled"] = not bool(settled.get("active", false)) and not bool(settled.get("presentation_active", false))
			return settled
	var steps := 0
	var runner: Dictionary = before.duplicate(true)
	while steps < max_steps and (bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))):
		steps += 1
		if bool(runner.get("presentation_active", false)) and host.actor_view_controller != null and host.actor_view_controller.has_method("finish_active_actor_presentation"):
			host.actor_view_controller.call("finish_active_actor_presentation", int(runner.get("presenting_npc_actor_id", runner.get("actor_id", 0))))
		if host.turn_action_runner.has_method("process"):
			host.turn_action_runner.call("process")
		runner = turn_action_runner_snapshot()
		if str(runner.get("phase", "")) == "player_turn_end" or str(runner.get("phase", "")) == "pending_resume":
			break
		if bool(runner.get("active", false)) and not bool(runner.get("presentation_active", false)) and not str(runner.get("pending_kind", "")).is_empty():
			break
	runner["settled"] = not bool(runner.get("presentation_active", false))
	runner["settle_steps"] = steps
	runner["settle_limit"] = max_steps
	runner["reason"] = reason
	runner["before"] = before.duplicate(true)
	return runner


func prepare_runtime_save_boundary(reason: String = "save_boundary") -> Dictionary:
	var before_runner: Dictionary = turn_action_runner_snapshot()
	var before_policy: Dictionary = host.world_render_policy_snapshot()
	var drain_result: Dictionary = {}
	if bool(before_runner.get("active", false)) or bool(before_runner.get("presentation_active", false)):
		drain_result = drain_turn_action_runner()
		drain_result["reason"] = reason
		host.refresh_hud(host.current_interaction_prompt())
	var after_runner: Dictionary = turn_action_runner_snapshot()
	var after_policy: Dictionary = host.world_render_policy_snapshot()
	var stable := not bool(after_runner.get("active", false)) and not bool(after_runner.get("presentation_active", false))
	var structural_allowed := bool(after_policy.get("structural_render_allowed", false))
	return {
		"success": stable and structural_allowed,
		"reason": reason if stable and structural_allowed else "save_boundary_unstable",
		"stable": stable,
		"save_allowed": stable and structural_allowed,
		"drained_turn_action_runner": not drain_result.is_empty() and bool(drain_result.get("drained", false)),
		"drain_result": drain_result.duplicate(true),
		"before_runner": before_runner.duplicate(true),
		"after_runner": after_runner.duplicate(true),
		"before_policy": before_policy.duplicate(true),
		"after_policy": after_policy.duplicate(true),
	}


func request_player_move(grid: Dictionary) -> Dictionary:
	host.call("_setup_world_container")
	host.call("_configure_turn_action_runner")
	if not runner_allows_move_replacement():
		var blocked: Dictionary = player_command_rejection("move")
		if not blocked.is_empty():
			return blocked
	var player_id := int(host.call("_player_actor_id"))
	var topology: Dictionary = dictionary_or_empty(host.world_result.get("map", {}))
	return dictionary_or_empty(host.turn_action_runner.call("request_move", player_id, grid, topology))


func runner_allows_move_replacement() -> bool:
	if host.is_observe_mode_enabled() or not str(host.call("_panel_modal_blocker_name")).is_empty():
		return false
	if host.world_action_flow_controller != null and bool(host.world_action_flow_controller.call("blocks_input")):
		return false
	var runner: Dictionary = turn_action_runner_snapshot()
	return (bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))) and str(runner.get("action_kind", "")) == "move"


func request_player_attack(target_actor_id: int, options: Dictionary = {}) -> Dictionary:
	var blocked: Dictionary = player_command_rejection("attack")
	if not blocked.is_empty():
		return blocked
	host.call("_setup_world_container")
	host.call("_configure_turn_action_runner")
	var player_id := int(host.call("_player_actor_id"))
	var topology: Dictionary = dictionary_or_empty(host.world_result.get("map", {}))
	var result: Dictionary = dictionary_or_empty(host.turn_action_runner.call("request_attack", player_id, target_actor_id, topology, options))
	if bool(result.get("success", false)):
		host.call("_restore_actor_camera_follow", "player_attack")
	return result


func request_player_interaction(target: Dictionary, option_id: String = "", options: Dictionary = {}) -> Dictionary:
	var blocked: Dictionary = player_command_rejection("interact")
	if not blocked.is_empty():
		return blocked
	if target.is_empty():
		return {"success": false, "reason": "interaction_target_not_selected"}
	host.call("_setup_world_container")
	host.call("_configure_turn_action_runner")
	var player_id := int(host.call("_player_actor_id"))
	var topology: Dictionary = dictionary_or_empty(host.world_result.get("map", {}))
	var result: Dictionary = dictionary_or_empty(host.turn_action_runner.call("request_interact", player_id, target, option_id, topology, options))
	if bool(result.get("success", false)):
		host.call("_restore_actor_camera_follow", "player_interaction")
	return result


func request_player_wait(options: Dictionary = {}) -> Dictionary:
	var blocked: Dictionary = player_command_rejection("wait")
	if not blocked.is_empty():
		return blocked
	host.call("_setup_world_container")
	host.call("_configure_turn_action_runner")
	var player_id := int(host.call("_player_actor_id"))
	var topology: Dictionary = dictionary_or_empty(host.world_result.get("map", {}))
	return dictionary_or_empty(host.turn_action_runner.call("request_wait", player_id, topology, options))


func request_player_craft(command: Dictionary, options: Dictionary = {}) -> Dictionary:
	var blocked: Dictionary = player_command_rejection("craft")
	if not blocked.is_empty():
		return blocked
	host.call("_setup_world_container")
	host.call("_configure_turn_action_runner")
	var player_id := int(host.call("_player_actor_id"))
	var topology: Dictionary = dictionary_or_empty(command.get("topology", host.world_result.get("map", {})))
	return dictionary_or_empty(host.turn_action_runner.call("request_craft", player_id, command, topology, options))


func sync_after_turn_action_step(step_result: Dictionary = {}, runner_snapshot: Dictionary = {}) -> Dictionary:
	var crafting_continuation: Dictionary = {}
	if runner_step_should_continue_crafting_queue(step_result, runner_snapshot):
		crafting_continuation = dictionary_or_empty(host.call("_continue_crafting_queue_after_wait", step_result, runner_snapshot))
	var interaction_result: Dictionary = runner_interaction_result(step_result, runner_snapshot)
	if not interaction_result.is_empty():
		host.call("_apply_world_root_snapshot", false)
		host.call("_configure_turn_action_runner")
		host.call("_configure_runtime_audio_layers")
		if bool(crafting_continuation.get("continued", false)):
			host.call("_refresh_operation_panels", array_or_empty(crafting_continuation.get("refresh", [])))
		host.call("_apply_interaction_execution_result", interaction_result, dictionary_or_empty(runner_snapshot.get("target", {})))
		return {
			"success": true,
			"render_world": true,
			"world_result_synced": false,
			"world_result_deferred": true,
			"step_result": step_result.duplicate(true),
			"turn_action_runner": runner_snapshot.duplicate(true),
		}
	var needs_world_result_sync := turn_action_step_needs_world_result_sync(step_result, runner_snapshot, interaction_result, crafting_continuation)
	if needs_world_result_sync and not bool(host.call("_rebuild_runtime_world_result", "turn_action_runner_step")):
		return {"success": false, "reason": "world_result_sync_failed"}
	host.call("_apply_world_root_snapshot", false)
	host.call("_configure_turn_action_runner")
	host.call("_configure_runtime_audio_layers")
	if bool(crafting_continuation.get("continued", false)):
		host.call("_refresh_operation_panels", array_or_empty(crafting_continuation.get("refresh", [])))
	host.refresh_hud(host.current_interaction_prompt())
	return {
		"success": true,
		"render_world": false,
		"world_result_synced": needs_world_result_sync,
		"step_result": step_result.duplicate(true),
		"turn_action_runner": runner_snapshot.duplicate(true),
	}


func turn_action_step_needs_world_result_sync(step_result: Dictionary, runner_snapshot: Dictionary, interaction_result: Dictionary, crafting_continuation: Dictionary = {}) -> bool:
	if not interaction_result.is_empty():
		return true
	if bool(crafting_continuation.get("continued", false)):
		return true
	return turn_action_result_has_structural_change(step_result) \
		or turn_action_result_has_structural_change(dictionary_or_empty(step_result.get("attack_result", {}))) \
		or turn_action_result_has_structural_change(dictionary_or_empty(step_result.get("npc_attack_result", {}))) \
		or turn_action_result_has_structural_change(dictionary_or_empty(step_result.get("pending_result", {}))) \
		or turn_action_runner_is_structural_refresh_boundary(runner_snapshot)


func turn_action_result_has_structural_change(result: Dictionary) -> bool:
	if result.is_empty():
		return false
	if result.has("context_snapshot"):
		return true
	if result.has("container") or result.has("shop"):
		return true
	if bool(result.get("consumed_target", false)) or bool(result.get("door_toggled", false)):
		return true
	if bool(result.get("defeated", false)) or bool(result.get("corpse_created", false)):
		return true
	for event_value in array_or_empty(host.call("_interaction_result_events", result)):
		var event: Dictionary = dictionary_or_empty(event_value)
		match str(event.get("kind", "")):
			"actor_defeated", "corpse_created", "interaction_succeeded", "scene_transition", "door_toggled", "door_auto_opened", "container_opened":
				return true
	return false


func turn_action_runner_is_structural_refresh_boundary(runner_snapshot: Dictionary) -> bool:
	if bool(runner_snapshot.get("active", false)) or bool(runner_snapshot.get("presentation_active", false)):
		return false
	var pending_kind := str(runner_snapshot.get("pending_kind", ""))
	if not pending_kind.is_empty():
		return false
	var action_kind := str(runner_snapshot.get("action_kind", ""))
	return action_kind in ["interact", "attack"]


func runner_interaction_result(step_result: Dictionary, runner_snapshot: Dictionary) -> Dictionary:
	if str(runner_snapshot.get("action_kind", "")) != "interact":
		return {}
	var pending_result: Dictionary = dictionary_or_empty(step_result.get("pending_result", {}))
	if is_final_interaction_result(pending_result):
		return pending_result
	if is_final_interaction_result(step_result):
		return step_result
	return {}


func is_final_interaction_result(result: Dictionary) -> bool:
	if result.is_empty() or not bool(result.get("success", false)):
		return false
	return bool(result.get("consumed_target", false)) \
		or result.has("dialogue_id") \
		or result.has("container") \
		or result.has("context_snapshot") \
		or bool(result.get("defeated", false)) \
		or bool(result.get("interaction_completed", false))


func runner_step_should_continue_crafting_queue(step_result: Dictionary, runner_snapshot: Dictionary) -> bool:
	if not ["wait", "craft"].has(str(runner_snapshot.get("action_kind", ""))):
		return false
	if not bool(step_result.get("success", false)):
		return false
	var pending_result: Dictionary = dictionary_or_empty(step_result.get("pending_result", {}))
	if pending_result.is_empty():
		return false
	if bool(host.call("_wait_result_resumed_active_crafting_queue", step_result)):
		return true
	if str(runner_snapshot.get("action_kind", "")) != "craft":
		return false
	var resumed: Dictionary = dictionary_or_empty(pending_result.get("resumed_pending_crafting", {}))
	if resumed.is_empty():
		return false
	var command: Dictionary = dictionary_or_empty(resumed.get("command", {}))
	return bool(command.get("crafting_queue_active", false))


func player_command_rejection(action: String) -> Dictionary:
	var modal_name := str(host.call("_panel_modal_blocker_name"))
	var result: Dictionary = dictionary_or_empty(host.player_command_blocker.call(
		"player_command_rejection",
		action,
		host.is_observe_mode_enabled(),
		modal_name,
		bool(host.call("_world_action_presenter_blocks_input")),
		host.gameplay_input_blocker_snapshot()
	))
	if not result.is_empty():
		host.refresh_hud(host.current_interaction_prompt())
	return result


func observe_command_rejected(action: String) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.player_command_blocker.call("observe_command_rejected", action, host.is_observe_mode_enabled()))
	host.refresh_hud(host.current_interaction_prompt())
	return result


func action_presenter_command_rejected(action: String) -> Dictionary:
	var blocker: Dictionary = host.gameplay_input_blocker_snapshot()
	var result: Dictionary = dictionary_or_empty(host.player_command_blocker.call("action_presenter_command_rejected", action, blocker))
	host.refresh_hud(host.current_interaction_prompt())
	return result


func ui_modal_command_rejected(action: String, modal_name: String) -> Dictionary:
	var blocker: Dictionary = host.gameplay_input_blocker_snapshot()
	var result: Dictionary = dictionary_or_empty(host.player_command_blocker.call("ui_modal_command_rejected", action, modal_name, blocker))
	host.refresh_hud(host.current_interaction_prompt())
	return result


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
