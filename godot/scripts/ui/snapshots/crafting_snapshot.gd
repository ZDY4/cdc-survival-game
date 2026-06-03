extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	var progression: Dictionary = _dictionary_or_empty(player.get("progression", {}))
	var recipes: Array[Dictionary] = []
	var recipe_ids: Array = registry.get_library("recipes").keys()
	recipe_ids.sort()
	for recipe_id in recipe_ids:
		var recipe_view: Dictionary = _recipe_snapshot(str(recipe_id), inventory, progression)
		if not recipe_view.is_empty():
			recipes.append(recipe_view)
	return {
		"owner_actor_id": int(player.get("actor_id", 0)),
		"owner_name": str(player.get("display_name", "")),
		"recipes": recipes,
		"craftable_count": _craftable_count(recipes),
	}


func _recipe_snapshot(recipe_id: String, inventory: Dictionary, progression: Dictionary) -> Dictionary:
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
	var availability: Dictionary = _availability(recipe, inventory, progression, materials)
	return {
		"recipe_id": recipe_id,
		"name": str(recipe.get("name", recipe_id)),
		"description": str(recipe.get("description", "")),
		"category": str(recipe.get("category", "")),
		"output_item_id": output_item_id,
		"output_name": str(output_item.get("name", output_item_id)),
		"output_count": max(1, int(output.get("count", 1))),
		"materials": materials,
		"required_tools": _array_or_empty(recipe.get("required_tools", [])).duplicate(true),
		"required_station": str(recipe.get("required_station", "none")),
		"skill_requirements": _dictionary_or_empty(recipe.get("skill_requirements", {})).duplicate(true),
		"craft_time": float(recipe.get("craft_time", 0.0)),
		"experience_reward": int(recipe.get("experience_reward", 0)),
		"is_default_unlocked": bool(recipe.get("is_default_unlocked", false)),
		"can_craft": bool(availability.get("can_craft", false)),
		"craft_reason": str(availability.get("reason", "")),
		"missing_materials": _array_or_empty(availability.get("missing_materials", [])).duplicate(true),
		"missing_skills": _array_or_empty(availability.get("missing_skills", [])).duplicate(true),
	}


func _availability(recipe: Dictionary, inventory: Dictionary, progression: Dictionary, materials: Array[Dictionary]) -> Dictionary:
	if not bool(recipe.get("is_default_unlocked", false)):
		return {"can_craft": false, "reason": "recipe_locked"}
	if not _array_or_empty(recipe.get("required_tools", [])).is_empty():
		return {"can_craft": false, "reason": "required_tools_unsupported"}
	if str(recipe.get("required_station", "none")) not in ["", "none"]:
		return {"can_craft": false, "reason": "required_station_unsupported"}
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


func _craftable_count(recipes: Array[Dictionary]) -> int:
	var count := 0
	for recipe in recipes:
		if bool(recipe.get("can_craft", false)):
			count += 1
	return count


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
