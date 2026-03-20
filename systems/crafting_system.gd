extends Node
# CraftingSystem - 制作系统
# 统一负责配方加载、解锁、制作队列与维修配方逻辑

const ValueUtils = preload("res://core/value_utils.gd")

signal crafting_started(recipe_id: String, craft_time: float)
signal crafting_completed(item_id: String, count: int)
signal crafting_failed(recipe_id: String, reason: String)
signal recipe_unlocked(recipe_id: String)
signal repair_recipe_unlocked(recipe_id: String)

var RECIPES: Dictionary = {}

var crafting_queue: Array[Dictionary] = []
var is_crafting: bool = false
var current_craft_timer: float = 0.0
var current_recipe: Dictionary = {}
var unlocked_recipes: Array[String] = []
var _durability_system: Node = null


func _ready() -> void:
	print("[CraftingSystem] 制作系统已初始化")
	_durability_system = get_node_or_null("/root/ItemDurabilitySystem")
	reload_recipes()


func _process(delta: float) -> void:
	if not is_crafting or crafting_queue.is_empty():
		return

	current_craft_timer -= delta
	if current_craft_timer <= 0.0:
		_finish_crafting()


func reload_recipes() -> void:
	var preserved_unlocks: Array[String] = unlocked_recipes.duplicate()
	RECIPES.clear()

	if DataManager and DataManager.has_method("reload_category"):
		DataManager.reload_category("recipes")

	var raw_recipes: Dictionary = {}
	if DataManager and DataManager.has_method("get_all_recipes"):
		raw_recipes = DataManager.get_all_recipes()

	for recipe_key in raw_recipes.keys():
		var recipe_id := str(recipe_key)
		var recipe_data: Variant = raw_recipes.get(recipe_key, {})
		if recipe_data is Dictionary:
			RECIPES[recipe_id] = _normalize_recipe_data(recipe_id, recipe_data)

	unlocked_recipes.clear()
	for recipe_id in preserved_unlocks:
		if RECIPES.has(recipe_id) and not unlocked_recipes.has(recipe_id):
			unlocked_recipes.append(recipe_id)

	_unlock_default_recipes()
	_restore_queue_recipes()
	print("[CraftingSystem] 已加载 %d 个配方" % RECIPES.size())


func has_recipe(recipe_id: String) -> bool:
	return RECIPES.has(recipe_id)


