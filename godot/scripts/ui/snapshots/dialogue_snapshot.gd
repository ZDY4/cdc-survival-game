extends RefCounted

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var dialogue_id: String = str(player.get("active_dialogue_id", ""))
	if dialogue_id.is_empty():
		return {"active": false}

	var dialogue_record: Dictionary = registry.get_library("dialogues").get(dialogue_id, {})
	if dialogue_record.is_empty():
		return {
			"active": true,
			"dialogue_id": dialogue_id,
			"node_id": "missing_dialogue",
			"speaker": "对话",
			"target": _dialogue_target(runtime_snapshot, dialogue_id),
			"text": "对话资源缺失：%s" % dialogue_id,
			"portrait": "",
			"portrait_asset": AssetPathResolver.resolve_media_asset("", "portrait"),
			"options": [],
			"fallback": true,
			"error": "unknown_dialogue",
		}

	var dialogue_data: Dictionary = dialogue_record.get("data", {})
	var nodes: Array = dialogue_data.get("nodes", [])
	var node_map: Dictionary = _nodes_by_id(nodes)
	var start_node: Dictionary = _start_node(nodes)
	var current_node: Dictionary = _current_node(player, start_node, node_map)
	var choice_node: Dictionary = current_node
	if current_node.get("type", "") == "dialog":
		choice_node = _dictionary_or_empty(node_map.get(str(current_node.get("next", "")), {}))

	return {
		"active": true,
		"dialogue_id": dialogue_id,
		"node_id": current_node.get("id", ""),
		"speaker": current_node.get("speaker", ""),
		"target": _dialogue_target(runtime_snapshot, dialogue_id),
		"text": current_node.get("text", ""),
		"portrait": current_node.get("portrait", ""),
		"portrait_asset": AssetPathResolver.resolve_media_asset(str(current_node.get("portrait", "")), "portrait"),
		"options": _options_from_node(choice_node, node_map, runtime_snapshot, player),
	}


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _nodes_by_id(nodes: Array) -> Dictionary:
	var output: Dictionary = {}
	for node in nodes:
		var node_data: Dictionary = _dictionary_or_empty(node)
		var node_id: String = str(node_data.get("id", ""))
		if not node_id.is_empty():
			output[node_id] = node_data
	return output


func _start_node(nodes: Array) -> Dictionary:
	for node in nodes:
		var node_data: Dictionary = _dictionary_or_empty(node)
		if bool(node_data.get("is_start", false)):
			return node_data
	if not nodes.is_empty():
		return _dictionary_or_empty(nodes[0])
	return {}


func _current_node(player: Dictionary, start_node: Dictionary, node_map: Dictionary) -> Dictionary:
	var current_node_id: String = str(player.get("active_dialogue_node_id", ""))
	if not current_node_id.is_empty() and node_map.has(current_node_id):
		return _dictionary_or_empty(node_map[current_node_id])
	return start_node


func _options_from_node(node: Dictionary, node_map: Dictionary, runtime_snapshot: Dictionary, player: Dictionary) -> Array[Dictionary]:
	if node.get("type", "") != "choice":
		return []
	var output: Array[Dictionary] = []
	for option in node.get("options", []):
		var option_data: Dictionary = _dictionary_or_empty(option)
		var next_node_id := str(option_data.get("next", ""))
		var resolution_preview := _resolution_preview(next_node_id, node_map, runtime_snapshot, player)
		output.append({
			"id": str(option_data.get("id", "")),
			"text": str(option_data.get("text", "")),
			"next": next_node_id,
			"resolution_preview": resolution_preview,
			"action_previews": _array_or_empty(resolution_preview.get("action_previews", [])),
			"action_types_preview": _array_or_empty(resolution_preview.get("action_types", [])),
			"end_type_preview": str(resolution_preview.get("end_type", "")),
			"next_node_preview": str(resolution_preview.get("next_node_id", "")),
			"next_node_type_preview": str(resolution_preview.get("next_node_type", "")),
			"will_finish_preview": bool(resolution_preview.get("will_finish", false)),
		})
	return output


