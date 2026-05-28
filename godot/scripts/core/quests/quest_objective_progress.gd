extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const QuestDefinitionIndex = preload("res://scripts/core/quests/quest_definition_index.gd")

var _inventory_entries := InventoryEntries.new()
var _quest_index := QuestDefinitionIndex.new()


func collect_progress(quest_id: String, quest_data: Dictionary, state: Dictionary, item_id: String, count: int) -> Dictionary:
	var objective: Dictionary = _quest_index.first_objective_node(quest_data)
	if objective.get("objective_type", "") != "collect":
		return {"matched": false}
	if _inventory_entries.normalize_content_id(objective.get("item_id", "")) != item_id:
		return {"matched": false}
	return _advance_objective_state(quest_id, state, objective, max(0, count))


func kill_progress(quest_id: String, quest_data: Dictionary, state: Dictionary, enemy_definition_id: String, enemy_kind: String) -> Dictionary:
	var objective: Dictionary = _quest_index.first_objective_node(quest_data)
	if objective.get("objective_type", "") != "kill":
		return {"matched": false}
	var enemy_type: String = str(objective.get("enemy_type", ""))
	if not enemy_type.is_empty() and not _quest_index.enemy_matches_objective(enemy_definition_id, enemy_kind, enemy_type):
		return {"matched": false}
	return _advance_objective_state(quest_id, state, objective, 1)


func _advance_objective_state(quest_id: String, state: Dictionary, objective: Dictionary, delta: int) -> Dictionary:
	var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {})).duplicate(true)
	var objective_id: String = str(objective.get("id", ""))
	var target_count: int = max(1, int(objective.get("count", 1)))
	# 规则层只计算封顶后的目标进度，事件发送和任务完成调度仍由 QuestRunner 统一处理。
	var current: int = min(target_count, int(completed.get(objective_id, 0)) + delta)
	completed[objective_id] = current
	var updated_state: Dictionary = state.duplicate(true)
	updated_state["completed_objectives"] = completed
	return {
		"matched": true,
		"quest_id": quest_id,
		"objective_id": objective_id,
		"current": current,
		"target": target_count,
		"completed": current >= target_count,
		"state": updated_state,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
