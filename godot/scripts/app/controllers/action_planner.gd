extends RefCounted


func move_intent(actor_id: int, target_grid: Dictionary, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	return {
		"kind": "move_to_grid",
		"actor_id": actor_id,
		"target_grid": target_grid.duplicate(true),
		"topology": topology.duplicate(true),
		"options": options.duplicate(true),
	}


func interact_intent(actor_id: int, target: Dictionary, option_id: String, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	return {
		"kind": "interact_target",
		"actor_id": actor_id,
		"target": target.duplicate(true),
		"target_grid": _interaction_target_grid(target),
		"option_id": option_id,
		"topology": topology.duplicate(true),
		"options": options.duplicate(true),
	}


func attack_intent(actor_id: int, target_actor_id: int, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	return {
		"kind": "attack_actor",
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"topology": topology.duplicate(true),
		"options": options.duplicate(true),
	}


func plan_move_to_grid(intent: Dictionary, begin_result: Dictionary) -> Array[Dictionary]:
	var path: Array = _array_or_empty(begin_result.get("path", [])).duplicate(true)
	var output: Array[Dictionary] = []
	if path.size() <= 1:
		return output
	for index in range(1, path.size()):
		var from_grid: Dictionary = _dictionary_or_empty(path[index - 1]).duplicate(true)
		var to_grid: Dictionary = _dictionary_or_empty(path[index]).duplicate(true)
		if from_grid.is_empty() or to_grid.is_empty():
			continue
		output.append({
			"kind": "move_step",
			"actor_id": int(intent.get("actor_id", 0)),
			"from": from_grid,
			"to": to_grid,
			"target": {},
			"option_id": "",
			"state": "planned",
			"rule_result": {},
			"presentation_token": 0,
			"created_by_intent": str(intent.get("kind", "move_to_grid")),
			"channel": "foreground_actor",
		})
	return output


func plan_interact_target(intent: Dictionary, begin_result: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = plan_move_to_grid(intent, begin_result)
	output.append({
		"kind": "interact",
		"actor_id": int(intent.get("actor_id", 0)),
		"from": {},
		"to": {},
		"target": _dictionary_or_empty(intent.get("target", {})).duplicate(true),
		"option_id": str(intent.get("option_id", "")),
		"state": "planned",
		"rule_result": {},
		"presentation_token": 0,
		"created_by_intent": str(intent.get("kind", "interact_target")),
		"channel": "foreground_actor",
	})
	return output


func plan_attack_actor(intent: Dictionary, begin_result: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = plan_move_to_grid(intent, begin_result)
	output.append({
		"kind": "attack",
		"actor_id": int(intent.get("actor_id", 0)),
		"target_actor_id": int(intent.get("target_actor_id", 0)),
		"from": {},
		"to": {},
		"target": {},
		"option_id": "",
		"state": "planned",
		"rule_result": {},
		"presentation_token": 0,
		"created_by_intent": str(intent.get("kind", "attack_actor")),
		"channel": "foreground_actor",
	})
	return output


func _interaction_target_grid(target: Dictionary) -> Dictionary:
	for key in ["grid_position", "anchor", "grid"]:
		var grid: Dictionary = _dictionary_or_empty(target.get(key, {}))
		if not grid.is_empty():
			return grid.duplicate(true)
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
