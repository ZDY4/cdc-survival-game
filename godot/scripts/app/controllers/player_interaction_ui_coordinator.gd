extends RefCounted

var host


func configure(p_host) -> void:
	host = p_host


func close_active_dialogue(reason: String = "closed") -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.dialogue_action_controller.call("close_dialogue", host.simulation, reason))
	var result: Dictionary = dictionary_or_empty(operation.get("result", {}))
	if bool(result.get("success", false)):
		host.close_trade_panel("dialogue_closed:%s" % reason)
		host.player_ui_action_coordinator.call("refresh_dialogue_operation", operation)
	return result


func close_active_container(reason: String = "closed") -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.container_action_controller.call("close_container", host.simulation, reason))
	var result: Dictionary = dictionary_or_empty(operation.get("result", {}))
	if bool(result.get("success", false)):
		host.active_container_feedback = {}
	return dictionary_or_empty(host.player_ui_action_coordinator.call("apply_container_action_operation", operation))


func close_active_ui(reason: String = "closed") -> Dictionary:
	if host.is_debug_console_open():
		if host.hud_root != null:
			host.hud_root.close_debug_console()
		host.refresh_hud(host.current_interaction_prompt())
		return {"success": true, "closed": "debug_console"}
	if host.hud_root != null:
		var modal_result: Dictionary = dictionary_or_empty(host.hud_root.close_blocking_modal())
		if bool(modal_result.get("success", false)):
			return {"success": true, "closed": str(modal_result.get("closed", "modal")), "result": modal_result}
	var runner_before_close: Dictionary = dictionary_or_empty(host.turn_action_runner_snapshot())
	if bool(runner_before_close.get("active", false)) or bool(runner_before_close.get("presentation_active", false)):
		var pending_before: Dictionary = runtime_pending_state_snapshot()
		var runner_result: Dictionary = dictionary_or_empty(host.settle_turn_action_runner_boundary(reason))
		host.refresh_hud(host.current_interaction_prompt())
		return {
			"success": true,
			"closed": "turn_action_runner",
			"result": runner_result,
			"pending_before": pending_before,
			"pending_after": runtime_pending_state_snapshot(),
		}
	if bool(host.interaction_world_action_coordinator.call("world_action_presenter_blocks_input")):
		var pending_before: Dictionary = runtime_pending_state_snapshot()
		var result: Dictionary = dictionary_or_empty(host.finish_world_action_presentations())
		return {
			"success": true,
			"closed": "world_action_presenter",
			"result": result,
			"pending_before": pending_before,
			"pending_after": runtime_pending_state_snapshot(),
		}
	if not host.active_skill_targeting.is_empty():
		return dictionary_or_empty(host.cancel_active_skill_targeting(reason))
	if host.runtime_input_controller != null and host.runtime_input_controller.has_method("has_selection_state") and bool(host.runtime_input_controller.has_selection_state()):
		var selection_result: Dictionary = host.runtime_input_controller.clear_selection_state(reason)
		return {"success": true, "closed": "selection", "result": selection_result}
	if host.game_ui_coordinator != null and bool(host.game_ui_coordinator.call("close_hud_interaction_menu")):
		return {"success": true, "closed": "interaction_menu"}
	var context_menu_close_result: Dictionary = close_active_context_menu()
	if bool(context_menu_close_result.get("success", false)):
		return context_menu_close_result
	if host.runtime_input_controller != null:
		host.runtime_input_controller.clear_selection_state(reason)
	var dialogue_result := close_active_dialogue(reason)
	if bool(dialogue_result.get("success", false)):
		return {"success": true, "closed": "dialogue", "result": dialogue_result}
	if not host.active_trade_target.is_empty():
		host.close_trade_panel(reason)
		return {"success": true, "closed": "trade"}
	var container_result := close_active_container(reason)
	if bool(container_result.get("success", false)):
		return {"success": true, "closed": "container", "result": container_result}
	if host.any_stage_panel_open():
		host.close_stage_panels()
		return {"success": true, "closed": "stage_panel"}
	if host.is_settings_open():
		host.hud_root.close_settings_panel()
		host.runtime_audio_coordinator.call("play_ui_audio_feedback", "settings_panel_closed", {"panel_id": "settings", "action": "close_settings_panel"})
		host.refresh_all_panels(host.current_interaction_prompt())
		return {"success": true, "closed": "settings"}
	var pending_result: Dictionary = dictionary_or_empty(host.cancel_pending(reason, false))
	if bool(pending_result.get("had_pending", false)):
		return {"success": true, "closed": "pending", "result": pending_result}
	if host.hud_root != null:
		host.hud_root.open_settings_panel()
		host.runtime_audio_coordinator.call("play_ui_audio_feedback", "settings_panel_opened", {"panel_id": "settings", "action": "open_settings_panel"})
		host.refresh_all_panels(host.current_interaction_prompt())
		return {"success": true, "closed": "", "opened": "settings"}
	return {"success": false, "reason": "panel_controller_missing"}


