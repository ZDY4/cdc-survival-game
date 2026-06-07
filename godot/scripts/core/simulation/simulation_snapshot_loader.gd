extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const SimulationEvent = preload("res://scripts/core/simulation/simulation_event.gd")

const CURRENT_SCHEMA_VERSION := 1

var _inventory_entries := InventoryEntries.new()


func load(simulation: RefCounted, snapshot_data: Dictionary) -> void:
	var source_schema_version: int = int(snapshot_data.get("schema_version", 0))
	# 这里是存档格式兼容边界：旧快照缺少 active_* 字段时仍回退到 start_*。
	simulation.active_map_id = str(snapshot_data.get("active_map_id", ""))
	simulation.start_location_id = str(snapshot_data.get("start_location_id", ""))
	simulation.start_entry_point_id = str(snapshot_data.get("start_entry_point_id", ""))
	simulation.active_location_id = str(snapshot_data.get("active_location_id", snapshot_data.get("start_location_id", "")))
	simulation.active_entry_point_id = str(snapshot_data.get("active_entry_point_id", snapshot_data.get("start_entry_point_id", "")))
	simulation.unlocked_locations = _string_array(snapshot_data.get("unlocked_locations", []))
	simulation.actor_registry.load_snapshot(snapshot_data.get("actors", []))
	simulation.events = _load_events(snapshot_data.get("events", []))
	simulation.consumed_interaction_targets = _load_consumed_targets(snapshot_data.get("consumed_interaction_targets", []))
	simulation.door_states = _load_door_states(snapshot_data.get("door_states", []))
	simulation.container_sessions = _load_container_sessions(snapshot_data.get("container_sessions", []))
	simulation.shop_sessions = _load_shop_sessions(snapshot_data.get("shop_sessions", []))
	simulation.active_quests = _load_active_quests(snapshot_data.get("active_quests", []))
	simulation.completed_quests = _load_completed_quests(snapshot_data.get("completed_quests", []))
	simulation.world_flags = _load_flag_dictionary(snapshot_data.get("world_flags", []))
	simulation.relationships = _load_relationships(snapshot_data.get("relationships", []))
	_initialize_missing_relationships(simulation)
	simulation.ai_intents = _load_ai_intents(snapshot_data.get("ai_intents", []))
	simulation._vision_rules.load_snapshot(_dictionary_or_empty(snapshot_data.get("vision", {})))
	simulation.turn_state = _dictionary_or_empty(snapshot_data.get("turn_state", simulation.turn_state)).duplicate(true)
	simulation.combat_state = _dictionary_or_empty(snapshot_data.get("combat_state", simulation.combat_state)).duplicate(true)
	if not simulation.combat_state.has("turn_order"):
		simulation.combat_state["turn_order"] = []
	if not simulation.combat_state.has("initiative"):
		simulation.combat_state["initiative"] = []
	if not simulation.combat_state.has("current_combat_actor_id"):
		simulation.combat_state["current_combat_actor_id"] = int(_dictionary_or_empty(simulation.turn_state).get("active_actor_id", 0)) if bool(simulation.combat_state.get("active", false)) else 0
	if not simulation.combat_state.has("next_combat_actor_id"):
		simulation.combat_state["next_combat_actor_id"] = 0
	if not simulation.combat_state.has("turns_without_hostile_player_sight"):
		simulation.combat_state["turns_without_hostile_player_sight"] = 0
	if not simulation.combat_state.has("combat_rng_seed"):
		simulation.combat_state["combat_rng_seed"] = 12648430
	if not simulation.combat_state.has("combat_rng_counter"):
		simulation.combat_state["combat_rng_counter"] = 0
	simulation.pending_movement = _dictionary_or_empty(snapshot_data.get("pending_movement", {})).duplicate(true)
	simulation.pending_interaction = _dictionary_or_empty(snapshot_data.get("pending_interaction", {})).duplicate(true)
	simulation.pending_crafting = _dictionary_or_empty(snapshot_data.get("pending_crafting", {})).duplicate(true)
	simulation.corpse_containers = _load_corpse_containers(snapshot_data.get("corpse_containers", []))
	_sync_corpse_container_sessions(simulation)
	simulation.interaction_menu = _dictionary_or_empty(snapshot_data.get("interaction_menu", {})).duplicate(true)
	_load_hotbar_state(simulation, snapshot_data)
	simulation.crafted_recipes = _load_flag_dictionary(snapshot_data.get("crafted_recipes", []))
	if source_schema_version < CURRENT_SCHEMA_VERSION:
		simulation.emit_event("snapshot_migrated", {
			"from_schema_version": source_schema_version,
			"to_schema_version": CURRENT_SCHEMA_VERSION,
		})


func _load_events(entries: Variant) -> Array[SimulationEvent]:
	var output: Array[SimulationEvent] = []
	for event_data in _array_or_empty(entries):
		var event: Dictionary = _dictionary_or_empty(event_data)
		output.append(SimulationEvent.new(str(event.get("kind", "")), _dictionary_or_empty(event.get("payload", {}))))
	return output


