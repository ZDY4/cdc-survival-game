extends RefCounted

var host


func configure(p_host) -> void:
	host = p_host


func finish_world_action_presentations() -> Dictionary:
	var result: Dictionary = {}
	if host.turn_action_runner != null and host.turn_action_runner.has_method("snapshot"):
		var runner: Dictionary = dictionary_or_empty(host.turn_action_runner_snapshot())
		if bool(runner.get("active", false)) or bool(runner.get("presentation_active", false)):
			result = dictionary_or_empty(host.drain_turn_action_runner())
			result["reason"] = "finish_world_action_presentations"
	if host.world_action_flow_controller != null and host.world_action_flow_controller.has_method("finish_active_presentations"):
		var presenter_result: Dictionary = dictionary_or_empty(host.world_action_flow_controller.call("finish_active_presentations"))
		if result.is_empty() or bool(presenter_result.get("active", false)) or int(presenter_result.get("finished_count", 0)) > 0:
			result = presenter_result
	elif result.is_empty():
		return dictionary_or_empty(host.world_action_presenter_snapshot())
	var applied_refresh := apply_pending_world_action_final_refresh("presenter_finished")
	if not apply_pending_world_action_ui("presenter_finished") and not applied_refresh:
		host.refresh_hud(host.current_interaction_prompt())
	return result


func apply_interaction_execution_result(result: Dictionary, executed_target: Dictionary) -> void:
	var presentation_result: Dictionary = interaction_world_action_result(result, executed_target)
	var followup: Dictionary = dictionary_or_empty(host.interaction_action_controller.call("execution_followup", result, executed_target))
	host.ui_feedback_state_controller.call("apply_interaction_followup", followup)
	var stage_panel_to_open := str(followup.get("stage_panel", ""))
	var final_world_result: Dictionary = build_interaction_final_world_result()
	var presenter_result: Dictionary = dictionary_or_empty(host.world_action_flow_controller.call("present_result", host, world_container_node(), presentation_result, host.world_result))
	var presenter_active := bool(presenter_result.get("active", false))
	if presenter_active:
		queue_deferred_world_refresh(final_world_result, dictionary_or_empty(result.get("prompt", {})), presentation_result, "interaction_final_refresh", true)
	else:
		apply_interaction_final_world_result(final_world_result, presentation_result)
	var deferred_ui := false
	if not stage_panel_to_open.is_empty():
		deferred_ui = queue_or_open_stage_panel_after_world_action(stage_panel_to_open, presentation_result)
	elif queue_or_refresh_all_panels_after_world_action(presentation_result):
		deferred_ui = true
	if deferred_ui:
		host.refresh_hud(dictionary_or_empty(result.get("prompt", {})))
	else:
		host.refresh_all_panels(dictionary_or_empty(result.get("prompt", {})))


func build_interaction_final_world_result() -> Dictionary:
	if host.runtime_refresh_controller == null or host.simulation == null:
		return host.world_result.duplicate(true)
	var built: Dictionary = dictionary_or_empty(host.runtime_refresh_controller.call("build_world_result_from_snapshot", host.simulation.world_runtime_view(), "interaction_final_refresh"))
	if bool(built.get("ok", false)):
		return dictionary_or_empty(built.get("world_result", {})).duplicate(true)
	push_error("交互最终地图快照构建失败: %s" % str(built.get("error", built.get("reason", "unknown"))))
	return host.world_result.duplicate(true)


func apply_interaction_final_world_result(final_world_result: Dictionary, presentation_result: Dictionary) -> void:
	host.runtime_scene_coordinator.call("apply_existing_runtime_world_result", final_world_result, "interaction_final_refresh")
	host.runtime_scene_coordinator.call("apply_runtime_scene_refresh", true, {}, {
		"present_world_action": false,
		"command_result": presentation_result,
		"source": "interaction_final_refresh",
	})


func interaction_world_action_result(result: Dictionary, executed_target: Dictionary) -> Dictionary:
	var output: Dictionary = result.duplicate(true)
	var events: Array = interaction_result_events(output)
	if not interaction_events_include_success(events):
		var payload: Dictionary = interaction_success_payload_for_presentation(output, executed_target)
		if not payload.is_empty():
			events.append({"kind": "interaction_succeeded", "payload": payload})
	if not events.is_empty():
		output["events"] = events.duplicate(true)
	return output


