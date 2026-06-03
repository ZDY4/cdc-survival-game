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


func build(runtime_snapshot: Dictionary) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var progression: Dictionary = _dictionary_or_empty(player.get("progression", {}))
	var attributes: Dictionary = _dictionary_or_empty(progression.get("attributes", {}))
	var equipment: Dictionary = _dictionary_or_empty(player.get("equipment", {}))
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
		"equipment": _equipment_snapshot(equipment),
	}


func _equipment_snapshot(equipment: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen_slots: Dictionary = {}
	for slot in EQUIPMENT_SLOTS:
		var slot_data: Dictionary = slot
		var slot_id: String = str(slot_data.get("slot_id", ""))
		var actual_slot_id: String = _actual_slot_id(equipment, slot_id)
		var item_id: String = str(equipment.get(actual_slot_id, ""))
		rows.append(_equipment_row(slot_id, str(slot_data.get("label", slot_id)), actual_slot_id, item_id))
		seen_slots[actual_slot_id] = true
	var extra_slots: Array = equipment.keys()
	extra_slots.sort()
	for extra_slot in extra_slots:
		var extra_slot_id: String = str(extra_slot)
		if bool(seen_slots.get(extra_slot_id, false)):
			continue
		rows.append(_equipment_row(extra_slot_id, extra_slot_id, extra_slot_id, str(equipment.get(extra_slot_id, ""))))
	return rows


func _equipment_row(slot_id: String, label: String, actual_slot_id: String, item_id: String) -> Dictionary:
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


func _item_name(item_id: String) -> String:
	if registry == null:
		return item_id
	var record: Dictionary = _dictionary_or_empty(registry.get_library("items").get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", item_id))


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
