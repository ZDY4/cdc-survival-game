extends RefCounted

const ActorRegistry = preload("res://scripts/core/actor/actor_registry.gd")
const SimulationEvent = preload("res://scripts/core/simulation/simulation_event.gd")

var actor_registry := ActorRegistry.new()
var active_map_id: String = ""
var start_location_id: String = ""
var start_entry_point_id: String = ""
var unlocked_locations: Array[String] = []
var events: Array[SimulationEvent] = []
var map_interaction_targets: Dictionary = {}
var consumed_interaction_targets: Dictionary = {}


func register_actor(request: Dictionary) -> int:
	var record := actor_registry.register_actor(request)
	_emit("actor_registered", {
		"actor_id": record.actor_id,
		"definition_id": record.definition_id,
		"group_id": record.group_id,
		"side": record.side,
		"grid_position": record.grid_position.to_dictionary(),
	})
	return record.actor_id


func configure_map_interactions(targets: Dictionary) -> void:
	map_interaction_targets = targets.duplicate(true)
	consumed_interaction_targets.clear()


func query_interaction_options(actor_id: int, target: Dictionary) -> Dictionary:
	if actor_registry.get_actor(actor_id) == null:
		return _failed_prompt("unknown_actor")

	var target_data: Dictionary = _resolve_interaction_target(target)
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


func execute_interaction(actor_id: int, target: Dictionary, option_id: String = "") -> Dictionary:
	var prompt: Dictionary = query_interaction_options(actor_id, target)
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
			return _execute_pickup(actor_id, prompt, option)
		"talk":
			return _execute_talk(actor_id, prompt, option)
		"enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor":
			return _execute_scene_transition(actor_id, prompt, option)
		_:
			return {
				"success": false,
				"reason": "unsupported_interaction_kind",
				"prompt": prompt,
			}


func snapshot() -> Dictionary:
	var event_output: Array[Dictionary] = []
	for event in events:
		event_output.append(event.to_dictionary())
	return {
		"schema_version": 1,
		"active_map_id": active_map_id,
		"start_location_id": start_location_id,
		"start_entry_point_id": start_entry_point_id,
		"unlocked_locations": unlocked_locations.duplicate(),
		"actors": actor_registry.snapshot(),
		"events": event_output,
		"consumed_interaction_targets": consumed_interaction_targets.keys(),
	}


func _emit(kind: String, payload: Dictionary) -> void:
	events.append(SimulationEvent.new(kind, payload))


func _resolve_interaction_target(target: Dictionary) -> Dictionary:
	var target_type: String = str(target.get("target_type", "map_object"))
	match target_type:
		"actor":
			var actor_id: int = int(target.get("actor_id", 0))
			var actor: RefCounted = actor_registry.get_actor(actor_id)
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
			if target_id.is_empty() or consumed_interaction_targets.has(target_id):
				return {}
			return map_interaction_targets.get(target_id, {})


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


func _execute_pickup(actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt}

	var item_id: String = str(option.get("item_id", ""))
	var count: int = max(1, int(option.get("count", 1)))
	if item_id.is_empty():
		return {"success": false, "reason": "pickup_item_invalid", "prompt": prompt}

	actor.inventory[item_id] = int(actor.inventory.get(item_id, 0)) + count
	var target_id: String = str(option.get("target_id", ""))
	consumed_interaction_targets[target_id] = true
	_emit("pickup_granted", {
		"actor_id": actor_id,
		"target_id": target_id,
		"item_id": item_id,
		"count": count,
	})
	_emit("interaction_succeeded", {
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


func _execute_talk(actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt}

	var dialogue_id: String = str(option.get("dialogue_id", ""))
	actor.active_dialogue_id = dialogue_id
	_emit("dialogue_started", {
		"actor_id": actor_id,
		"dialogue_id": dialogue_id,
	})
	_emit("interaction_succeeded", {
		"actor_id": actor_id,
		"target_id": prompt.get("target", {}).get("actor_id", 0),
		"option_id": "talk",
	})
	return {
		"success": true,
		"prompt": prompt,
		"dialogue_id": dialogue_id,
	}


func _execute_scene_transition(actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var target_map_id: String = str(option.get("target_map_id", ""))
	if target_map_id.is_empty():
		return {"success": false, "reason": "scene_transition_target_missing", "prompt": prompt}

	var previous_map_id: String = active_map_id
	active_map_id = target_map_id
	_emit("scene_transition", {
		"actor_id": actor_id,
		"from_map_id": previous_map_id,
		"to_map_id": target_map_id,
		"kind": option.get("kind", ""),
	})
	_emit("interaction_succeeded", {
		"actor_id": actor_id,
		"target_id": option.get("target_id", ""),
		"option_id": option.get("id", ""),
	})
	return {
		"success": true,
		"prompt": prompt,
		"context_snapshot": {
			"active_map_id": active_map_id,
		},
	}


func _failed_prompt(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}