func interaction_result_events(result: Dictionary) -> Array:
	var events: Array = []
	for source in [
		result.get("events", []),
		result.get("emitted_events", []),
		dictionary_or_empty(result.get("runtime_snapshot_delta", {})).get("events", []),
		dictionary_or_empty(result.get("pending_result", {})).get("events", []),
		dictionary_or_empty(result.get("result", {})).get("events", []),
		dictionary_or_empty(dictionary_or_empty(result.get("result", {})).get("runtime_snapshot_delta", {})).get("events", []),
	]:
		for event_value in array_or_empty(source):
			var event: Dictionary = dictionary_or_empty(event_value)
			if not event.is_empty():
				events.append(event.duplicate(true))
	return events


func interaction_events_include_success(events: Array) -> bool:
	for event_value in events:
		var event: Dictionary = dictionary_or_empty(event_value)
		if str(event.get("kind", "")) == "interaction_succeeded":
			return true
	return false


func interaction_success_payload_for_presentation(result: Dictionary, executed_target: Dictionary) -> Dictionary:
	if not bool(result.get("success", false)):
		return {}
	var prompt: Dictionary = dictionary_or_empty(result.get("prompt", {}))
	var target: Dictionary = dictionary_or_empty(prompt.get("target", {}))
	if target.is_empty():
		target = executed_target.duplicate(true)
	var option_id := str(result.get("option_id", prompt.get("primary_option_id", "")))
	var option: Dictionary = interaction_prompt_option(prompt, option_id)
	var target_id: Variant = interaction_target_id_for_presentation(result, target)
	var target_name := str(prompt.get("target_name", target.get("display_name", ""))).strip_edges()
	if target_name.is_empty():
		target_name = str(target_id).strip_edges()
	return {
		"actor_id": int(result.get("actor_id", host.runtime_scene_coordinator.call("player_actor_id"))),
		"target_id": target_id,
		"target_type": str(target.get("target_type", "")),
		"target_name": target_name,
		"target_grid": interaction_target_grid_for_presentation(target),
		"option_id": str(option.get("id", option_id)),
		"option_kind": str(option.get("kind", result.get("kind", "interact"))),
		"option_name": str(option.get("display_name", "")),
	}


func interaction_prompt_option(prompt: Dictionary, option_id: String) -> Dictionary:
	for option_value in array_or_empty(prompt.get("options", [])):
		var option: Dictionary = dictionary_or_empty(option_value)
		if option_id.is_empty() or str(option.get("id", "")) == option_id:
			return option.duplicate(true)
	return {}


func interaction_target_id_for_presentation(result: Dictionary, target: Dictionary) -> Variant:
	if result.has("target_id"):
		return result.get("target_id")
	if target.has("target_id"):
		return target.get("target_id")
	if target.has("actor_id"):
		return target.get("actor_id")
	return ""


func interaction_target_grid_for_presentation(target: Dictionary) -> Dictionary:
	for key in ["grid_position", "anchor", "grid"]:
		var grid: Dictionary = dictionary_or_empty(target.get(key, {}))
		if not grid.is_empty():
			return grid.duplicate(true)
	var cells: Array = array_or_empty(target.get("cells", []))
	if not cells.is_empty():
		return dictionary_or_empty(cells[0]).duplicate(true)
	return {}


func open_stage_panel_from_interaction(panel_id: String) -> void:
	if host.hud_root == null or not ["crafting"].has(panel_id):
		return
	host.hud_root.open_stage_panel(panel_id)


func queue_or_open_stage_panel_after_world_action(panel_id: String, result: Dictionary) -> bool:
	if panel_id.is_empty():
		return false
	if world_action_presenter_blocks_input():
		host.world_action_flow_controller.call("queue_open_stage_panel", panel_id, result, dictionary_or_empty(result.get("prompt", {})))
		return true
	open_stage_panel_from_interaction(panel_id)
	return false


func queue_or_refresh_all_panels_after_world_action(result: Dictionary) -> bool:
	if not world_action_presenter_blocks_input():
		return false
	host.world_action_flow_controller.call("queue_refresh_all_panels", result, dictionary_or_empty(result.get("prompt", {})))
	return true


func process_world_action_queue_completion() -> void:
	if host.world_action_flow_controller == null:
		return
	host.world_action_flow_controller.call("process_completion")


func world_action_presenter_blocks_input() -> bool:
	var presenter_blocks := host.world_action_flow_controller != null and bool(host.world_action_flow_controller.call("blocks_input"))
	var runner: Dictionary = dictionary_or_empty(host.turn_action_runner_snapshot())
	return presenter_blocks or bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))


