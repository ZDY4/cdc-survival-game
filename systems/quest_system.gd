extends Node
# QuestSystem - 任务系统

signal quest_started(quest_id: String)
signal quest_updated(quest_id: String, progress: Dictionary)
signal quest_completed(quest_id: String, rewards: Dictionary)
signal quest_failed(quest_id: String, reason: String)

# 任务数据
const QUESTS = {
	"tutorial_survive": {
		"title": "第一课：生存",
		"description": "在安全屋休息一晚，恢复你的状态",
		"objectives": [
			{"type": "sleep", "target": 1, "current": 0, "description": "在安全屋睡觉"}
		],
		"rewards": {
			"items": [{"id": "food_canned", "count": 2}],
			"experience": 50
		},
		"prerequisites": [],
		"time_limit": -1  # -1 表示无时间限制
	},
	
	"first_explore": {
		"title": "初次探索",
		"description": "前往废弃街道探索，至少搜索一次",
		"objectives": [
			{"type": "travel", "target": "street_a", "current": false, "description": "前往废弃街道"},
			{"type": "search", "target": 1, "current": 0, "description": "搜索废弃街道"}
		],
		"rewards": {
			"items": [{"id": "water_bottle", "count": 1}],
			"experience": 100
		},
		"prerequisites": ["tutorial_survive"]
	},
	
	"zombie_hunter": {
		"title": "僵尸猎人",
		"description": "在街道上击败3只僵尸",
		"objectives": [
			{"type": "kill", "target": 3, "current": 0, "enemy_type": "zombie", "description": "击败僵尸"}
		],
		"rewards": {
			"items": [{"id": "bandage", "count": 3}],
			"experience": 200,
			"unlock_location": "hospital"
		},
		"prerequisites": ["first_explore"]
	},
	
	"find_medicine": {
		"title": "寻找药品",
		"description": "前往废弃医院，搜索医疗物资",
		"objectives": [
			{"type": "travel", "target": "hospital", "current": false, "description": "前往医院"},
			{"type": "search", "target": 2, "current": 0, "description": "搜索医院"},
			{"type": "collect", "target": 1, "current": 0, "item_id": 1005, "description": "获得急救包"}
		],
		"rewards": {
			"items": [{"id": "first_aid_kit", "count": 2}],
			"experience": 300,
			"skill_points": 1
		},
		"prerequisites": ["zombie_hunter"]
	},
	
	"survival_day": {
		"title": "生存挑战",
		"description": "存活5天",
		"objectives": [
			{"type": "survive", "target": 5, "current": 0, "description": "存活天数"}
		],
		"rewards": {
			"items": [{"id": "key", "count": 1}],
			"experience": 500,
			"title": "生存专家"
		},
		"prerequisites": ["tutorial_survive"]
	},
	
	"find_food": {
		"title": "食物短缺",
		"description": "前往超市寻找10罐食物",
		"objectives": [
			{"type": "travel", "target": "supermarket", "current": false, "description": "前往超市"},
			{"type": "collect", "target": 10, "current": 0, "item_id": 1007, "description": "收集罐头"}
		],
		"rewards": {
			"items": [{"id": "water_bottle", "count": 5}],
			"experience": 300,
			"skill_points": 2
		},
		"prerequisites": ["first_explore"]
	},
	
	"find_materials": {
		"title": "资源收集",
		"description": "前往工厂收集20个废料",
		"objectives": [
			{"type": "travel", "target": "factory", "current": false, "description": "前往工厂"},
			{"type": "collect", "target": 20, "current": 0, "item_id": 1010, "description": "收集废料"}
		],
		"rewards": {
			"items": [{"id": "tool_kit", "count": 1}],
			"experience": 400,
			"unlock_location": "subway"
		},
		"prerequisites": ["zombie_hunter"]
	},
	
	"explore_underground": {
		"title": "地下探险",
		"description": "探索地铁站，击败5个敌人",
		"objectives": [
			{"type": "travel", "target": "subway", "current": false, "description": "前往地铁"},
			{"type": "search", "target": 3, "current": 0, "description": "搜索地铁"},
			{"type": "kill", "target": 5, "current": 0, "description": "击败敌人"}
		],
		"rewards": {
			"items": [{"id": "first_aid_kit", "count": 3}],
			"experience": 800,
			"skill_points": 3
		},
		"prerequisites": ["find_materials"]
	},
	
	"find_survivors": {
		"title": "寻找幸存者",
		"description": "在地铁站找到通往幸存者营地的路",
		"objectives": [
			{"type": "collect", "target": 1, "current": 0, "item_id": 1148, "description": "获得地铁钥匙"},
			{"type": "search", "target": 5, "current": 0, "description": "搜索各种地点"}
		],
		"rewards": {
			"items": [{"id": "food_canned", "count": 10}, {"id": "water_bottle", "count": 10}],
			"experience": 1000,
			"title": "希望使者",
		},
		"prerequisites": ["explore_underground"]
	},
	
	"master_hunter": {
		"title": "僵尸克星",
		"description": "击败所有类型的僵尸各3只",
		"objectives": [
			{"type": "kill", "target": 3, "current": 0, "enemy_type": "zombie_walker", "description": "击败行尸"},
			{"type": "kill", "target": 3, "current": 0, "enemy_type": "zombie_runner", "description": "击败奔袭者"},
			{"type": "kill", "target": 3, "current": 0, "enemy_type": "zombie_brute", "description": "击败巨力僵尸"},
			{"type": "kill", "target": 3, "current": 0, "enemy_type": "zombie_mutant", "description": "击败变异僵尸"},
		],
		"rewards": {
			"items": [{"id": "machete", "count": 1}],
			"experience": 1500,
			"skill_points": 5
		},
		"prerequisites": ["find_medicine", "explore_underground"]
	},
	
	# === 新剧情任务===
	"craft_weapon": {
		"title": "武装自己",
		"description": "学会制作你的第一把武器",
		"objectives": [
			{"type": "craft", "target": 1, "current": 0, "description": "制作任意武器"}
		],
		"rewards": {
			"items": [{"id": "scrap_metal", "count": 5}],
			"experience": 200,
			"unlock_recipes": ["pipe_wrench", "machete"]
		},
		"prerequisites": ["first_explore"]
	},
	
	"ammo_supply": {
		"title": "弹药补给",
		"description": "制作30发手枪弹药",
		"objectives": [
			{"type": "craft", "target": 30, "current": 0, "item_id": 1009, "description": "制作手枪弹药"}
		],
		"rewards": {
			"items": [{"id": "pistol", "count": 1}],
			"experience": 400,
			"skill_points": 2
		},
		"prerequisites": ["craft_weapon", "find_materials"]
	},
	
	"base_builder": {
		"title": "基地建设",
		"description": "在安全屋建造3个设施",
		"objectives": [
			{"type": "build", "target": 3, "current": 0, "description": "建造设施"}
		],
		"rewards": {
			"items": [{"id": "generator", "count": 1}, {"id": "water_collector", "count": 1}],
			"experience": 600,
			"title": "建筑师",
		},
		"prerequisites": ["zombie_hunter"]
	},
	
	"legendary_weapon": {
		"title": "传说武器",
		"description": "制作一把武士刀",
		"objectives": [
			{"type": "craft", "target": 1, "current": 0, "item_id": 1015, "description": "制作武士刀"}
		],
		"rewards": {
			"items": [{"id": "first_aid_kit", "count": 5}],
			"experience": 1000,
			"skill_points": 3,
			"title": "武器大师"
		},
		"prerequisites": ["master_hunter"]
	},
	
	"nightmare_hunter": {
		"title": "噩梦猎手",
		"description": "击败5只巨型变异体",
		"objectives": [
			{"type": "kill", "target": 5, "current": 0, "enemy_type": "mutant_giant", "description": "击败巨型变异体"},
		],
		"rewards": {
			"items": [{"id": "chainsaw", "count": 1}, {"id": "fuel", "count": 50}],
			"experience": 2000,
			"skill_points": 5,
			"title": "末日幸存者",
		},
		"prerequisites": ["find_survivors", "legendary_weapon"]
	},
	
	"final_stand": {
		"title": "最终防线",
		"description": "生存10天，击败50个敌人",
		"objectives": [
			{"type": "survive", "target": 10, "current": 0, "description": "存活10天"},
			{"type": "kill", "target": 50, "current": 0, "description": "击败50个敌人"},
		],
		"rewards": {
			"items": [{"id": "assault_rifle", "count": 1}, {"id": "ammo_rifle", "count": 90}],
			"experience": 3000,
			"skill_points": 10,
			"title": "传奇幸存者",
		},
		"prerequisites": ["nightmare_hunter"]
	}
}