func _resolution_preview(node_id: String, node_map: Dictionary, runtime_snapshot: Dictionary, player: Dictionary) -> Dictionary:
	var action_previews: Array[Dictionary] = []
	var action_types: Array[String] = []
	var visited: Dictionary = {}
	var current_node_id := node_id
	var steps := 0
	while not current_node_id.is_empty() and steps < 32:
		steps += 1
		if visited.has(current_node_id):
			return _resolution_failure("dialogue_resolution_cycle", node_id, current_node_id, "", action_previews, action_types)
		visited[current_node_id] = true
		var current_node: Dictionary = _dictionary_or_empty(node_map.get(current_node_id, {}))
		if current_node.is_empty():
			return _resolution_failure("dialogue_node_missing", node_id, current_node_id, "", action_previews, action_types)
		var node_type := str(current_node.get("type", ""))
		match node_type:
			"action":
				for action in _array_or_empty(current_node.get("actions", [])):
					var action_preview := _action_preview(_dictionary_or_empty(action), current_node_id, runtime_snapshot, player)
					action_previews.append(action_preview)
					var action_type := str(action_preview.get("type", ""))
					if not action_type.is_empty():
						action_types.append(action_type)
				current_node_id = str(current_node.get("next", ""))
			"dialog", "choice":
				return _resolution_success(node_id, current_node_id, node_type, false, "", action_previews, action_types)
			"end":
				return _resolution_success(node_id, current_node_id, node_type, true, str(current_node.get("end_type", "leave")), action_previews, action_types)
			_:
				return _resolution_failure("dialogue_node_unsupported", node_id, current_node_id, node_type, action_previews, action_types)
	return _resolution_success(node_id, "", "implicit_end", true, "leave", action_previews, action_types)


func _resolution_success(start_node_id: String, next_node_id: String, next_node_type: String, will_finish: bool, end_type: String, action_previews: Array[Dictionary], action_types: Array[String]) -> Dictionary:
	return {
		"ok": true,
		"start_node_id": start_node_id,
		"next_node_id": next_node_id,
		"next_node_type": next_node_type,
		"will_finish": will_finish,
		"end_type": end_type,
		"action_previews": action_previews,
		"action_types": action_types,
		"action_count": action_previews.size(),
	}


func _resolution_failure(reason: String, start_node_id: String, node_id: String, node_type: String, action_previews: Array[Dictionary], action_types: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"start_node_id": start_node_id,
		"node_id": node_id,
		"node_type": node_type,
		"action_previews": action_previews,
		"action_types": action_types,
		"action_count": action_previews.size(),
	}


func _action_preview(action: Dictionary, node_id: String, runtime_snapshot: Dictionary, player: Dictionary) -> Dictionary:
	var action_type := str(action.get("type", action.get("action_type", "")))
	var condition: Dictionary = _action_condition(action)
	var preview := {
		"type": action_type,
		"node_id": node_id,
		"requires_runtime_validation": not condition.is_empty() or action_type in ["turn_in_quest", "start_quest", "give_item", "give_reward", "grant_item", "grant_reward", "change_relationship", "adjust_relationship", "set_relationship"],
	}
	if not condition.is_empty():
		preview["has_condition"] = true
		preview["condition_preview"] = _condition_preview(condition, runtime_snapshot, player)
	match action_type:
		"start_quest", "turn_in_quest":
			preview["quest_id"] = str(action.get("quest_id", action.get("questId", "")))
			if action_type == "turn_in_quest":
				preview["turn_in_preview"] = _turn_in_quest_preview(str(preview.get("quest_id", "")), runtime_snapshot, player)
		"open_trade":
			preview["shop_id"] = str(action.get("shop_id", action.get("shopId", action.get("action_key", action.get("actionKey", "")))))
		"unlock_location":
			preview["location_id"] = str(action.get("location_id", action.get("locationId", "")))
		"set_world_flag", "set_flag", "world_flag":
			preview["flag_id"] = str(action.get("flag_id", action.get("flagId", action.get("world_flag", action.get("worldFlag", "")))))
			preview["value"] = bool(action.get("value", action.get("enabled", true)))
		"give_item", "grant_item":
			preview["item_id"] = str(action.get("item_id", action.get("itemId", action.get("id", ""))))
			preview["count"] = max(1, int(action.get("count", 1)))
		"give_reward", "grant_reward":
			var rewards: Dictionary = _dictionary_or_empty(action.get("rewards", action))
			preview["reward_summary"] = {
				"item_count": _array_or_empty(rewards.get("items", [])).size(),
				"money": int(rewards.get("money", 0)),
				"experience": int(rewards.get("experience", rewards.get("xp", 0))),
				"skill_points": int(rewards.get("skill_points", rewards.get("skillPoints", 0))),
			}
		"change_relationship", "adjust_relationship", "set_relationship":
			preview["target_definition_id"] = str(action.get("target_definition_id", action.get("targetDefinitionId", "")))
			preview["delta"] = float(action.get("delta", action.get("amount", 0.0)))
	return preview


