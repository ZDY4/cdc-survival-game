extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

var _inventory_entries := InventoryEntries.new()


func execute(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	match str(option.get("kind", "")):
		"pickup":
			return _execute_pickup(simulation, actor_id, prompt, option)
		"talk":
			return _execute_talk(simulation, actor_id, prompt, option)
		"open_container":
			return _execute_open_container(simulation, actor_id, prompt, option)
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
	simulation.emit_event("interaction_succeeded", {
		"actor_id": actor_id,
		"target_id": target_id,
		"option_id": "pickup",
	})
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
	simulation.emit_event("interaction_succeeded", {
		"actor_id": actor_id,
		"target_id": prompt.get("target", {}).get("actor_id", 0),
		"option_id": "talk",
	})
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
	simulation.emit_event("interaction_succeeded", {
		"actor_id": actor_id,
		"target_id": target_id,
		"option_id": "open_container",
	})
	return {
		"success": true,
		"prompt": prompt,
		"container": session.duplicate(true),
	}


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
	simulation.active_map_id = target_map_id
	simulation.emit_event("scene_transition", {
		"actor_id": actor_id,
		"from_map_id": previous_map_id,
		"to_map_id": target_map_id,
		"kind": option.get("kind", ""),
	})
	simulation.emit_event("interaction_succeeded", {
		"actor_id": actor_id,
		"target_id": option.get("target_id", ""),
		"option_id": option.get("id", ""),
	})
	return {
		"success": true,
		"prompt": prompt,
		"context_snapshot": {
			"active_map_id": simulation.active_map_id,
		},
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
