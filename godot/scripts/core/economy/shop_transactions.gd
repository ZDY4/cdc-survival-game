extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

var _inventory_entries := InventoryEntries.new()


func configure_shops(simulation: RefCounted, shops: Dictionary) -> void:
	for shop_id in shops.keys():
		var record: Dictionary = _dictionary_or_empty(shops[shop_id])
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var normalized_id: String = str(data.get("id", shop_id))
		if normalized_id.is_empty():
			normalized_id = str(shop_id)
		simulation.shop_sessions[normalized_id] = {
			"shop_id": normalized_id,
			"money": max(0, int(data.get("money", 0))),
			"buy_price_modifier": max(0.0, float(data.get("buy_price_modifier", 1.0))),
			"sell_price_modifier": max(0.0, float(data.get("sell_price_modifier", 1.0))),
			"inventory": _inventory_entries.normalize(data.get("inventory", [])),
		}


func buy_item_from_shop(simulation: RefCounted, actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var shop: Dictionary = _dictionary_or_empty(simulation.shop_sessions.get(shop_id, {}))
	if shop.is_empty():
		return {"success": false, "reason": "unknown_shop"}
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var buy_count: int = max(1, count)
	var available: int = _inventory_entries.count(_array_or_empty(shop.get("inventory", [])), normalized_item_id)
	if available < buy_count:
		return {"success": false, "reason": "shop_stock_insufficient"}
	var unit_price: int = _trade_unit_price(normalized_item_id, float(shop.get("buy_price_modifier", 1.0)), item_library)
	var total_price: int = unit_price * buy_count
	if actor.money < total_price:
		return {"success": false, "reason": "player_money_insufficient", "unit_price": unit_price, "total_price": total_price}

	actor.money -= total_price
	_inventory_entries.add_actor_item(actor, normalized_item_id, buy_count)
	_inventory_entries.add(shop["inventory"], normalized_item_id, -buy_count)
	shop["money"] = int(shop.get("money", 0)) + total_price
	simulation.shop_sessions[shop_id] = shop
	simulation.emit_event("trade_bought", {
		"actor_id": actor_id,
		"shop_id": shop_id,
		"item_id": normalized_item_id,
		"count": buy_count,
		"unit_price": unit_price,
		"total_price": total_price,
	})
	return {
		"success": true,
		"shop_id": shop_id,
		"item_id": normalized_item_id,
		"count": buy_count,
		"unit_price": unit_price,
		"total_price": total_price,
		"shop_money": shop.get("money", 0),
	}


func sell_item_to_shop(simulation: RefCounted, actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var shop: Dictionary = _dictionary_or_empty(simulation.shop_sessions.get(shop_id, {}))
	if shop.is_empty():
		return {"success": false, "reason": "unknown_shop"}
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var sell_count: int = max(1, count)
	if int(actor.inventory.get(normalized_item_id, 0)) < sell_count:
		return {"success": false, "reason": "player_stock_insufficient"}
	var unit_price: int = _trade_unit_price(normalized_item_id, float(shop.get("sell_price_modifier", 1.0)), item_library)
	var total_price: int = unit_price * sell_count
	if int(shop.get("money", 0)) < total_price:
		return {"success": false, "reason": "shop_money_insufficient", "unit_price": unit_price, "total_price": total_price}

	_inventory_entries.add_actor_item(actor, normalized_item_id, -sell_count)
	actor.money += total_price
	_inventory_entries.add(shop["inventory"], normalized_item_id, sell_count)
	shop["money"] = int(shop.get("money", 0)) - total_price
	simulation.shop_sessions[shop_id] = shop
	simulation.emit_event("trade_sold", {
		"actor_id": actor_id,
		"shop_id": shop_id,
		"item_id": normalized_item_id,
		"count": sell_count,
		"unit_price": unit_price,
		"total_price": total_price,
	})
	return {
		"success": true,
		"shop_id": shop_id,
		"item_id": normalized_item_id,
		"count": sell_count,
		"unit_price": unit_price,
		"total_price": total_price,
		"shop_money": shop.get("money", 0),
	}


func _trade_unit_price(item_id: String, modifier: float, item_library: Dictionary) -> int:
	var record: Dictionary = _dictionary_or_empty(item_library.get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	var base_value: int = max(0, int(data.get("value", 0)))
	return max(1, int(round(float(base_value) * max(0.0, modifier))))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
