extends RefCounted

const InventoryCapacity = preload("res://scripts/core/economy/inventory_capacity.gd")
const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")

var registry: RefCounted
var _inventory_capacity := InventoryCapacity.new()


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, feedback: Dictionary = {}) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	var inventory_order: Array[String] = _inventory_order(player.get("inventory_order", []), inventory)
	var items: Array[Dictionary] = []
	var total_weight := 0.0
	for order_index in range(inventory_order.size()):
		var item_id: String = inventory_order[order_index]
		var count: int = int(inventory.get(item_id, 0))
		if count <= 0:
			continue
		var item_snapshot: Dictionary = _item_snapshot(str(item_id), count)
		item_snapshot["order_index"] = order_index
		total_weight += float(item_snapshot.get("total_weight", 0.0))
		items.append(item_snapshot)
	var capacity: Dictionary = _inventory_capacity.capacity_snapshot(player, registry.get_library("items"))
	return {
		"owner_actor_id": int(player.get("actor_id", 0)),
		"owner_name": str(player.get("display_name", "")),
		"items": items,
		"inventory_order": inventory_order,
		"item_count": items.size(),
		"total_weight": total_weight,
		"max_weight": float(capacity.get("max_weight", 0.0)),
		"remaining_weight": float(capacity.get("remaining_weight", 0.0)),
		"over_capacity": bool(capacity.get("over_capacity", false)),
		"feedback": _feedback_snapshot(feedback),
	}


func _item_snapshot(item_id: String, count: int) -> Dictionary:
	var record: Dictionary = registry.get_library("items").get(item_id, {})
	if record.is_empty():
		return {
			"item_id": item_id,
			"name": item_id,
			"description": "",
			"count": count,
			"unit_weight": 0.0,
			"total_weight": 0.0,
			"value": 0,
			"total_value": 0,
			"rarity": "",
			"category": "misc",
			"category_label": _category_label("misc"),
			"icon_path": "",
			"icon_asset": AssetPathResolver.resolve_media_asset("", "item"),
			"thumbnail_asset": _thumbnail_asset(AssetPathResolver.resolve_media_asset("", "item"), "item"),
			"equip_slots": [],
			"usable": false,
			"use_ap_cost": 0.0,
			"use_effect_ids": [],
			"droppable": true,
			"deconstructable": false,
			"deconstruct_yield": [],
			"deconstruct_preview": {},
			"stackable": false,
			"max_stack": 1,
		}

	var data: Dictionary = record.get("data", {})
	var unit_weight: float = float(data.get("weight", 0.0))
	var value: int = int(data.get("value", 0))
	var category: String = _category(data)
	var icon_path := str(data.get("icon_path", ""))
	var icon_asset := AssetPathResolver.resolve_media_asset(icon_path, _icon_fallback_key(category))
	var usable: Dictionary = _fragment_by_kind(data, "usable")
	var use_allowed: bool = not usable.is_empty() and _is_item_use_allowed(data)
	var crafting_fragment: Dictionary = _fragment_by_kind(data, "crafting")
	var deconstruct_yield: Array[Dictionary] = _deconstruct_yield(data)
	return {
		"item_id": item_id,
		"name": str(data.get("name", item_id)),
		"description": str(data.get("description", "")),
		"count": count,
		"unit_weight": unit_weight,
		"total_weight": unit_weight * float(count),
		"value": value,
		"total_value": value * count,
		"rarity": _rarity(data),
		"category": category,
		"category_label": _category_label(category),
		"icon_path": icon_path,
		"icon_asset": icon_asset,
		"thumbnail_asset": _thumbnail_asset(icon_asset, "item"),
		"equip_slots": _equip_slots(data),
		"usable": use_allowed,
		"use_ap_cost": max(1.0, ceil(float(usable.get("use_time", 1.0)))) if not usable.is_empty() else 0.0,
		"use_effect_ids": _string_array(usable.get("effect_ids", [])) if not usable.is_empty() else [],
		"droppable": _is_item_droppable(data),
		"deconstructable": not deconstruct_yield.is_empty(),
		"deconstruct_yield": deconstruct_yield,
		"deconstruct_preview": _deconstruct_preview(deconstruct_yield, count),
		"deconstruct_requirements": _deconstruct_requirements(crafting_fragment),
		"stackable": _stackable(data),
		"max_stack": _max_stack(data),
	}


