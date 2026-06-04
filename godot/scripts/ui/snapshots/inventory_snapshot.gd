extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	var inventory_order: Array[String] = _inventory_order(player.get("inventory_order", []), inventory)
	var items: Array[Dictionary] = []
	var total_weight := 0.0
	for order_index in range(inventory_order.size()):
		var item_id: String = inventory_order[order_index]
		var count: int = int(inventory.get(item_id, 0))
		if count <= 0:
			continue
		var item_snapshot: Dictionary = _item_snapshot(str(item_id), count)
		item_snapshot["order_index"] = order_index
		total_weight += float(item_snapshot.get("total_weight", 0.0))
		items.append(item_snapshot)
	return {
		"owner_actor_id": int(player.get("actor_id", 0)),
		"owner_name": str(player.get("display_name", "")),
		"items": items,
		"inventory_order": inventory_order,
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
			"value": 0,
			"total_value": 0,
			"rarity": "",
			"category": "misc",
			"category_label": _category_label("misc"),
			"equip_slots": [],
			"stackable": false,
			"max_stack": 1,
		}

	var data: Dictionary = record.get("data", {})
	var unit_weight: float = float(data.get("weight", 0.0))
	var value: int = int(data.get("value", 0))
	var category: String = _category(data)
	return {
		"item_id": item_id,
		"name": str(data.get("name", item_id)),
		"description": str(data.get("description", "")),
		"count": count,
		"unit_weight": unit_weight,
		"total_weight": unit_weight * float(count),
		"value": value,
		"total_value": value * count,
		"rarity": _rarity(data),
		"category": category,
		"category_label": _category_label(category),
		"equip_slots": _equip_slots(data),
		"stackable": _stackable(data),
		"max_stack": _max_stack(data),
	}


func _rarity(item_data: Dictionary) -> String:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "economy":
			return str(fragment_data.get("rarity", ""))
	return ""


func _category(item_data: Dictionary) -> String:
	if _has_fragment(item_data, "weapon") or _has_fragment(item_data, "equip"):
		return "equipment"
	if _has_fragment(item_data, "usable"):
		return "consumable"
	if str(item_data.get("icon_path", "")).contains("/ammo/") or str(item_data.get("name", "")).contains("弹药"):
		return "ammo"
	if _has_fragment(item_data, "crafting"):
		return "material"
	return "misc"


func _category_label(category: String) -> String:
	match category:
		"equipment":
			return "装备"
		"consumable":
			return "消耗"
		"ammo":
			return "弹药"
		"material":
			return "材料"
		_:
			return "杂项"


func _equip_slots(item_data: Dictionary) -> Array[String]:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") != "equip":
			continue
		var slots: Array[String] = []
		for slot in fragment_data.get("slots", []):
			slots.append(str(slot))
		return slots
	return []


func _stackable(item_data: Dictionary) -> bool:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "stacking":
			return bool(fragment_data.get("stackable", false))
	return false


func _max_stack(item_data: Dictionary) -> int:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "stacking":
			return int(fragment_data.get("max_stack", 1))
	return 1


func _has_fragment(item_data: Dictionary, kind: String) -> bool:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == kind:
			return true
	return false


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _inventory_order(value: Variant, inventory: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for item_id in _array_or_empty(value):
		var normalized_id: String = str(item_id)
		if normalized_id.is_empty() or output.has(normalized_id):
			continue
		if int(inventory.get(normalized_id, 0)) > 0:
			output.append(normalized_id)
	var remaining: Array = inventory.keys()
	remaining.sort()
	for item_id in remaining:
		var normalized_id: String = str(item_id)
		if output.has(normalized_id):
			continue
		if int(inventory.get(normalized_id, 0)) > 0:
			output.append(normalized_id)
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