var active_quests: Dictionary = {}  # quest_id -> quest_data
var completed_quests: Array = []
var failed_quests: Array = []

func _ready():
	# 订阅相关事件
	EventBus.subscribe(EventBus.EventType.GAME_SAVED, _on_game_saved)
	EventBus.subscribe(EventBus.EventType.COMBAT_ENDED, _on_combat_ended)
	EventBus.subscribe(EventBus.EventType.LOCATION_CHANGED, _on_location_changed)
	print("[QuestSystem] 任务系统已初始化")

# 开始任务
func start_quest(quest_id: String):
	if not QUESTS.has(quest_id):
		push_error("Quest not found: " + quest_id)
		return false
	
	if active_quests.has(quest_id) || completed_quests.has(quest_id):
		return false  # 任务已在进行或已完成
	
	var quest_template = QUESTS[quest_id]
	
	# 检查前置条件
	for prereq in quest_template.prerequisites:
		if not completed_quests.has(prereq):
			print("[Quest] Prerequisites not met for: " + quest_id)
			return false
	
	# 创建任务实例
	var quest = quest_template.duplicate(true)
	quest["id"] = quest_id
	quest["start_day"] = GameState.world_day
	quest["start_time"] = Time.get_unix_time_from_system()
	
	active_quests[quest_id] = quest
	
	print("[Quest] Started: " + quest.title)
	quest_started.emit(quest_id)
	
	# 显示任务开始提示
	DialogModule.show_dialog(
		"任务开始：" + quest.title + "\n" + quest.description,
		"任务",
		""
	)
	
	return true

