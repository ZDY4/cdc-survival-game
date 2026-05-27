extends RefCounted


func advance(simulation: RefCounted, actor_id: int, option_ref: Variant, dialogue_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var dialogue_id: String = str(actor.active_dialogue_id)
	if dialogue_id.is_empty():
		return {"success": false, "reason": "dialogue_session_missing"}
	var dialogue: Dictionary = _dialogue_data(dialogue_id, dialogue_library)
	if dialogue.is_empty():
		return {"success": false, "reason": "unknown_dialogue", "dialogue_id": dialogue_id}
	var nodes: Dictionary = _nodes_by_id(_array_or_empty(dialogue.get("nodes", [])))
	var current_node_id: String = _active_node_id(actor, dialogue)
	var current_node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
	if current_node.is_empty():
		return {"success": false, "reason": "dialogue_node_missing", "node_id": current_node_id}
	if str(current_node.get("type", "")) != "choice":
		return {"success": false, "reason": "dialogue_choice_unavailable", "node_id": current_node_id}

	var option: Dictionary = _resolve_option(current_node, option_ref)
	if option.is_empty():
		return {"success": false, "reason": "dialogue_option_unavailable", "node_id": current_node_id}

	var emitted_actions: Array[Dictionary] = []
	var outcome: Dictionary = _advance_to_node(simulation, actor_id, actor, dialogue_id, str(option.get("next", "")), nodes, emitted_actions)
	outcome["selected_option"] = option
	outcome["emitted_actions"] = emitted_actions
	return outcome


func _dialogue_data(dialogue_id: String, dialogue_library: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(dialogue_library.get(dialogue_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _nodes_by_id(nodes: Array) -> Dictionary:
	var output: Dictionary = {}
	for node in nodes:
		var node_data: Dictionary = _dictionary_or_empty(node)
		var node_id: String = str(node_data.get("id", ""))
		if not node_id.is_empty():
			output[node_id] = node_data
	return output


func _active_node_id(actor: RefCounted, dialogue: Dictionary) -> String:
	var current_node_id: String = str(actor.active_dialogue_node_id)
	if not current_node_id.is_empty():
		return current_node_id
	var start_node: Dictionary = _start_node(_array_or_empty(dialogue.get("nodes", [])))
	var next_node_id: String = str(start_node.get("next", ""))
	if next_node_id.is_empty():
		return str(start_node.get("id", ""))
	actor.active_dialogue_node_id = next_node_id
	return next_node_id


func _start_node(nodes: Array) -> Dictionary:
	for node in nodes:
		var node_data: Dictionary = _dictionary_or_empty(node)
		if bool(node_data.get("is_start", false)):
			return node_data
	if not nodes.is_empty():
		return _dictionary_or_empty(nodes[0])
	return {}


func _resolve_option(choice_node: Dictionary, option_ref: Variant) -> Dictionary:
	var options: Array = _array_or_empty(choice_node.get("options", []))
	if options.is_empty():
		return {}
	if typeof(option_ref) == TYPE_INT:
		var index: int = int(option_ref)
		if index >= 0 and index < options.size():
			return _dictionary_or_empty(options[index])
		if index > 0 and index <= options.size():
			return _dictionary_or_empty(options[index - 1])
	var option_key: String = str(option_ref).strip_edges()
	if option_key.is_empty():
		return _dictionary_or_empty(options[0])
	if option_key.begins_with("choice_"):
		var choice_index: int = int(option_key.trim_prefix("choice_")) - 1
		if choice_index >= 0 and choice_index < options.size():
			return _dictionary_or_empty(options[choice_index])
	if option_key.is_valid_int():
		var parsed: int = int(option_key)
		if parsed > 0 and parsed <= options.size():
			return _dictionary_or_empty(options[parsed - 1])
		if parsed == 0:
			return _dictionary_or_empty(options[0])
	for option in options:
		var option_data: Dictionary = _dictionary_or_empty(option)
		if str(option_data.get("id", "")) == option_key:
			return option_data
		if str(option_data.get("next", "")) == option_key:
			return option_data
		if str(option_data.get("text", "")) == option_key:
			return option_data
	return {}


func _advance_to_node(simulation: RefCounted, actor_id: int, actor: RefCounted, dialogue_id: String, node_id: String, nodes: Dictionary, emitted_actions: Array[Dictionary]) -> Dictionary:
	var current_node_id: String = node_id
	while not current_node_id.is_empty():
		var node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
		if node.is_empty():
			return {"success": false, "reason": "dialogue_node_missing", "node_id": current_node_id}
		var node_type: String = str(node.get("type", ""))
		match node_type:
			"action":
				for action in _array_or_empty(node.get("actions", [])):
					var action_data: Dictionary = _dictionary_or_empty(action)
					var action_result: Dictionary = _apply_action(simulation, actor_id, action_data)
					emitted_actions.append(action_result)
				current_node_id = str(node.get("next", ""))
			"dialog", "choice":
				actor.active_dialogue_node_id = current_node_id
				simulation.emit_event("dialogue_advanced", {
					"actor_id": actor_id,
					"dialogue_id": dialogue_id,
					"node_id": current_node_id,
				})
				return {
					"success": true,
					"dialogue_id": dialogue_id,
					"node_id": current_node_id,
					"finished": false,
				}
			"end":
				var end_type: String = str(node.get("end_type", "leave"))
				actor.active_dialogue_id = ""
				actor.active_dialogue_node_id = ""
				simulation.emit_event("dialogue_finished", {
					"actor_id": actor_id,
					"dialogue_id": dialogue_id,
					"node_id": current_node_id,
					"end_type": end_type,
				})
				return {
					"success": true,
					"dialogue_id": dialogue_id,
					"node_id": current_node_id,
					"finished": true,
					"end_type": end_type,
				}
			_:
				return {"success": false, "reason": "dialogue_node_unsupported", "node_id": current_node_id, "node_type": node_type}

	var actor_dialogue_id: String = str(actor.active_dialogue_id)
	actor.active_dialogue_id = ""
	actor.active_dialogue_node_id = ""
	return {
		"success": true,
		"dialogue_id": actor_dialogue_id,
		"finished": true,
		"end_type": "leave",
	}


func _apply_action(simulation: RefCounted, actor_id: int, action: Dictionary) -> Dictionary:
	var action_type: String = str(action.get("type", action.get("action_type", "")))
	match action_type:
		"start_quest":
			var quest_id: String = str(action.get("quest_id", action.get("questId", "")))
			var started: bool = simulation.start_quest(actor_id, quest_id)
			return {"type": action_type, "success": started, "quest_id": quest_id}
		"turn_in_quest":
			var quest_id: String = str(action.get("quest_id", action.get("questId", "")))
			var result: Dictionary = simulation.turn_in_quest(actor_id, quest_id)
			result["type"] = action_type
			result["quest_id"] = quest_id
			return result
		"unlock_location":
			var location_id: String = str(action.get("location_id", action.get("locationId", "")))
			var unlocked: bool = simulation.unlock_location(location_id)
			return {"type": action_type, "success": unlocked, "location_id": location_id}
		"open_trade":
			simulation.emit_event("dialogue_trade_requested", {
				"actor_id": actor_id,
			})
			return {"type": action_type, "success": true}
		_:
			simulation.emit_event("dialogue_action_unsupported", {
				"actor_id": actor_id,
				"action_type": action_type,
			})
			return {"type": action_type, "success": false, "reason": "unsupported_dialogue_action"}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
