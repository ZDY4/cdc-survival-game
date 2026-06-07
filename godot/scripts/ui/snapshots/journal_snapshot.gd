extends RefCounted

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")

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
	var completed_quests: Array[Dictionary] = []
	for quest_id in runtime_snapshot.get("completed_quests", []):
		var completed_view: Dictionary = _completed_quest_view(str(quest_id))
		if not completed_view.is_empty():
			completed_quests.append(completed_view)
	completed_quests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")) < str(b.get("title", ""))
	)
	return {
		"quests": quests,
		"completed_quests": completed_quests,
		"completed_count": completed_quests.size(),
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
	var objective_snapshot: Dictionary = _objective_snapshot(objective, current, target)
	var objective_progress: Array[Dictionary] = _objective_progress_list(quest_data, completed)
	var icon_asset := _quest_icon_asset(quest_data, objective_snapshot, false)
	return {
		"quest_id": quest_id,
		"title": str(quest_data.get("title", quest_id)),
		"description": str(quest_data.get("description", "")),
		"icon_asset": icon_asset,
		"thumbnail_asset": _thumbnail_asset(icon_asset, "quest"),
		"objective_text": str(objective.get("description", quest_data.get("description", ""))),
		"current_node_id": str(state.get("current_node_id", objective_id)),
		"objective": objective_snapshot,
		"objective_progress": objective_progress,
		"objective_id": objective_id,
		"objective_type": str(objective_snapshot.get("type", "")),
		"progress_current": current,
		"progress_target": target,
		"progress_percent": float(current) / float(max(1, target)),
		"manual_turn_in": manual_turn_in,
		"turn_in_ready": turn_in_ready,
		"status_text": _status_text(manual_turn_in, turn_in_ready, current, target),
		"rewards": _reward_snapshot(quest_data),
		"state": "active",
	}


func _completed_quest_view(quest_id: String) -> Dictionary:
	var record: Dictionary = registry.get_library("quests").get(quest_id, {})
	if record.is_empty():
		return {}
	var quest_data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var objective: Dictionary = _current_objective(quest_data, "")
	var objective_id := str(objective.get("id", ""))
	var target: int = max(1, int(objective.get("count", 0)))
	var objective_snapshot: Dictionary = _objective_snapshot(objective, target, target)
	var objective_progress: Array[Dictionary] = _completed_objective_progress_list(quest_data)
	var icon_asset := _quest_icon_asset(quest_data, objective_snapshot, true)
	return {
		"quest_id": quest_id,
		"title": str(quest_data.get("title", quest_id)),
		"description": str(quest_data.get("description", "")),
		"icon_asset": icon_asset,
		"thumbnail_asset": _thumbnail_asset(icon_asset, "quest"),
		"objective_text": str(objective.get("description", quest_data.get("description", ""))),
		"current_node_id": "completed",
		"objective": objective_snapshot,
		"objective_progress": objective_progress,
		"objective_id": objective_id,
		"objective_type": str(objective_snapshot.get("type", "")),
		"progress_current": target,
		"progress_target": target,
		"progress_percent": 1.0,
		"manual_turn_in": bool(objective.get("manual_turn_in", false)),
		"turn_in_ready": false,
		"status_text": "已完成",
		"rewards": _reward_snapshot(quest_data),
		"state": "completed",
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


func _thumbnail_asset(icon_asset: Dictionary, domain: String) -> Dictionary:
	var thumbnail := icon_asset.duplicate(true)
	thumbnail["thumbnail"] = true
	thumbnail["thumbnail_domain"] = domain
	thumbnail["source"] = "icon_asset"
	return thumbnail


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


func _objective_progress_list(quest_data: Dictionary, completed: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for objective in _all_objectives(quest_data):
		var objective_data: Dictionary = _dictionary_or_empty(objective)
		var objective_id: String = str(objective_data.get("id", ""))
		var target: int = max(1, int(objective_data.get("count", 0)))
		var current: int = int(completed.get(objective_id, 0)) if not objective_id.is_empty() else 0
		var snapshot: Dictionary = _objective_snapshot(objective_data, current, target)
		snapshot["state"] = "completed" if current >= target else "active"
		snapshot["progress_percent"] = float(current) / float(max(1, target))
		result.append(snapshot)
	return result


func _completed_objective_progress_list(quest_data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for objective in _all_objectives(quest_data):
		var objective_data: Dictionary = _dictionary_or_empty(objective)
		var target: int = max(1, int(objective_data.get("count", 0)))
		var snapshot: Dictionary = _objective_snapshot(objective_data, target, target)
		snapshot["state"] = "completed"
		snapshot["progress_percent"] = 1.0
		result.append(snapshot)
	return result


func _all_objectives(quest_data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	var keys: Array = nodes.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		var a_node: Dictionary = _dictionary_or_empty(nodes.get(a, {}))
		var b_node: Dictionary = _dictionary_or_empty(nodes.get(b, {}))
		var a_pos: Dictionary = _dictionary_or_empty(a_node.get("position", {}))
		var b_pos: Dictionary = _dictionary_or_empty(b_node.get("position", {}))
		var ay := float(a_pos.get("y", 0.0))
		var by := float(b_pos.get("y", 0.0))
		if not is_equal_approx(ay, by):
			return ay < by
		return float(a_pos.get("x", 0.0)) < float(b_pos.get("x", 0.0))
	)
	for node_id in keys:
		var node: Dictionary = _dictionary_or_empty(nodes.get(node_id, {}))
		if str(node.get("type", "")) == "objective":
			result.append(node)
	return result


func _objective_snapshot(objective: Dictionary, current: int, target: int) -> Dictionary:
	var objective_type := str(objective.get("objective_type", ""))
	var item_id: String = _normalize_content_id(objective.get("item_id", ""))
	var enemy_type := str(objective.get("enemy_type", ""))
	var requirement := ""
	match objective_type:
		"collect":
			requirement = "%s x%d" % [_item_name(item_id), target] if not item_id.is_empty() else "收集 %d 件物品" % target
		"kill":
			requirement = "%s x%d" % [enemy_type if not enemy_type.is_empty() else "敌人", target]
		_:
			requirement = "完成目标 x%d" % target
	return {
		"id": str(objective.get("id", "")),
		"type": objective_type,
		"description": str(objective.get("description", "")),
		"item_id": item_id,
		"item_name": _item_name(item_id) if not item_id.is_empty() else "",
		"enemy_type": enemy_type,
		"current": current,
		"target": target,
		"manual_turn_in": bool(objective.get("manual_turn_in", false)),
		"requirement_text": requirement,
	}


func _reward_node(quest_data: Dictionary) -> Dictionary:
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	for node_id in nodes.keys():
		var node: Dictionary = _dictionary_or_empty(nodes[node_id])
		if node.get("type", "") == "reward":
			return node
	return {}


func _quest_icon_asset(quest_data: Dictionary, objective: Dictionary, completed: bool) -> Dictionary:
	var explicit_path := str(quest_data.get("icon_path", quest_data.get("icon", "")))
	if not explicit_path.is_empty():
		return AssetPathResolver.resolve_media_asset(explicit_path, "quest")
	if completed:
		return AssetPathResolver.resolve_media_asset("res://assets/icons/quests/quest_completed.svg", "quest")
	match str(objective.get("type", "")):
		"kill":
			return AssetPathResolver.resolve_media_asset("res://assets/icons/quests/quest_kill.svg", "quest")
		"collect":
			return AssetPathResolver.resolve_media_asset("res://assets/icons/quests/quest_collect.svg", "quest")
		_:
			return AssetPathResolver.resolve_media_asset("res://assets/icons/quests/quest_collect.svg", "quest")


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
