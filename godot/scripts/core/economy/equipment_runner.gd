extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

var _inventory_entries := InventoryEntries.new()


func equip_item(simulation: RefCounted, equipment_rules: RefCounted, actor_id: int, item_id: String, target_slot: String, item_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var result: Dictionary = equipment_rules.equip_item(actor, normalized_item_id, target_slot, item_library)
	if not bool(result.get("success", false)):
		return result
	simulation.emit_event("item_equipped", {
		"actor_id": actor_id,
		"item_id": result.get("item_id", normalized_item_id),
		"slot_id": result.get("slot_id", target_slot),
		"previous_item_id": result.get("previous_item_id", ""),
	})
	return result


func unequip_item(simulation: RefCounted, equipment_rules: RefCounted, actor_id: int, slot_id: String) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var result: Dictionary = equipment_rules.unequip_item(actor, slot_id, _dictionary_or_empty(simulation.get("item_library")))
	if not bool(result.get("success", false)):
		return result
	simulation.emit_event("item_unequipped", {
		"actor_id": actor_id,
		"item_id": result.get("item_id", ""),
		"slot_id": result.get("slot_id", slot_id),
	})
	return result


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
