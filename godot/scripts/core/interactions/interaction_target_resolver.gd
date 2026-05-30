extends RefCounted


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
				"return_spawn_id": target_data.get("return_spawn_id", ""),
				"target_entry_point_id": target_data.get("target_entry_point_id", ""),
				"entry_point_id": target_data.get("entry_point_id", ""),
			}
		"container":
			return {
				"id": "open_container",
				"kind": "open_container",
				"display_name": target_data.get("display_name", "打开容器"),
				"target_id": target_data.get("target_id", ""),
			}
	return {}


func _failed_prompt(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}
