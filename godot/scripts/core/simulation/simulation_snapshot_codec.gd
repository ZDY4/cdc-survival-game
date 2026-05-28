extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const SimulationSnapshotLoader = preload("res://scripts/core/simulation/simulation_snapshot_loader.gd")

var _inventory_entries := InventoryEntries.new()
var _loader := SimulationSnapshotLoader.new()


func build(simulation: RefCounted) -> Dictionary:
	var event_output: Array[Dictionary] = []
	for event in simulation.events:
		event_output.append(event.to_dictionary())
	return {
		"schema_version": 1,
		"active_map_id": simulation.active_map_id,
		"start_location_id": simulation.start_location_id,
		"start_entry_point_id": simulation.start_entry_point_id,
		"active_location_id": simulation.active_location_id,
		"active_entry_point_id": simulation.active_entry_point_id,
		"unlocked_locations": simulation.unlocked_locations.duplicate(),
		"actors": simulation.actor_registry.snapshot(),
		"events": event_output,
		"consumed_interaction_targets": simulation.consumed_interaction_targets.keys(),
		"container_sessions": _container_session_snapshots(simulation.container_sessions),
		"shop_sessions": _shop_session_snapshots(simulation.shop_sessions),
		"active_quests": _active_quest_snapshots(simulation.active_quests),
		"completed_quests": simulation.completed_quests.keys(),
		"ai_intents": _ai_intent_snapshots(simulation.ai_intents),
		"vision": simulation._vision_rules.snapshot(),
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


func _container_session_snapshots(container_sessions: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = container_sessions.keys()
	ids.sort()
	for container_id in ids:
		var session: Dictionary = _dictionary_or_empty(container_sessions[container_id])
		output.append({
			"container_id": str(session.get("container_id", container_id)),
			"display_name": str(session.get("display_name", container_id)),
			"inventory": _array_or_empty(session.get("inventory", [])).duplicate(true),
		})
	return output


func _shop_session_snapshots(shop_sessions: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = shop_sessions.keys()
	ids.sort()
	for shop_id in ids:
		var session: Dictionary = _dictionary_or_empty(shop_sessions[shop_id])
		output.append({
			"shop_id": str(session.get("shop_id", shop_id)),
			"money": max(0, int(session.get("money", 0))),
			"buy_price_modifier": max(0.0, float(session.get("buy_price_modifier", 1.0))),
			"sell_price_modifier": max(0.0, float(session.get("sell_price_modifier", 1.0))),
			"inventory": _inventory_entries.normalize(session.get("inventory", [])),
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
