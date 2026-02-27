extends Node
# ScavengeSystem - 搜刮系统
# 管理搜索机制、工具选择、时间权衡和噪音风险

# ===== 信号 =====
signal search_started(location: String, config: Dictionary)
signal search_completed(results: Dictionary)
signal search_event_triggered(event_data: Dictionary)
signal noise_generated(amount: float, risk: float)
signal tool_broken(tool_id: String)

# ===== 搜索配置 =====
enum SearchTime {
	QUICK = 2,		# 快速搜索 2小时
	STANDARD = 4,   # 标准搜索 4小时
	THOROUGH = 6    # 彻底搜索 6小时
}

# 搜索工具常量
const TOOL_HANDS = "hands"
const TOOL_CROWBAR = "crowbar"
const TOOL_SCREWDRIVER = "screwdriver"
const TOOL_LOCKPICK = "lockpick"
const TOOL_FLASHLIGHT = "flashlight"

# ===== 工具属性 =====
const TOOL_STATS: Dictionary = {
	"hands": {
		"name": "徒手",
		"efficiency": 0.5,
		"noise": 0.1,
		"durability_cost": 0,
		"can_open": ["open_container"],
		"description": "最安静但效率最低"
	},
	"crowbar": {
		"name": "撬棍",
		"efficiency": 1.2,
		"noise": 0.6,
		"durability_cost": 2,
		"can_open": ["open_container", "locked_door", "barred_window", "crate"],
		"description": "强力但噪音大"
	},
	"screwdriver": {
		"name": "螺丝刀",
		"efficiency": 0.9,
		"noise": 0.2,
		"durability_cost": 1,
		"can_open": ["open_container", "vent", "panel", "electronics"],
		"description": "适合精密搜索"
	},
	"lockpick": {
		"name": "开锁器",
		"efficiency": 1.0,
		"noise": 0.15,
		"durability_cost": 1,
		"can_open": ["locked_door", "locked_drawer", "safe"],
		"special_bonus": "发现隐藏物品 +20%",
		"description": "安静开锁，需要技"
	},
	"flashlight": {
		"name": "手电",
		"efficiency": 1.1,
		"noise": 0.1,
		"durability_cost": 1,
		"can_open": ["open_container", "dark_area"],
		"special_bonus": "夜间效率 +50%",
		"description": "夜间搜索必备"
	}
}

# ===== 地点搜刮配置 =====
const LOCATION_LOOT_TABLES: Dictionary = {
	"supermarket": {
		"common": ["canned_food", "water_bottle", "snack", "juice"],
		"uncommon": ["first_aid_kit", "backpack", "flashlight", "battery"],
		"rare": ["medicine", "map", "radio"],
		"base_quality": 1.0,
		"search_difficulty": 0.3
	},
	"hospital": {
		"common": ["bandage", "painkiller", "water_bottle"],
		"uncommon": ["first_aid_kit", "medicine", "syringe", "antibiotics"],
		"rare": ["surgical_kit", "rare_medicine", "medical_equipment"],
		"base_quality": 1.2,
		"search_difficulty": 0.5
	},
	"street_a": {
		"common": ["scrap_metal", "cloth", "wood", "stone"],
		"uncommon": ["crowbar", "rope", "nails", "glass_bottle"],
		"rare": ["hidden_stash", "weapon_part", "electronics"],
		"base_quality": 0.7,
		"search_difficulty": 0.4
	},
	"street_b": {
		"common": ["scrap_metal", "cloth", "wood", "stone"],
		"uncommon": ["crowbar", "rope", "nails", "glass_bottle"],
		"rare": ["hidden_stash", "weapon_part", "electronics"],
		"base_quality": 0.7,
		"search_difficulty": 0.4
	},
	"factory": {
		"common": ["scrap_metal", "wood", "rope", "tools"],
		"uncommon": ["crowbar", "metal_sheet", "gear", "wire"],
		"rare": ["blueprint", "advanced_tools", "machine_part"],
		"base_quality": 1.1,
		"search_difficulty": 0.6
	},
	"subway": {
		"common": ["scrap_metal", "cloth", "bottle"],
		"uncommon": ["backpack", "map", "battery", "canned_food"],
		"rare": ["weapon", "armor", "hidden_cache"],
		"base_quality": 0.9,
		"search_difficulty": 0.7
	},
	"safehouse": {
		"common": ["wood", "cloth", "nails"],
		"uncommon": ["food", "water", "basic_tools"],
		"rare": ["personal_cache"],
		"base_quality": 0.5,
		"search_difficulty": 0.1
	}
}

