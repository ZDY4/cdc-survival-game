extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

var _inventory_entries := InventoryEntries.new()


func toggle(simulation: RefCounted, actor_id: int, door_id: String) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "door_id": door_id}
	var target: Dictionary = _dictionary_or_empty(simulation.map_interaction_targets.get(door_id, {}))
	if target.is_empty():
		return {"success": false, "reason": "unknown_door", "door_id": door_id}
	var door: Dictionary = _dictionary_or_empty(target.get("door", {}))
	if door.is_empty():
		return {"success": false, "reason": "target_not_door", "door_id": door_id}
	var permission: Dictionary = door_permission(actor, actor_id, door_id, door)
	if not bool(permission.get("success", false)):
		return permission

	var current_state: Dictionary = _dictionary_or_empty(simulation.door_states.get(door_id, door))
	var is_open := bool(current_state.get("is_open", door.get("is_open", false)))
	var unlock_consumption: Dictionary = {}
	if not is_open:
		unlock_consumption = consume_unlock_requirements(simulation, actor, actor_id, door_id, current_state, door)
		if not bool(unlock_consumption.get("success", false)):
			return unlock_consumption
	var consumed_unlock_requirements: Array = _array_or_empty(unlock_consumption.get("consumed_unlock_requirements", []))
	var next_state: Dictionary = door.duplicate(true)
	for key in runtime_field_keys():
		if current_state.has(key):
			next_state[key] = current_state.get(key)
	next_state["is_open"] = not is_open
	next_state["locked"] = bool(current_state.get("locked", door.get("locked", false)))
	if not consumed_unlock_requirements.is_empty():
		next_state["locked"] = false
		next_state["unlock_requirements_consumed"] = true
		next_state["unlock_consumed_actor_id"] = actor_id
	next_state["blocks_movement"] = not bool(next_state.get("is_open", false))
	next_state["blocks_sight"] = not bool(next_state.get("is_open", false)) and bool(next_state.get("blocks_sight_when_closed", true))
	simulation.door_states[door_id] = next_state
	simulation.emit_event("door_toggled", {
		"actor_id": actor_id,
		"door_id": door_id,
		"target_id": door_id,
		"is_open": bool(next_state.get("is_open", false)),
		"locked": bool(next_state.get("locked", false)),
		"blocks_movement": bool(next_state.get("blocks_movement", false)),
		"blocks_sight": bool(next_state.get("blocks_sight", false)),
		"unlock_requirements_consumed": not consumed_unlock_requirements.is_empty(),
		"consumed_unlock_requirements": consumed_unlock_requirements.duplicate(true),
	})
	return {
		"success": true,
		"door_id": door_id,
		"is_open": bool(next_state.get("is_open", false)),
		"door": next_state.duplicate(true),
		"unlock_requirements_consumed": not consumed_unlock_requirements.is_empty(),
		"consumed_unlock_requirements": consumed_unlock_requirements.duplicate(true),
	}


func door_permission(actor: RefCounted, actor_id: int, door_id: String, door: Dictionary) -> Dictionary:
	var base := {
		"success": true,
		"actor_id": actor_id,
		"door_id": door_id,
	}
	var unlock_consumed: bool = bool(door.get("unlock_requirements_consumed", false))
	var required_item_ids: Array[String] = [] if unlock_consumed else required_item_ids(door)
	var missing_item_ids: Array[String] = missing_actor_items(actor, required_item_ids)
	if not missing_item_ids.is_empty():
		return permission_failure(base, "door_key_missing", {
			"item_id": missing_item_ids[0],
			"missing_item_ids": missing_item_ids,
			"required_item_ids": required_item_ids,
		})
	var required_tool_ids: Array[String] = [] if unlock_consumed else required_tool_ids(door)
	var missing_tool_ids: Array[String] = missing_actor_items(actor, required_tool_ids)
	if not missing_tool_ids.is_empty():
		return permission_failure(base, "door_tool_missing", {
			"item_id": missing_tool_ids[0],
			"missing_tool_ids": missing_tool_ids,
			"required_tool_ids": required_tool_ids,
		})
	var missing_durability_tools: Array[Dictionary] = [] if unlock_consumed else missing_door_tool_durability(actor, required_tool_requirements(door))
	if not missing_durability_tools.is_empty():
		return permission_failure(base, "tool_durability_insufficient", {
			"item_id": str(_dictionary_or_empty(missing_durability_tools[0]).get("item_id", "")),
			"missing_tools": missing_durability_tools,
			"missing_durability_tools": missing_durability_tools,
			"required_tool_ids": required_tool_ids,
		})
	var has_unlock_requirements: bool = not required_item_ids.is_empty() or not required_tool_ids.is_empty()
	if bool(door.get("locked", false)) and not has_unlock_requirements:
		return permission_failure(base, "door_locked", {})
	return base


