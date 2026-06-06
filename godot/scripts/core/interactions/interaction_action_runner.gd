extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const InventoryCapacity = preload("res://scripts/core/economy/inventory_capacity.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const MapBuilder = preload("res://scripts/world/map_builder.gd")
const MapSceneLoader = preload("res://scripts/world/map_scene_loader.gd")

var _inventory_entries := InventoryEntries.new()
var _inventory_capacity := InventoryCapacity.new()
var _map_builder := MapBuilder.new()
var _map_scene_loader := MapSceneLoader.new()


func execute(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	match str(option.get("kind", "")):
		"pickup":
			return _execute_pickup(simulation, actor_id, prompt, option)
		"talk":
			return _execute_talk(simulation, actor_id, prompt, option)
		"open_container":
			return _execute_open_container(simulation, actor_id, prompt, option)
		"attack":
			return _execute_attack(simulation, actor_id, prompt, option)
		"wait":
			return _execute_wait(simulation, actor_id, prompt, option)
		"move":
			return {"success": false, "reason": "move_requires_player_command", "prompt": prompt}
		"door_toggle":
			return _execute_door_toggle(simulation, actor_id, prompt, option)
		"enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor":
			return _execute_scene_transition(simulation, actor_id, prompt, option)
		_:
			return {
				"success": false,
				"reason": "unsupported_interaction_kind",
				"prompt": prompt,
			}


func _execute_pickup(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt}

	var item_id: String = _inventory_entries.normalize_content_id(option.get("item_id", ""))
	var count: int = max(1, int(option.get("count", 1)))
	if item_id.is_empty():
		return {"success": false, "reason": "pickup_item_invalid", "prompt": prompt}

	var capacity: Dictionary = _inventory_capacity.can_add_items(actor, _dictionary_or_empty(simulation.get("item_library")), [
		{"item_id": item_id, "count": count},
	])
	if not bool(capacity.get("success", false)):
		capacity["prompt"] = prompt
		capacity["target_id"] = str(option.get("target_id", ""))
		return capacity

	var before_count: int = int(actor.inventory.get(item_id, 0))
	_inventory_entries.add_actor_item(actor, item_id, count)
	var after_count: int = int(actor.inventory.get(item_id, 0))
	simulation.record_item_collected(actor_id, item_id, count)
	var target_id: String = str(option.get("target_id", ""))
	simulation.consumed_interaction_targets[target_id] = true
	simulation.emit_event("pickup_granted", {
		"actor_id": actor_id,
		"target_id": target_id,
		"item_id": item_id,
		"count": count,
		"inventory_before": before_count,
		"inventory_after": after_count,
	})
	var success_payload: Dictionary = _interaction_success_payload(actor_id, prompt, option, target_id)
	success_payload["item_id"] = item_id
	success_payload["count"] = count
	success_payload["inventory_before"] = before_count
	success_payload["inventory_after"] = after_count
	simulation.emit_event("interaction_succeeded", success_payload)
	return {
		"success": true,
		"prompt": prompt,
		"consumed_target": true,
		"item_id": item_id,
		"count": count,
		"inventory_before": before_count,
		"inventory_after": after_count,
	}


func _execute_talk(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt}

	var requested_dialogue_id: String = str(option.get("dialogue_id", ""))
	var target: Dictionary = _dictionary_or_empty(prompt.get("target", {}))
	var target_actor: RefCounted = simulation.actor_registry.get_actor(int(target.get("actor_id", 0)))
	var dialogue_resolution: Dictionary = _resolve_dialogue_id(simulation, actor, target_actor, requested_dialogue_id)
	var dialogue_id: String = str(dialogue_resolution.get("dialogue_id", requested_dialogue_id))
	if dialogue_id.is_empty():
		return {"success": false, "reason": "dialogue_missing", "prompt": prompt}
	actor.active_dialogue_id = dialogue_id
	actor.active_dialogue_node_id = ""
	simulation.emit_event("dialogue_started", {
		"actor_id": actor_id,
		"target_actor_id": int(target.get("actor_id", 0)),
		"dialogue_id": dialogue_id,
		"requested_dialogue_id": requested_dialogue_id,
		"dialogue_rule_key": str(dialogue_resolution.get("rule_key", "")),
		"dialogue_rule_source": str(dialogue_resolution.get("source", "direct")),
	})
	var success_payload: Dictionary = _interaction_success_payload(actor_id, prompt, option, target.get("actor_id", 0))
	success_payload["dialogue_id"] = dialogue_id
	success_payload["requested_dialogue_id"] = requested_dialogue_id
	success_payload["dialogue_rule_key"] = str(dialogue_resolution.get("rule_key", ""))
	success_payload["dialogue_rule_source"] = str(dialogue_resolution.get("source", "direct"))
	simulation.emit_event("interaction_succeeded", success_payload)
	return {
		"success": true,
		"prompt": prompt,
		"dialogue_id": dialogue_id,
		"requested_dialogue_id": requested_dialogue_id,
		"dialogue_rule_key": str(dialogue_resolution.get("rule_key", "")),
		"dialogue_rule_source": str(dialogue_resolution.get("source", "direct")),
	}


func _execute_open_container(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt}

	var target: Dictionary = _dictionary_or_empty(prompt.get("target", {}))
	var target_id: String = str(option.get("target_id", target.get("target_id", "")))
	if target_id.is_empty():
		return {"success": false, "reason": "container_target_missing", "prompt": prompt}

	var session: Dictionary = _container_session_for_target(simulation, target_id, target)
	var previous_container_id := str(actor.active_container_id)
	if not previous_container_id.is_empty() and previous_container_id != target_id:
		simulation.emit_event("container_closed", {
			"actor_id": actor_id,
			"container_id": previous_container_id,
			"reason": "replaced",
			"next_container_id": target_id,
		})
	actor.active_container_id = target_id
	simulation.emit_event("container_opened", {
		"actor_id": actor_id,
		"target_id": target_id,
		"display_name": session.get("display_name", target_id),
		"item_count": _array_or_empty(session.get("inventory", [])).size(),
	})
	simulation.emit_event("interaction_succeeded", _interaction_success_payload(actor_id, prompt, option, target_id))
	return {
		"success": true,
		"prompt": prompt,
		"container": session.duplicate(true),
	}


func _execute_attack(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var target_actor_id: int = int(option.get("target_actor_id", prompt.get("target", {}).get("actor_id", 0)))
	var result: Dictionary = simulation.perform_attack(actor_id, target_actor_id)
	if bool(result.get("success", false)):
		simulation.emit_event("interaction_succeeded", _interaction_success_payload(actor_id, prompt, option, target_actor_id))
	result["prompt"] = prompt
	return result


func _execute_wait(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt}
	var result: Dictionary = {}
	if actor.kind == "player" and actor.turn_open and simulation.has_method("_submit_wait_command"):
		result = simulation.call("_submit_wait_command", actor, {
			"kind": "wait",
			"actor_id": actor_id,
		})
	else:
		simulation.emit_event("actor_waited", {
			"actor_id": actor_id,
			"source": "interaction",
		})
		result = {
			"success": true,
			"waited": true,
		}
	simulation.emit_event("interaction_succeeded", _interaction_success_payload(actor_id, prompt, option, actor_id))
	result["prompt"] = prompt
	result["waited"] = true
	return result


func _execute_door_toggle(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var door_id := str(option.get("door_id", option.get("target_id", ""))).strip_edges()
	if door_id.is_empty():
		return {"success": false, "reason": "door_target_missing", "prompt": prompt}
	var result: Dictionary = simulation.toggle_door(actor_id, door_id)
	result["prompt"] = prompt
	if bool(result.get("success", false)):
		var success_payload: Dictionary = _interaction_success_payload(actor_id, prompt, option, door_id)
		success_payload["is_open"] = bool(result.get("is_open", false))
		simulation.emit_event("interaction_succeeded", success_payload)
		result["door_toggled"] = true
	return result


func _container_session_for_target(simulation: RefCounted, target_id: String, target: Dictionary) -> Dictionary:
	if simulation.container_sessions.has(target_id):
		return _dictionary_or_empty(simulation.container_sessions[target_id])
	var session := {
		"container_id": target_id,
		"display_name": str(target.get("display_name", target_id)),
		"inventory": _array_or_empty(target.get("container_inventory", [])).duplicate(true),
		"container_type": str(target.get("container_type", "map")),
		"container_origin": str(target.get("container_origin", "map_scene")),
		"map_id": str(target.get("map_id", simulation.active_map_id)),
	}
	_copy_optional_container_fields(session, target)
	simulation.container_sessions[target_id] = session
	return session


func _resolve_dialogue_id(simulation: RefCounted, actor: RefCounted, target_actor: RefCounted, requested_dialogue_id: String) -> Dictionary:
	var rule_key: String = str(target_actor.definition_id if target_actor != null else requested_dialogue_id)
	var rule_record: Dictionary = _dictionary_or_empty(simulation.dialogue_rule_library.get(rule_key, {}))
	var rule_data: Dictionary = _dictionary_or_empty(rule_record.get("data", rule_record))
	if rule_data.is_empty():
		return {
			"dialogue_id": requested_dialogue_id,
			"rule_key": rule_key,
			"source": "direct",
		}
	for variant in _array_or_empty(rule_data.get("variants", [])):
		var variant_data: Dictionary = _dictionary_or_empty(variant)
		if _dialogue_conditions_match(simulation, actor, target_actor, _dictionary_or_empty(variant_data.get("when", {}))):
			return {
				"dialogue_id": str(variant_data.get("dialogue_id", rule_data.get("default_dialogue_id", requested_dialogue_id))),
				"rule_key": rule_key,
				"source": "variant",
			}
	return {
		"dialogue_id": str(rule_data.get("default_dialogue_id", requested_dialogue_id)),
		"rule_key": rule_key,
		"source": "default",
	}


func _copy_optional_container_fields(session: Dictionary, target: Dictionary) -> void:
	for key in [
		"container_type",
		"container_origin",
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
	]:
		if target.has(key):
			session[key] = target.get(key)


func _dialogue_conditions_match(simulation: RefCounted, actor: RefCounted, target_actor: RefCounted, conditions: Dictionary) -> bool:
	if conditions.is_empty():
		return true
	if conditions.has("player_active_quests_any") and not _dictionary_has_any_key(simulation.active_quests, _array_or_empty(conditions.get("player_active_quests_any", []))):
		return false
	if conditions.has("player_completed_quests_any") and not _dictionary_has_any_key(simulation.completed_quests, _array_or_empty(conditions.get("player_completed_quests_any", []))):
		return false
	if conditions.has("player_item_count_min") and not _player_item_count_min_met(actor, _dictionary_or_empty(conditions.get("player_item_count_min", {}))):
		return false
	if conditions.has("relation_score_min") and _relation_score(simulation, actor, target_actor) < float(conditions.get("relation_score_min", 0.0)):
		return false
	if conditions.has("relation_score_max") and _relation_score(simulation, actor, target_actor) > float(conditions.get("relation_score_max", 0.0)):
		return false
	if conditions.has("npc_role_in") and not _array_or_empty(conditions.get("npc_role_in", [])).has(str(_dictionary_or_empty(target_actor.life if target_actor != null else {}).get("role", ""))):
		return false
	if conditions.has("npc_on_shift") and bool(conditions.get("npc_on_shift", false)) != _npc_on_shift(target_actor):
		return false
	if conditions.has("player_hp_ratio_max") and _hp_ratio(actor) > float(conditions.get("player_hp_ratio_max", 1.0)):
		return false
	return true


func _dictionary_has_any_key(dictionary: Dictionary, keys: Array) -> bool:
	for key in keys:
		if dictionary.has(str(key)):
			return true
	return false


func _player_item_count_min_met(actor: RefCounted, requirements: Dictionary) -> bool:
	if actor == null:
		return false
	for item_id in requirements.keys():
		if int(actor.inventory.get(str(item_id), 0)) < int(requirements[item_id]):
			return false
	return true


func _relation_score(simulation: RefCounted, actor: RefCounted, target_actor: RefCounted) -> float:
	if simulation == null or actor == null or target_actor == null:
		return 0.0
	if simulation.has_method("relationship_score"):
		return float(simulation.call("relationship_score", actor.actor_id, target_actor.actor_id))
	return 0.0


func _npc_on_shift(target_actor: RefCounted) -> bool:
	if target_actor == null:
		return false
	var life: Dictionary = _dictionary_or_empty(target_actor.life)
	if life.has("on_shift"):
		return bool(life.get("on_shift", false))
	if not str(life.get("duty_route_id", "")).is_empty():
		return true
	return false


func _hp_ratio(actor: RefCounted) -> float:
	if actor == null or actor.max_hp <= 0.0:
		return 1.0
	return clampf(actor.hp / actor.max_hp, 0.0, 1.0)


func _execute_scene_transition(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var target_map_id: String = str(option.get("target_map_id", ""))
	if target_map_id.is_empty():
		return {"success": false, "reason": "scene_transition_target_missing", "prompt": prompt, "target_map_id": target_map_id}
	var permission: Dictionary = _scene_transition_permission(simulation, option)
	if not bool(permission.get("success", false)):
		permission["prompt"] = prompt
		permission["target_map_id"] = target_map_id
		return permission

	var previous_map_id: String = simulation.active_map_id
	var target_entry_id := _target_entry_id(option)
	var entry_result := _entry_grid_for_map(target_map_id, target_entry_id)
	if not bool(entry_result.get("ok", false)):
		return {
			"success": false,
			"reason": entry_result.get("reason", "scene_transition_entry_missing"),
			"prompt": prompt,
			"target_map_id": target_map_id,
			"target_entry_point_id": target_entry_id,
		}

	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt, "target_map_id": target_map_id, "target_entry_point_id": target_entry_id}

	var target_grid: Dictionary = _dictionary_or_empty(entry_result.get("grid", {}))
	var entry_facing: String = str(entry_result.get("facing", "")).strip_edges()
	var target_id: String = str(option.get("target_id", ""))
	var target_name: String = str(option.get("display_name", prompt.get("target_name", target_id)))
	var previous_entry_point_id: String = str(simulation.active_entry_point_id)
	simulation.active_map_id = target_map_id
	simulation.active_entry_point_id = target_entry_id
	_configure_map_interactions(simulation, _dictionary_or_empty(entry_result.get("map_data", {})))
	actor.map_id = target_map_id
	actor.grid_position = GridCoord.from_dictionary(target_grid)
	simulation.emit_event("scene_transition", {
		"actor_id": actor_id,
		"target_id": target_id,
		"target_name": target_name,
		"from_map_id": previous_map_id,
		"to_map_id": target_map_id,
		"entry_point_id": target_entry_id,
		"target_entry_point_id": target_entry_id,
		"entry_facing": entry_facing,
		"grid_position": target_grid.duplicate(true),
		"return_map_id": previous_map_id,
		"return_entry_point_id": previous_entry_point_id,
		"kind": option.get("kind", ""),
	})
	var success_payload: Dictionary = _interaction_success_payload(actor_id, prompt, option, target_id)
	success_payload["target_map_id"] = target_map_id
	success_payload["target_entry_point_id"] = target_entry_id
	success_payload["entry_facing"] = entry_facing
	success_payload["return_map_id"] = previous_map_id
	success_payload["return_entry_point_id"] = previous_entry_point_id
	simulation.emit_event("interaction_succeeded", success_payload)
	return {
		"success": true,
		"kind": str(option.get("kind", "scene_transition")),
		"prompt": prompt,
		"target_id": target_id,
		"target_name": target_name,
		"from_map_id": previous_map_id,
		"target_map_id": target_map_id,
		"target_entry_point_id": target_entry_id,
		"entry_facing": entry_facing,
		"grid_position": target_grid.duplicate(true),
		"return_map_id": previous_map_id,
		"return_entry_point_id": previous_entry_point_id,
		"context_snapshot": {
			"active_map_id": simulation.active_map_id,
			"active_entry_point_id": simulation.active_entry_point_id,
			"entry_facing": entry_facing,
			"return_map_id": previous_map_id,
			"return_entry_point_id": previous_entry_point_id,
		},
	}


func _scene_transition_permission(simulation: RefCounted, option: Dictionary) -> Dictionary:
	for flag_id in _string_array(option.get("required_world_flags", [])):
		if not _dictionary_or_empty(simulation.get("world_flags")).has(flag_id):
			return {
				"success": false,
				"reason": "scene_transition_world_flag_missing",
				"flag_id": flag_id,
				"required_world_flags": _string_array(option.get("required_world_flags", [])),
			}
	for flag_id in _string_array(option.get("blocked_world_flags", [])):
		if _dictionary_or_empty(simulation.get("world_flags")).has(flag_id):
			return {
				"success": false,
				"reason": "scene_transition_world_flag_blocked",
				"flag_id": flag_id,
				"blocked_world_flags": _string_array(option.get("blocked_world_flags", [])),
			}
	var unlocked_lookup: Dictionary = _string_lookup(simulation.get("unlocked_locations"))
	for location_id in _string_array(option.get("required_unlocked_locations", [])):
		if not unlocked_lookup.has(location_id):
			return {
				"success": false,
				"reason": "scene_transition_location_locked",
				"location_id": location_id,
				"required_unlocked_locations": _string_array(option.get("required_unlocked_locations", [])),
			}
	for location_id in _string_array(option.get("blocked_unlocked_locations", [])):
		if unlocked_lookup.has(location_id):
			return {
				"success": false,
				"reason": "scene_transition_location_blocked",
				"location_id": location_id,
				"blocked_unlocked_locations": _string_array(option.get("blocked_unlocked_locations", [])),
			}
	return {"success": true}


func _target_entry_id(option: Dictionary) -> String:
	for key in ["return_spawn_id", "target_entry_point_id", "entry_point_id"]:
		var value := str(option.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return "default_entry"


func _entry_grid_for_map(map_id: String, entry_id: String) -> Dictionary:
	var map_result: Dictionary = _map_scene_loader.load_map_definition(map_id)
	if not bool(map_result.get("ok", false)):
		return {"ok": false, "reason": "scene_transition_map_missing"}
	var map_data: Dictionary = _dictionary_or_empty(map_result.get("data", {}))
	for entry in _array_or_empty(map_data.get("entry_points", [])):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if str(entry_data.get("id", "")) == entry_id:
			return {
				"ok": true,
				"map_data": map_data,
				"grid": _dictionary_or_empty(entry_data.get("grid", {})),
				"facing": str(entry_data.get("facing", "")).strip_edges(),
			}
	return {"ok": false, "reason": "scene_transition_entry_missing"}


func _configure_map_interactions(simulation: RefCounted, map_data: Dictionary) -> void:
	if map_data.is_empty():
		return
	var topology: RefCounted = _map_builder.build_from_definition(map_data)
	simulation.configure_map_interactions(topology.interaction_targets)


func _interaction_success_payload(actor_id: int, prompt: Dictionary, option: Dictionary, target_id: Variant) -> Dictionary:
	var target: Dictionary = _dictionary_or_empty(prompt.get("target", {}))
	var target_name: String = str(prompt.get("target_name", target.get("display_name", ""))).strip_edges()
	if target_name.is_empty():
		target_name = str(target_id).strip_edges()
	return {
		"actor_id": actor_id,
		"target_id": target_id,
		"target_type": str(target.get("target_type", "")),
		"target_name": target_name,
		"option_id": str(option.get("id", "")),
		"option_kind": str(option.get("kind", "")),
		"option_name": str(option.get("display_name", "")),
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(value) == TYPE_STRING:
		var normalized_value := str(value).strip_edges()
		if not normalized_value.is_empty():
			output.append(normalized_value)
		return output
	for entry in _array_or_empty(value):
		var normalized_entry := str(entry).strip_edges()
		if not normalized_entry.is_empty():
			output.append(normalized_entry)
	return output


func _string_lookup(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	for entry in _string_array(value):
		output[entry] = true
	return output
