extends "res://modules/skills/skill_effects/base_skill_effect.gd"
## StatBonusSkillEffect - 通用数值加成效果

func _build_effect(level: int, _context: Dictionary) -> Dictionary:
	var effect_name: String = str(params.get("effect_name", "generic_bonus"))
	var per_level: float = float(params.get("per_level", 0.0))
	var max_value: float = float(params.get("max_value", 0.0))
	var value: float = per_level * float(level)
	if max_value > 0.0:
		value = minf(value, max_value)
	return {effect_name: value}
