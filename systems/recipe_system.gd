extends Node
## RecipeSystem - 制作配方管理系统
## 管理所有制作配方，提供查询和制作接口
## 注意: 作为Autoload单例，不使用class_name

const RecipeData = preload("res://modules/crafting/recipe_data.gd")

# ========== 信号 ==========
signal recipe_unlocked(recipe_id: String)
signal recipe_completed(recipe_id: String, output_item_id: String, count: int)
signal crafting_started(recipe_id: String, duration: float)
signal crafting_cancelled(recipe_id: String)

# ========== 数据 ==========
var _recipes: Dictionary = {}  # recipe_id -> RecipeData
var _unlocked_recipes: Array[String] = []  # 已解锁的配方ID列表

# ========== 初始化 ==========
func _ready():
	print("[RecipeSystem] 配方系统初始化")
	_load_recipes()

func _load_recipes():
	var data_manager = get_node_or_null("/root/DataManager")
	if data_manager:
		var recipes_data = data_manager.get_data("recipes")
		for recipe_id in recipes_data.keys():
			var recipe = RecipeData.new()
			recipe.deserialize(recipes_data[recipe_id])
			_recipes[recipe_id] = recipe
		
		print("[RecipeSystem] 已加载 %d 个配方" % _recipes.size())
		
		# 默认解锁未设置解锁条件的配方
		for recipe_id in _recipes.keys():
			if _recipes[recipe_id].is_default_unlocked:
				unlock_recipe(recipe_id, false)

# ========== 查询 API ==========

## 获取配方数据
func get_recipe(recipe_id: String) -> RecipeData:
	return _recipes.get(recipe_id, null)

## 获取所有配方ID
func get_all_recipe_ids() -> Array[String]:
	return _recipes.keys()

## 获取所有已解锁的配方
func get_unlocked_recipes() -> Array[RecipeData]:
	var result: Array[RecipeData] = []
	for recipe_id in _unlocked_recipes:
		if _recipes.has(recipe_id):
			result.append(_recipes[recipe_id])
	return result

## 根据类别获取配方
func get_recipes_by_category(category: String) -> Array[RecipeData]:
	var result: Array[RecipeData] = []
	for recipe_id in _unlocked_recipes:
		var recipe = _recipes.get(recipe_id)
		if recipe and recipe.category == category:
			result.append(recipe)
	return result

## 获取产出指定物品的所有配方
func get_recipes_for_item(item_id: String) -> Array[RecipeData]:
	var result: Array[RecipeData] = []
	for recipe_id in _unlocked_recipes:
		var recipe = _recipes.get(recipe_id)
		if recipe and recipe.produces_item(item_id):
			result.append(recipe)
	return result

## 检查配方是否已解锁
func is_recipe_unlocked(recipe_id: String) -> bool:
	return recipe_id in _unlocked_recipes

# ========== 解锁系统 ==========

## 解锁配方
func unlock_recipe(recipe_id: String, emit_signal_flag: bool = true) -> bool:
	if not _recipes.has(recipe_id):
		return false
	
	if recipe_id in _unlocked_recipes:
		return false  # 已经解锁
	
	_unlocked_recipes.append(recipe_id)
	print("[RecipeSystem] 解锁配方: %s" % recipe_id)
	
	if emit_signal_flag:
		recipe_unlocked.emit(recipe_id)
	
	return true

## 锁定配方（用于某些特殊情况）
func lock_recipe(recipe_id: String):
	_unlocked_recipes.erase(recipe_id)

## 解锁所有配方（用于调试）
func unlock_all_recipes():
	for recipe_id in _recipes.keys():
		unlock_recipe(recipe_id, false)
	print("[RecipeSystem] 已解锁所有配方")

# ========== 制作检查 ==========

## 检查是否可以制作
## 返回详细结果，包括缺少的材料
func can_craft(recipe_id: String) -> Dictionary:
	var result = {
		"can_craft": false,
		"missing_materials": [],
		"missing_tools": [],
		"missing_station": false,
		"missing_skills": []
	}
	
	var recipe = get_recipe(recipe_id)
	if not recipe:
		return result
	
	# 检查是否解锁
	if not is_recipe_unlocked(recipe_id):
		return result
	
	# 检查材料
	for mat in recipe.materials:
		var item_id = mat.get("item_id", "")
		var count = mat.get("count", 1)
		
		if not InventoryModule.has_item(item_id, count):
			result.missing_materials.append({
				"item_id": item_id,
				"required": count,
				"current": InventoryModule.get_item_count(item_id)
			})
	
	# 检查工具（在装备槽或背包中）
	for tool_id in recipe.required_tools:
		if not _has_tool(tool_id):
			result.missing_tools.append(tool_id)
	
	# 检查工作台（简化检查，实际应该检查当前位置）
	if recipe.requires_station():
		# 这里应该检查玩家是否在工作台附近
		# 暂时假设总是满足
		pass
	
	# 检查技能
	for skill_name in recipe.skill_requirements.keys():
		var required_level = recipe.skill_requirements[skill_name]
		var current_level = _get_skill_level(skill_name)
		if current_level < required_level:
			result.missing_skills.append({
				"skill": skill_name,
				"required": required_level,
				"current": current_level
			})
	
	result.can_craft = result.missing_materials.is_empty() and \
					   result.missing_tools.is_empty() and \
					   result.missing_station == false and \
					   result.missing_skills.is_empty()
	
	return result

