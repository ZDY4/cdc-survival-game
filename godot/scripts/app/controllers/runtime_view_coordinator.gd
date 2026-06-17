extends RefCounted

var host


func configure(p_host) -> void:
	host = p_host


func current_map_level() -> int:
	return int(host.runtime_view_state_controller.call("current_map_level", host.world_result))


func map_level_snapshot() -> Dictionary:
	return dictionary_or_empty(host.runtime_view_state_controller.call("map_level_snapshot", host.world_result))


func change_observed_level(direction: int) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.runtime_view_state_controller.call("change_observed_level", direction, host.world_result))
	if bool(result.get("success", false)):
		focus_current_actor()
		host.refresh_hud(host.current_interaction_prompt())
	return result


func cycle_focused_actor() -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.runtime_view_state_controller.call("cycle_focused_actor", host.world_result, host.simulation, host.is_observe_mode_enabled(), host.hud_root != null and host.hud_root.gameplay_input_blocked()))
	return apply_focus_result(result)


func focus_actor(actor_id: int) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.runtime_view_state_controller.call("focus_actor", actor_id, host.world_result, host.simulation, host.is_observe_mode_enabled(), host.hud_root != null and host.hud_root.gameplay_input_blocked()))
	return apply_focus_result(result)


func apply_focus_result(result: Dictionary) -> Dictionary:
	if bool(result.get("success", false)):
		clear_focus_switch_ui_state()
		focus_current_actor()
		host.refresh_hud(host.current_interaction_prompt())
	return result


func focused_actor_snapshot() -> Dictionary:
	return dictionary_or_empty(host.runtime_view_state_controller.call("focused_actor_snapshot", host.world_result, host.is_observe_mode_enabled()))


func focused_actor_grid_position() -> Dictionary:
	return dictionary_or_empty(host.runtime_view_state_controller.call("focused_actor_grid_position", host.world_result, host.is_observe_mode_enabled()))


func focused_actor_visual_position() -> Variant:
	var node := focused_actor_node_for_camera_follow()
	if node != null:
		return node.global_position
	return null


func focused_actor_node_for_camera_follow() -> Node3D:
	var actor_id := active_runner_actor_id()
	if actor_id <= 0:
		actor_id = int(focused_actor_snapshot().get("actor_id", host.runtime_scene_coordinator.call("player_actor_id")))
	if host.actor_view_controller != null and host.actor_view_controller.has_method("active_actor_node"):
		var node := host.actor_view_controller.call("active_actor_node", actor_id) as Node3D
		if node != null:
			return node
	return null


func active_runner_actor_id() -> int:
	var runner: Dictionary = dictionary_or_empty(host.turn_action_runner_snapshot())
	if bool(runner.get("active", false)) or bool(runner.get("presentation_active", false)):
		return int(runner.get("actor_id", 0))
	return 0


func clear_focus_switch_ui_state() -> void:
	if host.runtime_input_controller != null and host.runtime_input_controller.has_method("clear_selection_state"):
		host.runtime_input_controller.clear_selection_state("focus_switch")
	if host.interaction_controller != null:
		host.interaction_action_controller.call("clear_selection", host.interaction_controller, "focus_switch", false)
	host.game_ui_coordinator.call("close_hud_interaction_menu")


func focus_current_actor() -> void:
	if host.runtime_input_controller != null and host.runtime_input_controller.has_method("focus_current_actor"):
		host.runtime_input_controller.focus_current_actor()


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
