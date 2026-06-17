extends RefCounted

const HUD_ROOT_SCENE = preload("res://scenes/ui/hud_root.tscn")

var host


func configure(p_host) -> void:
	host = p_host


func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	if host.hud_root == null:
		return
	host.call("_process_audio_feedback")
	host.runtime_performance_tracker.call("mark_hud_refresh")
	if selected_prompt.is_empty():
		selected_prompt = host.current_interaction_prompt()
	host.hud_root.refresh_hud(selected_prompt)


func refresh_panel(panel_id: String, feedback: Dictionary = {}) -> void:
	if host.hud_root == null:
		return
	host.hud_root.refresh_panel(panel_id, feedback)


func refresh_trade_panel() -> void:
	if host.hud_root == null:
		return
	if not bool(host.call("_active_trade_target_available")):
		host.close_trade_panel("target_unavailable")
		return
	host.hud_root.refresh_panel("trade", ui_feedback_payload())


func refresh_container_panel() -> void:
	if host.hud_root == null:
		return
	close_stale_container_session()
	host.hud_root.refresh_panel("container", ui_feedback_payload())


func refresh_all_panels(selected_prompt: Dictionary = {}) -> void:
	if host.hud_root == null:
		return
	if not bool(host.call("_active_trade_target_available")):
		host.close_trade_panel("target_unavailable")
	close_stale_container_session()
	host.call("_process_audio_feedback")
	host.runtime_performance_tracker.call("mark_hud_refresh")
	if selected_prompt.is_empty():
		selected_prompt = host.current_interaction_prompt()
	host.hud_root.refresh_all(selected_prompt, ui_feedback_payload())


func close_stale_container_session() -> void:
	if host.simulation == null:
		return
	var close_reason := str(host.call("_active_container_close_reason"))
	if close_reason.is_empty():
		return
	host.active_container_feedback = {}
	host.simulation.close_container(1, close_reason)


func refresh_operation_panels(panel_ids: Array, selected_prompt: Dictionary = {}) -> void:
	if host.hud_root == null:
		return
	host.hud_root.refresh_operation_panels(panel_ids, selected_prompt, ui_feedback_payload())


func toggle_stage_panel(panel_id: String) -> Dictionary:
	if host.hud_root == null:
		return {"success": false, "reason": "panel_controller_missing"}
	if world_action_presenter_blocks_input():
		return dictionary_or_empty(host.call("_action_presenter_command_rejected", "toggle_stage_panel:%s" % panel_id))
	var result: Dictionary = dictionary_or_empty(host.hud_root.toggle_stage_panel(panel_id))
	if bool(result.get("success", false)):
		host.call("_play_ui_audio_feedback", "stage_panel_opened" if bool(result.get("open", false)) else "stage_panel_closed", {
			"panel_id": panel_id,
			"action": "toggle_stage_panel",
		})
		refresh_all_panels(host.current_interaction_prompt())
	return result


func close_stage_panels() -> Dictionary:
	if host.hud_root == null:
		return {"success": false, "reason": "panel_controller_missing"}
	var result: Dictionary = dictionary_or_empty(host.hud_root.close_stage_panels())
	if bool(result.get("success", false)) and bool(result.get("closed", false)):
		host.call("_play_ui_audio_feedback", "stage_panel_closed", {
			"panel_id": str(result.get("panel_id", "stage")),
			"action": "close_stage_panels",
		})
	return result


func any_stage_panel_open() -> bool:
	return host.hud_root != null and host.hud_root.any_stage_panel_open()


func is_settings_open() -> bool:
	return host.hud_root != null and host.hud_root.is_settings_open()


func toggle_settings_panel() -> Dictionary:
	if host.hud_root == null:
		return {"success": false, "reason": "panel_controller_missing"}
	if world_action_presenter_blocks_input():
		return dictionary_or_empty(host.call("_action_presenter_command_rejected", "toggle_settings_panel"))
	var opened := not is_settings_open()
	var result: Dictionary = {}
	if opened:
		result = dictionary_or_empty(host.hud_root.open_settings_panel())
		if bool(result.get("success", false)):
			host.call("_play_ui_audio_feedback", "settings_panel_opened", {
				"panel_id": "settings",
				"action": "open_settings_panel",
			})
	else:
		result = dictionary_or_empty(host.hud_root.close_settings_panel())
		if bool(result.get("success", false)):
			host.call("_play_ui_audio_feedback", "settings_panel_closed", {
				"panel_id": "settings",
				"action": "close_settings_panel",
			})
	if bool(result.get("success", false)):
		result["open"] = opened
		refresh_all_panels(host.current_interaction_prompt())
	return result


