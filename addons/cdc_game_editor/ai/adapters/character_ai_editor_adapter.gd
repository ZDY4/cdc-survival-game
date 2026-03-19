@tool
extends "res://addons/cdc_game_editor/ai/adapters/ai_editor_adapter_base.gd"


func get_generation_rules() -> Array[String]:
	return [
		"record_type must be 'character'",
		"record.id must use lowercase snake_case",
		"record must contain identity, visual, combat, social, and skills blocks",
		"skills.initial_tree_ids and skills.initial_skills_by_tree must stay internally consistent"
	]


func summarize_record_changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var diff_summary := _build_diff_summary(before, after, [])
	var summary_lines: Array[String] = []
	if _has_any_paths(diff_summary, ["identity", "visual"]):
		summary_lines.append("身份或外观信息发生变化")
	if _has_any_paths(diff_summary, ["social"]):
		summary_lines.append("社交属性或对话引用发生变化")
	if _has_any_paths(diff_summary, ["combat"]):
		summary_lines.append("战斗属性发生变化")
	if _has_any_paths(diff_summary, ["skills"]):
		summary_lines.append("技能树或初始技能配置发生变化")
	return _build_diff_summary(before, after, summary_lines)
