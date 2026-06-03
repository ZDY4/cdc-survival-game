extends RefCounted

const ContainerTransactions = preload("res://scripts/core/economy/container_transactions.gd")
const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const ShopTransactions = preload("res://scripts/core/economy/shop_transactions.gd")

var _container_transactions := ContainerTransactions.new()
var _inventory_entries := InventoryEntries.new()
var _shop_transactions := ShopTransactions.new()


func configure_shops(simulation: RefCounted, shops: Dictionary) -> void:
	_shop_transactions.configure_shops(simulation, shops)


func buy_item_from_shop(simulation: RefCounted, actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	return _shop_transactions.buy_item_from_shop(simulation, actor_id, shop_id, item_id, count, item_library)


func sell_item_to_shop(simulation: RefCounted, actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	return _shop_transactions.sell_item_to_shop(simulation, actor_id, shop_id, item_id, count, item_library)


func sell_equipped_item_to_shop(simulation: RefCounted, actor_id: int, shop_id: String, slot_id: String, item_id: String, item_library: Dictionary) -> Dictionary:
	return _shop_transactions.sell_equipped_item_to_shop(simulation, actor_id, shop_id, slot_id, item_id, item_library)


func confirm_trade_cart(simulation: RefCounted, actor_id: int, shop_id: String, entries: Array, item_library: Dictionary) -> Dictionary:
	return _shop_transactions.confirm_trade_cart(simulation, actor_id, shop_id, entries, item_library)


func take_item_from_container(simulation: RefCounted, actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _container_transactions.take_item_from_container(simulation, actor_id, container_id, item_id, count, item_library)


func store_item_in_container(simulation: RefCounted, actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _container_transactions.store_item_in_container(simulation, actor_id, container_id, item_id, count, item_library)


func drop_actor_item(simulation: RefCounted, actor_id: int, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	if normalized_item_id.is_empty():
		return {"success": false, "reason": "item_id_missing"}
	if not item_library.is_empty() and _dictionary_or_empty(item_library.get(normalized_item_id, {})).is_empty():
		return {"success": false, "reason": "unknown_item", "item_id": normalized_item_id}
	var drop_count: int = max(1, count)
	var available: int = int(actor.inventory.get(normalized_item_id, 0))
	if available < drop_count:
		return {
			"success": false,
			"reason": "not_enough_items",
			"item_id": normalized_item_id,
			"required": drop_count,
			"current": available,
		}

	_inventory_entries.add_actor_item(actor, normalized_item_id, -drop_count)
	var container_id: String = "drop_%s_%d_%d_%d" % [normalized_item_id, actor.grid_position.x, actor.grid_position.y, actor.grid_position.z]
	var container: Dictionary = _drop_container(simulation, container_id, actor.grid_position.to_dictionary())
	_inventory_entries.add(container["inventory"], normalized_item_id, drop_count)
	simulation.corpse_containers[container_id] = container
	simulation.container_sessions[container_id] = {
		"container_id": container_id,
		"display_name": container.get("display_name", container_id),
		"inventory": _array_or_empty(container.get("inventory", [])).duplicate(true),
	}
	simulation.map_interaction_targets[container_id] = {
		"target_id": container_id,
		"target_type": "map_object",
		"display_name": container.get("display_name", container_id),
		"kind": "container",
		"anchor": container.get("grid_position", {}),
		"cells": [container.get("grid_position", {})],
		"container_inventory": _array_or_empty(container.get("inventory", [])).duplicate(true),
	}
	simulation.emit_event("inventory_item_dropped", {
		"actor_id": actor_id,
		"container_id": container_id,
		"item_id": normalized_item_id,
		"count": drop_count,
		"grid_position": actor.grid_position.to_dictionary(),
	})
	return {
		"success": true,
		"container_id": container_id,
		"item_id": normalized_item_id,
		"count": drop_count,
	}


func _drop_container(simulation: RefCounted, container_id: String, grid_position: Dictionary) -> Dictionary:
	if simulation.corpse_containers.has(container_id):
		return _dictionary_or_empty(simulation.corpse_containers[container_id])
	return {
		"container_id": container_id,
		"map_id": simulation.active_map_id,
		"grid_position": grid_position.duplicate(true),
		"display_name": "掉落物",
		"source_actor_definition_id": "",
		"inventory": [],
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
