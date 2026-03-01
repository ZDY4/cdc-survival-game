extends Node
# BalanceConfig - 游戏平衡配置
# 集中管理所有游戏数值，方便调试和平"
class_name BalanceConfig

# ===== 状态系统平"=====
const STATUS_BALANCE = {
	"hunger_decay_per_hour": 2,
	"thirst_decay_per_hour": 3,
	"stamina_decay_per_hour": 1,
	"mental_decay_per_hour": 1,
	"hp_regen_base": 0.5,
	"immunity_regen_base": 0.05
}

# ===== 体温系统 =====
const TEMPERATURE_BALANCE = {
	"normal_min": 35.0,
	"normal_max": 39.0,
	"optimal": 37.0,
	"damage_threshold_low": 32.0,
	"damage_threshold_high": 42.0,
	"damage_per_second": 1.0,
	"hunger_to_temp_factor": -0.1,
	"temp_to_immunity_factor": -2.0,
	"immunity_to_regen_factor": 0.5
}

# ===== 搜刮系统平衡 =====
const SCAVENGE_BALANCE = {
	"base_find_chance": 0.4,
	"quick_search_time": 2,
	"standard_search_time": 4,
	"thorough_search_time": 6,
	"noise_base_multiplier": 1.0,
	"night_penalty": 0.5,
	"rare_find_base_chance": 0.1,
	"event_trigger_chance": 0.15
}

# ===== 遭遇系统平衡 =====
const ENCOUNTER_BALANCE = {
	"base_encounter_chance": 0.15,
	"cooldown_hours": 3,
	"skill_check_base": 0.5,
	"skill_bonus_per_level": 0.1,
	"attribute_bonus_per_point": 0.05,
	"fatigue_penalty_tired": 0.1,
	"fatigue_penalty_exhausted": 0.2,
	"hunger_penalty": 0.1
}

# ===== 耐久系统平衡 =====
const DURABILITY_BALANCE = {
	"weapon_decay_per_hit": 2,
	"tool_decay_per_use": 2,
	"armor_decay_per_hit": 3,
	"equipment_decay_per_use": 1,
	"repair_kit_efficiency": 0.5,
	"tool_durability_influence": 0.2
}

# ===== 战斗平衡 =====
const COMBAT_BALANCE = {
	"night_enemy_hp_mult": 1.3,
	"night_enemy_damage_mult": 1.2,
	"night_player_dodge_penalty": 0.1,
	"fatigue_damage_mult_exhausted": 0.7,
	"fatigue_damage_mult_tired": 0.85,
	"fatigue_dodge_mult_exhausted": 0.6,
	"fatigue_dodge_mult_tired": 0.85
}

# ===== 移动平衡 =====
const MOVEMENT_BALANCE = {
	"base_travel_speed": 1.0,
	"night_speed_penalty": 0.8,
	"fatigue_speed_mult_exhausted": 0.6,
	"fatigue_speed_mult_tired": 0.8,
	"stamina_cost_per_hour": 10
}

# ===== 经验值平"=====
const XP_BALANCE = {
	"combat_weak": 10,
	"combat_normal": 25,
	"combat_strong": 50,
	"combat_elite": 100,
	"combat_boss": 250,
	"encounter_success": 15,
	"clue_discovery": 10,
	"level_up_xp_base": 100,
	"level_up_xp_multiplier": 1.5
}

# ===== 方法 =====

## 调整全局难度
static func set_difficulty_preset(preset: String):
	match preset:
		"easy":
			# 减少消耗，增加收益
			pass
		"normal":
			# 默认
			pass
		"hard":
			# 增加消耗，减少收益
			pass
		"nightmare":
			# 极限难度
			pass

## 获取平衡数值
static func get_value(category: String, key: String, default_value = 0):
	match category:
		"status":
			return STATUS_BALANCE.get(key, default_value)
		"temperature":
			return TEMPERATURE_BALANCE.get(key, default_value)
		"scavenge":
			return SCAVENGE_BALANCE.get(key, default_value)
		"encounter":
			return ENCOUNTER_BALANCE.get(key, default_value)
		"durability":
			return DURABILITY_BALANCE.get(key, default_value)
		"combat":
			return COMBAT_BALANCE.get(key, default_value)
		"movement":
			return MOVEMENT_BALANCE.get(key, default_value)
		"xp":
			return XP_BALANCE.get(key, default_value)
		_:
			return default_value

