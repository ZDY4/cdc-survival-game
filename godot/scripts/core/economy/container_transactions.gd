extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const InventoryCapacity = preload("res://scripts/core/economy/inventory_capacity.gd")

var _inventory_entries := InventoryEntries.new()
var _inventory_capacity := InventoryCapacity.new()


func take_item_from_container(simulation: RefCounted, actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_container_id: String = str(container_id)
	var container: Dictionary = _dictionary_or_empty(simulation.container_sessions.get(normalized_container_id, {}))
	if container.is_empty():
		return {"success": false, "reason": "unknown_container", "container_id": normalized_container_id}
	var permission: Dictionary = _container_permission(simulation, actor, actor_id, normalized_container_id, container, "take")
	if not bool(permission.get("success", false)):
		return permission
	var stealing: bool = bool(permission.get("stealing", false))
	var owner_actor_id: int = int(permission.get("owner_actor_id", 0))
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	if not item_library.is_empty() and _dictionary_or_empty(item_library.get(normalized_item_id, {})).is_empty():
		return {"success": false, "reason": "unknown_item", "item_id": normalized_item_id}
	if count <= 0:
		return {
			"success": false,
			"reason": "invalid_quantity",
			"container_id": normalized_container_id,
			"item_id": normalized_item_id,
			"count": count,
		}
	var transfer_count: int = count
	var available: int = _inventory_entries.count(_array_or_empty(container.get("inventory", [])), normalized_item_id)
	if available < transfer_count:
		return {
			"success": false,
			"reason": "container_inventory_insufficient",
			"container_id": normalized_container_id,
			"item_id": normalized_item_id,
			"required": transfer_count,
			"current": available,
		}
	var capacity: Dictionary = _inventory_capacity.can_add_items(actor, item_library, [
		{"item_id": normalized_item_id, "count": transfer_count},
	])
	if not bool(capacity.get("success", false)):
		capacity["container_id"] = normalized_container_id
		return capacity

	var unlock_consumption: Dictionary = _consume_container_unlock_requirements(simulation, actor, actor_id, normalized_container_id, container, "take")
	if not bool(unlock_consumption.get("success", false)):
		return unlock_consumption
	var consumed_unlock_requirements: Array = _array_or_empty(unlock_consumption.get("consumed_unlock_requirements", []))
	_inventory_entries.add(container["inventory"], normalized_item_id, -transfer_count)
	_inventory_entries.add_actor_item(actor, normalized_item_id, transfer_count)
	simulation.container_sessions[normalized_container_id] = container
	_sync_corpse_container_session(simulation, normalized_container_id, container)
	var steal_consequence: Dictionary = {}
	if stealing:
		steal_consequence = _apply_container_steal_consequences(simulation, actor_id, owner_actor_id, normalized_container_id, container, normalized_item_id, transfer_count)
	simulation.emit_event("container_item_taken", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
		"stealing": stealing,
		"owner_actor_id": owner_actor_id,
		"unlock_requirements_consumed": not consumed_unlock_requirements.is_empty(),
		"consumed_unlock_requirements": consumed_unlock_requirements.duplicate(true),
	})
	simulation.emit_event("container_transferred", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
		"direction": "take",
		"from": "container",
		"to": "actor_inventory",
		"stealing": stealing,
		"owner_actor_id": owner_actor_id,
		"unlock_requirements_consumed": not consumed_unlock_requirements.is_empty(),
		"consumed_unlock_requirements": consumed_unlock_requirements.duplicate(true),
	})
	simulation.record_item_collected(actor_id, normalized_item_id, transfer_count)
	var result := {
		"success": true,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
		"stealing": stealing,
		"owner_actor_id": owner_actor_id,
	}
	_copy_unlock_consumption(result, unlock_consumption)
	_copy_steal_consequence(result, steal_consequence)
	return result


