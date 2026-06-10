extends RefCounted

const WorldActionPresenter = preload("res://scripts/world/world_action_presenter.gd")

var presenter: RefCounted = WorldActionPresenter.new()
var sequence: int = 0
var queue_state: Dictionary = {
	"active": false,
	"state": "idle",
	"sequence": 0,
	"current_strategy": "present_before_final_refresh",
	"target_strategy": "present_before_final_refresh",
}
var pending_ui: Dictionary = {}
var pending_final_refresh: Dictionary = {}


func presenter_snapshot() -> Dictionary:
	if presenter == null:
		return {"active": false, "kind": "none", "active_count": 0}
	return _dictionary_or_empty(presenter.call("snapshot"))


func blocks_input() -> bool:
	return bool(presenter_snapshot().get("active", false))


func snapshot() -> Dictionary:
	var output: Dictionary = queue_state.duplicate(true)
	var current_presenter: Dictionary = presenter_snapshot()
	var presenter_active := bool(current_presenter.get("active", false))
	output["presenter_active"] = presenter_active
	output["presenter_kind"] = str(current_presenter.get("kind", ""))
	output["presenter_sequence"] = int(current_presenter.get("sequence", 0))
	output["input_blocked"] = blocks_input()
	output["pending_ui"] = pending_ui.duplicate(true)
	output["pending_ui_active"] = not pending_ui.is_empty()
	output["pending_final_refresh"] = pending_final_refresh.duplicate(true)
	output["pending_final_refresh_active"] = not pending_final_refresh.is_empty()
	if str(output.get("state", "")) == "presenting" and not presenter_active and pending_ui.is_empty() and pending_final_refresh.is_empty():
		output["active"] = false
		output["state"] = "completed"
		queue_state = output.duplicate(true)
	return output


func finish_active_presentations() -> Dictionary:
	if presenter == null or not presenter.has_method("finish_active_presentations"):
		return presenter_snapshot()
	var result: Dictionary = _dictionary_or_empty(presenter.call("finish_active_presentations"))
	record_finished(result)
	return result


func present_result(game_root: Node, world_container: Node3D, command_result: Dictionary, world_result: Dictionary) -> Dictionary:
	if presenter == null or command_result.is_empty() or world_container == null:
		return {}
	var presenter_result: Dictionary = _dictionary_or_empty(presenter.call("present_result", game_root, world_container, command_result, world_result))
	record_presented(command_result, presenter_result)
	return presenter_result


func queue_open_stage_panel(panel_id: String, result: Dictionary, prompt: Dictionary) -> void:
	pending_ui = {
		"kind": "open_stage_panel",
		"source": "interaction_result",
		"panel_id": panel_id,
		"command_kind": command_kind(result),
		"presenter_kind": str(presenter_snapshot().get("kind", "")),
		"queued_sequence": int(queue_state.get("sequence", 0)),
		"open_after": "presenter_finished",
		"refresh_all_panels": true,
		"prompt": prompt.duplicate(true),
	}
	queue_state["pending_ui"] = pending_ui.duplicate(true)
	queue_state["pending_ui_active"] = true


func queue_refresh_all_panels(result: Dictionary, prompt: Dictionary) -> void:
	pending_ui = {
		"kind": "refresh_all_panels",
		"source": "interaction_result",
		"command_kind": command_kind(result),
		"presenter_kind": str(presenter_snapshot().get("kind", "")),
		"queued_sequence": int(queue_state.get("sequence", 0)),
		"open_after": "presenter_finished",
		"refresh_all_panels": true,
		"prompt": prompt.duplicate(true),
	}
	queue_state["pending_ui"] = pending_ui.duplicate(true)
	queue_state["pending_ui_active"] = true


func queue_deferred_world_refresh(final_world_result: Dictionary, selected_prompt: Dictionary, command_result: Dictionary, source: String, render_world: bool = true) -> void:
	pending_final_refresh = {
		"kind": "final_world_refresh",
		"source": source,
		"command_kind": command_kind(command_result),
		"presenter_kind": str(presenter_snapshot().get("kind", "")),
		"queued_sequence": int(queue_state.get("sequence", 0)),
		"refresh_after": "presenter_finished",
		"render_world": render_world,
		"refresh_all_panels": true,
		"prompt": selected_prompt.duplicate(true),
		"world_result": final_world_result.duplicate(true),
	}
	queue_state["current_strategy"] = "present_before_final_refresh"
	queue_state["refresh_timing"] = "presenter_before_final_world_render"
	queue_state["final_refresh_deferred"] = true
	queue_state["final_refresh_deferred_supported"] = true
	queue_state["pending_final_refresh"] = deferred_world_refresh_public_snapshot(pending_final_refresh)
	queue_state["pending_final_refresh_active"] = true


func movement_execution_plan(command_result: Dictionary, final_world_result: Dictionary) -> Dictionary:
	if not bool(command_result.get("success", false)) or command_kind(command_result) != "move":
		return {
			"present_before_refresh": false,
			"defer_final_refresh": false,
			"refresh_now": true,
			"final_world_result": final_world_result.duplicate(true),
		}
	return {
		"present_before_refresh": true,
		"defer_final_refresh": blocks_input(),
		"refresh_now": not blocks_input(),
		"final_world_result": final_world_result.duplicate(true),
	}


func should_process_completion() -> bool:
	var queue_state_name := str(queue_state.get("state", ""))
	if pending_ui.is_empty() and pending_final_refresh.is_empty() and queue_state_name != "presenting":
		return false
	return not blocks_input()


