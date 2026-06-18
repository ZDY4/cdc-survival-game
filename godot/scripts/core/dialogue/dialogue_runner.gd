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
		return _finish_missing_dialogue(simulation, actor_id, actor, dialogue_id)
	var nodes: Dictionary = _dialogue_index.nodes_by_id(_array_or_empty(dialogue.get("nodes", [])))
	var current_node_id: String = _active_node_id(actor, dialogue)
	var current_node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
	if current_node.is_empty():
		return {"success": false, "reason": "dialogue_node_missing", "node_id": current_node_id}
	if str(current_node.get("type", "")) == "dialog":
		var next_choice: Dictionary = _dictionary_or_empty(nodes.get(str(current_node.get("next", "")), {}))
		if str(next_choice.get("type", "")) == "choice":
			current_node = next_choice
			current_node_id = str(current_node.get("id", current_node_id))
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
		return _finish_missing_dialogue(simulation, actor_id, actor, dialogue_id)
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
		var target_context := _dialogue_target_context(simulation, actor)
		actor.active_dialogue_id = ""
		actor.active_dialogue_node_id = ""
		_clear_dialogue_target(actor)
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
			"target_context": target_context,
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


func _finish_missing_dialogue(simulation: RefCounted, actor_id: int, actor: RefCounted, dialogue_id: String) -> Dictionary:
	actor.active_dialogue_id = ""
	actor.active_dialogue_node_id = ""
	_clear_dialogue_target(actor)
	simulation.emit_event("dialogue_finished", {
		"actor_id": actor_id,
		"dialogue_id": dialogue_id,
		"node_id": "missing_dialogue",
		"end_type": "missing_dialogue",
		"reason": "unknown_dialogue",
	})
	return {
		"success": true,
		"dialogue_id": dialogue_id,
		"node_id": "missing_dialogue",
		"finished": true,
		"end_type": "missing_dialogue",
		"reason": "unknown_dialogue",
	}


