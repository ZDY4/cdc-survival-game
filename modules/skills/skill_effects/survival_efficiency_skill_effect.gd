extends "res://modules/skills/skill_effects/base_skill_effect.gd"
## SurvivalEfficiencySkillEffect - 生存消耗减免

func _build_effect(level: int, _context: Dictionary) -> Dictionary:
	var per_level: float = float(params.get("consumption_reduction_per_level", 0.04))
	var max_value: float = float(params.get("max_reduction", 0.4))
	var value: float = minf(per_level * float(level), max_value)
	return {"consumption_reduction": value}
