extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const SimulationSnapshotLoader = preload("res://scripts/core/simulation/simulation_snapshot_loader.gd")

const CURRENT_SCHEMA_VERSION := 1

var _inventory_entries := InventoryEntries.new()
var _loader := SimulationSnapshotLoader.new()


func build(simulation: RefCounted) -> Dictionary:
	var event_output: Array[Dictionary] = []
	for event in simulation.events:
		event_output.append(event.to_dictionary())
	var control_actor: Dictionary = _current_control_actor_snapshot(simulation)
	var recent_failure: Dictionary = _recent_failure(event_output)
	var recent_interaction: Dictionary = _recent_interaction_target(event_output, simulation.interaction_menu)
	var runtime_queue: Array[Dictionary] = _runtime_command_queue(simulation)
	var command_history: Array[Dictionary] = _runtime_command_history(event_output)
	var target_preview: Dictionary = _target_preview(simulation.interaction_menu, simulation.pending_interaction, recent_interaction)
	var recent_feedback: Array[Dictionary] = _recent_event_feedback(event_output)
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"active_map_id": simulation.active_map_id,
		"start_location_id": simulation.start_location_id,
		"start_entry_point_id": simulation.start_entry_point_id,
		"active_location_id": simulation.active_location_id,
		"active_entry_point_id": simulation.active_entry_point_id,
		"unlocked_locations": simulation.unlocked_locations.duplicate(),
		"actors": simulation.actor_registry.snapshot(),
		"events": event_output,
		"consumed_interaction_targets": simulation.consumed_interaction_targets.keys(),
		"door_states": _door_state_snapshots(simulation.door_states),
		"container_sessions": _container_session_snapshots(simulation.container_sessions),
		"shop_sessions": _shop_session_snapshots(simulation.shop_sessions),
		"active_quests": _active_quest_snapshots(simulation.active_quests),
		"completed_quests": simulation.completed_quests.keys(),
		"world_flags": simulation.world_flags.keys(),
		"relationships": _relationship_snapshots(simulation.relationships),
		"ai_intents": _ai_intent_snapshots(simulation.ai_intents),
		"world_time": simulation.world_time.duplicate(true),
		"vision": simulation._vision_rules.snapshot(),
		"turn_state": simulation.turn_state.duplicate(true),
		"combat_state": simulation.combat_state.duplicate(true),
		"pending_movement": simulation.pending_movement.duplicate(true),
		"pending_interaction": simulation.pending_interaction.duplicate(true),
		"pending_crafting": simulation.pending_crafting.duplicate(true),
		"crafting_queue": _crafting_queue_snapshots(simulation.crafting_queue),
		"runtime_command_queue": runtime_queue,
		"runtime_command_history": command_history,
		"pending_progression_step": _pending_progression_step(control_actor),
		"current_control_actor": control_actor,
		"recent_interaction_target": recent_interaction,
		"recent_failure": recent_failure,
		"recent_event_feedback": recent_feedback,
		"target_preview": target_preview,
		"target_selection_state": _target_selection_state(simulation.interaction_menu, simulation.pending_interaction),
		"ui_menu_state_refs": _ui_menu_state_refs(simulation),
		"debug_runtime_diagnostics": _debug_runtime_diagnostics(simulation, event_output, runtime_queue, command_history, recent_failure, target_preview, recent_feedback),
		"corpse_containers": _corpse_container_snapshots(simulation.corpse_containers),
		"interaction_menu": simulation.interaction_menu.duplicate(true),
		"hotbar": simulation.hotbar.duplicate(true),
		"active_hotbar_group": str(simulation.active_hotbar_group),
		"hotbar_groups": _hotbar_group_snapshots(simulation.hotbar_groups),
		"hotbar_group_labels": _hotbar_group_label_snapshots(simulation.hotbar_group_labels),
		"crafted_recipes": simulation.crafted_recipes.keys(),
	}


func load(simulation: RefCounted, snapshot_data: Dictionary) -> void:
	_loader.load(simulation, snapshot_data)


