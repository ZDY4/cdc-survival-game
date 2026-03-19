@tool
extends "res://addons/cdc_game_editor/ai/adapters/ai_editor_adapter_base.gd"


func get_generation_rules() -> Array[String]:
	return [
		"record_type must be 'dialog'",
		"record must contain dialog_id, nodes, and connections",
		"every node id must be unique",
		"choice/condition/dialog/action next fields must stay consistent with the connections array"
	]


func summarize_record_changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var summary_lines: Array[String] = []
	var before_nodes := _extract_nodes(before)
	var after_nodes := _extract_nodes(after)
	if before_nodes != after_nodes:
		summary_lines.append("节点数量 %d -> %d" % [before_nodes, after_nodes])

	var before_branches := _count_branches(before)
	var after_branches := _count_branches(after)
	if before_branches != after_branches:
		summary_lines.append("分支数量 %d -> %d" % [before_branches, after_branches])

	var before_end_types := _collect_end_types(before)
	var after_end_types := _collect_end_types(after)
	if JSON.stringify(before_end_types) != JSON.stringify(after_end_types):
		summary_lines.append("结束节点类型发生变化")

	return _build_diff_summary(before, after, summary_lines)


func _extract_nodes(record: Dictionary) -> int:
	var nodes := record.get("nodes", [])
	return nodes.size() if nodes is Array else 0


func _count_branches(record: Dictionary) -> int:
	var total := 0
	var nodes := record.get("nodes", [])
	if not (nodes is Array):
		return total
	for node_variant in nodes:
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		match str(node.get("type", "")):
			"choice":
				var options := node.get("options", [])
				if options is Array:
					total += options.size()
			"condition":
				if not str(node.get("true_next", "")).strip_edges().is_empty():
					total += 1
				if not str(node.get("false_next", "")).strip_edges().is_empty():
					total += 1
	return total


func _collect_end_types(record: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var nodes := record.get("nodes", [])
	if not (nodes is Array):
		return result
	for node_variant in nodes:
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		if str(node.get("type", "")) != "end":
			continue
		var end_type := str(node.get("end_type", "normal")).strip_edges()
		if end_type.is_empty():
			end_type = "normal"
		if not result.has(end_type):
			result.append(end_type)
	result.sort()
	return result
