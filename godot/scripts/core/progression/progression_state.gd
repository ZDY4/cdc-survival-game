extends RefCounted


func build_initial_state(level: int, attributes: Dictionary = {}) -> Dictionary:
	return {
		"level": max(1, level),
		"current_xp": 0,
		"total_xp_earned": 0,
		"available_stat_points": 0,
		"available_skill_points": 0,
		"total_stat_points_earned": 0,
		"total_skill_points_earned": 0,
		"learned_skills": {},
		"attributes": normalized_attributes(attributes),
	}


func normalized_state(state: Dictionary) -> Dictionary:
	var next_state: Dictionary = state.duplicate(true)
	next_state["level"] = max(1, int(next_state.get("level", 1)))
	next_state["current_xp"] = max(0, int(next_state.get("current_xp", 0)))
	next_state["total_xp_earned"] = max(0, int(next_state.get("total_xp_earned", 0)))
	next_state["available_stat_points"] = max(0, int(next_state.get("available_stat_points", 0)))
	next_state["available_skill_points"] = max(0, int(next_state.get("available_skill_points", 0)))
	next_state["total_stat_points_earned"] = max(0, int(next_state.get("total_stat_points_earned", 0)))
	next_state["total_skill_points_earned"] = max(0, int(next_state.get("total_skill_points_earned", 0)))
	next_state["learned_skills"] = _dictionary_or_empty(next_state.get("learned_skills", {})).duplicate(true)
	next_state["attributes"] = normalized_attributes(_dictionary_or_empty(next_state.get("attributes", {})))
	return next_state


func normalized_attributes(attributes: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key in attributes.keys():
		output[str(key)] = max(0, int(attributes.get(key, 0)))
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
