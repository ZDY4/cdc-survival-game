extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	var equipment: Dictionary = _dictionary_or_empty(player.get("equipment", {}))
	var progression: Dictionary = _dictionary_or_empty(player.get("progression", {}))
	var crafted_recipes: Dictionary = _flag_dictionary(runtime_snapshot.get("crafted_recipes", []))
	var completed_quests: Dictionary = _flag_dictionary(runtime_snapshot.get("completed_quests", []))
	var recipes: Array[Dictionary] = []
	var recipe_ids: Array = registry.get_library("recipes").keys()
	recipe_ids.sort()
	for recipe_id in recipe_ids:
		var recipe_view: Dictionary = _recipe_snapshot(str(recipe_id), player, inventory, equipment, progression, crafted_recipes, completed_quests, crafting_context)
		if not recipe_view.is_empty():
			recipes.append(recipe_view)
	return {
		"owner_actor_id": int(player.get("actor_id", 0)),
		"owner_name": str(player.get("display_name", "")),
		"recipes": recipes,
		"craftable_count": _craftable_count(recipes),
	}


func _recipe_snapshot(recipe_id: String, player: Dictionary, inventory: Dictionary, equipment: Dictionary, progression: Dictionary, crafted_recipes: Dictionary, completed_quests: Dictionary, crafting_context: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("recipes").get(recipe_id, {}))
	var recipe: Dictionary = _dictionary_or_empty(record.get("data", record))
	if recipe.is_empty():
		return {}
	var output: Dictionary = _dictionary_or_empty(recipe.get("output", {}))
	var output_item_id: String = _normalize_content_id(output.get("item_id", ""))
	var output_item: Dictionary = _item_data(output_item_id)
	var materials: Array[Dictionary] = []
	for material in _array_or_empty(recipe.get("materials", [])):
		var material_data: Dictionary = _dictionary_or_empty(material)
		var item_id: String = _normalize_content_id(material_data.get("item_id", ""))
		var required_count: int = max(0, int(material_data.get("count", 0)))
		materials.append({
			"item_id": item_id,
			"name": str(_item_data(item_id).get("name", item_id)),
			"required": required_count,
			"available": int(inventory.get(item_id, 0)),
		})
	var required_tools: Array[Dictionary] = _required_tools_snapshot(_array_or_empty(recipe.get("required_tools", [])), inventory, equipment)
	var required_station := str(recipe.get("required_station", "none"))
	var station_check: Dictionary = _station_check(player, required_station, crafting_context)
	var unlock_check: Dictionary = _unlock_check(recipe, progression, crafted_recipes, completed_quests)
	var availability: Dictionary = _availability(recipe, inventory, equipment, progression, materials, required_tools, station_check, unlock_check)
	var max_craft_count: int = _max_craft_count(materials, bool(availability.get("can_craft", false)))
	var output_count: int = max(1, int(output.get("count", 1)))
	return {
		"recipe_id": recipe_id,
		"name": str(recipe.get("name", recipe_id)),
		"description": str(recipe.get("description", "")),
		"category": str(recipe.get("category", "")),
		"output_item_id": output_item_id,
		"output_name": str(output_item.get("name", output_item_id)),
		"output_count": output_count,
		"preview_output_count": output_count * max(1, max_craft_count),
		"materials": materials,
		"required_tools": required_tools,
		"required_station": required_station,
		"available_station": _dictionary_or_empty(station_check.get("station", {})).duplicate(true),
		"skill_requirements": _dictionary_or_empty(recipe.get("skill_requirements", {})).duplicate(true),
		"craft_time": float(recipe.get("craft_time", 0.0)),
		"experience_reward": int(recipe.get("experience_reward", 0)),
		"is_default_unlocked": bool(recipe.get("is_default_unlocked", false)),
		"unlock_conditions": _unlock_condition_snapshot(recipe),
		"can_craft": bool(availability.get("can_craft", false)),
		"max_craft_count": max_craft_count,
		"craft_reason": str(availability.get("reason", "")),
		"missing_unlock_conditions": _array_or_empty(availability.get("missing_unlock_conditions", [])).duplicate(true),
		"missing_materials": _array_or_empty(availability.get("missing_materials", [])).duplicate(true),
		"missing_skills": _array_or_empty(availability.get("missing_skills", [])).duplicate(true),
		"missing_tools": _array_or_empty(availability.get("missing_tools", [])).duplicate(true),
	}


