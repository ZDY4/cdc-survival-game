@tool
extends "res://addons/cdc_game_editor/ai/adapters/ai_editor_adapter_base.gd"


func get_generation_rules() -> Array[String]:
	return [
		"record_type must be 'quest'",
		"record must use the flow graph schema instead of the legacy objectives/rewards schema",
		"flow.start_node_id must point to an existing start node",
		"the flow must contain exactly one start node and at least one end node"
	]


func summarize_record_changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var summary_lines: Array[String] = []
	var before_node_count := _count_flow_nodes(before)
	var after_node_count := _count_flow_nodes(after)
	if before_node_count != after_node_count:
		summary_lines.append("流程节点数量 %d -> %d" % [before_node_count, after_node_count])

	var before_objective_types := _collect_objective_types(before)
	var after_objective_types := _collect_objective_types(after)
	if JSON.stringify(before_objective_types) != JSON.stringify(after_objective_types):
		summary_lines.append("任务目标类型发生变化")

	var before_reward_refs := _collect_reward_item_refs(before)
	var after_reward_refs := _collect_reward_item_refs(after)
	if JSON.stringify(before_reward_refs) != JSON.stringify(after_reward_refs):
		summary_lines.append("奖励引用发生变化")

	var before_prereqs := _collect_prerequisites(before)
	var after_prereqs := _collect_prerequisites(after)
	if JSON.stringify(before_prereqs) != JSON.stringify(after_prereqs):
		summary_lines.append("前置任务发生变化")

	return _build_diff_summary(before, after, summary_lines)


func _count_flow_nodes(record: Dictionary) -> int:
	var flow := record.get("flow", {})
	if not (flow is Dictionary):
		return 0
	var nodes := (flow as Dictionary).get("nodes", {})
	return nodes.size() if nodes is Dictionary else 0


func _collect_objective_types(record: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for node in _iterate_flow_nodes(record):
		if str(node.get("type", "")) != "objective":
			continue
		var objective_type := str(node.get("objective_type", "")).strip_edges()
		if objective_type.is_empty() or result.has(objective_type):
			continue
		result.append(objective_type)
	result.sort()
	return result


func _collect_reward_item_refs(record: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for node in _iterate_flow_nodes(record):
		if str(node.get("type", "")) != "reward":
			continue
		var rewards := node.get("rewards", {})
		if not (rewards is Dictionary):
			continue
		var items := (rewards as Dictionary).get("items", [])
		if not (items is Array):
			continue
		for reward_item in items:
			if not (reward_item is Dictionary):
				continue
			var item_id := str((reward_item as Dictionary).get("id", "")).strip_edges()
			if item_id.is_empty() or result.has(item_id):
				continue
			result.append(item_id)
	result.sort()
	return result


func _collect_prerequisites(record: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var prerequisites := record.get("prerequisites", [])
	if not (prerequisites is Array):
		return result
	for prereq in prerequisites:
		var prereq_id := str(prereq).strip_edges()
		if prereq_id.is_empty() or result.has(prereq_id):
			continue
		result.append(prereq_id)
	result.sort()
	return result


func _iterate_flow_nodes(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var flow := record.get("flow", {})
	if not (flow is Dictionary):
		return result
	var nodes := (flow as Dictionary).get("nodes", {})
	if not (nodes is Dictionary):
		return result
	for node_id in (nodes as Dictionary).keys():
		var node: Variant = (nodes as Dictionary).get(node_id, {})
		if node is Dictionary:
			result.append((node as Dictionary).duplicate(true))
	return result
