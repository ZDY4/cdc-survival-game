extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	var items: Array[Dictionary] = []
	var total_weight := 0.0
	for item_id in inventory.keys():
		var count: int = int(inventory[item_id])
		if count <= 0:
			continue
		var item_snapshot: Dictionary = _item_snapshot(str(item_id), count)
		total_weight += float(item_snapshot.get("total_weight", 0.0))
		items.append(item_snapshot)

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
	)
	return {
		"owner_actor_id": int(player.get("actor_id", 0)),
		"owner_name": str(player.get("display_name", "")),
		"items": items,
		"item_count": items.size(),
		"total_weight": total_weight,
	}


func _item_snapshot(item_id: String, count: int) -> Dictionary:
	var record: Dictionary = registry.get_library("items").get(item_id, {})
	if record.is_empty():
		return {
			"item_id": item_id,
			"name": item_id,
			"description": "",
			"count": count,
			"unit_weight": 0.0,
			"total_weight": 0.0,
			"rarity": "",
		}

	var data: Dictionary = record.get("data", {})
	var unit_weight: float = float(data.get("weight", 0.0))
	return {
		"item_id": item_id,
		"name": str(data.get("name", item_id)),
		"description": str(data.get("description", "")),
		"count": count,
		"unit_weight": unit_weight,
		"total_weight": unit_weight * float(count),
		"rarity": _rarity(data),
	}


func _rarity(item_data: Dictionary) -> String:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "economy":
			return str(fragment_data.get("rarity", ""))
	return ""


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
