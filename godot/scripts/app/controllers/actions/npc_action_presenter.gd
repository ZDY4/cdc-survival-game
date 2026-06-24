extends RefCounted


static func present(host: Node, actor_view: RefCounted, npc_result: Dictionary, options: Dictionary = {}) -> Dictionary:
	if actor_view == null:
		return {"success": false, "active": false, "reason": "actor_view_missing"}
	var attack: Dictionary = attack_from_result(npc_result)
	if not attack.is_empty():
		return _present_attack(host, actor_view, npc_result, attack, options)
	return _present_move(host, actor_view, npc_result, options)


static func attack_from_result(npc_result: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(npc_result.get("result", {}))
	var direct_attack: Dictionary = _normalized_attack_result(result, int(npc_result.get("actor_id", 0)))
	if not direct_attack.is_empty():
		return direct_attack
	var actions: Array = _array_or_empty(result.get("actions", []))
	for index in range(actions.size() - 1, -1, -1):
		var action_result: Dictionary = _normalized_attack_result(_dictionary_or_empty(actions[index]), int(npc_result.get("actor_id", 0)))
		if not action_result.is_empty():
			return action_result
	for event in _array_or_empty(npc_result.get("events", [])):
		var event_data: Dictionary = _dictionary_or_empty(event)
		if str(event_data.get("kind", "")) != "attack_resolved":
			continue
		var payload: Dictionary = _dictionary_or_empty(event_data.get("payload", event_data))
		var event_attack: Dictionary = _normalized_attack_result(payload, int(npc_result.get("actor_id", 0)))
		if not event_attack.is_empty():
			return event_attack
	return {}


static func move_step_from_result(npc_result: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(npc_result.get("result", {}))
	var actor_id := int(result.get("actor_id", npc_result.get("actor_id", 0)))
	var from_grid: Dictionary = _dictionary_or_empty(result.get("from", {})).duplicate(true)
	var to_grid: Dictionary = _dictionary_or_empty(result.get("to", {})).duplicate(true)
	if not from_grid.is_empty() and not to_grid.is_empty():
		return {"actor_id": actor_id, "from": from_grid, "to": to_grid}
	for event in _array_or_empty(npc_result.get("events", [])):
		var event_data: Dictionary = _dictionary_or_empty(event)
		if str(event_data.get("kind", "")) != "movement_step":
			continue
		var payload: Dictionary = _dictionary_or_empty(event_data.get("payload", event_data))
		var event_actor_id := int(payload.get("actor_id", actor_id))
		if actor_id > 0 and event_actor_id != actor_id:
			continue
		from_grid = _dictionary_or_empty(payload.get("from", {})).duplicate(true)
		to_grid = _dictionary_or_empty(payload.get("to", {})).duplicate(true)
		if not from_grid.is_empty() and not to_grid.is_empty():
			return {"actor_id": event_actor_id, "from": from_grid, "to": to_grid}
	return {}


static func _present_attack(host: Node, actor_view: RefCounted, npc_result: Dictionary, attack: Dictionary, options: Dictionary = {}) -> Dictionary:
	if not actor_view.has_method("play_attack"):
		return {"success": false, "active": false, "reason": "actor_view_attack_missing"}
	var attacker_id := int(attack.get("actor_id", npc_result.get("actor_id", 0)))
	var target_actor_id := int(attack.get("target_actor_id", 0))
	if attacker_id <= 0 or target_actor_id <= 0:
		return {"success": false, "active": false, "reason": "npc_attack_actor_missing", "actor_id": attacker_id, "target_actor_id": target_actor_id}
	var presentation: Dictionary = _dictionary_or_empty(actor_view.call("play_attack", host, attacker_id, target_actor_id, attack, {
		"duration_sec": 0.10,
		"source": "npc_action",
		"presentation_token": int(options.get("presentation_token", 0)),
	}))
	presentation["source"] = "npc_action"
	presentation["npc_intent"] = "attack"
	return presentation


static func _present_move(host: Node, actor_view: RefCounted, npc_result: Dictionary, options: Dictionary = {}) -> Dictionary:
	if not actor_view.has_method("move_actor_step"):
		return {"success": false, "active": false, "reason": "actor_view_move_missing"}
	var step: Dictionary = move_step_from_result(npc_result)
	if step.is_empty():
		return {"success": false, "active": false, "reason": "npc_move_step_missing"}
	var actor_id := int(step.get("actor_id", 0))
	if actor_id <= 0:
		return {"success": false, "active": false, "reason": "npc_actor_id_missing"}
	var from_grid: Dictionary = _dictionary_or_empty(step.get("from", {}))
	var to_grid: Dictionary = _dictionary_or_empty(step.get("to", {}))
	if from_grid.is_empty() or to_grid.is_empty():
		return {"success": false, "active": false, "reason": "npc_move_grid_missing", "actor_id": actor_id}
	var presentation: Dictionary = _dictionary_or_empty(actor_view.call("move_actor_step", host, actor_id, from_grid, to_grid, {
		"duration_sec": 0.08,
		"source": "npc_action",
		"presentation_token": int(options.get("presentation_token", 0)),
	}))
	presentation["source"] = "npc_action"
	return presentation


static func _normalized_attack_result(result: Dictionary, fallback_actor_id: int) -> Dictionary:
	if result.is_empty():
		return {}
	var fallback_intent := "attack" if (result.has("target_actor_id") and (result.has("damage") or bool(result.get("attack_prepared", false)))) else ""
	if str(result.get("intent", fallback_intent)) != "attack":
		return {}
	var actor_id := int(result.get("actor_id", fallback_actor_id))
	var target_actor_id := int(result.get("target_actor_id", 0))
	if actor_id <= 0 or target_actor_id <= 0:
		return {}
	var output := result.duplicate(true)
	output["actor_id"] = actor_id
	output["target_actor_id"] = target_actor_id
	return output


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