# ===== 当前搜索状态 =====
var current_search: Dictionary = {}
var _is_searching: bool = false

func _ready():
	print("[ScavengeSystem] 搜刮系统已初始化")

# ===== 搜索配置 =====

## 准备搜索
func prepare_search(location: String, tool_id: String = "hands", time_type: int = SearchTime.STANDARD) -> Dictionary:
	var tool_stats = TOOL_STATS.get(tool_id, TOOL_STATS["hands"])
	var location_data = _get_location_data(location)
	
	# 计算搜索配置
	var config = {
		"location": location,
		"tool_id": tool_id,
		"tool_name": tool_stats.name,
		"time_hours": time_type,
		"efficiency": tool_stats.efficiency,
		"noise_base": tool_stats.noise,
		"can_open": tool_stats.can_open,
		"location_difficulty": location_data.search_difficulty,
		"base_quality": location_data.base_quality
	}
	
	# 计算预期收益
	config["expected_yield"] = _calculate_expected_yield(config)
	
	# 计算噪音风险
	config["noise_risk"] = _calculate_noise_risk(config)
	
	# 计算时间风险 (夜间风险更高)
	config["time_risk"] = _calculate_time_risk(time_type)
	
	return config

## 执行搜索
func execute_search(config: Dictionary) -> Dictionary:
	if _is_searching:
		return {"success": false, "reason": "正在搜索"}
	
	_is_searching = true
	current_search = config
	
	search_started.emit(config.location, config)
	
	# 消耗时间
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager:
		time_manager.advance_hours(config.time_hours)
	
	# 消耗体力
	if GameState:
		var stamina_cost = config.time_hours * 5
		GameState.player_stamina = maxi(0, GameState.player_stamina - stamina_cost)
	
	# 执行搜索流程
	var results = _perform_search(config)
	
	# 生成噪音
	_generate_noise(config)
	
	# 消耗工具耐久
	_consume_tool_durability(config)
	
	_is_searching = false
	search_completed.emit(results)
	
	return results

## 快速搜索接口
func quick_search(location: String, tool_id: String = "hands") -> Dictionary:
	var config = prepare_search(location, tool_id, SearchTime.QUICK)
	return execute_search(config)

## 标准搜索接口
func standard_search(location: String, tool_id: String = "hands") -> Dictionary:
	var config = prepare_search(location, tool_id, SearchTime.STANDARD)
	return execute_search(config)

## 彻底搜索接口
func thorough_search(location: String, tool_id: String = "hands") -> Dictionary:
	var config = prepare_search(location, tool_id, SearchTime.THOROUGH)
	return execute_search(config)

# ===== 搜索计算 =====

func _perform_search(config: Dictionary) -> Dictionary:
	var results = {
		"success": true,
		"items_found": [],
		"events": [],
		"total_value": 0,
		"search_time": config.time_hours
	}
	
	var location_data = _get_location_data(config.location)
	
	# 计算搜索次数 (基于时间)
	var search_attempts = config.time_hours * 2  # 每小时2次搜索机会
	
	# 应用工具效率
	search_attempts *= config.efficiency
	
	# 应用技能加成
	var skill_system = get_node_or_null("/root/SkillSystem")
	if skill_system and skill_system.has_method("get_loot_bonus_chance"):
		var loot_bonus = skill_system.get_loot_bonus_chance()
		search_attempts *= (1.0 + loot_bonus)
	
	# 执行搜索
	for i in range(int(search_attempts)):
		# 判定是否发现物品
		var find_chance = _calculate_find_chance(config, location_data)
		if randf() < find_chance:
			var item = _generate_loot(location_data, config)
			if item:
				results.items_found.append(item)
				results.total_value += _get_item_value(item.id)
		
		# 判定是否触发事件
		var event_chance = 0.15 * config.time_risk  # 时间越长，事件概率越高
		if randf() < event_chance:
			var event = _generate_search_event(config)
			if event:
				results.events.append(event)
				search_event_triggered.emit(event)
	
	# 添加物品到背包
	for item in results.items_found:
		GameState.add_item(item.id, item.count)
	
	return results

