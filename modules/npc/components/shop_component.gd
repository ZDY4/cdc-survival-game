extends Node
## Scene-bound shop that can be explicitly bound to a runtime actor.

class_name ShopComponent

const ShopDefinitionResource = preload("res://modules/npc/components/shop_definition.gd")
const TRADE_UI_SCENE_PATH := "res://modules/npc/ui/npc_trade_ui.tscn"

signal trade_opened
signal trade_closed
signal item_bought(item_id: String, count: int, price: int)
signal item_sold(item_id: String, count: int, price: int)
signal trade_completed(profit: int)

@export var shop_definition: ShopDefinitionResource

var _bound_actor: Node = null
var _shop_state: Dictionary = {}
var trade_ui: Control = null

func _ready() -> void:
	_reset_shop_state()

func bind_actor(actor: Node) -> void:
	if actor == _bound_actor:
		return

	unbind_actor()
	if actor == null or not is_instance_valid(actor):
		return

	_bound_actor = actor
	_bound_actor.set_meta("bound_trade_component", self)

func unbind_actor() -> void:
	if _bound_actor != null and is_instance_valid(_bound_actor):
		if _bound_actor.get_meta("bound_trade_component", null) == self:
			_bound_actor.remove_meta("bound_trade_component")
	_bound_actor = null

func is_trade_available() -> bool:
	if _bound_actor == null or not is_instance_valid(_bound_actor):
		return false
	return bool(_get_relation_result().get("allow_trade", false))

func initialize_with_data(data: Dictionary) -> void:
	if data.is_empty():
		return

	# Compatibility shim for any remaining legacy callers.
	_shop_state = {
		"buy_price_modifier": float(data.get("buy_price_modifier", 1.0)),
		"sell_price_modifier": float(data.get("sell_price_modifier", 1.0)),
		"money": int(data.get("money", 0)),
		"inventory": data.get("inventory", []).duplicate(true)
	}

func open_trade_ui() -> bool:
	if not is_trade_available():
		return false

	if not FileAccess.file_exists(TRADE_UI_SCENE_PATH):
		push_warning("[ShopComponent] npc_trade_ui.tscn not found")
		return false

	var ui_scene: PackedScene = load(TRADE_UI_SCENE_PATH)
	if not ui_scene:
		push_error("[ShopComponent] Failed to load NPC trade UI scene")
		return false

	trade_ui = ui_scene.instantiate()
	trade_ui.initialize(self, _get_character_data())
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	host.add_child(trade_ui)
	trade_opened.emit()

	await trade_ui.trade_finished

	var profit: int = trade_ui.total_profit
	trade_completed.emit(profit)

	trade_ui.queue_free()
	trade_ui = null
	trade_closed.emit()
	return true

func calculate_buy_price(_item_id: String, base_price: int) -> int:
	var trade: Dictionary = _get_trade_dict()
	var mood: Dictionary = _get_mood_dict()
	var multiplier: float = float(trade.get("buy_price_modifier", 1.0))
	var player_charisma: int = _get_player_charisma()
	var charisma_bonus: float = float(player_charisma - 10) * 0.02
	var friendliness_bonus: float = float(mood.get("friendliness", 50) - 50) * 0.01
	var trust_bonus: float = float(mood.get("trust", 30) - 50) * 0.005
	var final_multiplier: float = clampf(multiplier - charisma_bonus - friendliness_bonus - trust_bonus, 0.3, 3.0)
	return int(base_price * final_multiplier)

func calculate_sell_price(_item_id: String, base_price: int) -> int:
	var trade: Dictionary = _get_trade_dict()
	var mood: Dictionary = _get_mood_dict()
	var multiplier: float = float(trade.get("sell_price_modifier", 1.0))
	var player_charisma: int = _get_player_charisma()
	var charisma_bonus: float = float(player_charisma - 10) * 0.02
	var friendliness_bonus: float = float(mood.get("friendliness", 50) - 50) * 0.005
	var final_multiplier: float = clampf(multiplier + charisma_bonus + friendliness_bonus, 0.1, 2.0)
	return int(base_price * final_multiplier)

func can_buy_item(item_id: String, count: int) -> bool:
	if count <= 0:
		return false

	var inventory: Array = _get_inventory()
	for item_variant in inventory:
		if not (item_variant is Dictionary):
			continue
		var item: Dictionary = item_variant
		if str(item.get("id", "")) == item_id and int(item.get("count", 0)) >= count:
			return true

	return false

func buy_item(item_id: String, count: int) -> Dictionary:
	var result: Dictionary = {"success": false, "reason": ""}
	if not is_trade_available():
		result.reason = "Trade is unavailable"
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
	_remove_from_inventory(item_id, count)
	if InventoryModule:
		InventoryModule.add_item(item_id, count)

	var trade: Dictionary = _get_trade_dict()
	trade["money"] = get_npc_money() + total_price
	_increase_friendliness()

	result["success"] = true
	result["price"] = total_price
	item_bought.emit(item_id, count, total_price)
	return result