func gameplay_input_blocked_by_ui() -> bool:
	var hud_blocker := hud_input_blocker_snapshot()
	var panel_blocked: bool = host.hud_root != null and host.hud_root.gameplay_input_blocked()
	return bool(host.ui_blocker_state_controller.call("gameplay_input_blocked", hud_blocker, panel_blocked, world_action_presenter_blocks_input()))


func gameplay_input_blocker_name() -> String:
	var hud_blocker := hud_input_blocker_snapshot()
	var context_menu: Dictionary = context_menu_snapshot()
	var panel_blocker_name: String = host.hud_root.gameplay_input_blocker_name() if host.hud_root != null else ""
	return str(host.ui_blocker_state_controller.call("blocker_name", hud_blocker, panel_modal_blocker_snapshot(), context_menu, world_action_blocker_snapshot(), panel_blocker_name))


func gameplay_input_blocker_snapshot() -> Dictionary:
	var hud_blocker := hud_input_blocker_snapshot()
	var context_menu: Dictionary = context_menu_snapshot()
	var world_blocks := world_action_presenter_blocks_input()
	var panel_blocker: Dictionary = panel_input_blocker_snapshot()
	var fallback_name := gameplay_input_blocker_name()
	return dictionary_or_empty(host.ui_blocker_state_controller.call("blocker_snapshot", hud_blocker, panel_modal_blocker_snapshot(), context_menu, host.world_action_presenter_snapshot(), world_action_blocker_snapshot(), world_blocks, panel_blocker, fallback_name))


func hud_input_blocker_snapshot() -> Dictionary:
	if host.hud_root != null:
		return dictionary_or_empty(host.hud_root.hud_input_blocker_snapshot(host.is_debug_console_open()))
	return {}


func close_hud_interaction_menu() -> bool:
	var hud_blocker := hud_input_blocker_snapshot()
	if str(hud_blocker.get("name", "")) != "interaction_menu":
		return false
	return host.hud_root != null and host.hud_root.close_hud_interaction_menu()


func show_interaction_menu(screen_position: Vector2, prompt: Dictionary = {}) -> Dictionary:
	if host.hud_root == null:
		return {"success": false, "reason": "hud_root_missing", "visible": false}
	return dictionary_or_empty(host.hud_root.show_interaction_menu(screen_position, prompt))


func hide_interaction_menu() -> Dictionary:
	if host.hud_root == null:
		return {"success": false, "reason": "hud_root_missing", "visible": false}
	return dictionary_or_empty(host.hud_root.hide_interaction_menu())


func is_interaction_menu_open() -> bool:
	return host.hud_root != null and host.hud_root.is_interaction_menu_open()


func panel_modal_blocker_name() -> String:
	var snapshot := panel_modal_blocker_snapshot()
	return str(snapshot.get("name", ""))


func panel_modal_blocker_snapshot() -> Dictionary:
	return dictionary_or_empty(host.ui_blocker_state_controller.call("panel_modal_blocker_snapshot", panel_input_blocker_snapshot()))


func panel_input_blocker_snapshot() -> Dictionary:
	if host.hud_root == null:
		return {}
	return dictionary_or_empty(host.hud_root.gameplay_input_blocker_snapshot())


func world_action_presenter_blocks_input() -> bool:
	var presenter_blocks := host.world_action_flow_controller != null and bool(host.world_action_flow_controller.call("blocks_input"))
	var runner: Dictionary = host.turn_action_runner_snapshot()
	return presenter_blocks or bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))


func world_action_blocker_snapshot() -> Dictionary:
	var presenter: Dictionary = host.world_action_presenter_snapshot()
	if host.world_action_flow_controller != null and bool(host.world_action_flow_controller.call("blocks_input")):
		return {
			"blocked": true,
			"name": "world_action_presenter",
			"kind": "world_action_presenter",
			"source": "world_action_presenter",
			"action_kind": str(presenter.get("kind", "")),
			"phase": str(presenter.get("current_phase", presenter.get("state", ""))),
			"active_count": int(presenter.get("active_count", 0)),
			"sequence": int(presenter.get("sequence", 0)),
			"mouse_blocks_world": true,
			"camera_drag_allowed": true,
		}
	var runner: Dictionary = host.turn_action_runner_snapshot()
	if bool(runner.get("active", false)) or bool(runner.get("presentation_active", false)):
		return {
			"blocked": true,
			"name": "turn_action_runner",
			"kind": "turn_action_runner",
			"source": "turn_action_runner",
			"action_kind": str(runner.get("action_kind", "")),
			"phase": str(runner.get("phase", "")),
			"turn_phase": str(runner.get("turn_phase", "")),
			"actor_id": int(runner.get("actor_id", 0)),
			"presentation_active": bool(runner.get("presentation_active", false)),
			"mouse_blocks_world": true,
			"camera_drag_allowed": true,
		}
	return {}