func _rarity(item_data: Dictionary) -> String:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "economy":
			return str(fragment_data.get("rarity", ""))
	return ""


func _category(item_data: Dictionary) -> String:
	if _has_fragment(item_data, "weapon") or _has_fragment(item_data, "equip"):
		return "equipment"
	if _has_fragment(item_data, "usable"):
		return "consumable"
	if str(item_data.get("icon_path", "")).contains("/ammo/") or str(item_data.get("name", "")).contains("弹药"):
		return "ammo"
	if _has_fragment(item_data, "crafting"):
		return "material"
	return "misc"


func _category_label(category: String) -> String:
	match category:
		"equipment":
			return "装备"
		"consumable":
			return "消耗"
		"ammo":
			return "弹药"
		"material":
			return "材料"
		_:
			return "杂项"


func _icon_fallback_key(category: String) -> String:
	match category:
		"equipment":
			return "equipment"
		"consumable":
			return "item"
		"ammo":
			return "ammo"
		"material":
			return "material"
		_:
			return "item"


func _thumbnail_asset(icon_asset: Dictionary, domain: String) -> Dictionary:
	var thumbnail := icon_asset.duplicate(true)
	thumbnail["thumbnail"] = true
	thumbnail["thumbnail_domain"] = domain
	thumbnail["source"] = "icon_asset"
	return thumbnail


func _equip_slots(item_data: Dictionary) -> Array[String]:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") != "equip":
			continue
		var slots: Array[String] = []
		for slot in fragment_data.get("slots", []):
			slots.append(str(slot))
		return slots
	return []


func _stackable(item_data: Dictionary) -> bool:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "stacking":
			return bool(fragment_data.get("stackable", false))
	return false


func _max_stack(item_data: Dictionary) -> int:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "stacking":
			return int(fragment_data.get("max_stack", 1))
	return 1


func _deconstruct_yield(item_data: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) != "crafting":
			continue
		for entry in _array_or_empty(fragment_data.get("deconstruct_yield", [])):
			var entry_data: Dictionary = _dictionary_or_empty(entry)
			var item_id := str(entry_data.get("item_id", ""))
			var count := int(entry_data.get("count", 0))
			if item_id.is_empty() or count <= 0:
				continue
			output.append({
				"item_id": item_id,
				"count": count,
			})
		return output
	return output


func _deconstruct_preview(deconstruct_yield: Array[Dictionary], source_count: int) -> Dictionary:
	if deconstruct_yield.is_empty():
		return {}
	var entries: Array[Dictionary] = []
	var total_weight := 0.0
	var preview_count: int = max(1, source_count)
	for entry in deconstruct_yield:
		var item_id := str(entry.get("item_id", ""))
		var count_per_item: int = int(entry.get("count", 0))
		if item_id.is_empty() or count_per_item <= 0:
			continue
		var total_count: int = count_per_item * preview_count
		var item_data: Dictionary = _item_data(item_id)
		var unit_weight := float(item_data.get("weight", 0.0))
		total_weight += unit_weight * float(total_count)
		entries.append({
			"item_id": item_id,
			"name": str(item_data.get("name", item_id)),
			"count_per_item": count_per_item,
			"total_count": total_count,
			"unit_weight": unit_weight,
			"total_weight": unit_weight * float(total_count),
		})
	return {
		"source_count": preview_count,
		"entries": entries,
		"total_weight": total_weight,
	}