# 更新任务进度
func update_quest_progress(quest_id: String, objective_type: String, amount: int = 1, params: Dictionary = {}):
	if not active_quests.has(quest_id):
		return
	
	var quest = active_quests[quest_id]
	var updated = false
	
	for objective in quest.objectives:
		if objective.type == objective_type:
			# 检查额外条件
			if params.has("enemy_type") && objective.get("enemy_type") != params.enemy_type:
				continue
			if params.has("item_id") && objective.has("item_id"):
				var expected_item = objective.get("item_id")
				var provided_item = params.item_id
				if ItemDatabase:
					expected_item = ItemDatabase.resolve_item_id(str(expected_item))
					provided_item = ItemDatabase.resolve_item_id(str(provided_item))
				if expected_item != provided_item:
					continue
			if params.has("location") && objective.get("target") != params.location:
				continue
			
			# 更新进度
			if typeof(objective.current) == TYPE_BOOL:
				objective.current = true
			else:
				objective.current = min(objective.current + amount, objective.target)
			
			updated = true
			print("[Quest] Progress: %s - %s: %s/%s" % [
				quest.title, 
				objective.description,
				objective.current,
				objective.target
			])
	
	if updated:
		quest_updated.emit(quest_id, _get_quest_progress(quest_id))
		_check_quest_completion(quest_id)

# 检查任务完成
func _check_quest_completion(quest_id: String):
	if not active_quests.has(quest_id):
		return
	
	var quest = active_quests[quest_id]
	var all_complete = true
	
	for objective in quest.objectives:
		if typeof(objective.current) == TYPE_BOOL:
			if not objective.current:
				all_complete = false
				break
		else:
			if objective.current < objective.target:
				all_complete = false
				break
	
	if all_complete:
		complete_quest(quest_id)

