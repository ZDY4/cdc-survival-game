extends RefCounted


func normalize_player_command_result(simulation: RefCounted, result: Dictionary, command: Dictionary, command_kind: String, actor_id: int, event_start_index: int) -> Dictionary:
	var output: Dictionary = result.duplicate(true)
	var success: bool = bool(output.get("success", false))
	var resolved_kind := str(output.get("kind", command_kind))
	if resolved_kind.is_empty():
		resolved_kind = "unknown"
	output["success"] = success
	output["kind"] = resolved_kind
	if not output.has("actor_id") and actor_id > 0:
		output["actor_id"] = actor_id
	var reason := str(output.get("reason", ""))
	if reason.is_empty():
		reason = "ok" if success else "unknown"
	output["reason"] = reason
	output["turn_state"] = simulation.turn_state.duplicate(true)
	output["combat_state"] = simulation.combat_state.duplicate(true)
	if not output.has("prompt"):
		output["prompt"] = {}
	if not output.has("context_snapshot"):
		output["context_snapshot"] = {}
	var completion_payload := player_command_log_payload(command, actor_id, command_kind)
	completion_payload["result_kind"] = resolved_kind
	completion_payload["success"] = success
	completion_payload["reason"] = reason
	if not success:
		copy_failure_context(output, completion_payload)
	if output.has("turn_policy"):
		completion_payload["turn_policy"] = _dictionary_or_empty(output.get("turn_policy", {})).duplicate(true)
	simulation.emit_event("player_command_completed" if success else "player_command_rejected", completion_payload)
	var emitted_events := events_since(simulation, event_start_index)
	if not output.has("events"):
		output["events"] = emitted_events
	if not output.has("runtime_snapshot_delta"):
		output["runtime_snapshot_delta"] = {
			"active_map_id": simulation.active_map_id,
			"combat_active": bool(simulation.combat_state.get("active", false)),
			"events": emitted_events,
			"pending_movement": simulation.pending_movement.duplicate(true),
			"pending_interaction": simulation.pending_interaction.duplicate(true),
			"pending_crafting": simulation.pending_crafting.duplicate(true),
			"turn_state": simulation.turn_state.duplicate(true),
		}
	if not output.has("ui_feedback"):
		output["ui_feedback"] = {
			"success": success,
			"kind": resolved_kind,
			"reason": reason,
		}
	var feedback: Dictionary = _dictionary_or_empty(output.get("ui_feedback", {})).duplicate(true)
	feedback["actor_id"] = actor_id
	feedback["kind"] = str(feedback.get("kind", resolved_kind))
	feedback["success"] = bool(feedback.get("success", success))
	feedback["reason"] = str(feedback.get("reason", reason))
	if not success:
		copy_failure_context(output, feedback)
	output["ui_feedback"] = feedback.duplicate(true)
	simulation.emit_event("ui_feedback", feedback)
	var updated_events := events_since(simulation, event_start_index)
	output["events"] = updated_events
	var runtime_delta: Dictionary = _dictionary_or_empty(output.get("runtime_snapshot_delta", {})).duplicate(true)
	runtime_delta["events"] = updated_events
	if output.has("turn_policy"):
		runtime_delta["turn_policy"] = _dictionary_or_empty(output.get("turn_policy", {})).duplicate(true)
	output["runtime_snapshot_delta"] = runtime_delta
	return output


func copy_failure_context(source: Dictionary, target: Dictionary) -> void:
	for key in ["goal", "start", "bounds", "blocker", "start_level", "goal_level", "visited_cell_count"]:
		if not source.has(key):
			continue
		var value: Variant = source.get(key)
		if typeof(value) == TYPE_DICTIONARY:
			target[key] = _dictionary_or_empty(value).duplicate(true)
		else:
			target[key] = value


func player_command_log_payload(command: Dictionary, actor_id: int, command_kind: String) -> Dictionary:
	var payload: Dictionary = {
		"actor_id": actor_id,
		"kind": command_kind,
	}
	for key in ["action", "target", "target_actor_id", "target_position", "grid", "option_id", "item_id", "recipe_id", "skill_id", "slot_id", "container_id", "shop_id", "count"]:
		if command.has(key):
			payload[key] = command.get(key)
	return payload


func events_since(simulation: RefCounted, start_index: int) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var first_index: int = clampi(start_index, 0, simulation.events.size())
	for index in range(first_index, simulation.events.size()):
		output.append(simulation.events[index].to_dictionary())
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