func take_money_from_container(simulation: RefCounted, actor_id: int, container_id: String, count: int = -1) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_container_id: String = str(container_id)
	var container: Dictionary = _dictionary_or_empty(simulation.container_sessions.get(normalized_container_id, {}))
	if container.is_empty():
		return {"success": false, "reason": "unknown_container", "container_id": normalized_container_id}
	var permission: Dictionary = _container_permission(simulation, actor, actor_id, normalized_container_id, container, "take")
	if not bool(permission.get("success", false)):
		return permission
	var stealing: bool = bool(permission.get("stealing", false))
	var owner_actor_id: int = int(permission.get("owner_actor_id", 0))
	var available: int = max(0, int(container.get("money", 0)))
	var transfer_count: int = available if count < 0 else count
	if transfer_count <= 0:
		return {
			"success": false,
			"reason": "invalid_quantity",
			"container_id": normalized_container_id,
			"item_id": "money",
			"count": count,
		}
	if available < transfer_count:
		return {
			"success": false,
			"reason": "container_money_insufficient",
			"container_id": normalized_container_id,
			"item_id": "money",
			"required": transfer_count,
			"current": available,
		}

	var unlock_consumption: Dictionary = _consume_container_unlock_requirements(simulation, actor, actor_id, normalized_container_id, container, "take_money")
	if not bool(unlock_consumption.get("success", false)):
		return unlock_consumption
	var consumed_unlock_requirements: Array = _array_or_empty(unlock_consumption.get("consumed_unlock_requirements", []))
	var actor_money_before: int = max(0, int(actor.money))
	var container_money_after: int = available - transfer_count
	actor.money = actor_money_before + transfer_count
	container["money"] = container_money_after
	simulation.container_sessions[normalized_container_id] = container
	if simulation.corpse_containers.has(normalized_container_id):
		var corpse: Dictionary = _dictionary_or_empty(simulation.corpse_containers[normalized_container_id])
		corpse["money"] = container_money_after
		simulation.corpse_containers[normalized_container_id] = corpse
	var steal_consequence: Dictionary = {}
	if stealing:
		steal_consequence = _apply_container_steal_consequences(simulation, actor_id, owner_actor_id, normalized_container_id, container, "money", transfer_count)
	simulation.emit_event("container_money_taken", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"count": transfer_count,
		"player_money_before": actor_money_before,
		"player_money_after": actor.money,
		"container_money_before": available,
		"container_money_after": container_money_after,
		"stealing": stealing,
		"owner_actor_id": owner_actor_id,
		"unlock_requirements_consumed": not consumed_unlock_requirements.is_empty(),
		"consumed_unlock_requirements": consumed_unlock_requirements.duplicate(true),
	})
	simulation.emit_event("container_transferred", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": "money",
		"count": transfer_count,
		"direction": "take",
		"from": "container_money",
		"to": "actor_money",
		"stealing": stealing,
		"owner_actor_id": owner_actor_id,
		"unlock_requirements_consumed": not consumed_unlock_requirements.is_empty(),
		"consumed_unlock_requirements": consumed_unlock_requirements.duplicate(true),
	})
	var result := {
		"success": true,
		"container_id": normalized_container_id,
		"item_id": "money",
		"count": transfer_count,
		"player_money_before": actor_money_before,
		"player_money_after": actor.money,
		"container_money_before": available,
		"container_money_after": container_money_after,
		"stealing": stealing,
		"owner_actor_id": owner_actor_id,
	}
	_copy_unlock_consumption(result, unlock_consumption)
	_copy_steal_consequence(result, steal_consequence)
	return result


func take_all_from_container(simulation: RefCounted, actor_id: int, container_id: String, item_library: Dictionary = {}, include_money: bool = true) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_container_id: String = str(container_id)
	var container: Dictionary = _dictionary_or_empty(simulation.container_sessions.get(normalized_container_id, {}))
	if container.is_empty():
		return {"success": false, "reason": "unknown_container", "container_id": normalized_container_id}

	var transfers: Array[Dictionary] = []
	var failures: Array[Dictionary] = []
	for entry in _array_or_empty(container.get("inventory", [])).duplicate(true):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var item_id: String = _inventory_entries.normalize_content_id(entry_data.get("item_id", ""))
		var count: int = max(0, int(entry_data.get("count", 0)))
		if item_id.is_empty() or count <= 0:
			continue
		var result: Dictionary = take_item_from_container(simulation, actor_id, normalized_container_id, item_id, count, item_library)
		if bool(result.get("success", false)):
			transfers.append(result)
		else:
			failures.append(result)
	if include_money:
		var money_available: int = max(0, int(_dictionary_or_empty(simulation.container_sessions.get(normalized_container_id, {})).get("money", 0)))
		if money_available > 0:
			var money_result: Dictionary = take_money_from_container(simulation, actor_id, normalized_container_id, -1)
			if bool(money_result.get("success", false)):
				transfers.append(money_result)
			else:
				failures.append(money_result)
	return _bulk_container_result(simulation, actor_id, normalized_container_id, "take_all", transfers, failures)


func store_item_in_container(simulation: RefCounted, actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_container_id: String = str(container_id)
	var container: Dictionary = _dictionary_or_empty(simulation.container_sessions.get(normalized_container_id, {}))
	if container.is_empty():
		return {"success": false, "reason": "unknown_container", "container_id": normalized_container_id}
	var permission: Dictionary = _container_permission(simulation, actor, actor_id, normalized_container_id, container, "store")
	if not bool(permission.get("success", false)):
		return permission
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	if not item_library.is_empty() and _dictionary_or_empty(item_library.get(normalized_item_id, {})).is_empty():
		return {"success": false, "reason": "unknown_item", "item_id": normalized_item_id}
	if count <= 0:
		return {
			"success": false,
			"reason": "invalid_quantity",
			"container_id": normalized_container_id,
			"item_id": normalized_item_id,
			"count": count,
		}
	var transfer_count: int = count
	var available: int = int(actor.inventory.get(normalized_item_id, 0))
	if available < transfer_count:
		return {
			"success": false,
			"reason": "not_enough_items",
			"item_id": normalized_item_id,
			"required": transfer_count,
			"current": available,
		}
	var capacity: Dictionary = _container_capacity_check(normalized_container_id, container, normalized_item_id, transfer_count, item_library)
	if not bool(capacity.get("success", false)):
		return capacity

	var unlock_consumption: Dictionary = _consume_container_unlock_requirements(simulation, actor, actor_id, normalized_container_id, container, "store")
	if not bool(unlock_consumption.get("success", false)):
		return unlock_consumption
	var consumed_unlock_requirements: Array = _array_or_empty(unlock_consumption.get("consumed_unlock_requirements", []))
	_inventory_entries.add_actor_item(actor, normalized_item_id, -transfer_count)
	_inventory_entries.add(container["inventory"], normalized_item_id, transfer_count)
	simulation.container_sessions[normalized_container_id] = container
	_sync_corpse_container_session(simulation, normalized_container_id, container)
	simulation.emit_event("container_item_stored", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
		"unlock_requirements_consumed": not consumed_unlock_requirements.is_empty(),
		"consumed_unlock_requirements": consumed_unlock_requirements.duplicate(true),
	})
	simulation.emit_event("container_transferred", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
		"direction": "store",
		"from": "actor_inventory",
		"to": "container",
		"unlock_requirements_consumed": not consumed_unlock_requirements.is_empty(),
		"consumed_unlock_requirements": consumed_unlock_requirements.duplicate(true),
	})
	var result := {
		"success": true,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
	}
	_copy_unlock_consumption(result, unlock_consumption)
	return result


