extends RefCounted

const EquipmentEffects = preload("res://scripts/core/economy/equipment_effects.gd")

var registry: RefCounted
var _equipment_effects := EquipmentEffects.new()

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
	var weapon_ammo: Dictionary = _dictionary_or_empty(player.get("weapon_ammo", {}))
	var combat: Dictionary = _dictionary_or_empty(player.get("combat", {}))
	var equipment_rows: Array[Dictionary] = _equipment_snapshot(equipment, inventory, weapon_ammo, float(player.get("ap", 0.0)))
	var status_effects: Array[Dictionary] = _status_effects_snapshot(_array_or_empty(combat.get("active_effects", [])))
	return {
		"owner_actor_id": int(player.get("actor_id", 0)),
		"owner_name": str(player.get("display_name", "")),
		"level": int(progression.get("level", 1)),
		"current_xp": int(progression.get("current_xp", 0)),
		"available_stat_points": int(progression.get("available_stat_points", 0)),
		"available_skill_points": int(progression.get("available_skill_points", 0)),
		"hp": float(combat.get("hp", 0.0)),
		"max_hp": float(combat.get("max_hp", 0.0)),
		"ap": float(player.get("ap", 0.0)),
		"attributes": attributes.duplicate(true),
		"derived_stats": _derived_stats_snapshot(attributes, combat, equipment_rows, status_effects),
		"equipment": equipment_rows,
		"status_effects": status_effects,
		"feedback": _feedback_snapshot(feedback),
	}


func _equipment_snapshot(equipment: Dictionary, inventory: Dictionary, weapon_ammo: Dictionary, actor_ap: float) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen_slots: Dictionary = {}
	for slot in EQUIPMENT_SLOTS:
		var slot_data: Dictionary = slot
		var slot_id: String = str(slot_data.get("slot_id", ""))
		var actual_slot_id: String = _actual_slot_id(equipment, slot_id)
		var item_id: String = str(equipment.get(actual_slot_id, ""))
		rows.append(_equipment_row(slot_id, str(slot_data.get("label", slot_id)), actual_slot_id, item_id, equipment, inventory, weapon_ammo, actor_ap))
		seen_slots[actual_slot_id] = true
	var extra_slots: Array = equipment.keys()
	extra_slots.sort()
	for extra_slot in extra_slots:
		var extra_slot_id: String = str(extra_slot)
		if bool(seen_slots.get(extra_slot_id, false)):
			continue
		rows.append(_equipment_row(extra_slot_id, extra_slot_id, extra_slot_id, str(equipment.get(extra_slot_id, "")), equipment, inventory, weapon_ammo, actor_ap))
	return rows


