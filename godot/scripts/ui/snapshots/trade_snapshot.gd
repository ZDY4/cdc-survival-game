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

	var shop_data: Dictionary = _shop_session_or_definition(runtime_snapshot, shop_id, shop_record)
	var player: Dictionary = _player_actor(runtime_snapshot)
	return {
		"active": true,
		"shop_id": shop_id,
		"target_actor_id": int(session.get("target_actor_id", 0)),
		"target_name": str(session.get("target_name", "")),
		"player_money": int(player.get("money", 0)),
		"money": int(shop_data.get("money", 0)),
		"buy_price_modifier": float(shop_data.get("buy_price_modifier", 1.0)),
		"sell_price_modifier": float(shop_data.get("sell_price_modifier", 1.0)),
		"items": _shop_items(shop_data.get("inventory", []), float(shop_data.get("buy_price_modifier", 1.0))),
		"player_items": _inventory_items(_dictionary_or_empty(player.get("inventory", {})), float(shop_data.get("sell_price_modifier", 1.0))),
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


func _shop_items(entries: Array, buy_price_modifier: float) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var item_id: String = _normalize_content_id(entry_data.get("item_id", ""))
		var item_data: Dictionary = _item_data(item_id)
		var base_price: int = int(entry_data.get("price", item_data.get("value", 0)))
		var price: int = _trade_price(base_price, buy_price_modifier)
		items.append({
			"item_id": item_id,
			"name": str(item_data.get("name", item_id)),
			"description": str(item_data.get("description", "")),
			"count": int(entry_data.get("count", 0)),
			"price": price,
			"base_price": base_price,
			"rarity": _rarity(item_data),
		})

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("price", 0)) > int(b.get("price", 0))
	)
	return items


func _inventory_items(inventory: Dictionary, sell_price_modifier: float) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for item_id in inventory.keys():
		var normalized_item_id := _normalize_content_id(item_id)
		var count := int(inventory[item_id])
		if normalized_item_id.is_empty() or count <= 0:
			continue
		var item_data: Dictionary = _item_data(normalized_item_id)
		var base_price := int(item_data.get("value", 0))
		items.append({
			"item_id": normalized_item_id,
			"name": str(item_data.get("name", normalized_item_id)),
			"description": str(item_data.get("description", "")),
			"count": count,
			"price": _trade_price(base_price, sell_price_modifier),
			"base_price": base_price,
			"rarity": _rarity(item_data),
		})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
	)
	return items


func _shop_session_or_definition(runtime_snapshot: Dictionary, shop_id: String, shop_record: Dictionary) -> Dictionary:
	for session in runtime_snapshot.get("shop_sessions", []):
		var session_data: Dictionary = _dictionary_or_empty(session)
		if str(session_data.get("shop_id", "")) == shop_id:
			return session_data
	return _dictionary_or_empty(shop_record.get("data", {}))


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


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


func _trade_price(base_price: int, modifier: float) -> int:
	return max(1, int(round(float(max(0, base_price)) * max(0.0, modifier))))


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