func store_all_in_container(simulation: RefCounted, actor_id: int, container_id: String, item_library: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_container_id: String = str(container_id)
	var container: Dictionary = _dictionary_or_empty(simulation.container_sessions.get(normalized_container_id, {}))
	if container.is_empty():
		return {"success": false, "reason": "unknown_container", "container_id": normalized_container_id}

	var transfers: Array[Dictionary] = []
	var failures: Array[Dictionary] = []
	for item_id_key in actor.inventory.keys().duplicate():
		var item_id: String = _inventory_entries.normalize_content_id(item_id_key)
		var count: int = max(0, int(actor.inventory.get(item_id_key, 0)))
		if item_id.is_empty() or count <= 0:
			continue
		var result: Dictionary = store_item_in_container(simulation, actor_id, normalized_container_id, item_id, count, item_library)
		if bool(result.get("success", false)):
			transfers.append(result)
		else:
			failures.append(result)
	return _bulk_container_result(simulation, actor_id, normalized_container_id, "store_all", transfers, failures)


func _bulk_container_result(simulation: RefCounted, actor_id: int, container_id: String, action: String, transfers: Array[Dictionary], failures: Array[Dictionary]) -> Dictionary:
	var transferred_count: int = _bulk_transfer_item_count(transfers)
	var result := {
		"success": not transfers.is_empty(),
		"partial_success": not transfers.is_empty() and not failures.is_empty(),
		"reason": "" if failures.is_empty() else str(_dictionary_or_empty(failures[0]).get("reason", "")),
		"action": action,
		"actor_id": actor_id,
		"container_id": container_id,
		"transfers": transfers,
		"failures": failures,
		"transfer_count": transfers.size(),
		"failed_count": failures.size(),
		"item_count": transferred_count,
	}
	if transfers.is_empty() and failures.is_empty():
		result["success"] = false
		result["reason"] = "container_empty" if action == "take_all" else "inventory_empty"
	if not failures.is_empty():
		var first_failure: Dictionary = _dictionary_or_empty(failures[0])
		for key in first_failure.keys():
			if not result.has(key):
				result[key] = first_failure[key]
	if not transfers.is_empty():
		simulation.emit_event("container_bulk_transferred", {
			"actor_id": actor_id,
			"container_id": container_id,
			"action": action,
			"transfer_count": transfers.size(),
			"failed_count": failures.size(),
			"item_count": transferred_count,
			"partial_success": not failures.is_empty(),
		})
	return result


func _bulk_transfer_item_count(transfers: Array[Dictionary]) -> int:
	var total := 0
	for transfer in transfers:
		total += max(0, int(_dictionary_or_empty(transfer).get("count", 0)))
	return total


func _sync_corpse_container_session(simulation: RefCounted, container_id: String, container: Dictionary) -> void:
	if simulation == null or not simulation.corpse_containers.has(container_id):
		return
	var corpse: Dictionary = _dictionary_or_empty(simulation.corpse_containers[container_id])
	corpse["inventory"] = _array_or_empty(container.get("inventory", [])).duplicate(true)
	corpse["money"] = max(0, int(container.get("money", corpse.get("money", 0))))
	for key in ["container_type", "container_origin", "map_id", "grid_position", "source_actor_id", "source_actor_definition_id", "source_actor_kind", "defeated_by_actor_id", "drop_item_id"]:
		if container.has(key):
			corpse[key] = container.get(key)
	simulation.corpse_containers[container_id] = corpse


func _container_permission(simulation: RefCounted, actor: RefCounted, actor_id: int, container_id: String, container: Dictionary, action: String) -> Dictionary:
	var base := {
		"success": true,
		"actor_id": actor_id,
		"container_id": container_id,
		"action": action,
	}
	var unlock_consumed: bool = bool(container.get("unlock_requirements_consumed", false))
	var required_item_ids: Array[String] = [] if unlock_consumed else _required_item_ids(container)
	var missing_item_ids: Array[String] = _missing_actor_items(actor, required_item_ids)
	if not missing_item_ids.is_empty():
		return _permission_failure(base, "container_key_missing", {
			"item_id": missing_item_ids[0],
			"missing_item_ids": missing_item_ids,
			"required_item_ids": required_item_ids,
		})
	var required_tool_ids: Array[String] = [] if unlock_consumed else _required_tool_ids(container)
	var missing_tool_ids: Array[String] = _missing_actor_items(actor, required_tool_ids)
	if not missing_tool_ids.is_empty():
		return _permission_failure(base, "container_tool_missing", {
			"item_id": missing_tool_ids[0],
			"missing_tool_ids": missing_tool_ids,
			"required_tool_ids": required_tool_ids,
		})
	var missing_durability_tools: Array[Dictionary] = [] if unlock_consumed else _missing_tool_durability(actor, _required_tool_requirements(container))
	if not missing_durability_tools.is_empty():
		return _permission_failure(base, "tool_durability_insufficient", {
			"item_id": str(_dictionary_or_empty(missing_durability_tools[0]).get("item_id", "")),
			"missing_tools": missing_durability_tools,
			"missing_durability_tools": missing_durability_tools,
			"required_tool_ids": required_tool_ids,
		})
	var has_unlock_requirements: bool = not required_item_ids.is_empty() or not required_tool_ids.is_empty()
	if bool(container.get("locked", false)) and not has_unlock_requirements:
		return _permission_failure(base, "container_locked", {})
	if action == "take" and not bool(container.get("allow_take", true)):
		return _permission_failure(base, "container_take_forbidden", {})
	if action == "store" and not bool(container.get("allow_store", true)):
		return _permission_failure(base, "container_store_forbidden", {})
	var quest_permission: Dictionary = _container_quest_permission(simulation, base, container)
	if not bool(quest_permission.get("success", false)):
		return quest_permission
	var owner_permission: Dictionary = _container_owner_permission(simulation, actor, actor_id, container_id, container, action)
	if not bool(owner_permission.get("success", false)):
		return owner_permission
	for key in owner_permission.keys():
		if key != "success":
			base[key] = owner_permission.get(key)
	for flag_id in _normalized_string_array(container.get("required_world_flags", [])):
		if not _simulation_world_flags(simulation).has(flag_id):
			return _permission_failure(base, "container_world_flag_missing", {
				"flag_id": flag_id,
				"required_world_flags": _normalized_string_array(container.get("required_world_flags", [])),
			})
	for flag_id in _normalized_string_array(container.get("blocked_world_flags", [])):
		if _simulation_world_flags(simulation).has(flag_id):
			return _permission_failure(base, "container_world_flag_blocked", {
				"flag_id": flag_id,
				"blocked_world_flags": _normalized_string_array(container.get("blocked_world_flags", [])),
			})
	return base


func _container_quest_permission(simulation: RefCounted, base: Dictionary, container: Dictionary) -> Dictionary:
	var active_quests: Dictionary = _simulation_active_quests(simulation)
	var completed_quests: Dictionary = _simulation_completed_quests(simulation)
	var required_active: Array[String] = _container_quest_ids(container, ["required_active_quest_ids", "required_active_quests"])
	for quest_id in required_active:
		if not active_quests.has(quest_id):
			return _permission_failure(base, "container_active_quest_missing", {
				"quest_id": quest_id,
				"required_active_quest_ids": required_active,
			})
	var required_completed: Array[String] = _container_quest_ids(container, ["required_completed_quest_ids", "required_completed_quests"])
	for quest_id in required_completed:
		if not completed_quests.has(quest_id):
			return _permission_failure(base, "container_completed_quest_missing", {
				"quest_id": quest_id,
				"required_completed_quest_ids": required_completed,
			})
	var blocked_active: Array[String] = _container_quest_ids(container, ["blocked_active_quest_ids", "blocked_active_quests"])
	for quest_id in blocked_active:
		if active_quests.has(quest_id):
			return _permission_failure(base, "container_active_quest_blocked", {
				"quest_id": quest_id,
				"blocked_active_quest_ids": blocked_active,
			})
	var blocked_completed: Array[String] = _container_quest_ids(container, ["blocked_completed_quest_ids", "blocked_completed_quests"])
	for quest_id in blocked_completed:
		if completed_quests.has(quest_id):
			return _permission_failure(base, "container_completed_quest_blocked", {
				"quest_id": quest_id,
				"blocked_completed_quest_ids": blocked_completed,
			})
	return base


func _container_quest_ids(container: Dictionary, keys: Array[String]) -> Array[String]:
	var output: Array[String] = []
	for key in keys:
		for quest_id in _normalized_string_array(container.get(key, [])):
			if not output.has(quest_id):
				output.append(quest_id)
	return output


func _container_owner_permission(simulation: RefCounted, actor: RefCounted, actor_id: int, container_id: String, container: Dictionary, action: String) -> Dictionary:
	var owner_actor_id: int = _container_owner_actor_id(simulation, container)
	var has_owner: bool = owner_actor_id > 0 or not str(container.get("owner_actor_definition_id", "")).strip_edges().is_empty()
	var is_owned: bool = bool(container.get("owned", false)) or bool(container.get("owner_restricted", false)) or has_owner and (container.has("owner_relationship_min") or container.has("owner_relationship_max") or container.has("required_owner_relationship_min") or container.has("required_owner_relationship_max"))
	var result := {
		"success": true,
		"container_id": container_id,
		"actor_id": actor_id,
		"action": action,
		"owned": is_owned,
		"owner_actor_id": owner_actor_id,
		"owner_actor_definition_id": str(container.get("owner_actor_definition_id", "")),
		"stealing": false,
	}
	if not is_owned:
		return result
	if _actor_is_container_owner(actor, owner_actor_id, str(container.get("owner_actor_definition_id", ""))):
		return result

	var score: float = _relationship_score(simulation, actor_id, owner_actor_id)
	result["relationship_score"] = score
	if _has_owner_relationship_min(container):
		var min_score: float = _owner_relationship_min(container)
		result["owner_relationship_min"] = min_score
		if score < min_score:
			return _permission_failure(result, "container_owner_relationship_too_low", {
				"relationship_score": score,
				"owner_relationship_min": min_score,
			})
	if _has_owner_relationship_max(container):
		var max_score: float = _owner_relationship_max(container)
		result["owner_relationship_max"] = max_score
		if score > max_score:
			return _permission_failure(result, "container_owner_relationship_too_high", {
				"relationship_score": score,
				"owner_relationship_max": max_score,
			})
	if action == "take":
		var relationship_gate: bool = _has_owner_relationship_min(container) or _has_owner_relationship_max(container)
		if not relationship_gate and not bool(container.get("allow_steal", container.get("allow_theft", false))):
			return _permission_failure(result, "container_owner_forbidden", {})
		result["stealing"] = bool(container.get("allow_steal", container.get("allow_theft", false))) and not relationship_gate
	return result


func _container_owner_actor_id(simulation: RefCounted, container: Dictionary) -> int:
	var explicit_id: int = int(container.get("owner_actor_id", 0))
	if explicit_id > 0:
		return explicit_id
	var definition_id := str(container.get("owner_actor_definition_id", "")).strip_edges()
	if definition_id.is_empty() or simulation == null or simulation.actor_registry == null:
		return 0
	for actor in simulation.actor_registry.actors():
		if actor != null and str(actor.definition_id) == definition_id:
			return int(actor.actor_id)
	return 0


func _actor_is_container_owner(actor: RefCounted, owner_actor_id: int, owner_definition_id: String) -> bool:
	if actor == null:
		return false
	if owner_actor_id > 0 and int(actor.actor_id) == owner_actor_id:
		return true
	return not owner_definition_id.strip_edges().is_empty() and str(actor.definition_id) == owner_definition_id


func _relationship_score(simulation: RefCounted, actor_id: int, target_actor_id: int) -> float:
	if target_actor_id <= 0:
		return 0.0
	if simulation != null and simulation.has_method("relationship_score"):
		return float(simulation.relationship_score(actor_id, target_actor_id))
	return 0.0


func _apply_container_steal_consequences(simulation: RefCounted, actor_id: int, owner_actor_id: int, container_id: String, container: Dictionary, item_id: String, count: int) -> Dictionary:
	var relationship_before: float = _relationship_score(simulation, actor_id, owner_actor_id)
	var relationship_after: float = relationship_before
	var configured_delta: float = _container_steal_relationship_delta(container)
	var relationship_result: Dictionary = {}
	if owner_actor_id > 0 and absf(configured_delta) > 0.001 and simulation != null and simulation.has_method("set_relationship_score"):
		relationship_result = simulation.set_relationship_score(actor_id, owner_actor_id, relationship_before + configured_delta, "container_steal:%s" % container_id)
		if bool(relationship_result.get("success", false)):
			relationship_after = float(relationship_result.get("score", relationship_before))
	var applied_delta: float = relationship_after - relationship_before
	var payload := {
		"actor_id": actor_id,
		"container_id": container_id,
		"owner_actor_id": owner_actor_id,
		"item_id": item_id,
		"count": count,
		"configured_relationship_delta": configured_delta,
		"relationship_delta": applied_delta,
		"relationship_before": relationship_before,
		"relationship_after": relationship_after,
		"relationship_changed": absf(applied_delta) > 0.001,
	}
	if not relationship_result.is_empty():
		payload["relationship_result"] = relationship_result.duplicate(true)
	if simulation != null and simulation.has_method("emit_event"):
		simulation.emit_event("container_stolen", payload.duplicate(true))
	return payload


func _container_steal_relationship_delta(container: Dictionary) -> float:
	if container.has("steal_relationship_delta"):
		return float(container.get("steal_relationship_delta", 0.0))
	if container.has("theft_relationship_delta"):
		return float(container.get("theft_relationship_delta", 0.0))
	return 0.0


func _copy_steal_consequence(target: Dictionary, consequence: Dictionary) -> void:
	if consequence.is_empty():
		return
	for key in [
		"configured_relationship_delta",
		"relationship_delta",
		"relationship_before",
		"relationship_after",
		"relationship_changed",
	]:
		target[key] = consequence.get(key)


func _consume_container_unlock_requirements(simulation: RefCounted, actor: RefCounted, actor_id: int, container_id: String, container: Dictionary, action: String) -> Dictionary:
	if not bool(container.get("locked", false)) or bool(container.get("unlock_requirements_consumed", false)):
		return {"success": true, "consumed_unlock_requirements": []}
	var consumed: Array[Dictionary] = []
	if _container_consumes_required_items(container):
		var item_count: int = _container_required_item_consume_count(container)
		for item_id in _required_item_ids(container):
			var consume_result: Dictionary = _consume_actor_inventory_requirement(actor, item_id, item_count, "item")
			if not bool(consume_result.get("success", false)):
				return _permission_failure({
					"success": true,
					"actor_id": actor_id,
					"container_id": container_id,
					"action": action,
				}, "container_key_missing", {
					"item_id": item_id,
					"required_item_ids": _required_item_ids(container),
					"consume_count": item_count,
				})
			consumed.append(consume_result)
	var durable_tools: Array[Dictionary] = _container_durable_tool_consumption_requirements(actor, container)
	for tool in durable_tools:
		var durability_result: Dictionary = _consume_actor_tool_durability(actor, str(tool.get("item_id", "")), float(tool.get("durability_cost", 0.0)), "tool")
		if not bool(durability_result.get("success", false)):
			return _permission_failure({
				"success": true,
				"actor_id": actor_id,
				"container_id": container_id,
				"action": action,
			}, "tool_durability_insufficient", {
				"item_id": str(tool.get("item_id", "")),
				"required_tool_ids": _required_tool_ids(container),
				"durability_cost": float(tool.get("durability_cost", 0.0)),
				"available_durability": float(durability_result.get("durability_before", 0.0)),
			})
		consumed.append(durability_result)
	if _container_consumes_required_tools(container):
		var tool_count: int = _container_required_tool_consume_count(container)
		for tool_id in _required_tool_ids(container):
			if _tool_requirement_has_durability(container, tool_id):
				continue
			var consume_result: Dictionary = _consume_actor_inventory_requirement(actor, tool_id, tool_count, "tool")
			if not bool(consume_result.get("success", false)):
				return _permission_failure({
					"success": true,
					"actor_id": actor_id,
					"container_id": container_id,
					"action": action,
				}, "container_tool_missing", {
					"item_id": tool_id,
					"required_tool_ids": _required_tool_ids(container),
					"consume_count": tool_count,
				})
			consumed.append(consume_result)
	if consumed.is_empty():
		return {"success": true, "consumed_unlock_requirements": []}
	container["locked"] = false
	container["unlock_requirements_consumed"] = true
	container["unlock_consumed_actor_id"] = actor_id
	container["unlock_consumed_action"] = action
	for entry in consumed:
		var event_payload: Dictionary = _dictionary_or_empty(entry).duplicate(true)
		event_payload["actor_id"] = actor_id
		event_payload["target_kind"] = "container"
		event_payload["container_id"] = container_id
		event_payload["target_id"] = container_id
		event_payload["action"] = action
		if simulation != null and simulation.has_method("emit_event"):
			simulation.emit_event("unlock_requirement_consumed", event_payload)
	if simulation != null and simulation.has_method("emit_event"):
		simulation.emit_event("container_unlocked", {
			"actor_id": actor_id,
			"container_id": container_id,
			"target_id": container_id,
			"action": action,
			"consumed_unlock_requirements": consumed.duplicate(true),
		})
	return {
		"success": true,
		"unlock_requirements_consumed": true,
		"consumed_unlock_requirements": consumed,
	}


func _consume_actor_inventory_requirement(actor: RefCounted, item_id: String, count: int, requirement_kind: String) -> Dictionary:
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var consume_count: int = max(1, count)
	var before_count: int = int(actor.inventory.get(normalized_item_id, 0)) if actor != null else 0
	if actor == null or normalized_item_id.is_empty() or before_count < consume_count:
		return {
			"success": false,
			"item_id": normalized_item_id,
			"count": consume_count,
			"inventory_before": before_count,
			"requirement_kind": requirement_kind,
		}
	_inventory_entries.add_actor_item(actor, normalized_item_id, -consume_count)
	return {
		"success": true,
		"item_id": normalized_item_id,
		"count": consume_count,
		"inventory_before": before_count,
		"inventory_after": int(actor.inventory.get(normalized_item_id, 0)),
		"requirement_kind": requirement_kind,
	}


func _consume_actor_tool_durability(actor: RefCounted, item_id: String, durability_cost: float, requirement_kind: String) -> Dictionary:
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var cost: float = max(0.0, durability_cost)
	var before_durability: float = _actor_tool_durability(actor, normalized_item_id)
	if actor == null or normalized_item_id.is_empty() or cost <= 0.0 or before_durability < cost:
		return {
			"success": false,
			"item_id": normalized_item_id,
			"count": 0,
			"durability_cost": cost,
			"durability_before": before_durability,
			"requirement_kind": requirement_kind,
		}
	var after_durability: float = max(0.0, before_durability - cost)
	actor.tool_durability[normalized_item_id] = after_durability
	return {
		"success": true,
		"item_id": normalized_item_id,
		"count": 0,
		"durability_cost": cost,
		"durability_before": before_durability,
		"durability_after": after_durability,
		"requirement_kind": requirement_kind,
	}


func _actor_tool_durability(actor: RefCounted, item_id: String) -> float:
	if actor == null or item_id.is_empty():
		return 0.0
	if actor.tool_durability.has(item_id):
		return max(0.0, float(actor.tool_durability.get(item_id, 0.0)))
	return 100.0


func _container_consumes_required_items(container: Dictionary) -> bool:
	return bool(container.get("consume_required_items_on_unlock", container.get("consume_required_items", container.get("consume_keys_on_unlock", false))))


func _container_consumes_required_tools(container: Dictionary) -> bool:
	return bool(container.get("consume_required_tools_on_unlock", container.get("consume_required_tools", container.get("consume_tools_on_unlock", false))))


func _container_durable_tool_consumption_requirements(actor: RefCounted, container: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for requirement in _required_tool_requirements(container):
		var tool_id := str(requirement.get("item_id", ""))
		var durability_cost: float = max(0.0, float(requirement.get("durability_cost", 0.0)))
		if tool_id.is_empty() or durability_cost <= 0.0:
			continue
		output.append({
			"item_id": tool_id,
			"count": 0,
			"durability_cost": durability_cost,
			"available_durability": _actor_tool_durability(actor, tool_id),
			"requirement_kind": "tool",
		})
	return output


func _container_required_item_consume_count(container: Dictionary) -> int:
	return max(1, int(container.get("required_item_consume_count", container.get("unlock_item_consume_count", container.get("key_consume_count", 1)))))


func _container_required_tool_consume_count(container: Dictionary) -> int:
	return max(1, int(container.get("required_tool_consume_count", container.get("unlock_tool_consume_count", container.get("tool_consume_count", 1)))))


func _copy_unlock_consumption(target: Dictionary, unlock_consumption: Dictionary) -> void:
	if unlock_consumption.is_empty():
		return
	var consumed: Array = _array_or_empty(unlock_consumption.get("consumed_unlock_requirements", []))
	target["unlock_requirements_consumed"] = not consumed.is_empty()
	target["consumed_unlock_requirements"] = consumed.duplicate(true)


func _has_owner_relationship_min(container: Dictionary) -> bool:
	return container.has("owner_relationship_min") or container.has("required_owner_relationship_min")


func _has_owner_relationship_max(container: Dictionary) -> bool:
	return container.has("owner_relationship_max") or container.has("required_owner_relationship_max")


func _owner_relationship_min(container: Dictionary) -> float:
	if container.has("owner_relationship_min"):
		return float(container.get("owner_relationship_min", -100.0))
	return float(container.get("required_owner_relationship_min", -100.0))


func _owner_relationship_max(container: Dictionary) -> float:
	if container.has("owner_relationship_max"):
		return float(container.get("owner_relationship_max", 100.0))
	return float(container.get("required_owner_relationship_max", 100.0))


func _container_capacity_check(container_id: String, container: Dictionary, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	var inventory: Array = _array_or_empty(container.get("inventory", []))
	var additions: Array = [{"item_id": item_id, "count": count}]
	var current_weight: float = _inventory_entries_weight(inventory, item_library)
	var added_weight: float = _inventory_capacity.entries_weight(additions, item_library)
	var projected_weight: float = current_weight + added_weight
	var max_weight: float = _container_max_weight(container)
	if max_weight >= 0.0 and projected_weight > max_weight + 0.001:
		return {
			"success": false,
			"reason": "container_over_capacity",
			"limit_kind": "weight",
			"container_id": container_id,
			"item_id": item_id,
			"count": count,
			"current_weight": current_weight,
			"added_weight": added_weight,
			"projected_weight": projected_weight,
			"max_weight": max_weight,
			"remaining_weight": max_weight - current_weight,
			"over_by": projected_weight - max_weight,
		}

	var current_item_count: int = _container_item_count(inventory)
	var projected_item_count: int = current_item_count + max(0, count)
	var max_items: int = _container_max_int(container, ["max_items", "max_item_count", "item_capacity"])
	if max_items >= 0 and projected_item_count > max_items:
		return {
			"success": false,
			"reason": "container_over_capacity",
			"limit_kind": "items",
			"container_id": container_id,
			"item_id": item_id,
			"count": count,
			"current_item_count": current_item_count,
			"projected_item_count": projected_item_count,
			"max_items": max_items,
			"over_by": projected_item_count - max_items,
		}

	var current_stack_count: int = _container_stack_count(inventory)
	var projected_stack_count: int = current_stack_count + 1
	var max_stacks: int = _container_max_int(container, ["max_stacks", "max_stack_count", "slot_capacity", "max_slots"])
	if max_stacks >= 0 and projected_stack_count > max_stacks:
		return {
			"success": false,
			"reason": "container_over_capacity",
			"limit_kind": "stacks",
			"container_id": container_id,
			"item_id": item_id,
			"count": count,
			"current_stack_count": current_stack_count,
			"projected_stack_count": projected_stack_count,
			"max_stacks": max_stacks,
			"over_by": projected_stack_count - max_stacks,
		}
	return {
		"success": true,
		"current_weight": current_weight,
		"added_weight": added_weight,
		"projected_weight": projected_weight,
		"max_weight": max_weight,
		"current_item_count": current_item_count,
		"projected_item_count": projected_item_count,
		"current_stack_count": current_stack_count,
		"projected_stack_count": projected_stack_count,
	}


func _inventory_entries_weight(entries: Array, item_library: Dictionary) -> float:
	var normalized_entries: Array[Dictionary] = []
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var normalized_item_id: String = _inventory_entries.normalize_content_id(entry_data.get("item_id", ""))
		var entry_count: int = max(0, int(entry_data.get("count", 0)))
		if normalized_item_id.is_empty() or entry_count <= 0:
			continue
		normalized_entries.append({
			"item_id": normalized_item_id,
			"count": entry_count,
		})
	return _inventory_capacity.entries_weight(normalized_entries, item_library)


func _container_item_count(entries: Array) -> int:
	var total := 0
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		total += max(0, int(entry_data.get("count", 0)))
	return total


func _container_stack_count(entries: Array) -> int:
	var total := 0
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var normalized_item_id: String = _inventory_entries.normalize_content_id(entry_data.get("item_id", ""))
		if normalized_item_id.is_empty() or int(entry_data.get("count", 0)) <= 0:
			continue
		total += 1
	return total


func _container_max_weight(container: Dictionary) -> float:
	for key in ["max_weight", "max_container_weight", "weight_capacity"]:
		if container.has(key):
			return max(0.0, float(container.get(key, 0.0)))
	return -1.0


func _container_max_int(container: Dictionary, keys: Array[String]) -> int:
	for key in keys:
		if container.has(key):
			return max(0, int(container.get(key, 0)))
	return -1


func _required_item_ids(container: Dictionary) -> Array[String]:
	var output: Array[String] = []
	_append_unique_normalized(output, container.get("required_item_ids", []))
	_append_unique_normalized(output, container.get("required_items", []))
	return output


func _required_tool_ids(container: Dictionary) -> Array[String]:
	var output: Array[String] = []
	_append_unique_normalized(output, container.get("required_tool_ids", []))
	_append_unique_normalized(output, container.get("required_tools", []))
	return output


func _required_tool_requirements(container: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	_append_tool_requirements(output, container.get("required_tool_ids", []), container)
	_append_tool_requirements(output, container.get("required_tools", []), container)
	return output


func _append_tool_requirements(output: Array[Dictionary], value: Variant, container: Dictionary) -> void:
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_tool_requirements(output, entry, container)
		return
	var requirement: Dictionary = _tool_requirement(value, container)
	var tool_id := str(requirement.get("item_id", ""))
	if tool_id.is_empty():
		return
	for index in range(output.size()):
		var existing: Dictionary = _dictionary_or_empty(output[index])
		if str(existing.get("item_id", "")) != tool_id:
			continue
		existing["durability_cost"] = max(float(existing.get("durability_cost", 0.0)), float(requirement.get("durability_cost", 0.0)))
		output[index] = existing
		return
	output.append(requirement)


func _tool_requirement(value: Variant, container: Dictionary) -> Dictionary:
	var data: Dictionary = _dictionary_or_empty(value)
	var raw_id: Variant = value
	if not data.is_empty():
		raw_id = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var durability_cost: float = float(data.get("durability_cost", data.get("tool_durability_cost", data.get("unlock_tool_durability_cost", data.get("required_tool_durability_cost", container.get("tool_durability_cost", container.get("unlock_tool_durability_cost", 0.0)))))))
	return {
		"item_id": _inventory_entries.normalize_content_id(raw_id),
		"durability_cost": max(0.0, durability_cost),
	}


func _missing_tool_durability(actor: RefCounted, tool_requirements: Array[Dictionary]) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for tool in tool_requirements:
		var tool_id := str(tool.get("item_id", ""))
		var durability_cost: float = max(0.0, float(tool.get("durability_cost", 0.0)))
		if tool_id.is_empty() or durability_cost <= 0.0:
			continue
		var available_durability: float = _actor_tool_durability(actor, tool_id)
		if available_durability >= durability_cost:
			continue
		missing.append({
			"item_id": tool_id,
			"available_durability": available_durability,
			"required_durability": durability_cost,
			"durability_cost": durability_cost,
		})
	return missing


func _tool_requirement_has_durability(container: Dictionary, tool_id: String) -> bool:
	for requirement in _required_tool_requirements(container):
		if str(requirement.get("item_id", "")) == tool_id and float(requirement.get("durability_cost", 0.0)) > 0.0:
			return true
	return false


func _missing_actor_items(actor: RefCounted, item_ids: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for item_id in item_ids:
		if _actor_has_item(actor, item_id):
			continue
		missing.append(item_id)
	return missing


func _actor_has_item(actor: RefCounted, item_id: String) -> bool:
	if actor == null or item_id.is_empty():
		return false
	if int(actor.inventory.get(item_id, 0)) > 0:
		return true
	for slot_id in actor.equipment.keys():
		if _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) == item_id:
			return true
	return false


func _append_unique_normalized(output: Array[String], value: Variant) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		_append_one_normalized(output, value)
		return
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_one_normalized(output, entry)
		return
	_append_one_normalized(output, value)


func _append_one_normalized(output: Array[String], value: Variant) -> void:
	var raw_value: Variant = value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = _dictionary_or_empty(value)
		raw_value = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var normalized_entry: String = _inventory_entries.normalize_content_id(raw_value)
	if normalized_entry.is_empty() or output.has(normalized_entry):
		return
	output.append(normalized_entry)


func _permission_failure(base: Dictionary, reason: String, extra: Dictionary) -> Dictionary:
	var output: Dictionary = base.duplicate(true)
	output["success"] = false
	output["reason"] = reason
	for key in extra.keys():
		output[key] = extra[key]
	return output


func _simulation_world_flags(simulation: RefCounted) -> Dictionary:
	if simulation != null:
		return _dictionary_or_empty(simulation.get("world_flags"))
	return {}


func _simulation_active_quests(simulation: RefCounted) -> Dictionary:
	if simulation != null:
		return _dictionary_or_empty(simulation.get("active_quests"))
	return {}


func _simulation_completed_quests(simulation: RefCounted) -> Dictionary:
	if simulation != null:
		return _dictionary_or_empty(simulation.get("completed_quests"))
	return {}


func _normalized_string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(value) == TYPE_STRING:
		var normalized_value: String = str(value).strip_edges()
		if not normalized_value.is_empty():
			output.append(normalized_value)
		return output
	for entry in _array_or_empty(value):
		var normalized_entry: String = str(entry).strip_edges()
		if not normalized_entry.is_empty():
			output.append(normalized_entry)
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
