extends Node
# ExperienceSystem - 经验值与升级系统
# 管理玩家经验值获取、等级计算、升级奖"
# ===== 升级配置 =====
const BASE_XP_REQUIREMENT: int = 100  # 基础经验需"const XP_PER_LEVEL_MULTIPLIER: float = 1.5  # 每级经验需求倍率

# ===== 升级奖励 =====
const STAT_POINTS_PER_LEVEL: int = 3  # 每级获得属性点
const SKILL_POINTS_PER_LEVEL: int = 1  # 每级获得技能点

# ===== 信号 =====
signal level_up(new_level: int, rewards: Dictionary)
signal xp_gained(amount: int, source: String, total_xp: int)
signal xp_to_next_level_changed(xp_needed: int)

# ===== 玩家数据 =====
var current_level: int = 1
var current_xp: int = 0
var total_xp_earned: int = 0  # 累计获得的经验"
# 升级奖励点数
var available_stat_points: int = 0  # 可用属性点
var available_skill_points: int = 0  # 可用技能点
var total_stat_points_earned: int = 0  # 累计获得属性点
var total_skill_points_earned: int = 0  # 累计获得技能点

# ===== 经验来源配置 =====
var xp_sources: Dictionary = {
	"combat_weak": 10,       # 击败弱敌"	"combat_normal": 25,     # 击败普通敌"	"combat_strong": 50,     # 击败强敌
	"combat_elite": 100,     # 击败精英敌人
	"combat_boss": 250,      # 击败BOSS
	
	"exploration_location": 15,   # 发现新地"	"exploration_search": 5,      # 搜索成功
	"exploration_secret": 30,     # 发现秘密
	
	"quest_easy": 20,        # 简单任"	"quest_normal": 50,      # 普通任"	"quest_hard": 100,       # 困难任务
	"quest_main": 200,       # 主线任务
	
	"crafting": 10,          # 制作物品
	"survival_day": 20,      # 生存一"	"first_aid": 5           # 成功治疗
}

func _ready():
	print("[ExperienceSystem] 经验值系统已初始")

# ===== 经验值获"=====

## 获得经验值（通用接口）
func gain_xp(amount: int, source: String = "unknown") -> Dictionary:
	if amount <= 0:
		return {"gained": 0, "leveled_up": false}
	
	current_xp += amount
	total_xp_earned += amount
	
	print("[ExperienceSystem] 获得 %d 经验(来源: %s)" % [amount, source])
	xp_gained.emit(amount, source, current_xp)
	
	# 检查升级
	var level_up_result = _check_level_up()
	
	return {
		"gained": amount,
		"source": source,
		"total_xp": current_xp,
		"leveled_up": level_up_result.leveled_up,
		"levels_gained": level_up_result.levels_gained
	}

## 从预设来源获取经验
func gain_xp_from_source(source_type: String, custom_amount: int = -1) -> Dictionary:
	var amount = custom_amount
	if amount < 0:
		amount = xp_sources.get(source_type, 10)
	return gain_xp(amount, source_type)

## 击败敌人获得经验
func gain_combat_xp(enemy_strength: String = "normal") -> Dictionary:
	var source_key = "combat_" + enemy_strength
	return gain_xp_from_source(source_key)

## 探索获得经验
func gain_exploration_xp(discovery_type: String = "search") -> Dictionary:
	var source_key = "exploration_" + discovery_type
	return gain_xp_from_source(source_key)

## 任务完成获得经验
func gain_quest_xp(quest_difficulty: String = "normal") -> Dictionary:
	var source_key = "quest_" + quest_difficulty
	return gain_xp_from_source(source_key)

# ===== 等级计算 =====

## 计算升到下一级需要的经验
func get_xp_to_next_level() -> int:
	return int(BASE_XP_REQUIREMENT * pow(current_level, 1.2))

## 获取当前等级进度百分"func get_level_progress_percent() -> float:
	var xp_needed = get_xp_to_next_level()
	if xp_needed <= 0:
		return 1.0
	return float(current_xp) / float(xp_needed)

## 获取当前等级的经验条显示
func get_xp_bar_text() -> String:
	var xp_needed = get_xp_to_next_level()
	return "%d / %d XP" % [current_xp, xp_needed]