func runtime_field_keys() -> Array[String]:
	return [
		"required_item_ids",
		"required_items",
		"required_tool_ids",
		"required_tools",
		"consume_required_items_on_unlock",
		"consume_required_tools_on_unlock",
		"consume_required_items",
		"consume_required_tools",
		"consume_keys_on_unlock",
		"consume_tools_on_unlock",
		"required_item_consume_count",
		"required_tool_consume_count",
		"unlock_item_consume_count",
		"unlock_tool_consume_count",
		"key_consume_count",
		"tool_consume_count",
		"tool_durability_cost",
		"unlock_tool_durability_cost",
		"required_tool_durability_cost",
		"unlock_requirements_consumed",
		"unlock_consumed_actor_id",
	]


func consume_unlock_requirements(
	simulation: RefCounted,
	actor: RefCounted,
	actor_id: int,
	door_id: String,
	current_state: Dictionary,
	door: Dictionary
) -> Dictionary:
	var source: Dictionary = door.duplicate(true)
	for key in runtime_field_keys():
		if current_state.has(key):
			source[key] = current_state.get(key)
	if not bool(source.get("locked", false)) or bool(source.get("unlock_requirements_consumed", false)):
		return {"success": true, "consumed_unlock_requirements": []}
	var consumed: Array[Dictionary] = []
	if door_consumes_required_items(source):
		var item_count: int = door_required_item_consume_count(source)
		for item_id in required_item_ids(source):
			var consume_result: Dictionary = consume_actor_inventory_requirement(actor, item_id, item_count, "item")
			if not bool(consume_result.get("success", false)):
				return permission_failure({
					"success": true,
					"actor_id": actor_id,
					"door_id": door_id,
				}, "door_key_missing", {
					"item_id": item_id,
					"required_item_ids": required_item_ids(source),
					"consume_count": item_count,
				})
			consumed.append(consume_result)
	var durable_tools: Array[Dictionary] = door_durable_tool_consumption_requirements(actor, source)
	for tool in durable_tools:
		var durability_result: Dictionary = consume_actor_tool_durability(actor, str(tool.get("item_id", "")), float(tool.get("durability_cost", 0.0)), "tool")
		if not bool(durability_result.get("success", false)):
			return permission_failure({
				"success": true,
				"actor_id": actor_id,
				"door_id": door_id,
			}, "tool_durability_insufficient", {
				"item_id": str(tool.get("item_id", "")),
				"required_tool_ids": required_tool_ids(source),
				"durability_cost": float(tool.get("durability_cost", 0.0)),
				"available_durability": float(durability_result.get("durability_before", 0.0)),
			})
		consumed.append(durability_result)
	if door_consumes_required_tools(source):
		var tool_count: int = door_required_tool_consume_count(source)
		for tool_id in required_tool_ids(source):
			if door_tool_requirement_has_durability(source, tool_id):
				continue
			var consume_result: Dictionary = consume_actor_inventory_requirement(actor, tool_id, tool_count, "tool")
			if not bool(consume_result.get("success", false)):
				return permission_failure({
					"success": true,
					"actor_id": actor_id,
					"door_id": door_id,
				}, "door_tool_missing", {
					"item_id": tool_id,
					"required_tool_ids": required_tool_ids(source),
					"consume_count": tool_count,
				})
			consumed.append(consume_result)
	if consumed.is_empty():
		return {"success": true, "consumed_unlock_requirements": []}
	for entry in consumed:
		var event_payload: Dictionary = _dictionary_or_empty(entry).duplicate(true)
		event_payload["actor_id"] = actor_id
		event_payload["target_kind"] = "door"
		event_payload["door_id"] = door_id
		event_payload["target_id"] = door_id
		simulation.emit_event("unlock_requirement_consumed", event_payload)
	simulation.emit_event("door_unlocked", {
		"actor_id": actor_id,
		"door_id": door_id,
		"target_id": door_id,
		"consumed_unlock_requirements": consumed.duplicate(true),
	})
	return {
		"success": true,
		"unlock_requirements_consumed": true,
		"consumed_unlock_requirements": consumed,
	}


func consume_actor_inventory_requirement(actor: RefCounted, item_id: String, count: int, requirement_kind: String) -> Dictionary:
	var normalized_item_id: String = normalize_content_id(item_id)
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


func consume_actor_tool_durability(actor: RefCounted, item_id: String, durability_cost: float, requirement_kind: String) -> Dictionary:
	var normalized_item_id: String = normalize_content_id(item_id)
	var cost: float = max(0.0, durability_cost)
	var before_durability: float = actor_tool_durability(actor, normalized_item_id)
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


func door_consumes_required_items(door: Dictionary) -> bool:
	return bool(door.get("consume_required_items_on_unlock", door.get("consume_required_items", door.get("consume_keys_on_unlock", false))))


func door_consumes_required_tools(door: Dictionary) -> bool:
	return bool(door.get("consume_required_tools_on_unlock", door.get("consume_required_tools", door.get("consume_tools_on_unlock", false))))


func door_required_item_consume_count(door: Dictionary) -> int:
	return max(1, int(door.get("required_item_consume_count", door.get("unlock_item_consume_count", door.get("key_consume_count", 1)))))


