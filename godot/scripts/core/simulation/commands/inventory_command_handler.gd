extends RefCounted

## 玩家库存命令处理：容器/商店分发、库存拆分排序、物品使用和装备装填。
## 无状态命令处理；actor 库存、装备、AP 和事件仍由 simulation 持有。


func submit_inventory_action_command(simulation: RefCounted, actor: RefCounted, command: Dictionary) -> Dictionary:
	var items: Dictionary = simulation._dictionary_or_empty(command.get("item_library", simulation.item_library))
	match str(command.get("action", "")):
		"take_container":
			return simulation.take_item_from_container(actor.actor_id, str(command.get("container_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items, int(command.get("stack_index", 0)))
		"take_container_money":
			return simulation.take_money_from_container(actor.actor_id, str(command.get("container_id", "")), int(command.get("count", -1)))
		"take_all_container":
			return simulation.take_all_from_container(actor.actor_id, str(command.get("container_id", "")), items, bool(command.get("include_money", true)))
		"store_container":
			return simulation.store_item_in_container(actor.actor_id, str(command.get("container_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items, int(command.get("stack_index", 0)))
		"store_all_container":
			return simulation.store_all_in_container(actor.actor_id, str(command.get("container_id", "")), items)
		"drop":
			return simulation.drop_actor_item(actor.actor_id, str(command.get("item_id", "")), int(command.get("count", 1)), items)
		"deconstruct":
			return simulation._finalize_player_ap_action(actor, simulation._submit_deconstruct_action(actor, command, items), command, "deconstruct")
		"split_stack":
			return simulation._split_actor_inventory_stack(actor, str(command.get("item_id", "")), int(command.get("count", 1)), int(command.get("source_stack_index", 0)))
		"reorder_inventory":
			return simulation._reorder_actor_inventory(actor, str(command.get("item_id", "")), int(command.get("target_index", 0)))
		"equip":
			return simulation.equip_item(actor.actor_id, str(command.get("item_id", "")), str(command.get("slot_id", "")), items)
		"unequip":
			return simulation.unequip_item(actor.actor_id, str(command.get("slot_id", "")))
		"reload_equipped":
			return simulation._finalize_player_ap_action(actor, simulation._submit_reload_equipped_action(actor, command, items), command, "reload")
		"use_item":
			return simulation._finalize_player_ap_action(actor, simulation._submit_use_item_action(actor, command, items), command, "use_item")
		"buy_shop":
			return simulation.buy_item_from_shop(actor.actor_id, str(command.get("shop_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items, int(command.get("stack_index", 0)))
		"sell_shop":
			return simulation.sell_item_to_shop(actor.actor_id, str(command.get("shop_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items, int(command.get("stack_index", 0)))
		"sell_equipped_shop":
			return simulation.sell_equipped_item_to_shop(actor.actor_id, str(command.get("shop_id", "")), str(command.get("slot_id", "")), str(command.get("item_id", "")), items)
	return {"success": false, "reason": "unknown_inventory_action"}


func split_actor_inventory_stack(simulation: RefCounted, actor: RefCounted, item_id: String, count: int, source_stack_index: int = 0) -> Dictionary:
	var normalized_item_id: String = simulation._inventory_entries.normalize_content_id(item_id)
	if normalized_item_id.is_empty():
		return {"success": false, "reason": "invalid_item_id"}
	var available: int = int(actor.inventory.get(normalized_item_id, 0))
	if available <= 0:
		return {
			"success": false,
			"reason": "item_not_in_inventory",
			"item_id": normalized_item_id,
		}
	if count <= 0:
		return {
			"success": false,
			"reason": "invalid_quantity",
			"item_id": normalized_item_id,
			"count": count,
		}
	if count >= available:
		return {
			"success": false,
			"reason": "split_count_must_be_less_than_stack",
			"item_id": normalized_item_id,
			"count": count,
			"available": available,
		}
	simulation._inventory_entries.sync_actor_inventory_order(actor)
	var stacks: Array[int] = simulation._actor_inventory_stacks_for(actor, normalized_item_id, available)
	var source_index: int = source_stack_index - 1 if source_stack_index > 0 else simulation._largest_stack_index(stacks)
	if source_index < 0 or source_index >= stacks.size():
		return {
			"success": false,
			"reason": "split_source_stack_invalid",
			"item_id": normalized_item_id,
			"count": count,
			"available": available,
			"source_stack_index": source_stack_index,
			"stacks": stacks.duplicate(),
		}
	if source_index < 0 or int(stacks[source_index]) <= count:
		return {
			"success": false,
			"reason": "split_count_must_be_less_than_stack",
			"item_id": normalized_item_id,
			"count": count,
			"available": available,
			"source_stack_index": source_stack_index,
			"stacks": stacks.duplicate(),
		}
	stacks[source_index] = int(stacks[source_index]) - count
	stacks.append(count)
	actor.inventory_stacks[normalized_item_id] = stacks
	simulation._emit("inventory_stack_split", {
		"actor_id": actor.actor_id,
		"item_id": normalized_item_id,
		"count": count,
		"source_stack_index": source_index,
		"new_stack_index": stacks.size() - 1,
		"stacks": stacks.duplicate(),
	})
	return {
		"success": true,
		"kind": "inventory_stack_split",
		"item_id": normalized_item_id,
		"count": count,
		"available": available,
		"source_stack_index": source_index,
		"new_stack_index": stacks.size() - 1,
		"stacks": stacks.duplicate(),
	}


func actor_inventory_stacks_for(simulation: RefCounted, actor: RefCounted, item_id: String, available: int) -> Array[int]:
	var stacks: Array[int] = []
	for stack_count in simulation._array_or_empty(actor.inventory_stacks.get(item_id, [])):
		var count: int = max(0, int(stack_count))
		if count > 0:
			stacks.append(count)
	var stack_sum := 0
	for count in stacks:
		stack_sum += count
	if stacks.is_empty() or stack_sum != available:
		stacks = [available]
	actor.inventory_stacks[item_id] = stacks
	return stacks


func largest_stack_index(_simulation: RefCounted, stacks: Array[int]) -> int:
	var best_index := -1
	var best_count := 0
	for index in range(stacks.size()):
		var count: int = int(stacks[index])
		if count > best_count:
			best_count = count
			best_index = index
	return best_index


func reorder_actor_inventory(simulation: RefCounted, actor: RefCounted, item_id: String, target_index: int) -> Dictionary:
	var normalized_item_id: String = simulation._inventory_entries.normalize_content_id(item_id)
	if normalized_item_id.is_empty():
		return {"success": false, "reason": "invalid_item_id"}
	if int(actor.inventory.get(normalized_item_id, 0)) <= 0:
		return {
			"success": false,
			"reason": "item_not_in_inventory",
			"item_id": normalized_item_id,
		}
	simulation._inventory_entries.sync_actor_inventory_order(actor)
	var order: Array[String] = []
	for order_item_id in actor.inventory_order:
		order.append(str(order_item_id))
	var from_index: int = order.find(normalized_item_id)
	if from_index < 0:
		return {
			"success": false,
			"reason": "item_not_in_inventory_order",
			"item_id": normalized_item_id,
		}
	var original_order: Array[String] = order.duplicate()
	order.remove_at(from_index)
	var insertion_index: int = clampi(target_index, 0, order.size())
	if target_index > from_index:
		insertion_index = clampi(target_index - 1, 0, order.size())
	order.insert(insertion_index, normalized_item_id)
	actor.inventory_order = order
	simulation.emit_event("inventory_reordered", {
		"actor_id": actor.actor_id,
		"item_id": normalized_item_id,
		"from_index": from_index,
		"to_index": insertion_index,
		"previous_order": original_order,
		"inventory_order": order.duplicate(),
	})
	return {
		"success": true,
		"item_id": normalized_item_id,
		"from_index": from_index,
		"to_index": insertion_index,
		"inventory_order": order.duplicate(),
	}


func submit_use_item_action(simulation: RefCounted, actor: RefCounted, command: Dictionary, items: Dictionary) -> Dictionary:
	var item_id: String = str(command.get("item_id", ""))
	var effects: Dictionary = simulation._dictionary_or_empty(command.get("effect_library", simulation.effect_library))
	var validation: Dictionary = simulation._item_use_runner.validate_use_item(simulation, actor.actor_id, item_id, items, effects)
	if not bool(validation.get("success", false)):
		return validation
	var ap_cost: float = float(command.get("ap_cost", simulation._item_use_runner.use_ap_cost(item_id, items)))
	if actor.ap < ap_cost:
		return {
			"success": false,
			"reason": "ap_insufficient_use_item",
			"item_id": item_id,
			"required_ap": ap_cost,
			"available_ap": actor.ap,
		}
	simulation._spend_ap(actor, ap_cost, "use_item:%s" % item_id)
	var result: Dictionary = simulation._item_use_runner.use_item(simulation, actor.actor_id, item_id, items, effects)
	if bool(result.get("success", false)):
		result["ap_cost"] = ap_cost
		result["ap_remaining"] = actor.ap
	return result


func submit_reload_equipped_action(simulation: RefCounted, actor: RefCounted, command: Dictionary, items: Dictionary) -> Dictionary:
	var slot_id := str(command.get("slot_id", "main_hand")).strip_edges()
	if slot_id.is_empty():
		slot_id = "main_hand"
	var item_id := str(actor.equipment.get(slot_id, ""))
	if item_id.is_empty():
		return {"success": false, "reason": "empty_equipment_slot", "slot_id": slot_id}
	var weapon: Dictionary = simulation._weapon_fragment(item_id, items)
	if weapon.is_empty():
		return {"success": false, "reason": "weapon_not_reloadable", "slot_id": slot_id, "item_id": item_id}
	var ammo_type: String = simulation._normalize_item_id(weapon.get("ammo_type", ""))
	var magazine_capacity: int = simulation._equipment_effects.weapon_magazine_capacity(actor, weapon, items)
	if ammo_type.is_empty() or magazine_capacity <= 0:
		return {"success": false, "reason": "weapon_not_reloadable", "slot_id": slot_id, "item_id": item_id}
	var loaded_before := clampi(int(actor.weapon_ammo.get(slot_id, 0)), 0, magazine_capacity)
	var missing: int = magazine_capacity - loaded_before
	if missing <= 0:
		return {
			"success": false,
			"reason": "magazine_full",
			"slot_id": slot_id,
			"item_id": item_id,
			"loaded": loaded_before,
			"capacity": magazine_capacity,
			"ammo_type": ammo_type,
		}
	var available := int(actor.inventory.get(ammo_type, 0))
	if available <= 0:
		return {
			"success": false,
			"reason": "ammo_insufficient",
			"slot_id": slot_id,
			"item_id": item_id,
			"ammo_type": ammo_type,
			"required": 1,
			"current": available,
			"loaded": loaded_before,
			"capacity": magazine_capacity,
		}
	var override_cost: Variant = command.get("ap_cost", null) if command.has("ap_cost") else null
	var reload_cost: float = simulation._equipment_effects.reload_ap_cost(actor, weapon, items, override_cost)
	if actor.ap < reload_cost:
		return {
			"success": false,
			"reason": "ap_insufficient_reload",
			"slot_id": slot_id,
			"item_id": item_id,
			"required_ap": reload_cost,
			"available_ap": actor.ap,
		}
	var loaded_count: int = min(missing, available)
	simulation._spend_ap(actor, reload_cost, "reload")
	simulation._inventory_entries.add_actor_item(actor, ammo_type, -loaded_count)
	actor.weapon_ammo[slot_id] = loaded_before + loaded_count
	simulation._emit("weapon_reloaded", {
		"actor_id": actor.actor_id,
		"slot_id": slot_id,
		"weapon_item_id": item_id,
		"ammo_type": ammo_type,
		"loaded": int(actor.weapon_ammo.get(slot_id, 0)),
		"loaded_before": loaded_before,
		"loaded_count": loaded_count,
		"capacity": magazine_capacity,
		"remaining_inventory": int(actor.inventory.get(ammo_type, 0)),
		"ap_cost": reload_cost,
	})
	return {
		"success": true,
		"kind": "reload_equipped",
		"slot_id": slot_id,
		"item_id": item_id,
		"ammo_type": ammo_type,
		"loaded": int(actor.weapon_ammo.get(slot_id, 0)),
		"loaded_before": loaded_before,
		"loaded_count": loaded_count,
		"capacity": magazine_capacity,
		"remaining_inventory": int(actor.inventory.get(ammo_type, 0)),
		"ap_cost": reload_cost,
	}
