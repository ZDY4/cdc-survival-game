extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

var _inventory_entries := InventoryEntries.new()


func use_item(simulation: RefCounted, actor_id: int, item_id: String, item_library: Dictionary, effect_library: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_use_item(simulation, actor_id, item_id, item_library, effect_library)
	if not bool(validation.get("success", false)):
		return validation
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var usable: Dictionary = _dictionary_or_empty(validation.get("usable", {}))
	var effects: Array[Dictionary] = []
	for effect_id in _string_array(usable.get("effect_ids", [])):
		effects.append(_apply_effect(actor, effect_id, effect_library))
	if bool(usable.get("consume_on_use", true)):
		_inventory_entries.add_actor_item(actor, normalized_item_id, -1)
	simulation.emit_event("item_used", {
		"actor_id": actor_id,
		"item_id": normalized_item_id,
		"consume_on_use": bool(usable.get("consume_on_use", true)),
		"effects": effects.duplicate(true),
	})
	return {
		"success": true,
		"kind": "use_item",
		"actor_id": actor_id,
		"item_id": normalized_item_id,
		"consume_on_use": bool(usable.get("consume_on_use", true)),
		"effects": effects,
		"remaining": int(actor.inventory.get(normalized_item_id, 0)),
	}


func validate_use_item(simulation: RefCounted, actor_id: int, item_id: String, item_library: Dictionary, effect_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	if normalized_item_id.is_empty():
		return {"success": false, "reason": "item_id_missing"}
	if int(actor.inventory.get(normalized_item_id, 0)) <= 0:
		return {
			"success": false,
			"reason": "not_enough_items",
			"item_id": normalized_item_id,
			"current": int(actor.inventory.get(normalized_item_id, 0)),
			"required": 1,
		}
	var item: Dictionary = _item_data(normalized_item_id, item_library)
	if item.is_empty():
		return {"success": false, "reason": "unknown_item", "item_id": normalized_item_id}
	var usable: Dictionary = _fragment_by_kind(item, "usable")
	if usable.is_empty():
		return {"success": false, "reason": "item_not_usable", "item_id": normalized_item_id}
	if not _is_item_use_allowed(item):
		return {"success": false, "reason": "item_use_forbidden", "item_id": normalized_item_id}
	for effect_id in _string_array(usable.get("effect_ids", [])):
		if _effect_data(effect_id, effect_library).is_empty():
			return {
				"success": false,
				"reason": "unknown_effect",
				"item_id": normalized_item_id,
				"effect_id": effect_id,
			}
	return {
		"success": true,
		"actor_id": actor_id,
		"item_id": normalized_item_id,
		"usable": usable.duplicate(true),
	}


func use_ap_cost(item_id: String, item_library: Dictionary) -> float:
	var item: Dictionary = _item_data(item_id, item_library)
	var usable: Dictionary = _fragment_by_kind(item, "usable")
	if usable.is_empty():
		return 1.0
	return max(1.0, ceil(float(usable.get("use_time", 1.0))))


func _apply_effect(actor: RefCounted, effect_id: String, effect_library: Dictionary) -> Dictionary:
	var effect: Dictionary = _effect_data(effect_id, effect_library)
	if effect.is_empty():
		return {"success": false, "reason": "unknown_effect", "effect_id": effect_id}
	var gameplay: Dictionary = _dictionary_or_empty(effect.get("gameplay_effect", {}))
	var deltas: Dictionary = _dictionary_or_empty(gameplay.get("resource_deltas", {}))
	var resources: Array[Dictionary] = []
	for key in deltas.keys():
		var resource_id: String = str(key)
		var delta: float = float(deltas.get(key, 0.0))
		resources.append(_apply_resource_delta(actor, resource_id, delta))
	return {
		"success": true,
		"effect_id": effect_id,
		"resource_deltas": resources,
	}


func _apply_resource_delta(actor: RefCounted, resource_id: String, delta: float) -> Dictionary:
	if resource_id == "health" or resource_id == "hp":
		var before_hp: float = actor.hp
		actor.hp = clampf(actor.hp + delta, 0.0, actor.max_hp)
		actor.resources["hp"] = {"current": actor.hp, "max": actor.max_hp}
		return {
			"resource": "hp",
			"before": before_hp,
			"after": actor.hp,
			"delta": actor.hp - before_hp,
		}
	var resource: Dictionary = _dictionary_or_empty(actor.resources.get(resource_id, {}))
	var max_value: float = max(1.0, float(resource.get("max", 100.0)))
	var before: float = clampf(float(resource.get("current", 0.0)), 0.0, max_value)
	var after: float = clampf(before + delta, 0.0, max_value)
	actor.resources[resource_id] = {
		"current": after,
		"max": max_value,
	}
	return {
		"resource": resource_id,
		"before": before,
		"after": after,
		"delta": after - before,
	}


func _item_data(item_id: String, item_library: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(item_library.get(item_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _effect_data(effect_id: String, effect_library: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(effect_library.get(effect_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _fragment_by_kind(item: Dictionary, kind: String) -> Dictionary:
	for fragment in _array_or_empty(item.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == kind:
			return fragment_data
	return {}


func _is_item_use_allowed(item: Dictionary) -> bool:
	for key in ["usable", "can_use"]:
		if item.has(key) and not bool(item.get(key)):
			return false
	for fragment in _array_or_empty(item.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		var kind: String = str(fragment_data.get("kind", ""))
		if kind in ["quest", "task", "key_item"]:
			return false
		for key in ["usable", "can_use"]:
			if fragment_data.has(key) and not bool(fragment_data.get(key)):
				return false
	return true


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
