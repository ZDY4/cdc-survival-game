extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const MapBuilder = preload("res://scripts/world/map_builder.gd")
const MapSceneLoader = preload("res://scripts/world/map_scene_loader.gd")

var _inventory_entries := InventoryEntries.new()
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

	var item_id: String = str(option.get("item_id", ""))
	var count: int = max(1, int(option.get("count", 1)))
	if item_id.is_empty():
		return {"success": false, "reason": "pickup_item_invalid", "prompt": prompt}

	_inventory_entries.add_actor_item(actor, item_id, count)
	simulation.record_item_collected(actor_id, item_id, count)
	var target_id: String = str(option.get("target_id", ""))
	simulation.consumed_interaction_targets[target_id] = true
	simulation.emit_event("pickup_granted", {
		"actor_id": actor_id,
		"target_id": target_id,
		"item_id": item_id,
		"count": count,
	})
	simulation.emit_event("interaction_succeeded", _interaction_success_payload(actor_id, prompt, option, target_id))
	return {
		"success": true,
		"prompt": prompt,
		"consumed_target": true,
		"item_id": item_id,
		"count": count,
	}


func _execute_talk(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt}

	var dialogue_id: String = str(option.get("dialogue_id", ""))
	actor.active_dialogue_id = dialogue_id
	actor.active_dialogue_node_id = ""
	simulation.emit_event("dialogue_started", {
		"actor_id": actor_id,
		"dialogue_id": dialogue_id,
	})
	var target: Dictionary = _dictionary_or_empty(prompt.get("target", {}))
	simulation.emit_event("interaction_succeeded", _interaction_success_payload(actor_id, prompt, option, target.get("actor_id", 0)))
	return {
		"success": true,
		"prompt": prompt,
		"dialogue_id": dialogue_id,
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


func _container_session_for_target(simulation: RefCounted, target_id: String, target: Dictionary) -> Dictionary:
	if simulation.container_sessions.has(target_id):
		return _dictionary_or_empty(simulation.container_sessions[target_id])
	var session := {
		"container_id": target_id,
		"display_name": str(target.get("display_name", target_id)),
		"inventory": _array_or_empty(target.get("container_inventory", [])).duplicate(true),
	}
	simulation.container_sessions[target_id] = session
	return session


func _execute_scene_transition(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var target_map_id: String = str(option.get("target_map_id", ""))
	if target_map_id.is_empty():
		return {"success": false, "reason": "scene_transition_target_missing", "prompt": prompt}

	var previous_map_id: String = simulation.active_map_id
	var target_entry_id := _target_entry_id(option)
	var entry_result := _entry_grid_for_map(target_map_id, target_entry_id)
	if not bool(entry_result.get("ok", false)):
		return {"success": false, "reason": entry_result.get("reason", "scene_transition_entry_missing"), "prompt": prompt}

	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt}

	simulation.active_map_id = target_map_id
	simulation.active_entry_point_id = target_entry_id
	_configure_map_interactions(simulation, _dictionary_or_empty(entry_result.get("map_data", {})))
	actor.map_id = target_map_id
	actor.grid_position = GridCoord.from_dictionary(_dictionary_or_empty(entry_result.get("grid", {})))
	simulation.emit_event("scene_transition", {
		"actor_id": actor_id,
		"from_map_id": previous_map_id,
		"to_map_id": target_map_id,
		"entry_point_id": target_entry_id,
		"kind": option.get("kind", ""),
	})
	simulation.emit_event("interaction_succeeded", _interaction_success_payload(actor_id, prompt, option, option.get("target_id", "")))
	return {
		"success": true,
		"prompt": prompt,
		"context_snapshot": {
			"active_map_id": simulation.active_map_id,
			"active_entry_point_id": simulation.active_entry_point_id,
		},
	}


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
