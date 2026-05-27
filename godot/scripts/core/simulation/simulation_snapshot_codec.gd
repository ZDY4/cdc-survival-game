extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const SimulationEvent = preload("res://scripts/core/simulation/simulation_event.gd")

var _inventory_entries := InventoryEntries.new()


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
	simulation.active_map_id = str(snapshot_data.get("active_map_id", ""))
	simulation.start_location_id = str(snapshot_data.get("start_location_id", ""))
	simulation.start_entry_point_id = str(snapshot_data.get("start_entry_point_id", ""))
	simulation.active_location_id = str(snapshot_data.get("active_location_id", snapshot_data.get("start_location_id", "")))
	simulation.active_entry_point_id = str(snapshot_data.get("active_entry_point_id", snapshot_data.get("start_entry_point_id", "")))
	simulation.unlocked_locations = _string_array(snapshot_data.get("unlocked_locations", []))
	simulation.actor_registry.load_snapshot(snapshot_data.get("actors", []))
	simulation.events = _load_events(snapshot_data.get("events", []))
	simulation.consumed_interaction_targets = _load_consumed_targets(snapshot_data.get("consumed_interaction_targets", []))
	simulation.container_sessions = _load_container_sessions(snapshot_data.get("container_sessions", []))
	simulation.shop_sessions = _load_shop_sessions(snapshot_data.get("shop_sessions", []))
	simulation.active_quests = _load_active_quests(snapshot_data.get("active_quests", []))
	simulation.completed_quests = _load_completed_quests(snapshot_data.get("completed_quests", []))
	simulation.ai_intents = _load_ai_intents(snapshot_data.get("ai_intents", []))
	simulation._vision_rules.load_snapshot(_dictionary_or_empty(snapshot_data.get("vision", {})))


func _load_events(entries: Variant) -> Array[SimulationEvent]:
	var output: Array[SimulationEvent] = []
	for event_data in _array_or_empty(entries):
		var event: Dictionary = _dictionary_or_empty(event_data)
		output.append(SimulationEvent.new(str(event.get("kind", "")), _dictionary_or_empty(event.get("payload", {}))))
	return output


func _load_consumed_targets(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	for target_id in _array_or_empty(entries):
		output[str(target_id)] = true
	return output


func _load_container_sessions(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	for session in _array_or_empty(entries):
		var session_data: Dictionary = _dictionary_or_empty(session)
		var container_id: String = str(session_data.get("container_id", ""))
		if container_id.is_empty():
			continue
		output[container_id] = {
			"container_id": container_id,
			"display_name": str(session_data.get("display_name", container_id)),
			"inventory": _array_or_empty(session_data.get("inventory", [])).duplicate(true),
		}
	return output


func _load_shop_sessions(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	for session in _array_or_empty(entries):
		var shop_data: Dictionary = _dictionary_or_empty(session)
		var shop_id: String = str(shop_data.get("shop_id", ""))
		if shop_id.is_empty():
			continue
		output[shop_id] = {
			"shop_id": shop_id,
			"money": max(0, int(shop_data.get("money", 0))),
			"buy_price_modifier": max(0.0, float(shop_data.get("buy_price_modifier", 1.0))),
			"sell_price_modifier": max(0.0, float(shop_data.get("sell_price_modifier", 1.0))),
			"inventory": _inventory_entries.normalize(shop_data.get("inventory", [])),
		}
	return output


func _load_active_quests(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	for quest_state in _array_or_empty(entries):
		var state: Dictionary = _dictionary_or_empty(quest_state)
		var quest_id: String = str(state.get("quest_id", ""))
		if quest_id.is_empty():
			continue
		output[quest_id] = {
			"quest_id": quest_id,
			"current_node_id": str(state.get("current_node_id", "")),
			"completed_objectives": _dictionary_or_empty(state.get("completed_objectives", {})).duplicate(true),
		}
	return output


func _load_completed_quests(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	for quest_id in _array_or_empty(entries):
		output[str(quest_id)] = true
	return output


func _load_ai_intents(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	for intent in _array_or_empty(entries):
		var intent_data: Dictionary = _dictionary_or_empty(intent)
		var actor_id: int = int(intent_data.get("actor_id", 0))
		if actor_id > 0:
			output[actor_id] = intent_data.duplicate(true)
	return output


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


func _string_array(values: Variant) -> Array[String]:
	var output: Array[String] = []
	for value in _array_or_empty(values):
		output.append(str(value))
	return output
