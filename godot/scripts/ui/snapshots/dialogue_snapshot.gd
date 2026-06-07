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
		"options": _options_from_node(choice_node),
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


func _options_from_node(node: Dictionary) -> Array[Dictionary]:
	if node.get("type", "") != "choice":
		return []
	var output: Array[Dictionary] = []
	for option in node.get("options", []):
		var option_data: Dictionary = _dictionary_or_empty(option)
		output.append({
			"text": str(option_data.get("text", "")),
			"next": str(option_data.get("next", "")),
		})
	return output


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