func _advance_to_node(simulation: RefCounted, actor_id: int, actor: RefCounted, dialogue_id: String, node_id: String, nodes: Dictionary, emitted_actions: Array[Dictionary]) -> Dictionary:
	var current_node_id: String = node_id
	while not current_node_id.is_empty():
		var node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
		if node.is_empty():
			return {"success": false, "reason": "dialogue_node_missing", "node_id": current_node_id}
		var node_type: String = str(node.get("type", ""))
		match node_type:
			"action":
				var actions: Array = _array_or_empty(node.get("actions", []))
				var rollback_snapshot: Dictionary = simulation.snapshot()
				var node_action_results: Array[Dictionary] = []
				for action_index in range(actions.size()):
					var action_data: Dictionary = _dictionary_or_empty(actions[action_index])
					var action_result: Dictionary = _conditional_action_result(simulation, actor_id, actor, action_data)
					if action_result.is_empty():
						action_result = _action_runner.apply_action(simulation, actor_id, action_data, _dialogue_action_context(simulation, dialogue_id, current_node_id, actor))
					emitted_actions.append(action_result)
					node_action_results.append(action_result)
					_emit_dialogue_action_resolved(simulation, actor_id, actor, dialogue_id, current_node_id, action_index, action_data, action_result)
					if not bool(action_result.get("success", false)):
						var action_type := str(action_result.get("type", action_data.get("type", "")))
						if _should_rollback_action_node(node_action_results):
							actor = _rollback_failed_action_node(simulation, actor_id, actor, rollback_snapshot, dialogue_id, current_node_id, action_index, actions, node_action_results, action_result)
						simulation.emit_event("dialogue_action_failed", {
							"actor_id": actor_id,
							"dialogue_id": dialogue_id,
							"node_id": current_node_id,
							"action_type": action_type,
							"reason": str(action_result.get("reason", "dialogue_action_failed")),
							"action_result": action_result.duplicate(true),
						})
						return {
							"success": false,
							"reason": "dialogue_action_failed",
							"dialogue_id": dialogue_id,
							"node_id": current_node_id,
							"action_type": action_type,
							"action_result": action_result,
						}
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
				var target_context := _dialogue_target_context(simulation, actor)
				actor.active_dialogue_id = ""
				actor.active_dialogue_node_id = ""
				_clear_dialogue_target(actor)
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
					"target_context": target_context,
				}
			_:
				return {"success": false, "reason": "dialogue_node_unsupported", "node_id": current_node_id, "node_type": node_type}

	var actor_dialogue_id: String = str(actor.active_dialogue_id)
	var target_context := _dialogue_target_context(simulation, actor)
	actor.active_dialogue_id = ""
	actor.active_dialogue_node_id = ""
	_clear_dialogue_target(actor)
	return {
		"success": true,
		"dialogue_id": actor_dialogue_id,
		"finished": true,
		"end_type": "leave",
		"target_context": target_context,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _should_rollback_action_node(node_action_results: Array[Dictionary]) -> bool:
	if node_action_results.size() <= 1:
		return false
	for result_index in range(node_action_results.size() - 1):
		var result: Dictionary = _dictionary_or_empty(node_action_results[result_index])
		if bool(result.get("success", false)) and not bool(result.get("skipped", false)):
			return true
	return false


func _rollback_failed_action_node(
		simulation: RefCounted,
		actor_id: int,
		actor: RefCounted,
		rollback_snapshot: Dictionary,
		dialogue_id: String,
		node_id: String,
		failed_action_index: int,
		actions: Array,
		node_action_results: Array[Dictionary],
		failed_action_result: Dictionary) -> RefCounted:
	if rollback_snapshot.is_empty():
		return actor
	simulation.load_snapshot(rollback_snapshot)
	var restored_actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	simulation.emit_event("dialogue_action_rollback", {
		"actor_id": actor_id,
		"dialogue_id": dialogue_id,
		"node_id": node_id,
		"failed_action_index": failed_action_index,
		"failed_action_type": str(failed_action_result.get("type", _dictionary_or_empty(actions[failed_action_index]).get("type", ""))),
		"reason": str(failed_action_result.get("reason", "dialogue_action_failed")),
		"rolled_back_action_count": node_action_results.size(),
		"action_results": _duplicate_dictionary_array(node_action_results),
	})
	for replay_index in range(node_action_results.size()):
		var replay_action: Dictionary = _dictionary_or_empty(actions[replay_index])
		_emit_dialogue_action_resolved(simulation, actor_id, restored_actor, dialogue_id, node_id, replay_index, replay_action, node_action_results[replay_index])
	return restored_actor


func _duplicate_dictionary_array(values: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value in values:
		output.append(_dictionary_or_empty(value).duplicate(true))
	return output


func _conditional_action_result(simulation: RefCounted, actor_id: int, actor: RefCounted, action_data: Dictionary) -> Dictionary:
	var condition: Dictionary = _action_condition(action_data)
	if condition.is_empty():
		return {}
	var target_actor: RefCounted = _dialogue_target_actor(simulation, actor)
	if _dialogue_action_condition_matches(simulation, actor, target_actor, condition):
		return {}
	var action_type := str(action_data.get("type", action_data.get("action_type", "")))
	var target_context := _dialogue_target_context(simulation, actor)
	return {
		"type": action_type,
		"success": true,
		"skipped": true,
		"status": "condition_not_met",
		"reason": "dialogue_action_condition_not_met",
		"actor_id": actor_id,
		"target_actor_id": int(target_context.get("target_actor_id", 0)),
		"target_definition_id": str(target_context.get("target_definition_id", "")),
		"condition": condition.duplicate(true),
	}


func _action_condition(action_data: Dictionary) -> Dictionary:
	for key in ["when", "condition", "conditions"]:
		var condition: Dictionary = _dictionary_or_empty(action_data.get(key, {}))
		if not condition.is_empty():
			return condition
	return {}


func _dialogue_action_condition_matches(simulation: RefCounted, actor: RefCounted, target_actor: RefCounted, condition: Dictionary) -> bool:
	if condition.is_empty():
		return true
	if condition.has("player_active_quests_any") and not _dictionary_has_any_key(simulation.active_quests, _array_or_empty(condition.get("player_active_quests_any", []))):
		return false
	if condition.has("player_completed_quests_any") and not _dictionary_has_any_key(simulation.completed_quests, _array_or_empty(condition.get("player_completed_quests_any", []))):
		return false
	if condition.has("player_item_count_min") and not _player_item_count_min_met(actor, _dictionary_or_empty(condition.get("player_item_count_min", {}))):
		return false
	if condition.has("world_flags_all") and not _dictionary_has_all_keys(simulation.world_flags, _array_or_empty(condition.get("world_flags_all", []))):
		return false
	if condition.has("world_flags_any") and not _dictionary_has_any_key(simulation.world_flags, _array_or_empty(condition.get("world_flags_any", []))):
		return false
	if condition.has("world_flags_none") and _dictionary_has_any_key(simulation.world_flags, _array_or_empty(condition.get("world_flags_none", []))):
		return false
	if condition.has("relation_score_min") and _relation_score(simulation, actor, target_actor) < float(condition.get("relation_score_min", 0.0)):
		return false
	if condition.has("relation_score_max") and _relation_score(simulation, actor, target_actor) > float(condition.get("relation_score_max", 0.0)):
		return false
	if condition.has("npc_role_in") and not _array_or_empty(condition.get("npc_role_in", [])).has(str(_dictionary_or_empty(target_actor.life if target_actor != null else {}).get("role", ""))):
		return false
	if condition.has("npc_on_shift") and bool(condition.get("npc_on_shift", false)) != _npc_on_shift(target_actor):
		return false
	if condition.has("player_hp_ratio_min") and _hp_ratio(actor) < float(condition.get("player_hp_ratio_min", 0.0)):
		return false
	if condition.has("player_hp_ratio_max") and _hp_ratio(actor) > float(condition.get("player_hp_ratio_max", 1.0)):
		return false
	return true


func _dictionary_has_any_key(dictionary: Dictionary, keys: Array) -> bool:
	for key in keys:
		if dictionary.has(str(key)):
			return true
	return false


func _dictionary_has_all_keys(dictionary: Dictionary, keys: Array) -> bool:
	for key in keys:
		if not dictionary.has(str(key)):
			return false
	return true


func _player_item_count_min_met(actor: RefCounted, requirements: Dictionary) -> bool:
	if actor == null:
		return false
	for item_id in requirements.keys():
		if int(actor.inventory.get(str(item_id), 0)) < int(requirements[item_id]):
			return false
	return true


func _relation_score(simulation: RefCounted, actor: RefCounted, target_actor: RefCounted) -> float:
	if simulation == null or actor == null or target_actor == null:
		return 0.0
	if simulation.has_method("relationship_score"):
		return float(simulation.call("relationship_score", actor.actor_id, target_actor.actor_id))
	return 0.0


func _npc_on_shift(target_actor: RefCounted) -> bool:
	if target_actor == null:
		return false
	var life: Dictionary = _dictionary_or_empty(target_actor.life)
	if life.has("on_shift"):
		return bool(life.get("on_shift", false))
	if not str(life.get("duty_route_id", "")).is_empty():
		return true
	return false


func _hp_ratio(actor: RefCounted) -> float:
	if actor == null or actor.max_hp <= 0.0:
		return 1.0
	return clampf(actor.hp / actor.max_hp, 0.0, 1.0)


func _dialogue_target_actor(simulation: RefCounted, actor: RefCounted) -> RefCounted:
	if simulation == null or actor == null:
		return null
	var target_actor_id := int(actor.active_dialogue_target_actor_id)
	if target_actor_id > 0:
		return simulation.actor_registry.get_actor(target_actor_id)
	var target_definition_id := str(actor.active_dialogue_target_definition_id)
	if target_definition_id.is_empty():
		return null
	for candidate in simulation.actor_registry.actors():
		if candidate.actor_id != actor.actor_id and candidate.definition_id == target_definition_id:
			return candidate
	return null


func _dialogue_target_context(simulation: RefCounted, actor: RefCounted) -> Dictionary:
	var target_actor_id := int(actor.active_dialogue_target_actor_id) if actor != null else 0
	var target_definition_id := str(actor.active_dialogue_target_definition_id) if actor != null else ""
	var target_actor: RefCounted = _dialogue_target_actor(simulation, actor)
	if target_actor != null:
		target_actor_id = int(target_actor.actor_id)
		target_definition_id = str(target_actor.definition_id)
	return {
		"target_actor_id": target_actor_id,
		"target_definition_id": target_definition_id,
	}


func _emit_dialogue_action_resolved(simulation: RefCounted, actor_id: int, actor: RefCounted, dialogue_id: String, node_id: String, action_index: int, action_data: Dictionary, action_result: Dictionary) -> void:
	if simulation == null or not simulation.has_method("emit_event"):
		return
	var action_type := str(action_result.get("type", action_data.get("type", action_data.get("action_type", ""))))
	var target_context := _dialogue_target_context(simulation, actor)
	var payload := {
		"actor_id": actor_id,
		"dialogue_id": dialogue_id,
		"node_id": node_id,
		"action_index": action_index,
		"action_type": action_type,
		"success": bool(action_result.get("success", false)),
		"reason": str(action_result.get("reason", "")),
		"target_actor_id": int(target_context.get("target_actor_id", 0)),
		"target_definition_id": str(target_context.get("target_definition_id", "")),
		"action_summary": _dialogue_action_summary(action_data, action_result),
		"action_result": action_result.duplicate(true),
	}
	simulation.emit_event("dialogue_action_resolved", payload)


func _dialogue_action_summary(action_data: Dictionary, action_result: Dictionary) -> Dictionary:
	var summary := {
		"type": str(action_result.get("type", action_data.get("type", action_data.get("action_type", "")))),
	}
	for key in [
		"quest_id",
		"location_id",
		"shop_id",
		"item_id",
		"flag_id",
		"target_actor_id",
		"target_definition_id",
		"count",
		"status",
	]:
		if action_result.has(key):
			summary[key] = action_result.get(key)
		elif action_data.has(key):
			summary[key] = action_data.get(key)
	if bool(action_result.get("skipped", false)):
		summary["skipped"] = true
		summary["condition"] = _dictionary_or_empty(action_result.get("condition", {})).duplicate(true)
	return summary


func _dialogue_action_context(simulation: RefCounted, dialogue_id: String, node_id: String, actor: RefCounted) -> Dictionary:
	var target_context := _dialogue_target_context(simulation, actor)
	return {
		"source": "dialogue",
		"dialogue_id": dialogue_id,
		"dialogue_node_id": node_id,
		"target_actor_id": int(target_context.get("target_actor_id", 0)),
		"target_definition_id": str(target_context.get("target_definition_id", "")),
	}


func _clear_dialogue_target(actor: RefCounted) -> void:
	if actor == null:
		return
	actor.active_dialogue_target_actor_id = 0
	actor.active_dialogue_target_definition_id = ""
