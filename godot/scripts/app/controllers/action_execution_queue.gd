extends RefCounted


var _queue_id_seq := 0
var _action_id_seq := 0
var _intent_id_seq := 0


func create_queue(intent: Dictionary, planned_actions: Array) -> Dictionary:
	_queue_id_seq += 1
	_intent_id_seq += 1
	var queue_id := _queue_id_seq
	var intent_id := _intent_id_seq
	var actions: Array[Dictionary] = []
	for action_value in planned_actions:
		var planned: Dictionary = _dictionary_or_empty(action_value).duplicate(true)
		if planned.is_empty():
			continue
		_action_id_seq += 1
		planned["queue_id"] = queue_id
		planned["action_id"] = _action_id_seq
		planned["intent_id"] = intent_id
		planned["state"] = str(planned.get("state", "planned"))
		planned["presentation_token"] = int(planned.get("presentation_token", 0))
		actions.append(planned)
	var queue := {
		"active": not actions.is_empty(),
		"queue_id": queue_id,
		"intent_id": intent_id,
		"actor_id": int(intent.get("actor_id", 0)),
		"state": "planned" if not actions.is_empty() else "empty",
		"intent": intent.duplicate(true),
		"actions": actions,
		"current_index": 0,
		"cancel_requested": false,
		"cancel_reason": "",
		"replacement_intent": {},
		"blocked_reason": "",
		"presentation": {
			"waiting_token": 0,
			"wait_frames": 0,
			"timeout_frames": 180,
			"last_completion": {},
		},
	}
	return queue


func empty_snapshot() -> Dictionary:
	return {
		"active": false,
		"queue_id": 0,
		"intent_id": 0,
		"actor_id": 0,
		"state": "idle",
		"current_action": {},
		"remaining_actions": [],
		"remaining_move_path": [],
		"cancel_requested": false,
		"blocked_reason": "",
		"presentation": {
			"waiting_token": 0,
			"wait_frames": 0,
			"timeout_frames": 180,
			"last_completion": {},
		},
	}


func snapshot(queue: Dictionary) -> Dictionary:
	if queue.is_empty():
		return empty_snapshot()
	var current: Dictionary = current_action(queue)
	var remaining: Array[Dictionary] = []
	var actions: Array = _array_or_empty(queue.get("actions", []))
	var current_index := int(queue.get("current_index", 0))
	for index in range(current_index, actions.size()):
		var entry: Dictionary = _dictionary_or_empty(actions[index])
		if entry.is_empty():
			continue
		remaining.append(entry.duplicate(true))
	return {
		"active": bool(queue.get("active", false)),
		"queue_id": int(queue.get("queue_id", 0)),
		"intent_id": int(queue.get("intent_id", 0)),
		"actor_id": int(queue.get("actor_id", 0)),
		"state": str(queue.get("state", "idle")),
		"intent": _dictionary_or_empty(queue.get("intent", {})).duplicate(true),
		"current_action": current.duplicate(true),
		"remaining_actions": remaining,
		"remaining_move_path": remaining_move_path(queue),
		"cancel_requested": bool(queue.get("cancel_requested", false)),
		"cancel_reason": str(queue.get("cancel_reason", "")),
		"replacement_intent": _dictionary_or_empty(queue.get("replacement_intent", {})).duplicate(true),
		"blocked_reason": str(queue.get("blocked_reason", "")),
		"presentation": _dictionary_or_empty(queue.get("presentation", {})).duplicate(true),
	}


func current_action(queue: Dictionary) -> Dictionary:
	var actions: Array = _array_or_empty(queue.get("actions", []))
	var current_index := int(queue.get("current_index", 0))
	if current_index < 0 or current_index >= actions.size():
		return {}
	return _dictionary_or_empty(actions[current_index])