func _availability(recipe: Dictionary, inventory: Dictionary, equipment: Dictionary, progression: Dictionary, materials: Array[Dictionary], required_tools: Array[Dictionary], station_check: Dictionary, unlock_check: Dictionary) -> Dictionary:
	if not bool(unlock_check.get("success", false)):
		return unlock_check
	var missing_tools: Array[Dictionary] = []
	for tool in required_tools:
		var tool_data: Dictionary = _dictionary_or_empty(tool)
		var tool_id := str(tool_data.get("item_id", ""))
		if tool_id.is_empty():
			continue
		if _has_tool(tool_id, inventory, equipment):
			continue
		missing_tools.append({
			"item_id": tool_id,
			"name": str(tool_data.get("name", tool_id)),
			"available": 0,
			"required": 1,
		})
	if not missing_tools.is_empty():
		return {"can_craft": false, "reason": "missing_tools", "missing_tools": missing_tools}
	if not bool(station_check.get("success", false)):
		return station_check
	var missing_skills: Array[Dictionary] = []
	var learned: Dictionary = _dictionary_or_empty(progression.get("learned_skills", {}))
	for skill_id in _dictionary_or_empty(recipe.get("skill_requirements", {})).keys():
		var required_level: int = max(1, int(recipe.get("skill_requirements", {}).get(skill_id, 0)))
		var current_level: int = int(learned.get(str(skill_id), 0))
		if current_level < required_level:
			missing_skills.append({
				"skill_id": str(skill_id),
				"required_level": required_level,
				"current_level": current_level,
			})
	if not missing_skills.is_empty():
		return {"can_craft": false, "reason": "missing_skills", "missing_skills": missing_skills}
	var missing_materials: Array[Dictionary] = []
	for material in materials:
		var item_id: String = str(material.get("item_id", ""))
		var required: int = int(material.get("required", 0))
		var available: int = int(inventory.get(item_id, 0))
		if available < required:
			missing_materials.append({
				"item_id": item_id,
				"name": str(material.get("name", item_id)),
				"required": required,
				"available": available,
			})
	if not missing_materials.is_empty():
		return {"can_craft": false, "reason": "materials_insufficient", "missing_materials": missing_materials}
	return {"can_craft": true, "reason": "available"}


func _unlock_check(recipe: Dictionary, progression: Dictionary, crafted_recipes: Dictionary, completed_quests: Dictionary) -> Dictionary:
	if bool(recipe.get("is_default_unlocked", false)):
		return {"success": true}
	var missing: Array[Dictionary] = []
	var learned: Dictionary = _dictionary_or_empty(progression.get("learned_skills", {}))
	for condition in _array_or_empty(recipe.get("unlock_conditions", [])):
		var data: Dictionary = _dictionary_or_empty(condition)
		var condition_type := str(data.get("type", ""))
		match condition_type:
			"recipe":
				var recipe_id := str(data.get("id", ""))
				if recipe_id.is_empty() or not crafted_recipes.has(recipe_id):
					missing.append(_unlock_condition_view(data))
			"skill":
				var skill_id := str(data.get("id", ""))
				var required_level: int = max(1, int(data.get("level", data.get("required_level", 1))))
				var current_level: int = int(learned.get(skill_id, 0))
				if skill_id.is_empty() or current_level < required_level:
					var skill_condition := _unlock_condition_view(data)
					skill_condition["required_level"] = required_level
					skill_condition["current_level"] = current_level
					missing.append(skill_condition)
			"quest":
				var quest_id := str(data.get("id", ""))
				if quest_id.is_empty() or not completed_quests.has(quest_id):
					missing.append(_unlock_condition_view(data))
			_:
				var unsupported := _unlock_condition_view(data)
				unsupported["unsupported"] = true
				missing.append(unsupported)
	if missing.is_empty() and not _array_or_empty(recipe.get("unlock_conditions", [])).is_empty():
		return {"success": true}
	return {
		"success": false,
		"can_craft": false,
		"reason": "recipe_locked",
		"missing_unlock_conditions": missing,
	}