func _calculate_find_chance(config: Dictionary, location_data: Dictionary) -> float:
	var base_chance = 0.4
	
	# 时间影响 (长时间搜索更彻底)
	base_chance += (config.time_hours - 2) * 0.05
	
	# 工具效率
	base_chance *= config.efficiency
	
	# 地点难度
	base_chance *= (1.0 - location_data.search_difficulty)
	
	# 夜间惩罚
	if GameState and GameState.is_night():
		if config.tool_id != "flashlight":
			base_chance *= 0.5
	
	return clampf(base_chance, 0.1, 0.9)

func _generate_loot(location_data: Dictionary, config: Dictionary) -> Dictionary:
	var rarity_roll = randf()
	var selected_category = "common"
	
	# 根据时间和工具调整稀有度
	var rare_bonus = (config.time_hours - 2) * 0.05  # 长时间搜索更容易找到稀有物品
	if config.tool_id == "lockpick":
		rare_bonus += 0.1
	
	rarity_roll -= rare_bonus
	
	if rarity_roll < 0.05:
		selected_category = "rare"
	elif rarity_roll < 0.25:
		selected_category = "uncommon"
	
	var loot_table = location_data.get(selected_category, [])
	if loot_table.is_empty():
		return {}
	
	var item_id = loot_table[randi() % loot_table.size()]
	var count = 1
	
	# 某些物品可能有多个
	if item_id in ["canned_food", "water_bottle", "bandage", "bullet"]:
		count = randi_range(1, 3)
	
	return {"id": item_id, "count": count, "rarity": selected_category}

func _get_location_data(location: String) -> Dictionary:
	# 处理类似地点
	if location.begins_with("street_"):
		location = "street_a"
	
	return LOCATION_LOOT_TABLES.get(location, {
		"common": ["scrap_metal", "cloth"],
		"uncommon": ["rope", "wood"],
		"rare": ["tool"],
		"base_quality": 0.5,
		"search_difficulty": 0.5
	})

func _get_item_value(item_id: String) -> int:
	# 简化的物品价值表
	var values = {
		"canned_food": 10, "water_bottle": 10, "snack": 5, "juice": 8,
		"bandage": 15, "first_aid_kit": 50, "medicine": 30, "antibiotics": 100,
		"crowbar": 25, "flashlight": 20, "backpack": 40, "map": 15,
		"weapon": 100, "armor": 80, "ammo": 20,
		"scrap_metal": 5, "wood": 3, "cloth": 5, "rope": 8
	}
	return values.get(item_id, 5)

# ===== 收益和风险计算 =====

func _calculate_expected_yield(config: Dictionary) -> Dictionary:
	var base_items = config.time_hours * 2 * config.efficiency
	var rare_chance = 0.1 + (config.time_hours - 2) * 0.03
	
	return {
		"min_items": int(base_items * 0.5),
		"max_items": int(base_items * 1.5),
		"rare_chance": clampf(rare_chance, 0.05, 0.4)
	}

func _calculate_noise_risk(config: Dictionary) -> Dictionary:
	var base_noise = config.noise_base * config.time_hours
	
	# 夜间噪音传播更远
	if GameState and GameState.is_night():
		base_noise *= 1.5
	
	# 地点影响
	var location_modifiers = {
		"supermarket": 0.8,
		"hospital": 1.0,
		"factory": 1.2,
		"subway": 1.5,  # 封闭空间噪音更大
		"safehouse": 0.3
	}
	
	var location_modifier = location_modifiers.get(config.location, 1.0)
	var final_noise = base_noise * location_modifier
	
	# 计算吸引敌人的风险等级
	var risk_level = "low"
	if final_noise > 3.0:
		risk_level = "extreme"
	elif final_noise > 2.0:
		risk_level = "high"
	elif final_noise > 1.0:
		risk_level = "medium"
	
	return {
		"noise_level": final_noise,
		"risk_level": risk_level,
		"enemy_attract_chance": clampf(final_noise * 0.1, 0.02, 0.5)
	}

func _calculate_time_risk(time_hours: int) -> float:
	# 长时间停留增加风险
	return 1.0 + (time_hours - 2) * 0.1

