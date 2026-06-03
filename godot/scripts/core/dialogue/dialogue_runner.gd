extends RefCounted

const DialogueActionRunner = preload("res://scripts/core/dialogue/dialogue_action_runner.gd")
const DialogueDefinitionIndex = preload("res://scripts/core/dialogue/dialogue_definition_index.gd")

var _action_runner := DialogueActionRunner.new()
var _dialogue_index := DialogueDefinitionIndex.new()


func advance(simulation: RefCounted, actor_id: int, option_ref: Variant, dialogue_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var dialogue_id: String = str(actor.active_dialogue_id)
	if dialogue_id.is_empty():
		return {"success": false, "reason": "dialogue_session_missing"}
	var dialogue: Dictionary = _dialogue_index.dialogue_data(dialogue_id, dialogue_library)
	if dialogue.is_empty():
		return {"success": false, "reason": "unknown_dialogue", "dialogue_id": dialogue_id}
	var nodes: Dictionary = _dialogue_index.nodes_by_id(_array_or_empty(dialogue.get("nodes", [])))
	var current_node_id: String = _active_node_id(actor, dialogue)
	var current_node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
	if current_node.is_empty():
		return {"success": false, "reason": "dialogue_node_missing", "node_id": current_node_id}
	if str(current_node.get("type", "")) != "choice":
		return {"success": false, "reason": "dialogue_choice_unavailable", "node_id": current_node_id}

	var option: Dictionary = _dialogue_index.resolve_option(current_node, option_ref)
	if option.is_empty():
		return {"success": false, "reason": "dialogue_option_unavailable", "node_id": current_node_id}

	var emitted_actions: Array[Dictionary] = []
	var outcome: Dictionary = _advance_to_node(simulation, actor_id, actor, dialogue_id, str(option.get("next", "")), nodes, emitted_actions)
	outcome["selected_option"] = option
	outcome["emitted_actions"] = emitted_actions
	return outcome


func advance_without_choice(simulation: RefCounted, actor_id: int, dialogue_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var dialogue_id: String = str(actor.active_dialogue_id)
	if dialogue_id.is_empty():
		return {"success": false, "reason": "dialogue_session_missing"}
	var dialogue: Dictionary = _dialogue_index.dialogue_data(dialogue_id, dialogue_library)
	if dialogue.is_empty():
		return {"success": false, "reason": "unknown_dialogue", "dialogue_id": dialogue_id}
	var nodes: Dictionary = _dialogue_index.nodes_by_id(_array_or_empty(dialogue.get("nodes", [])))
	var current_node_id: String = _active_node_id(actor, dialogue)
	var current_node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
	if current_node.is_empty():
		return {"success": false, "reason": "dialogue_node_missing", "node_id": current_node_id}
	var node_type: String = str(current_node.get("type", ""))
	if node_type == "choice":
		return {"success": false, "reason": "dialogue_choice_required", "node_id": current_node_id}
	if node_type != "dialog":
		return {"success": false, "reason": "dialogue_advance_unavailable", "node_id": current_node_id, "node_type": node_type}
	var next_node_id: String = str(current_node.get("next", ""))
	if next_node_id.is_empty():
		actor.active_dialogue_id = ""
		actor.active_dialogue_node_id = ""
		simulation.emit_event("dialogue_finished", {
			"actor_id": actor_id,
			"dialogue_id": dialogue_id,
			"node_id": current_node_id,
			"end_type": "leave",
		})
		return {
			"success": true,
			"dialogue_id": dialogue_id,
			"node_id": current_node_id,
			"finished": true,
			"end_type": "leave",
		}
	var emitted_actions: Array[Dictionary] = []
	var outcome: Dictionary = _advance_to_node(simulation, actor_id, actor, dialogue_id, next_node_id, nodes, emitted_actions)
	outcome["emitted_actions"] = emitted_actions
	outcome["advanced_without_choice"] = true
	return outcome


func _active_node_id(actor: RefCounted, dialogue: Dictionary) -> String:
	var current_node_id: String = str(actor.active_dialogue_node_id)
	if not current_node_id.is_empty():
		return current_node_id
	var start_node: Dictionary = _dialogue_index.start_node(_array_or_empty(dialogue.get("nodes", [])))
	var next_node_id: String = str(start_node.get("next", ""))
	if next_node_id.is_empty():
		return str(start_node.get("id", ""))
	actor.active_dialogue_node_id = next_node_id
	return next_node_id


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
					var action_result: Dictionary = _action_runner.apply_action(simulation, actor_id, action_data)
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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
