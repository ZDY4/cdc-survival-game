extends RefCounted

var host


func configure(p_host) -> void:
	host = p_host


func toggle_controls_hint() -> Dictionary:
	if host.hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	var result: Dictionary = dictionary_or_empty(host.hud_root.toggle_controls_hint())
	host.refresh_hud(host.current_interaction_prompt())
	host.call("_play_hud_shortcut_audio", "ui_button_pressed", "ControlsHintShortcut", "keyboard_shortcut", "toggle_controls_hint", {
		"value": "on" if bool(result.get("visible", false)) else "off",
	})
	return result


func controls_hint_visible() -> bool:
	return host.hud_root != null and bool(host.hud_root.controls_hint_visible())


func toggle_debug_console() -> Dictionary:
	if host.hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	var result: Dictionary = dictionary_or_empty(host.hud_root.toggle_debug_console())
	host.refresh_hud(host.current_interaction_prompt())
	host.call("_play_hud_shortcut_audio", "ui_button_pressed", "DebugConsoleShortcut", "keyboard_shortcut", "toggle_debug_console", {
		"value": "open" if bool(result.get("visible", false)) else "close",
	})
	return result


func close_debug_console() -> Dictionary:
	if host.hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	var result: Dictionary = dictionary_or_empty(host.hud_root.close_debug_console())
	host.refresh_hud(host.current_interaction_prompt())
	return result


func is_debug_console_open() -> bool:
	return host.hud_root != null and bool(host.hud_root.is_debug_console_open())


func debug_console_snapshot() -> Dictionary:
	var permission: Dictionary = host.debug_runtime_controller.permission_snapshot(host)
	if host.hud_root != null:
		return dictionary_or_empty(host.hud_root.debug_console_snapshot(permission))
	return {
		"visible": false,
		"history": [],
		"history_count": 0,
		"suggestions": [],
		"suggestion_count": 0,
		"input_text": "",
		"permission": permission,
	}


func clear_debug_console_history() -> Dictionary:
	if host.hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	return dictionary_or_empty(host.hud_root.clear_debug_console_history())


func reset_debug_view_state() -> void:
	host.active_trade_target = {}
	host.active_trade_feedback = {}
	host.active_container_feedback = {}
	host.active_character_feedback = {}
	host.active_inventory_feedback = {}
	host.active_skill_targeting = {}
	host.active_skill_target_preview = {}
	if host.runtime_view_state_controller != null:
		host.runtime_view_state_controller.focused_actor_id = 0
		host.runtime_view_state_controller.observed_map_level = 0
	if host.runtime_control_state_controller != null:
		host.runtime_control_state_controller.auto_tick_enabled = false
		host.runtime_control_state_controller.auto_tick_elapsed_sec = 0.0


func submit_debug_console_command(command_text: String) -> Dictionary:
	var command := command_text.strip_edges()
	var result: Dictionary = execute_debug_console_command(command)
	if host.hud_root != null:
		host.hud_root.set_debug_console_result(command, result)
	host.refresh_all_panels(host.current_interaction_prompt())
	host.call("_play_hud_shortcut_audio", "ui_button_pressed", "DebugConsoleInput", "text_submit", "submit_debug_console_command", {
		"value": command,
		"reason": str(result.get("reason", "")),
	})
	return result


func execute_debug_console_command(command: String) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.debug_runtime_controller.execute(host, command))
	return apply_debug_console_intent(result)


func apply_debug_console_intent(result: Dictionary) -> Dictionary:
	var intent := str(result.get("debug_intent", ""))
	if intent.is_empty():
		return result
	var output := result.duplicate(true)
	output.erase("debug_intent")
	match intent:
		"toggle_fps_panel":
			if not host.has_method("toggle_debug_panel"):
				return {"success": false, "reason": "debug_panel_missing", "message": "debug panel missing"}
			var panel_result: Dictionary = host.toggle_debug_panel()
			return merge_debug_console_intent_result(output, panel_result, "fps panel=%s" % ("on" if bool(panel_result.get("visible", false)) else "off"))
		"cycle_debug_overlay":
			if not host.has_method("cycle_debug_overlay_mode"):
				return {"success": false, "reason": "debug_overlay_missing", "message": "debug overlay missing"}
			var overlay_result: Dictionary = host.cycle_debug_overlay_mode()
			return merge_debug_console_intent_result(output, overlay_result, "overlay=%s" % str(overlay_result.get("mode", "")))
		"toggle_observe_mode":
			if not host.has_method("toggle_observe_mode"):
				return {"success": false, "reason": "observe_mode_missing", "message": "observe mode missing"}
			var observe_result: Dictionary = host.toggle_observe_mode()
			var observe_mode := bool(observe_result.get("observe_mode", false))
			return merge_debug_console_intent_result(output, observe_result, "observe=%s" % ("on" if observe_mode else "off"))
		"clear_console":
			if not host.has_method("clear_debug_console_history"):
				return {"success": false, "reason": "debug_console_missing", "message": "debug console missing"}
			var clear_result: Dictionary = host.clear_debug_console_history()
			return merge_debug_console_intent_result(output, clear_result, "console cleared" if bool(clear_result.get("success", false)) else "debug console missing")
	return {"success": false, "reason": "unknown_debug_intent", "debug_intent": intent, "message": "unknown debug intent: %s" % intent}


