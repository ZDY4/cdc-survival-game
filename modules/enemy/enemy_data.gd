extends "res://core/character_base.gd"
## EnemyData - 敌人数据类
## 继承自CharacterBase，添加敌人特有属性

class_name EnemyData

# ========== 敌人类型枚举 ==========
enum EnemyType {
	NORMAL,         # 普通敌人
	ELITE,          # 精英敌人
	BOSS,           # Boss
	MINIBOSS        # 小Boss
}

enum AIType {
	AGGRESSIVE,     # 主动攻击
	DEFENSIVE,      # 防守型
	COWARDLY,       # 胆小（低血量逃跑）
	BERSERK,        # 狂暴（低血量狂暴）
	STEALTHY,       # 潜行（偷袭）
	SUPPORT         # 辅助（治疗队友）
}

# ========== 基础信息 ==========
var enemy_type: EnemyType = EnemyType.NORMAL
var ai_type: AIType = AIType.AGGRESSIVE

# ========== 战斗特性 ==========
var aggression_range: float = 200.0      # 仇恨范围
var patrol_radius: float = 100.0         # 巡逻半径
var attack_cooldown: float = 1.0         # 攻击冷却时间

# ========== 特殊能力 ==========
var special_abilities: Array = []        # ["poison_attack", "heal_self", "summon"]
var immunities: Array = []               # ["poison", "stun", "bleeding"]
var weaknesses: Dictionary = {}          # {"fire": 1.5, "ice": 0.5}

# ========== 掉落表 ==========
var loot_table: Array = []               # [{"item_id": "", "chance": 0.5, "min": 1, "max": 2}]
var exp_reward: int = 10                 # 击杀经验

# ========== 生成设置 ==========
var spawn_weight: int = 10               # 生成权重
var min_spawn_level: int = 1             # 最小生成等级
var max_spawn_level: int = 99            # 最大生成等级
var spawn_locations: Array = []          # ["safehouse", "street_a"]

# ========== 行为设置 ==========
var can_flee: bool = false               # 是否会逃跑
var flee_hp_threshold: float = 0.2       # 逃跑血量阈值
var can_call_reinforcements: bool = false # 是否会呼叫增援

# ========== 序列化/反序列化（扩展） ==========

func serialize() -> Dictionary:
	var base_data = super.serialize()
	base_data.merge({
		"enemy_type": enemy_type,
		"ai_type": ai_type,
		"aggression_range": aggression_range,
		"patrol_radius": patrol_radius,
		"attack_cooldown": attack_cooldown,
		"special_abilities": special_abilities.duplicate(),
		"immunities": immunities.duplicate(),
		"weaknesses": weaknesses.duplicate(),
		"loot_table": loot_table.duplicate(true),
		"exp_reward": exp_reward,
		"spawn_weight": spawn_weight,
		"min_spawn_level": min_spawn_level,
		"max_spawn_level": max_spawn_level,
		"spawn_locations": spawn_locations.duplicate(),
		"can_flee": can_flee,
		"flee_hp_threshold": flee_hp_threshold,
		"can_call_reinforcements": can_call_reinforcements
	})
	return base_data

func deserialize(data: Dictionary):
	super.deserialize(data)
	enemy_type = data.get("enemy_type", EnemyType.NORMAL)
	ai_type = data.get("ai_type", AIType.AGGRESSIVE)
	aggression_range = data.get("aggression_range", 200.0)
	patrol_radius = data.get("patrol_radius", 100.0)
	attack_cooldown = data.get("attack_cooldown", 1.0)
	special_abilities = data.get("special_abilities", []).duplicate()
	immunities = data.get("immunities", []).duplicate()
	weaknesses = data.get("weaknesses", {}).duplicate()
	loot_table = data.get("loot_table", []).duplicate(true)
	exp_reward = data.get("exp_reward", 10)
	spawn_weight = data.get("spawn_weight", 10)
	min_spawn_level = data.get("min_spawn_level", 1)
	max_spawn_level = data.get("max_spawn_level", 99)
	spawn_locations = data.get("spawn_locations", []).duplicate()
	can_flee = data.get("can_flee", false)
	flee_hp_threshold = data.get("flee_hp_threshold", 0.2)
	can_call_reinforcements = data.get("can_call_reinforcements", false)

# ========== 便捷方法 ==========

func get_type_string() -> String:
	match enemy_type:
		EnemyType.NORMAL:
			return "普通"
		EnemyType.ELITE:
			return "精英"
		EnemyType.BOSS:
			return "Boss"
		EnemyType.MINIBOSS:
			return "小Boss"
		_:
			return "未知"

func get_ai_string() -> String:
	match ai_type:
		AIType.AGGRESSIVE:
			return "主动"
		AIType.DEFENSIVE:
			return "防守"
		AIType.COWARDLY:
			return "胆小"
		AIType.BERSERK:
			return "狂暴"
		AIType.STEALTHY:
			return "潜行"
		AIType.SUPPORT:
			return "辅助"
		_:
			return "未知"

## 检查是否在生成等级范围内
func can_spawn_at_level(player_level: int) -> bool:
	return player_level >= min_spawn_level and player_level <= max_spawn_level

## 获取生成概率
func get_spawn_chance(total_weight: int) -> float:
	if total_weight <= 0:
		return 0.0
	return float(spawn_weight) / float(total_weight)

## 执行掉落
func roll_loot() -> Array:
	var dropped_items = []
	for loot in loot_table:
		var chance = loot.get("chance", 0.0)
		if randf() < chance:
			var item_id = loot.get("item_id", "")
			var count = randi_range(loot.get("min", 1), loot.get("max", 1))
			dropped_items.append({"item_id": item_id, "count": count})
	return dropped_items

## 检查免疫
func is_immune_to(effect: String) -> bool:
	return immunities.has(effect)

## 获取弱点倍率
func get_weakness_multiplier(damage_type: String) -> float:
	return weaknesses.get(damage_type, 1.0)
