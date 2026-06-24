extends RefCounted

## 模拟态的"派生视图"实时查询层。
## 这里的字段都不是持久化状态，而是从 events + pending/interaction_menu 等实时推导出来的展示用数据
## （最近失败、目标预览、控制权 actor、命令历史等）。
## 既供 simulation_snapshot_builder 组装完整快照时调用，也供 UI 构建器脱离大快照、直接从活 sim 取用，
## 避免每个面板都触发一次整局全量序列化。

const COMMAND_HISTORY_LIMIT := 12
const RECENT_FEEDBACK_LIMIT := 5


## 把 simulation.events 序列化为字典数组；多个派生查询共用，调用方只需算一次后复用。
func serialize_events(simulation: RefCounted) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for event in simulation.events:
		output.append(event.to_dictionary())
	return output


func current_control_actor(simulation: RefCounted) -> Dictionary:
	var actor_id: int = int(_dictionary_or_empty(simulation.turn_state).get("active_actor_id", 0))
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		for candidate in simulation.actor_registry.actors():
			if candidate.kind == "player":
				actor = candidate
				actor_id = candidate.actor_id
				break
	if actor == null:
		return {}
	var attributes: Dictionary = _dictionary_or_empty(actor.combat_attributes)
	var turn_ap_gain: float = _turn_ap_gain(attributes)
	var turn_ap_max: float = _turn_ap_max(attributes, turn_ap_gain)
	return {
		"actor_id": actor_id,
		"definition_id": actor.definition_id,
		"display_name": actor.display_name,
		"kind": actor.kind,
		"side": actor.side,
		"grid_position": actor.grid_position.to_dictionary(),
		"ap": actor.ap,
		"turn_ap_gain": turn_ap_gain,
		"turn_ap_max": turn_ap_max,
		"affordable_ap_threshold": _affordable_ap_threshold(attributes),
		"turn_open": actor.turn_open,
		"in_combat": actor.in_combat,
		"active_dialogue_id": actor.active_dialogue_id,
		"active_dialogue_target_actor_id": actor.active_dialogue_target_actor_id,
		"active_dialogue_target_definition_id": actor.active_dialogue_target_definition_id,
		"active_container_id": actor.active_container_id,
	}


func runtime_command_queue(simulation: RefCounted) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if not simulation.pending_movement.is_empty():
		output.append({
			"kind": "pending_movement",
			"actor_id": int(simulation.pending_movement.get("actor_id", 0)),
			"target_position": _dictionary_or_empty(simulation.pending_movement.get("target_position", {})).duplicate(true),
			"required_ap": float(simulation.pending_movement.get("required_ap", 0.0)),
			"available_ap": float(simulation.pending_movement.get("available_ap", 0.0)),
		})
	if not simulation.pending_interaction.is_empty():
		var pending: Dictionary = simulation.pending_interaction
		output.append({
			"kind": str(pending.get("kind", "pending_interaction")),
			"actor_id": int(pending.get("actor_id", 0)),
			"target": _dictionary_or_empty(pending.get("target", {})).duplicate(true),
			"target_actor_id": int(pending.get("target_actor_id", 0)),
			"option_id": str(pending.get("option_id", "")),
			"required_ap": float(pending.get("required_ap", 0.0)),
			"available_ap": float(pending.get("available_ap", 0.0)),
		})
	if not simulation.pending_crafting.is_empty():
		var crafting: Dictionary = simulation.pending_crafting
		output.append({
			"kind": str(crafting.get("kind", "pending_crafting")),
			"actor_id": int(crafting.get("actor_id", 0)),
			"recipe_id": str(crafting.get("recipe_id", "")),
			"count": int(crafting.get("count", 1)),
			"required_ap": float(crafting.get("required_ap", 0.0)),
			"progress_ap": float(crafting.get("progress_ap", 0.0)),
			"remaining_ap": float(crafting.get("remaining_ap", 0.0)),
			"available_ap": float(crafting.get("available_ap", 0.0)),
		})
	return output


func runtime_command_history(events: Array[Dictionary]) -> Array[Dictionary]:
	var by_index: Dictionary = {}
	var order: Array[int] = []
	for index in range(events.size()):
		var event: Dictionary = _dictionary_or_empty(events[index])
		var kind := str(event.get("kind", ""))
		if not ["player_command_submitted", "player_command_completed", "player_command_rejected"].has(kind):
			continue
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		var command_index := _command_history_index_for_event(kind, index, order)
		if command_index < 0:
			continue
		if not by_index.has(command_index):
			by_index[command_index] = {
				"sequence": command_index,
				"event_index": index,
				"terminal_event_index": index,
				"kind": str(payload.get("kind", "")),
				"actor_id": int(payload.get("actor_id", 0)),
				"submitted": false,
				"completed": false,
				"success": false,
				"reason": "",
				"target": {},
			}
			order.append(command_index)
		var entry: Dictionary = _dictionary_or_empty(by_index.get(command_index, {}))
		if kind == "player_command_submitted":
			entry["submitted"] = true
			entry["event_index"] = index
			_copy_command_payload_summary(entry, payload)
		else:
			entry["completed"] = true
			entry["terminal_event_index"] = index
			entry["terminal_event_kind"] = kind
			entry["success"] = kind == "player_command_completed"
			entry["reason"] = str(payload.get("reason", "ok" if bool(entry.get("success", false)) else "unknown"))
			entry["result_kind"] = str(payload.get("result_kind", payload.get("kind", "")))
			_copy_command_payload_summary(entry, payload)
		by_index[command_index] = entry
	var output: Array[Dictionary] = []
	var start: int = max(0, order.size() - COMMAND_HISTORY_LIMIT)
	for order_index in range(start, order.size()):
		output.append(_dictionary_or_empty(by_index.get(order[order_index], {})).duplicate(true))
	return output