func queue_deferred_world_refresh(final_world_result: Dictionary, selected_prompt: Dictionary, command_result: Dictionary, source: String, render_world: bool = true) -> void:
	host.world_action_flow_controller.call("queue_deferred_world_refresh", final_world_result, selected_prompt, command_result, source, render_world)


func apply_pending_world_action_final_refresh(trigger: String, pending_refresh: Dictionary = {}) -> bool:
	if pending_refresh.is_empty() and host.world_action_flow_controller != null:
		pending_refresh = dictionary_or_empty(host.world_action_flow_controller.call("take_pending_final_refresh"))
	if pending_refresh.is_empty():
		return false
	var refresh: Dictionary = dictionary_or_empty(host.runtime_refresh_controller.call("apply_pending_final_refresh", host.simulation, host.interaction_controller, pending_refresh, "world refresh failed"))
	host.world_result = dictionary_or_empty(refresh.get("world_result", {}))
	if not bool(refresh.get("ok", false)):
		return false
	if bool(refresh.get("sync_observed_level", false)):
		host.runtime_view_state_controller.call("sync_observed_level_to_map", host.world_result)
	host.runtime_scene_coordinator.call("apply_runtime_scene_refresh", bool(refresh.get("render_world", true)))
	var completion: Dictionary = dictionary_or_empty(host.world_action_flow_controller.call("complete_final_refresh", pending_refresh, refresh, trigger))
	if bool(completion.get("refresh_all_panels", false)):
		host.refresh_all_panels(dictionary_or_empty(completion.get("prompt", {})))
	return true


func deferred_world_refresh_public_snapshot(source: Dictionary) -> Dictionary:
	return dictionary_or_empty(host.world_action_flow_controller.call("deferred_world_refresh_public_snapshot", source))


func apply_pending_world_action_ui(trigger: String, pending_ui: Dictionary = {}) -> bool:
	if pending_ui.is_empty() and host.world_action_flow_controller != null:
		pending_ui = dictionary_or_empty(host.world_action_flow_controller.call("take_pending_ui"))
	if pending_ui.is_empty():
		return false
	if str(pending_ui.get("kind", "")) == "open_stage_panel":
		open_stage_panel_from_interaction(str(pending_ui.get("panel_id", "")))
	if bool(pending_ui.get("refresh_all_panels", false)) or str(pending_ui.get("kind", "")) == "refresh_all_panels":
		host.refresh_all_panels(dictionary_or_empty(pending_ui.get("prompt", {})))
	host.world_action_flow_controller.call("mark_deferred_ui_applied", pending_ui, trigger)
	return true


func present_world_action(command_result: Dictionary) -> void:
	host.world_action_flow_controller.call("present_result", host, world_container_node(), command_result, host.world_result)


func connect_world_action_flow_signals() -> void:
	if host.world_action_flow_controller == null:
		return
	var final_callable := Callable(self, "on_world_action_final_refresh_ready")
	if not host.world_action_flow_controller.is_connected("final_refresh_ready", final_callable):
		host.world_action_flow_controller.connect("final_refresh_ready", final_callable)
	var ui_callable := Callable(self, "on_world_action_deferred_ui_ready")
	if not host.world_action_flow_controller.is_connected("deferred_ui_ready", ui_callable):
		host.world_action_flow_controller.connect("deferred_ui_ready", ui_callable)


func on_world_action_final_refresh_ready(pending_refresh: Dictionary) -> void:
	apply_pending_world_action_final_refresh("presenter_finished", pending_refresh)


func on_world_action_deferred_ui_ready(pending_ui: Dictionary) -> void:
	apply_pending_world_action_ui("presenter_finished", pending_ui)


func record_world_action_queue_presented(command_result: Dictionary, presenter_result: Dictionary) -> void:
	host.world_action_flow_controller.call("record_presented", command_result, presenter_result)


func record_world_action_queue_finished(finish_result: Dictionary) -> void:
	host.world_action_flow_controller.call("record_finished", finish_result)


func world_action_command_kind(command_result: Dictionary) -> String:
	return str(host.world_action_flow_controller.call("command_kind", command_result))


func world_action_event_count(command_result: Dictionary) -> int:
	return int(host.world_action_flow_controller.call("event_count", command_result))


func world_action_events_from_result(command_result: Dictionary) -> Array:
	return array_or_empty(host.world_action_flow_controller.call("events_from_result", command_result))


func world_container_node() -> Node3D:
	return host.runtime_scene_coordinator.call("world_container_node") as Node3D


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
