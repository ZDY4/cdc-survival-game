extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, target: Dictionary = {}) -> Dictionary:
	if target.is_empty():
		return {"active": false}
	var session: Dictionary = resolve_trade_session(runtime_snapshot, target)
	if session.is_empty():
		return {"active": false}

	var shop_id: String = str(session.get("shop_id", ""))
	var shop_record: Dictionary = registry.get_library("shops").get(shop_id, {})
	if shop_record.is_empty():
		return {
			"active": true,
			"shop_id": shop_id,
			"error": "unknown_shop",
		}

	var shop_data: Dictionary = shop_record.get("data", {})
	return {
		"active": true,
		"shop_id": shop_id,
		"target_actor_id": int(session.get("target_actor_id", 0)),
		"target_name": str(session.get("target_name", "")),
		"money": int(shop_data.get("money", 0)),
		"buy_price_modifier": float(shop_data.get("buy_price_modifier", 1.0)),
		"sell_price_modifier": float(shop_data.get("sell_price_modifier", 1.0)),
		"items": _shop_items(shop_data.get("inventory", [])),
	}


func resolve_trade_session(runtime_snapshot: Dictionary, target: Dictionary = {}) -> Dictionary:
	var shops: Dictionary = registry.get_library("shops")
	if shops.is_empty():
		return {}

	var target_actor_id: int = int(target.get("actor_id", 0))
	if str(target.get("target_type", "")) == "actor" and target_actor_id > 0:
		var actor: Dictionary = _actor_by_id(runtime_snapshot, target_actor_id)
		if not actor.is_empty():
			var candidate: String = "%s_shop" % actor.get("definition_id", "")
			if shops.has(candidate):
				return {
					"shop_id": candidate,
					"target_actor_id": target_actor_id,
					"target_name": actor.get("display_name", ""),
				}

	var shop_ids: Array = shops.keys()
	shop_ids.sort()
	return {
		"shop_id": str(shop_ids[0]),
		"target_actor_id": 0,
		"target_name": "",
	}


func _shop_items(entries: Array) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var item_id: String = _normalize_content_id(entry_data.get("item_id", ""))
		var item_data: Dictionary = _item_data(item_id)
		var price: int = int(entry_data.get("price", item_data.get("value", 0)))
		items.append({
			"item_id": item_id,
			"name": str(item_data.get("name", item_id)),
			"description": str(item_data.get("description", "")),
			"count": int(entry_data.get("count", 0)),
			"price": price,
			"rarity": _rarity(item_data),
		})

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("price", 0)) > int(b.get("price", 0))
	)
	return items


func _item_data(item_id: String) -> Dictionary:
	var record: Dictionary = registry.get_library("items").get(item_id, {})
	return _dictionary_or_empty(record.get("data", {}))


func _actor_by_id(runtime_snapshot: Dictionary, actor_id: int) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return actor_data
	return {}


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