func begin_current_action(queue: Dictionary, rule_result: Dictionary, presentation_token: int, timeout_frames: int = 180) -> Dictionary:
	var actions: Array = _array_or_empty(queue.get("actions", []))
	var current_index := int(queue.get("current_index", 0))
	if current_index < 0 or current_index >= actions.size():
		queue["active"] = false
		queue["state"] = "completed"
		return {}
	var action: Dictionary = _dictionary_or_empty(actions[current_index]).duplicate(true)
	action["state"] = "presenting"
	action["rule_result"] = rule_result.duplicate(true)
	action["presentation_token"] = presentation_token
	if rule_result.has("from"):
		action["from"] = _dictionary_or_empty(rule_result.get("from", action.get("from", {}))).duplicate(true)
	if rule_result.has("to"):
		action["to"] = _dictionary_or_empty(rule_result.get("to", action.get("to", {}))).duplicate(true)
	actions[current_index] = action
	queue["actions"] = actions
	queue["active"] = true
	queue["state"] = "waiting_for_presentation"
	queue["presentation"] = {
		"waiting_token": presentation_token,
		"wait_frames": 0,
		"timeout_frames": timeout_frames,
		"last_completion": {},
	}
	return action


func complete_current_action(queue: Dictionary, completion: Dictionary = {}) -> Dictionary:
	var actions: Array = _array_or_empty(queue.get("actions", []))
	var current_index := int(queue.get("current_index", 0))
	if current_index < 0 or current_index >= actions.size():
		queue["active"] = false
		queue["state"] = "completed"
		return {}
	var action: Dictionary = _dictionary_or_empty(actions[current_index]).duplicate(true)
	action["state"] = "completed"
	if not completion.is_empty():
		action["completion"] = completion.duplicate(true)
	actions[current_index] = action
	current_index += 1
	queue["actions"] = actions
	queue["current_index"] = current_index
	queue["active"] = current_index < actions.size()
	queue["state"] = "planned" if bool(queue.get("active", false)) else "completed"
	queue["presentation"] = {
		"waiting_token": 0,
		"wait_frames": 0,
		"timeout_frames": int(_dictionary_or_empty(queue.get("presentation", {})).get("timeout_frames", 180)),
		"last_completion": completion.duplicate(true),
	}
	return action


func complete_current_without_presentation(queue: Dictionary, rule_result: Dictionary = {}) -> Dictionary:
	var actions: Array = _array_or_empty(queue.get("actions", []))
	var current_index := int(queue.get("current_index", 0))
	if current_index < 0 or current_index >= actions.size():
		queue["active"] = false
		queue["state"] = "completed"
		return {}
	var action: Dictionary = _dictionary_or_empty(actions[current_index]).duplicate(true)
	action["state"] = "completed"
	action["rule_result"] = rule_result.duplicate(true)
	actions[current_index] = action
	current_index += 1
	queue["actions"] = actions
	queue["current_index"] = current_index
	queue["active"] = current_index < actions.size()
	queue["state"] = "planned" if bool(queue.get("active", false)) else "completed"
	return action


func mark_current_stale(queue: Dictionary, reason: String) -> Dictionary:
	var actions: Array = _array_or_empty(queue.get("actions", []))
	var current_index := int(queue.get("current_index", 0))
	if current_index >= 0 and current_index < actions.size():
		var action: Dictionary = _dictionary_or_empty(actions[current_index]).duplicate(true)
		action["state"] = "cancelled"
		action["cancel_reason"] = reason
		actions[current_index] = action
		queue["actions"] = actions
	queue["active"] = false
	queue["state"] = "cancelled"
	queue["blocked_reason"] = reason
	return current_action(queue)


func request_replacement(queue: Dictionary, replacement_intent: Dictionary, reason: String = "replacement_intent") -> void:
	if queue.is_empty():
		return
	queue["cancel_requested"] = true
	queue["cancel_reason"] = reason
	queue["replacement_intent"] = replacement_intent.duplicate(true)


func remaining_move_path(queue: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var actions: Array = _array_or_empty(queue.get("actions", []))
	var current_index := int(queue.get("current_index", 0))
	for index in range(current_index, actions.size()):
		var action: Dictionary = _dictionary_or_empty(actions[index])
		if str(action.get("kind", "")) != "move_step":
			continue
		var to_grid: Dictionary = _dictionary_or_empty(action.get("to", {}))
		if to_grid.is_empty():
			continue
		output.append(to_grid.duplicate(true))
	return output


func wait_frame(queue: Dictionary) -> int:
	var presentation: Dictionary = _dictionary_or_empty(queue.get("presentation", {})).duplicate(true)
	presentation["wait_frames"] = int(presentation.get("wait_frames", 0)) + 1
	queue["presentation"] = presentation
	return int(presentation.get("wait_frames", 0))


func clear(queue: Dictionary) -> void:
	queue.clear()


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
