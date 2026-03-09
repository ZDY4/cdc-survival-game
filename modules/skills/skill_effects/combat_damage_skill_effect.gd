extends "res://modules/skills/skill_effects/base_skill_effect.gd"
## CombatDamageSkillEffect - 战斗伤害加成

func _build_effect(level: int, _context: Dictionary) -> Dictionary:
	var per_level: float = float(params.get("damage_bonus_per_level", 0.05))
	return {"damage_bonus": per_level * float(level)}
