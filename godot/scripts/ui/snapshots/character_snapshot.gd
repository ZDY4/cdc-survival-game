extends RefCounted

var registry: RefCounted

const EQUIPMENT_SLOTS: Array[Dictionary] = [
	{"slot_id": "main_hand", "label": "主手"},
	{"slot_id": "off_hand", "label": "副手"},
	{"slot_id": "head", "label": "头部"},
	{"slot_id": "body", "label": "身体"},
	{"slot_id": "hands", "label": "手部"},
	{"slot_id": "legs", "label": "腿部"},
	{"slot_id": "feet", "label": "脚部"},
	{"slot_id": "back", "label": "背部"},
	{"slot_id": "accessory_1", "label": "饰品 1"},
	{"slot_id": "accessory_2", "label": "饰品 2"},
]


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, feedback: Dictionary = {}) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var progression: Dictionary = _dictionary_or_empty(player.get("progression", {}))
	var attributes: Dictionary = _dictionary_or_empty(progression.get("attributes", {}))
	var equipment: Dictionary = _dictionary_or_empty(player.get("equipment", {}))
	var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	return {
		"owner_actor_id": int(player.get("actor_id", 0)),
		"owner_name": str(player.get("display_name", "")),
		"level": int(progression.get("level", 1)),
		"current_xp": int(progression.get("current_xp", 0)),
		"available_stat_points": int(progression.get("available_stat_points", 0)),
		"available_skill_points": int(progression.get("available_skill_points", 0)),
		"hp": float(_dictionary_or_empty(player.get("combat", {})).get("hp", 0.0)),
		"max_hp": float(_dictionary_or_empty(player.get("combat", {})).get("max_hp", 0.0)),
		"ap": float(player.get("ap", 0.0)),
		"attributes": attributes.duplicate(true),
		"equipment": _equipment_snapshot(equipment, inventory),
		"feedback": _feedback_snapshot(feedback),
	}


