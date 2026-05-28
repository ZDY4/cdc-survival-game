extends RefCounted


func quest_data(quest_library: Dictionary, quest_id: String) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(quest_library.get(quest_id, {}))
	return _dictionary_or_empty(record.get("data", {}))


func first_objective_node(quest_data: Dictionary) -> Dictionary:
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	for node_id in nodes.keys():
		var node: Dictionary = _dictionary_or_empty(nodes[node_id])
		if node.get("type", "") == "objective":
			return node
	return {}


func first_reward_node(quest_data: Dictionary) -> Dictionary:
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	for node_id in nodes.keys():
		var node: Dictionary = _dictionary_or_empty(nodes[node_id])
		if node.get("type", "") == "reward":
			return node
	return {}


func prerequisites_completed(completed_quests: Dictionary, quest_data: Dictionary) -> bool:
	for prerequisite in _array_or_empty(quest_data.get("prerequisites", [])):
		if not completed_quests.has(str(prerequisite)):
			return false
	return true


func enemy_matches_objective(enemy_definition_id: String, enemy_kind: String, enemy_type: String) -> bool:
	if enemy_type == enemy_kind or enemy_type == enemy_definition_id:
		return true
	if enemy_type == "zombie" and enemy_definition_id.begins_with("zombie_"):
		return true
	return false


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