func merge_debug_console_intent_result(base_result: Dictionary, action_result: Dictionary, message: String) -> Dictionary:
	var output := base_result.duplicate(true)
	for key in action_result.keys():
		output[key] = action_result[key]
	output["success"] = bool(action_result.get("success", output.get("success", false)))
	output["message"] = message
	return output


func controls_hint_snapshot() -> Dictionary:
	if host.hud_root != null:
		return dictionary_or_empty(host.hud_root.controls_hint_snapshot())
	return {"visible": false, "line_count": 0, "lines": []}


func toggle_debug_panel() -> Dictionary:
	if host.hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	var result: Dictionary = dictionary_or_empty(host.hud_root.toggle_debug_panel())
	host.refresh_hud(host.current_interaction_prompt())
	host.call("_play_hud_shortcut_audio", "ui_button_pressed", "DebugPanelShortcut", "keyboard_shortcut", "toggle_debug_panel", {
		"value": "open" if bool(result.get("visible", false)) else "close",
	})
	return result


func is_debug_panel_open() -> bool:
	return host.hud_root != null and bool(host.hud_root.is_debug_panel_open())


func debug_panel_snapshot() -> Dictionary:
	if host.hud_root != null:
		return dictionary_or_empty(host.hud_root.debug_panel_snapshot())
	return {"visible": false, "line_count": 0, "lines": []}


func cycle_debug_overlay_mode() -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.debug_runtime_controller.call("cycle_debug_overlay_mode"))
	host.refresh_world_visuals(false)
	host.refresh_hud(host.current_interaction_prompt())
	host.call("_play_hud_shortcut_audio", "ui_option_selected", "DebugOverlayShortcut", "keyboard_shortcut", "cycle_debug_overlay", {
		"value": current_debug_overlay_mode(),
	})
	return result


func current_debug_overlay_mode() -> String:
	return str(host.debug_runtime_controller.call("current_debug_overlay_mode"))


func debug_overlay_snapshot() -> Dictionary:
	if host.world_root != null and host.world_root.has_method("debug_overlay_snapshot"):
		return dictionary_or_empty(host.world_root.call("debug_overlay_snapshot"))
	return {"active": false, "mode": "off", "cell_count": 0}


func toggle_auto_tick() -> Dictionary:
	if host.has_active_dialogue() or host.gameplay_input_blocked_by_ui():
		return dictionary_or_empty(host.runtime_control_state_controller.call("toggle_auto_tick", true))
	var result: Dictionary = dictionary_or_empty(host.runtime_control_state_controller.call("toggle_auto_tick", false))
	return apply_runtime_control_result(result)


func is_auto_tick_enabled() -> bool:
	return bool(host.runtime_control_state_controller.auto_tick_enabled) if host.runtime_control_state_controller != null else false


func is_observe_mode_enabled() -> bool:
	return bool(host.runtime_control_state_controller.observe_mode_enabled) if host.runtime_control_state_controller != null else false


func can_issue_player_commands() -> bool:
	return not is_observe_mode_enabled() and not bool(host.call("_world_action_presenter_blocks_input")) and str(host.call("_panel_modal_blocker_name")).is_empty()


func toggle_observe_mode() -> Dictionary:
	return set_observe_mode(not is_observe_mode_enabled())


func set_observe_mode(enabled: bool) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.runtime_control_state_controller.call("set_observe_mode", enabled, host.gameplay_input_blocked_by_ui()))
	return apply_runtime_control_result(result)


func toggle_observe_playback() -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.runtime_control_state_controller.call("toggle_observe_playback", host.has_active_dialogue() or host.gameplay_input_blocked_by_ui()))
	return apply_runtime_control_result(result)


func cycle_observe_speed() -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.runtime_control_state_controller.call("cycle_observe_speed"))
	return apply_runtime_control_result(result)


func set_observe_speed(speed_id: String) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.runtime_control_state_controller.call("set_observe_speed", speed_id))
	return apply_runtime_control_result(result)


func cycle_info_panel(direction: int) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.runtime_control_state_controller.call("cycle_info_panel", direction))
	return apply_runtime_control_result(result)


