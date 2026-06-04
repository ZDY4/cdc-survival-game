extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

var _inventory_entries := InventoryEntries.new()


func take_item_from_container(simulation: RefCounted, actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_container_id: String = str(container_id)
	var container: Dictionary = _dictionary_or_empty(simulation.container_sessions.get(normalized_container_id, {}))
	if container.is_empty():
		return {"success": false, "reason": "unknown_container", "container_id": normalized_container_id}
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	if not item_library.is_empty() and _dictionary_or_empty(item_library.get(normalized_item_id, {})).is_empty():
		return {"success": false, "reason": "unknown_item", "item_id": normalized_item_id}
	if count <= 0:
		return {
			"success": false,
			"reason": "invalid_quantity",
			"container_id": normalized_container_id,
			"item_id": normalized_item_id,
			"count": count,
		}
	var transfer_count: int = count
	var available: int = _inventory_entries.count(_array_or_empty(container.get("inventory", [])), normalized_item_id)
	if available < transfer_count:
		return {
			"success": false,
			"reason": "container_inventory_insufficient",
			"container_id": normalized_container_id,
			"item_id": normalized_item_id,
			"required": transfer_count,
			"current": available,
		}

	_inventory_entries.add(container["inventory"], normalized_item_id, -transfer_count)
	_inventory_entries.add_actor_item(actor, normalized_item_id, transfer_count)
	simulation.container_sessions[normalized_container_id] = container
	simulation.emit_event("container_item_taken", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
	})
	simulation.emit_event("container_transferred", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
		"direction": "take",
		"from": "container",
		"to": "actor_inventory",
	})
	simulation.record_item_collected(actor_id, normalized_item_id, transfer_count)
	return {
		"success": true,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
	}


func store_item_in_container(simulation: RefCounted, actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_container_id: String = str(container_id)
	var container: Dictionary = _dictionary_or_empty(simulation.container_sessions.get(normalized_container_id, {}))
	if container.is_empty():
		return {"success": false, "reason": "unknown_container", "container_id": normalized_container_id}
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	if not item_library.is_empty() and _dictionary_or_empty(item_library.get(normalized_item_id, {})).is_empty():
		return {"success": false, "reason": "unknown_item", "item_id": normalized_item_id}
	if count <= 0:
		return {
			"success": false,
			"reason": "invalid_quantity",
			"container_id": normalized_container_id,
			"item_id": normalized_item_id,
			"count": count,
		}
	var transfer_count: int = count
	var available: int = int(actor.inventory.get(normalized_item_id, 0))
	if available < transfer_count:
		return {
			"success": false,
			"reason": "not_enough_items",
			"item_id": normalized_item_id,
			"required": transfer_count,
			"current": available,
		}

	_inventory_entries.add_actor_item(actor, normalized_item_id, -transfer_count)
	_inventory_entries.add(container["inventory"], normalized_item_id, transfer_count)
	simulation.container_sessions[normalized_container_id] = container
	simulation.emit_event("container_item_stored", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
	})
	simulation.emit_event("container_transferred", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
		"direction": "store",
		"from": "actor_inventory",
		"to": "container",
	})
	return {
		"success": true,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
