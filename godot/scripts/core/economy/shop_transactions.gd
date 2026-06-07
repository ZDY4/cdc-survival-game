extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const InventoryCapacity = preload("res://scripts/core/economy/inventory_capacity.gd")

var _inventory_entries := InventoryEntries.new()
var _inventory_capacity := InventoryCapacity.new()


func configure_shops(simulation: RefCounted, shops: Dictionary) -> void:
	for shop_id in shops.keys():
		var record: Dictionary = _dictionary_or_empty(shops[shop_id])
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var normalized_id: String = str(data.get("id", shop_id))
		if normalized_id.is_empty():
			normalized_id = str(shop_id)
		var session := {
			"shop_id": normalized_id,
			"money": max(0, int(data.get("money", 0))),
			"buy_price_modifier": max(0.0, float(data.get("buy_price_modifier", 1.0))),
			"sell_price_modifier": max(0.0, float(data.get("sell_price_modifier", 1.0))),
			"inventory": _inventory_entries.normalize(data.get("inventory", [])),
		}
		_copy_permission_fields(session, data)
		simulation.shop_sessions[normalized_id] = session


func buy_item_from_shop(simulation: RefCounted, actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary, stack_index: int = 0) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var shop: Dictionary = _dictionary_or_empty(simulation.shop_sessions.get(shop_id, {}))
	if shop.is_empty():
		return {"success": false, "reason": "unknown_shop"}
	var permission: Dictionary = _trade_permission(simulation, actor_id, shop_id, shop)
	if not bool(permission.get("success", false)):
		return permission
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var buy_count: int = max(1, count)
	var available: int = _inventory_entries.count(_array_or_empty(shop.get("inventory", [])), normalized_item_id)
	var selected_stack_index: int = max(0, stack_index)
	if selected_stack_index > 0:
		available = _inventory_entries.stack_count_at(_array_or_empty(shop.get("inventory", [])), normalized_item_id, selected_stack_index)
	if available < buy_count:
		return {
			"success": false,
			"reason": "shop_stock_insufficient",
			"item_id": normalized_item_id,
			"count": buy_count,
			"available": available,
			"stack_index": selected_stack_index,
		}
	var unit_price: int = _trade_unit_price(normalized_item_id, float(shop.get("buy_price_modifier", 1.0)), item_library)
	var total_price: int = unit_price * buy_count
	if actor.money < total_price:
		return {"success": false, "reason": "player_money_insufficient", "unit_price": unit_price, "total_price": total_price}
	var capacity: Dictionary = _inventory_capacity.can_add_items(actor, item_library, [
		{"item_id": normalized_item_id, "count": buy_count},
	])
	if not bool(capacity.get("success", false)):
		capacity["shop_id"] = shop_id
		capacity["unit_price"] = unit_price
		capacity["total_price"] = total_price
		return capacity

	actor.money -= total_price
	_inventory_entries.add_actor_item(actor, normalized_item_id, buy_count)
	_inventory_entries.remove_from_stack(shop["inventory"], normalized_item_id, buy_count, selected_stack_index)
	shop["money"] = int(shop.get("money", 0)) + total_price
	simulation.shop_sessions[shop_id] = shop
	simulation.emit_event("trade_bought", {
		"actor_id": actor_id,
		"shop_id": shop_id,
		"item_id": normalized_item_id,
		"count": buy_count,
		"stack_index": selected_stack_index,
		"unit_price": unit_price,
		"total_price": total_price,
	})
	simulation.emit_event("trade_confirmed", {
		"actor_id": actor_id,
		"shop_id": shop_id,
		"mode": "buy",
		"item_id": normalized_item_id,
		"count": buy_count,
		"stack_index": selected_stack_index,
		"unit_price": unit_price,
		"total_price": total_price,
		"player_money_after": actor.money,
		"shop_money_after": int(shop.get("money", 0)),
	})
	return {
		"success": true,
		"shop_id": shop_id,
		"item_id": normalized_item_id,
		"count": buy_count,
		"stack_index": selected_stack_index,
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
	var permission: Dictionary = _trade_permission(simulation, actor_id, shop_id, shop)
	if not bool(permission.get("success", false)):
		return permission
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var sell_count: int = max(1, count)
	if int(actor.inventory.get(normalized_item_id, 0)) < sell_count:
		return {"success": false, "reason": "player_stock_insufficient"}
	if not _is_item_sellable(normalized_item_id, item_library):
		return {"success": false, "reason": "item_not_sellable", "item_id": normalized_item_id, "count": sell_count}
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
	simulation.emit_event("trade_confirmed", {
		"actor_id": actor_id,
		"shop_id": shop_id,
		"mode": "sell",
		"item_id": normalized_item_id,
		"count": sell_count,
		"unit_price": unit_price,
		"total_price": total_price,
		"player_money_after": actor.money,
		"shop_money_after": int(shop.get("money", 0)),
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


func sell_equipped_item_to_shop(simulation: RefCounted, actor_id: int, shop_id: String, slot_id: String, item_id: String, item_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var shop: Dictionary = _dictionary_or_empty(simulation.shop_sessions.get(shop_id, {}))
	if shop.is_empty():
		return {"success": false, "reason": "unknown_shop"}
	var permission: Dictionary = _trade_permission(simulation, actor_id, shop_id, shop)
	if not bool(permission.get("success", false)):
		return permission
	var normalized_slot_id: String = slot_id.strip_edges()
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var equipped_item_id: String = _inventory_entries.normalize_content_id(actor.equipment.get(normalized_slot_id, ""))
	if normalized_slot_id.is_empty():
		return {"success": false, "reason": "equipment_slot_missing"}
	if equipped_item_id.is_empty():
		return {"success": false, "reason": "empty_equipment_slot", "slot_id": normalized_slot_id}
	if not normalized_item_id.is_empty() and normalized_item_id != equipped_item_id:
		return {
			"success": false,
			"reason": "equipment_item_mismatch",
			"slot_id": normalized_slot_id,
			"item_id": normalized_item_id,
			"equipped_item_id": equipped_item_id,
		}
	if not _is_item_sellable(equipped_item_id, item_library):
		return {
			"success": false,
			"reason": "item_not_sellable",
			"slot_id": normalized_slot_id,
			"item_id": equipped_item_id,
			"count": 1,
		}
	var unit_price: int = _trade_unit_price(equipped_item_id, float(shop.get("sell_price_modifier", 1.0)), item_library)
	var total_price: int = unit_price
	if int(shop.get("money", 0)) < total_price:
		return {
			"success": false,
			"reason": "shop_money_insufficient",
			"slot_id": normalized_slot_id,
			"item_id": equipped_item_id,
			"count": 1,
			"unit_price": unit_price,
			"total_price": total_price,
		}

	actor.equipment.erase(normalized_slot_id)
	actor.money += total_price
	_inventory_entries.add(shop["inventory"], equipped_item_id, 1)
	shop["money"] = int(shop.get("money", 0)) - total_price
	simulation.shop_sessions[shop_id] = shop
	simulation.emit_event("trade_equipped_item_sold", {
		"actor_id": actor_id,
		"shop_id": shop_id,
		"slot_id": normalized_slot_id,
		"item_id": equipped_item_id,
		"count": 1,
		"unit_price": unit_price,
		"total_price": total_price,
	})
	simulation.emit_event("trade_confirmed", {
		"actor_id": actor_id,
		"shop_id": shop_id,
		"mode": "sell_equipped",
		"slot_id": normalized_slot_id,
		"item_id": equipped_item_id,
		"count": 1,
		"unit_price": unit_price,
		"total_price": total_price,
		"player_money_after": actor.money,
		"shop_money_after": int(shop.get("money", 0)),
	})
	return {
		"success": true,
		"shop_id": shop_id,
		"slot_id": normalized_slot_id,
		"item_id": equipped_item_id,
		"count": 1,
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
				_inventory_entries.remove_from_stack(shop["inventory"], item_id, count, int(entry.get("stack_index", 0)))
			"player":
				_inventory_entries.add_actor_item(actor, item_id, -count)
				_inventory_entries.add(shop["inventory"], item_id, count)
			_:
				var slot_id: String = _equipment_slot_from_source(str(entry.get("source", "")))
				if not slot_id.is_empty():
					actor.equipment.erase(slot_id)
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
	simulation.emit_event("trade_confirmed", {
		"actor_id": actor_id,
		"shop_id": shop_id,
		"mode": "cart",
		"entries": normalized_entries.duplicate(true),
		"entry_count": normalized_entries.size(),
		"buy_total": int(quote.get("buy_total", 0)),
		"sell_total": int(quote.get("sell_total", 0)),
		"net_payment": int(quote.get("net_payment", 0)),
		"player_money_before": int(quote.get("player_money_before", actor.money)),
		"player_money_after": actor.money,
		"shop_money_before": int(quote.get("shop_money_before", shop.get("money", 0))),
		"shop_money_after": int(shop.get("money", 0)),
	})
	return quote


func quote_trade_cart(simulation: RefCounted, actor_id: int, shop_id: String, entries: Array, item_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var shop: Dictionary = _dictionary_or_empty(simulation.shop_sessions.get(shop_id, {}))
	if shop.is_empty():
		return {"success": false, "reason": "unknown_shop"}
	var permission: Dictionary = _trade_permission(simulation, actor_id, shop_id, shop)
	if not bool(permission.get("success", false)):
		return permission
	var normalized_entries: Array[Dictionary] = []
	var buy_counts: Dictionary = {}
	var buy_stack_counts: Dictionary = {}
	var sell_counts: Dictionary = {}
	var equipment_sell_counts: Dictionary = {}
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
				var stack_index: int = max(0, int(entry.get("stack_index", 0)))
				buy_total += buy_unit_price * count
				if stack_index > 0:
					var stack_key := "%s#%d" % [item_id, stack_index]
					buy_stack_counts[stack_key] = int(buy_stack_counts.get(stack_key, 0)) + count
				else:
					buy_counts[item_id] = int(buy_counts.get(item_id, 0)) + count
				var normalized_entry := {
					"source": source,
					"item_id": item_id,
					"count": count,
					"unit_price": buy_unit_price,
					"total_price": buy_unit_price * count,
				}
				if stack_index > 0:
					normalized_entry["stack_index"] = stack_index
				normalized_entries.append(normalized_entry)
			"player":
				if not _is_item_sellable(item_id, item_library):
					return {"success": false, "reason": "item_not_sellable", "item_id": item_id, "count": count, "failed_index": index}
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
				var slot_id: String = _equipment_slot_from_source(source)
				if slot_id.is_empty():
					return {"success": false, "reason": "unknown_trade_transfer_source", "source": source, "failed_index": index}
				if not _is_item_sellable(item_id, item_library):
					return {"success": false, "reason": "item_not_sellable", "item_id": item_id, "slot_id": slot_id, "count": count, "failed_index": index}
				var equipped_sell_unit_price: int = _trade_unit_price(item_id, float(shop.get("sell_price_modifier", 1.0)), item_library)
				sell_total += equipped_sell_unit_price * count
				equipment_sell_counts[slot_id] = int(equipment_sell_counts.get(slot_id, 0)) + count
				normalized_entries.append({
					"source": source,
					"slot_id": slot_id,
					"item_id": item_id,
					"count": count,
					"unit_price": equipped_sell_unit_price,
					"total_price": equipped_sell_unit_price * count,
				})
	if normalized_entries.is_empty():
		return {"success": false, "reason": "empty_trade_cart"}
	for item_id in buy_counts.keys():
		var required: int = int(buy_counts[item_id])
		var available: int = _inventory_entries.count(_array_or_empty(shop.get("inventory", [])), str(item_id))
		if available < required:
			return {"success": false, "reason": "shop_stock_insufficient", "item_id": str(item_id), "count": required, "available": available}
	for stack_key in buy_stack_counts.keys():
		var key_parts: PackedStringArray = str(stack_key).split("#", false, 1)
		var item_id: String = key_parts[0] if key_parts.size() > 0 else ""
		var stack_index: int = int(key_parts[1]) if key_parts.size() > 1 else 0
		var required: int = int(buy_stack_counts[stack_key])
		var available: int = _inventory_entries.stack_count_at(_array_or_empty(shop.get("inventory", [])), item_id, stack_index)
		if available < required:
			return {"success": false, "reason": "shop_stock_insufficient", "item_id": item_id, "count": required, "available": available, "stack_index": stack_index}
	for item_id in sell_counts.keys():
		var required: int = int(sell_counts[item_id])
		var available: int = int(actor.inventory.get(str(item_id), 0))
		if available < required:
			return {"success": false, "reason": "player_stock_insufficient", "item_id": str(item_id), "count": required, "available": available}
	for slot_id in equipment_sell_counts.keys():
		var required: int = int(equipment_sell_counts[slot_id])
		var equipped_item_id: String = _inventory_entries.normalize_content_id(actor.equipment.get(str(slot_id), ""))
		if equipped_item_id.is_empty():
			return {"success": false, "reason": "empty_equipment_slot", "slot_id": str(slot_id), "count": required, "available": 0}
		if required > 1:
			return {"success": false, "reason": "equipment_stock_insufficient", "slot_id": str(slot_id), "count": required, "available": 1}
		for entry in normalized_entries:
			var entry_data: Dictionary = entry
			if str(entry_data.get("slot_id", "")) == str(slot_id) and str(entry_data.get("item_id", "")) != equipped_item_id:
				return {
					"success": false,
					"reason": "equipment_item_mismatch",
					"slot_id": str(slot_id),
					"item_id": str(entry_data.get("item_id", "")),
					"equipped_item_id": equipped_item_id,
				}
	var net_payment: int = buy_total - sell_total
	if net_payment > actor.money:
		return {"success": false, "reason": "player_money_insufficient", "total_price": net_payment}
	if net_payment < 0 and int(shop.get("money", 0)) < -net_payment:
		return {"success": false, "reason": "shop_money_insufficient", "total_price": -net_payment}
	var capacity: Dictionary = _inventory_capacity.can_add_items(actor, item_library, _entries_for_source(normalized_entries, "shop"), _entries_for_source(normalized_entries, "player"))
	if not bool(capacity.get("success", false)):
		capacity["shop_id"] = shop_id
		capacity["total_price"] = net_payment
		capacity["entries"] = normalized_entries.duplicate(true)
		return capacity
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


func _entries_for_source(entries: Array[Dictionary], source: String) -> Array:
	var output: Array = []
	for entry in entries:
		var entry_data: Dictionary = entry
		if str(entry_data.get("source", "")) != source:
			continue
		output.append({
			"item_id": str(entry_data.get("item_id", "")),
			"count": int(entry_data.get("count", 0)),
		})
	return output


func _copy_permission_fields(session: Dictionary, data: Dictionary) -> void:
	for key in [
		"target_actor_id",
		"target_actor_definition_id",
		"required_relationship_min",
		"required_relationship_max",
		"required_world_flags",
		"blocked_world_flags",
	]:
		if data.has(key):
			session[key] = data.get(key)
	var camel_case_aliases := {
		"targetActorId": "target_actor_id",
		"targetActorDefinitionId": "target_actor_definition_id",
		"requiredRelationshipMin": "required_relationship_min",
		"requiredRelationshipMax": "required_relationship_max",
		"requiredWorldFlags": "required_world_flags",
		"blockedWorldFlags": "blocked_world_flags",
	}
	for source_key in camel_case_aliases.keys():
		if data.has(source_key):
			session[str(camel_case_aliases[source_key])] = data.get(source_key)


func _trade_permission(simulation: RefCounted, actor_id: int, shop_id: String, shop: Dictionary) -> Dictionary:
	var target_actor_id: int = _trade_target_actor_id(simulation, shop_id, shop)
	var result := {
		"success": true,
		"shop_id": shop_id,
		"target_actor_id": target_actor_id,
	}
	for flag_id in _normalized_string_array(shop.get("required_world_flags", [])):
		if not _simulation_world_flags(simulation).has(flag_id):
			return _trade_permission_failure(result, "trade_world_flag_missing", {
				"flag_id": flag_id,
				"required_world_flags": _normalized_string_array(shop.get("required_world_flags", [])),
			})
	for flag_id in _normalized_string_array(shop.get("blocked_world_flags", [])):
		if _simulation_world_flags(simulation).has(flag_id):
			return _trade_permission_failure(result, "trade_world_flag_blocked", {
				"flag_id": flag_id,
				"blocked_world_flags": _normalized_string_array(shop.get("blocked_world_flags", [])),
			})
	if target_actor_id > 0 and (shop.has("required_relationship_min") or shop.has("required_relationship_max")):
		var score: float = _relationship_score(simulation, actor_id, target_actor_id)
		result["relationship_score"] = score
		if shop.has("required_relationship_min"):
			var min_score: float = float(shop.get("required_relationship_min", -100.0))
			if score < min_score:
				return _trade_permission_failure(result, "trade_relationship_too_low", {
					"relationship_score": score,
					"required_relationship_min": min_score,
				})
		if shop.has("required_relationship_max"):
			var max_score: float = float(shop.get("required_relationship_max", 100.0))
			if score > max_score:
				return _trade_permission_failure(result, "trade_relationship_too_high", {
					"relationship_score": score,
					"required_relationship_max": max_score,
				})
	return result


func _trade_permission_failure(base: Dictionary, reason: String, extra: Dictionary) -> Dictionary:
	var output: Dictionary = base.duplicate(true)
	output["success"] = false
	output["reason"] = reason
	for key in extra.keys():
		output[key] = extra[key]
	return output


func _trade_target_actor_id(simulation: RefCounted, shop_id: String, shop: Dictionary) -> int:
	var explicit_id: int = int(shop.get("target_actor_id", 0))
	if explicit_id > 0:
		return explicit_id
	var definition_id: String = str(shop.get("target_actor_definition_id", "")).strip_edges()
	if definition_id.is_empty() and shop_id.ends_with("_shop"):
		definition_id = shop_id.trim_suffix("_shop")
	if definition_id.is_empty() or simulation == null or simulation.actor_registry == null:
		return 0
	for actor in simulation.actor_registry.actors():
		if actor != null and str(actor.definition_id) == definition_id:
			return int(actor.actor_id)
	return 0


func _relationship_score(simulation: RefCounted, actor_id: int, target_actor_id: int) -> float:
	if simulation != null and simulation.has_method("relationship_score"):
		return float(simulation.relationship_score(actor_id, target_actor_id))
	return 0.0


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


func _is_item_sellable(item_id: String, item_library: Dictionary) -> bool:
	var record: Dictionary = _dictionary_or_empty(item_library.get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	if data.is_empty():
		return true
	for key in ["sellable", "can_sell", "tradeable"]:
		if data.has(key) and not bool(data.get(key)):
			return false
	for fragment in _array_or_empty(data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		var kind: String = str(fragment_data.get("kind", ""))
		if kind in ["quest", "task", "key_item"]:
			return false
		for key in ["sellable", "can_sell", "tradeable"]:
			if fragment_data.has(key) and not bool(fragment_data.get(key)):
				return false
	return true


func _equipment_slot_from_source(source: String) -> String:
	if source.begins_with("equipment:"):
		return source.trim_prefix("equipment:").strip_edges()
	return ""


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