func apply_runtime_control_result(result: Dictionary) -> Dictionary:
	if not bool(result.get("success", false)):
		return result
	if bool(result.get("refresh_hud", false)):
		host.refresh_hud(host.current_interaction_prompt())
	var audio: Dictionary = dictionary_or_empty(result.get("hud_audio", {}))
	if not audio.is_empty():
		host.call(
			"_play_hud_shortcut_audio",
			str(audio.get("event_kind", "")),
			str(audio.get("control_name", "")),
			str(audio.get("control_kind", "")),
			str(audio.get("action", "")),
			dictionary_or_empty(audio.get("payload", {}))
		)
	return result


func current_info_panel_page() -> Dictionary:
	return dictionary_or_empty(host.runtime_control_state_controller.call("current_info_panel_page"))


func info_panel_snapshot() -> Dictionary:
	return dictionary_or_empty(host.runtime_control_state_controller.call("info_panel_snapshot"))


func runtime_control_snapshot() -> Dictionary:
	var snapshot: Dictionary = dictionary_or_empty(host.runtime_control_state_controller.call("runtime_control_snapshot"))
	snapshot["world_time"] = host.runtime_world_time_snapshot()
	snapshot["map_level"] = host.map_level_snapshot()
	snapshot["focused_actor"] = host.focused_actor_snapshot()
	snapshot["ui_blocker"] = host.gameplay_input_blocker_name()
	snapshot["ui_blocker_snapshot"] = host.gameplay_input_blocker_snapshot()
	snapshot["modal_stack"] = host.modal_stack_snapshot()
	snapshot["menu_state"] = host.menu_state_snapshot()
	snapshot["ui_theme"] = host.ui_theme_snapshot()
	snapshot["ui_layer_stack"] = host.ui_layer_stack_snapshot()
	snapshot["context_menu"] = host.context_menu_snapshot()
	snapshot["controls_hint"] = controls_hint_snapshot()
	snapshot["debug_console"] = debug_console_snapshot()
	snapshot["debug_panel"] = debug_panel_snapshot()
	snapshot["hover"] = runtime_hover_snapshot()
	snapshot["tooltip"] = host.hover_tooltip_snapshot()
	snapshot["tooltip_render"] = tooltip_render_snapshot()
	snapshot["hotbar_hit_test"] = host.hotbar_hit_test_snapshot()
	snapshot["drag"] = host.drag_state_snapshot()
	snapshot["drag_preview_render"] = drag_preview_render_snapshot()
	snapshot["selection_debug"] = runtime_selection_debug_snapshot()
	snapshot["action_presenter"] = world_action_presenter_snapshot()
	snapshot["world_action_queue"] = world_action_queue_snapshot()
	snapshot["turn_action_runner"] = host.turn_action_runner_snapshot()
	snapshot["latest_action_chain"] = host.latest_action_chain.duplicate(true)
	snapshot["actor_view"] = actor_view_snapshot()
	snapshot["camera_follow"] = camera_follow_snapshot()
	snapshot["world_render_policy"] = world_render_policy_snapshot()
	snapshot["structural_refresh_boundary"] = host.structural_refresh_boundary_snapshot()
	snapshot["ai_debug"] = ai_debug_snapshot()
	snapshot["debug_overlay"] = debug_overlay_snapshot()
	snapshot["runtime_refresh"] = host.runtime_refresh_report_snapshot()
	snapshot["audio_feedback"] = audio_feedback_snapshot()
	snapshot["performance"] = runtime_performance_snapshot()
	snapshot["skill_targeting"] = host.active_skill_targeting_snapshot()
	snapshot["player_command_authority_audit"] = player_command_authority_audit_snapshot()
	return snapshot


func tooltip_render_snapshot() -> Dictionary:
	var controller: RefCounted = host.call("_ui_overlay_controller") as RefCounted
	if controller == null:
		return {"active": false}
	return dictionary_or_empty(controller.call("tooltip_render_snapshot"))


func drag_preview_render_snapshot() -> Dictionary:
	var controller: RefCounted = host.call("_ui_overlay_controller") as RefCounted
	if controller == null:
		return {"active": false}
	return dictionary_or_empty(controller.call("drag_preview_render_snapshot"))


func player_command_authority_audit_snapshot() -> Dictionary:
	return dictionary_or_empty(host.player_command_authority_audit.call("snapshot", host.debug_runtime_controller, host))


func debug_console_mutation_authority_audit() -> Dictionary:
	return dictionary_or_empty(host.player_command_authority_audit.call("debug_console_mutation_authority_audit", host.debug_runtime_controller, host))


func ai_debug_snapshot() -> Dictionary:
	return dictionary_or_empty(host.ai_debug_snapshot_builder.call("snapshot", host.simulation, host.focused_actor_snapshot()))


func runtime_world_time_snapshot() -> Dictionary:
	return dictionary_or_empty(host.world_time_snapshot_builder.call("snapshot", host.simulation))


