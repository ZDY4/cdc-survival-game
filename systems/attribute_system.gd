extends Node
# AttributeSystem - 角色属性系统
# 管理三大基础属性：力量、敏捷、体质
# ===== 信号 =====
signal attribute_changed(attr_name: String, new_value: int, old_value: int)
signal attribute_points_changed(available_points: int)
signal calculated_stats_updated(stats: Dictionary)

# ===== 基础属性 =====
var strength: int = 5      # 力量 - 影响伤害、负重
var agility: int = 5       # 敏捷 - 影响闪避、速度
var constitution: int = 5  # 体质 - 影响HP上限、抗性
# 属性上限
const MAX_ATTRIBUTE: int = 20
const MIN_ATTRIBUTE: int = 1

# ===== 属性点 =====
var available_points: int = 0

# ===== 计算属性缓存 =====
var _cached_stats: Dictionary = {}
var _needs_recalculation: bool = true

func _ready():
	print("[AttributeSystem] 属性系统已初始")
	_recalculate_stats()

# ===== 属性点管理 =====

func set_available_points(points: int):
	available_points = maxi(0, points)
	attribute_points_changed.emit(available_points)

func add_attribute_points(points: int):
	available_points += points
	attribute_points_changed.emit(available_points)
	print("[AttributeSystem] 获得 %d 属性点" % points)

## 分配属性点
func allocate_point(attr_name: String) -> bool:
	if available_points <= 0:
		print("[AttributeSystem] 没有可用的属性点")
		return false
	
	match attr_name:
		"strength":
			if strength >= MAX_ATTRIBUTE:
				return false
			var old = strength
			strength += 1
			available_points -= 1
			attribute_changed.emit("strength", strength, old)
			attribute_points_changed.emit(available_points)
			
		"agility":
			if agility >= MAX_ATTRIBUTE:
				return false
			var old = agility
			agility += 1
			available_points -= 1
			attribute_changed.emit("agility", agility, old)
			attribute_points_changed.emit(available_points)
			
		"constitution":
			if constitution >= MAX_ATTRIBUTE:
				return false
			var old = constitution
			constitution += 1
			available_points -= 1
			attribute_changed.emit("constitution", constitution, old)
			attribute_points_changed.emit(available_points)
		
		_:
			print("[AttributeSystem] 未知属性: %s" % attr_name)
			return false
	
	_needs_recalculation = true
	_recalculate_stats()
	print("[AttributeSystem] %s 增加到 %d" % [attr_name, get(attr_name)])
	return true

## 重置属性（返回所有已分配的点数）
func reset_attributes():
	var total_spent = (strength - 5) + (agility - 5) + (constitution - 5)
	strength = 5
	agility = 5
	constitution = 5
	available_points += total_spent
	attribute_changed.emit("strength", 5, strength)
	attribute_changed.emit("agility", 5, agility)
	attribute_changed.emit("constitution", 5, constitution)
	attribute_points_changed.emit(available_points)
	_needs_recalculation = true
	_recalculate_stats()
	print("[AttributeSystem] 属性已重置，返回 %d 点" % total_spent)

## 批量设置属性（用于加载存档）
func set_attributes(str_val: int, agi_val: int, con_val: int):
	strength = clampi(str_val, MIN_ATTRIBUTE, MAX_ATTRIBUTE)
	agility = clampi(agi_val, MIN_ATTRIBUTE, MAX_ATTRIBUTE)
	constitution = clampi(con_val, MIN_ATTRIBUTE, MAX_ATTRIBUTE)
	_needs_recalculation = true
	_recalculate_stats()

# ===== 计算属"=====

func _recalculate_stats():
	if not _needs_recalculation:
		return
	
	_cached_stats = {
		# 战斗相关
		"damage_bonus": calculate_damage_bonus(),
		"attack_speed": calculate_attack_speed(),
		"crit_chance": calculate_crit_chance(),
		
		# 防御相关
		"dodge_chance": calculate_dodge_chance(),
		"hp_bonus": calculate_hp_bonus(),
		"damage_reduction": calculate_damage_reduction(),
		
		# 生存相关
		"max_carry_weight": calculate_carry_weight(),
		"stamina_bonus": calculate_stamina_bonus(),
		"recovery_rate": calculate_recovery_rate(),
		
		# 抗性相关
		"disease_resistance": calculate_disease_resistance(),
		"toxin_resistance": calculate_toxin_resistance()
	}
	
	_needs_recalculation = false
	calculated_stats_updated.emit(_cached_stats)

## 力量相关计算

# 伤害加成：每点力量 +5% 伤害
func calculate_damage_bonus() -> float:
	return (strength - 5) * 0.05

