extends RefCounted
## BaseSkillEffect - 技能效果基类

# 1. Public variables
var skill_id: String = ""
var params: Dictionary = {}

# 2. Public methods
func setup(p_skill_id: String, p_params: Dictionary) -> void:
	skill_id = p_skill_id
	params = p_params.duplicate(true)


func on_level_changed(level: int, context: Dictionary) -> Dictionary:
	return _build_effect(level, context)


# 3. Private methods
func _build_effect(_level: int, _context: Dictionary) -> Dictionary:
	return {}
