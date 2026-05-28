extends RefCounted

const ProgressionLeveling = preload("res://scripts/core/progression/progression_leveling.gd")
const ProgressionState = preload("res://scripts/core/progression/progression_state.gd")

var _leveling := ProgressionLeveling.new()
var _state_tools := ProgressionState.new()


func build_initial_state(level: int, attributes: Dictionary = {}) -> Dictionary:
	return _state_tools.build_initial_state(level, attributes)


func grant_experience(state: Dictionary, amount: int) -> Dictionary:
	return _leveling.grant_experience(state, amount)


func add_skill_points(state: Dictionary, amount: int) -> Dictionary:
	return _leveling.add_skill_points(state, amount)


func learn_skill(state: Dictionary, skill_id: String, skill_library: Dictionary) -> Dictionary:
	var normalized_skill_id: String = str(skill_id)
	if normalized_skill_id.is_empty():
		return {"success": false, "reason": "skill_missing"}

	var skill: Dictionary = _skill_data(normalized_skill_id, skill_library)
	if skill.is_empty():
		return {"success": false, "reason": "unknown_skill", "skill_id": normalized_skill_id}

	var next_state: Dictionary = _state_tools.normalized_state(state)
	var learned: Dictionary = _dictionary_or_empty(next_state.get("learned_skills", {})).duplicate(true)
	var current_level: int = max(0, int(learned.get(normalized_skill_id, 0)))
	var max_level: int = max(1, int(skill.get("max_level", 1)))
	if current_level >= max_level:
		return {"success": false, "reason": "skill_already_maxed", "skill_id": normalized_skill_id}
	if int(next_state.get("available_skill_points", 0)) <= 0:
		return {"success": false, "reason": "missing_skill_points", "skill_id": normalized_skill_id}

	for prerequisite in _array_or_empty(skill.get("prerequisites", [])):
		var prerequisite_id: String = str(prerequisite)
		if int(learned.get(prerequisite_id, 0)) <= 0:
			return {
				"success": false,
				"reason": "skill_prerequisite_missing",
				"skill_id": normalized_skill_id,
				"prerequisite_id": prerequisite_id,
			}

	var attributes: Dictionary = _dictionary_or_empty(next_state.get("attributes", {}))
	for attribute in _dictionary_or_empty(skill.get("attribute_requirements", {})).keys():
		var required: int = int(skill.get("attribute_requirements", {}).get(attribute, 0))
		var current: int = int(attributes.get(str(attribute), 0))
		if current < required:
			return {
				"success": false,
				"reason": "skill_attribute_requirement_missing",
				"skill_id": normalized_skill_id,
				"attribute": str(attribute),
				"required": required,
				"current": current,
			}

	var new_level: int = current_level + 1
	learned[normalized_skill_id] = new_level
	next_state["learned_skills"] = learned
	next_state["available_skill_points"] = int(next_state.get("available_skill_points", 0)) - 1
	return {
		"success": true,
		"state": next_state,
		"skill_id": normalized_skill_id,
		"level": new_level,
		"available_skill_points": int(next_state.get("available_skill_points", 0)),
	}


func meets_skill_requirements(state: Dictionary, skill_requirements: Dictionary) -> Dictionary:
	var normalized_state: Dictionary = _state_tools.normalized_state(state)
	var learned: Dictionary = _dictionary_or_empty(normalized_state.get("learned_skills", {}))
	var missing: Array[Dictionary] = []
	for skill_id in skill_requirements.keys():
		var normalized_skill_id: String = str(skill_id)
		var required_level: int = max(1, int(skill_requirements.get(skill_id, 0)))
		var current_level: int = int(learned.get(normalized_skill_id, 0))
		if current_level < required_level:
			missing.append({
				"skill_id": normalized_skill_id,
				"required_level": required_level,
				"current_level": current_level,
			})
	return {
		"success": missing.is_empty(),
		"missing_skills": missing,
	}


func xp_to_next_level(level: int) -> int:
	return _leveling.xp_to_next_level(level)


func _skill_data(skill_id: String, skill_library: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(skill_library.get(skill_id, {}))
	if record.is_empty():
		return {}
	return _dictionary_or_empty(record.get("data", record))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
