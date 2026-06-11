extends RefCounted


func submit(simulation: RefCounted, command: Dictionary) -> Dictionary:
	var kind := str(command.get("kind", ""))
	var actor_id: int = int(command.get("actor_id", simulation._player_actor_id()))
	var event_start_index: int = simulation.events.size()
	simulation.emit_event("player_command_submitted", simulation._player_command_log_payload(command, actor_id, kind))
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return simulation._normalize_player_command_result({"success": false, "reason": "unknown_actor"}, command, kind, actor_id, event_start_index)
	if actor.kind != "player":
		return simulation._normalize_player_command_result({"success": false, "reason": "command_actor_not_player"}, command, kind, actor_id, event_start_index)
	if not actor.turn_open:
		return simulation._normalize_player_command_result({"success": false, "reason": "turn_closed", "turn_state": simulation.turn_state.duplicate(true)}, command, kind, actor_id, event_start_index)
	if simulation._actor_has_special_effect(actor, "stun") and kind != "cancel_pending":
		return simulation._normalize_player_command_result(simulation._submit_stunned_player_turn(actor, command, kind), command, kind, actor_id, event_start_index)

	var result: Dictionary = {}
	var cancelled_pending: Dictionary = simulation._cancel_pending_for_new_target_command(actor_id, kind, command)
	match kind:
		"wait":
			result = simulation._submit_wait_command(actor, command)
		"move":
			result = simulation._finalize_player_ap_action(actor, simulation._submit_move_command(actor, command), command, "move")
		"interact":
			result = simulation._finalize_player_ap_action(actor, simulation._submit_interact_command(actor, command), command, "interact")
		"attack":
			result = simulation._finalize_player_ap_action(actor, simulation._submit_attack_command(actor, command), command, "attack")
		"craft":
			result = simulation._finalize_player_ap_action(actor, simulation._submit_craft_command(actor, command), command, "craft")
		"inventory_action":
			result = simulation._submit_inventory_action_command(actor, command)
		"cancel_pending":
			result = simulation.cancel_pending(str(command.get("reason", "player_command")), bool(command.get("auto_end_turn", false)), _dictionary_or_empty(command.get("topology", {})))
		"learn_skill":
			result = simulation._submit_learn_skill_command(actor, command)
		"bind_hotbar":
			result = simulation._submit_bind_hotbar_command(actor, command)
		"use_skill":
			result = simulation._finalize_player_ap_action(actor, simulation._submit_use_skill_command(actor, command), command, "use_skill")
		_:
			result = simulation._unsupported_player_command(command, "unknown_player_command")
	if not cancelled_pending.is_empty():
		result["cancelled_pending"] = cancelled_pending
	return simulation._normalize_player_command_result(result, command, kind, actor_id, event_start_index)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
