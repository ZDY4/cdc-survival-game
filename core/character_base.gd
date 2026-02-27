extends RefCounted
## CharacterBase - 角色基础类
## NPC和敌人的共同基类，提供通用属性和方法
## 可被序列化/反序列化用于存档

class_name CharacterBase

# ========== 基础信息 ==========
var id: String = ""
var name: String = ""
var description: String = ""
var level: int = 1

# ========== 外观 ==========
var portrait_path: String = ""            # 立绘路径
var avatar_path: String = ""              # 头像路径
var model_path: String = ""               # 场景中的模型/精灵

# ========== 核心属性 (1-20) ==========
var attributes: Dictionary = {
	"strength": 10,       # 力量：影响物理攻击、负重
	"perception": 10,     # 感知：影响发现隐藏物品、命中率
	"endurance": 10,      # 体质：影响HP和耐力恢复
	"charisma": 10,       # 魅力：影响交易价格和说服
	"intelligence": 10,   # 智力：影响技能学习、法术伤害
	"agility": 10,        # 敏捷：影响闪避、暴击
	"luck": 10            # 幸运：影响暴击和掉落
}

# ========== 战斗属性 ==========
var combat_stats: Dictionary = {
	"hp": 50,
	"max_hp": 50,
	"damage": 5,
	"defense": 2,
	"speed": 5,
	"crit_chance": 0.05,   # 5% 基础暴击率
	"crit_damage": 1.5,    # 150% 暴击伤害
	"accuracy": 0.9,       # 90% 基础命中率
	"evasion": 0.05        # 5% 基础闪避率
}

# ========== 状态 ==========
var is_alive: bool = true
var is_active: bool = true

# ========== 当前效果 ==========
var active_effects: Array = []  # {effect_id, stacks, remaining_time}

# ========== 序列化/反序列化 ==========

## 将角色数据序列化为字典
func serialize() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"level": level,
		"portrait_path": portrait_path,
		"avatar_path": avatar_path,
		"model_path": model_path,
		"attributes": attributes.duplicate(),
		"combat_stats": combat_stats.duplicate(),
		"is_alive": is_alive,
		"active_effects": active_effects.duplicate()
	}

## 从字典反序列化角色数据
func deserialize(data: Dictionary):
	id = data.get("id", "")
	name = data.get("name", "")
	description = data.get("description", "")
	level = data.get("level", 1)
	
	portrait_path = data.get("portrait_path", "")
	avatar_path = data.get("avatar_path", "")
	model_path = data.get("model_path", "")
	
	if data.has("attributes"):
		attributes.merge(data.attributes, true)
	if data.has("combat_stats"):
		combat_stats.merge(data.combat_stats, true)
	
	is_alive = data.get("is_alive", true)
	active_effects = data.get("active_effects", []).duplicate()

# ========== 属性计算方法 ==========

## 计算实际属性值（考虑效果修饰）
func get_attribute(attr_name: String) -> int:
	var base = attributes.get(attr_name, 10)
	var modifier = _get_attribute_modifier(attr_name)
	return maxi(1, base + modifier)

## 计算战斗属性
func get_combat_stat(stat_name: String) -> float:
	return combat_stats.get(stat_name, 0.0)

## 获取当前HP
func get_hp() -> int:
	return combat_stats.hp

## 获取最大HP
func get_max_hp() -> int:
	return combat_stats.max_hp

## 设置HP（带边界检查）
func set_hp(value: int):
	combat_stats.hp = clampi(value, 0, combat_stats.max_hp)
	if combat_stats.hp <= 0:
		is_alive = false

## 受到伤害
func take_damage(amount: int) -> int:
	var actual_damage = maxi(1, amount - combat_stats.defense)
	combat_stats.hp = maxi(0, combat_stats.hp - actual_damage)
	
	if combat_stats.hp <= 0:
		is_alive = false
	
	return actual_damage

## 恢复生命
func heal(amount: int) -> int:
	if not is_alive:
		return 0
	
	var old_hp = combat_stats.hp
	combat_stats.hp = mini(combat_stats.max_hp, combat_stats.hp + amount)
	return combat_stats.hp - old_hp

## 计算攻击力
func get_attack_damage() -> int:
	var base_damage = combat_stats.damage
	var str_bonus = get_attribute("strength") / 5  # 每5点力量+1伤害
	return base_damage + str_bonus

## 计算防御力
func get_defense() -> int:
	var base_defense = combat_stats.defense
	var end_bonus = get_attribute("endurance") / 5  # 每5点体质+1防御
	return base_defense + end_bonus

## 计算速度
func get_speed() -> int:
	var base_speed = combat_stats.speed
	var agi_bonus = get_attribute("agility") / 4  # 每4点敏捷+1速度
	return base_speed + agi_bonus

## 获取闪避率
func get_evasion_rate() -> float:
	var base_evasion = combat_stats.evasion
	var agi_bonus = get_attribute("agility") * 0.005  # 每点敏捷+0.5%闪避
	return clampf(base_evasion + agi_bonus, 0.0, 0.75)  # 最高75%闪避

## 获取暴击率
func get_crit_rate() -> float:
	var base_crit = combat_stats.crit_chance
	var luck_bonus = get_attribute("luck") * 0.002  # 每点幸运+0.2%暴击
	var agi_bonus = get_attribute("agility") * 0.001  # 每点敏捷+0.1%暴击
	return clampf(base_crit + luck_bonus + agi_bonus, 0.0, 0.5)  # 最高50%暴击

# ========== 效果系统接口 ==========

## 应用效果
func apply_effect(effect_id: String, stacks: int = 1):
	# 检查是否已有此效果
	for effect in active_effects:
		if effect.effect_id == effect_id:
			effect.stacks = mini(effect.stacks + stacks, 10)  # 最大10层
			return
	
	# 添加新效果
	active_effects.append({
		"effect_id": effect_id,
		"stacks": stacks,
		"remaining_time": 0.0  # 由EffectSystem设置
	})

## 移除效果
func remove_effect(effect_id: String):
	active_effects = active_effects.filter(func(e): return e.effect_id != effect_id)

## 检查是否有效果
func has_effect(effect_id: String) -> bool:
	for effect in active_effects:
		if effect.effect_id == effect_id:
			return true
	return false

# ========== 私有方法 ==========

func _get_attribute_modifier(attr_name: String) -> int:
	var total = 0
	# 这里后续可以通过EffectSystem查询效果对属性的影响
	# 暂时简单返回0
	return total

# ========== 便捷方法 ==========

## 获取显示名称（带等级）
func get_display_name() -> String:
	if level > 1:
		return "%s Lv.%d" % [name, level]
	return name

## 是否满血
func is_full_hp() -> bool:
	return combat_stats.hp >= combat_stats.max_hp

## 血量百分比
func get_hp_percent() -> float:
	if combat_stats.max_hp <= 0:
		return 0.0
	return float(combat_stats.hp) / float(combat_stats.max_hp)

## 复活
func revive(hp_percent: float = 0.5):
	is_alive = true
	combat_stats.hp = int(combat_stats.max_hp * hp_percent)