func _action_condition(action: Dictionary) -> Dictionary:
	for key in ["when", "condition", "conditions"]:
		var condition: Dictionary = _dictionary_or_empty(action.get(key, {}))
		if not condition.is_empty():
			return condition
	return {}


func _condition_preview(condition: Dictionary, runtime_snapshot: Dictionary, player: Dictionary) -> Dictionary:
	var missing: Array[Dictionary] = []
	if condition.has("player_active_quests_any") and not _quest_list_has_any(runtime_snapshot.get("active_quests", []), _array_or_empty(condition.get("player_active_quests_any", []))):
		missing.append({"kind": "player_active_quests_any", "ids": _array_or_empty(condition.get("player_active_quests_any", []))})
	if condition.has("player_completed_quests_any") and not _completed_quests_have_any(runtime_snapshot.get("completed_quests", []), _array_or_empty(condition.get("player_completed_quests_any", []))):
		missing.append({"kind": "player_completed_quests_any", "ids": _array_or_empty(condition.get("player_completed_quests_any", []))})
	if condition.has("player_item_count_min"):
		var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
		for item_id in _dictionary_or_empty(condition.get("player_item_count_min", {})).keys():
			var required := int(_dictionary_or_empty(condition.get("player_item_count_min", {})).get(item_id, 0))
			var current := int(inventory.get(str(item_id), 0))
			if current < required:
				missing.append({"kind": "player_item_count_min", "item_id": str(item_id), "required": required, "current": current})
	if condition.has("world_flags_all") and not _flag_list_has_all(runtime_snapshot.get("world_flags", []), _array_or_empty(condition.get("world_flags_all", []))):
		missing.append({"kind": "world_flags_all", "ids": _array_or_empty(condition.get("world_flags_all", []))})
	if condition.has("world_flags_any") and not _flag_list_has_any(runtime_snapshot.get("world_flags", []), _array_or_empty(condition.get("world_flags_any", []))):
		missing.append({"kind": "world_flags_any", "ids": _array_or_empty(condition.get("world_flags_any", []))})
	if condition.has("world_flags_none") and _flag_list_has_any(runtime_snapshot.get("world_flags", []), _array_or_empty(condition.get("world_flags_none", []))):
		missing.append({"kind": "world_flags_none", "ids": _array_or_empty(condition.get("world_flags_none", []))})
	return {
		"condition": condition.duplicate(true),
		"ready": missing.is_empty(),
		"missing": missing,
		"reason": "" if missing.is_empty() else "dialogue_action_condition_not_met",
	}


func _turn_in_quest_preview(quest_id: String, runtime_snapshot: Dictionary, player: Dictionary) -> Dictionary:
	var active_state: Dictionary = _active_quest_state(runtime_snapshot, quest_id)
	var record: Dictionary = _dictionary_or_empty(registry.get_library("quests").get(quest_id, {}))
	var quest_data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var title: String = str(quest_data.get("title", quest_id))
	if quest_id.is_empty() or quest_data.is_empty():
		return _turn_in_preview_result(quest_id, title, false, "unknown_quest", [], [], "", 0, 1)
	if active_state.is_empty():
		return _turn_in_preview_result(quest_id, title, false, "quest_not_active", [], [], "", 0, 1)
	var objective: Dictionary = _quest_objective(quest_data, str(active_state.get("current_node_id", "")))
	if objective.is_empty() or not bool(objective.get("manual_turn_in", false)):
		return _turn_in_preview_result(quest_id, title, false, "quest_not_waiting_for_turn_in", [], [], "", 0, 1)
	var objective_id: String = str(objective.get("id", ""))
	var completed: Dictionary = _dictionary_or_empty(active_state.get("completed_objectives", {}))
	var target: int = max(1, int(objective.get("count", 1)))
	var current: int = int(completed.get(objective_id, 0)) if not objective_id.is_empty() else 0
	var item_id: String = _normalize_content_id(objective.get("item_id", ""))
	var item_name: String = _item_name(item_id)
	var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	var inventory_count: int = int(inventory.get(item_id, 0)) if not item_id.is_empty() else 0
	var requirements: Array[Dictionary] = []
	var missing: Array[Dictionary] = []
	if not item_id.is_empty():
		var item_requirement: Dictionary = {
			"kind": "item",
			"item_id": item_id,
			"item_name": item_name,
			"required": target,
			"current": inventory_count,
			"ready": inventory_count >= target,
			"text": "%s %d/%d" % [item_name if not item_name.is_empty() else item_id, inventory_count, target],
		}
		requirements.append(item_requirement)
		if not bool(item_requirement.get("ready", false)):
			missing.append(item_requirement)
	var turn_in_info: Dictionary = _turn_in_info(quest_data, objective)
	if bool(turn_in_info.get("requires_dialogue", false)):
		requirements.append({
			"kind": "dialogue",
			"target_definition_id": str(turn_in_info.get("target_definition_id", "")),
			"target_name": str(turn_in_info.get("target_name", "")),
			"dialogue_id": str(turn_in_info.get("dialogue_id", "")),
			"dialogue_rule_id": str(turn_in_info.get("dialogue_rule_id", "")),
			"ready": true,
			"text": str(turn_in_info.get("summary", "")),
		})
	var reason: String = ""
	if current < target:
		reason = "quest_objective_incomplete"
	elif not missing.is_empty():
		reason = "not_enough_items"
	var ready: bool = reason.is_empty()
	return _turn_in_preview_result(quest_id, title, ready, reason, requirements, missing, str(turn_in_info.get("summary", "")), current, target)


