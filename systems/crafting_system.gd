extends Node
# CraftingSystem - 制作系统
# 管理配方、制作队列、材料检查
signal crafting_started(recipe_id: String, craft_time: float)
signal crafting_completed(item_id: String, count: int)
signal crafting_failed(recipe_id: String, reason: String)
signal recipe_unlocked(recipe_id: String)
signal repair_recipe_unlocked(recipe_id: String)

# ===== 制作配方数据 =====
const RECIPES = {
	# === 基础物品 ===
	"bandage": {
		"name": "绷带",
		"description": "基础医疗用品，恢复 10HP",
		"category": "medical",
		"materials": [
			{"item": 1011, "count": 2}
		],
		"output": {"item": 1006, "count": 1},
		"craft_time": 10.0,
		"required_level": 0,
		"required_station": "none",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"first_aid_kit": {
		"name": "急救",
		"description": "恢复50HP",
		"category": "medical",
		"materials": [
			{"item": 1006, "count": 2},
			{"item": 1030, "count": 1}
		],
		"output": {"item": 1005, "count": 1},
		"craft_time": 30.0,
		"required_level": 2,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	# === 武器制作 ===
	"knife": {
		"name": "小刀",
		"description": "近战武器，耐久100，适合精准攻击",
		"category": "weapon",
		"materials": [
			{"item": 1010, "count": 3},
			{"item": 1012, "count": 1}
		],
		"output": {"item": 1002, "count": 1},
		"craft_time": 30.0,
		"required_level": 1,
		"required_station": "workbench",
		"tool_required": 1151,
		"durability_influence": 1.0
	},
	
	"baseball_bat": {
		"name": "棒球",
		"description": "钝器，耐久80，制作简",
		"category": "weapon",
		"materials": [
			{"item": 1010, "count": 5}
		],
		"output": {"item": 1003, "count": 1},
		"craft_time": 45.0,
		"required_level": 1,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"pipe_wrench": {
		"name": "管钳",
		"description": "重型钝器/工具，耐久120，可用于战斗和维",
		"category": "weapon",
		"materials": [
			{"item": 1010, "count": 8},
			{"item": 1144, "count": 1}
		],
		"output": {"item": 1013, "count": 1},
		"craft_time": 60.0,
		"required_level": 2,
		"required_station": "workbench",
		"tool_required": 1151,
		"durability_influence": 1.0
	},
	
	"machete": {
		"name": "砍刀",
		"description": "锋利的砍刀，耐久120，适合野外生存",
		"category": "weapon",
		"materials": [
			{"item": 1010, "count": 10},
			{"item": 1144, "count": 1}
		],
		"output": {"item": 1014, "count": 1},
		"craft_time": 90.0,
		"required_level": 3,
		"required_station": "workbench",
		"tool_required": 1151,
		"durability_influence": 1.0
	},
	
	"crowbar": {
		"name": "撬棍",
		"description": "多功能工具武器，耐久150，可用于撬锁和战斗",
		"category": "weapon",
		"materials": [
			{"item": 1010, "count": 12}
		],
		"output": {"item": 1125, "count": 1},
		"craft_time": 75.0,
		"required_level": 2,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	# === 弹药制作 ===
	"ammo_pistol": {
		"name": "手枪弹药",
		"description": "用于手枪",
		"category": "ammo",
		"materials": [
			{"item": 1010, "count": 1},
			{"item": 1012, "count": 1}
		],
		"output": {"item": 1009, "count": 5},
		"craft_time": 20.0,
		"required_level": 3,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"ammo_shotgun": {
		"name": "霰弹",
		"description": "用于霰弹",
		"category": "ammo",
		"materials": [
			{"item": 1010, "count": 2}
		],
		"output": {"item": 1021, "count": 4},
		"craft_time": 25.0,
		"required_level": 4,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"ammo_rifle": {
		"name": "步枪弹药",
		"description": "用于步枪",
		"category": "ammo",
		"materials": [
			{"item": 1010, "count": 2},
			{"item": 1012, "count": 1}
		],
		"output": {"item": 1022, "count": 5},
		"craft_time": 30.0,
		"required_level": 5,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"fuel": {
		"name": "燃料",
		"description": "用于电锯",
		"category": "ammo",
		"materials": [
			{"item": 1010, "count": 1},
			{"item": 1012, "count": 2}
		],
		"output": {"item": 1147, "count": 10},
		"craft_time": 40.0,
		"required_level": 6,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	# === 工具制作 ===
	"tool_kit": {
		"name": "工具",
		"description": "制作必需品，耐久100",
		"category": "tool",
		"materials": [
			{"item": 1010, "count": 5},
			{"item": 1012, "count": 2}
		],
		"output": {"item": 1144, "count": 1},
		"craft_time": 60.0,
		"required_level": 2,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"lockpick": {
		"name": "开锁器",
		"description": "打开上锁的门和箱子，耐久50，制作简",
		"category": "tool",
		"materials": [
			{"item": 1010, "count": 2}
		],
		"output": {"item": 1150, "count": 3},
		"craft_time": 15.0,
		"required_level": 2,
		"required_station": "none",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"screwdriver": {
		"name": "螺丝刀",
		"description": "精密工具，耐久80，提高制作成功率",
		"category": "tool",
		"materials": [
			{"item": 1010, "count": 3}
		],
		"output": {"item": 1151, "count": 1},
		"craft_time": 20.0,
		"required_level": 1,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"flashlight": {
		"name": "手电",
		"description": "夜间搜索必备，耐久100，需要电",
		"category": "tool",
		"materials": [
			{"item": 1010, "count": 2},
			{"item": 1012, "count": 2}
		],
		"output": {"item": 1126, "count": 1},
		"craft_time": 30.0,
		"required_level": 2,
		"required_station": "workbench",
		"tool_required": 1151,
		"durability_influence": 1.0
	},
	
	# === 护甲制作 ===
	"cloth_armor": {
		"name": "布甲",
		"description": "基础护甲，耐久50，轻便但防护有限",
		"category": "armor",
		"materials": [
			{"item": 1011, "count": 8}
		],
		"output": {"item": 2004, "count": 1},
		"craft_time": 40.0,
		"required_level": 1,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"leather_jacket": {
		"name": "皮夹",
		"description": "皮制护甲，耐久80，较好的防护",
		"category": "armor",
		"materials": [
			{"item": 1011, "count": 5},
			{"item": 1010, "count": 2}
		],
		"output": {"item": 2005, "count": 1},
		"craft_time": 50.0,
		"required_level": 2,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"kevlar_vest": {
		"name": "凯夫拉背",
		"description": "防弹护甲，耐久150，优秀的防",
		"category": "armor",
		"materials": [
			{"item": 1011, "count": 10},
			{"item": 1010, "count": 8},
			{"item": 1012, "count": 3}
		],
		"output": {"item": 2007, "count": 1},
		"craft_time": 90.0,
		"required_level": 4,
		"required_station": "workbench",
		"tool_required": 1151,
		"durability_influence": 1.0
	},
	
	"helmet": {
		"name": "头盔",
		"description": "头部防护，耐久100",
		"category": "armor",
		"materials": [
			{"item": 1010, "count": 5},
			{"item": 1011, "count": 3}
		],
		"output": {"item": 2001, "count": 1},
		"craft_time": 45.0,
		"required_level": 2,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	# === 基地建设 ===
	"barricade_wood": {
		"name": "木制路障",
		"description": "阻挡敌人",
		"category": "base",
		"materials": [
			{"item": 1010, "count": 5}
		],
		"output": {"item": 1156, "count": 1},
		"craft_time": 30.0,
		"required_level": 1,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"generator": {
		"name": "发电",
		"description": "提供电力",
		"category": "base",
		"materials": [
			{"item": 1010, "count": 15},
			{"item": 1012, "count": 5},
			{"item": 1144, "count": 1}
		],
		"output": {"item": 1145, "count": 1},
		"craft_time": 120.0,
		"required_level": 4,
		"required_station": "workbench",
		"tool_required": 1151,
		"durability_influence": 1.0
	},
	
	"water_collector": {
		"name": "集水",
		"description": "自动收集雨水",
		"category": "base",
		"materials": [
			{"item": 1010, "count": 8},
			{"item": 1012, "count": 2}
		],
		"output": {"item": 1146, "count": 1},
		"craft_time": 60.0,
		"required_level": 3,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	"grow_box": {
		"name": "种植",
		"description": "种植食物",
		"category": "base",
		"materials": [
			{"item": 1010, "count": 5}
		],
		"output": {"item": 1157, "count": 1},
		"craft_time": 45.0,
		"required_level": 2,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 1.0
	},
	
	# === 维修配方 ===
	"repair_weapon_basic": {
		"name": "基础武器维修",
		"description": "恢复武器30%耐久",
		"category": "repair",
		"materials": [
			{"item": 1010, "count": 2},
			{"item": 1011, "count": 1}
		],
		"output": {"item": 1152, "count": 1, "repair_amount": 30},
		"craft_time": 20.0,
		"required_level": 1,
		"required_station": "workbench",
		"tool_required": 1151,
		"durability_influence": 0.8,
		"is_repair": true,
		"target_type": "weapon"
	},
	
	"repair_armor_basic": {
		"name": "基础护甲维修",
		"description": "恢复护甲30%耐久",
		"category": "repair",
		"materials": [
			{"item": 1011, "count": 3},
			{"item": 1010, "count": 1}
		],
		"output": {"item": 1153, "count": 1, "repair_amount": 30},
		"craft_time": 20.0,
		"required_level": 1,
		"required_station": "workbench",
		"tool_required": "",
		"durability_influence": 0.8,
		"is_repair": true,
		"target_type": "armor"
	},
	
	"repair_tool_basic": {
		"name": "基础工具维修",
		"description": "恢复工具40%耐久",
		"category": "repair",
		"materials": [
			{"item": 1010, "count": 1},
			{"item": 1100, "count": 1}
		],
		"output": {"item": 1154, "count": 1, "repair_amount": 40},
		"craft_time": 15.0,
		"required_level": 1,
		"required_station": "none",
		"tool_required": "",
		"durability_influence": 0.9,
		"is_repair": true,
		"target_type": "tool"
	},
	
	"repair_advanced": {
		"name": "高级维修套件",
		"description": "恢复任何装备50%耐久",
		"category": "repair",
		"materials": [
			{"item": 1010, "count": 5},
			{"item": 1011, "count": 3},
			{"item": 1144, "count": 1}
		],
		"output": {"item": 1155, "count": 1, "repair_amount": 50},
		"craft_time": 60.0,
		"required_level": 3,
		"required_station": "workbench",
		"tool_required": 1151,
		"durability_influence": 1.0,
		"is_repair": true,
		"target_type": "any"
	}
}

# ===== 制作队列 =====
var crafting_queue: Array[Dictionary] = []
var is_crafting: bool = false
var current_craft_timer: float = 0.0
var current_recipe: Dictionary = {}
var _durability_system: Node = null

# ===== 已解锁配"=====
var unlocked_recipes: Array[String] = []

func _ready():
	print("[CraftingSystem] 制作系统已初始化")
	_durability_system = get_node_or_null("/root/ItemDurabilitySystem")
	_unlock_default_recipes()

func _process(delta: float):
	if is_crafting and crafting_queue.size() > 0:
		current_craft_timer -= delta
		
		if current_craft_timer <= 0:
			_finish_crafting(crafting_queue[0].recipe_id if crafting_queue.size() > 0 else "")

# 解锁默认配方
func _unlock_default_recipes():
	for recipe_id in RECIPES.keys():
		var recipe = RECIPES[recipe_id]
		if recipe.required_level == 0 and not recipe.get("is_repair", false):
			unlocked_recipes.append(recipe_id)

# 检查是否可以制作
func can_craft(recipe_id: String) -> Dictionary:
	var result = {
		"can_craft": false,
		"missing_materials": [],
		"message": "",
		"tool_status": {}
	}
	
	if not RECIPES.has(recipe_id):
		result.message = "配方不存在"
		return result
	
	if not recipe_id in unlocked_recipes:
		result.message = "配方未解锁"
		return result
	
	var recipe = RECIPES[recipe_id]
	
	# 检查等级
	var player_level = _get_player_level()
	if player_level < recipe.required_level:
		result.message = "等级不足 (需要等级 %d)" % recipe.required_level
		return result
	
	# 检查所需工具
	if recipe.has("tool_required") and not recipe.tool_required.is_empty():
		var tool_check = _check_required_tool(recipe.tool_required)
		result.tool_status = tool_check
		if not tool_check.has_tool:
			result.message = "缺少工具: %s" % recipe.tool_required
			return result
		if tool_check.broken:
			result.message = "工具已损坏"
			return result
	
	# 检查材料
	for material in recipe.materials:
		if not InventoryModule.has_item(material.item, material.count):
			result.missing_materials.append(material)
	
	if result.missing_materials.size() > 0:
		result.message = "材料不足"
		return result
	
	result.can_craft = true
	result.message = "可以制作"
	return result

## 检查所需工具
func _check_required_tool(tool_id: String) -> Dictionary:
	tool_id = str(tool_id)
	if tool_id.is_empty():
		return {"has_tool": true, "broken": false, "durability_percent": 100}
	
	var has_tool = InventoryModule.has_item(tool_id) or GameState.has_item(tool_id)
	
	if not has_tool:
		return {"has_tool": false, "broken": false, "durability_percent": 0}
	
	# 检查工具耐久
	if _durability_system:
		var durability = _durability_system.get_durability_by_item_id(tool_id)
		return {
			"has_tool": true,
			"broken": durability.broken,
			"durability_percent": durability.percent
		}
	
	return {"has_tool": true, "broken": false, "durability_percent": 100}

## 计算工具对成功率的影响
func _calculate_tool_success_chance(recipe: Dictionary) -> float:
	var base_chance = 1.0
	
	if recipe.has("tool_required") and not recipe.tool_required.is_empty():
		var tool_check = _check_required_tool(recipe.tool_required)
		if tool_check.has_tool and not tool_check.broken:
			# 耐久越高，成功率越高
			var durability_bonus = tool_check.durability_percent / 100.0 * 0.2
			base_chance += durability_bonus
		
		# 消耗工具耐久
		if _durability_system:
			_durability_system.consume_durability(recipe.tool_required, 1)
	
	# 应用配方本身的成功率修正
	if recipe.has("durability_influence"):
		base_chance *= recipe.durability_influence
	
	return minf(base_chance, 1.0)

# 开始制作
func start_crafting(recipe_id: String, target_item_id: String = "") -> bool:
	var check = can_craft(recipe_id)
	if not check.can_craft:
		crafting_failed.emit(recipe_id, check.message)
		return false
	
	var recipe = RECIPES[recipe_id]
	
	# 计算实际成功率
	var success_chance = _calculate_tool_success_chance(recipe)
	var roll = randf()
	
	if roll > success_chance:
		# 制作失败
		_consume_materials(recipe.materials)
		crafting_failed.emit(recipe_id, "制作失败！工具状态影响了制作")
		return false
	
	# 消耗材料
	_consume_materials(recipe.materials)
	
	# 添加到队列
	crafting_queue.append({
		"recipe_id": recipe_id,
		"recipe": recipe,
		"start_time": Time.get_unix_time_from_system(),
		"target_item_id": target_item_id  # 用于维修配方的目标物品
	})
	
	# 如果没有正在制作，开始制作
	if not is_crafting:
		_start_next_craft()
	
	print("[Crafting] Started: " + recipe.name)
	return true

func _consume_materials(materials: Array):
	for material in materials:
		InventoryModule.remove_item(material.item, material.count)

func _start_next_craft():
	if crafting_queue.size() == 0:
		is_crafting = false
		return
	
	var craft_item = crafting_queue[0]
	current_recipe = craft_item.recipe
	current_craft_timer = current_recipe.craft_time
	is_crafting = true
	
	crafting_started.emit(craft_item.recipe_id, current_recipe.craft_time)

func _finish_crafting(recipe_id: String):
	if crafting_queue.size() == 0:
		return
	
	var craft_item = crafting_queue.pop_front()
	var recipe = craft_item.recipe
	var output = recipe.output
	
	# 检查是否是维修配方
	if recipe.get("is_repair", false):
		_process_repair_result(recipe, craft_item.get("target_item_id", ""))
	else:
		# 添加产物到背包
		_process_craft_result(output)
	
	crafting_completed.emit(output.item, output.get("count", 1))
	print("[Crafting] Completed: %s x%d" % [output.item, output.get("count", 1)])
	
	# 开始下一个
	if crafting_queue.size() > 0:
		_start_next_craft()
	else:
		is_crafting = false

func _process_craft_result(output: Dictionary):
	# 优先使用统一装备系统
	if ItemDatabase.has_item(output.item):
		if ItemDatabase.get_item_type(output.item) == "ammo":
			var equip_system = GameState.get_equipment_system() if GameState else null
			if equip_system:
				equip_system.add_ammo(str(output.item), output.count)
		else:
			InventoryModule.add_item(output.item, output.count)
	else:
		InventoryModule.add_item(output.item, output.count)

func _process_repair_result(recipe: Dictionary, target_item_id: String):
	if not _durability_system or target_item_id.is_empty():
		return
	
	var repair_amount = recipe.output.get("repair_amount", 30)
	var instance_id = _durability_system._find_item_instance(target_item_id)
	
	if not instance_id.is_empty():
		_durability_system.use_repair_kit(instance_id, repair_amount / 100.0)

# 取消制作
func cancel_crafting(index: int) -> bool:
	if index >= crafting_queue.size():
		return false
	
	var craft_item = crafting_queue[index]
	
	# 退还材料
	for material in craft_item.recipe.materials:
		InventoryModule.add_item(material.item, material.count)
	
	crafting_queue.remove_at(index)
	
	# 如果取消的是正在制作的，开始下一个
	if index == 0 and is_crafting:
		is_crafting = false
		_start_next_craft()
	
	return true

# 解锁配方
func unlock_recipe(recipe_id: String) -> bool:
	if not RECIPES.has(recipe_id):
		return false
	
	if recipe_id in unlocked_recipes:
		return false
	
	unlocked_recipes.append(recipe_id)
	
	var recipe = RECIPES[recipe_id]
	if recipe.get("is_repair", false):
		repair_recipe_unlocked.emit(recipe_id)
	else:
		recipe_unlocked.emit(recipe_id)
	
	print("[Crafting] Unlocked recipe: " + recipe.name)
	return true

# 检查配方是否解锁
func is_recipe_unlocked(recipe_id: String) -> bool:
	return recipe_id in unlocked_recipes

# 获取可制作配方列表
func get_available_recipes(category: String = "") -> Array[Dictionary]:
	var available = []
	
	for recipe_id in unlocked_recipes:
		var recipe = RECIPES[recipe_id]
		
		if category != "" and recipe.category != category:
			continue
		
		var check = can_craft(recipe_id)
		
		available.append({
			"id": recipe_id,
			"name": recipe.name,
			"description": recipe.description,
			"category": recipe.category,
			"materials": recipe.materials,
			"output": recipe.output,
			"craft_time": recipe.craft_time,
			"can_craft": check.can_craft,
			"missing_materials": check.missing_materials,
			"tool_required": recipe.get("tool_required", ""),
			"is_repair": recipe.get("is_repair", false)
		})
	
	return available

# 获取制作进度
func get_crafting_progress() -> float:
	if not is_crafting or current_recipe.is_empty():
		return 0.0
	
	var total_time = current_recipe.craft_time
	var elapsed = total_time - current_craft_timer
	return clampf(elapsed / total_time, 0.0, 1.0)

# 获取制作队列
func get_crafting_queue() -> Array[Dictionary]:
	return crafting_queue.duplicate()

# 获取分类列表
func get_categories() -> Array[String]:
	return ["medical", "weapon", "ammo", "tool", "armor", "base", "repair"]

# 辅助方法
func _get_player_level() -> int:
	if GameState:
		return GameState.player_level
	return 1

# ===== 维修配方接口 =====

func get_repair_recipes() -> Array[Dictionary]:
	var repair_recipes = []
	for recipe_id in unlocked_recipes:
		var recipe = RECIPES[recipe_id]
		if recipe.get("is_repair", false):
			repair_recipes.append({
				"id": recipe_id,
				"name": recipe.name,
				"target_type": recipe.get("target_type", "any"),
				"repair_amount": recipe.output.get("repair_amount", 30)
			})
	return repair_recipes

func can_repair_item(item_id: String) -> Dictionary:
	if not _durability_system:
		return {"can_repair": false, "reason": "系统未初始化"}
	
	var durability_info = _durability_system.get_durability_by_item_id(item_id)
	if durability_info.broken:
		return {"can_repair": false, "reason": "物品已完全损"}
	
	if durability_info.current >= durability_info.max:
		return {"can_repair": false, "reason": "物品完好"}
	
	# 查找合适的维修配方
	var item_data = ItemDurabilitySystem.ITEM_DURABILITY_DATA.get(item_id, {})
	var item_type = item_data.get("type", "misc")
	
	var suitable_recipes = []
	for recipe_id in unlocked_recipes:
		var recipe = RECIPES[recipe_id]
		if recipe.get("is_repair", false):
			var target_type = recipe.get("target_type", "any")
			if target_type == "any" or target_type == item_type:
				suitable_recipes.append(recipe_id)
	
	if suitable_recipes.is_empty():
		return {"can_repair": false, "reason": "没有合适的维修配方"}
	
	return {
		"can_repair": true,
		"recipes": suitable_recipes,
		"current_durability": durability_info.current,
		"max_durability": durability_info.max
	}

# 保存/加载
func get_save_data() -> Dictionary:
	return {
		"unlocked_recipes": unlocked_recipes,
		"crafting_queue": crafting_queue
	}

func load_save_data(data: Dictionary):
	unlocked_recipes = data.get("unlocked_recipes", [])
	crafting_queue = data.get("crafting_queue", [])
	
	# 恢复制作
	if crafting_queue.size() > 0:
		_start_next_craft()
	
	print("[CraftingSystem] Loaded save data")





