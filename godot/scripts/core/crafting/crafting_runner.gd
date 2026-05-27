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
	if not _array_or_empty(recipe.get("required_tools", [])).is_empty():
		return {"success": false, "reason": "required_tools_unsupported"}
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