func close_active_context_menu() -> Dictionary:
	if host.hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	return dictionary_or_empty(host.hud_root.close_active_context_menu())


func runtime_pending_state_snapshot() -> Dictionary:
	if host.simulation == null:
		return {"pending_movement": {}, "pending_interaction": {}, "pending_crafting": {}}
	var snapshot: Dictionary = host.simulation.snapshot()
	return {
		"pending_movement": dictionary_or_empty(snapshot.get("pending_movement", {})).duplicate(true),
		"pending_interaction": dictionary_or_empty(snapshot.get("pending_interaction", {})).duplicate(true),
		"pending_crafting": dictionary_or_empty(snapshot.get("pending_crafting", {})).duplicate(true),
	}


func select_interaction_target(target: Dictionary) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.interaction_action_controller.call("select_target", host.interaction_controller, target))
	return apply_interaction_selection_operation(operation)


func select_interaction_node(node: Node) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.interaction_action_controller.call("select_node", host.interaction_controller, node))
	return apply_interaction_selection_operation(operation)


func clear_interaction_selection(reason: String = "cleared") -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.interaction_action_controller.call("clear_selection", host.interaction_controller, reason))
	return apply_interaction_selection_operation(operation)


func apply_interaction_selection_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(operation.get("result", {}))
	if bool(operation.get("refresh_hud", false)):
		host.refresh_hud(dictionary_or_empty(result.get("prompt", {})))
	return result


func execute_primary_interaction() -> Dictionary:
	if host.interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var target: Dictionary = dictionary_or_empty(host.interaction_controller.selected_target).duplicate(true)
	var prompt: Dictionary = dictionary_or_empty(host.interaction_controller.selected_prompt)
	return dictionary_or_empty(host.request_player_interaction(target, str(prompt.get("primary_option_id", ""))))


func execute_interaction_option(option_id: String) -> Dictionary:
	if host.interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var target: Dictionary = dictionary_or_empty(host.interaction_controller.selected_target).duplicate(true)
	return dictionary_or_empty(host.request_player_interaction(target, option_id))


func apply_interaction_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(operation.get("result", {}))
	if bool(operation.get("apply_result", false)):
		host.interaction_world_action_coordinator.call("apply_interaction_execution_result", result, dictionary_or_empty(operation.get("executed_target", {})))
	return result


func select_grid_target(grid: Dictionary) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.interaction_action_controller.call("select_grid", host.interaction_controller, grid))
	return apply_interaction_selection_operation(operation)


func execute_move_to_grid(grid: Dictionary) -> Dictionary:
	var selection: Dictionary = select_grid_target(grid)
	if not bool(selection.get("success", false)):
		return selection
	var result: Dictionary = dictionary_or_empty(host.request_player_move(grid))
	if not bool(result.get("success", false)):
		host.refresh_hud(host.current_interaction_prompt())
		return result
	host.refresh_hud(host.current_interaction_prompt())
	return result


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