func sell_item(item_id: String, count: int) -> Dictionary:
	var result: Dictionary = {"success": false, "reason": ""}
	if not is_trade_available():
		result.reason = "Trade is unavailable"
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

	_add_to_inventory(item_id, count, price_per_item)
	_give_player_currency(total_price)
	_increase_friendliness()

	result["success"] = true
	result["price"] = total_price
	item_sold.emit(item_id, count, total_price)
	return result

func get_npc_inventory() -> Array:
	return _get_inventory().duplicate(true)

func get_npc_money() -> int:
	return int(_get_trade_dict().get("money", 0))

func set_npc_money(amount: int) -> void:
	_get_trade_dict()["money"] = maxi(0, amount)

func restock() -> void:
	if shop_definition == null:
		return
	_reset_shop_state()

func _reset_shop_state() -> void:
	if shop_definition == null:
		_shop_state = _build_default_shop_state()
		return

	_shop_state = {
		"buy_price_modifier": shop_definition.buy_price_modifier,
		"sell_price_modifier": shop_definition.sell_price_modifier,
		"money": shop_definition.money,
		"inventory": shop_definition.inventory.duplicate(true)
	}

func _build_default_shop_state() -> Dictionary:
	return {
		"buy_price_modifier": 1.0,
		"sell_price_modifier": 1.0,
		"money": 0,
		"inventory": []
	}

func _get_trade_dict() -> Dictionary:
	if _shop_state.is_empty():
		_reset_shop_state()
	return _shop_state

func _get_inventory() -> Array:
	var trade: Dictionary = _get_trade_dict()
	if not trade.has("inventory"):
		trade["inventory"] = []
	return trade["inventory"]

func _get_relation_result() -> Dictionary:
	if _bound_actor == null or not is_instance_valid(_bound_actor):
		return {}
	var relation_variant: Variant = _bound_actor.get_meta("relation_result", {})
	if relation_variant is Dictionary:
		return relation_variant as Dictionary
	return {}

func _get_character_data() -> Dictionary:
	if _bound_actor == null or not is_instance_valid(_bound_actor):
		return {}
	var data_variant: Variant = _bound_actor.get_meta("character_data", {})
	if data_variant is Dictionary:
		return (data_variant as Dictionary).duplicate(true)
	return {}

func _get_mood_dict() -> Dictionary:
	var character_data: Dictionary = _get_character_data()
	var social: Dictionary = character_data.get("social", {})
	var mood: Dictionary = social.get("mood", {})
	if mood.is_empty():
		return {
			"friendliness": 50,
			"trust": 30,
			"fear": 0,
			"anger": 0
		}
	return mood

func _remove_from_inventory(item_id: String, count: int) -> void:
	var inventory: Array = _get_inventory()
	for i in range(inventory.size()):
		var item_variant: Variant = inventory[i]
		if not (item_variant is Dictionary):
			continue
		var item: Dictionary = item_variant
		if str(item.get("id", "")) != item_id:
			continue

		var remaining: int = int(item.get("count", 0)) - count
		if remaining <= 0:
			inventory.remove_at(i)
		else:
			item["count"] = remaining
			inventory[i] = item
		return

func _add_to_inventory(item_id: String, count: int, price: int) -> void:
	var inventory: Array = _get_inventory()
	for i in range(inventory.size()):
		var item_variant: Variant = inventory[i]
		if not (item_variant is Dictionary):
			continue
		var item: Dictionary = item_variant
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

func _increase_friendliness() -> void:
	if _bound_actor == null or not is_instance_valid(_bound_actor):
		return
	var character_data: Dictionary = _get_character_data()
	if character_data.is_empty():
		return

	var social: Dictionary = character_data.get("social", {})
	var mood: Dictionary = social.get("mood", {})
	if mood.is_empty():
		return

	mood["friendliness"] = clampi(int(mood.get("friendliness", 50)) + 1, 0, 100)
	social["mood"] = mood
	character_data["social"] = social
	_bound_actor.set_meta("character_data", character_data)

func _get_player_charisma() -> int:
	if GameState and GameState.has("player_charisma"):
		return GameState.player_charisma
	return 10

func _get_item_base_price(item_id: String) -> int:
	var data_manager: Node = get_node_or_null("/root/DataManager")
	if data_manager != null and data_manager.has_method("get_item_data"):
		var item_data_variant: Variant = data_manager.get_item_data(item_id)
		if item_data_variant is Dictionary:
			return int((item_data_variant as Dictionary).get("value", 10))
	return 10

func _can_player_afford(amount: int) -> bool:
	if GameState:
		return GameState.has_money(amount)
	return false

func _deduct_player_currency(amount: int) -> bool:
	if GameState:
		return GameState.remove_money(amount)
	return false

func _give_player_currency(amount: int) -> bool:
	if GameState:
		return GameState.add_money(amount)
	return false