func _turn_in_preview_result(quest_id: String, title: String, ready: bool, reason: String, requirements: Array[Dictionary], missing: Array[Dictionary], turn_in_summary: String, current: int, target: int) -> Dictionary:
	var parts: Array[String] = []
	if not title.is_empty():
		parts.append(title)
	for requirement in requirements:
		var text := str(_dictionary_or_empty(requirement).get("text", ""))
		if not text.is_empty():
			parts.append(text)
	if not turn_in_summary.is_empty():
		parts.append(turn_in_summary)
	return {
		"quest_id": quest_id,
		"title": title,
		"ready": ready,
		"reason": reason,
		"objective_current": current,
		"objective_target": target,
		"requirements": requirements,
		"missing_requirements": missing,
		"turn_in_summary": turn_in_summary,
		"summary": " / ".join(parts),
	}


func _active_quest_state(runtime_snapshot: Dictionary, quest_id: String) -> Dictionary:
	for state in _array_or_empty(runtime_snapshot.get("active_quests", [])):
		var state_data: Dictionary = _dictionary_or_empty(state)
		if str(state_data.get("quest_id", "")) == quest_id:
			return state_data
	return {}


func _quest_list_has_any(values: Variant, required_ids: Array) -> bool:
	for state in _array_or_empty(values):
		var state_data: Dictionary = _dictionary_or_empty(state)
		if required_ids.has(str(state_data.get("quest_id", ""))):
			return true
	return false


func _completed_quests_have_any(values: Variant, required_ids: Array) -> bool:
	for quest_id in _array_or_empty(values):
		if required_ids.has(str(quest_id)):
			return true
	return false


func _flag_list_has_any(values: Variant, required_ids: Array) -> bool:
	for flag_id in _array_or_empty(values):
		if required_ids.has(str(flag_id)):
			return true
	return false


func _flag_list_has_all(values: Variant, required_ids: Array) -> bool:
	for required_id in required_ids:
		if not _flag_list_has_any(values, [str(required_id)]):
			return false
	return true


func _quest_objective(quest_data: Dictionary, current_node_id: String) -> Dictionary:
	var nodes: Dictionary = _dictionary_or_empty(_dictionary_or_empty(quest_data.get("flow", {})).get("nodes", {}))
	var current_node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
	if str(current_node.get("type", "")) == "objective":
		return current_node
	for node_id in nodes.keys():
		var node: Dictionary = _dictionary_or_empty(nodes[node_id])
		if str(node.get("type", "")) == "objective":
			return node
	return {}