func _equipment_snapshot(equipment: Dictionary, inventory: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen_slots: Dictionary = {}
	for slot in EQUIPMENT_SLOTS:
		var slot_data: Dictionary = slot
		var slot_id: String = str(slot_data.get("slot_id", ""))
		var actual_slot_id: String = _actual_slot_id(equipment, slot_id)
		var item_id: String = str(equipment.get(actual_slot_id, ""))
		rows.append(_equipment_row(slot_id, str(slot_data.get("label", slot_id)), actual_slot_id, item_id, inventory))
		seen_slots[actual_slot_id] = true
	var extra_slots: Array = equipment.keys()
	extra_slots.sort()
	for extra_slot in extra_slots:
		var extra_slot_id: String = str(extra_slot)
		if bool(seen_slots.get(extra_slot_id, false)):
			continue
		rows.append(_equipment_row(extra_slot_id, extra_slot_id, extra_slot_id, str(equipment.get(extra_slot_id, "")), inventory))
	return rows


func _equipment_row(slot_id: String, label: String, actual_slot_id: String, item_id: String, inventory: Dictionary) -> Dictionary:
	var data: Dictionary = _item_data(item_id)
	var equipped: bool = not item_id.is_empty()
	return {
		"slot_id": slot_id,
		"actual_slot_id": actual_slot_id,
		"label": label,
		"item_id": item_id,
		"name": str(data.get("name", item_id)) if equipped else "",
		"description": str(data.get("description", "")),
		"value": int(data.get("value", 0)),
		"weight": float(data.get("weight", 0.0)),
		"rarity": _rarity(data),
		"details": _equipment_details(data, inventory),
		"equipped": equipped,
	}


func _actual_slot_id(equipment: Dictionary, slot_id: String) -> String:
	if equipment.has(slot_id):
		return slot_id
	if slot_id == "accessory_1" and equipment.has("accessory"):
		return "accessory"
	return slot_id


func _item_data(item_id: String) -> Dictionary:
	if item_id.is_empty() or registry == null:
		return {}
	var record: Dictionary = _dictionary_or_empty(registry.get_library("items").get(item_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _rarity(item_data: Dictionary) -> String:
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "economy":
			return str(fragment_data.get("rarity", ""))
	return ""


func _equipment_details(item_data: Dictionary, inventory: Dictionary) -> Array[String]:
	var details: Array[String] = []
	var weapon: Dictionary = _fragment_by_kind(item_data, "weapon")
	if not weapon.is_empty():
		var weapon_parts: Array[String] = [
			"伤害 %d" % int(weapon.get("damage", 0)),
			"射程 %d" % int(weapon.get("range", 0)),
			"攻速 %.1f" % float(weapon.get("attack_speed", 0.0)),
		]
		var ammo_type: String = _normalize_item_id(weapon.get("ammo_type", ""))
		var max_ammo: int = _optional_int(weapon.get("max_ammo", 0), 0)
		if not ammo_type.is_empty() and ammo_type != "<null>":
			var available_ammo: int = int(inventory.get(ammo_type, 0))
			if max_ammo > 0:
				weapon_parts.append("弹药 %s %d/%d" % [ammo_type, available_ammo, max_ammo])
			else:
				weapon_parts.append("弹药 %s x%d" % [ammo_type, available_ammo])
		details.append("武器: %s" % " / ".join(weapon_parts))
	var durability: Dictionary = _fragment_by_kind(item_data, "durability")
	if not durability.is_empty():
		details.append("耐久: %d/%d" % [
			int(durability.get("durability", 0)),
			int(durability.get("max_durability", 0)),
		])
	var modifiers: Dictionary = _dictionary_or_empty(_fragment_by_kind(item_data, "attribute_modifiers").get("attributes", {}))
	if not modifiers.is_empty():
		var modifier_parts: Array[String] = []
		var keys: Array = modifiers.keys()
		keys.sort()
		for key in keys:
			modifier_parts.append("%s %s" % [str(key), _signed_number(float(modifiers.get(key, 0.0)))])
		details.append("属性: %s" % " / ".join(modifier_parts))
	var appearance: Dictionary = _dictionary_or_empty(_fragment_by_kind(item_data, "appearance").get("definition", {}))
	if not appearance.is_empty():
		var visual_asset: String = str(appearance.get("visual_asset", ""))
		if not visual_asset.is_empty():
			details.append("外观: %s" % visual_asset)
	return details


func _fragment_by_kind(item_data: Dictionary, kind: String) -> Dictionary:
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == kind:
			return fragment_data
	return {}


func _signed_number(value: float) -> String:
	var prefix := "+" if value >= 0.0 else ""
	return "%s%.1f" % [prefix, value]


func _normalize_item_id(value: Variant) -> String:
	if value == null:
		return ""
	if typeof(value) == TYPE_FLOAT:
		var float_value: float = value
		if is_equal_approx(float_value, roundf(float_value)):
			return str(int(float_value))
	if typeof(value) == TYPE_INT:
		return str(value)
	return str(value).strip_edges()


func _optional_int(value: Variant, fallback: int) -> int:
	if value == null:
		return fallback
	if typeof(value) == TYPE_STRING and str(value).strip_edges().is_empty():
		return fallback
	return int(value)


func _item_name(item_id: String) -> String:
	if registry == null:
		return item_id
	var record: Dictionary = _dictionary_or_empty(registry.get_library("items").get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", item_id))


func _feedback_snapshot(feedback: Dictionary) -> Dictionary:
	if feedback.is_empty():
		return {}
	var snapshot := feedback.duplicate(true)
	snapshot["message"] = _feedback_message(snapshot)
	return snapshot


func _feedback_message(feedback: Dictionary) -> String:
	var reason := str(feedback.get("reason", ""))
	var slot_id := str(feedback.get("slot_id", ""))
	var slot_label := _slot_label(slot_id)
	match reason:
		"empty_equipment_slot":
			if not slot_label.is_empty():
				return "%s为空，无法卸下。" % slot_label
			return "装备槽为空，无法卸下。"
		"invalid_equipment_slot":
			if not slot_label.is_empty():
				return "%s不能装备该物品。" % slot_label
			return "不能装备到该装备槽。"
		"item_not_equippable":
			return "该物品不能装备。"
		"not_enough_items":
			return "背包中没有该物品。"
		"unknown_item":
			return "找不到要装备的物品。"
		"unknown_actor":
			return "找不到角色，无法更新装备。"
		"simulation_missing":
			return "运行时未就绪，无法更新装备。"
		_:
			if reason.is_empty():
				return "装备操作失败。"
			return "装备操作失败：%s" % reason


func _slot_label(slot_id: String) -> String:
	for slot in EQUIPMENT_SLOTS:
		var slot_data: Dictionary = slot
		if str(slot_data.get("slot_id", "")) == slot_id:
			return str(slot_data.get("label", slot_id))
	if slot_id == "accessory":
		return "饰品"
	return slot_id


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