func _equipment_row(slot_id: String, label: String, actual_slot_id: String, item_id: String, equipment: Dictionary, inventory: Dictionary, weapon_ammo: Dictionary, actor_ap: float) -> Dictionary:
	var data: Dictionary = _item_data(item_id)
	var equipped: bool = not item_id.is_empty()
	var reload: Dictionary = _reload_snapshot(data, actual_slot_id, equipment, inventory, weapon_ammo, actor_ap)
	var effect_ids: Array[String] = _equipment_effects.item_equip_effect_ids(item_id, _item_library())
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
		"effect_ids": effect_ids,
		"effects": _effect_labels(effect_ids),
		"details": _equipment_details(data, inventory, reload, effect_ids),
		"reload": reload,
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
	var record: Dictionary = _dictionary_or_empty(_item_library().get(item_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _rarity(item_data: Dictionary) -> String:
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "economy":
			return str(fragment_data.get("rarity", ""))
	return ""


func _equipment_details(item_data: Dictionary, inventory: Dictionary, reload: Dictionary, effect_ids: Array[String]) -> Array[String]:
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
			var display_ammo: int = int(reload.get("loaded", available_ammo)) if bool(reload.get("magazine_tracked", false)) else available_ammo
			var display_capacity: int = int(reload.get("capacity", max_ammo))
			if display_capacity > 0:
				weapon_parts.append("弹药 %s %d/%d" % [ammo_type, display_ammo, display_capacity])
				if bool(reload.get("magazine_tracked", false)):
					weapon_parts.append("备用 %d" % available_ammo)
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
	var effect_labels: Array[String] = _effect_labels(effect_ids)
	if not effect_labels.is_empty():
		details.append("效果: %s" % " / ".join(effect_labels))
	var appearance: Dictionary = _dictionary_or_empty(_fragment_by_kind(item_data, "appearance").get("definition", {}))
	if not appearance.is_empty():
		var visual_asset: String = str(appearance.get("visual_asset", ""))
		if not visual_asset.is_empty():
			details.append("外观: %s" % visual_asset)
	return details


func _reload_snapshot(item_data: Dictionary, slot_id: String, equipment: Dictionary, inventory: Dictionary, weapon_ammo: Dictionary, actor_ap: float) -> Dictionary:
	var weapon: Dictionary = _fragment_by_kind(item_data, "weapon")
	if weapon.is_empty():
		return {}
	var ammo_type: String = _normalize_item_id(weapon.get("ammo_type", ""))
	var capacity: int = _equipment_effects.weapon_magazine_capacity_from_equipment(equipment, weapon, _item_library())
	if ammo_type.is_empty() or ammo_type == "<null>" or capacity <= 0:
		return {}
	var magazine_tracked: bool = weapon_ammo.has(slot_id)
	var loaded: int = clampi(int(weapon_ammo.get(slot_id, 0)), 0, capacity)
	var inventory_ammo: int = int(inventory.get(ammo_type, 0))
	var reload_ap_cost: float = _equipment_effects.reload_ap_cost_from_equipment(equipment, weapon, _item_library())
	return {
		"reloadable": true,
		"can_reload": loaded < capacity and inventory_ammo > 0 and actor_ap >= reload_ap_cost,
		"magazine_tracked": magazine_tracked,
		"slot_id": slot_id,
		"ammo_type": ammo_type,
		"loaded": loaded,
		"capacity": capacity,
		"inventory_ammo": inventory_ammo,
		"ap_cost": reload_ap_cost,
	}


func _item_library() -> Dictionary:
	if registry == null:
		return {}
	return registry.get_library("items")


func _effect_labels(effect_ids: Array[String]) -> Array[String]:
	var labels: Array[String] = []
	var effects: Dictionary = _effect_library()
	for effect_id in effect_ids:
		var record: Dictionary = _dictionary_or_empty(effects.get(effect_id, {}))
		var data: Dictionary = _dictionary_or_empty(record.get("data", record))
		var label: String = str(data.get("name", effect_id))
		labels.append(label if not label.is_empty() else effect_id)
	return labels


func _effect_library() -> Dictionary:
	if registry == null:
		return {}
	return registry.get_library("json")


func _status_effects_snapshot(active_effects: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for effect in active_effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		var effect_id: String = str(effect_data.get("effect_id", ""))
		if effect_id.is_empty():
			continue
		rows.append({
			"effect_id": effect_id,
			"source": str(effect_data.get("source", "")),
			"skill_id": str(effect_data.get("skill_id", "")),
			"name": _status_effect_name(effect_data),
			"category": str(effect_data.get("category", "")),
			"level": int(effect_data.get("level", 0)),
			"duration_remaining": float(effect_data.get("duration_remaining", 0.0)),
			"is_infinite": bool(effect_data.get("is_infinite", false)),
			"modifiers": _dictionary_or_empty(effect_data.get("modifiers", {})).duplicate(true),
			"modifier_labels": _modifier_labels(_dictionary_or_empty(effect_data.get("modifiers", {}))),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("effect_id", "")) < str(b.get("effect_id", ""))
	)
	return rows


func _derived_stats_snapshot(attributes: Dictionary, combat: Dictionary, equipment_rows: Array, status_effects: Array) -> Array[Dictionary]:
	var combat_attributes: Dictionary = _dictionary_or_empty(combat.get("attributes", {}))
	var equipment_modifiers: Dictionary = _summed_equipment_modifiers(equipment_rows)
	var status_modifiers: Dictionary = _summed_status_modifiers(status_effects)
	return [
		{
			"id": "survivability",
			"label": "生存",
			"value": "HP %.0f/%.0f | 速度 %.1f" % [
				float(combat.get("hp", 0.0)),
				float(combat.get("max_hp", 0.0)),
				float(combat_attributes.get("speed", 0.0)),
			],
			"tooltip": "当前生命 / 最大生命 / 速度派生",
		},
		{
			"id": "combat",
			"label": "战斗",
			"value": "攻击 %.0f | 防御 %.0f | 暴击 %.0f%%" % [
				float(combat_attributes.get("attack_power", 0.0)) + float(equipment_modifiers.get("attack_power", 0.0)),
				float(combat_attributes.get("defense", 0.0)) + float(equipment_modifiers.get("defense", 0.0)),
				float(combat_attributes.get("crit_chance", 0.0)) * 100.0,
			],
			"tooltip": "基础战斗属性加装备修饰",
		},
		{
			"id": "progression",
			"label": "属性",
			"value": "力 %d | 敏 %d | 体 %d | 合计 %d" % [
				int(attributes.get("strength", 0)),
				int(attributes.get("agility", 0)),
				int(attributes.get("constitution", 0)),
				_attribute_total(attributes),
			],
			"tooltip": "当前基础属性合计",
		},
		{
			"id": "equipment",
			"label": "装备",
			"value": "%d 件 | 修饰 %s" % [
				_equipped_count(equipment_rows),
				_modifier_summary(equipment_modifiers),
			],
			"tooltip": "已装备物品数量与装备属性修饰",
		},
		{
			"id": "effects",
			"label": "状态",
			"value": "%d 个 | 修饰 %s" % [
				status_effects.size(),
				_modifier_summary(status_modifiers),
			],
			"tooltip": "主动和被动状态效果修饰",
		},
	]


func _summed_equipment_modifiers(equipment_rows: Array) -> Dictionary:
	var output: Dictionary = {}
	for row in equipment_rows:
		var row_data: Dictionary = _dictionary_or_empty(row)
		if not bool(row_data.get("equipped", false)):
			continue
		var item_data: Dictionary = _item_data(str(row_data.get("item_id", "")))
		var modifiers: Dictionary = _dictionary_or_empty(_fragment_by_kind(item_data, "attribute_modifiers").get("attributes", {}))
		_add_modifiers(output, modifiers)
	return output


func _summed_status_modifiers(status_effects: Array) -> Dictionary:
	var output: Dictionary = {}
	for effect in status_effects:
		_add_modifiers(output, _dictionary_or_empty(_dictionary_or_empty(effect).get("modifiers", {})))
	return output


func _add_modifiers(target: Dictionary, modifiers: Dictionary) -> void:
	for key in modifiers.keys():
		var modifier_id := str(key)
		target[modifier_id] = float(target.get(modifier_id, 0.0)) + float(modifiers.get(key, 0.0))


func _attribute_total(attributes: Dictionary) -> int:
	var total := 0
	for key in attributes.keys():
		total += int(attributes.get(key, 0))
	return total


func _equipped_count(equipment_rows: Array) -> int:
	var count := 0
	for row in equipment_rows:
		if bool(_dictionary_or_empty(row).get("equipped", false)):
			count += 1
	return count


func _modifier_summary(modifiers: Dictionary) -> String:
	if modifiers.is_empty():
		return "无"
	var parts: Array[String] = []
	var keys: Array = modifiers.keys()
	keys.sort()
	for key in keys:
		var value: float = float(modifiers.get(key, 0.0))
		if is_zero_approx(value):
			continue
		parts.append("%s %s" % [str(key), _signed_modifier(value)])
	return "无" if parts.is_empty() else " / ".join(parts)


func _status_effect_name(effect: Dictionary) -> String:
	var skill_id: String = str(effect.get("skill_id", ""))
	if not skill_id.is_empty() and registry != null:
		var record: Dictionary = _dictionary_or_empty(registry.get_library("skills").get(skill_id, {}))
		var data: Dictionary = _dictionary_or_empty(record.get("data", record))
		var skill_name: String = str(data.get("name", ""))
		if not skill_name.is_empty():
			return skill_name
	var effect_id: String = str(effect.get("effect_id", ""))
	if not effect_id.is_empty():
		return effect_id
	return "状态效果"


func _modifier_labels(modifiers: Dictionary) -> Array[String]:
	var labels: Array[String] = []
	var keys: Array = modifiers.keys()
	keys.sort()
	for key in keys:
		labels.append("%s %s" % [str(key), _signed_modifier(float(modifiers.get(key, 0.0)))])
	return labels


func _signed_modifier(value: float) -> String:
	var prefix := "+" if value >= 0.0 else ""
	return "%s%.2f" % [prefix, value]


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
		"weapon_not_reloadable":
			if not slot_label.is_empty():
				return "%s不能装填。" % slot_label
			return "该装备不能装填。"
		"magazine_full":
			if not slot_label.is_empty():
				return "%s弹匣已满。" % slot_label
			return "弹匣已满。"
		"ammo_insufficient":
			return "背包中没有可用弹药。"
		"ap_insufficient_reload":
			return "AP不足，无法装填。"
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
