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
	var permission: Dictionary = _container_permission(simulation, actor_id, normalized_container_id, container, "take")
	if not bool(permission.get("success", false)):
		return permission
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


func take_money_from_container(simulation: RefCounted, actor_id: int, container_id: String, count: int = -1) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_container_id: String = str(container_id)
	var container: Dictionary = _dictionary_or_empty(simulation.container_sessions.get(normalized_container_id, {}))
	if container.is_empty():
		return {"success": false, "reason": "unknown_container", "container_id": normalized_container_id}
	var permission: Dictionary = _container_permission(simulation, actor_id, normalized_container_id, container, "take")
	if not bool(permission.get("success", false)):
		return permission
	var available: int = max(0, int(container.get("money", 0)))
	var transfer_count: int = available if count < 0 else count
	if transfer_count <= 0:
		return {
			"success": false,
			"reason": "invalid_quantity",
			"container_id": normalized_container_id,
			"item_id": "money",
			"count": count,
		}
	if available < transfer_count:
		return {
			"success": false,
			"reason": "container_money_insufficient",
			"container_id": normalized_container_id,
			"item_id": "money",
			"required": transfer_count,
			"current": available,
		}

	var actor_money_before: int = max(0, int(actor.money))
	var container_money_after: int = available - transfer_count
	actor.money = actor_money_before + transfer_count
	container["money"] = container_money_after
	simulation.container_sessions[normalized_container_id] = container
	if simulation.corpse_containers.has(normalized_container_id):
		var corpse: Dictionary = _dictionary_or_empty(simulation.corpse_containers[normalized_container_id])
		corpse["money"] = container_money_after
		simulation.corpse_containers[normalized_container_id] = corpse
	simulation.emit_event("container_money_taken", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"count": transfer_count,
		"player_money_before": actor_money_before,
		"player_money_after": actor.money,
		"container_money_before": available,
		"container_money_after": container_money_after,
	})
	simulation.emit_event("container_transferred", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": "money",
		"count": transfer_count,
		"direction": "take",
		"from": "container_money",
		"to": "actor_money",
	})
	return {
		"success": true,
		"container_id": normalized_container_id,
		"item_id": "money",
		"count": transfer_count,
		"player_money_before": actor_money_before,
		"player_money_after": actor.money,
		"container_money_before": available,
		"container_money_after": container_money_after,
	}


func store_item_in_container(simulation: RefCounted, actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_container_id: String = str(container_id)
	var container: Dictionary = _dictionary_or_empty(simulation.container_sessions.get(normalized_container_id, {}))
	if container.is_empty():
		return {"success": false, "reason": "unknown_container", "container_id": normalized_container_id}
	var permission: Dictionary = _container_permission(simulation, actor_id, normalized_container_id, container, "store")
	if not bool(permission.get("success", false)):
		return permission
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


func _container_permission(simulation: RefCounted, actor_id: int, container_id: String, container: Dictionary, action: String) -> Dictionary:
	var base := {
		"success": true,
		"actor_id": actor_id,
		"container_id": container_id,
		"action": action,
	}
	if bool(container.get("locked", false)):
		return _permission_failure(base, "container_locked", {})
	if action == "take" and not bool(container.get("allow_take", true)):
		return _permission_failure(base, "container_take_forbidden", {})
	if action == "store" and not bool(container.get("allow_store", true)):
		return _permission_failure(base, "container_store_forbidden", {})
	for flag_id in _normalized_string_array(container.get("required_world_flags", [])):
		if not _simulation_world_flags(simulation).has(flag_id):
			return _permission_failure(base, "container_world_flag_missing", {
				"flag_id": flag_id,
				"required_world_flags": _normalized_string_array(container.get("required_world_flags", [])),
			})
	for flag_id in _normalized_string_array(container.get("blocked_world_flags", [])):
		if _simulation_world_flags(simulation).has(flag_id):
			return _permission_failure(base, "container_world_flag_blocked", {
				"flag_id": flag_id,
				"blocked_world_flags": _normalized_string_array(container.get("blocked_world_flags", [])),
			})
	return base


func _permission_failure(base: Dictionary, reason: String, extra: Dictionary) -> Dictionary:
	var output: Dictionary = base.duplicate(true)
	output["success"] = false
	output["reason"] = reason
	for key in extra.keys():
		output[key] = extra[key]
	return output


func _simulation_world_flags(simulation: RefCounted) -> Dictionary:
	if simulation != null:
		return _dictionary_or_empty(simulation.get("world_flags"))
	return {}


func _normalized_string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(value) == TYPE_STRING:
		var normalized_value: String = str(value).strip_edges()
		if not normalized_value.is_empty():
			output.append(normalized_value)
		return output
	for entry in _array_or_empty(value):
		var normalized_entry: String = str(entry).strip_edges()
		if not normalized_entry.is_empty():
			output.append(normalized_entry)
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