func _command_history_index_for_event(kind: String, event_index: int, order: Array[int]) -> int:
	if kind == "player_command_submitted":
		return event_index
	for order_index in range(order.size() - 1, -1, -1):
		var candidate: int = order[order_index]
		if candidate < event_index:
			return candidate
	return event_index


func _copy_command_payload_summary(entry: Dictionary, payload: Dictionary) -> void:
	entry["kind"] = str(payload.get("kind", entry.get("kind", "")))
	entry["actor_id"] = int(payload.get("actor_id", entry.get("actor_id", 0)))
	for key in ["action", "target_actor_id", "target_position", "grid", "option_id", "item_id", "recipe_id", "skill_id", "slot_id", "container_id", "shop_id", "count"]:
		if payload.has(key):
			entry[key] = payload.get(key)
	if payload.has("target"):
		entry["target"] = _dictionary_or_empty(payload.get("target", {})).duplicate(true)


func pending_progression_step(control_actor: Dictionary) -> Dictionary:
	if control_actor.is_empty():
		return {}
	if int(control_actor.get("actor_id", 0)) <= 0:
		return {}
	if not bool(control_actor.get("turn_open", false)):
		return {}
	if float(control_actor.get("ap", 0.0)) > 0.0:
		return {}
	return {
		"kind": "await_turn_advance",
		"actor_id": int(control_actor.get("actor_id", 0)),
		"reason": "ap_empty",
	}


func recent_interaction_target(events: Array[Dictionary], interaction_menu: Dictionary) -> Dictionary:
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(events[index])
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		if str(event.get("kind", "")) == "interaction_succeeded":
			return {
				"target_id": payload.get("target_id", ""),
				"target_type": str(payload.get("target_type", "")),
				"target_name": str(payload.get("target_name", "")),
				"option_id": str(payload.get("option_id", "")),
				"option_kind": str(payload.get("option_kind", "")),
			}
	if not interaction_menu.is_empty():
		return _target_summary_from_prompt(interaction_menu)
	return {}


func recent_failure(events: Array[Dictionary]) -> Dictionary:
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(events[index])
		if str(event.get("kind", "")) != "player_command_rejected":
			continue
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		var failure := {
			"kind": str(payload.get("kind", "")),
			"reason": str(payload.get("reason", "")),
			"actor_id": int(payload.get("actor_id", 0)),
			"target": _dictionary_or_empty(payload.get("target", {})).duplicate(true),
		}
		for key in ["goal", "start", "bounds", "blocker", "start_level", "goal_level", "visited_cell_count"]:
			if not payload.has(key):
				continue
			var value: Variant = payload.get(key)
			if typeof(value) == TYPE_DICTIONARY:
				failure[key] = _dictionary_or_empty(value).duplicate(true)
			else:
				failure[key] = value
		return failure
	return {}


