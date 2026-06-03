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
	var manual_turn_in: bool = bool(objective.get("manual_turn_in", false))
	var turn_in_ready: bool = manual_turn_in and current >= target
	return {
		"quest_id": quest_id,
		"title": str(quest_data.get("title", quest_id)),
		"description": str(quest_data.get("description", "")),
		"objective_text": str(objective.get("description", quest_data.get("description", ""))),
		"progress_current": current,
		"progress_target": target,
		"manual_turn_in": manual_turn_in,
		"turn_in_ready": turn_in_ready,
		"status_text": _status_text(manual_turn_in, turn_in_ready, current, target),
		"rewards": _reward_snapshot(quest_data),
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


func _reward_snapshot(quest_data: Dictionary) -> Dictionary:
	var reward_node: Dictionary = _reward_node(quest_data)
	var rewards: Dictionary = _dictionary_or_empty(reward_node.get("rewards", {}))
	var items: Array[Dictionary] = []
	for item in _array_or_empty(rewards.get("items", [])):
		var item_data: Dictionary = _dictionary_or_empty(item)
		var item_id: String = _normalize_content_id(item_data.get("id", item_data.get("item_id", "")))
		items.append({
			"item_id": item_id,
			"name": _item_name(item_id),
			"count": max(1, int(item_data.get("count", 1))),
		})
	return {
		"items": items,
		"experience": int(rewards.get("experience", 0)),
		"skill_points": int(rewards.get("skill_points", 0)),
	}


func _reward_node(quest_data: Dictionary) -> Dictionary:
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	for node_id in nodes.keys():
		var node: Dictionary = _dictionary_or_empty(nodes[node_id])
		if node.get("type", "") == "reward":
			return node
	return {}


func _status_text(manual_turn_in: bool, ready: bool, current: int, target: int) -> String:
	if manual_turn_in and ready:
		return "可交付"
	if manual_turn_in:
		return "待收集 %d/%d" % [current, target]
	if current >= target:
		return "已达成"
	return "进行中"


func _item_name(item_id: String) -> String:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("items").get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", item_id))


func _normalize_content_id(value: Variant) -> String:
	if value == null:
		return ""
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	if typeof(value) == TYPE_INT:
		return str(value)
	var text := str(value).strip_edges()
	return "" if text == "<null>" else text


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
