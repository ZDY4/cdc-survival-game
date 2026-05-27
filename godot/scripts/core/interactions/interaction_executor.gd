extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

var _inventory_entries := InventoryEntries.new()


func query(simulation: RefCounted, actor_id: int, target: Dictionary) -> Dictionary:
	if simulation.actor_registry.get_actor(actor_id) == null:
		return _failed_prompt("unknown_actor")

	var target_data: Dictionary = _resolve_target(simulation, target)
	if target_data.is_empty():
		return _failed_prompt("interaction_target_unavailable")

	var option: Dictionary = _option_for_target(target_data)
	if option.is_empty():
		return _failed_prompt("interaction_option_unavailable")

	return {
		"ok": true,
		"actor_id": actor_id,
		"target": target_data,
		"target_name": target_data.get("display_name", ""),
		"options": [option],
		"primary_option_id": option.get("id", ""),
	}


func execute(simulation: RefCounted, actor_id: int, target: Dictionary, option_id: String = "") -> Dictionary:
	var prompt: Dictionary = query(simulation, actor_id, target)
	if not bool(prompt.get("ok", false)):
		return {
			"success": false,
			"reason": prompt.get("reason", "interaction_unavailable"),
			"prompt": prompt,
		}

	var options: Array = prompt.get("options", [])
	var option: Dictionary = options[0]
	if not option_id.is_empty() and option.get("id", "") != option_id:
		return {
			"success": false,
			"reason": "interaction_option_unavailable",
			"prompt": prompt,
		}

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


func _resolve_target(simulation: RefCounted, target: Dictionary) -> Dictionary:
	var target_type: String = str(target.get("target_type", "map_object"))
	match target_type:
		"actor":
			var actor_id: int = int(target.get("actor_id", 0))
			var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
			if actor == null or actor.side == "hostile":
				return {}
			return {
				"target_type": "actor",
				"actor_id": actor.actor_id,
				"definition_id": actor.definition_id,
				"display_name": actor.display_name,
				"kind": "talk",
			}
		_:
			var target_id: String = str(target.get("target_id", ""))
			if target_id.is_empty() or simulation.consumed_interaction_targets.has(target_id):
				return {}
			return simulation.map_interaction_targets.get(target_id, {})


func _option_for_target(target_data: Dictionary) -> Dictionary:
	var kind: String = str(target_data.get("kind", ""))
	match kind:
		"pickup":
			return {
				"id": "pickup",
				"kind": "pickup",
				"display_name": "拾取",
				"item_id": target_data.get("item_id", ""),
				"count": max(1, int(target_data.get("max_count", target_data.get("min_count", 1)))),
				"target_id": target_data.get("target_id", ""),
			}
		"talk":
			return {
				"id": "talk",
				"kind": "talk",
				"display_name": "对话",
				"dialogue_id": target_data.get("definition_id", target_data.get("target_id", "")),
			}
		"enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor":
			return {
				"id": kind,
				"kind": kind,
				"display_name": target_data.get("display_name", "进入"),
				"target_map_id": target_data.get("target_map_id", ""),
				"target_id": target_data.get("target_id", ""),
			}
		"container":
			return {
				"id": "open_container",
				"kind": "open_container",
				"display_name": target_data.get("display_name", "打开容器"),
				"target_id": target_data.get("target_id", ""),
			}
	return {}


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


func _failed_prompt(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