## 简化的检查方法
func can_craft_simple(recipe_id: String) -> bool:
	return can_craft(recipe_id).can_craft

# ========== 制作执行 ==========

## 执行制作
func craft(recipe_id: String) -> Dictionary:
	var result = {
		"success": false,
		"message": "",
		"output_item": "",
		"output_count": 0
	}
	
	# 检查是否可以制作
	var check = can_craft(recipe_id)
	if not check.can_craft:
		result.message = _format_craft_failure_reason(check)
		return result
	
	var recipe = get_recipe(recipe_id)
	
	# 消耗材料
	for mat in recipe.materials:
		var item_id = mat.get("item_id", "")
		var count = mat.get("count", 1)
		InventoryModule.remove_item(item_id, count)
	
	# 产出物品
	var output_item_id = recipe.output_item_id
	var output_count = recipe.output_count
	var quality_bonus = recipe.output_quality_bonus
	
	InventoryModule.add_item(output_item_id, output_count)
	
	# 给予经验
	if recipe.experience_reward > 0:
		_give_crafting_experience(recipe.experience_reward)
	
	result.success = true
	result.output_item = output_item_id
	result.output_count = output_count
	result.message = "制作成功！"
	
	recipe_completed.emit(recipe_id, output_item_id, output_count)
	
	print("[RecipeSystem] 制作完成: %s x%d" % [output_item_id, output_count])
	return result

## 获取制作预览（不执行）
func preview_craft(recipe_id: String) -> Dictionary:
	var recipe = get_recipe(recipe_id)
	if not recipe:
		return {}
	
	return {
		"recipe_id": recipe_id,
		"name": recipe.name,
		"output_item": recipe.output_item_id,
		"output_count": recipe.output_count,
		"materials": recipe.materials,
		"craft_time": recipe.craft_time,
		"can_craft": can_craft_simple(recipe_id)
	}

# ========== 批量操作 ==========

## 获取所有可制作的配方
func get_craftable_recipes() -> Array[RecipeData]:
	var result: Array[RecipeData] = []
	for recipe_id in _unlocked_recipes:
		if can_craft_simple(recipe_id):
			result.append(_recipes[recipe_id])
	return result

## 获取按类别分组的可制作配方
func get_craftable_recipes_by_category() -> Dictionary:
	var result = {}
	for recipe in get_craftable_recipes():
		if not result.has(recipe.category):
			result[recipe.category] = []
		result[recipe.category].append(recipe)
	return result

# ========== 私有方法 ==========

func _has_tool(tool_id: String) -> bool:
	tool_id = str(tool_id)
	# 检查装备槽
	var equip_system = GameState.get_equipment_system() if GameState else null
	var equipped = equip_system.get_equipped_item("main_hand") if equip_system else ""
	if equipped == tool_id:
		return true
	
	# 检查背包
	return InventoryModule.has_item(tool_id)

func _get_skill_level(skill_name: String) -> int:
	# 这里应该查询SkillModule
	# 暂时返回基础等级
	return 1

func _give_crafting_experience(amount: int):
	# 这里应该增加制作技能经验
	if ExperienceSystem:
		ExperienceSystem.add_crafting_exp(amount)

func _format_craft_failure_reason(check_result: Dictionary) -> String:
	var reasons = []
	
	if not check_result.missing_materials.is_empty():
		var mats = check_result.missing_materials
		reasons.append("缺少材料 (%d种)" % mats.size())
	
	if not check_result.missing_tools.is_empty():
		reasons.append("缺少工具: %s" % ", ".join(check_result.missing_tools))
	
	if check_result.missing_station:
		reasons.append("需要工作台")
	
	if not check_result.missing_skills.is_empty():
		reasons.append("技能等级不足")
	
	return "; ".join(reasons)

# ========== 存档/读档 ==========

func get_save_data() -> Dictionary:
	return {
		"unlocked_recipes": _unlocked_recipes.duplicate()
	}

func load_save_data(data: Dictionary):
	var unlocked = data.get("unlocked_recipes", [])
	for recipe_id in unlocked:
		unlock_recipe(recipe_id, false)

# ========== 调试 ==========

func debug_print_recipes():
	print("=== RecipeSystem 配方列表 ===")
	print("总计: %d 个配方" % _recipes.size())
	print("已解锁: %d 个配方" % _unlocked_recipes.size())
	
	var category_count = {}
	for recipe_id in _recipes.keys():
		var cat = _recipes[recipe_id].category
		category_count[cat] = category_count.get(cat, 0) + 1
	
	print("按类别分布:")
	for cat in category_count.keys():
		print("  %s: %d" % [cat, category_count[cat]])
