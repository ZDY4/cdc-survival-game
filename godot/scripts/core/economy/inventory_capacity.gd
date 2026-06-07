extends RefCounted

const EquipmentEffects = preload("res://scripts/core/economy/equipment_effects.gd")
const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

const DEFAULT_CARRY_WEIGHT := 50.0
const STRENGTH_BASELINE := 5.0
const STRENGTH_CARRY_SCALE := 10.0
const INVENTORY_ITEM_LIMIT_KEYS := ["max_inventory_items", "inventory_item_capacity", "max_items", "item_capacity"]
const INVENTORY_STACK_LIMIT_KEYS := ["max_inventory_stacks", "max_inventory_slots", "inventory_stack_capacity", "inventory_slot_capacity", "inventory_slots", "max_stacks", "slot_capacity", "max_slots"]

var _equipment_effects := EquipmentEffects.new()
var _inventory_entries := InventoryEntries.new()


func capacity_snapshot(actor: Variant, item_library: Dictionary) -> Dictionary:
	var current_weight := inventory_weight(actor, item_library)
	var max_weight := carry_weight(actor, item_library)
	var current_item_count: int = inventory_item_count(actor)
	var current_stack_count: int = inventory_stack_count(actor)
	var max_items: int = inventory_item_capacity(actor)
	var max_stacks: int = inventory_stack_capacity(actor)
	return {
		"current_weight": current_weight,
		"max_weight": max_weight,
		"remaining_weight": max_weight - current_weight,
		"current_item_count": current_item_count,
		"max_items": max_items,
		"remaining_items": max_items - current_item_count if max_items >= 0 else -1,
		"over_item_capacity": max_items >= 0 and current_item_count > max_items,
		"current_stack_count": current_stack_count,
		"max_stacks": max_stacks,
		"remaining_stacks": max_stacks - current_stack_count if max_stacks >= 0 else -1,
		"over_stack_capacity": max_stacks >= 0 and current_stack_count > max_stacks,
		"over_capacity": current_weight > max_weight + 0.001 or (max_items >= 0 and current_item_count > max_items) or (max_stacks >= 0 and current_stack_count > max_stacks),
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
			"limit_kind": "weight",
			"capacity_kind": "weight",
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
	var projection: Dictionary = _project_inventory_change(actor, item_library, additions, removals)
	var projected_item_count: int = int(projection.get("item_count", 0))
	var max_items: int = inventory_item_capacity(actor)
	if max_items >= 0 and projected_item_count > max_items:
		var first_addition: Dictionary = _first_entry(additions)
		return {
			"success": false,
			"reason": "inventory_over_capacity",
			"limit_kind": "items",
			"capacity_kind": "items",
			"item_id": str(first_addition.get("item_id", "")),
			"count": int(first_addition.get("count", 0)),
			"current_item_count": inventory_item_count(actor),
			"projected_item_count": projected_item_count,
			"max_items": max_items,
			"remaining_items": max_items - projected_item_count,
			"over_by": projected_item_count - max_items,
			"current_weight": current_weight,
			"removed_weight": removed_weight,
			"added_weight": added_weight,
			"projected_weight": projected_weight,
			"max_weight": max_weight,
			"remaining_weight": remaining_weight,
		}
	var projected_stack_count: int = int(projection.get("stack_count", 0))
	var max_stacks: int = inventory_stack_capacity(actor)
	if max_stacks >= 0 and projected_stack_count > max_stacks:
		var first_addition: Dictionary = _first_entry(additions)
		return {
			"success": false,
			"reason": "inventory_over_capacity",
			"limit_kind": "stacks",
			"capacity_kind": "stacks",
			"item_id": str(first_addition.get("item_id", "")),
			"count": int(first_addition.get("count", 0)),
			"current_stack_count": inventory_stack_count(actor),
			"projected_stack_count": projected_stack_count,
			"max_stacks": max_stacks,
			"remaining_stacks": max_stacks - projected_stack_count,
			"over_by": projected_stack_count - max_stacks,
			"current_weight": current_weight,
			"removed_weight": removed_weight,
			"added_weight": added_weight,
			"projected_weight": projected_weight,
			"max_weight": max_weight,
			"remaining_weight": remaining_weight,
		}
	return {
		"success": true,
		"current_weight": current_weight,
		"removed_weight": removed_weight,
		"added_weight": added_weight,
		"projected_weight": projected_weight,
		"max_weight": max_weight,
		"remaining_weight": remaining_weight,
		"projected_item_count": projected_item_count,
		"max_items": max_items,
		"projected_stack_count": projected_stack_count,
		"max_stacks": max_stacks,
	}


func inventory_weight(actor: Variant, item_library: Dictionary) -> float:
	return inventory_entries_weight(_dictionary_or_empty(_actor_value(actor, "inventory", {})), item_library)


func inventory_item_count(actor: Variant) -> int:
	var total := 0
	for item_id in _dictionary_or_empty(_actor_value(actor, "inventory", {})).keys():
		if int(_dictionary_or_empty(_actor_value(actor, "inventory", {})).get(item_id, 0)) > 0:
			total += 1
	return total


func inventory_stack_count(actor: Variant) -> int:
	var total := 0
	var inventory: Dictionary = _dictionary_or_empty(_actor_value(actor, "inventory", {}))
	var inventory_stacks: Dictionary = _dictionary_or_empty(_actor_value(actor, "inventory_stacks", {}))
	for item_id in inventory.keys():
		var normalized_id: String = _inventory_entries.normalize_content_id(item_id)
		var count: int = max(0, int(inventory.get(item_id, 0)))
		if normalized_id.is_empty() or count <= 0:
			continue
		total += _stack_counts_for(normalized_id, count, inventory_stacks).size()
	return total


func inventory_item_capacity(actor: Variant) -> int:
	return _inventory_capacity_int(actor, INVENTORY_ITEM_LIMIT_KEYS)


func inventory_stack_capacity(actor: Variant) -> int:
	return _inventory_capacity_int(actor, INVENTORY_STACK_LIMIT_KEYS)


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


func _project_inventory_change(actor: Variant, item_library: Dictionary, additions: Array, removals: Array) -> Dictionary:
	var inventory: Dictionary = _normalized_inventory(_dictionary_or_empty(_actor_value(actor, "inventory", {})))
	var stacks: Dictionary = {}
	var inventory_stacks: Dictionary = _dictionary_or_empty(_actor_value(actor, "inventory_stacks", {}))
	for item_id in inventory.keys():
		var count: int = int(inventory.get(item_id, 0))
		stacks[item_id] = _stack_counts_for(str(item_id), count, inventory_stacks)
	for entry in removals:
		var removal: Dictionary = _dictionary_or_empty(entry)
		_apply_projected_delta(inventory, stacks, str(removal.get("item_id", "")), -max(0, int(removal.get("count", 0))), item_library)
	for entry in additions:
		var addition: Dictionary = _dictionary_or_empty(entry)
		_apply_projected_delta(inventory, stacks, str(addition.get("item_id", "")), max(0, int(addition.get("count", 0))), item_library)
	var item_count := 0
	var stack_count := 0
	for item_id in inventory.keys():
		if int(inventory.get(item_id, 0)) <= 0:
			continue
		item_count += 1
		stack_count += _array_or_empty(stacks.get(item_id, [])).size()
	return {
		"inventory": inventory,
		"stacks": stacks,
		"item_count": item_count,
		"stack_count": stack_count,
	}


func _apply_projected_delta(inventory: Dictionary, stacks_by_item: Dictionary, item_id: String, delta: int, item_library: Dictionary) -> void:
	var normalized_id: String = _inventory_entries.normalize_content_id(item_id)
	if normalized_id.is_empty() or delta == 0:
		return
	var current_count: int = max(0, int(inventory.get(normalized_id, 0)))
	var next_count: int = current_count + delta
	var stacks: Array[int] = _int_array(stacks_by_item.get(normalized_id, []))
	if stacks.is_empty() and current_count > 0:
		stacks = [current_count]
	if next_count <= 0:
		inventory.erase(normalized_id)
		stacks_by_item.erase(normalized_id)
		return
	inventory[normalized_id] = next_count
	if delta > 0:
		var max_stack: int = _item_max_stack(normalized_id, item_library)
		stacks = _split_stacks_by_max(stacks, max_stack)
		_append_stack_delta(stacks, delta, max_stack)
	else:
		var remaining: int = -delta
		for index in range(stacks.size() - 1, -1, -1):
			if remaining <= 0:
				break
			var stack_count: int = int(stacks[index])
			var consumed: int = min(stack_count, remaining)
			stack_count -= consumed
			remaining -= consumed
			if stack_count <= 0:
				stacks.remove_at(index)
			else:
				stacks[index] = stack_count
	stacks_by_item[normalized_id] = _stacks_or_single_total(stacks, next_count)


func _normalized_inventory(inventory: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for item_id in inventory.keys():
		var normalized_id: String = _inventory_entries.normalize_content_id(item_id)
		var count: int = max(0, int(inventory.get(item_id, 0)))
		if normalized_id.is_empty() or count <= 0:
			continue
		output[normalized_id] = int(output.get(normalized_id, 0)) + count
	return output


func _stack_counts_for(item_id: String, count: int, inventory_stacks: Dictionary) -> Array[int]:
	var stacks: Array[int] = []
	for stack_count in _array_or_empty(inventory_stacks.get(item_id, [])):
		var normalized_count: int = max(0, int(stack_count))
		if normalized_count > 0:
			stacks.append(normalized_count)
	return _stacks_or_single_total(stacks, count)


func _stacks_or_single_total(stacks: Array[int], total_count: int) -> Array[int]:
	var stack_sum := 0
	for count in stacks:
		stack_sum += count
	if stacks.is_empty() or stack_sum != total_count:
		stacks = [total_count]
	return stacks


func _append_stack_delta(stacks: Array[int], delta: int, max_stack: int) -> void:
	var remaining: int = max(0, delta)
	if remaining <= 0:
		return
	if max_stack <= 0:
		stacks.append(remaining)
		return
	for index in range(stacks.size()):
		if remaining <= 0:
			break
		var stack_count: int = int(stacks[index])
		var room: int = max(0, max_stack - stack_count)
		if room > 0:
			var filled: int = min(room, remaining)
			stacks[index] = stack_count + filled
			remaining -= filled
	while remaining > 0:
		var stack_count: int = min(max_stack, remaining)
		stacks.append(stack_count)
		remaining -= stack_count


func _split_stacks_by_max(stacks: Array[int], max_stack: int) -> Array[int]:
	if max_stack <= 0:
		return stacks
	var output: Array[int] = []
	for stack in stacks:
		var remaining: int = max(0, int(stack))
		while remaining > 0:
			var stack_count: int = min(max_stack, remaining)
			output.append(stack_count)
			remaining -= stack_count
	return output


func _item_max_stack(item_id: String, item_library: Dictionary) -> int:
	if item_library.is_empty():
		return 0
	var data: Dictionary = item_data(item_id, item_library)
	if data.is_empty():
		return 0
	for fragment in _array_or_empty(data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "stacking":
			if not bool(fragment_data.get("stackable", false)):
				return 1
			return max(1, int(fragment_data.get("max_stack", 1)))
	return 0


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


func _inventory_capacity_int(actor: Variant, keys: Array) -> int:
	for key in keys:
		var key_string := str(key)
		var direct: Variant = _actor_value(actor, key_string, null)
		if direct != null:
			return int(direct)
	var combat_attributes: Dictionary = _combat_attributes(actor)
	for key in keys:
		var key_string := str(key)
		if combat_attributes.has(key_string):
			return int(combat_attributes.get(key_string, -1))
	var inventory_limits: Dictionary = _dictionary_or_empty(_actor_value(actor, "inventory_limits", {}))
	for key in keys:
		var key_string := str(key)
		if inventory_limits.has(key_string):
			return int(inventory_limits.get(key_string, -1))
	return -1


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


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _int_array(value: Variant) -> Array[int]:
	var output: Array[int] = []
	for entry in _array_or_empty(value):
		var count: int = max(0, int(entry))
		if count > 0:
			output.append(count)
	return output