## 检查并处理升级
func _check_level_up() -> Dictionary:
	var levels_gained = 0
	var rewards_history = []
	
	while current_xp >= get_xp_to_next_level():
		var xp_needed = get_xp_to_next_level()
		current_xp -= xp_needed
		current_level += 1
		levels_gained += 1
		
		# 发放升级奖励
		var rewards = _give_level_up_rewards()
		rewards_history.append(rewards)
		
		print("[ExperienceSystem] 升级！当前等级: %d" % current_level)
		level_up.emit(current_level, rewards)
	
	if levels_gained > 0:
		xp_to_next_level_changed.emit(get_xp_to_next_level())
	
	return {
		"leveled_up": levels_gained > 0,
		"levels_gained": levels_gained,
		"rewards": rewards_history
	}

## 发放升级奖励
func _give_level_up_rewards() -> Dictionary:
	var rewards = {
		"stat_points": STAT_POINTS_PER_LEVEL,
		"skill_points": SKILL_POINTS_PER_LEVEL,
		"hp_restored": 0,
		"stamina_restored": 0,
		"mental_restored": 0
	}
	
	# 属性点和技能点
	available_stat_points += STAT_POINTS_PER_LEVEL
	available_skill_points += SKILL_POINTS_PER_LEVEL
	total_stat_points_earned += STAT_POINTS_PER_LEVEL
	total_skill_points_earned += SKILL_POINTS_PER_LEVEL
	
	# 状态恢复奖励（通过EventBus通知GameState）
	EventBus.emit(EventBus.EventType.PLAYER_HEALED, {
		"hp_percent": 0.3,      # 恢复30% HP
		"stamina_percent": 0.5,  # 恢复50% 体力
		"mental_percent": 0.3    # 恢复30% 精神
	})
	
	rewards.hp_restored = 30
	rewards.stamina_restored = 50
	rewards.mental_restored = 30
	
	return rewards

# ===== 点数管理 =====

## 使用属性点
func spend_stat_points(amount: int = 1) -> bool:
	if available_stat_points >= amount:
		available_stat_points -= amount
		return true
	return false

## 使用技能点
func spend_skill_points(amount: int = 1) -> bool:
	if available_skill_points >= amount:
		available_skill_points -= amount
		return true
	return false

## 返还属性点
func refund_stat_points(amount: int = 1):
	available_stat_points += amount

## 返还技能点
func refund_skill_points(amount: int = 1):
	available_skill_points += amount

## 获取当前可用点数
func get_available_points() -> Dictionary:
	return {
		"stat_points": available_stat_points,
		"skill_points": available_skill_points
	}

## 获取累计获得点数
func get_total_points_earned() -> Dictionary:
	return {
		"stat_points": total_stat_points_earned,
		"skill_points": total_skill_points_earned
	}

# ===== 查询方法 =====

func get_level() -> int:
	return current_level

func get_current_xp() -> int:
	return current_xp

func get_total_xp_earned() -> int:
	return total_xp_earned

## 获取等级称号
func get_level_title() -> String:
	match current_level:
		1: return "幸存"
		2: return "拾荒"
		3: return "探索"
		4: return "战士"
		5: return "猎手"
		6: return "守护"
		7: return "专家"
		8: return "老兵"
		9: return "英雄"
		10: return "传奇"
		_: return "传说+%d" % (current_level - 10)

# ===== 配置方法 =====

## 添加自定义经验来源
func add_xp_source(source_name: String, xp_amount: int):
	xp_sources[source_name] = xp_amount

## 修改现有经验来源
func set_xp_source(source_name: String, xp_amount: int):
	xp_sources[source_name] = xp_amount

# ===== 序列化 =====

func serialize() -> Dictionary:
	return {
		"level": current_level,
		"current_xp": current_xp,
		"total_xp_earned": total_xp_earned,
		"available_stat_points": available_stat_points,
		"available_skill_points": available_skill_points,
		"total_stat_points_earned": total_stat_points_earned,
		"total_skill_points_earned": total_skill_points_earned
	}

func deserialize(data: Dictionary):
	current_level = data.get("level", 1)
	current_xp = data.get("current_xp", 0)
	total_xp_earned = data.get("total_xp_earned", 0)
	available_stat_points = data.get("available_stat_points", 0)
	available_skill_points = data.get("available_skill_points", 0)
	total_stat_points_earned = data.get("total_stat_points_earned", 0)
	total_skill_points_earned = data.get("total_skill_points_earned", 0)
	print("[ExperienceSystem] 经验值数据已加载: 等级 %d" % current_level)