func modal_stack_snapshot() -> Dictionary:
	if host.hud_root != null:
		return dictionary_or_empty(host.hud_root.modal_stack_snapshot())
	return {"active": false, "count": 0, "top": {}, "stack": []}


func menu_state_snapshot() -> Dictionary:
	var panel_snapshot: Dictionary = {}
	var fallback_priority: Array[String] = ["settings"]
	if host.hud_root != null:
		panel_snapshot = dictionary_or_empty(host.hud_root.menu_state_snapshot()).duplicate(true)
	return dictionary_or_empty(host.ui_blocker_state_controller.call("menu_state_snapshot", panel_snapshot, fallback_priority, modal_stack_snapshot(), context_menu_snapshot(), close_context_snapshot()))


func root_close_priority(panel_priority: Array = []) -> Array[String]:
	return array_of_strings(host.ui_blocker_state_controller.call("root_close_priority", panel_priority, close_context_snapshot()))


func close_context_snapshot() -> Dictionary:
	var pending_state: Dictionary = dictionary_or_empty(host.call("_runtime_pending_state_snapshot"))
	return {
		"hud_blocker": hud_input_blocker_snapshot(),
		"panel_modal": panel_modal_blocker_snapshot(),
		"context_menu": context_menu_snapshot(),
		"world_action_blocks": world_action_presenter_blocks_input(),
		"world_action_blocker": world_action_blocker_snapshot(),
		"skill_targeting_active": not host.active_skill_targeting.is_empty(),
		"selection_active": host.runtime_input_controller != null and host.runtime_input_controller.has_method("has_selection_state") and bool(host.runtime_input_controller.has_selection_state()),
		"has_pending": not dictionary_or_empty(pending_state.get("pending_movement", {})).is_empty() or not dictionary_or_empty(pending_state.get("pending_interaction", {})).is_empty() or not dictionary_or_empty(pending_state.get("pending_crafting", {})).is_empty(),
	}


func ui_theme_snapshot() -> Dictionary:
	if host.hud_root != null:
		return dictionary_or_empty(host.hud_root.ui_theme_snapshot())
	return {"applied": false, "reason": "panel_controller_missing"}


func context_menu_snapshot() -> Dictionary:
	if host.hud_root != null:
		return dictionary_or_empty(host.hud_root.context_menu_snapshot())
	return {"active": false, "count": 0, "top": {}, "menus": []}


func ui_overlay_controller() -> RefCounted:
	return host.hud_root.ui_overlay_render_controller if host.hud_root != null else null


func hover_tooltip_snapshot(control: Control = null) -> Dictionary:
	if host.hud_root != null:
		return dictionary_or_empty(host.hud_root.hover_tooltip_snapshot(host.get_viewport(), control))
	return {
		"active": false,
		"requested_source": "hover",
		"source_name": "",
		"owner_panel": "",
		"text": "",
	}


func hotbar_hit_test_snapshot(screen_position: Vector2 = Vector2(-1.0, -1.0)) -> Dictionary:
	if host.hud_root != null:
		return dictionary_or_empty(host.hud_root.hotbar_hit_test_snapshot(host.get_viewport(), screen_position))
	var position := screen_position
	if position.x < 0.0 or position.y < 0.0:
		var viewport := host.get_viewport()
		position = viewport.get_mouse_position() if viewport != null else Vector2.ZERO
	return {
		"active": false,
		"owner_panel": "hud",
		"target_kind": "",
		"target_id": "",
		"group_id": "",
		"source_path": "",
		"source_name": "",
		"mouse_blocks_world": false,
		"disabled": false,
		"tooltip": "",
		"screen_position": {"x": position.x, "y": position.y},
		"rect": {},
	}


func drag_state_snapshot(data: Variant = {}, hover_target: Control = null) -> Dictionary:
	var drag_data: Dictionary = dictionary_or_empty(data)
	var target: Dictionary = dictionary_or_empty(host.call("_drag_hover_target_snapshot", hover_target, drag_data))
	if host.hud_root != null:
		return dictionary_or_empty(host.hud_root.drag_state_snapshot(host.get_viewport(), drag_data, target))
	return {
		"active": false,
		"kind": "",
		"source": {},
		"target": target,
		"preview": {},
		"payload": {},
	}


