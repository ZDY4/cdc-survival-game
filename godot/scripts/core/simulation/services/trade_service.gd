extends RefCounted

const ShopTransactions = preload("res://scripts/core/economy/shop_transactions.gd")

var _shop_transactions := ShopTransactions.new()


func configure_shops(simulation: RefCounted, shops: Dictionary) -> void:
	_shop_transactions.configure_shops(simulation, shops)


func buy_item(simulation: RefCounted, actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary, stack_index: int = 0) -> Dictionary:
	return _shop_transactions.buy_item_from_shop(simulation, actor_id, shop_id, item_id, count, item_library, stack_index)


func sell_item(simulation: RefCounted, actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary, stack_index: int = 0) -> Dictionary:
	return _shop_transactions.sell_item_to_shop(simulation, actor_id, shop_id, item_id, count, item_library, stack_index)


func sell_equipped_item(simulation: RefCounted, actor_id: int, shop_id: String, slot_id: String, item_id: String, item_library: Dictionary) -> Dictionary:
	return _shop_transactions.sell_equipped_item_to_shop(simulation, actor_id, shop_id, slot_id, item_id, item_library)


func confirm_cart(simulation: RefCounted, actor_id: int, shop_id: String, entries: Array, item_library: Dictionary) -> Dictionary:
	return _shop_transactions.confirm_trade_cart(simulation, actor_id, shop_id, entries, item_library)
