extends "res://core/base_module.gd"
# SkillModule - 技能系统
# 数据从 DataManager 加载

signal skill_learned(skill_id: String)
signal skill_upgraded(skill_id: String, new_level: int)
signal skill_points_changed(amount: int)

# 技能数据缓存（从 DataManager 加载）
var _skills: Dictionary = {}


func _get_skill(skill_id: String) -> Dictionary:
	return _skills.get(skill_id, {})


func _ready():
	_load_skills_from_manager()


func _load_skills_from_manager():
	var dm = get_node_or_null("/root/DataManager")
	if dm:
		_skills = dm.get_all_skills()

	if _skills.is_empty():
		push_warning("[SkillModule] 无法从 DataManager 加载技能数据")


var skill_points: int = 0
var learned_skills: Dictionary = {}  # skill_id -> level


func add_skill_points(amount: int):
	skill_points += amount
	skill_points_changed.emit(skill_points)


func can_learn_skill(skill_id: String):
	var skill = _get_skill(skill_id)
	if skill.is_empty():
		return false

	if skill_points <= 0:
		return false

	var current_level = learned_skills.get(skill_id, 0)
	if current_level >= skill.get("max_level", 0):
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

	var skill = _get_skill(skill_id)
	if skill.is_empty():
		return {}

	var effect = {}
	var effect_per_level = skill.get("effect_per_level", {})

	for key in effect_per_level:
		effect[key] = effect_per_level[key] * level

	return effect


func get_total_damage_bonus(skill_id: String = "combat"):
	return get_skill_effect(skill_id).get("damage_bonus", 0)


func get_consumption_reduction(skill_id: String = "survival"):
	return get_skill_effect(skill_id).get("consumption_reduction", 0.0)


func get_available_skills() -> Array[Dictionary]:
	var available = []
	for id in _skills:
		var skill = _skills[id]
		var level = get_skill_level(id)
		available.append(
			{
				"id": id,
				"name": skill.get("name", ""),
				"description": skill.get("description", ""),
				"current_level": level,
				"max_level": skill.get("max_level", 0),
				"can_learn": can_learn_skill(id)
			}
		)
	return available
