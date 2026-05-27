extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary) -> Dictionary:
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

	return {
		"active": true,
		"container_id": container_id,
		"display_name": str(session.get("display_name", container_id)),
		"items": _item_snapshots(session.get("inventory", [])),
	}


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
			"rarity": _rarity(item_data),
		})

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
	)
	return items


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
