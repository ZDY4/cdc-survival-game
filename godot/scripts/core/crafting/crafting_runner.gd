extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const InventoryCapacity = preload("res://scripts/core/economy/inventory_capacity.gd")

var _inventory_entries := InventoryEntries.new()
var _inventory_capacity := InventoryCapacity.new()


func craft_recipe(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, recipe_id: String, recipe_library: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	var validation: Dictionary = validate_craft_recipe(simulation, progression_rules, actor_id, recipe_id, recipe_library, crafting_context)
	if not bool(validation.get("success", false)):
		return validation
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var materials: Array[Dictionary] = _array_or_empty(validation.get("materials", []))
	var tool_consumption: Array[Dictionary] = _array_or_empty(validation.get("tool_consumption", []))
	var output_item_id: String = str(validation.get("output_item_id", ""))
	var output_count: int = int(validation.get("output_count", 0))
	var tool_source_check: Dictionary = _tool_consumption_sources_available(simulation, actor, tool_consumption, simulation.item_library)
	if not bool(tool_source_check.get("success", false)):
		return tool_source_check
	var consumed_tools: Array[Dictionary] = _consume_recipe_tools(simulation, actor, tool_consumption)
	for material in materials:
		_inventory_entries.add_actor_item(actor, str(material.get("item_id", "")), -int(material.get("count", 0)))
	_inventory_entries.add_actor_item(actor, output_item_id, output_count, simulation.item_library)
	simulation.emit_event("recipe_crafted", {
		"actor_id": actor_id,
		"recipe_id": recipe_id,
		"output_item_id": output_item_id,
		"output_count": output_count,
		"craft_time": float(validation.get("craft_time", 0.0)),
		"experience_reward": int(validation.get("experience_reward", 0)),
		"consumed_tools": consumed_tools.duplicate(true),
	})
	if int(validation.get("experience_reward", 0)) > 0:
		simulation.grant_experience(actor_id, int(validation.get("experience_reward", 0)), "recipe:%s" % recipe_id)
	_mark_recipe_crafted(simulation, actor_id, recipe_id)
	return {
		"success": true,
		"recipe_id": recipe_id,
		"output_item_id": output_item_id,
		"output_count": output_count,
		"craft_time": float(validation.get("craft_time", 0.0)),
		"consumed_tools": consumed_tools,
	}


func validate_craft_recipe(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, recipe_id: String, recipe_library: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var record: Dictionary = _dictionary_or_empty(recipe_library.get(recipe_id, {}))
	if record.is_empty():
		return {"success": false, "reason": "unknown_recipe"}
	var recipe: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var unlock_check: Dictionary = _unlock_check(simulation, actor, recipe)
	if not bool(unlock_check.get("success", false)):
		return unlock_check
	var required_tools: Array[Dictionary] = _tool_requirements(_array_or_empty(recipe.get("required_tools", [])), recipe)
	var missing_tools: Array[Dictionary] = _missing_required_tools(actor, required_tools, simulation.item_library, crafting_context)
	if not missing_tools.is_empty():
		return {
			"success": false,
			"reason": "missing_tools",
			"missing_tools": missing_tools,
		}
	var missing_durability_tools: Array[Dictionary] = _missing_tool_durability(actor, required_tools, simulation.item_library)
	if not missing_durability_tools.is_empty():
		return {
			"success": false,
			"reason": "tool_durability_insufficient",
			"missing_tools": missing_durability_tools,
			"missing_durability_tools": missing_durability_tools,
		}
	var tool_consumption: Array[Dictionary] = _tool_consumption_requirements(actor, required_tools, crafting_context)
	var missing_consumable_tools: Array[Dictionary] = _missing_consumable_tools(tool_consumption, simulation.item_library)
	if not missing_consumable_tools.is_empty():
		return {
			"success": false,
			"reason": "missing_consumable_tools",
			"missing_consumable_tools": missing_consumable_tools,
		}
	var station_check: Dictionary = _station_check(actor, str(recipe.get("required_station", "none")), crafting_context)
	if not bool(station_check.get("success", false)):
		return station_check
	var skill_check: Dictionary = progression_rules.meets_skill_requirements(actor.progression, _dictionary_or_empty(recipe.get("skill_requirements", {})))
	if not bool(skill_check.get("success", false)):
		return {
			"success": false,
			"reason": "missing_skills",
			"missing_skills": skill_check.get("missing_skills", []),
		}

	var materials: Array[Dictionary] = _inventory_entries.normalize(recipe.get("materials", []))
	for material in materials:
		var material_id: String = str(material.get("item_id", ""))
		var required_count: int = int(material.get("count", 0))
		if int(actor.inventory.get(material_id, 0)) < required_count:
			return {
				"success": false,
				"reason": "materials_insufficient",
				"item_id": material_id,
				"required": required_count,
				"available": int(actor.inventory.get(material_id, 0)),
			}

	var output: Dictionary = _dictionary_or_empty(recipe.get("output", {}))
	var output_item_id: String = _inventory_entries.normalize_content_id(output.get("item_id", ""))
	var output_count: int = max(1, int(output.get("count", 1)))
	if output_item_id.is_empty():
		return {"success": false, "reason": "recipe_output_invalid"}
	var removals: Array[Dictionary] = materials.duplicate(true)
	for consumed_tool in tool_consumption:
		for source in _array_or_empty(consumed_tool.get("sources", [])):
			var source_data: Dictionary = _dictionary_or_empty(source)
			if str(source_data.get("source", "")) != "actor_inventory":
				continue
			removals.append({
				"item_id": str(consumed_tool.get("item_id", "")),
				"count": int(source_data.get("count", 0)),
			})
	var equipment_after_consumption: Dictionary = _equipment_after_tool_consumption(actor, tool_consumption)
	var capacity: Dictionary = _inventory_capacity.can_change_inventory(actor, simulation.item_library, [
		{"item_id": output_item_id, "count": output_count},
	], removals, equipment_after_consumption)
	if not bool(capacity.get("success", false)):
		capacity["recipe_id"] = recipe_id
		capacity["output_item_id"] = output_item_id
		capacity["output_count"] = output_count
		return capacity

	return {
		"success": true,
		"recipe_id": recipe_id,
		"materials": materials,
		"required_tools": required_tools,
		"tool_consumption": tool_consumption,
		"output_item_id": output_item_id,
		"output_count": output_count,
		"craft_time": float(recipe.get("craft_time", 0.0)),
		"experience_reward": int(recipe.get("experience_reward", 0)),
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _missing_required_tools(actor: RefCounted, required_tools: Array[Dictionary], item_library: Dictionary, crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for tool in required_tools:
		var tool_id: String = str(tool.get("item_id", ""))
		if tool_id.is_empty():
			continue
		var required_count: int = max(1, int(tool.get("required", 1)))
		var available_count: int = _actor_tool_available_count(actor, tool_id, crafting_context)
		if available_count >= required_count:
			continue
		missing.append({
			"item_id": tool_id,
			"name": _item_name(tool_id, item_library),
			"available": available_count,
			"required": required_count,
		})
	return missing


func _actor_has_tool(actor: RefCounted, tool_id: String, crafting_context: Dictionary = {}) -> bool:
	return _actor_tool_available_count(actor, tool_id, crafting_context) > 0


func _actor_tool_available_count(actor: RefCounted, tool_id: String, crafting_context: Dictionary = {}) -> int:
	if actor == null:
		return 0
	var count := 0
	if int(actor.inventory.get(tool_id, 0)) > 0:
		count += int(actor.inventory.get(tool_id, 0))
	for slot_id in actor.equipment.keys():
		if _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) == tool_id:
			count += 1
	for container in _array_or_empty(crafting_context.get("nearby_tool_containers", [])):
		var container_data: Dictionary = _dictionary_or_empty(container)
		count += _inventory_entries.count(_array_or_empty(container_data.get("inventory", [])), tool_id)
	return count


func _tool_requirements(required_tools: Array, recipe: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var recipe_consumes_tools: bool = _recipe_consumes_required_tools(recipe)
	var recipe_consume_count: int = _recipe_required_tool_consume_count(recipe)
	for tool in required_tools:
		var tool_data: Dictionary = _tool_requirement(tool)
		var tool_id := str(tool_data.get("item_id", ""))
		if tool_id.is_empty():
			continue
		if recipe_consumes_tools:
			tool_data["consume_on_craft"] = true
			if not tool_data.has("consume_count"):
				tool_data["consume_count"] = recipe_consume_count
		output.append(tool_data)
	return output


func _tool_requirement(tool: Variant) -> Dictionary:
	var data: Dictionary = _dictionary_or_empty(tool)
	var raw_id: Variant = tool
	if not data.is_empty():
		raw_id = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var required_count: int = max(1, int(data.get("required", data.get("required_count", data.get("count", 1)))))
	var consume_on_craft: bool = bool(data.get("consume_on_craft", data.get("consume", data.get("consumed", false))))
	var consume_count: int = max(1, int(data.get("consume_count", data.get("consumed_count", data.get("tool_consume_count", required_count)))))
	var output := {
		"item_id": _inventory_entries.normalize_content_id(raw_id),
		"required": required_count,
		"consume_on_craft": consume_on_craft,
		"consume_count": consume_count,
	}
	var durability_cost: float = float(data.get("durability_cost", data.get("tool_durability_cost", data.get("required_tool_durability_cost", 0.0))))
	if durability_cost > 0.0:
		output["durability_cost"] = durability_cost
	return output


func _tool_consumption_requirements(actor: RefCounted, required_tools: Array[Dictionary], crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for tool in required_tools:
		var durability_cost: float = max(0.0, float(tool.get("durability_cost", 0.0)))
		if not bool(tool.get("consume_on_craft", false)) and durability_cost <= 0.0:
			continue
		var tool_id := str(tool.get("item_id", ""))
		if tool_id.is_empty():
			continue
		var consume_count: int = max(1, int(tool.get("consume_count", tool.get("required", 1)))) if durability_cost <= 0.0 else 0
		var sources: Array[Dictionary] = []
		if durability_cost <= 0.0:
			sources = _tool_consumption_sources(actor, tool_id, consume_count, crafting_context)
		var requirement := {
			"item_id": tool_id,
			"count": consume_count,
			"available": _consumption_source_total(sources) if durability_cost <= 0.0 else (int(actor.inventory.get(tool_id, 0)) if actor != null else 0),
			"requirement_kind": "tool",
		}
		if not sources.is_empty():
			requirement["sources"] = sources
		if durability_cost > 0.0:
			requirement["durability_cost"] = durability_cost
			requirement["available_durability"] = _tool_durability(actor, tool_id)
		output.append(requirement)
	return output


func _missing_consumable_tools(tool_consumption: Array[Dictionary], item_library: Dictionary) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for tool in tool_consumption:
		var tool_id := str(tool.get("item_id", ""))
		if float(tool.get("durability_cost", 0.0)) > 0.0:
			continue
		var required_count: int = max(1, int(tool.get("count", 1)))
		var available_count: int = max(0, int(tool.get("available", 0)))
		if not tool_id.is_empty() and available_count >= required_count:
			continue
		missing.append({
			"item_id": tool_id,
			"name": _item_name(tool_id, item_library),
			"available": available_count,
			"required": required_count,
			"consume_on_craft": true,
		})
	return missing


func _missing_tool_durability(actor: RefCounted, required_tools: Array[Dictionary], item_library: Dictionary) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for tool in required_tools:
		var tool_id := str(tool.get("item_id", ""))
		var durability_cost: float = max(0.0, float(tool.get("durability_cost", 0.0)))
		if tool_id.is_empty() or durability_cost <= 0.0:
			continue
		var available_durability: float = _tool_durability(actor, tool_id)
		if available_durability >= durability_cost:
			continue
		missing.append({
			"item_id": tool_id,
			"name": _item_name(tool_id, item_library),
			"available_durability": available_durability,
			"required_durability": durability_cost,
			"durability_cost": durability_cost,
		})
	return missing


func _equipment_after_tool_consumption(actor: RefCounted, tool_consumption: Array[Dictionary]) -> Dictionary:
	if actor == null:
		return {}
	var equipment: Dictionary = _dictionary_or_empty(actor.equipment).duplicate(true)
	for tool in tool_consumption:
		for source in _array_or_empty(_dictionary_or_empty(tool).get("sources", [])):
			var source_data: Dictionary = _dictionary_or_empty(source)
			if str(source_data.get("source", "")) != "equipment":
				continue
			var slot_id := str(source_data.get("slot_id", ""))
			if not slot_id.is_empty():
				equipment.erase(slot_id)
	return equipment


func _tool_consumption_sources_available(simulation: RefCounted, actor: RefCounted, tool_consumption: Array[Dictionary], item_library: Dictionary) -> Dictionary:
	var missing: Array[Dictionary] = []
	for tool in tool_consumption:
		var tool_data: Dictionary = _dictionary_or_empty(tool)
		if float(tool_data.get("durability_cost", 0.0)) > 0.0:
			continue
		var tool_id := str(tool_data.get("item_id", ""))
		var required_count: int = max(1, int(tool_data.get("count", 1)))
		var available_count := 0
		for source in _array_or_empty(tool_data.get("sources", [])):
			available_count += _tool_source_available_count(simulation, actor, tool_id, _dictionary_or_empty(source))
		if not tool_id.is_empty() and available_count >= required_count:
			continue
		missing.append({
			"item_id": tool_id,
			"name": _item_name(tool_id, item_library),
			"available": available_count,
			"required": required_count,
			"consume_on_craft": true,
		})
	if missing.is_empty():
		return {"success": true}
	return {
		"success": false,
		"reason": "missing_consumable_tools",
		"missing_consumable_tools": missing,
	}


func _tool_source_available_count(simulation: RefCounted, actor: RefCounted, tool_id: String, source: Dictionary) -> int:
	match str(source.get("source", "")):
		"actor_inventory":
			return max(0, int(actor.inventory.get(tool_id, 0))) if actor != null else 0
		"equipment":
			var slot_id := str(source.get("slot_id", ""))
			if actor == null or slot_id.is_empty():
				return 0
			return 1 if _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) == tool_id else 0
		"nearby_container":
			var container_id := str(source.get("container_id", ""))
			if simulation == null or container_id.is_empty():
				return 0
			if simulation.container_sessions.has(container_id):
				return _inventory_entries.count(_array_or_empty(_dictionary_or_empty(simulation.container_sessions[container_id]).get("inventory", [])), tool_id)
			if simulation.corpse_containers.has(container_id):
				return _inventory_entries.count(_array_or_empty(_dictionary_or_empty(simulation.corpse_containers[container_id]).get("inventory", [])), tool_id)
			if simulation.map_interaction_targets.has(container_id):
				var target: Dictionary = _dictionary_or_empty(simulation.map_interaction_targets[container_id])
				return _inventory_entries.count(_array_or_empty(target.get("inventory", target.get("container_inventory", []))), tool_id)
	return 0


func _consume_recipe_tools(simulation: RefCounted, actor: RefCounted, tool_consumption: Array[Dictionary]) -> Array[Dictionary]:
	var consumed: Array[Dictionary] = []
	for tool in tool_consumption:
		var tool_id := str(tool.get("item_id", ""))
		var count: int = max(1, int(tool.get("count", 1)))
		var durability_cost: float = max(0.0, float(tool.get("durability_cost", 0.0)))
		if actor == null or tool_id.is_empty():
			continue
		if durability_cost > 0.0:
			var durability_before: float = _tool_durability(actor, tool_id)
			var durability_after: float = max(0.0, durability_before - durability_cost)
			actor.tool_durability[tool_id] = durability_after
			consumed.append({
				"item_id": tool_id,
				"count": 0,
				"durability_cost": durability_cost,
				"durability_before": durability_before,
				"durability_after": durability_after,
				"requirement_kind": "tool",
			})
			continue
		var remaining: int = count
		for source in _array_or_empty(tool.get("sources", [])):
			if remaining <= 0:
				break
			var source_data: Dictionary = _dictionary_or_empty(source)
			var source_count: int = mini(remaining, max(0, int(source_data.get("count", 0))))
			if source_count <= 0:
				continue
			var consumed_source: Dictionary = _consume_tool_from_source(simulation, actor, tool_id, source_count, source_data)
			if consumed_source.is_empty():
				continue
			remaining -= int(consumed_source.get("count", 0))
			consumed.append(consumed_source)
	return consumed


func _tool_consumption_sources(actor: RefCounted, tool_id: String, count: int, crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var remaining: int = max(0, count)
	if actor != null and remaining > 0:
		var actor_count: int = max(0, int(actor.inventory.get(tool_id, 0)))
		if actor_count > 0:
			var consumed_actor_count: int = mini(actor_count, remaining)
			output.append({
				"source": "actor_inventory",
				"count": consumed_actor_count,
				"inventory_before": actor_count,
			})
			remaining -= consumed_actor_count
	if actor != null and remaining > 0:
		var slot_ids: Array = actor.equipment.keys()
		slot_ids.sort()
		for slot_id in slot_ids:
			if remaining <= 0:
				break
			if _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) != tool_id:
				continue
			output.append({
				"source": "equipment",
				"slot_id": str(slot_id),
				"count": 1,
			})
			remaining -= 1
	if remaining > 0:
		for container in _array_or_empty(crafting_context.get("nearby_tool_containers", [])):
			if remaining <= 0:
				break
			var container_data: Dictionary = _dictionary_or_empty(container)
			var inventory: Array = _array_or_empty(container_data.get("inventory", []))
			var container_count: int = _inventory_entries.count(inventory, tool_id)
			if container_count <= 0:
				continue
			var consumed_container_count: int = mini(container_count, remaining)
			output.append({
				"source": "nearby_container",
				"container_id": str(container_data.get("container_id", "")),
				"display_name": str(container_data.get("display_name", container_data.get("container_id", ""))),
				"count": consumed_container_count,
				"inventory_before": container_count,
			})
			remaining -= consumed_container_count
	return output


func _consumption_source_total(sources: Array[Dictionary]) -> int:
	var total := 0
	for source in sources:
		total += max(0, int(_dictionary_or_empty(source).get("count", 0)))
	return total


func _consume_tool_from_source(simulation: RefCounted, actor: RefCounted, tool_id: String, count: int, source: Dictionary) -> Dictionary:
	match str(source.get("source", "")):
		"actor_inventory":
			var before_count: int = int(actor.inventory.get(tool_id, 0)) if actor != null else 0
			_inventory_entries.add_actor_item(actor, tool_id, -count)
			return {
				"item_id": tool_id,
				"count": count,
				"source": "actor_inventory",
				"inventory_before": before_count,
				"inventory_after": int(actor.inventory.get(tool_id, 0)) if actor != null else 0,
				"requirement_kind": "tool",
			}
		"equipment":
			var slot_id := str(source.get("slot_id", ""))
			if actor == null or slot_id.is_empty() or _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) != tool_id:
				return {}
			actor.equipment.erase(slot_id)
			return {
				"item_id": tool_id,
				"count": 1,
				"source": "equipment",
				"slot_id": slot_id,
				"requirement_kind": "tool",
			}
		"nearby_container":
			return _consume_tool_from_nearby_container(simulation, tool_id, count, source)
	return {}


func _consume_tool_from_nearby_container(simulation: RefCounted, tool_id: String, count: int, source: Dictionary) -> Dictionary:
	if simulation == null:
		return {}
	var container_id := str(source.get("container_id", ""))
	if container_id.is_empty():
		return {}
	var inventory: Array = []
	var persisted_target: Dictionary = {}
	var persisted_key := ""
	if simulation.container_sessions.has(container_id):
		persisted_target = _dictionary_or_empty(simulation.container_sessions[container_id]).duplicate(true)
		persisted_key = "container_sessions"
	elif simulation.corpse_containers.has(container_id):
		persisted_target = _dictionary_or_empty(simulation.corpse_containers[container_id]).duplicate(true)
		persisted_key = "corpse_containers"
	elif simulation.map_interaction_targets.has(container_id):
		persisted_target = _dictionary_or_empty(simulation.map_interaction_targets[container_id]).duplicate(true)
		persisted_key = "map_interaction_targets"
	else:
		return {}
	inventory = _array_or_empty(persisted_target.get("inventory", persisted_target.get("container_inventory", []))).duplicate(true)
	var before_count: int = _inventory_entries.count(inventory, tool_id)
	if before_count <= 0:
		return {}
	var consumed_count: int = mini(count, before_count)
	_inventory_entries.add(inventory, tool_id, -consumed_count)
	if persisted_key == "map_interaction_targets":
		persisted_target["container_inventory"] = inventory
		simulation.map_interaction_targets[container_id] = persisted_target
	else:
		persisted_target["inventory"] = inventory
		if persisted_key == "container_sessions":
			simulation.container_sessions[container_id] = persisted_target
			if simulation.corpse_containers.has(container_id):
				var corpse_from_session: Dictionary = _dictionary_or_empty(simulation.corpse_containers[container_id]).duplicate(true)
				corpse_from_session["inventory"] = inventory.duplicate(true)
				simulation.corpse_containers[container_id] = corpse_from_session
		else:
			simulation.corpse_containers[container_id] = persisted_target
			if simulation.container_sessions.has(container_id):
				var session: Dictionary = _dictionary_or_empty(simulation.container_sessions[container_id]).duplicate(true)
				session["inventory"] = inventory.duplicate(true)
				simulation.container_sessions[container_id] = session
	return {
		"item_id": tool_id,
		"count": consumed_count,
		"source": "nearby_container",
		"container_id": container_id,
		"display_name": str(source.get("display_name", container_id)),
		"inventory_before": before_count,
		"inventory_after": _inventory_entries.count(inventory, tool_id),
		"requirement_kind": "tool",
	}


func _tool_durability(actor: RefCounted, tool_id: String) -> float:
	if actor == null or tool_id.is_empty():
		return 0.0
	if actor.tool_durability.has(tool_id):
		return max(0.0, float(actor.tool_durability.get(tool_id, 0.0)))
	return 100.0


func _recipe_consumes_required_tools(recipe: Dictionary) -> bool:
	return bool(recipe.get("consume_required_tools_on_craft", recipe.get("consume_required_tools", recipe.get("consume_tools_on_craft", false))))


func _recipe_required_tool_consume_count(recipe: Dictionary) -> int:
	return max(1, int(recipe.get("required_tool_consume_count", recipe.get("craft_tool_consume_count", recipe.get("tool_consume_count", 1)))))


func _item_name(item_id: String, item_library: Dictionary) -> String:
	var record: Dictionary = _dictionary_or_empty(item_library.get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", item_id))


func _unlock_check(simulation: RefCounted, actor: RefCounted, recipe: Dictionary) -> Dictionary:
	if bool(recipe.get("is_default_unlocked", false)):
		return {"success": true, "unlock_source": "default"}
	var missing: Array[Dictionary] = []
	for condition in _array_or_empty(recipe.get("unlock_conditions", [])):
		var condition_data: Dictionary = _dictionary_or_empty(condition)
		var condition_type := str(condition_data.get("type", ""))
		match condition_type:
			"recipe":
				var required_recipe_id := str(condition_data.get("id", ""))
				if required_recipe_id.is_empty() or not simulation.crafted_recipes.has(required_recipe_id):
					missing.append({
						"type": "recipe",
						"id": required_recipe_id,
					})
			"skill":
				var required_skill_id := str(condition_data.get("id", ""))
				var required_level: int = max(1, int(condition_data.get("level", condition_data.get("required_level", 1))))
				var learned: Dictionary = _dictionary_or_empty(actor.progression.get("learned_skills", {})) if actor != null else {}
				var current_level: int = int(learned.get(required_skill_id, 0))
				if required_skill_id.is_empty() or current_level < required_level:
					missing.append({
						"type": "skill",
						"id": required_skill_id,
						"required_level": required_level,
						"current_level": current_level,
					})
			"quest":
				var required_quest_id := str(condition_data.get("id", ""))
				if required_quest_id.is_empty() or not simulation.completed_quests.has(required_quest_id):
					missing.append({
						"type": "quest",
						"id": required_quest_id,
					})
			"item", "book":
				var required_item_id: String = _inventory_entries.normalize_content_id(condition_data.get("id", condition_data.get("item_id", "")))
				var required_count: int = max(1, int(condition_data.get("count", 1)))
				var current_count: int = int(actor.inventory.get(required_item_id, 0)) if actor != null else 0
				if required_item_id.is_empty() or current_count < required_count:
					missing.append({
						"type": condition_type,
						"id": required_item_id,
						"required": required_count,
						"available": current_count,
					})
			"world_flag", "flag":
				var required_flag_id := str(condition_data.get("id", "")).strip_edges()
				if required_flag_id.is_empty() or not simulation.world_flags.has(required_flag_id):
					missing.append({
						"type": condition_type,
						"id": required_flag_id,
					})
			_:
				missing.append({
					"type": condition_type,
					"id": str(condition_data.get("id", "")),
					"unsupported": true,
				})
	if missing.is_empty() and not _array_or_empty(recipe.get("unlock_conditions", [])).is_empty():
		return {"success": true, "unlock_source": "conditions"}
	return {
		"success": false,
		"reason": "recipe_locked",
		"missing_unlock_conditions": missing,
	}


func _mark_recipe_crafted(simulation: RefCounted, actor_id: int, recipe_id: String) -> void:
	if recipe_id.is_empty():
		return
	var was_known: bool = simulation.crafted_recipes.has(recipe_id)
	simulation.crafted_recipes[recipe_id] = true
	if not was_known:
		simulation.emit_event("recipe_unlocked", {
			"actor_id": actor_id,
			"source_recipe_id": recipe_id,
		})


func _station_check(actor: RefCounted, required_station: String, crafting_context: Dictionary) -> Dictionary:
	var station_id := required_station.strip_edges()
	if station_id in ["", "none"]:
		return {"success": true}
	var station: Dictionary = _nearest_station(actor, station_id, _array_or_empty(crafting_context.get("crafting_stations", [])))
	if station.is_empty():
		return {
			"success": false,
			"reason": "missing_station",
			"required_station": station_id,
		}
	var permission: Dictionary = _station_permission(actor, station, crafting_context)
	if not bool(permission.get("success", false)):
		permission["required_station"] = station_id
		permission["station"] = station.duplicate(true)
		return permission
	return {
		"success": true,
		"station": station,
	}


func _nearest_station(actor: RefCounted, station_id: String, stations: Array) -> Dictionary:
	var best_station: Dictionary = {}
	var best_distance := 2147483647
	for station in stations:
		var station_data: Dictionary = _dictionary_or_empty(station)
		if str(station_data.get("station_id", "")) != station_id:
			continue
		var distance: int = _distance_to_station(actor, station_data)
		var station_range: int = max(0, int(station_data.get("range", 1)))
		if distance > station_range:
			continue
		if distance < best_distance:
			best_distance = distance
			best_station = station_data.duplicate(true)
			best_station["distance"] = distance
	return best_station


func _distance_to_station(actor: RefCounted, station: Dictionary) -> int:
	if actor == null:
		return 2147483647
	var actor_grid: Dictionary = actor.grid_position.to_dictionary()
	var best_distance := 2147483647
	for cell in _array_or_empty(station.get("cells", [])):
		var cell_data: Dictionary = _dictionary_or_empty(cell)
		if int(cell_data.get("y", 0)) != int(actor_grid.get("y", 0)):
			continue
		var dx: int = abs(int(cell_data.get("x", 0)) - int(actor_grid.get("x", 0)))
		var dz: int = abs(int(cell_data.get("z", 0)) - int(actor_grid.get("z", 0)))
		best_distance = mini(best_distance, dx + dz)
	if best_distance != 2147483647:
		return best_distance
	var anchor: Dictionary = _dictionary_or_empty(station.get("anchor", {}))
	if int(anchor.get("y", 0)) != int(actor_grid.get("y", 0)):
		return best_distance
	return abs(int(anchor.get("x", 0)) - int(actor_grid.get("x", 0))) + abs(int(anchor.get("z", 0)) - int(actor_grid.get("z", 0)))


func _station_permission(actor: RefCounted, station: Dictionary, crafting_context: Dictionary) -> Dictionary:
	var world_flags: Dictionary = _dictionary_or_empty(crafting_context.get("world_flags", {}))
	for flag_id in _string_array(station.get("required_world_flags", [])):
		if not world_flags.has(flag_id):
			return {
				"success": false,
				"reason": "station_world_flag_missing",
				"flag_id": flag_id,
				"required_world_flags": _string_array(station.get("required_world_flags", [])),
			}
	for flag_id in _string_array(station.get("blocked_world_flags", [])):
		if world_flags.has(flag_id):
			return {
				"success": false,
				"reason": "station_world_flag_blocked",
				"flag_id": flag_id,
				"blocked_world_flags": _string_array(station.get("blocked_world_flags", [])),
			}
	var missing_items: Array[String] = _missing_actor_items(actor, _required_item_ids(station))
	if not missing_items.is_empty():
		return {
			"success": false,
			"reason": "station_item_missing",
			"item_id": missing_items[0],
			"required_item_ids": _required_item_ids(station),
		}
	var missing_tools: Array[String] = _missing_actor_tools(actor, _required_tool_ids(station), crafting_context)
	if not missing_tools.is_empty():
		return {
			"success": false,
			"reason": "station_tool_missing",
			"item_id": missing_tools[0],
			"required_tool_ids": _required_tool_ids(station),
		}
	return {"success": true}


func _required_item_ids(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	_append_unique_normalized_item_id(output, value.get("required_item_ids", []))
	_append_unique_normalized_item_id(output, value.get("required_items", []))
	return output


func _required_tool_ids(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	_append_unique_normalized_item_id(output, value.get("required_tool_ids", []))
	_append_unique_normalized_item_id(output, value.get("required_tools", []))
	return output


func _missing_actor_items(actor: RefCounted, item_ids: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for item_id in item_ids:
		if actor != null and int(actor.inventory.get(item_id, 0)) > 0:
			continue
		missing.append(item_id)
	return missing


func _missing_actor_tools(actor: RefCounted, tool_ids: Array[String], crafting_context: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for tool_id in tool_ids:
		if _actor_tool_available_count(actor, tool_id, crafting_context) > 0:
			continue
		missing.append(tool_id)
	return missing


func _append_unique_normalized_item_id(output: Array[String], value: Variant) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		_append_one_normalized_item_id(output, value)
		return
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_one_normalized_item_id(output, entry)
		return
	_append_one_normalized_item_id(output, value)


func _append_one_normalized_item_id(output: Array[String], value: Variant) -> void:
	var raw_value: Variant = value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = _dictionary_or_empty(value)
		raw_value = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var normalized_entry: String = _inventory_entries.normalize_content_id(raw_value)
	if normalized_entry.is_empty() or output.has(normalized_entry):
		return
	output.append(normalized_entry)


func _string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(value) == TYPE_STRING:
		var normalized_value := str(value).strip_edges()
		if not normalized_value.is_empty():
			output.append(normalized_value)
		return output
	for entry in _array_or_empty(value):
		var normalized_entry := str(entry).strip_edges()
		if not normalized_entry.is_empty():
			output.append(normalized_entry)
	return output