func _unlock_condition_snapshot(recipe: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for condition in _array_or_empty(recipe.get("unlock_conditions", [])):
		output.append(_unlock_condition_view(_dictionary_or_empty(condition)))
	return output


func _unlock_condition_view(condition: Dictionary) -> Dictionary:
	var condition_type := str(condition.get("type", ""))
	var condition_id := str(condition.get("id", ""))
	var display_name := condition_id
	match condition_type:
		"recipe":
			var recipe_record: Dictionary = _dictionary_or_empty(registry.get_library("recipes").get(condition_id, {}))
			var recipe_data: Dictionary = _dictionary_or_empty(recipe_record.get("data", recipe_record))
			display_name = str(recipe_data.get("name", condition_id))
		"skill":
			var skill_record: Dictionary = _dictionary_or_empty(registry.get_library("skills").get(condition_id, {}))
			var skill_data: Dictionary = _dictionary_or_empty(skill_record.get("data", skill_record))
			display_name = str(skill_data.get("name", condition_id))
		"quest":
			var quest_record: Dictionary = _dictionary_or_empty(registry.get_library("quests").get(condition_id, {}))
			var quest_data: Dictionary = _dictionary_or_empty(quest_record.get("data", quest_record))
			display_name = str(quest_data.get("title", condition_id))
	var view := {
		"type": condition_type,
		"id": condition_id,
		"display_name": display_name,
	}
	if condition.has("level"):
		view["level"] = max(1, int(condition.get("level", 1)))
	if condition.has("required_level"):
		view["required_level"] = max(1, int(condition.get("required_level", 1)))
	return view


func _station_check(player: Dictionary, required_station: String, crafting_context: Dictionary) -> Dictionary:
	var station_id := required_station.strip_edges()
	if station_id in ["", "none"]:
		return {"success": true}
	var station: Dictionary = _nearest_station(player, station_id, _array_or_empty(crafting_context.get("crafting_stations", [])))
	if station.is_empty():
		return {
			"can_craft": false,
			"success": false,
			"reason": "missing_station",
			"required_station": station_id,
		}
	return {
		"success": true,
		"station": station,
	}


func _nearest_station(player: Dictionary, station_id: String, stations: Array) -> Dictionary:
	var best_station: Dictionary = {}
	var best_distance := 2147483647
	for station in stations:
		var station_data: Dictionary = _dictionary_or_empty(station)
		if str(station_data.get("station_id", "")) != station_id:
			continue
		var distance: int = _distance_to_station(player, station_data)
		var station_range: int = max(0, int(station_data.get("range", 1)))
		if distance > station_range:
			continue
		if distance < best_distance:
			best_distance = distance
			best_station = station_data.duplicate(true)
			best_station["distance"] = distance
	return best_station


func _distance_to_station(player: Dictionary, station: Dictionary) -> int:
	var player_grid: Dictionary = _dictionary_or_empty(player.get("grid_position", {}))
	var best_distance := 2147483647
	for cell in _array_or_empty(station.get("cells", [])):
		var cell_data: Dictionary = _dictionary_or_empty(cell)
		if int(cell_data.get("y", 0)) != int(player_grid.get("y", 0)):
			continue
		var dx: int = abs(int(cell_data.get("x", 0)) - int(player_grid.get("x", 0)))
		var dz: int = abs(int(cell_data.get("z", 0)) - int(player_grid.get("z", 0)))
		best_distance = mini(best_distance, dx + dz)
	if best_distance != 2147483647:
		return best_distance
	var anchor: Dictionary = _dictionary_or_empty(station.get("anchor", {}))
	if int(anchor.get("y", 0)) != int(player_grid.get("y", 0)):
		return best_distance
	return abs(int(anchor.get("x", 0)) - int(player_grid.get("x", 0))) + abs(int(anchor.get("z", 0)) - int(player_grid.get("z", 0)))


func _required_tools_snapshot(required_tools: Array, inventory: Dictionary, equipment: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for tool in required_tools:
		var tool_id: String = _normalize_content_id(tool)
		if tool_id.is_empty():
			continue
		var has_tool := _has_tool(tool_id, inventory, equipment)
		output.append({
			"item_id": tool_id,
			"name": str(_item_data(tool_id).get("name", tool_id)),
			"available": 1 if has_tool else 0,
			"required": 1,
		})
	return output


func _has_tool(tool_id: String, inventory: Dictionary, equipment: Dictionary) -> bool:
	if int(inventory.get(tool_id, 0)) > 0:
		return true
	for slot_id in equipment.keys():
		if _normalize_content_id(equipment.get(slot_id, "")) == tool_id:
			return true
	return false


func _craftable_count(recipes: Array[Dictionary]) -> int:
	var count := 0
	for recipe in recipes:
		if bool(recipe.get("can_craft", false)):
			count += 1
	return count


func _max_craft_count(materials: Array[Dictionary], can_craft: bool) -> int:
	if not can_craft:
		return 0
	if materials.is_empty():
		return 1
	var max_count := 2147483647
	for material in materials:
		var required := int(material.get("required", 0))
		if required <= 0:
			continue
		max_count = mini(max_count, int(material.get("available", 0)) / required)
	if max_count == 2147483647:
		return 1
	return max(0, max_count)


func _item_data(item_id: String) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("items").get(item_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _normalize_content_id(value: Variant) -> String:
	if value == null:
		return ""
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	if typeof(value) == TYPE_INT:
		return str(value)
	var text := str(value).strip_edges()
	return "" if text == "<null>" else text


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _flag_dictionary(values: Variant) -> Dictionary:
	var output: Dictionary = {}
	for value in _array_or_empty(values):
		output[str(value)] = true
	return output