func door_required_tool_consume_count(door: Dictionary) -> int:
	return max(1, int(door.get("required_tool_consume_count", door.get("unlock_tool_consume_count", door.get("tool_consume_count", 1)))))


func door_durable_tool_consumption_requirements(actor: RefCounted, door: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for requirement in required_tool_requirements(door):
		var tool_id := str(requirement.get("item_id", ""))
		var durability_cost: float = max(0.0, float(requirement.get("durability_cost", 0.0)))
		if tool_id.is_empty() or durability_cost <= 0.0:
			continue
		output.append({
			"item_id": tool_id,
			"count": 0,
			"durability_cost": durability_cost,
			"available_durability": actor_tool_durability(actor, tool_id),
			"requirement_kind": "tool",
		})
	return output


func required_item_ids(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	append_unique_normalized_item_id(output, value.get("required_item_ids", []))
	append_unique_normalized_item_id(output, value.get("required_items", []))
	return output


func required_tool_ids(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	append_unique_normalized_item_id(output, value.get("required_tool_ids", []))
	append_unique_normalized_item_id(output, value.get("required_tools", []))
	return output


func required_tool_requirements(value: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	append_tool_requirements(output, value.get("required_tool_ids", []), value)
	append_tool_requirements(output, value.get("required_tools", []), value)
	return output


func append_tool_requirements(output: Array[Dictionary], value: Variant, source: Dictionary) -> void:
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			append_tool_requirements(output, entry, source)
		return
	var requirement: Dictionary = tool_requirement(value, source)
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


func tool_requirement(value: Variant, source: Dictionary) -> Dictionary:
	var data: Dictionary = _dictionary_or_empty(value)
	var raw_id: Variant = value
	if not data.is_empty():
		raw_id = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var durability_cost: float = float(data.get("durability_cost", data.get("tool_durability_cost", data.get("unlock_tool_durability_cost", data.get("required_tool_durability_cost", source.get("tool_durability_cost", source.get("unlock_tool_durability_cost", 0.0)))))))
	return {
		"item_id": normalize_content_id(raw_id),
		"durability_cost": max(0.0, durability_cost),
	}


func missing_door_tool_durability(actor: RefCounted, tool_requirements: Array[Dictionary]) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for tool in tool_requirements:
		var tool_id := str(tool.get("item_id", ""))
		var durability_cost: float = max(0.0, float(tool.get("durability_cost", 0.0)))
		if tool_id.is_empty() or durability_cost <= 0.0:
			continue
		var available_durability: float = actor_tool_durability(actor, tool_id)
		if available_durability >= durability_cost:
			continue
		missing.append({
			"item_id": tool_id,
			"available_durability": available_durability,
			"required_durability": durability_cost,
			"durability_cost": durability_cost,
		})
	return missing


func door_tool_requirement_has_durability(source: Dictionary, tool_id: String) -> bool:
	for requirement in required_tool_requirements(source):
		if str(requirement.get("item_id", "")) == tool_id and float(requirement.get("durability_cost", 0.0)) > 0.0:
			return true
	return false


func missing_actor_items(actor: RefCounted, item_ids: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for item_id in item_ids:
		if actor_has_item(actor, item_id):
			continue
		missing.append(item_id)
	return missing


func actor_has_item(actor: RefCounted, item_id: String) -> bool:
	if actor == null or item_id.is_empty():
		return false
	if int(actor.inventory.get(item_id, 0)) > 0:
		return true
	for slot_id in actor.equipment.keys():
		if normalize_content_id(actor.equipment.get(slot_id, "")) == item_id:
			return true
	return false


func append_unique_normalized_item_id(output: Array[String], value: Variant) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		append_one_normalized_item_id(output, value)
		return
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			append_one_normalized_item_id(output, entry)
		return
	append_one_normalized_item_id(output, value)


func append_one_normalized_item_id(output: Array[String], value: Variant) -> void:
	var raw_value: Variant = value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = _dictionary_or_empty(value)
		raw_value = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var normalized_entry: String = normalize_content_id(raw_value)
	if normalized_entry.is_empty() or output.has(normalized_entry):
		return
	output.append(normalized_entry)


func normalize_content_id(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		var float_value: float = value
		if is_equal_approx(float_value, roundf(float_value)):
			return str(int(float_value))
	if typeof(value) == TYPE_INT:
		return str(value)
	return str(value).strip_edges()


func permission_failure(base: Dictionary, reason: String, extra: Dictionary) -> Dictionary:
	var output: Dictionary = base.duplicate(true)
	output["success"] = false
	output["reason"] = reason
	for key in extra.keys():
		output[key] = extra[key]
	return output


func actor_tool_durability(actor: RefCounted, tool_id: String) -> float:
	if actor == null or tool_id.is_empty():
		return 0.0
	if actor.tool_durability.has(tool_id):
		return max(0.0, float(actor.tool_durability.get(tool_id, 0.0)))
	return 100.0


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