func _generate_noise(config: Dictionary):
	var noise_data = _calculate_noise_risk(config)
	noise_generated.emit(noise_data.noise_level, noise_data.enemy_attract_chance)
	
	# 可能触发敌人遭遇
	if randf() < noise_data.enemy_attract_chance:
		_trigger_enemy_encounter(noise_data.risk_level)

func _trigger_enemy_encounter(risk_level: String):
	# 通过EventBus触发敌人遭遇
	var enemy_strength = _get_enemy_strength_by_risk(risk_level)
	EventBus.emit(EventBus.EventType.ENEMY_ENCOUNTER, {
		"strength": enemy_strength,
		"reason": "噪音吸引",
		"location": current_search.get("location", "unknown")
	})

func _get_enemy_strength_by_risk(risk_level: String) -> String:
	match risk_level:
		"low": return "weak" if randf() < 0.7 else "normal"
		"medium": return "normal" if randf() < 0.7 else "strong"
		"high": return "strong" if randf() < 0.6 else "elite"
		"extreme": return "elite" if randf() < 0.7 else "boss"
		_: return "normal"

func _consume_tool_durability(config: Dictionary):
	var tool_stats = TOOL_STATS.get(config.tool_id)
	if not tool_stats or tool_stats.durability_cost <= 0:
		return
	
	# 这里应该调用耐久系统来消耗工具耐久
	var durability_system = get_node_or_null("/root/ItemDurabilitySystem")
	if durability_system:
		var total_cost = tool_stats.durability_cost * config.time_hours
		var broken = durability_system.consume_durability(config.tool_id, total_cost)
		if broken:
			tool_broken.emit(config.tool_id)

# ===== 搜索事件系统 =====