func _turn_in_info(quest_data: Dictionary, objective: Dictionary) -> Dictionary:
	var source: Dictionary = quest_data.duplicate(true)
	for key in _dictionary_or_empty(quest_data.get("turn_in", {})).keys():
		source[key] = _dictionary_or_empty(quest_data.get("turn_in", {})).get(key)
	for key in objective.keys():
		var key_text := str(key)
		if key_text.begins_with("turn_in") or key_text.begins_with("turnIn") or key_text.contains("dialogue") or key_text.contains("target") or key_text == "npc":
			source[key] = objective.get(key)
	for key in _dictionary_or_empty(objective.get("turn_in", {})).keys():
		source[key] = _dictionary_or_empty(objective.get("turn_in", {})).get(key)
	var target_definition_id: String = _first_string(source, [
		"turn_in_target_definition_id",
		"turn_in_actor_definition_id",
		"target_definition_id",
		"targetDefinitionId",
		"npc_definition_id",
		"npc",
	])
	var dialogue_id: String = _first_string(source, ["turn_in_dialogue_id", "dialogue_id", "dialogue"])
	var dialogue_rule_id: String = _first_string(source, ["turn_in_dialogue_rule_id", "dialogue_rule_id"])
	var requires_dialogue: bool = bool(source.get("requires_dialogue_turn_in", source.get("turn_in_requires_dialogue", false)))
	if not target_definition_id.is_empty() or not dialogue_id.is_empty() or not dialogue_rule_id.is_empty():
		requires_dialogue = true
	var target_name: String = _character_name(target_definition_id)
	if target_name.is_empty():
		target_name = target_definition_id
	var parts: Array[String] = []
	if requires_dialogue:
		parts.append("对话交付")
		if not target_name.is_empty():
			parts.append("对象: %s" % target_name)
		if not dialogue_id.is_empty():
			parts.append("对话: %s" % dialogue_id)
		if not dialogue_rule_id.is_empty():
			parts.append("规则: %s" % dialogue_rule_id)
	return {
		"requires_dialogue": requires_dialogue,
		"target_definition_id": target_definition_id,
		"target_name": target_name,
		"dialogue_id": dialogue_id,
		"dialogue_rule_id": dialogue_rule_id,
		"summary": " / ".join(parts),
	}


func _item_name(item_id: String) -> String:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("items").get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	return str(data.get("name", data.get("display_name", item_id)))


func _character_name(definition_id: String) -> String:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("characters").get(definition_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var identity: Dictionary = _dictionary_or_empty(data.get("identity", {}))
	var identity_name := _first_string(identity, ["display_name", "name", "title"])
	if not identity_name.is_empty():
		return identity_name
	return _first_string(data, ["display_name", "name", "title"])


func _first_string(source: Dictionary, keys: Array[String]) -> String:
	for key in keys:
		var value := str(source.get(key, ""))
		if not value.is_empty():
			return value
	return ""


func _normalize_content_id(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		return str(int(value))
	if typeof(value) == TYPE_INT:
		return str(value)
	return str(value)


func _dialogue_target(runtime_snapshot: Dictionary, dialogue_id: String) -> Dictionary:
	var player := _player_actor(runtime_snapshot)
	var target_actor_id := int(player.get("active_dialogue_target_actor_id", 0))
	var target_definition_id := str(player.get("active_dialogue_target_definition_id", ""))
	var source := "active_actor_state" if target_actor_id > 0 or not target_definition_id.is_empty() else ""
	for index in range(runtime_snapshot.get("events", []).size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(runtime_snapshot.get("events", [])[index])
		if str(event.get("kind", "")) != "dialogue_started":
			continue
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		if str(payload.get("dialogue_id", "")) != dialogue_id:
			continue
		if target_actor_id <= 0:
			target_actor_id = int(payload.get("target_actor_id", 0))
		if target_definition_id.is_empty():
			target_definition_id = str(payload.get("target_definition_id", ""))
		if source.is_empty():
			source = "dialogue_started_event"
		break
	if target_actor_id <= 0 and not target_definition_id.is_empty():
		var actor_by_definition := _actor_by_definition(runtime_snapshot, target_definition_id)
		if not actor_by_definition.is_empty():
			target_actor_id = int(actor_by_definition.get("actor_id", 0))
			source = "definition_actor_lookup"
	if target_actor_id <= 0:
		if target_definition_id.is_empty():
			return {}
		return {
			"actor_id": 0,
			"definition_id": target_definition_id,
			"display_name": _character_name(target_definition_id),
			"source": source if not source.is_empty() else "definition_id",
		}
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == target_actor_id:
			var actor_definition_id := str(actor_data.get("definition_id", target_definition_id))
			var display_name := str(actor_data.get("display_name", ""))
			if display_name.is_empty():
				display_name = _character_name(actor_definition_id)
			return {
				"actor_id": target_actor_id,
				"definition_id": actor_definition_id,
				"display_name": display_name,
				"kind": str(actor_data.get("kind", "")),
				"side": str(actor_data.get("side", "")),
				"source": source if not source.is_empty() else "actor_id",
			}
	return {
		"actor_id": target_actor_id,
		"definition_id": target_definition_id,
		"display_name": _character_name(target_definition_id),
		"source": source if not source.is_empty() else "actor_id",
	}


func _actor_by_definition(runtime_snapshot: Dictionary, definition_id: String) -> Dictionary:
	if definition_id.is_empty():
		return {}
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if str(actor_data.get("definition_id", "")) == definition_id:
			return actor_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
