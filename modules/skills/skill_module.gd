extends BaseModule
# SkillModule - 技能系统

signal skill_learned(skill_id: String)
signal skill_upgraded(skill_id: String, new_level: int)
signal skill_points_changed(amount: int)

const SKILLS = {
	"combat": {
		"name": "战斗精通",
		"description": "增加攻击力",
		"max_level": 5,
		"effect_per_level": {"damage_bonus": 2}
	},
	"survival": {
		"name": "生存专家",
		"description": "减少饥饿和口渴消耗",
		"max_level": 5,
		"effect_per_level": {"consumption_reduction": 0.1}
	},
	"crafting": {
		"name": "制作大师",
		"description": "解锁高级配方",
		"max_level": 3,
		"effect_per_level": {"recipe_unlock": 1}
	},
	"stealth": {
		"name": "潜行",
		"description": "降低被敌人发现几率",
		"max_level": 5,
		"effect_per_level": {"detection_reduction": 0.15}
	}
}

var skill_points: int = 0
var learned_skills: Dictionary = {}  # skill_id -> level

func add_skill_points(amount: int):
	skill_points += amount
	skill_points_changed.emit(skill_points)

func can_learn_skill(skill_id: String):
	if not SKILLS.has(skill_id):
		return false
	
	if skill_points <= 0:
		return false
	
	var current_level = learned_skills.get(skill_id, 0)
	if current_level >= SKILLS[skill_id].max_level:
		return false
	
	return true

func learn_skill(skill_id: String):
	if not can_learn_skill(skill_id):
		return false
	
	if not learned_skills.has(skill_id):
		learned_skills[skill_id] = 0
		skill_learned.emit(skill_id)
	
	learned_skills[skill_id] += 1
	skill_points -= 1
	
	skill_upgraded.emit(skill_id, learned_skills[skill_id])
	skill_points_changed.emit(skill_points)
	
	return true

func get_skill_level(skill_id: String):
	return learned_skills.get(skill_id, 0)

func get_skill_effect(skill_id: String):
	var level = get_skill_level(skill_id)
	if level <= 0:
		return {}
	
	var skill = SKILLS[skill_id]
	var effect = {}
	
	for key in skill.effect_per_level:
		effect[key] = skill.effect_per_level[key] * level
	
	return effect

func get_total_damage_bonus(skill_id: String = "combat"):
	return get_skill_effect(skill_id).get("damage_bonus", 0)

func get_consumption_reduction(skill_id: String = "survival"):
	return get_skill_effect(skill_id).get("consumption_reduction", 0.0)

func get_available_skills() -> Array[Dictionary]:
	var available = []
	for id in SKILLS:
		var level = get_skill_level(id)
		available.append({
			"id": id,
			"name": SKILLS[id].name,
			"description": SKILLS[id].description,
			"current_level": level,
			"max_level": SKILLS[id].max_level,
			"can_learn": can_learn_skill(id)
		})
	return available
