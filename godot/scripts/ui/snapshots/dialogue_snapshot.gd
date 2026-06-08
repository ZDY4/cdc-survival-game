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
		"options": _options_from_node(choice_node, node_map),
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


func _options_from_node(node: Dictionary, node_map: Dictionary) -> Array[Dictionary]:
	if node.get("type", "") != "choice":
		return []
	var output: Array[Dictionary] = []
	for option in node.get("options", []):
		var option_data: Dictionary = _dictionary_or_empty(option)
		var next_node_id := str(option_data.get("next", ""))
		var resolution_preview := _resolution_preview(next_node_id, node_map)
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


func _resolution_preview(node_id: String, node_map: Dictionary) -> Dictionary:
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
					var action_preview := _action_preview(_dictionary_or_empty(action), current_node_id)
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


func _action_preview(action: Dictionary, node_id: String) -> Dictionary:
	var action_type := str(action.get("type", action.get("action_type", "")))
	var preview := {
		"type": action_type,
		"node_id": node_id,
		"requires_runtime_validation": action_type in ["turn_in_quest", "start_quest", "give_item", "give_reward", "grant_item", "grant_reward", "change_relationship", "adjust_relationship", "set_relationship"],
	}
	match action_type:
		"start_quest", "turn_in_quest":
			preview["quest_id"] = str(action.get("quest_id", action.get("questId", "")))
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


func _dialogue_target(runtime_snapshot: Dictionary, dialogue_id: String) -> Dictionary:
	var target_actor_id := 0
	for index in range(runtime_snapshot.get("events", []).size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(runtime_snapshot.get("events", [])[index])
		if str(event.get("kind", "")) != "dialogue_started":
			continue
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		if str(payload.get("dialogue_id", "")) != dialogue_id:
			continue
		target_actor_id = int(payload.get("target_actor_id", 0))
		break
	if target_actor_id <= 0:
		return {}
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == target_actor_id:
			return {
				"actor_id": target_actor_id,
				"definition_id": str(actor_data.get("definition_id", "")),
				"display_name": str(actor_data.get("display_name", "")),
				"kind": str(actor_data.get("kind", "")),
				"side": str(actor_data.get("side", "")),
			}
	return {"actor_id": target_actor_id}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
