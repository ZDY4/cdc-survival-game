extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, feedback: Dictionary = {}) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var container_id: String = str(player.get("active_container_id", ""))
	if container_id.is_empty():
		return {"active": false}
	var session: Dictionary = _container_session(runtime_snapshot, container_id)
	if session.is_empty():
		return {
			"active": true,
			"container_id": container_id,
			"error": "unknown_container",
		}

	var snapshot := {
		"active": true,
		"container_id": container_id,
		"display_name": str(session.get("display_name", container_id)),
		"items": _item_snapshots(session.get("inventory", [])),
		"player_items": _inventory_item_snapshots(_dictionary_or_empty(player.get("inventory", {}))),
	}
	var scoped_feedback := _feedback_snapshot(feedback, container_id)
	if not scoped_feedback.is_empty():
		snapshot["feedback"] = scoped_feedback
	return snapshot


func _item_snapshots(entries: Array) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var item_id: String = _normalize_content_id(entry_data.get("item_id", ""))
		var count: int = int(entry_data.get("count", 0))
		if item_id.is_empty() or count <= 0:
			continue
		var item_data: Dictionary = _item_data(item_id)
		items.append({
			"item_id": item_id,
			"name": str(item_data.get("name", item_id)),
			"description": str(item_data.get("description", "")),
			"count": count,
			"unit_weight": float(item_data.get("weight", 0.0)),
			"total_weight": float(item_data.get("weight", 0.0)) * float(count),
			"rarity": _rarity(item_data),
		})

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
	)
	return items


func _inventory_item_snapshots(inventory: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for item_id in inventory.keys():
		var count := int(inventory[item_id])
		if count <= 0:
			continue
		var normalized_item_id := _normalize_content_id(item_id)
		if normalized_item_id.is_empty():
			continue
		var item_data: Dictionary = _item_data(normalized_item_id)
		entries.append({
			"item_id": normalized_item_id,
			"name": str(item_data.get("name", normalized_item_id)),
			"description": str(item_data.get("description", "")),
			"count": count,
			"unit_weight": float(item_data.get("weight", 0.0)),
			"total_weight": float(item_data.get("weight", 0.0)) * float(count),
			"rarity": _rarity(item_data),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
	)
	return entries


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _container_session(runtime_snapshot: Dictionary, container_id: String) -> Dictionary:
	for session in runtime_snapshot.get("container_sessions", []):
		var session_data: Dictionary = _dictionary_or_empty(session)
		if str(session_data.get("container_id", "")) == container_id:
			return session_data
	return {}


func _item_data(item_id: String) -> Dictionary:
	var record: Dictionary = registry.get_library("items").get(item_id, {})
	return _dictionary_or_empty(record.get("data", {}))


func _rarity(item_data: Dictionary) -> String:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "economy":
			return str(fragment_data.get("rarity", ""))
	return ""


func _feedback_snapshot(feedback: Dictionary, container_id: String) -> Dictionary:
	if feedback.is_empty():
		return {}
	if not str(feedback.get("container_id", container_id)).is_empty() and str(feedback.get("container_id", container_id)) != container_id:
		return {}
	var reason := str(feedback.get("reason", ""))
	var text := _feedback_text(feedback)
	if reason.is_empty() and text.is_empty():
		return {}
	return {
		"type": str(feedback.get("type", "error")),
		"reason": reason,
		"text": text,
	}


func _feedback_text(feedback: Dictionary) -> String:
	var explicit_text := str(feedback.get("text", ""))
	if not explicit_text.is_empty():
		return explicit_text
	var item_name := _feedback_item_name(feedback)
	var required := int(feedback.get("required", feedback.get("count", 1)))
	var current := int(feedback.get("current", 0))
	match str(feedback.get("reason", "")):
		"container_inventory_insufficient":
			return "容器中没有足够的%s，需要 %d，当前 %d。" % [item_name, required, current]
		"not_enough_items":
			return "背包中没有足够的%s，需要 %d，当前 %d。" % [item_name, required, current]
		"unknown_container":
			return "容器不存在或已经失效。"
		"unknown_item":
			return "物品数据不可用: %s。" % str(feedback.get("item_id", ""))
		"unknown_actor":
			return "当前角色不可用，无法操作容器。"
		"active_container_missing":
			return "没有打开的容器。"
		"invalid_quantity":
			return "数量无效，请输入大于 0 的数量。"
		_:
			return str(feedback.get("reason", ""))


func _feedback_item_name(feedback: Dictionary) -> String:
	var item_id := _normalize_content_id(feedback.get("item_id", ""))
	if item_id.is_empty():
		return "物品"
	var item_data := _item_data(item_id)
	return str(item_data.get("name", item_id))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _normalize_content_id(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		var float_value: float = value
		if is_equal_approx(float_value, roundf(float_value)):
			return str(int(float_value))
	if typeof(value) == TYPE_INT:
		return str(value)
	return str(value)