func mark_presenter_finished_if_needed() -> void:
	if str(queue_state.get("state", "")) == "presenting":
		record_finished(presenter_snapshot())


func take_pending_final_refresh() -> Dictionary:
	var output := pending_final_refresh.duplicate(true)
	pending_final_refresh.clear()
	return output


func take_pending_ui() -> Dictionary:
	var output := pending_ui.duplicate(true)
	pending_ui.clear()
	return output


func mark_final_refresh_applied(pending_refresh: Dictionary, trigger: String) -> Dictionary:
	var applied: Dictionary = deferred_world_refresh_public_snapshot(pending_refresh)
	applied["trigger"] = trigger
	applied["applied"] = true
	queue_state["pending_final_refresh"] = {}
	queue_state["pending_final_refresh_active"] = false
	queue_state["final_refresh_deferred"] = false
	queue_state["final_refresh_applied"] = true
	queue_state["applied_final_refresh"] = applied
	return applied


func mark_deferred_ui_applied(pending: Dictionary, trigger: String) -> Dictionary:
	var applied: Dictionary = pending.duplicate(true)
	applied["trigger"] = trigger
	applied["applied"] = true
	queue_state["pending_ui"] = {}
	queue_state["pending_ui_active"] = false
	queue_state["applied_deferred_ui"] = applied
	queue_state["deferred_ui_applied"] = true
	return applied


func record_presented(command_result: Dictionary, presenter_result: Dictionary) -> void:
	sequence += 1
	var presenter_active := bool(presenter_result.get("active", false))
	var presenter_kind := str(presenter_result.get("kind", "none"))
	queue_state = {
		"active": presenter_active,
		"state": "presenting" if presenter_active else "completed",
		"sequence": sequence,
		"current_strategy": "present_before_final_refresh",
		"target_strategy": "present_before_final_refresh",
		"refresh_timing": "presenter_before_final_world_render",
		"next_strategy_step": "apply_final_world_refresh_after_presenter_finished",
		"phase_order": [
			"command_result_received",
			"runtime_snapshot_applied",
			"presenter_started",
			"final_world_refresh_deferred",
		],
		"command_kind": command_kind(command_result),
		"success": bool(command_result.get("success", false)),
		"reason": str(command_result.get("reason", "")),
		"event_count": event_count(command_result),
		"presenter_kind": presenter_kind,
		"presenter_active": presenter_active,
		"presenter_sequence": int(presenter_result.get("sequence", 0)),
		"presenter_snapshot": presenter_result.duplicate(true),
		"final_refresh_deferred": false,
		"final_refresh_deferred_supported": true,
	}


func record_finished(finish_result: Dictionary) -> void:
	var output: Dictionary = queue_state.duplicate(true)
	output["active"] = false
	output["state"] = "completed"
	output["finished"] = true
	output["finish_reason"] = "fast_forwarded" if bool(finish_result.get("fast_forwarded", false)) else "presenter_idle"
	output["finish_result"] = finish_result.duplicate(true)
	output["presenter_active"] = bool(finish_result.get("active", false))
	output["presenter_kind"] = str(finish_result.get("kind", output.get("presenter_kind", "")))
	output["presenter_sequence"] = int(finish_result.get("sequence", output.get("presenter_sequence", 0)))
	queue_state = output


func deferred_world_refresh_public_snapshot(source: Dictionary) -> Dictionary:
	return {
		"kind": str(source.get("kind", "final_world_refresh")),
		"source": str(source.get("source", "")),
		"command_kind": str(source.get("command_kind", "")),
		"presenter_kind": str(source.get("presenter_kind", "")),
		"queued_sequence": int(source.get("queued_sequence", 0)),
		"refresh_after": str(source.get("refresh_after", "")),
		"render_world": bool(source.get("render_world", true)),
		"refresh_all_panels": bool(source.get("refresh_all_panels", false)),
		"prompt": _dictionary_or_empty(source.get("prompt", {})).duplicate(true),
	}


func command_kind(command_result: Dictionary) -> String:
	var result: Dictionary = _dictionary_or_empty(command_result.get("result", {}))
	var kind := str(result.get("kind", ""))
	if not kind.is_empty():
		return kind
	kind = str(command_result.get("kind", ""))
	if not kind.is_empty():
		return kind
	for event_value in events_from_result(command_result):
		var event: Dictionary = _dictionary_or_empty(event_value)
		match str(event.get("kind", "")):
			"movement_step", "actor_moved", "movement_queued", "movement_cancelled":
				return "move"
			"attack_resolved":
				return "attack"
			"interaction_succeeded", "interaction_queued", "interaction_cancelled":
				return "interact"
			"item_used", "item_equipped", "item_unequipped", "item_dropped", "item_deconstructed", "container_item_taken", "container_item_stored", "shop_item_bought", "shop_item_sold", "inventory_reordered", "inventory_stack_split", "ammo_reloaded":
				return "inventory_action"
			"crafting_started", "crafting_completed", "crafting_cancelled":
				return "craft"
			"skill_learned":
				return "learn_skill"
			"hotbar_bound":
				return "bind_hotbar"
	return "unknown"


func event_count(command_result: Dictionary) -> int:
	return events_from_result(command_result).size()


func events_from_result(command_result: Dictionary) -> Array:
	var result: Dictionary = _dictionary_or_empty(command_result.get("result", {}))
	var events: Array = []
	for source in [
		command_result.get("events", []),
		result.get("events", []),
		command_result.get("emitted_events", []),
		result.get("emitted_events", []),
	]:
		for event in _array_or_empty(source):
			events.append(event)
	return events


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
