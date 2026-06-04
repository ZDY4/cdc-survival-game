extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

var _inventory_entries := InventoryEntries.new()


func craft_recipe(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, recipe_id: String, recipe_library: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var record: Dictionary = _dictionary_or_empty(recipe_library.get(recipe_id, {}))
	if record.is_empty():
		return {"success": false, "reason": "unknown_recipe"}
	var recipe: Dictionary = _dictionary_or_empty(record.get("data", {}))
	if not bool(recipe.get("is_default_unlocked", false)):
		return {"success": false, "reason": "recipe_locked"}
	var missing_tools: Array[Dictionary] = _missing_required_tools(actor, _array_or_empty(recipe.get("required_tools", [])), simulation.item_library)
	if not missing_tools.is_empty():
		return {
			"success": false,
			"reason": "missing_tools",
			"missing_tools": missing_tools,
		}
	if str(recipe.get("required_station", "none")) not in ["", "none"]:
		return {"success": false, "reason": "required_station_unsupported"}
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


func _missing_required_tools(actor: RefCounted, required_tools: Array, item_library: Dictionary) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for tool in required_tools:
		var tool_id: String = _inventory_entries.normalize_content_id(tool)
		if tool_id.is_empty():
			continue
		if _actor_has_tool(actor, tool_id):
			continue
		missing.append({
			"item_id": tool_id,
			"name": _item_name(tool_id, item_library),
			"available": 0,
			"required": 1,
		})
	return missing


func _actor_has_tool(actor: RefCounted, tool_id: String) -> bool:
	if actor == null:
		return false
	if int(actor.inventory.get(tool_id, 0)) > 0:
		return true
	for slot_id in actor.equipment.keys():
		if _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) == tool_id:
			return true
	return false


func _item_name(item_id: String, item_library: Dictionary) -> String:
	var record: Dictionary = _dictionary_or_empty(item_library.get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", item_id))