func recent_event_feedback(events: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(events[index])
		var kind: String = str(event.get("kind", ""))
		if not _feedback_event_kind(kind):
			continue
		output.push_front({
			"kind": kind,
			"payload": _dictionary_or_empty(event.get("payload", {})).duplicate(true),
		})
		if output.size() >= RECENT_FEEDBACK_LIMIT:
			break
	return output


func target_preview(interaction_menu: Dictionary, pending_interaction: Dictionary, recent_interaction: Dictionary) -> Dictionary:
	if not interaction_menu.is_empty():
		return {
			"source": "interaction_menu",
			"target": _target_summary_from_prompt(interaction_menu),
			"primary_option_id": str(interaction_menu.get("primary_option_id", "")),
			"primary_option_kind": str(interaction_menu.get("primary_option_kind", "")),
			"action_label": str(interaction_menu.get("action_label", "")),
			"ap_cost": float(interaction_menu.get("ap_cost", 0.0)),
			"disabled_options": _array_or_empty(interaction_menu.get("disabled_options", [])).duplicate(true),
		}
	if not pending_interaction.is_empty():
		return {
			"source": "pending_interaction",
			"target": _dictionary_or_empty(pending_interaction.get("target", {})).duplicate(true),
			"option_id": str(pending_interaction.get("option_id", "")),
			"required_ap": float(pending_interaction.get("required_ap", 0.0)),
			"available_ap": float(pending_interaction.get("available_ap", 0.0)),
		}
	if not recent_interaction.is_empty():
		return {
			"source": "recent_interaction",
			"target": recent_interaction.duplicate(true),
		}
	return {}


func target_selection_state(interaction_menu: Dictionary, pending_interaction: Dictionary) -> Dictionary:
	var has_prompt := not interaction_menu.is_empty()
	return {
		"has_selection": has_prompt or not pending_interaction.is_empty(),
		"has_prompt": has_prompt,
		"has_pending_interaction": not pending_interaction.is_empty(),
		"target": _target_summary_from_prompt(interaction_menu) if has_prompt else _dictionary_or_empty(pending_interaction.get("target", {})).duplicate(true),
	}


func ui_menu_state_refs(simulation: RefCounted) -> Dictionary:
	return {
		"interaction_menu_open": not simulation.interaction_menu.is_empty(),
		"interaction_menu_target": _target_summary_from_prompt(simulation.interaction_menu),
		"active_dialogue_actor_id": _active_actor_with_field(simulation, "active_dialogue_id"),
		"active_container_actor_id": _active_actor_with_field(simulation, "active_container_id"),
		"pending_movement": not simulation.pending_movement.is_empty(),
		"pending_interaction": not simulation.pending_interaction.is_empty(),
		"pending_crafting": not simulation.pending_crafting.is_empty(),
	}


func debug_runtime_diagnostics(simulation: RefCounted, events: Array[Dictionary], runtime_queue: Array[Dictionary], command_history: Array[Dictionary], recent_failure_data: Dictionary, target_preview_data: Dictionary, recent_feedback: Array[Dictionary]) -> Dictionary:
	var latest_command: Dictionary = {}
	if not command_history.is_empty():
		latest_command = _dictionary_or_empty(command_history[command_history.size() - 1]).duplicate(true)
	return {
		"event_count": events.size(),
		"command_history_count": command_history.size(),
		"command_history_limit": COMMAND_HISTORY_LIMIT,
		"queued_command_count": runtime_queue.size(),
		"pending_movement": not simulation.pending_movement.is_empty(),
		"pending_interaction": not simulation.pending_interaction.is_empty(),
		"pending_crafting": not simulation.pending_crafting.is_empty(),
		"interaction_menu_open": not simulation.interaction_menu.is_empty(),
		"recent_feedback_count": recent_feedback.size(),
		"latest_command": latest_command,
		"latest_failure_reason": str(recent_failure_data.get("reason", "")),
		"target_preview_source": str(target_preview_data.get("source", "")),
		"combat_active": bool(simulation.combat_state.get("active", false)),
		"turn_phase": str(simulation.turn_state.get("phase", "")),
		"active_actor_id": int(simulation.turn_state.get("active_actor_id", 0)),
	}


func _target_summary_from_prompt(prompt: Dictionary) -> Dictionary:
	if prompt.is_empty():
		return {}
	var target: Dictionary = _dictionary_or_empty(prompt.get("target", {}))
	return {
		"target_type": str(prompt.get("target_type", target.get("target_type", ""))),
		"target_kind": str(prompt.get("target_kind", target.get("kind", ""))),
		"target_name": str(prompt.get("target_name", target.get("display_name", ""))),
		"actor_id": int(target.get("actor_id", 0)),
		"target_id": str(target.get("target_id", "")),
	}


func _active_actor_with_field(simulation: RefCounted, field_name: String) -> int:
	for actor in simulation.actor_registry.actors():
		if not str(actor.get(field_name)).is_empty():
			return actor.actor_id
	return 0


func _feedback_event_kind(kind: String) -> bool:
	return [
		"interaction_succeeded",
		"actor_waited",
		"movement_step",
		"attack_resolved",
		"actor_defeated",
		"corpse_created",
		"combat_started",
		"combat_ended",
		"recipe_crafted",
		"skill_used",
		"relationship_changed",
		"world_flag_changed",
		"dialogue_item_granted",
		"dialogue_reward_granted",
		"dialogue_action_failed",
		"crafting_queued",
		"crafting_resumed",
		"crafting_cancelled",
		"movement_cancelled",
		"interaction_cancelled",
		"pending_cancelled",
		"player_command_rejected",
		"ui_feedback",
	].has(kind)


func _turn_ap_gain(attributes: Dictionary) -> float:
	if attributes.has("turn_ap_gain"):
		return max(0.0, float(attributes.get("turn_ap_gain", 6.0)))
	if attributes.has("speed"):
		return max(1.0, float(attributes.get("speed", 6.0)) + 1.0)
	return 6.0


func _turn_ap_max(attributes: Dictionary, turn_ap_gain: float) -> float:
	if attributes.has("turn_ap_max"):
		return max(1.0, float(attributes.get("turn_ap_max", 6.0)))
	if attributes.has("ap_max"):
		return max(1.0, float(attributes.get("ap_max", 6.0)))
	return max(6.0, turn_ap_gain)


func _affordable_ap_threshold(attributes: Dictionary) -> float:
	if attributes.has("affordable_ap_threshold"):
		return max(0.0, float(attributes.get("affordable_ap_threshold", 1.0)))
	if attributes.has("ap_affordable_threshold"):
		return max(0.0, float(attributes.get("ap_affordable_threshold", 1.0)))
	return 1.0


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
