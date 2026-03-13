extends NPCTradeComponent
## Adapts the existing NPC trade UI for runtime 3D merchants.

var merchant_data: Dictionary = {}

func initialize_with_data(data: Dictionary) -> void:
	if data is Dictionary:
		merchant_data = data.duplicate(true)
	else:
		merchant_data = {}

func open_trade_ui() -> bool:
	if merchant_data.is_empty():
		return false
	if not _is_trade_enabled():
		return false

	if not FileAccess.file_exists("res://modules/npc/ui/npc_trade_ui.tscn"):
		push_warning("[GameWorldMerchantTradeComponent] npc_trade_ui.tscn not found")
		return false

	var ui_scene: PackedScene = load("res://modules/npc/ui/npc_trade_ui.tscn")
	if not ui_scene:
		push_error("[GameWorldMerchantTradeComponent] Failed to load NPC trade UI scene")
		return false

	trade_ui = ui_scene.instantiate()
	trade_ui.initialize(self, merchant_data)
	get_tree().current_scene.add_child(trade_ui)
	trade_opened.emit()

	await trade_ui.trade_finished

	var profit: int = trade_ui.total_profit
	trade_completed.emit(profit)

	trade_ui.queue_free()
	trade_ui = null
	trade_closed.emit()
	return true

func calculate_buy_price(item_id: String, base_price: int) -> int:
	if merchant_data.is_empty():
		return base_price

	var trade: Dictionary = _get_trade_dict()
	var mood: Dictionary = _get_mood_dict()
	var multiplier: float = float(trade.get("buy_price_modifier", 1.0))
	var player_charisma: int = _get_player_charisma()
	var charisma_bonus: float = float(player_charisma - 10) * 0.02
	var friendliness_bonus: float = float(mood.get("friendliness", 50) - 50) * 0.01
	var trust_bonus: float = float(mood.get("trust", 30) - 50) * 0.005
	var final_multiplier: float = clampf(multiplier - charisma_bonus - friendliness_bonus - trust_bonus, 0.3, 3.0)

	return int(base_price * final_multiplier)

func calculate_sell_price(item_id: String, base_price: int) -> int:
	if merchant_data.is_empty():
		return base_price

	var trade: Dictionary = _get_trade_dict()
	var mood: Dictionary = _get_mood_dict()
	var multiplier: float = float(trade.get("sell_price_modifier", 1.0))
	var player_charisma: int = _get_player_charisma()
	var charisma_bonus: float = float(player_charisma - 10) * 0.02
	var friendliness_bonus: float = float(mood.get("friendliness", 50) - 50) * 0.005
	var final_multiplier: float = clampf(multiplier + charisma_bonus + friendliness_bonus, 0.1, 2.0)

	return int(base_price * final_multiplier)

func can_buy_item(item_id: String, count: int) -> bool:
	if merchant_data.is_empty():
		return false
	if count <= 0:
		return false

	var inventory: Array = _get_inventory()
	for i in range(inventory.size()):
		var item: Dictionary = inventory[i]
		if str(item.get("id", "")) == item_id and int(item.get("count", 0)) >= count:
			return true

	return false

func buy_item(item_id: String, count: int) -> Dictionary:
	var result: Dictionary = {"success": false, "reason": ""}
	if merchant_data.is_empty():
		result.reason = "Merchant data unavailable"
		return result
	if count <= 0:
		result.reason = "Invalid count"
		return result
	if not can_buy_item(item_id, count):
		result.reason = "Merchant inventory is insufficient"
		return result

	var base_price: int = _get_item_base_price(item_id)
	var price_per_item: int = calculate_buy_price(item_id, base_price)
	var total_price: int = price_per_item * count

	if not _can_player_afford(total_price):
		result.reason = "Not enough money"
		return result

	_deduct_player_currency(total_price)
	_remove_from_merchant_inventory(item_id, count)
	if InventoryModule:
		InventoryModule.add_item(item_id, count)

	var trade: Dictionary = _get_trade_dict()
	trade["money"] = get_npc_money() + total_price
	trade["trade_count_today"] = int(trade.get("trade_count_today", 0)) + count
	var mood: Dictionary = _get_mood_dict()
	mood["friendliness"] = clampi(int(mood.get("friendliness", 50)) + 1, 0, 100)

	result.success = true
	result.price = total_price
	item_bought.emit(item_id, count, total_price)
	return result

