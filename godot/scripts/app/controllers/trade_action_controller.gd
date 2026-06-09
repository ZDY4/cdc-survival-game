extends RefCounted


func buy_item(shop_id: String, item_id: String, count: int, stack_index: int, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if shop_id.is_empty():
		return _missing_trade("buy_shop", "", item_id, count, record_feedback)
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "buy_shop",
		"shop_id": shop_id,
		"item_id": item_id,
		"count": count,
		"stack_index": stack_index,
	})
	_record(record_feedback, result, "buy_shop", shop_id, item_id, count)
	return _operation_result(result, ["inventory", "trade"])


func sell_item(shop_id: String, item_id: String, count: int, stack_index: int, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if shop_id.is_empty():
		return _missing_trade("sell_shop", "", item_id, count, record_feedback)
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "sell_shop",
		"shop_id": shop_id,
		"item_id": item_id,
		"count": count,
		"stack_index": stack_index,
	})
	_record(record_feedback, result, "sell_shop", shop_id, item_id, count)
	return _operation_result(result, ["inventory", "trade"])


func sell_equipment(shop_id: String, slot_id: String, item_id: String, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	if shop_id.is_empty():
		return _missing_trade("sell_equipped_shop", "", item_id, 1, record_feedback)
	var result: Dictionary = _submit(submit_inventory_action, {
		"action": "sell_equipped_shop",
		"shop_id": shop_id,
		"slot_id": slot_id,
		"item_id": item_id,
		"count": 1,
	})
	_record(record_feedback, result, "sell_equipped_shop", shop_id, item_id, 1)
	if bool(result.get("success", false)):
		return _operation_result(result, [], true)
	return _operation_result(result, ["inventory", "trade"])


func transfer_item(source: String, shop_id: String, item_id: String, count: int, stack_index: int, submit_inventory_action: Callable, record_feedback: Callable) -> Dictionary:
	match source:
		"shop":
			return buy_item(shop_id, item_id, count, stack_index, submit_inventory_action, record_feedback)
		"player":
			return sell_item(shop_id, item_id, count, stack_index, submit_inventory_action, record_feedback)
	if source.begins_with("equipment:"):
		return sell_equipment(shop_id, source.trim_prefix("equipment:"), item_id, submit_inventory_action, record_feedback)
	return _operation_result({"success": false, "reason": "unknown_trade_transfer_source", "source": source}, [])


func confirm_cart(entries: Array, shop_id: String, confirm_trade_cart: Callable, record_feedback: Callable) -> Dictionary:
	if entries.is_empty():
		return _operation_result({"success": false, "reason": "empty_trade_cart"}, [])
	if shop_id.is_empty():
		return _missing_trade("trade_cart", "", "", 0, record_feedback)
	if not confirm_trade_cart.is_valid():
		var missing_result := {"success": false, "reason": "confirm_trade_cart_missing"}
		_record(record_feedback, missing_result, "trade_cart", shop_id, "", 0)
		return _operation_result(missing_result, ["trade"])
	var result: Dictionary = dictionary_or_empty(confirm_trade_cart.call(shop_id, entries))
	_record(record_feedback, result, "trade_cart", shop_id, str(result.get("item_id", "")), int(result.get("count", 0)))
	return _operation_result(result, ["inventory", "trade"])


func _missing_trade(action: String, shop_id: String, item_id: String, count: int, record_feedback: Callable) -> Dictionary:
	var result := {"success": false, "reason": "active_trade_missing"}
	_record(record_feedback, result, action, shop_id, item_id, count)
	return _operation_result(result, [])


func _submit(submit_inventory_action: Callable, action: Dictionary) -> Dictionary:
	if not submit_inventory_action.is_valid():
		return {"success": false, "reason": "submit_inventory_action_missing"}
	return dictionary_or_empty(submit_inventory_action.call(action))


func _record(record_feedback: Callable, result: Dictionary, action: String, shop_id: String, item_id: String, count: int) -> void:
	if record_feedback.is_valid():
		record_feedback.call(result, action, shop_id, item_id, count)


func _operation_result(result: Dictionary, refresh_panels: Array, rebuild_world: bool = false) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh": refresh_panels.duplicate(true),
		"rebuild_world": rebuild_world,
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
