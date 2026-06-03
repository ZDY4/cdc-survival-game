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


func confirm_trade_cart(simulation: RefCounted, actor_id: int, shop_id: String, entries: Array, item_library: Dictionary) -> Dictionary:
	var quote := quote_trade_cart(simulation, actor_id, shop_id, entries, item_library)
	if not bool(quote.get("success", false)):
		return quote
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var shop: Dictionary = _dictionary_or_empty(simulation.shop_sessions.get(shop_id, {}))
	var normalized_entries: Array[Dictionary] = quote.get("entries", [])
	for entry in normalized_entries:
		var item_id := str(entry.get("item_id", ""))
		var count := int(entry.get("count", 0))
		match str(entry.get("source", "")):
			"shop":
				_inventory_entries.add_actor_item(actor, item_id, count)
				_inventory_entries.add(shop["inventory"], item_id, -count)
			"player":
				_inventory_entries.add_actor_item(actor, item_id, -count)
				_inventory_entries.add(shop["inventory"], item_id, count)
	actor.money = int(quote.get("player_money_after", actor.money))
	shop["money"] = int(quote.get("shop_money_after", shop.get("money", 0)))
	simulation.shop_sessions[shop_id] = shop
	simulation.emit_event("trade_cart_confirmed", {
		"actor_id": actor_id,
		"shop_id": shop_id,
		"entry_count": normalized_entries.size(),
		"buy_total": int(quote.get("buy_total", 0)),
		"sell_total": int(quote.get("sell_total", 0)),
		"net_payment": int(quote.get("net_payment", 0)),
	})
	return quote


func quote_trade_cart(simulation: RefCounted, actor_id: int, shop_id: String, entries: Array, item_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var shop: Dictionary = _dictionary_or_empty(simulation.shop_sessions.get(shop_id, {}))
	if shop.is_empty():
		return {"success": false, "reason": "unknown_shop"}
	var normalized_entries: Array[Dictionary] = []
	var buy_counts: Dictionary = {}
	var sell_counts: Dictionary = {}
	var buy_total: int = 0
	var sell_total: int = 0
	for index in range(entries.size()):
		var entry: Dictionary = _dictionary_or_empty(entries[index])
		var source: String = str(entry.get("source", ""))
		var item_id: String = _inventory_entries.normalize_content_id(entry.get("item_id", ""))
		var count: int = max(1, int(entry.get("count", 1)))
		if item_id.is_empty():
			return {"success": false, "reason": "item_id_missing", "failed_index": index}
		match source:
			"shop":
				var buy_unit_price: int = _trade_unit_price(item_id, float(shop.get("buy_price_modifier", 1.0)), item_library)
				buy_total += buy_unit_price * count
				buy_counts[item_id] = int(buy_counts.get(item_id, 0)) + count
				normalized_entries.append({
					"source": source,
					"item_id": item_id,
					"count": count,
					"unit_price": buy_unit_price,
					"total_price": buy_unit_price * count,
				})
			"player":
				var sell_unit_price: int = _trade_unit_price(item_id, float(shop.get("sell_price_modifier", 1.0)), item_library)
				sell_total += sell_unit_price * count
				sell_counts[item_id] = int(sell_counts.get(item_id, 0)) + count
				normalized_entries.append({
					"source": source,
					"item_id": item_id,
					"count": count,
					"unit_price": sell_unit_price,
					"total_price": sell_unit_price * count,
				})
			_:
				return {"success": false, "reason": "unknown_trade_transfer_source", "source": source, "failed_index": index}
	if normalized_entries.is_empty():
		return {"success": false, "reason": "empty_trade_cart"}
	for item_id in buy_counts.keys():
		var required: int = int(buy_counts[item_id])
		var available: int = _inventory_entries.count(_array_or_empty(shop.get("inventory", [])), str(item_id))
		if available < required:
			return {"success": false, "reason": "shop_stock_insufficient", "item_id": str(item_id), "count": required, "available": available}
	for item_id in sell_counts.keys():
		var required: int = int(sell_counts[item_id])
		var available: int = int(actor.inventory.get(str(item_id), 0))
		if available < required:
			return {"success": false, "reason": "player_stock_insufficient", "item_id": str(item_id), "count": required, "available": available}
	var net_payment: int = buy_total - sell_total
	if net_payment > actor.money:
		return {"success": false, "reason": "player_money_insufficient", "total_price": net_payment}
	if net_payment < 0 and int(shop.get("money", 0)) < -net_payment:
		return {"success": false, "reason": "shop_money_insufficient", "total_price": -net_payment}
	return {
		"success": true,
		"shop_id": shop_id,
		"entries": normalized_entries,
		"buy_total": buy_total,
		"sell_total": sell_total,
		"net_payment": net_payment,
		"player_money_before": actor.money,
		"player_money_after": actor.money - net_payment,
		"shop_money_before": int(shop.get("money", 0)),
		"shop_money_after": int(shop.get("money", 0)) + net_payment,
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