func ui_layer_stack_snapshot(drag_data: Variant = {}, drag_hover_target: Control = null, tooltip_control: Control = null) -> Dictionary:
	var blocker: Dictionary = gameplay_input_blocker_snapshot()
	var modal_stack: Dictionary = modal_stack_snapshot()
	var context_menu: Dictionary = context_menu_snapshot()
	var drag: Dictionary = drag_state_snapshot(drag_data, drag_hover_target)
	var tooltip: Dictionary = hover_tooltip_snapshot(tooltip_control)
	return dictionary_or_empty(host.ui_blocker_state_controller.call("layer_stack_snapshot", blocker, modal_stack, context_menu, drag, tooltip))


func setup_tooltip_layer() -> void:
	if host.hud_root != null:
		host.hud_root.setup_tooltip_layer(host)


func update_tooltip_layer() -> void:
	if host.hud_root == null:
		return
	var snapshot: Dictionary = hover_tooltip_snapshot()
	host.hud_root.update_tooltip_layer(snapshot, host)


func hide_tooltip_layer(reason: String) -> void:
	if host.hud_root != null:
		host.hud_root.hide_tooltip_layer(reason)


func render_tooltip_snapshot(snapshot: Dictionary) -> void:
	if host.hud_root != null:
		host.hud_root.render_tooltip_snapshot(snapshot, host)


func setup_drag_preview_layer() -> void:
	if host.hud_root != null:
		host.hud_root.setup_drag_preview_layer(host)


func render_drag_preview_for_snapshot(drag_data: Variant = {}, hover_target: Control = null) -> Dictionary:
	var drag: Dictionary = drag_state_snapshot(drag_data, hover_target)
	if not bool(drag.get("active", false)):
		hide_drag_preview_layer("inactive")
		return host.drag_preview_render_snapshot()
	render_drag_preview_snapshot(drag)
	return host.drag_preview_render_snapshot()


func hide_drag_preview_layer(reason: String) -> void:
	if host.hud_root != null:
		host.hud_root.hide_drag_preview_layer(reason)


func render_drag_preview_snapshot(drag: Dictionary) -> void:
	if host.hud_root != null:
		host.hud_root.render_drag_preview_snapshot(drag, host)


func handle_trade_shortcut(event: InputEventKey) -> bool:
	if host.hud_root == null:
		return false
	return host.hud_root.handle_trade_shortcut(event)


func setup_panels() -> void:
	if host.hud_root == null:
		host.hud_root = HUD_ROOT_SCENE.instantiate()
		host.hud_root.name = "HudRoot"
		host.add_child(host.hud_root)
		if host.hud_root.has_method("configure"):
			host.hud_root.call("configure", host)
	host.hud_root.setup_panels(host.registry, host.simulation, host.world_result, ui_feedback_payload())
	host.panel_controller = host.hud_root.panel_controller
	sync_panel_refs_from_hud_root()
	# 对外保留面板引用，方便既有 smoke 和编辑器入口继续做状态复核。
	host.call("_sync_debug_console_schema")


func ui_feedback_payload() -> Dictionary:
	return {
		"active_trade_target": host.active_trade_target,
		"active_trade_feedback": host.active_trade_feedback,
		"active_container_feedback": host.active_container_feedback,
		"active_character_feedback": host.active_character_feedback,
		"active_inventory_feedback": host.active_inventory_feedback,
	}


func sync_panel_refs_from_hud_root() -> void:
	if host.hud_root == null:
		return
	var refs: Dictionary = dictionary_or_empty(host.hud_root.panel_refs())
	host.hud = refs.get("hud", null) as Control
	host.dialogue_panel = refs.get("dialogue", null) as Control
	host.inventory_panel = refs.get("inventory", null) as Control
	host.trade_panel = refs.get("trade", null) as Control
	host.container_panel = refs.get("container", null) as Control
	host.character_panel = refs.get("character", null) as Control
	host.journal_panel = refs.get("journal", null) as Control
	host.map_panel = refs.get("map", null) as Control
	host.skills_panel = refs.get("skills", null) as Control
	host.crafting_panel = refs.get("crafting", null) as Control
	host.settings_panel = refs.get("settings", null) as Control


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_of_strings(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return output
	for item in value:
		output.append(str(item))
	return output
