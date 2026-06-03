extends RefCounted


func attribute_modifier(actor: RefCounted, item_library: Dictionary, key: String) -> float:
	if actor == null:
		return 0.0
	return attribute_modifier_from_equipment(_dictionary_or_empty(actor.equipment), item_library, key)


func attribute_modifier_from_equipment(equipment: Dictionary, item_library: Dictionary, key: String) -> float:
	var value := 0.0
	for slot_id in equipment.keys():
		var item_id: String = str(equipment.get(slot_id, ""))
		if item_id.is_empty():
			continue
		value += item_attribute_modifier(item_id, item_library, key)
	return value


func item_attribute_modifier(item_id: String, item_library: Dictionary, key: String) -> float:
	var item: Dictionary = item_data(item_id, item_library)
	var modifiers: Dictionary = _dictionary_or_empty(_fragment_by_kind(item, "attribute_modifiers").get("attributes", {}))
	return float(modifiers.get(key, 0.0))


func active_effect_ids(actor: RefCounted, item_library: Dictionary) -> Array[String]:
	if actor == null:
		return []
	return active_effect_ids_from_equipment(_dictionary_or_empty(actor.equipment), item_library)


func active_effect_ids_from_equipment(equipment: Dictionary, item_library: Dictionary) -> Array[String]:
	var effects: Array[String] = []
	for slot_id in equipment.keys():
		var item_id: String = str(equipment.get(slot_id, ""))
		if item_id.is_empty():
			continue
		for effect_id in item_equip_effect_ids(item_id, item_library):
			if not effects.has(effect_id):
				effects.append(effect_id)
	effects.sort()
	return effects


func item_equip_effect_ids(item_id: String, item_library: Dictionary) -> Array[String]:
	var item: Dictionary = item_data(item_id, item_library)
	var equip: Dictionary = _fragment_by_kind(item, "equip")
	var output: Array[String] = []
	for effect_id in _array_or_empty(equip.get("equip_effect_ids", [])):
		var normalized_id: String = str(effect_id).strip_edges()
		if not normalized_id.is_empty():
			output.append(normalized_id)
	return output


func weapon_magazine_capacity(actor: RefCounted, weapon: Dictionary, item_library: Dictionary) -> int:
	if actor == null:
		return _weapon_base_capacity(weapon)
	return weapon_magazine_capacity_from_equipment(_dictionary_or_empty(actor.equipment), weapon, item_library)


func weapon_magazine_capacity_from_equipment(equipment: Dictionary, weapon: Dictionary, item_library: Dictionary) -> int:
	var base_capacity: int = _weapon_base_capacity(weapon)
	if base_capacity <= 0:
		return 0
	var capacity_bonus: int = max(0, int(round(attribute_modifier_from_equipment(equipment, item_library, "ammo_capacity"))))
	return max(1, base_capacity + capacity_bonus)


func reload_ap_cost(actor: RefCounted, weapon: Dictionary, item_library: Dictionary, override_cost: Variant = null) -> float:
	if actor == null:
		return _reload_ap_cost_from_bonus(weapon, 0.0, override_cost)
	return reload_ap_cost_from_equipment(_dictionary_or_empty(actor.equipment), weapon, item_library, override_cost)


func reload_ap_cost_from_equipment(equipment: Dictionary, weapon: Dictionary, item_library: Dictionary, override_cost: Variant = null) -> float:
	var reload_speed_bonus: float = clampf(attribute_modifier_from_equipment(equipment, item_library, "reload_speed"), 0.0, 0.8)
	return _reload_ap_cost_from_bonus(weapon, reload_speed_bonus, override_cost)


func item_data(item_id: String, item_library: Dictionary) -> Dictionary:
	if item_id.is_empty():
		return {}
	var record: Dictionary = _dictionary_or_empty(item_library.get(item_id, {}))
	if record.is_empty():
		return {}
	return _dictionary_or_empty(record.get("data", record))


func _reload_ap_cost_from_bonus(weapon: Dictionary, reload_speed_bonus: float, override_cost: Variant = null) -> float:
	var base_cost: float = _optional_float(override_cost, _optional_float(weapon.get("reload_time", 1.0), 1.0))
	return max(1.0, ceil(max(0.1, base_cost) * (1.0 - reload_speed_bonus)))


func _weapon_base_capacity(weapon: Dictionary) -> int:
	return max(0, _optional_int(weapon.get("max_ammo", 0), 0))


func _fragment_by_kind(item: Dictionary, kind: String) -> Dictionary:
	for fragment in _array_or_empty(item.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == kind:
			return fragment_data
	return {}


func _optional_int(value: Variant, fallback: int) -> int:
	if value == null:
		return fallback
	if typeof(value) == TYPE_STRING and str(value).strip_edges().is_empty():
		return fallback
	return int(value)


func _optional_float(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	if typeof(value) == TYPE_STRING and str(value).strip_edges().is_empty():
		return fallback
	return float(value)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
