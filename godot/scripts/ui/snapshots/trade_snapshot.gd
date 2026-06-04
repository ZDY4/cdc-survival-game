extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, target: Dictionary = {}, feedback: Dictionary = {}) -> Dictionary:
	if target.is_empty():
		return {"active": false}
	var session: Dictionary = resolve_trade_session(runtime_snapshot, target)
	if session.is_empty():
		return {"active": false}

	var shop_id: String = str(session.get("shop_id", ""))
	var shop_record: Dictionary = registry.get_library("shops").get(shop_id, {})
	if shop_record.is_empty():
		return {
			"active": true,
			"shop_id": shop_id,
			"error": "unknown_shop",
		}

	var shop_data: Dictionary = _shop_session_or_definition(runtime_snapshot, shop_id, shop_record)
	var player: Dictionary = _player_actor(runtime_snapshot)
	var snapshot := {
		"active": true,
		"shop_id": shop_id,
		"target_actor_id": int(session.get("target_actor_id", 0)),
		"target_name": str(session.get("target_name", "")),
		"player_money": int(player.get("money", 0)),
		"money": int(shop_data.get("money", 0)),
		"buy_price_modifier": float(shop_data.get("buy_price_modifier", 1.0)),
		"sell_price_modifier": float(shop_data.get("sell_price_modifier", 1.0)),
		"items": _shop_items(shop_data.get("inventory", []), float(shop_data.get("buy_price_modifier", 1.0))),
		"player_items": _player_trade_items(player, float(shop_data.get("sell_price_modifier", 1.0))),
	}
	var scoped_feedback := _feedback_snapshot(feedback, shop_id)
	if not scoped_feedback.is_empty():
		snapshot["feedback"] = scoped_feedback
	return snapshot


func resolve_trade_session(runtime_snapshot: Dictionary, target: Dictionary = {}) -> Dictionary:
	var shops: Dictionary = registry.get_library("shops")
	if shops.is_empty():
		return {}

	var explicit_shop_id := str(target.get("shop_id", target.get("shopId", ""))).strip_edges()
	if str(target.get("target_type", "")) == "shop" and not explicit_shop_id.is_empty():
		return {
			"shop_id": explicit_shop_id,
			"target_actor_id": 0,
			"target_name": str(target.get("target_name", "")),
		}

	var target_actor_id: int = int(target.get("actor_id", 0))
	if str(target.get("target_type", "")) == "actor" and target_actor_id > 0:
		var actor: Dictionary = _actor_by_id(runtime_snapshot, target_actor_id)
		if not actor.is_empty():
			var candidate: String = "%s_shop" % actor.get("definition_id", "")
			if shops.has(candidate):
				return {
					"shop_id": candidate,
					"target_actor_id": target_actor_id,
					"target_name": actor.get("display_name", ""),
				}

	var shop_ids: Array = shops.keys()
	shop_ids.sort()
	return {
		"shop_id": str(shop_ids[0]),
		"target_actor_id": 0,
		"target_name": "",
	}


func _shop_items(entries: Array, buy_price_modifier: float) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var item_id: String = _normalize_content_id(entry_data.get("item_id", ""))
		var item_data: Dictionary = _item_data(item_id)
		var base_price: int = int(item_data.get("value", 0))
		var price: int = _trade_price(base_price, buy_price_modifier)
		items.append({
			"item_id": item_id,
			"name": str(item_data.get("name", item_id)),
			"description": str(item_data.get("description", "")),
			"count": int(entry_data.get("count", 0)),
			"price": price,
			"base_price": base_price,
			"rarity": _rarity(item_data),
		})

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("price", 0)) > int(b.get("price", 0))
	)
	return items


func _inventory_items(inventory: Dictionary, sell_price_modifier: float) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for item_id in inventory.keys():
		var normalized_item_id := _normalize_content_id(item_id)
		var count := int(inventory[item_id])
		if normalized_item_id.is_empty() or count <= 0:
			continue
		var item_data: Dictionary = _item_data(normalized_item_id)
		var base_price := int(item_data.get("value", 0))
		var sellable: bool = _is_item_sellable(item_data)
		items.append({
			"item_id": normalized_item_id,
			"name": str(item_data.get("name", normalized_item_id)),
			"description": str(item_data.get("description", "")),
			"count": count,
			"price": _trade_price(base_price, sell_price_modifier),
			"base_price": base_price,
			"rarity": _rarity(item_data),
			"sellable": sellable,
			"disabled_reason": "" if sellable else "不可出售",
		})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
	)
	return items


func _player_trade_items(player: Dictionary, sell_price_modifier: float) -> Array[Dictionary]:
	var items: Array[Dictionary] = _inventory_items(_dictionary_or_empty(player.get("inventory", {})), sell_price_modifier)
	for slot_id in _dictionary_or_empty(player.get("equipment", {})).keys():
		var normalized_slot_id: String = str(slot_id).strip_edges()
		var normalized_item_id: String = _normalize_content_id(_dictionary_or_empty(player.get("equipment", {})).get(slot_id, ""))
		if normalized_slot_id.is_empty() or normalized_item_id.is_empty():
			continue
		var item_data: Dictionary = _item_data(normalized_item_id)
		var base_price: int = int(item_data.get("value", 0))
		var sellable: bool = _is_item_sellable(item_data)
		items.append({
			"source": "equipment:%s" % normalized_slot_id,
			"slot_id": normalized_slot_id,
			"item_id": normalized_item_id,
			"name": "%s %s" % [_equipment_slot_label(normalized_slot_id), str(item_data.get("name", normalized_item_id))],
			"description": str(item_data.get("description", "")),
			"count": 1,
			"price": _trade_price(base_price, sell_price_modifier),
			"base_price": base_price,
			"rarity": _rarity(item_data),
			"equipped": true,
			"sellable": sellable,
			"disabled_reason": "" if sellable else "不可出售",
		})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_equipped: bool = bool(a.get("equipped", false))
		var b_equipped: bool = bool(b.get("equipped", false))
		if a_equipped != b_equipped:
			return a_equipped
		return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
	)
	return items