func _deconstruct_requirements(crafting_fragment: Dictionary) -> Dictionary:
	if crafting_fragment.is_empty():
		return {}
	return {
		"required_tools": _normalized_item_ids(crafting_fragment.get("deconstruct_required_tools", crafting_fragment.get("required_deconstruct_tools", crafting_fragment.get("deconstruct_required_tool_ids", crafting_fragment.get("required_deconstruct_tool_ids", []))))),
		"required_station": str(crafting_fragment.get("deconstruct_required_station", crafting_fragment.get("required_deconstruct_station", "none"))),
	}


func _normalized_item_ids(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_normalized_item_id(output, entry)
	else:
		_append_normalized_item_id(output, value)
	return output


func _append_normalized_item_id(output: Array[String], value: Variant) -> void:
	var raw_value: Variant = value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = _dictionary_or_empty(value)
		raw_value = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var normalized_id := str(raw_value).strip_edges()
	if normalized_id.is_empty() or output.has(normalized_id):
		return
	output.append(normalized_id)


func _has_fragment(item_data: Dictionary, kind: String) -> bool:
	return not _fragment_by_kind(item_data, kind).is_empty()


func _item_data(item_id: String) -> Dictionary:
	var record: Dictionary = registry.get_library("items").get(item_id, {})
	return _dictionary_or_empty(record.get("data", record))


func _fragment_by_kind(item_data: Dictionary, kind: String) -> Dictionary:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == kind:
			return fragment_data
	return {}


func _is_item_use_allowed(item_data: Dictionary) -> bool:
	for key in ["usable", "can_use"]:
		if item_data.has(key) and not bool(item_data.get(key)):
			return false
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		var kind: String = str(fragment_data.get("kind", ""))
		if kind in ["quest", "task", "key_item"]:
			return false
		for key in ["usable", "can_use"]:
			if fragment_data.has(key) and not bool(fragment_data.get(key)):
				return false
	return true


func _is_item_droppable(item_data: Dictionary) -> bool:
	for key in ["droppable", "can_drop", "discardable"]:
		if item_data.has(key) and not bool(item_data.get(key)):
			return false
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		var kind: String = str(fragment_data.get("kind", ""))
		if kind in ["quest", "task", "key_item"]:
			return false
		for key in ["droppable", "can_drop", "discardable"]:
			if fragment_data.has(key) and not bool(fragment_data.get(key)):
				return false
	return true


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _feedback_snapshot(feedback: Dictionary) -> Dictionary:
	if feedback.is_empty():
		return {}
	var reason := str(feedback.get("reason", ""))
	var text := _feedback_text(feedback)
	if reason.is_empty() and text.is_empty():
		return {}
	return {
		"type": str(feedback.get("type", "success" if bool(feedback.get("success", false)) else "error")),
		"action": str(feedback.get("action", "")),
		"reason": reason,
		"item_id": str(feedback.get("item_id", "")),
		"text": text,
	}


func _feedback_text(feedback: Dictionary) -> String:
	var explicit_text := str(feedback.get("text", ""))
	if not explicit_text.is_empty():
		return explicit_text
	var item_name := _feedback_item_name(feedback)
	var action := str(feedback.get("action", ""))
	var count := maxi(1, int(feedback.get("count", 1)))
	if bool(feedback.get("success", false)):
		match action:
			"use_item":
				return _use_item_success_text(item_name, feedback)
			"drop":
				return "已丢弃 %s x%d。" % [item_name, int(feedback.get("dropped_count", count))]
			"deconstruct":
				return "已拆解 %s x%d。" % [item_name, count]
			"reorder_inventory":
				return "已调整 %s 的背包顺序。" % item_name
			_:
				return "背包操作完成：%s。" % item_name
	match str(feedback.get("reason", "")):
		"ap_insufficient_use_item":
			return "AP 不足，使用 %s 需要 %.0f，当前 %.0f。" % [item_name, float(feedback.get("required_ap", 0.0)), float(feedback.get("available_ap", 0.0))]
		"ap_insufficient_deconstruct":
			return "AP 不足，拆解 %s 需要 %.0f，当前 %.0f。" % [item_name, float(feedback.get("required_ap", 0.0)), float(feedback.get("available_ap", 0.0))]
		"missing_tools":
			return "缺少拆解工具，无法拆解 %s。" % item_name
		"missing_station":
			return "缺少拆解工作台 %s，无法拆解 %s。" % [
				str(feedback.get("required_station", "")),
				item_name,
			]
		"not_enough_items":
			return "背包中没有足够的 %s，需要 %d，当前 %d。" % [item_name, int(feedback.get("required", count)), int(feedback.get("current", 0))]
		"inventory_over_capacity":
			return "背包负重不足，加入 %s x%d 后为 %.1f/%.1f kg，超出 %.1f kg。" % [
				item_name,
				count,
				float(feedback.get("projected_weight", 0.0)),
				float(feedback.get("max_weight", 0.0)),
				float(feedback.get("over_by", 0.0)),
			]
		"item_not_usable":
			return "%s 不能使用。" % item_name
		"item_use_forbidden":
			return "%s 当前禁止使用。" % item_name
		"unknown_item":
			return "物品数据不可用：%s。" % str(feedback.get("item_id", ""))
		"unknown_effect":
			return "物品效果不可用：%s。" % str(feedback.get("effect_id", ""))
		"inventory_split_requires_stack_model":
			return "当前背包按物品合并计数，%s 暂不能拆分。" % item_name
		"invalid_quantity":
			return "数量无效，请输入大于 0 的数量。"
		"item_not_in_inventory":
			return "背包中没有 %s。" % item_name
		"simulation_missing":
			return "运行时不可用，无法操作背包。"
		_:
			var reason := str(feedback.get("reason", ""))
			return reason if not reason.is_empty() else ""


func _use_item_success_text(item_name: String, feedback: Dictionary) -> String:
	var parts: Array[String] = []
	for effect in _array_or_empty(feedback.get("effects", [])):
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		for delta in _array_or_empty(effect_data.get("resource_deltas", [])):
			var delta_data: Dictionary = _dictionary_or_empty(delta)
			var resource := str(delta_data.get("resource", ""))
			var amount := float(delta_data.get("delta", 0.0))
			if resource == "hp" and absf(amount) > 0.01:
				parts.append("HP %+d" % int(round(amount)))
			elif not resource.is_empty() and absf(amount) > 0.01:
				parts.append("%s %+d" % [resource, int(round(amount))])
	var effect_text := "，%s" % " / ".join(parts) if not parts.is_empty() else ""
	return "已使用 %s%s，剩余 %d，AP 剩余 %.0f。" % [
		item_name,
		effect_text,
		int(feedback.get("remaining", 0)),
		float(feedback.get("ap_remaining", 0.0)),
	]


func _feedback_item_name(feedback: Dictionary) -> String:
	var item_id := str(feedback.get("item_id", ""))
	if item_id.is_empty():
		return "物品"
	var record: Dictionary = registry.get_library("items").get(item_id, {})
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", item_id))


func _inventory_order(value: Variant, inventory: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for item_id in _array_or_empty(value):
		var normalized_id: String = str(item_id)
		if normalized_id.is_empty() or output.has(normalized_id):
			continue
		if int(inventory.get(normalized_id, 0)) > 0:
			output.append(normalized_id)
	var remaining: Array = inventory.keys()
	remaining.sort()
	for item_id in remaining:
		var normalized_id: String = str(item_id)
		if output.has(normalized_id):
			continue
		if int(inventory.get(normalized_id, 0)) > 0:
			output.append(normalized_id)
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _string_array(values: Variant) -> Array[String]:
	var output: Array[String] = []
	for value in _array_or_empty(values):
		output.append(str(value))
	return output