func sell_item(item_id: String, count: int) -> Dictionary:
	var result: Dictionary = {"success": false, "reason": ""}
	if merchant_data.is_empty():
		result.reason = "Merchant data unavailable"
		return result
	if count <= 0:
		result.reason = "Invalid count"
		return result
	if InventoryModule and not InventoryModule.has_item(item_id, count):
		result.reason = "Player does not have enough items"
		return result

	var base_price: int = _get_item_base_price(item_id)
	var price_per_item: int = calculate_sell_price(item_id, base_price)
	var total_price: int = price_per_item * count

	if get_npc_money() < total_price:
		result.reason = "Merchant does not have enough money"
		return result

	set_npc_money(get_npc_money() - total_price)
	if InventoryModule:
		InventoryModule.remove_item(item_id, count)

	_add_to_merchant_inventory(item_id, count, price_per_item)
	_give_player_currency(total_price)
	var mood: Dictionary = _get_mood_dict()
	mood["friendliness"] = clampi(int(mood.get("friendliness", 50)) + 1, 0, 100)

	result.success = true
	result.price = total_price
	item_sold.emit(item_id, count, total_price)
	return result

func get_npc_inventory() -> Array:
	if merchant_data.is_empty():
		return []
	return _get_inventory().duplicate(true)

func get_npc_money() -> int:
	if merchant_data.is_empty():
		return 0
	var trade: Dictionary = _get_trade_dict()
	return int(trade.get("money", 0))

func set_npc_money(amount: int):
	if merchant_data.is_empty():
		return
	var trade: Dictionary = _get_trade_dict()
	trade["money"] = maxi(0, amount)

func _is_trade_enabled() -> bool:
	var social: Dictionary = merchant_data.get("social", {})
	var trade: Dictionary = social.get("trade", {})
	return bool(trade.get("enabled", false))

func _get_trade_dict() -> Dictionary:
	if not merchant_data.has("social"):
		merchant_data["social"] = {}
	var social: Dictionary = merchant_data["social"]
	if not social.has("trade"):
		social["trade"] = {
			"enabled": false,
			"buy_price_modifier": 1.0,
			"sell_price_modifier": 1.0,
			"money": 0,
			"inventory": []
		}
	return social["trade"]

func _get_mood_dict() -> Dictionary:
	if not merchant_data.has("social"):
		merchant_data["social"] = {}
	var social: Dictionary = merchant_data["social"]
	if not social.has("mood"):
		social["mood"] = {
			"friendliness": 50,
			"trust": 30,
			"fear": 0,
			"anger": 0
		}
	return social["mood"]

func _get_inventory() -> Array:
	var trade: Dictionary = _get_trade_dict()
	if not trade.has("inventory"):
		trade["inventory"] = []
	return trade["inventory"]

func _remove_from_merchant_inventory(item_id: String, count: int) -> void:
	var inventory: Array = _get_inventory()
	for i in range(inventory.size()):
		var item: Dictionary = inventory[i]
		if str(item.get("id", "")) != item_id:
			continue

		var remaining: int = int(item.get("count", 0)) - count
		if remaining <= 0:
			inventory.remove_at(i)
		else:
			item["count"] = remaining
			inventory[i] = item
		return

func _add_to_merchant_inventory(item_id: String, count: int, price: int) -> void:
	var inventory: Array = _get_inventory()
	for i in range(inventory.size()):
		var item: Dictionary = inventory[i]
		if str(item.get("id", "")) != item_id:
			continue

		item["count"] = int(item.get("count", 0)) + count
		item["price"] = price
		inventory[i] = item
		return

	inventory.append({
		"id": item_id,
		"count": count,
		"price": price
	})
