extends RefCounted

const ContainerTransactions = preload("res://scripts/core/economy/container_transactions.gd")
const ShopTransactions = preload("res://scripts/core/economy/shop_transactions.gd")

var _container_transactions := ContainerTransactions.new()
var _shop_transactions := ShopTransactions.new()


func configure_shops(simulation: RefCounted, shops: Dictionary) -> void:
	_shop_transactions.configure_shops(simulation, shops)


func buy_item_from_shop(simulation: RefCounted, actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	return _shop_transactions.buy_item_from_shop(simulation, actor_id, shop_id, item_id, count, item_library)


func sell_item_to_shop(simulation: RefCounted, actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	return _shop_transactions.sell_item_to_shop(simulation, actor_id, shop_id, item_id, count, item_library)


func take_item_from_container(simulation: RefCounted, actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _container_transactions.take_item_from_container(simulation, actor_id, container_id, item_id, count, item_library)


func store_item_in_container(simulation: RefCounted, actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _container_transactions.store_item_in_container(simulation, actor_id, container_id, item_id, count, item_library)
