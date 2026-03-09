extends Node
# SkillSystem - 技能系"# 管理技能树、技能点分配、技能效"
# ===== 信号 =====
signal skill_learned(skill_id: String, skill_data: Dictionary)
signal skill_points_changed(available_points: int)
signal skill_effect_triggered(skill_id: String, effect_type: String)

# ===== 技能数据结"=====
class Skill:
	var id: String
	var name: String
	var description: String
	var category: String  # combat, survival, crafting
	var max_level: int
	var current_level: int = 0
	var prerequisites: Array[String] = []
	var effects: Dictionary = {}
	var icon: String = ""
	
	func _init(p_id: String, p_name: String, p_desc: String, p_cat: String, p_max: int = 3):
		id = p_id
		name = p_name
		description = p_desc
		category = p_cat
		max_level = p_max
	
	func is_maxed() -> bool:
		return current_level >= max_level
	
	func can_level_up() -> bool:
		return current_level < max_level
	
	func get_current_effect() -> Dictionary:
		if current_level <= 0:
			return {}
		var effect = effects.duplicate()
		# 根据等级调整效果数量
		for key in effect.keys():
			if effect[key] is float or effect[key] is int:
				effect[key] = effect[key] * current_level
		return effect
	
	func to_dictionary() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"description": description,
			"category": category,
			"max_level": max_level,
			"current_level": current_level,
			"prerequisites": prerequisites,
			"effects": effects,
			"is_learned": current_level > 0,
			"is_maxed": is_maxed()
		}

# ===== 技能点 =====
var available_points: int = 0

# ===== 技能树 =====
var skills: Dictionary = {}
var learned_skills: Array[String] = []

# ===== 激活的技能效果 =====
var active_effects: Dictionary = {}

func _ready():
	print("[SkillSystem] 技能系统已初始")
	_initialize_skill_tree()

# ===== 初始化技能树 =====

func _initialize_skill_tree():
	# 战斗技能
	_add_skill("combat_training", "战斗训练", "基础战斗技巧，提升伤害输出", "combat", 5, 
		{"damage_bonus": 0.05})
	
	_add_skill("precise_strike", "精准打击", "提高暴击", "combat", 3,
		{"crit_chance": 0.03}, ["combat_training"])
	
	_add_skill("defense_stance", "防御姿", "减少受到的伤", "combat", 3,
		{"damage_reduction": 0.05})
	
	_add_skill("weapon_master", "武器大师", "熟练使用各种武器", "combat", 3,
		{"weapon_damage": 0.10}, ["combat_training", "precise_strike"])
	
	# 生存技"	
	_add_skill("survival_instinct", "生存本能", "提高生存能力", "survival", 5,
		{"stamina_efficiency": 0.05})
	
	_add_skill("scavenger", "拾荒专家", "搜索时获得额外物", "survival", 3,
		{"extra_loot_chance": 0.10}, ["survival_instinct"])
	
	_add_skill("first_aid", "急救", "治疗效果提升", "survival", 3,
		{"healing_bonus": 0.15})
	
	_add_skill("night_owl", "夜猫", "夜间行动能力增强", "survival", 3,
		{"night_penalty_reduction": 0.20}, ["survival_instinct"])
	
	# 制作技"	
	_add_skill("crafting_basic", "基础制作", "基础制作技", "crafting", 5,
		{"crafting_speed": 0.10})
	
	_add_skill("efficient_crafting", "高效制作", "减少材料消", "crafting", 3,
		{"material_efficiency": 0.10}, ["crafting_basic"])
	
	_add_skill("repair_expert", "修理专家", "可以修复装备", "crafting", 3,
		{}, ["crafting_basic"])
	
	_add_skill("advanced_crafting", "高级制作", "解锁高级配方", "crafting", 3,
		{}, ["crafting_basic", "efficient_crafting"])
	
	print("[SkillSystem] 技能树初始化完成，'%d 个技' % skills.size()")

func _add_skill(id: String, name: String, desc: String, category: String, max_level: int, 
		effects: Dictionary = {}, prerequisites: Array[String] = []):
	var skill = Skill.new(id, name, desc, category, max_level)
		skill.effects = effects
		skill.prerequisites = prerequisites
		skills[id] = skill

# ===== 技能点管理 =====

func set_available_points(points: int):
	available_points = maxi(0, points)
	skill_points_changed.emit(available_points)

func add_skill_points(points: int):
	available_points += points
	skill_points_changed.emit(available_points)
	print("[SkillSystem] 获得 %d 技能点" % points)

func get_available_points() -> int:
	return available_points

# ===== 技能学"=====

## 检查是否可以学习技"func can_learn_skill(skill_id: String) -> Dictionary:
	var skill = skills.get(skill_id)
	if skill == null:
		return {"can_learn": false, "reason": "技能不存在"}
	
	if skill.is_maxed():
		return {"can_learn": false, "reason": "技能已满级"}
	
	if available_points <= 0:
		return {"can_learn": false, "reason": "没有可用技能点"}
	
	# 检查前置技"	for prereq in skill.prerequisites:
		if not learned_skills.has(prereq):
			var prereq_skill = skills.get(prereq)
			var prereq_name = prereq_skill.name if prereq_skill else prereq
			return {"can_learn": false, "reason": "需要先学习: " + prereq_name}
		var prereq_skill = skills.get(prereq)
		if prereq_skill and prereq_skill.current_level <= 0:
			return {"can_learn": false, "reason": "前置技能等级不"}
	
	return {"can_learn": true, "reason": ""}