# 负重能力：基础50 + 每点力量 +10
func calculate_carry_weight() -> int:
	return 50 + (strength - 5) * 10

## 敏捷相关计算

# 闪避率：每点敏捷 +2% 闪避
func calculate_dodge_chance() -> float:
	return (agility - 5) * 0.02

# 攻击速度：每点敏捷 +3% 速度
func calculate_attack_speed() -> float:
	return 1.0 + (agility - 5) * 0.03

# 暴击率：每点敏捷 +1% 暴击
func calculate_crit_chance() -> float:
	return (agility - 5) * 0.01

## 体质相关计算

# HP加成：每点体质 +10 HP
func calculate_hp_bonus() -> int:
	return (constitution - 5) * 10

# 体力加成：每点体质 +5 体力上限
func calculate_stamina_bonus() -> int:
	return (constitution - 5) * 5

# 伤害减免：每点体质 +1% 减伤
func calculate_damage_reduction() -> float:
	return (constitution - 5) * 0.01

# 恢复速度：每点体质 +5% 恢复速度
func calculate_recovery_rate() -> float:
	return 1.0 + (constitution - 5) * 0.05

# 疾病抗性：每点体质 +5% 抗性
func calculate_disease_resistance() -> float:
	return (constitution - 5) * 0.05

# 毒素抗性：每点体质 +3% 抗性
func calculate_toxin_resistance() -> float:
	return (constitution - 5) * 0.03

# ===== 获取计算属性 =====

func get_calculated_stats() -> Dictionary:
	if _needs_recalculation:
		_recalculate_stats()
	return _cached_stats.duplicate()

func get_stat(stat_name: String) -> float:
	if _needs_recalculation:
		_recalculate_stats()
	return _cached_stats.get(stat_name, 0.0)

# ===== 便捷查询 =====

## 获取最终伤害倍率
func get_damage_multiplier() -> float:
	return 1.0 + calculate_damage_bonus()

## 获取最终HP上限
func get_max_hp_bonus() -> int:
	return calculate_hp_bonus()

## 获取最终闪避概"(0-1)
func get_dodge_probability() -> float:
	return minf(0.5, calculate_dodge_chance())  # 上限50%

## 尝试闪避
func attempt_dodge() -> bool:
	return randf() < get_dodge_probability()

## 获取最终暴击概"(0-1)
func get_crit_probability() -> float:
	return minf(0.3, calculate_crit_chance())  # 上限30%

## 尝试暴击
func attempt_crit() -> bool:
	return randf() < get_crit_probability()

# ===== 属性描述 =====

func get_attribute_description(attr_name: String) -> String:
	match attr_name:
		"strength":
			return "力量：影响物理伤害和负重能力\n当前: %d%%伤害, +%d负重" % [
				int(calculate_damage_bonus() * 100),
				calculate_carry_weight() - 50
			]
		"agility":
			return "敏捷：影响闪避、速度和暴击\n当前: %d%%闪避, +%d%%攻速, +%d%%暴击" % [
				int(calculate_dodge_chance() * 100),
				int(calculate_attack_speed() * 100 - 100),
				int(calculate_crit_chance() * 100)
			]
		"constitution":
			return "体质：影响生命值和抗性\n当前: %d HP, +%d%%减伤, +%d%%疾病抗性" % [
				calculate_hp_bonus(),
				int(calculate_damage_reduction() * 100),
				int(calculate_disease_resistance() * 100)
			]
		_:
			return "未知属性"

func get_all_attributes() -> Dictionary:
	return {
		"strength": {
			"value": strength,
			"min": MIN_ATTRIBUTE,
			"max": MAX_ATTRIBUTE,
			"description": "力量",
			"effects": ["伤害", "负重"]
		},
		"agility": {
			"value": agility,
			"min": MIN_ATTRIBUTE,
			"max": MAX_ATTRIBUTE,
			"description": "敏捷",
			"effects": ["闪避", "攻", "暴击"]
		},
		"constitution": {
			"value": constitution,
			"min": MIN_ATTRIBUTE,
			"max": MAX_ATTRIBUTE,
			"description": "体质",
			"effects": ["HP", "减伤", "抗"]
		}
	}

# ===== 序列"=====

func serialize() -> Dictionary:
	return {
		"strength": strength,
		"agility": agility,
		"constitution": constitution,
		"available_points": available_points
	}

func deserialize(data: Dictionary):
	strength = data.get("strength", 5)
	agility = data.get("agility", 5)
	constitution = data.get("constitution", 5)
	available_points = data.get("available_points", 0)
	_needs_recalculation = true
	_recalculate_stats()
	print("[AttributeSystem] 属性数据已加载")