func _active_quest_snapshots(active_quests: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = active_quests.keys()
	ids.sort()
	for quest_id in ids:
		var state: Dictionary = _dictionary_or_empty(active_quests[quest_id])
		output.append({
			"quest_id": str(state.get("quest_id", quest_id)),
			"current_node_id": str(state.get("current_node_id", "")),
			"completed_objectives": _dictionary_or_empty(state.get("completed_objectives", {})).duplicate(true),
		})
	return output


func _ai_intent_snapshots(ai_intents: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = ai_intents.keys()
	ids.sort()
	for actor_id in ids:
		output.append(_dictionary_or_empty(ai_intents[actor_id]).duplicate(true))
	return output


func _relationship_snapshots(relationships: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for key in relationships.keys():
		var parts := str(key).split(":", false)
		if parts.size() != 2:
			continue
		var actor_id := int(parts[0])
		var target_actor_id := int(parts[1])
		if actor_id <= 0 or target_actor_id <= 0 or actor_id == target_actor_id:
			continue
		output.append({
			"actor_id": min(actor_id, target_actor_id),
			"target_actor_id": max(actor_id, target_actor_id),
			"score": clampf(float(relationships.get(key, 0.0)), -100.0, 100.0),
		})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left_actor := int(a.get("actor_id", 0))
		var right_actor := int(b.get("actor_id", 0))
		if left_actor == right_actor:
			return int(a.get("target_actor_id", 0)) < int(b.get("target_actor_id", 0))
		return left_actor < right_actor
	)
	return output


func _container_session_snapshots(container_sessions: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = container_sessions.keys()
	ids.sort()
	for container_id in ids:
		var session: Dictionary = _dictionary_or_empty(container_sessions[container_id])
		var snapshot := {
			"container_id": str(session.get("container_id", container_id)),
			"container_type": _container_type_for_session(session, str(container_id)),
			"container_origin": _container_origin_for_session(session, str(container_id)),
			"display_name": str(session.get("display_name", container_id)),
			"money": max(0, int(session.get("money", 0))),
			"inventory": _array_or_empty(session.get("inventory", [])).duplicate(true),
		}
		_copy_optional_keys(snapshot, session, [
			"map_id",
			"grid_position",
			"source_actor_id",
			"source_actor_definition_id",
			"source_actor_kind",
			"defeated_by_actor_id",
			"owner_actor_id",
			"owner_actor_definition_id",
			"owned",
			"allow_steal",
			"allow_theft",
			"steal_relationship_delta",
			"theft_relationship_delta",
			"owner_relationship_min",
			"owner_relationship_max",
			"required_owner_relationship_min",
			"required_owner_relationship_max",
			"required_active_quest_ids",
			"required_active_quests",
			"required_completed_quest_ids",
			"required_completed_quests",
			"blocked_active_quest_ids",
			"blocked_active_quests",
			"blocked_completed_quest_ids",
			"blocked_completed_quests",
			"quest_id",
			"shop_id",
			"drop_item_id",
			"locked",
			"allow_take",
			"allow_store",
			"required_item_ids",
			"required_items",
			"required_tool_ids",
			"required_tools",
			"consume_required_items_on_unlock",
			"consume_required_tools_on_unlock",
			"consume_required_items",
			"consume_required_tools",
			"consume_keys_on_unlock",
			"consume_tools_on_unlock",
			"required_item_consume_count",
			"required_tool_consume_count",
			"unlock_item_consume_count",
			"unlock_tool_consume_count",
			"key_consume_count",
			"tool_consume_count",
			"tool_durability_cost",
			"unlock_tool_durability_cost",
			"required_tool_durability_cost",
			"unlock_requirements_consumed",
			"unlock_consumed_actor_id",
			"unlock_consumed_action",
			"required_world_flags",
			"blocked_world_flags",
			"max_weight",
			"max_container_weight",
			"weight_capacity",
			"max_items",
			"max_item_count",
			"item_capacity",
			"max_stacks",
			"max_stack_count",
			"slot_capacity",
			"max_slots",
		])
		if snapshot.has("unlock_consumed_actor_id"):
			snapshot["unlock_consumed_actor_id"] = int(snapshot.get("unlock_consumed_actor_id", 0))
		output.append(snapshot)
	return output


func _container_type_for_session(session: Dictionary, container_id: String) -> String:
	var explicit := str(session.get("container_type", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	if container_id.begins_with("corpse_"):
		return "corpse"
	if container_id.begins_with("drop_"):
		return "drop"
	return "map"


func _container_origin_for_session(session: Dictionary, container_id: String) -> String:
	var explicit := str(session.get("container_origin", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	match _container_type_for_session(session, container_id):
		"corpse":
			return "combat_defeat"
		"drop":
			return "inventory_drop"
	return "map_scene"


func _door_state_snapshots(door_states: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = door_states.keys()
	ids.sort()
	for door_id in ids:
		var state: Dictionary = _dictionary_or_empty(door_states[door_id])
		var snapshot := {
			"door_id": str(state.get("door_id", door_id)),
			"object_id": str(state.get("object_id", door_id)),
			"display_name": str(state.get("display_name", door_id)),
			"is_open": bool(state.get("is_open", false)),
			"locked": bool(state.get("locked", false)),
			"blocks_movement": bool(state.get("blocks_movement", not bool(state.get("is_open", false)))),
			"blocks_sight": bool(state.get("blocks_sight", not bool(state.get("is_open", false)))),
			"blocks_sight_when_closed": bool(state.get("blocks_sight_when_closed", true)),
		}
		_copy_optional_keys(snapshot, state, [
			"required_item_ids",
			"required_items",
			"required_tool_ids",
			"required_tools",
			"consume_required_items_on_unlock",
			"consume_required_tools_on_unlock",
			"consume_required_items",
			"consume_required_tools",
			"consume_keys_on_unlock",
			"consume_tools_on_unlock",
			"required_item_consume_count",
			"required_tool_consume_count",
			"unlock_item_consume_count",
			"unlock_tool_consume_count",
			"key_consume_count",
			"tool_consume_count",
			"tool_durability_cost",
			"unlock_tool_durability_cost",
			"required_tool_durability_cost",
			"unlock_requirements_consumed",
			"unlock_consumed_actor_id",
		])
		if snapshot.has("unlock_consumed_actor_id"):
			snapshot["unlock_consumed_actor_id"] = int(snapshot.get("unlock_consumed_actor_id", 0))
		output.append(snapshot)
	return output


func _shop_session_snapshots(shop_sessions: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = shop_sessions.keys()
	ids.sort()
	for shop_id in ids:
		var session: Dictionary = _dictionary_or_empty(shop_sessions[shop_id])
		var snapshot := {
			"shop_id": str(session.get("shop_id", shop_id)),
			"money": max(0, int(session.get("money", 0))),
			"buy_price_modifier": max(0.0, float(session.get("buy_price_modifier", 1.0))),
			"sell_price_modifier": max(0.0, float(session.get("sell_price_modifier", 1.0))),
			"inventory": _inventory_entries.normalize(session.get("inventory", [])),
		}
		_copy_optional_keys(snapshot, session, [
			"target_actor_id",
			"target_actor_definition_id",
			"required_relationship_min",
			"required_relationship_max",
			"required_world_flags",
			"blocked_world_flags",
		])
		output.append(snapshot)
	return output


func _copy_optional_keys(target: Dictionary, source: Dictionary, keys: Array[String]) -> void:
	for key in keys:
		if source.has(key):
			target[key] = source.get(key)


func _corpse_container_snapshots(corpse_containers: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = corpse_containers.keys()
	ids.sort()
	for corpse_id in ids:
		var corpse: Dictionary = _dictionary_or_empty(corpse_containers[corpse_id])
		output.append({
			"container_id": str(corpse.get("container_id", corpse_id)),
			"container_type": str(corpse.get("container_type", "corpse")),
			"container_origin": str(corpse.get("container_origin", "combat_defeat")),
			"map_id": str(corpse.get("map_id", "")),
			"grid_position": _dictionary_or_empty(corpse.get("grid_position", {})).duplicate(true),
			"display_name": str(corpse.get("display_name", corpse_id)),
			"source_actor_id": int(corpse.get("source_actor_id", 0)),
			"source_actor_definition_id": str(corpse.get("source_actor_definition_id", "")),
			"source_actor_kind": str(corpse.get("source_actor_kind", "")),
			"defeated_by_actor_id": int(corpse.get("defeated_by_actor_id", 0)),
			"appearance_profile_id": str(corpse.get("appearance_profile_id", "")),
			"model_asset": str(corpse.get("model_asset", "")),
			"equipped_slots": _dictionary_or_empty(corpse.get("equipped_slots", {})).duplicate(true),
			"money": max(0, int(corpse.get("money", 0))),
			"inventory": _inventory_entries.normalize(corpse.get("inventory", [])),
		})
	return output


func _hotbar_group_snapshots(hotbar_groups: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	var group_ids: Array = hotbar_groups.keys()
	group_ids.sort()
	for group_id in group_ids:
		output[str(group_id)] = _dictionary_or_empty(hotbar_groups.get(group_id, {})).duplicate(true)
	return output


func _hotbar_group_label_snapshots(hotbar_group_labels: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	var group_ids: Array = hotbar_group_labels.keys()
	group_ids.sort()
	for group_id in group_ids:
		var label := str(hotbar_group_labels.get(group_id, "")).strip_edges()
		if label.is_empty():
			continue
		output[str(group_id)] = label
	return output


func _crafting_queue_snapshots(entries: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry in entries:
		var data: Dictionary = _dictionary_or_empty(entry)
		var recipe_id := str(data.get("recipe_id", "")).strip_edges()
		if recipe_id.is_empty():
			continue
		output.append({
			"recipe_id": recipe_id,
			"count": max(1, int(data.get("count", 1))),
		})
	return output


func _current_control_actor_snapshot(simulation: RefCounted) -> Dictionary:
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


func _runtime_command_queue(simulation: RefCounted) -> Array[Dictionary]:
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


func _runtime_command_history(events: Array[Dictionary]) -> Array[Dictionary]:
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
	var start: int = max(0, order.size() - 12)
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


func _pending_progression_step(control_actor: Dictionary) -> Dictionary:
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


func _recent_interaction_target(events: Array[Dictionary], interaction_menu: Dictionary) -> Dictionary:
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


func _recent_failure(events: Array[Dictionary]) -> Dictionary:
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


func _recent_event_feedback(events: Array[Dictionary]) -> Array[Dictionary]:
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
		if output.size() >= 5:
			break
	return output


func _target_preview(interaction_menu: Dictionary, pending_interaction: Dictionary, recent_interaction: Dictionary) -> Dictionary:
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


func _target_selection_state(interaction_menu: Dictionary, pending_interaction: Dictionary) -> Dictionary:
	var has_prompt := not interaction_menu.is_empty()
	return {
		"has_selection": has_prompt or not pending_interaction.is_empty(),
		"has_prompt": has_prompt,
		"has_pending_interaction": not pending_interaction.is_empty(),
		"target": _target_summary_from_prompt(interaction_menu) if has_prompt else _dictionary_or_empty(pending_interaction.get("target", {})).duplicate(true),
	}


func _ui_menu_state_refs(simulation: RefCounted) -> Dictionary:
	return {
		"interaction_menu_open": not simulation.interaction_menu.is_empty(),
		"interaction_menu_target": _target_summary_from_prompt(simulation.interaction_menu),
		"active_dialogue_actor_id": _active_actor_with_field(simulation, "active_dialogue_id"),
		"active_container_actor_id": _active_actor_with_field(simulation, "active_container_id"),
		"pending_movement": not simulation.pending_movement.is_empty(),
		"pending_interaction": not simulation.pending_interaction.is_empty(),
		"pending_crafting": not simulation.pending_crafting.is_empty(),
	}


func _debug_runtime_diagnostics(simulation: RefCounted, events: Array[Dictionary], runtime_queue: Array[Dictionary], command_history: Array[Dictionary], recent_failure: Dictionary, target_preview: Dictionary, recent_feedback: Array[Dictionary]) -> Dictionary:
	var latest_command: Dictionary = {}
	if not command_history.is_empty():
		latest_command = _dictionary_or_empty(command_history[command_history.size() - 1]).duplicate(true)
	return {
		"event_count": events.size(),
		"command_history_count": command_history.size(),
		"command_history_limit": 12,
		"queued_command_count": runtime_queue.size(),
		"pending_movement": not simulation.pending_movement.is_empty(),
		"pending_interaction": not simulation.pending_interaction.is_empty(),
		"pending_crafting": not simulation.pending_crafting.is_empty(),
		"interaction_menu_open": not simulation.interaction_menu.is_empty(),
		"recent_feedback_count": recent_feedback.size(),
		"latest_command": latest_command,
		"latest_failure_reason": str(recent_failure.get("reason", "")),
		"target_preview_source": str(target_preview.get("source", "")),
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