## 学习/升级技"func learn_skill(skill_id: String) -> Dictionary:
	var check = can_learn_skill(skill_id)
	if not check.can_learn:
		print("[SkillSystem] 无法学习技" %s" % check.reason)
		return {"success": false, "reason": check.reason}
	
	var skill = skills[skill_id]
	skill.current_level += 1
	available_points -= 1
	
	if not learned_skills.has(skill_id):
		learned_skills.append(skill_id)
	
	# 更新技能效"	_update_skill_effects(skill_id)
	
	skill_learned.emit(skill_id, skill.to_dictionary())
	skill_points_changed.emit(available_points)
	
	print("[SkillSystem] 学习技"'%s' (等级 %d/%d)" % [skill.name, skill.current_level, skill.max_level])
	
	return {
		"success": true,
		"skill_id": skill_id,
		"skill_name": skill.name,
		"new_level": skill.current_level,
		"max_level": skill.max_level,
		"effect": skill.get_current_effect()
	}

## 重置技能（返还所有技能点"func reset_skills():
	var points_refunded = 0
	for skill_id in learned_skills:
		var skill = skills[skill_id]
		points_refunded += skill.current_level
		skill.current_level = 0
	
	learned_skills.clear()
	active_effects.clear()
	available_points += points_refunded
	
	skill_points_changed.emit(available_points)
	print("[SkillSystem] 技能已重置，返"%d 技能点" % points_refunded)

# ===== 技能效"=====

func _update_skill_effects(skill_id: String):
	var skill = skills.get(skill_id)
	if skill == null:
		return
	
	active_effects[skill_id] = skill.get_current_effect()

## 获取技能效"func get_skill_effect(skill_id: String) -> Dictionary:
	return active_effects.get(skill_id, {})

## 获取所有激活的效果
func get_all_active_effects() -> Dictionary:
	return active_effects.duplicate()

## 按类别获取效"func get_effects_by_category(category: String) -> Dictionary:
	var result = {}
	for skill_id in learned_skills:
		var skill = skills[skill_id]
		if skill.category == category:
			result[skill_id] = skill.get_current_effect()
	return result

## 计算总效果数"func get_total_effect(effect_name: String) -> float:
	var total = 0.0
	for effects in active_effects.values():
		if effects.has(effect_name):
			total += effects[effect_name]
	return total

# ===== 特定效果查询 =====

func get_damage_bonus() -> float:
	return get_total_effect("damage_bonus")

func get_crit_chance_bonus() -> float:
	return get_total_effect("crit_chance")

func get_damage_reduction_bonus() -> float:
	return get_total_effect("damage_reduction")

func get_healing_bonus() -> float:
	return get_total_effect("healing_bonus")

func get_loot_bonus_chance() -> float:
	return get_total_effect("extra_loot_chance")

func get_night_penalty_reduction() -> float:
	return get_total_effect("night_penalty_reduction")

func get_crafting_speed_bonus() -> float:
	return get_total_effect("crafting_speed")

# ===== 技能查"=====

func get_skill(skill_id: String) -> Dictionary:
	var skill = skills.get(skill_id)
	if skill:
		return skill.to_dictionary()
	return {}

func get_all_skills() -> Dictionary:
	var result = {}
	for id in skills.keys():
		result[id] = skills[id].to_dictionary()
	return result

func get_skills_by_category(category: String) -> Dictionary:
	var result = {}
	for id in skills.keys():
		var skill = skills[id]
		if skill.category == category:
			result[id] = skill.to_dictionary()
	return result

func get_learned_skills() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in learned_skills:
		result.append(skills[id].to_dictionary())
	return result

func is_skill_learned(skill_id: String) -> bool:
	return learned_skills.has(skill_id)

func get_skill_level(skill_id: String) -> int:
	var skill = skills.get(skill_id)
	if skill:
		return skill.current_level
	return 0

# ===== 技能树UI数据 =====

func get_skill_tree_data() -> Dictionary:
	return {
		"combat": {
			"name": "战斗",
			"description": "提升战斗能力的技",
			"skills": get_skills_by_category("combat")
		},
		"survival": {
			"name": "生存",
			"description": "提升生存能力的技",
			"skills": get_skills_by_category("survival")
		},
		"crafting": {
			"name": "制作",
			"description": "提升制作能力的技",
			"skills": get_skills_by_category("crafting")
		}
	}

# ===== 序列"=====

func serialize() -> Dictionary:
	var skill_data = {}
	for id in skills.keys():
		skill_data[id] = {
			"current_level": skills[id].current_level
		}
	
	return {
		"available_points": available_points,
		"learned_skills": learned_skills,
		"skill_data": skill_data
	}

func deserialize(data: Dictionary):
	available_points = data.get("available_points", 0)
	learned_skills = data.get("learned_skills", [])
	
	var skill_data = data.get("skill_data", {})
	for id in skill_data.keys():
		if skills.has(id):
			skills[id].current_level = skill_data[id].get("current_level", 0)
			if skills[id].current_level > 0:
				_update_skill_effects(id)
	
	print("[SkillSystem] 技能数据已加载")

