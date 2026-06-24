extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const SimulationDerivedView = preload("res://scripts/core/simulation/simulation_derived_view.gd")

const CURRENT_SCHEMA_VERSION := 1

var _inventory_entries := InventoryEntries.new()
# 派生字段（最近失败、目标预览、命令历史等）统一委托给该助手计算，UI 构建器也复用同一逻辑。
var _derived := SimulationDerivedView.new()


func build(simulation: RefCounted) -> Dictionary:
	var event_output: Array[Dictionary] = _derived.serialize_events(simulation)
	var control_actor: Dictionary = _derived.current_control_actor(simulation)
	var recent_failure: Dictionary = _derived.recent_failure(event_output)
	var recent_interaction: Dictionary = _derived.recent_interaction_target(event_output, simulation.interaction_menu)
	var runtime_queue: Array[Dictionary] = _derived.runtime_command_queue(simulation)
	var command_history: Array[Dictionary] = _derived.runtime_command_history(event_output)
	var target_preview: Dictionary = _derived.target_preview(simulation.interaction_menu, simulation.pending_interaction, recent_interaction)
	var recent_feedback: Array[Dictionary] = _derived.recent_event_feedback(event_output)
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
		"pending_progression_step": _derived.pending_progression_step(control_actor),
		"current_control_actor": control_actor,
		"recent_interaction_target": recent_interaction,
		"recent_failure": recent_failure,
		"recent_event_feedback": recent_feedback,
		"target_preview": target_preview,
		"target_selection_state": _derived.target_selection_state(simulation.interaction_menu, simulation.pending_interaction),
		"ui_menu_state_refs": _derived.ui_menu_state_refs(simulation),
		"debug_runtime_diagnostics": _derived.debug_runtime_diagnostics(simulation, event_output, runtime_queue, command_history, recent_failure, target_preview, recent_feedback),
		"corpse_containers": _corpse_container_snapshots(simulation.corpse_containers),
		"interaction_menu": simulation.interaction_menu.duplicate(true),
		"hotbar": simulation.hotbar.duplicate(true),
		"active_hotbar_group": str(simulation.active_hotbar_group),
		"hotbar_groups": _hotbar_group_snapshots(simulation.hotbar_groups),
		"hotbar_group_labels": _hotbar_group_label_snapshots(simulation.hotbar_group_labels),
		"crafted_recipes": simulation.crafted_recipes.keys(),
	}


## 世界表现层（world_snapshot_builder / fog / debug overlay / 刷新日志）实际消费的精简运行时视图。
## 只序列化这些消费者读取的字段，避免世界重建时跑整局全量 snapshot()（省掉派生字段的多轮 events 扫描、
## relationships/ai_intents/hotbar 等无关序列化）。字段值与 build() 中对应项保持一致，故世界产物不变。
func build_world_runtime_view(simulation: RefCounted) -> Dictionary:
	return {
		"active_map_id": simulation.active_map_id,
		"active_location_id": simulation.active_location_id,
		"actors": simulation.actor_registry.snapshot(),
		"events": _derived.serialize_events(simulation),
		"vision": simulation._vision_rules.snapshot(),
		"world_time": simulation.world_time.duplicate(true),
		"door_states": _door_state_snapshots(simulation.door_states),
		"container_sessions": _container_session_snapshots(simulation.container_sessions),
		"shop_sessions": _shop_session_snapshots(simulation.shop_sessions),
		"corpse_containers": _corpse_container_snapshots(simulation.corpse_containers),
		"consumed_interaction_targets": simulation.consumed_interaction_targets.keys(),
		"active_quests": _active_quest_snapshots(simulation.active_quests),
		"completed_quests": simulation.completed_quests.keys(),
	}


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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
