extends RefCounted

const EquipmentEffects = preload("res://scripts/core/economy/equipment_effects.gd")
const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

const DEFAULT_CARRY_WEIGHT := 50.0
const STRENGTH_BASELINE := 5.0
const STRENGTH_CARRY_SCALE := 10.0

var _equipment_effects := EquipmentEffects.new()
var _inventory_entries := InventoryEntries.new()


func capacity_snapshot(actor: Variant, item_library: Dictionary) -> Dictionary:
	var current_weight := inventory_weight(actor, item_library)
	var max_weight := carry_weight(actor, item_library)
	return {
		"current_weight": current_weight,
		"max_weight": max_weight,
		"remaining_weight": max_weight - current_weight,
		"over_capacity": current_weight > max_weight + 0.001,
	}


func can_add_items(actor: Variant, item_library: Dictionary, additions: Array, removals: Array = []) -> Dictionary:
	return can_change_inventory(actor, item_library, additions, removals)


func can_change_inventory(actor: Variant, item_library: Dictionary, additions: Array, removals: Array = [], equipment_override: Variant = null) -> Dictionary:
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var current_weight := inventory_weight(actor, item_library)
	var removed_weight := entries_weight(removals, item_library)
	var added_weight := entries_weight(additions, item_library)
	var projected_weight: float = max(0.0, current_weight - removed_weight) + added_weight
	var max_weight := carry_weight_for_equipment(actor, item_library, _dictionary_or_empty(equipment_override)) if typeof(equipment_override) == TYPE_DICTIONARY else carry_weight(actor, item_library)
	var remaining_weight := max_weight - projected_weight
	if projected_weight > max_weight + 0.001:
		var first_addition: Dictionary = _first_entry(additions)
		return {
			"success": false,
			"reason": "inventory_over_capacity",
			"item_id": str(first_addition.get("item_id", "")),
			"count": int(first_addition.get("count", 0)),
			"current_weight": current_weight,
			"removed_weight": removed_weight,
			"added_weight": added_weight,
			"projected_weight": projected_weight,
			"max_weight": max_weight,
			"remaining_weight": remaining_weight,
			"over_by": projected_weight - max_weight,
		}
	return {
		"success": true,
		"current_weight": current_weight,
		"removed_weight": removed_weight,
		"added_weight": added_weight,
		"projected_weight": projected_weight,
		"max_weight": max_weight,
		"remaining_weight": remaining_weight,
	}


func inventory_weight(actor: Variant, item_library: Dictionary) -> float:
	return inventory_entries_weight(_dictionary_or_empty(_actor_value(actor, "inventory", {})), item_library)


func inventory_entries_weight(inventory: Dictionary, item_library: Dictionary) -> float:
	var total := 0.0
	for item_id in inventory.keys():
		var normalized_id: String = _inventory_entries.normalize_content_id(item_id)
		var count: int = int(inventory.get(item_id, 0))
		if normalized_id.is_empty() or count <= 0:
			continue
		total += item_weight(normalized_id, item_library) * float(count)
	return total


func entries_weight(entries: Array, item_library: Dictionary) -> float:
	var total := 0.0
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var item_id: String = _inventory_entries.normalize_content_id(entry_data.get("item_id", ""))
		var count: int = max(0, int(entry_data.get("count", 0)))
		if item_id.is_empty() or count <= 0:
			continue
		total += item_weight(item_id, item_library) * float(count)
	return total


func item_weight(item_id: String, item_library: Dictionary) -> float:
	var data: Dictionary = item_data(item_id, item_library)
	return max(0.0, float(data.get("weight", 0.0)))


func carry_weight(actor: Variant, item_library: Dictionary) -> float:
	return carry_weight_for_equipment(actor, item_library, _dictionary_or_empty(_actor_value(actor, "equipment", {})))


func carry_weight_for_equipment(actor: Variant, item_library: Dictionary, equipment: Dictionary) -> float:
	var combat_attributes: Dictionary = _combat_attributes(actor)
	var base := DEFAULT_CARRY_WEIGHT
	if combat_attributes.has("carry_weight"):
		base = max(0.0, float(combat_attributes.get("carry_weight", base)))
	else:
		var progression: Dictionary = _dictionary_or_empty(_actor_value(actor, "progression", {}))
		var attributes: Dictionary = _dictionary_or_empty(progression.get("attributes", {}))
		if attributes.has("strength"):
			base += (float(attributes.get("strength", STRENGTH_BASELINE)) - STRENGTH_BASELINE) * STRENGTH_CARRY_SCALE
	var carry_bonus: float = _equipment_effects.attribute_modifier_from_equipment(equipment, item_library, "carry_bonus")
	var carry_weight_bonus: float = _equipment_effects.attribute_modifier_from_equipment(equipment, item_library, "carry_weight")
	return max(0.0, base + carry_bonus + carry_weight_bonus)


func item_data(item_id: String, item_library: Dictionary) -> Dictionary:
	if item_id.is_empty():
		return {}
	var record: Dictionary = _dictionary_or_empty(item_library.get(item_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _combat_attributes(actor: Variant) -> Dictionary:
	var direct: Dictionary = _dictionary_or_empty(_actor_value(actor, "combat_attributes", {}))
	if not direct.is_empty():
		return direct
	var combat: Dictionary = _dictionary_or_empty(_actor_value(actor, "combat", {}))
	return _dictionary_or_empty(combat.get("attributes", {}))


func _actor_value(actor: Variant, key: String, fallback: Variant) -> Variant:
	if typeof(actor) == TYPE_DICTIONARY:
		return _dictionary_or_empty(actor).get(key, fallback)
	if actor == null:
		return fallback
	var value: Variant = actor.get(key)
	return fallback if value == null else value


func _first_entry(entries: Array) -> Dictionary:
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if not entry_data.is_empty():
			return entry_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