func world_action_presenter_snapshot() -> Dictionary:
	if host.world_action_flow_controller == null:
		return {"active": false, "kind": "missing"}
	return dictionary_or_empty(host.world_action_flow_controller.call("presenter_snapshot"))


func world_action_queue_snapshot() -> Dictionary:
	if host.world_action_flow_controller == null:
		return {"active": false, "state": "idle", "sequence": 0}
	return dictionary_or_empty(host.world_action_flow_controller.call("snapshot"))


func actor_view_snapshot() -> Dictionary:
	if host.actor_view_controller == null or not host.actor_view_controller.has_method("snapshot"):
		return {"active": false}
	return dictionary_or_empty(host.actor_view_controller.call("snapshot"))


func camera_follow_snapshot() -> Dictionary:
	var input_snapshot: Dictionary = {}
	if host.runtime_input_controller != null and host.runtime_input_controller.has_method("camera_follow_snapshot"):
		input_snapshot = dictionary_or_empty(host.runtime_input_controller.call("camera_follow_snapshot"))
	else:
		input_snapshot = {"has_camera": false, "reason": "runtime_input_missing"}
	var world_snapshot: Dictionary = {}
	if host.world_root != null and host.world_root.has_method("camera_follow_snapshot"):
		world_snapshot = dictionary_or_empty(host.world_root.call("camera_follow_snapshot"))
	var output: Dictionary = input_snapshot.duplicate(true)
	output["input_controller"] = input_snapshot.duplicate(true)
	output["world_camera"] = world_snapshot.duplicate(true)
	if not world_snapshot.is_empty():
		output["has_world_camera"] = bool(world_snapshot.get("has_camera", false))
		output["world_follow_source"] = str(world_snapshot.get("follow_source", ""))
		output["world_follow_actor_id"] = int(world_snapshot.get("follow_actor_id", 0))
		output["world_follow_node_active"] = bool(world_snapshot.get("follow_node_active", false))
		output["world_follow_node_instance_id"] = int(world_snapshot.get("follow_node_instance_id", 0))
	return output


func world_render_policy_snapshot() -> Dictionary:
	var runner: Dictionary = host.turn_action_runner_snapshot()
	var queue: Dictionary = world_action_queue_snapshot()
	var performance: Dictionary = runtime_performance_snapshot()
	var runner_active := bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))
	var queue_active := bool(queue.get("active", false))
	return {
		"render_sequence": int(performance.get("render_sequence", 0)),
		"last_render_count": int(performance.get("render_count", 0)),
		"last_render_counts": dictionary_or_empty(performance.get("render_counts", {})).duplicate(true),
		"runner_active": runner_active,
		"runner_action_kind": str(runner.get("action_kind", "")),
		"runner_phase": str(runner.get("phase", "")),
		"world_action_queue_active": queue_active,
		"ordinary_action_render_world": false,
		"structural_render_allowed": not runner_active,
		"policy": "runner_actions_update_actor_view_without_full_world_render" if runner_active else "idle_structural_refresh_allowed",
	}


func audio_feedback_snapshot() -> Dictionary:
	if host.audio_feedback_controller == null or not host.audio_feedback_controller.has_method("snapshot"):
		return {"enabled": false, "reason": "audio_feedback_missing"}
	return dictionary_or_empty(host.audio_feedback_controller.call("snapshot"))


func runtime_performance_snapshot() -> Dictionary:
	return dictionary_or_empty(host.runtime_performance_tracker.call("snapshot", last_pathfinding_time_ms(), last_pathfinding_visited_cell_count()))


func runtime_hover_snapshot() -> Dictionary:
	if host.runtime_input_controller != null and host.runtime_input_controller.has_method("hover_state_snapshot"):
		return dictionary_or_empty(host.runtime_input_controller.hover_state_snapshot())
	return {"active": false}


func runtime_selection_debug_snapshot() -> Dictionary:
	if host.runtime_input_controller != null and host.runtime_input_controller.has_method("selection_debug_snapshot"):
		return dictionary_or_empty(host.runtime_input_controller.selection_debug_snapshot())
	return {"active": false, "kind": "", "hovered_grid": {}, "blocker_name": "", "prompt": {"has_prompt": false}}


func update_runtime_performance(delta: float) -> void:
	host.runtime_performance_tracker.call("update_process", delta)


func last_pathfinding_time_ms() -> float:
	var hover: Dictionary = runtime_hover_snapshot()
	var move_preview: Dictionary = dictionary_or_empty(hover.get("move_preview", {}))
	return float(move_preview.get("pathfinding_time_ms", 0.0))


func last_pathfinding_visited_cell_count() -> int:
	var hover: Dictionary = runtime_hover_snapshot()
	var move_preview: Dictionary = dictionary_or_empty(hover.get("move_preview", {}))
	return int(move_preview.get("visited_cell_count", 0))


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
