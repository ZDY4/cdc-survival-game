extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const InventoryCapacity = preload("res://scripts/core/economy/inventory_capacity.gd")

var _inventory_entries := InventoryEntries.new()
var _inventory_capacity := InventoryCapacity.new()


func craft_recipe(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, recipe_id: String, recipe_library: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
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
	var missing_tools: Array[Dictionary] = _missing_required_tools(actor, _array_or_empty(recipe.get("required_tools", [])), simulation.item_library, crafting_context)
	if not missing_tools.is_empty():
		return {
			"success": false,
			"reason": "missing_tools",
			"missing_tools": missing_tools,
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
	var capacity: Dictionary = _inventory_capacity.can_add_items(actor, simulation.item_library, [
		{"item_id": output_item_id, "count": output_count},
	], materials)
	if not bool(capacity.get("success", false)):
		capacity["recipe_id"] = recipe_id
		capacity["output_item_id"] = output_item_id
		capacity["output_count"] = output_count
		return capacity

	for material in materials:
		_inventory_entries.add_actor_item(actor, str(material.get("item_id", "")), -int(material.get("count", 0)))
	_inventory_entries.add_actor_item(actor, output_item_id, output_count)
	simulation.emit_event("recipe_crafted", {
		"actor_id": actor_id,
		"recipe_id": recipe_id,
		"output_item_id": output_item_id,
		"output_count": output_count,
		"craft_time": float(recipe.get("craft_time", 0.0)),
		"experience_reward": int(recipe.get("experience_reward", 0)),
	})
	if int(recipe.get("experience_reward", 0)) > 0:
		simulation.grant_experience(actor_id, int(recipe.get("experience_reward", 0)), "recipe:%s" % recipe_id)
	_mark_recipe_crafted(simulation, actor_id, recipe_id)
	return {
		"success": true,
		"recipe_id": recipe_id,
		"output_item_id": output_item_id,
		"output_count": output_count,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _missing_required_tools(actor: RefCounted, required_tools: Array, item_library: Dictionary, crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for tool in required_tools:
		var tool_id: String = _inventory_entries.normalize_content_id(tool)
		if tool_id.is_empty():
			continue
		if _actor_has_tool(actor, tool_id, crafting_context):
			continue
		missing.append({
			"item_id": tool_id,
			"name": _item_name(tool_id, item_library),
			"available": 0,
			"required": 1,
		})
	return missing


func _actor_has_tool(actor: RefCounted, tool_id: String, crafting_context: Dictionary = {}) -> bool:
	if actor == null:
		return false
	if int(actor.inventory.get(tool_id, 0)) > 0:
		return true
	for slot_id in actor.equipment.keys():
		if _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) == tool_id:
			return true
	for container in _array_or_empty(crafting_context.get("nearby_tool_containers", [])):
		var container_data: Dictionary = _dictionary_or_empty(container)
		if _inventory_entries.count(_array_or_empty(container_data.get("inventory", [])), tool_id) > 0:
			return true
	return false


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