func _load_hotbar_state(simulation: RefCounted, snapshot_data: Dictionary) -> void:
	var active_group_id := str(snapshot_data.get("active_hotbar_group", "group_1"))
	if active_group_id.is_empty():
		active_group_id = "group_1"
	var groups: Dictionary = _dictionary_or_empty(snapshot_data.get("hotbar_groups", {})).duplicate(true)
	var legacy_hotbar: Dictionary = _dictionary_or_empty(snapshot_data.get("hotbar", {})).duplicate(true)
	if groups.is_empty():
		groups[active_group_id] = legacy_hotbar
	if not groups.has(active_group_id):
		groups[active_group_id] = legacy_hotbar
	simulation.active_hotbar_group = active_group_id
	simulation.hotbar_groups = groups
	simulation.hotbar_group_labels = _dictionary_or_empty(snapshot_data.get("hotbar_group_labels", {})).duplicate(true)
	if simulation.has_method("set_active_hotbar_group"):
		simulation.set_active_hotbar_group(active_group_id)
	else:
		simulation.hotbar = _dictionary_or_empty(groups.get(active_group_id, {})).duplicate(true)


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
		var loaded_session := {
			"container_id": container_id,
			"container_type": _container_type_for_session(session_data, container_id),
			"container_origin": _container_origin_for_session(session_data, container_id),
			"display_name": str(session_data.get("display_name", container_id)),
			"money": max(0, int(session_data.get("money", 0))),
			"inventory": _array_or_empty(session_data.get("inventory", [])).duplicate(true),
		}
		_copy_optional_keys(loaded_session, session_data, [
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
		output[container_id] = loaded_session
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


func _load_door_states(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	for entry in _array_or_empty(entries):
		var state: Dictionary = _dictionary_or_empty(entry)
		var door_id: String = str(state.get("door_id", state.get("object_id", "")))
		if door_id.is_empty():
			continue
		var loaded_state := {
			"door_id": door_id,
			"object_id": str(state.get("object_id", door_id)),
			"display_name": str(state.get("display_name", door_id)),
			"is_open": bool(state.get("is_open", false)),
			"locked": bool(state.get("locked", false)),
			"blocks_movement": bool(state.get("blocks_movement", not bool(state.get("is_open", false)))),
			"blocks_sight": bool(state.get("blocks_sight", not bool(state.get("is_open", false)))),
			"blocks_sight_when_closed": bool(state.get("blocks_sight_when_closed", true)),
		}
		_copy_optional_keys(loaded_state, state, [
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
		output[door_id] = loaded_state
	return output


func _load_shop_sessions(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	for session in _array_or_empty(entries):
		var shop_data: Dictionary = _dictionary_or_empty(session)
		var shop_id: String = str(shop_data.get("shop_id", ""))
		if shop_id.is_empty():
			continue
		var loaded_session := {
			"shop_id": shop_id,
			"money": max(0, int(shop_data.get("money", 0))),
			"buy_price_modifier": max(0.0, float(shop_data.get("buy_price_modifier", 1.0))),
			"sell_price_modifier": max(0.0, float(shop_data.get("sell_price_modifier", 1.0))),
			"inventory": _inventory_entries.normalize(shop_data.get("inventory", [])),
		}
		_copy_optional_keys(loaded_session, shop_data, [
			"target_actor_id",
			"target_actor_definition_id",
			"required_relationship_min",
			"required_relationship_max",
			"required_world_flags",
			"blocked_world_flags",
		])
		output[shop_id] = loaded_session
	return output


func _copy_optional_keys(target: Dictionary, source: Dictionary, keys: Array[String]) -> void:
	for key in keys:
		if source.has(key):
			target[key] = source.get(key)


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
	return _load_flag_dictionary(entries)


func _load_flag_dictionary(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	for value in _array_or_empty(entries):
		output[str(value)] = true
	return output


func _load_ai_intents(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	for intent in _array_or_empty(entries):
		var intent_data: Dictionary = _dictionary_or_empty(intent)
		var actor_id: int = int(intent_data.get("actor_id", 0))
		if actor_id > 0:
			output[actor_id] = intent_data.duplicate(true)
	return output


func _load_relationships(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	if typeof(entries) == TYPE_DICTIONARY:
		for key in _dictionary_or_empty(entries).keys():
			var normalized_key := _relationship_key_from_string(str(key))
			if normalized_key.is_empty():
				continue
			output[normalized_key] = clampf(float(_dictionary_or_empty(entries).get(key, 0.0)), -100.0, 100.0)
		return output
	for entry in _array_or_empty(entries):
		var relationship: Dictionary = _dictionary_or_empty(entry)
		var actor_id := int(relationship.get("actor_id", 0))
		var target_actor_id := int(relationship.get("target_actor_id", 0))
		var key := _relationship_key(actor_id, target_actor_id)
		if key.is_empty():
			continue
		output[key] = clampf(float(relationship.get("score", 0.0)), -100.0, 100.0)
	return output


func _initialize_missing_relationships(simulation: RefCounted) -> void:
	if not simulation.has_method("_initialize_relationships_for_actor"):
		return
	for actor in simulation.actor_registry.actors():
		simulation.call("_initialize_relationships_for_actor", actor)


func _relationship_key(actor_id: int, target_actor_id: int) -> String:
	if actor_id <= 0 or target_actor_id <= 0 or actor_id == target_actor_id:
		return ""
	return "%d:%d" % [min(actor_id, target_actor_id), max(actor_id, target_actor_id)]


func _relationship_key_from_string(key: String) -> String:
	var parts := key.split(":", false)
	if parts.size() != 2:
		return ""
	return _relationship_key(int(parts[0]), int(parts[1]))


func _load_corpse_containers(entries: Variant) -> Dictionary:
	var output: Dictionary = {}
	for corpse in _array_or_empty(entries):
		var corpse_data: Dictionary = _dictionary_or_empty(corpse)
		var container_id: String = str(corpse_data.get("container_id", ""))
		if container_id.is_empty():
			continue
		output[container_id] = {
			"container_id": container_id,
			"container_type": str(corpse_data.get("container_type", "corpse")),
			"container_origin": str(corpse_data.get("container_origin", "combat_defeat")),
			"map_id": str(corpse_data.get("map_id", "")),
			"grid_position": _dictionary_or_empty(corpse_data.get("grid_position", {})).duplicate(true),
			"display_name": str(corpse_data.get("display_name", container_id)),
			"source_actor_id": int(corpse_data.get("source_actor_id", 0)),
			"source_actor_definition_id": str(corpse_data.get("source_actor_definition_id", "")),
			"source_actor_kind": str(corpse_data.get("source_actor_kind", "")),
			"defeated_by_actor_id": int(corpse_data.get("defeated_by_actor_id", 0)),
			"appearance_profile_id": str(corpse_data.get("appearance_profile_id", "")),
			"model_asset": str(corpse_data.get("model_asset", "")),
			"equipped_slots": _dictionary_or_empty(corpse_data.get("equipped_slots", {})).duplicate(true),
			"money": max(0, int(corpse_data.get("money", 0))),
			"inventory": _inventory_entries.normalize(corpse_data.get("inventory", [])),
		}
	return output


func _sync_corpse_container_sessions(simulation: RefCounted) -> void:
	for container_id_value in simulation.corpse_containers.keys():
		var container_id := str(container_id_value)
		var corpse: Dictionary = _dictionary_or_empty(simulation.corpse_containers.get(container_id, {})).duplicate(true)
		var session: Dictionary = _dictionary_or_empty(simulation.container_sessions.get(container_id, {})).duplicate(true)
		if session.is_empty():
			session = {
				"container_id": container_id,
				"container_type": _container_type_for_session(corpse, container_id),
				"container_origin": _container_origin_for_session(corpse, container_id),
				"display_name": str(corpse.get("display_name", container_id)),
				"money": max(0, int(corpse.get("money", 0))),
				"inventory": _inventory_entries.normalize(corpse.get("inventory", [])),
			}
		_copy_missing_container_metadata(session, corpse, container_id)
		corpse["inventory"] = _array_or_empty(session.get("inventory", corpse.get("inventory", []))).duplicate(true)
		corpse["money"] = max(0, int(session.get("money", corpse.get("money", 0))))
		_copy_missing_container_metadata(corpse, session, container_id)
		simulation.container_sessions[container_id] = session
		simulation.corpse_containers[container_id] = corpse


func _copy_missing_container_metadata(target: Dictionary, source: Dictionary, container_id: String) -> void:
	if not target.has("container_type") or str(target.get("container_type", "")).strip_edges().is_empty():
		target["container_type"] = _container_type_for_session(source, container_id)
	if not target.has("container_origin") or str(target.get("container_origin", "")).strip_edges().is_empty():
		target["container_origin"] = _container_origin_for_session(source, container_id)
	for key in [
		"map_id",
		"grid_position",
		"source_actor_id",
		"source_actor_definition_id",
		"source_actor_kind",
		"defeated_by_actor_id",
		"appearance_profile_id",
		"model_asset",
		"equipped_slots",
		"drop_item_id",
	]:
		if (not target.has(key) or _metadata_value_empty(target.get(key))) and source.has(key):
			target[key] = source.get(key)


func _metadata_value_empty(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL:
			return true
		TYPE_STRING:
			return str(value).strip_edges().is_empty()
		TYPE_ARRAY:
			return (value as Array).is_empty()
		TYPE_DICTIONARY:
			return (value as Dictionary).is_empty()
	return false


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
