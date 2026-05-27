extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary) -> Dictionary:
	var quests: Array[Dictionary] = []
	for quest_state in runtime_snapshot.get("active_quests", []):
		var state: Dictionary = _dictionary_or_empty(quest_state)
		var view: Dictionary = _quest_view(state)
		if not view.is_empty():
			quests.append(view)

	quests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")) < str(b.get("title", ""))
	)
	return {
		"quests": quests,
		"completed_count": runtime_snapshot.get("completed_quests", []).size(),
	}


func _quest_view(state: Dictionary) -> Dictionary:
	var quest_id: String = str(state.get("quest_id", ""))
	var record: Dictionary = registry.get_library("quests").get(quest_id, {})
	if record.is_empty():
		return {}

	var quest_data: Dictionary = record.get("data", {})
	var objective: Dictionary = _current_objective(quest_data, str(state.get("current_node_id", "")))
	var objective_id: String = str(objective.get("id", ""))
	var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {}))
	var target: int = max(1, int(objective.get("count", 0)))
	var current: int = int(completed.get(objective_id, 0)) if not objective_id.is_empty() else 0
	return {
		"quest_id": quest_id,
		"title": str(quest_data.get("title", quest_id)),
		"description": str(quest_data.get("description", "")),
		"objective_text": str(objective.get("description", quest_data.get("description", ""))),
		"progress_current": current,
		"progress_target": target,
		"manual_turn_in": bool(objective.get("manual_turn_in", false)),
	}


func _current_objective(quest_data: Dictionary, current_node_id: String) -> Dictionary:
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	var current_node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
	if current_node.get("type", "") == "objective":
		return current_node
	for node_id in nodes.keys():
		var node: Dictionary = _dictionary_or_empty(nodes[node_id])
		if node.get("type", "") == "objective":
			return node
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
