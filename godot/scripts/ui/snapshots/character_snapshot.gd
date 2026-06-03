extends RefCounted

var registry: RefCounted


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
	var slots: Array = equipment.keys()
	slots.sort()
	for slot_id in slots:
		var item_id: String = str(equipment.get(slot_id, ""))
		if item_id.is_empty():
			continue
		rows.append({
			"slot_id": str(slot_id),
			"item_id": item_id,
			"name": _item_name(item_id),
		})
	return rows


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
