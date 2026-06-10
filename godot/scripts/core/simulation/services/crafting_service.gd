extends RefCounted

const CraftingRunner = preload("res://scripts/core/crafting/crafting_runner.gd")
const EconomyTransactions = preload("res://scripts/core/economy/economy_transactions.gd")
const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

const DEFAULT_INTERACTION_AP := 1.0
const CRAFTING_SECONDS_PER_AP := 10.0

var _crafting_runner := CraftingRunner.new()
var _economy_transactions := EconomyTransactions.new()
var _inventory_entries := InventoryEntries.new()


func validate_recipe(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, recipe_id: String, recipe_library: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	return _crafting_runner.validate_craft_recipe(simulation, progression_rules, actor_id, recipe_id, recipe_library, crafting_context)


func craft_recipe(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, recipe_id: String, recipe_library: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	return _crafting_runner.craft_recipe(simulation, progression_rules, actor_id, recipe_id, recipe_library, crafting_context)


func deconstruct_actor_item(simulation: RefCounted, actor_id: int, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.deconstruct_actor_item(simulation, actor_id, item_id, count, item_library)


func deconstruct_requirement_check(actor: RefCounted, item_id: String, items: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var item_record: Dictionary = _dictionary_or_empty(items.get(normalized_item_id, {}))
	var item_data: Dictionary = _dictionary_or_empty(item_record.get("data", item_record))
	var crafting_fragment: Dictionary = _item_crafting_fragment(item_data)
	if crafting_fragment.is_empty():
		return {"success": true}
	var missing_tools: Array[Dictionary] = []
	var required_tools: Array[Dictionary] = _deconstruct_tool_requirements(crafting_fragment)
	for tool in required_tools:
		var tool_id: String = str(tool.get("item_id", ""))
		var available_count: int = _actor_tool_available_count(actor, tool_id, crafting_context)
		var required_count: int = max(1, int(tool.get("required", 1)))
		if available_count >= required_count:
			continue
		missing_tools.append({
			"item_id": tool_id,
			"required": required_count,
			"available": available_count,
		})
	if not missing_tools.is_empty():
		return {"success": false, "reason": "missing_tools", "item_id": normalized_item_id, "missing_tools": missing_tools}
	var missing_durability_tools: Array[Dictionary] = _missing_deconstruct_tool_durability(actor, required_tools, items)
	if not missing_durability_tools.is_empty():
		return {
			"success": false,
			"reason": "tool_durability_insufficient",
			"item_id": normalized_item_id,
			"missing_tools": missing_durability_tools,
			"missing_durability_tools": missing_durability_tools,
		}
	var tool_consumption: Array[Dictionary] = _deconstruct_tool_consumption_requirements(actor, required_tools, crafting_context)
	var missing_consumable_tools: Array[Dictionary] = _missing_deconstruct_consumable_tools(tool_consumption, items)
	if not missing_consumable_tools.is_empty():
		return {
			"success": false,
			"reason": "missing_consumable_tools",
			"item_id": normalized_item_id,
			"missing_consumable_tools": missing_consumable_tools,
		}
	var required_station := str(crafting_fragment.get("deconstruct_required_station", crafting_fragment.get("required_deconstruct_station", ""))).strip_edges()
	if required_station in ["", "none"]:
		return {"success": true, "required_tools": required_tools, "tool_consumption": tool_consumption}
	var station: Dictionary = _nearest_crafting_station(actor, required_station, _array_or_empty(crafting_context.get("crafting_stations", [])))
	if station.is_empty():
		return {"success": false, "reason": "missing_station", "item_id": normalized_item_id, "required_station": required_station}
	return {
		"success": true,
		"required_tools": required_tools,
		"tool_consumption": tool_consumption,
		"required_station": required_station,
		"station": station,
	}


func deconstruct_tool_consumption_sources_available(simulation: RefCounted, actor: RefCounted, tool_consumption: Array, items: Dictionary) -> Dictionary:
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
			"name": _item_name_from_library(tool_id, items),
			"available": available_count,
			"required": required_count,
			"consume_on_deconstruct": true,
		})
	if missing.is_empty():
		return {"success": true}
	return {"success": false, "reason": "missing_consumable_tools", "missing_consumable_tools": missing}


func consume_deconstruct_tools(simulation: RefCounted, actor: RefCounted, tool_consumption: Array) -> Array[Dictionary]:
	var consumed: Array[Dictionary] = []
	for tool in tool_consumption:
		var tool_data: Dictionary = _dictionary_or_empty(tool)
		var tool_id := str(tool_data.get("item_id", ""))
		var count: int = max(1, int(tool_data.get("count", 1)))
		var durability_cost: float = max(0.0, float(tool_data.get("durability_cost", 0.0)))
		if actor == null or tool_id.is_empty():
			continue
		if durability_cost > 0.0:
			var durability_before: float = _actor_tool_durability(actor, tool_id)
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
		for source in _array_or_empty(tool_data.get("sources", [])):
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


func deconstruct_ap_cost(item_id: String, items: Dictionary, count: int, command: Dictionary = {}) -> float:
	if command.has("ap_cost"):
		return max(0.0, float(command.get("ap_cost", DEFAULT_INTERACTION_AP))) * float(max(1, count))
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var item_record: Dictionary = _dictionary_or_empty(items.get(normalized_item_id, {}))
	var item_data: Dictionary = _dictionary_or_empty(item_record.get("data", item_record))
	var crafting_fragment: Dictionary = _item_crafting_fragment(item_data)
	var per_item_cost: float = DEFAULT_INTERACTION_AP
	if crafting_fragment.has("deconstruct_ap_cost"):
		per_item_cost = max(0.0, float(crafting_fragment.get("deconstruct_ap_cost", DEFAULT_INTERACTION_AP)))
	elif crafting_fragment.has("deconstruct_time"):
		per_item_cost = _ap_cost_from_seconds(float(crafting_fragment.get("deconstruct_time", 0.0)))
	return per_item_cost * float(max(1, count))


func normalize_item_id(item_id: String) -> String:
	return _inventory_entries.normalize_content_id(item_id)


func _deconstruct_tool_requirements(crafting_fragment: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for key in ["deconstruct_required_tools", "required_deconstruct_tools", "deconstruct_required_tool_ids", "required_deconstruct_tool_ids"]:
		if crafting_fragment.has(key):
			_append_deconstruct_tool_requirements(output, crafting_fragment.get(key), crafting_fragment)
	return output


func _append_deconstruct_tool_requirements(output: Array[Dictionary], value: Variant, crafting_fragment: Dictionary) -> void:
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_deconstruct_tool_requirements(output, entry, crafting_fragment)
		return
	var requirement: Dictionary = _deconstruct_tool_requirement(value, crafting_fragment)
	var tool_id := str(requirement.get("item_id", ""))
	if tool_id.is_empty():
		return
	for index in range(output.size()):
		var existing: Dictionary = _dictionary_or_empty(output[index])
		if str(existing.get("item_id", "")) != tool_id:
			continue
		existing["required"] = max(int(existing.get("required", 1)), int(requirement.get("required", 1)))
		if bool(requirement.get("consume_on_deconstruct", false)):
			existing["consume_on_deconstruct"] = true
			existing["consume_count"] = max(int(existing.get("consume_count", 1)), int(requirement.get("consume_count", 1)))
		if float(requirement.get("durability_cost", 0.0)) > 0.0:
			existing["durability_cost"] = max(float(existing.get("durability_cost", 0.0)), float(requirement.get("durability_cost", 0.0)))
		output[index] = existing
		return
	output.append(requirement)


func _deconstruct_tool_requirement(tool: Variant, crafting_fragment: Dictionary) -> Dictionary:
	var data: Dictionary = _dictionary_or_empty(tool)
	var raw_id: Variant = tool
	if not data.is_empty():
		raw_id = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var required_count: int = max(1, int(data.get("required", data.get("required_count", data.get("count", 1)))))
	var consume_on_deconstruct: bool = bool(data.get("consume_on_deconstruct", data.get("consume_on_deconstruct_item", data.get("consume_on_craft", data.get("consume", data.get("consumed", false))))))
	if _deconstruct_consumes_required_tools(crafting_fragment):
		consume_on_deconstruct = true
	var consume_count: int = max(1, int(data.get("consume_count", data.get("consumed_count", data.get("tool_consume_count", data.get("deconstruct_tool_consume_count", _deconstruct_required_tool_consume_count(crafting_fragment)))))))
	var durability_cost: float = float(data.get("durability_cost", data.get("tool_durability_cost", data.get("deconstruct_tool_durability_cost", data.get("required_tool_durability_cost", 0.0)))))
	return {
		"item_id": _inventory_entries.normalize_content_id(raw_id),
		"required": required_count,
		"consume_on_deconstruct": consume_on_deconstruct,
		"consume_count": consume_count,
		"durability_cost": max(0.0, durability_cost),
	}


func _deconstruct_consumes_required_tools(crafting_fragment: Dictionary) -> bool:
	return bool(crafting_fragment.get("consume_required_tools_on_deconstruct", crafting_fragment.get("consume_deconstruct_tools", crafting_fragment.get("consume_required_tools", false))))


func _deconstruct_required_tool_consume_count(crafting_fragment: Dictionary) -> int:
	return max(1, int(crafting_fragment.get("required_tool_consume_count", crafting_fragment.get("deconstruct_tool_consume_count", crafting_fragment.get("tool_consume_count", 1)))))


func _deconstruct_tool_consumption_requirements(actor: RefCounted, required_tools: Array[Dictionary], crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for tool in required_tools:
		var durability_cost: float = max(0.0, float(tool.get("durability_cost", 0.0)))
		if not bool(tool.get("consume_on_deconstruct", false)) and durability_cost <= 0.0:
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
			requirement["available_durability"] = _actor_tool_durability(actor, tool_id)
		output.append(requirement)
	return output


func _missing_deconstruct_consumable_tools(tool_consumption: Array[Dictionary], items: Dictionary) -> Array[Dictionary]:
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
			"name": _item_name_from_library(tool_id, items),
			"available": available_count,
			"required": required_count,
			"consume_on_deconstruct": true,
		})
	return missing


func _missing_deconstruct_tool_durability(actor: RefCounted, required_tools: Array[Dictionary], items: Dictionary) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for tool in required_tools:
		var tool_id := str(tool.get("item_id", ""))
		var durability_cost: float = max(0.0, float(tool.get("durability_cost", 0.0)))
		if tool_id.is_empty() or durability_cost <= 0.0:
			continue
		var available_durability: float = _actor_tool_durability(actor, tool_id)
		if available_durability >= durability_cost:
			continue
		missing.append({
			"item_id": tool_id,
			"name": _item_name_from_library(tool_id, items),
			"available_durability": available_durability,
			"required_durability": durability_cost,
			"durability_cost": durability_cost,
		})
	return missing


func _tool_consumption_sources(actor: RefCounted, tool_id: String, count: int, crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var remaining: int = max(0, count)
	if actor != null and remaining > 0:
		var actor_count: int = max(0, int(actor.inventory.get(tool_id, 0)))
		if actor_count > 0:
			var consumed_actor_count: int = mini(actor_count, remaining)
			output.append({"source": "actor_inventory", "count": consumed_actor_count, "inventory_before": actor_count})
			remaining -= consumed_actor_count
	if actor != null and remaining > 0:
		var slot_ids: Array = actor.equipment.keys()
		slot_ids.sort()
		for slot_id in slot_ids:
			if remaining <= 0:
				break
			if _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) != tool_id:
				continue
			output.append({"source": "equipment", "slot_id": str(slot_id), "count": 1})
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
			return {"item_id": tool_id, "count": 1, "source": "equipment", "slot_id": slot_id, "requirement_kind": "tool"}
		"nearby_container":
			return _consume_tool_from_nearby_container(simulation, tool_id, count, source)
	return {}


func _consume_tool_from_nearby_container(simulation: RefCounted, tool_id: String, count: int, source: Dictionary) -> Dictionary:
	if simulation == null:
		return {}
	var container_id := str(source.get("container_id", ""))
	if container_id.is_empty():
		return {}
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
	var inventory: Array = _array_or_empty(persisted_target.get("inventory", persisted_target.get("container_inventory", []))).duplicate(true)
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


func _actor_tool_durability(actor: RefCounted, tool_id: String) -> float:
	if actor == null or tool_id.is_empty():
		return 0.0
	if actor.tool_durability.has(tool_id):
		return max(0.0, float(actor.tool_durability.get(tool_id, 0.0)))
	return 100.0


func _item_name_from_library(item_id: String, items: Dictionary) -> String:
	var record: Dictionary = _dictionary_or_empty(items.get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", item_id))


func _actor_tool_available_count(actor: RefCounted, tool_id: String, crafting_context: Dictionary = {}) -> int:
	if actor == null or tool_id.is_empty():
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


func _nearest_crafting_station(actor: RefCounted, station_id: String, stations: Array) -> Dictionary:
	var best_station: Dictionary = {}
	var best_distance := 2147483647
	for station in stations:
		var station_data: Dictionary = _dictionary_or_empty(station)
		if str(station_data.get("station_id", "")) != station_id:
			continue
		var distance: int = _distance_to_crafting_station(actor, station_data)
		var station_range: int = max(0, int(station_data.get("range", 1)))
		if distance > station_range:
			continue
		if distance < best_distance:
			best_distance = distance
			best_station = station_data.duplicate(true)
			best_station["distance"] = distance
	return best_station


func _distance_to_crafting_station(actor: RefCounted, station: Dictionary) -> int:
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


func _item_crafting_fragment(item_data: Dictionary) -> Dictionary:
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "crafting":
			return fragment_data
	return {}


func _ap_cost_from_seconds(seconds: float) -> float:
	if seconds <= 0.0:
		return DEFAULT_INTERACTION_AP
	return max(DEFAULT_INTERACTION_AP, ceil(seconds / CRAFTING_SECONDS_PER_AP))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