func get_recipe(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = RECIPES.get(recipe_id, {})
	return recipe.duplicate(true)


func get_all_recipe_ids() -> Array[String]:
	var recipe_ids: Array[String] = []
	for recipe_variant in RECIPES.keys():
		recipe_ids.append(str(recipe_variant))
	recipe_ids.sort()
	return recipe_ids


func get_unlocked_recipe_ids() -> Array[String]:
	return unlocked_recipes.duplicate()


func get_unlocked_recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe_id in unlocked_recipes:
		if RECIPES.has(recipe_id):
			result.append(get_recipe(recipe_id))
	return result


func get_recipes_by_category(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe_id in get_all_recipe_ids():
		var recipe: Dictionary = RECIPES.get(recipe_id, {})
		if not category.is_empty() and str(recipe.get("category", "")) != category:
			continue
		result.append(recipe.duplicate(true))
	return result


func get_recipes_for_item(item_id: String) -> Array[Dictionary]:
	var resolved_item_id := _normalize_item_id(item_id)
	var result: Array[Dictionary] = []
	for recipe_id in get_all_recipe_ids():
		var recipe: Dictionary = RECIPES.get(recipe_id, {})
		var output: Dictionary = recipe.get("output", {})
		if _normalize_item_id(output.get("item_id", "")) == resolved_item_id:
			result.append(recipe.duplicate(true))
	return result


func preview_craft(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = RECIPES.get(recipe_id, {})
	if recipe.is_empty():
		return {}

	var output: Dictionary = recipe.get("output", {})
	return {
		"recipe_id": recipe_id,
		"name": str(recipe.get("name", recipe_id)),
		"output_item": str(output.get("item_id", "")),
		"output_count": ValueUtils.to_int(output.get("count", 1), 1),
		"materials": recipe.get("materials", []).duplicate(true),
		"craft_time": float(recipe.get("craft_time", 0.0)),
		"can_craft": can_craft_simple(recipe_id)
	}


func get_craftable_recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe_id in unlocked_recipes:
		if can_craft_simple(recipe_id):
			result.append(get_recipe(recipe_id))
	return result


func get_craftable_recipes_by_category() -> Dictionary:
	var grouped := {}
	for recipe in get_craftable_recipes():
		var category := str(recipe.get("category", "misc"))
		if not grouped.has(category):
			grouped[category] = []
		grouped[category].append(recipe)
	return grouped


func can_craft_simple(recipe_id: String) -> bool:
	return bool(can_craft(recipe_id).get("can_craft", false))


func can_craft(recipe_id: String) -> Dictionary:
	var result := {
		"can_craft": false,
		"missing_materials": [],
		"missing_tools": [],
		"missing_station": false,
		"missing_skills": [],
		"message": "",
		"tool_status": {}
	}

	if not RECIPES.has(recipe_id):
		result["message"] = "配方不存在"
		return result

	if not is_recipe_unlocked(recipe_id):
		result["message"] = "配方未解锁"
		return result

	var recipe: Dictionary = RECIPES[recipe_id]

	for material_variant in recipe.get("materials", []):
		var material: Dictionary = material_variant
		var material_id := _normalize_item_id(material.get("item_id", ""))
		var material_count := ValueUtils.to_int(material.get("count", 1), 1)
		if not InventoryModule or not InventoryModule.has_item(material_id, material_count):
			result["missing_materials"].append({
				"item_id": material_id,
				"item": material_id,
				"required": material_count,
				"count": material_count,
				"current": InventoryModule.get_item_count(material_id) if InventoryModule else 0
			})

	for tool_id in _get_required_tools(recipe):
		var tool_check := _check_tool(tool_id)
		result["tool_status"][tool_id] = tool_check
		if not bool(tool_check.get("has_tool", false)) or bool(tool_check.get("broken", false)):
			result["missing_tools"].append(tool_id)

	for skill_name_variant in recipe.get("skill_requirements", {}).keys():
		var skill_name := str(skill_name_variant)
		var required_level := ValueUtils.to_int(recipe.get("skill_requirements", {}).get(skill_name_variant, 0))
		var current_level := _get_skill_level(skill_name)
		if current_level < required_level:
			result["missing_skills"].append({
				"skill": skill_name,
				"required": required_level,
				"current": current_level
			})

	result["can_craft"] = result["missing_materials"].is_empty() \
		and result["missing_tools"].is_empty() \
		and result["missing_skills"].is_empty() \
		and not bool(result["missing_station"])

	result["message"] = "可以制作" if result["can_craft"] else _format_craft_failure_reason(result)
	return result


func start_crafting(recipe_id: String, target_item_id: String = "") -> bool:
	var check := can_craft(recipe_id)
	if not bool(check.get("can_craft", false)):
		crafting_failed.emit(recipe_id, str(check.get("message", "无法制作")))
		return false

	var recipe: Dictionary = RECIPES.get(recipe_id, {})
	if recipe.is_empty():
		crafting_failed.emit(recipe_id, "配方不存在")
		return false

	var success_chance := _calculate_tool_success_chance(recipe)
	if randf() > success_chance:
		_consume_materials(recipe.get("materials", []))
		crafting_failed.emit(recipe_id, "制作失败！工具状态影响了制作")
		return false

	_consume_materials(recipe.get("materials", []))
	crafting_queue.append({
		"recipe_id": recipe_id,
		"recipe": recipe.duplicate(true),
		"start_time": Time.get_unix_time_from_system(),
		"target_item_id": _normalize_item_id(target_item_id)
	})

	if not is_crafting:
		_start_next_craft()

	print("[CraftingSystem] 开始制作: %s" % recipe_id)
	return true


func cancel_crafting(index: int) -> bool:
	if index < 0 or index >= crafting_queue.size():
		return false

	var craft_item: Dictionary = crafting_queue[index]
	var recipe: Dictionary = craft_item.get("recipe", {})
	for material_variant in recipe.get("materials", []):
		var material: Dictionary = material_variant
		if InventoryModule:
			InventoryModule.add_item(_normalize_item_id(material.get("item_id", "")), ValueUtils.to_int(material.get("count", 1), 1))

	crafting_queue.remove_at(index)

	if index == 0 and is_crafting:
		is_crafting = false
		current_craft_timer = 0.0
		current_recipe.clear()
		_start_next_craft()

	return true


func unlock_recipe(recipe_id: String) -> bool:
	if not RECIPES.has(recipe_id):
		return false

	if unlocked_recipes.has(recipe_id):
		return false

	unlocked_recipes.append(recipe_id)
	var recipe: Dictionary = RECIPES.get(recipe_id, {})
	if bool(recipe.get("is_repair", false)):
		repair_recipe_unlocked.emit(recipe_id)
	else:
		recipe_unlocked.emit(recipe_id)

	print("[CraftingSystem] 解锁配方: %s" % recipe_id)
	return true


func lock_recipe(recipe_id: String) -> void:
	unlocked_recipes.erase(recipe_id)


func unlock_all_recipes() -> void:
	for recipe_id in get_all_recipe_ids():
		if not unlocked_recipes.has(recipe_id):
			unlocked_recipes.append(recipe_id)


func is_recipe_unlocked(recipe_id: String) -> bool:
	return unlocked_recipes.has(recipe_id)


func get_available_recipes(category: String = "") -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for recipe_id in unlocked_recipes:
		var recipe: Dictionary = RECIPES.get(recipe_id, {})
		if recipe.is_empty():
			continue
		if not category.is_empty() and str(recipe.get("category", "")) != category:
			continue

		var check := can_craft(recipe_id)
		var output: Dictionary = recipe.get("output", {})
		available.append({
			"id": recipe_id,
			"name": str(recipe.get("name", recipe_id)),
			"description": str(recipe.get("description", "")),
			"category": str(recipe.get("category", "misc")),
			"materials": recipe.get("materials", []).duplicate(true),
			"output": output.duplicate(true),
			"craft_time": float(recipe.get("craft_time", 0.0)),
			"can_craft": bool(check.get("can_craft", false)),
			"missing_materials": check.get("missing_materials", []).duplicate(true),
			"missing_tools": check.get("missing_tools", []).duplicate(true),
			"tool_required": _get_required_tools(recipe)[0] if not _get_required_tools(recipe).is_empty() else "",
			"required_tools": _get_required_tools(recipe),
			"optional_tools": _get_optional_tools(recipe),
			"is_repair": bool(recipe.get("is_repair", false))
		})

	available.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return available


func get_categories() -> Array[String]:
	var categories: Array[String] = []
	for recipe_id in get_all_recipe_ids():
		var category := str(RECIPES.get(recipe_id, {}).get("category", ""))
		if not category.is_empty() and not categories.has(category):
			categories.append(category)
	categories.sort()
	return categories


func get_crafting_progress() -> float:
	if not is_crafting or current_recipe.is_empty():
		return 0.0

	var total_time := float(current_recipe.get("craft_time", 0.0))
	if total_time <= 0.0:
		return 1.0

	var elapsed := total_time - current_craft_timer
	return clampf(elapsed / total_time, 0.0, 1.0)


func get_crafting_queue() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for craft_item_variant in crafting_queue:
		var craft_item: Dictionary = craft_item_variant
		result.append(craft_item.duplicate(true))
	return result


func get_repair_recipes() -> Array[Dictionary]:
	var repair_recipes: Array[Dictionary] = []
	for recipe_id in unlocked_recipes:
		var recipe: Dictionary = RECIPES.get(recipe_id, {})
		if bool(recipe.get("is_repair", false)):
			repair_recipes.append({
				"id": recipe_id,
				"name": str(recipe.get("name", recipe_id)),
				"target_type": str(recipe.get("target_type", "any")),
				"repair_amount": ValueUtils.to_int(recipe.get("repair_amount", 30), 30)
			})
	return repair_recipes


func can_repair_item(item_id: String) -> Dictionary:
	if _durability_system == null:
		return {"can_repair": false, "reason": "系统未初始化"}

	var normalized_item_id := _normalize_item_id(item_id)
	var durability_info: Dictionary = _durability_system.get_durability_by_item_id(normalized_item_id)
	if bool(durability_info.get("broken", false)):
		return {"can_repair": false, "reason": "物品已完全损坏"}

	if ValueUtils.to_int(durability_info.get("current", 0)) >= ValueUtils.to_int(durability_info.get("max", 0)):
		return {"can_repair": false, "reason": "物品完好"}

	var item_data: Dictionary = ItemDurabilitySystem.ITEM_DURABILITY_DATA.get(normalized_item_id, {})
	var item_type := str(item_data.get("type", "misc"))

	var suitable_recipes: Array[String] = []
	for recipe_id in unlocked_recipes:
		var recipe: Dictionary = RECIPES.get(recipe_id, {})
		if not bool(recipe.get("is_repair", false)):
			continue
		var target_type := str(recipe.get("target_type", "any"))
		if target_type == "any" or target_type == item_type:
			suitable_recipes.append(recipe_id)

	if suitable_recipes.is_empty():
		return {"can_repair": false, "reason": "没有合适的维修配方"}

	return {
		"can_repair": true,
		"recipes": suitable_recipes,
		"current_durability": ValueUtils.to_int(durability_info.get("current", 0)),
		"max_durability": ValueUtils.to_int(durability_info.get("max", 0))
	}


func get_save_data() -> Dictionary:
	var queue_data: Array[Dictionary] = []
	for craft_item_variant in crafting_queue:
		var craft_item: Dictionary = craft_item_variant
		queue_data.append({
			"recipe_id": str(craft_item.get("recipe_id", "")),
			"start_time": ValueUtils.to_int(craft_item.get("start_time", 0)),
			"target_item_id": str(craft_item.get("target_item_id", ""))
		})

	return {
		"unlocked_recipes": unlocked_recipes.duplicate(),
		"crafting_queue": queue_data
	}


func load_save_data(data: Dictionary) -> void:
	unlocked_recipes.clear()
	for recipe_variant in data.get("unlocked_recipes", []):
		var recipe_id := str(recipe_variant)
		if RECIPES.has(recipe_id) and not unlocked_recipes.has(recipe_id):
			unlocked_recipes.append(recipe_id)

	_unlock_default_recipes()

	crafting_queue.clear()
	for craft_item_variant in data.get("crafting_queue", []):
		if not (craft_item_variant is Dictionary):
			continue
		var craft_item: Dictionary = craft_item_variant
		var recipe_id := str(craft_item.get("recipe_id", ""))
		if not RECIPES.has(recipe_id):
			continue
		crafting_queue.append({
			"recipe_id": recipe_id,
			"recipe": RECIPES[recipe_id].duplicate(true),
			"start_time": ValueUtils.to_int(craft_item.get("start_time", 0)),
			"target_item_id": str(craft_item.get("target_item_id", ""))
		})

	is_crafting = false
	current_craft_timer = 0.0
	current_recipe.clear()
	if not crafting_queue.is_empty():
		_start_next_craft()

	print("[CraftingSystem] Loaded save data")


func _normalize_recipe_data(recipe_id: String, raw_recipe: Dictionary) -> Dictionary:
	var recipe: Dictionary = raw_recipe.duplicate(true)
	recipe["id"] = recipe_id
	recipe["name"] = str(recipe.get("name", recipe_id))
	recipe["description"] = str(recipe.get("description", ""))
	recipe["category"] = str(recipe.get("category", "misc"))
	recipe["required_station"] = str(recipe.get("required_station", "none"))
	recipe["craft_time"] = float(recipe.get("craft_time", 0.0))
	recipe["experience_reward"] = ValueUtils.to_int(recipe.get("experience_reward", 0))
	recipe["is_default_unlocked"] = bool(recipe.get("is_default_unlocked", false))
	recipe["durability_influence"] = float(recipe.get("durability_influence", 1.0))
	recipe["is_repair"] = bool(recipe.get("is_repair", false))
	recipe["target_type"] = str(recipe.get("target_type", "any"))
	recipe["repair_amount"] = ValueUtils.to_int(recipe.get("repair_amount", recipe.get("output", {}).get("repair_amount", 30)), 30)

	var output: Dictionary = {}
	var raw_output: Variant = recipe.get("output", {})
	if raw_output is Dictionary:
		output = raw_output.duplicate(true)
	output["item_id"] = _normalize_item_id(output.get("item_id", output.get("item", "")))
	output["item"] = output["item_id"]
	output["count"] = ValueUtils.to_int(output.get("count", 1), 1)
	output["quality_bonus"] = ValueUtils.to_int(output.get("quality_bonus", 0))
	recipe["output"] = output

	var materials: Array[Dictionary] = []
	var raw_materials: Variant = recipe.get("materials", [])
	if raw_materials is Array:
		for material_variant in raw_materials:
			if not (material_variant is Dictionary):
				continue
			var material: Dictionary = material_variant.duplicate(true)
			material["item_id"] = _normalize_item_id(material.get("item_id", material.get("item", "")))
			material["item"] = material["item_id"]
			material["count"] = ValueUtils.to_int(material.get("count", material.get("required", 1)), 1)
			materials.append(material)
	elif raw_materials is Dictionary:
		for material_key in raw_materials.keys():
			materials.append({
				"item_id": _normalize_item_id(material_key),
				"item": _normalize_item_id(material_key),
				"count": ValueUtils.to_int(raw_materials.get(material_key, 1), 1)
			})
	recipe["materials"] = materials

	var required_tools: Array[String] = []
	for tool_variant in recipe.get("required_tools", []):
		required_tools.append(_normalize_item_id(tool_variant))
	var legacy_tool := _normalize_item_id(recipe.get("tool_required", ""))
	if not legacy_tool.is_empty() and not required_tools.has(legacy_tool):
		required_tools.append(legacy_tool)
	recipe["required_tools"] = required_tools

	var optional_tools: Array[String] = []
	for tool_variant in recipe.get("optional_tools", []):
		optional_tools.append(_normalize_item_id(tool_variant))
	recipe["optional_tools"] = optional_tools

	var skill_requirements: Dictionary = {}
	var raw_skill_requirements: Variant = recipe.get("skill_requirements", {})
	if raw_skill_requirements is Dictionary:
		for skill_key in raw_skill_requirements.keys():
			skill_requirements[str(skill_key)] = ValueUtils.to_int(raw_skill_requirements.get(skill_key, 0))
	var legacy_required_level := ValueUtils.to_int(recipe.get("required_level", 0))
	if legacy_required_level > 0 and skill_requirements.is_empty():
		skill_requirements["crafting"] = legacy_required_level
	recipe["skill_requirements"] = skill_requirements

	var unlock_conditions: Array[Dictionary] = []
	for condition_variant in recipe.get("unlock_conditions", []):
		if condition_variant is Dictionary:
			unlock_conditions.append((condition_variant as Dictionary).duplicate(true))
	recipe["unlock_conditions"] = unlock_conditions

	if not recipe["is_default_unlocked"] and legacy_required_level == 0 and unlock_conditions.is_empty():
		recipe["is_default_unlocked"] = true

	return recipe


func _normalize_item_id(value: Variant) -> String:
	var text := str(value).strip_edges()
	if text.is_empty():
		return ""
	if ItemDatabase and ItemDatabase.has_method("resolve_item_id"):
		return str(ItemDatabase.resolve_item_id(text))
	return text


func _unlock_default_recipes() -> void:
	for recipe_id in get_all_recipe_ids():
		var recipe: Dictionary = RECIPES.get(recipe_id, {})
		if bool(recipe.get("is_default_unlocked", false)) and not unlocked_recipes.has(recipe_id):
			unlocked_recipes.append(recipe_id)


func _restore_queue_recipes() -> void:
	var restored_queue: Array[Dictionary] = []
	for craft_item_variant in crafting_queue:
		if not (craft_item_variant is Dictionary):
			continue
		var craft_item: Dictionary = craft_item_variant
		var recipe_id := str(craft_item.get("recipe_id", ""))
		if not RECIPES.has(recipe_id):
			continue
		craft_item["recipe"] = RECIPES[recipe_id].duplicate(true)
		restored_queue.append(craft_item)
	crafting_queue = restored_queue

	if crafting_queue.is_empty():
		is_crafting = false
		current_craft_timer = 0.0
		current_recipe.clear()
	elif is_crafting:
		current_recipe = crafting_queue[0].get("recipe", {}).duplicate(true)


func _get_required_tools(recipe: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for tool_variant in recipe.get("required_tools", []):
		var tool_id := _normalize_item_id(tool_variant)
		if not tool_id.is_empty() and not result.has(tool_id):
			result.append(tool_id)
	return result


func _get_optional_tools(recipe: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for tool_variant in recipe.get("optional_tools", []):
		var tool_id := _normalize_item_id(tool_variant)
		if not tool_id.is_empty() and not result.has(tool_id):
			result.append(tool_id)
	return result


func _check_tool(tool_id: String) -> Dictionary:
	var normalized_tool_id := _normalize_item_id(tool_id)
	if normalized_tool_id.is_empty():
		return {"has_tool": true, "broken": false, "durability_percent": 100.0}

	var has_tool := false
	if InventoryModule:
		has_tool = InventoryModule.has_item(normalized_tool_id)
	if not has_tool and GameState and GameState.has_method("has_item"):
		has_tool = GameState.has_item(normalized_tool_id)

	if not has_tool:
		return {"has_tool": false, "broken": false, "durability_percent": 0.0}

	if _durability_system and _durability_system.has_method("get_durability_by_item_id"):
		var durability: Dictionary = _durability_system.get_durability_by_item_id(normalized_tool_id)
		return {
			"has_tool": true,
			"broken": bool(durability.get("broken", false)),
			"durability_percent": float(durability.get("percent", 100.0))
		}

	return {"has_tool": true, "broken": false, "durability_percent": 100.0}


func _calculate_tool_success_chance(recipe: Dictionary) -> float:
	var success_chance := float(recipe.get("durability_influence", 1.0))

	for tool_id in _get_required_tools(recipe):
		var tool_check := _check_tool(tool_id)
		if bool(tool_check.get("has_tool", false)) and not bool(tool_check.get("broken", false)):
			success_chance += float(tool_check.get("durability_percent", 100.0)) / 100.0 * 0.05

	for tool_id in _get_optional_tools(recipe):
		var tool_check := _check_tool(tool_id)
		if bool(tool_check.get("has_tool", false)) and not bool(tool_check.get("broken", false)):
			success_chance += float(tool_check.get("durability_percent", 100.0)) / 100.0 * 0.03

	if _durability_system and _durability_system.has_method("consume_durability"):
		for tool_id in _get_required_tools(recipe):
			if bool(_check_tool(tool_id).get("has_tool", false)):
				_durability_system.consume_durability(tool_id, 1)

	return clampf(success_chance, 0.0, 1.0)


func _consume_materials(materials: Array) -> void:
	if InventoryModule == null:
		return

	for material_variant in materials:
		if not (material_variant is Dictionary):
			continue
		var material: Dictionary = material_variant
		InventoryModule.remove_item(_normalize_item_id(material.get("item_id", "")), ValueUtils.to_int(material.get("count", 1), 1))


func _start_next_craft() -> void:
	if crafting_queue.is_empty():
		is_crafting = false
		current_craft_timer = 0.0
		current_recipe.clear()
		return

	var craft_item: Dictionary = crafting_queue[0]
	current_recipe = craft_item.get("recipe", {}).duplicate(true)
	current_craft_timer = float(current_recipe.get("craft_time", 0.0))
	is_crafting = true
	crafting_started.emit(str(craft_item.get("recipe_id", "")), current_craft_timer)


func _finish_crafting() -> void:
	if crafting_queue.is_empty():
		is_crafting = false
		current_craft_timer = 0.0
		current_recipe.clear()
		return

	var craft_item: Dictionary = crafting_queue.pop_front()
	var recipe_id := str(craft_item.get("recipe_id", ""))
	var recipe: Dictionary = craft_item.get("recipe", {})
	var output: Dictionary = recipe.get("output", {})
	var output_item_id := _normalize_item_id(output.get("item_id", ""))
	var output_count := ValueUtils.to_int(output.get("count", 1), 1)

	if bool(recipe.get("is_repair", false)):
		_process_repair_result(recipe, str(craft_item.get("target_item_id", "")))
	else:
		_process_craft_result(output)

	crafting_completed.emit(output_item_id, output_count)
	if EventBus and EventBus.has_method("emit"):
		EventBus.emit(EventBus.EventType.CRAFTING_COMPLETED, {
			"recipe": recipe_id,
			"result": {
				"item": output_item_id,
				"count": output_count
			}
		})

	print("[CraftingSystem] 制作完成: %s x%d" % [output_item_id, output_count])
	if crafting_queue.is_empty():
		is_crafting = false
		current_craft_timer = 0.0
		current_recipe.clear()
	else:
		_start_next_craft()


func _process_craft_result(output: Dictionary) -> void:
	var item_id := _normalize_item_id(output.get("item_id", ""))
	var count := ValueUtils.to_int(output.get("count", 1), 1)

	if ItemDatabase and ItemDatabase.has_item(item_id) and ItemDatabase.get_item_type(item_id) == "ammo":
		var equipment_system = GameState.get_equipment_system() if GameState else null
		if equipment_system and equipment_system.has_method("add_ammo"):
			equipment_system.add_ammo(item_id, count)
			return

	if InventoryModule:
		InventoryModule.add_item(item_id, count)


func _process_repair_result(recipe: Dictionary, target_item_id: String) -> void:
	if _durability_system == null or target_item_id.is_empty():
		return

	var repair_amount := float(recipe.get("repair_amount", 30)) / 100.0
	var instance_id: String = str(_durability_system._find_item_instance(_normalize_item_id(target_item_id)))
	if not instance_id.is_empty():
		_durability_system.use_repair_kit(instance_id, repair_amount)


func _get_skill_level(skill_name: String) -> int:
	if SkillSystem and SkillSystem.has_method("get_skill_level"):
		return ValueUtils.to_int(SkillSystem.get_skill_level(skill_name))
	if SkillModule and SkillModule.has_method("get_skill_level"):
		return ValueUtils.to_int(SkillModule.get_skill_level(skill_name))
	if skill_name == "crafting" and GameState:
		return ValueUtils.to_int(GameState.player_level)
	return 0


func _format_craft_failure_reason(check_result: Dictionary) -> String:
	var reasons: Array[String] = []

	var missing_materials: Array = check_result.get("missing_materials", [])
	if not missing_materials.is_empty():
		reasons.append("缺少材料 (%d 种)" % missing_materials.size())

	var missing_tools: Array = check_result.get("missing_tools", [])
	if not missing_tools.is_empty():
		reasons.append("缺少工具: %s" % ", ".join(PackedStringArray(missing_tools)))

	if bool(check_result.get("missing_station", false)):
		reasons.append("需要工作台")

	var missing_skills: Array = check_result.get("missing_skills", [])
	if not missing_skills.is_empty():
		reasons.append("技能等级不足")

	if reasons.is_empty():
		return "无法制作"
	return "; ".join(reasons)