func _shop_session_or_definition(runtime_snapshot: Dictionary, shop_id: String, shop_record: Dictionary) -> Dictionary:
	for session in runtime_snapshot.get("shop_sessions", []):
		var session_data: Dictionary = _dictionary_or_empty(session)
		if str(session_data.get("shop_id", "")) == shop_id:
			return session_data
	return _dictionary_or_empty(shop_record.get("data", {}))


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _item_data(item_id: String) -> Dictionary:
	var record: Dictionary = registry.get_library("items").get(item_id, {})
	return _dictionary_or_empty(record.get("data", {}))


func _actor_by_id(runtime_snapshot: Dictionary, actor_id: int) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return actor_data
	return {}


func _rarity(item_data: Dictionary) -> String:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "economy":
			return str(fragment_data.get("rarity", ""))
	return ""


func _is_item_sellable(item_data: Dictionary) -> bool:
	if item_data.is_empty():
		return true
	for key in ["sellable", "can_sell", "tradeable"]:
		if item_data.has(key) and not bool(item_data.get(key)):
			return false
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		var kind: String = str(fragment_data.get("kind", ""))
		if kind in ["quest", "task", "key_item"]:
			return false
		for key in ["sellable", "can_sell", "tradeable"]:
			if fragment_data.has(key) and not bool(fragment_data.get(key)):
				return false
	return true


func _trade_price(base_price: int, modifier: float) -> int:
	return max(1, int(round(float(max(0, base_price)) * max(0.0, modifier))))


func _feedback_snapshot(feedback: Dictionary, shop_id: String) -> Dictionary:
	if feedback.is_empty():
		return {}
	if not str(feedback.get("shop_id", shop_id)).is_empty() and str(feedback.get("shop_id", shop_id)) != shop_id:
		return {}
	var reason := str(feedback.get("reason", ""))
	var text := _feedback_text(feedback)
	if reason.is_empty() and text.is_empty():
		return {}
	return {
		"type": str(feedback.get("type", "error")),
		"reason": reason,
		"text": text,
	}


func _feedback_text(feedback: Dictionary) -> String:
	var item_name: String = _feedback_item_name(feedback)
	var count: int = int(feedback.get("count", 1))
	var action: String = str(feedback.get("action", ""))
	match str(feedback.get("reason", "")):
		"player_money_insufficient":
			if action == "trade_cart":
				return "玩家资金不足，购物车需要支付 %d。" % int(feedback.get("total_price", 0))
			return "玩家资金不足，购买 %s x%d 需要 %d。" % [item_name, count, int(feedback.get("total_price", 0))]
		"shop_money_insufficient":
			if action == "trade_cart":
				return "店铺资金不足，购物车需要支付 %d。" % int(feedback.get("total_price", 0))
			return "店铺资金不足，收购 %s x%d 需要 %d。" % [item_name, count, int(feedback.get("total_price", 0))]
		"shop_stock_insufficient":
			return "店铺库存不足：%s x%d。" % [item_name, count]
		"player_stock_insufficient":
			return "背包库存不足：%s x%d。" % [item_name, count]
		"item_not_sellable":
			return "该物品不可出售：%s。" % item_name
		"unknown_shop":
			return "店铺不存在或已经失效。"
		"unknown_actor":
			return "当前角色不可用，无法交易。"
		"active_trade_missing":
			return "没有打开的交易。"
		"trade_relationship_too_low":
			return "关系不足，当前商人拒绝交易。"
		"trade_relationship_too_high":
			return "关系条件不符，当前商人拒绝交易。"
		"trade_world_flag_missing":
			return "缺少交易许可，当前商店暂不可用。"
		"trade_world_flag_blocked":
			return "交易许可已失效，当前商店暂不可用。"
		_:
			return str(feedback.get("reason", ""))


func _feedback_item_name(feedback: Dictionary) -> String:
	var item_id := _normalize_content_id(feedback.get("item_id", ""))
	if item_id.is_empty():
		return "物品"
	var item_data := _item_data(item_id)
	return str(item_data.get("name", item_id))


func _equipment_slot_label(slot_id: String) -> String:
	match slot_id:
		"main_hand":
			return "主手"
		"off_hand":
			return "副手"
		"head":
			return "头部"
		"body":
			return "身体"
		"legs":
			return "腿部"
		"feet":
			return "脚部"
		"hands":
			return "手部"
		"back":
			return "背部"
		"accessory", "accessory_1", "accessory_2":
			return "饰品"
		_:
			return slot_id


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _normalize_content_id(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		var float_value: float = value
		if is_equal_approx(float_value, roundf(float_value)):
			return str(int(float_value))
	if typeof(value) == TYPE_INT:
		return str(value)
	return str(value)
