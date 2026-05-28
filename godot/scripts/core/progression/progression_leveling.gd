extends RefCounted

const ProgressionState = preload("res://scripts/core/progression/progression_state.gd")

var _state_tools := ProgressionState.new()


func grant_experience(state: Dictionary, amount: int) -> Dictionary:
	var xp_amount: int = max(0, amount)
	if xp_amount <= 0:
		return {"changed": false, "state": state}

	var next_state: Dictionary = _state_tools.normalized_state(state)
	next_state["current_xp"] = int(next_state.get("current_xp", 0)) + xp_amount
	next_state["total_xp_earned"] = int(next_state.get("total_xp_earned", 0)) + xp_amount

	var level_ups: Array[Dictionary] = []
	while int(next_state.get("current_xp", 0)) >= xp_to_next_level(int(next_state.get("level", 1))):
		var required: int = xp_to_next_level(int(next_state.get("level", 1)))
		next_state["current_xp"] = int(next_state.get("current_xp", 0)) - required
		next_state["level"] = int(next_state.get("level", 1)) + 1
		# 升级奖励统一在这里结算，runner 只根据结果发事件。
		next_state["available_stat_points"] = int(next_state.get("available_stat_points", 0)) + 3
		next_state["available_skill_points"] = int(next_state.get("available_skill_points", 0)) + 1
		next_state["total_stat_points_earned"] = int(next_state.get("total_stat_points_earned", 0)) + 3
		next_state["total_skill_points_earned"] = int(next_state.get("total_skill_points_earned", 0)) + 1
		level_ups.append({
			"new_level": int(next_state.get("level", 1)),
			"available_stat_points": int(next_state.get("available_stat_points", 0)),
			"available_skill_points": int(next_state.get("available_skill_points", 0)),
		})

	return {
		"changed": true,
		"state": next_state,
		"amount": xp_amount,
		"total_xp": int(next_state.get("current_xp", 0)),
		"level_ups": level_ups,
	}


func add_skill_points(state: Dictionary, amount: int) -> Dictionary:
	var points: int = max(0, amount)
	var next_state: Dictionary = _state_tools.normalized_state(state)
	if points <= 0:
		return {"changed": false, "state": next_state}
	next_state["available_skill_points"] = int(next_state.get("available_skill_points", 0)) + points
	next_state["total_skill_points_earned"] = int(next_state.get("total_skill_points_earned", 0)) + points
	return {
		"changed": true,
		"state": next_state,
		"available_skill_points": int(next_state.get("available_skill_points", 0)),
	}


func xp_to_next_level(level: int) -> int:
	return max(1, int(round(100.0 * pow(float(max(1, level)), 1.2))))