func _generate_search_event(config: Dictionary) -> Dictionary:
	var events = [
		{
			"id": "creaking_floor",
			"name": "地板咯吱",
			"description": "你踩到了一块松动的地板，发出了刺耳的声响",
			"choices": [
				{"text": "继续搜索", "risk": 0.3, "reward": "继续搜索但增加噪音"},
				{"text": "小心移动", "risk": 0.1, "reward": "减少搜索效率但更安全"},
				{"text": "放弃搜索", "risk": 0, "reward": "安全离开但浪费时间"}
			],
			"trigger_weight": 1.0
		},
		{
			"id": "hidden_room",
			"name": "发现隐藏房间",
			"description": "你注意到墙壁后面似乎有空间，可能是一个隐藏房间",
			"choices": [
				{"text": "强行破开", "risk": 0.4, "reward": "可能获得稀有物品", "need_tool": "crowbar"},
				{"text": "仔细寻找入口", "risk": 0.2, "reward": "安全进入但耗时"},
				{"text": "标记位置离开", "risk": 0, "reward": "暂时放弃"}
			],
			"trigger_weight": 0.5,
			"rare_bonus": true
		},
		{
			"id": "trap_triggered",
			"name": "触发陷阱",
			"description": "你不小心触发了一个陷阱！",
			"choices": [
				{"text": "尝试躲避", "risk": 0.5, "skill_check": "agility"},
				{"text": "硬抗伤害", "risk": 0.8, "reward": "受到伤害但继续搜索"},
				{"text": "放弃搜索", "risk": 0.2, "reward": "受到部分伤害并离开"}
			],
			"trigger_weight": 0.3
		},
		{
			"id": "other_survivor",
			"name": "遇到其他幸存者",
			"description": "你发现了另一个幸存者正在搜索这个区域",
			"choices": [
				{"text": "尝试交流", "risk": 0.3, "reward": "可能获得交易或信息"},
				{"text": "隐藏观察", "risk": 0.1, "reward": "了解对方情况"},
				{"text": "悄悄离开", "risk": 0.05, "reward": "安全但无收益"},
				{"text": "偷袭对方", "risk": 0.6, "reward": "可能获得所有物品"}
			],
			"trigger_weight": 0.4
		},
		{
			"id": "valuable_discovered",
			"name": "发现贵重物品",
			"description": "你在角落里发现了一些看起来很有价值的东西",
			"choices": [
				{"text": "立即拿取", "risk": 0.2, "reward": "获得物品"},
				{"text": "仔细检查", "risk": 0.1, "reward": "可能发现隐藏物品"},
				{"text": "怀疑是陷阱", "risk": 0, "reward": "放弃但安全"}
			],
			"trigger_weight": 0.6,
			"rare_bonus": true
		},
		{
			"id": "collapsing_structure",
			"name": "结构坍塌",
			"description": "建筑物的某部分开始坍塌，情况危急！",
			"choices": [
				{"text": "快速逃离", "risk": 0.2, "skill_check": "agility"},
				{"text": "寻找掩体", "risk": 0.4, "reward": "可能受伤但继续搜索"},
				{"text": "抓紧搜集", "risk": 0.7, "reward": "高风险的额外搜索"}
			],
			"trigger_weight": 0.2
		},
		{
			"id": "locked_safe",
			"name": "发现保险箱",
			"description": "你发现了一个上锁的保险箱",
			"choices": [
				{"text": "尝试开锁", "risk": 0.3, "need_tool": "lockpick", "skill_check": "lockpicking"},
				{"text": "强行撬开", "risk": 0.5, "need_tool": "crowbar", "reward": "噪音大但有效"},
				{"text": "放弃", "risk": 0, "reward": "无收益"}
			],
			"trigger_weight": 0.4,
			"rare_bonus": true
		},
		{
			"id": "wild_animal",
			"name": "野生动物",
			"description": "一只野生动物出现在你的搜索范围内",
			"choices": [
				{"text": "慢慢后退", "risk": 0.2, "reward": "安全离开"},
				{"text": "大声驱赶", "risk": 0.5, "reward": "可能吓跑但产生噪音"},
				{"text": "准备战斗", "risk": 0.6, "reward": "可能获得食物资源"}
			],
			"trigger_weight": 0.5
		},
		{
			"id": "supply_cache",
			"name": "物资藏匿",
			"description": "你注意到有人在这里藏了物资",
			"choices": [
				{"text": "拿走物资", "risk": 0.3, "reward": "获得物资但可能有风险"},
				{"text": "只拿一点", "risk": 0.1, "reward": "获得少量物资"},
				{"text": "留下标记", "risk": 0, "reward": "可能获得未来友好互动"}
			],
			"trigger_weight": 0.5,
			"rare_bonus": true
		},
		{
			"id": "strange_noise",
			"name": "奇怪的声音",
			"description": "你听到了奇怪的声响，不确定是什么",
			"choices": [
				{"text": "调查声源", "risk": 0.4, "reward": "可能发现隐藏内容"},
				{"text": "保持警惕继续搜索", "risk": 0.3, "reward": "继续搜索但效率降"},
				{"text": "立即离开", "risk": 0.05, "reward": "安全但中断搜"}
			],
			"trigger_weight": 0.7
		}
	]
	
	# 根据配置过滤和选择事件
	var valid_events = []
	for event in events:
		var weight = event.trigger_weight
		# 稀有物品发现加成
		if event.get("rare_bonus", false) and config.time_hours >= SearchTime.STANDARD:
			weight *= 1.5
		
		# 工具影响
		if event.has("need_tool"):
			if event.need_tool in TOOL_STATS.get(config.tool_id, {}).get("can_open", []):
				weight *= 2.0
		
		for i in range(int(weight * 10)):
			valid_events.append(event)
	
	if valid_events.is_empty():
		return {}
	
	return valid_events[randi() % valid_events.size()]

# ===== 公共接口 =====

func get_available_tools() -> Array:
	var tools = []
	for tool_id in TOOL_STATS.keys():
		var tool = TOOL_STATS[tool_id]
		tools.append({
			"id": tool_id,
			"name": tool.name,
			"description": tool.description,
			"has_tool": _check_has_tool(tool_id)
		})
	return tools

func _check_has_tool(tool_id: String) -> bool:
	if tool_id == "hands":
		return true
	if GameState:
		return GameState.has_item(tool_id)
	return false

func is_searching() -> bool:
	return _is_searching

func get_current_search() -> Dictionary:
	return current_search

# ===== 序列"=====
func serialize() -> Dictionary:
	return {
		"is_searching": _is_searching,
		"current_search": current_search
	}

func deserialize(data: Dictionary):
	_is_searching = data.get("is_searching", false)
	current_search = data.get("current_search", {})