# 完成任务
func complete_quest(quest_id: String):
	if not active_quests.has(quest_id):
		return
	
	var quest = active_quests[quest_id]
	
	# 给予奖励
	_give_rewards(quest.rewards)
	
	# 移动任务到已完成
	active_quests.erase(quest_id)
	completed_quests.append(quest_id)
	
	print("[Quest] Completed: " + quest.title)
	quest_completed.emit(quest_id, quest.rewards)
	
	# 显示完成提示
	var reward_text = _format_rewards(quest.rewards)
	DialogModule.show_dialog(
		"任务完成" + quest.title + "\n" + reward_text,
		"任务",
		""
	)

# 给予奖励
func _give_rewards(rewards: Dictionary):
	if rewards.has("items"):
		for item in rewards.items:
			InventoryModule.add_item(item.id, item.count)
	
	if rewards.has("experience"):
		# 这里可以添加到玩家经验系统
		print("[Quest] Gained %d experience" % rewards.experience)
	
	if rewards.has("skill_points"):
		SkillModule.add_skill_points(rewards.skill_points)
	
	if rewards.has("unlock_location"):
		MapModule.unlock_location(rewards.unlock_location)
		print("[Quest] Unlocked location: " + rewards.unlock_location)

# 格式化奖励文本
func _format_rewards(rewards: Dictionary):
	var text = "奖励：\n"
	
	if rewards.has("items"):
		for item in rewards.items:
			text += "  - %s x%d\n" % [item.id, item.count]
	
	if rewards.has("experience"):
		text += "  - %d 经验\n" % rewards.experience
	
	if rewards.has("skill_points"):
		text += "  - %d 技能点\n" % rewards.skill_points
	
	return text

# 获取任务进度
func _get_quest_progress(quest_id: String):
	if not active_quests.has(quest_id):
		return {}
	
	var quest = active_quests[quest_id]
	var progress = {}
	
	for i in range(quest.objectives.size()):
		var obj = quest.objectives[i]
		progress[i] = {
			"current": obj.current,
			"target": obj.target,
			"description": obj.description
		}
	
	return progress

# 获取可用任务
func get_available_quests():
	var available = []
	
	for quest_id in QUESTS.keys():
		if active_quests.has(quest_id) || completed_quests.has(quest_id):
			continue
		
		var quest = QUESTS[quest_id]
		var can_start = true
		
		for prereq in quest.prerequisites:
			if not completed_quests.has(prereq):
				can_start = false
				break
		
		if can_start:
			available.append({
				"id": quest_id,
				"title": quest.title,
				"description": quest.description
			})
	
	return available

# 获取当前任务列表
func get_active_quests():
	var quests = []
	for quest_id in active_quests.keys():
		var quest = active_quests[quest_id]
		quests.append({
			"id": quest_id,
			"title": quest.title,
			"description": quest.description,
			"progress": _get_quest_progress(quest_id)
		})
	return quests

# 事件处理
func _on_game_saved():
	# 检查生存天数任务
	for quest_id in active_quests.keys():
		var quest = active_quests[quest_id]
		for objective in quest.objectives:
			if objective.type == "sleep" || objective.type == "survive":
				update_quest_progress(quest_id, objective.type, 1)

func _on_combat_ended(data: Dictionary):
	if data.victory && data.has("enemy_data"):
		var enemy = data.enemy_data
		# 更新击杀任务
		for quest_id in active_quests.keys():
			update_quest_progress(quest_id, "kill", 1, {"enemy_type": enemy.get("type", "zombie")})

func _on_location_changed(data: Dictionary):
	var location = data.get("location", "")
	# 更新旅行任务
	for quest_id in active_quests.keys():
		update_quest_progress(quest_id, "travel", 1, {"location": location})

# 公共方法：搜索
func on_search_completed():
	for quest_id in active_quests.keys():
		update_quest_progress(quest_id, "search", 1)
		update_quest_progress(quest_id, "collect")  # 检查是否收集到所需物品

# 保存/加载
func get_save_data():
	return {
		"active_quests": active_quests,
		"completed_quests": completed_quests,
		"failed_quests": failed_quests
	}

func load_save_data(data: Dictionary):
	active_quests = data.get("active_quests", {})
	completed_quests = data.get("completed_quests", [])
	failed_quests = data.get("failed_quests", [])
	print("[QuestSystem] Loaded save data")



