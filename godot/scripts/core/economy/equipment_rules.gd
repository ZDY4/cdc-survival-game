extends RefCounted


func equip_item(actor: RefCounted, item_id: String, requested_slot: String, item_library: Dictionary) -> Dictionary:
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var record: Dictionary = _dictionary_or_empty(item_library.get(item_id, {}))
	if record.is_empty():
		return {"success": false, "reason": "unknown_item", "item_id": item_id}
	var item: Dictionary = _dictionary_or_empty(record.get("data", record))
	var equip_fragment: Dictionary = _fragment_by_kind(item, "equip")
	if equip_fragment.is_empty():
		return {"success": false, "reason": "item_not_equippable", "item_id": item_id}

	var slot_result: Dictionary = _resolve_equipment_slot(item_id, _string_array(equip_fragment.get("slots", [])), requested_slot)
	if not bool(slot_result.get("success", false)):
		return slot_result
	var slot_id: String = str(slot_result.get("slot_id", ""))
	if int(actor.inventory.get(item_id, 0)) <= 0:
		return {
			"success": false,
			"reason": "not_enough_items",
			"item_id": item_id,
			"required": 1,
			"current": int(actor.inventory.get(item_id, 0)),
		}

	var previous_item_id: String = str(actor.equipment.get(slot_id, ""))
	_add_actor_item(actor, item_id, -1)
	if not previous_item_id.is_empty():
		_add_actor_item(actor, previous_item_id, 1)
	actor.equipment[slot_id] = item_id
	return {
		"success": true,
		"item_id": item_id,
		"slot_id": slot_id,
		"previous_item_id": previous_item_id,
	}


func unequip_item(actor: RefCounted, slot_id: String) -> Dictionary:
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_slot: String = slot_id.strip_edges()
	var item_id: String = str(actor.equipment.get(normalized_slot, ""))
	if item_id.is_empty():
		return {"success": false, "reason": "empty_equipment_slot", "slot_id": normalized_slot}
	actor.equipment.erase(normalized_slot)
	_add_actor_item(actor, item_id, 1)
	return {
		"success": true,
		"item_id": item_id,
		"slot_id": normalized_slot,
	}


func _resolve_equipment_slot(item_id: String, allowed_slots: Array[String], requested_slot: String) -> Dictionary:
	var normalized_request: String = requested_slot.strip_edges()
	if not normalized_request.is_empty():
		if _slot_supported(allowed_slots, normalized_request):
			return {"success": true, "slot_id": normalized_request}
		return {
			"success": false,
			"reason": "invalid_equipment_slot",
			"item_id": item_id,
			"slot_id": normalized_request,
		}
	if allowed_slots.is_empty():
		return {"success": false, "reason": "item_not_equippable", "item_id": item_id}
	return {"success": true, "slot_id": allowed_slots[0]}


func _slot_supported(allowed_slots: Array[String], requested_slot: String) -> bool:
	for slot in allowed_slots:
		var normalized_slot: String = slot.strip_edges()
		if normalized_slot == requested_slot:
			return true
		if normalized_slot == "main_hand" and requested_slot == "off_hand":
			return true
		if normalized_slot == "accessory" and requested_slot in ["accessory_1", "accessory_2"]:
			return true
	return false


func _fragment_by_kind(item: Dictionary, kind: String) -> Dictionary:
	for fragment in _array_or_empty(item.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == kind:
			return fragment_data
	return {}


func _add_actor_item(actor: RefCounted, item_id: String, delta: int) -> void:
	var next_count: int = int(actor.inventory.get(item_id, 0)) + delta
	if next_count <= 0:
		actor.inventory.erase(item_id)
	else:
		actor.inventory[item_id] = next_count


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
