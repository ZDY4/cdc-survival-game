@tool
extends "res://addons/cdc_game_editor/ai/adapters/ai_editor_adapter_base.gd"


func get_generation_rules() -> Array[String]:
	return [
		"record_type must be 'item'",
		"record.id must be a positive integer",
		"record must follow the real item JSON schema used in data/items/*.json",
		"do not omit item fields that are used by the game runtime such as value, stackable, max_stack, icon_path, equippable, slot, durability, usable, and attributes_bonus"
	]


func summarize_record_changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var diff_summary := _build_diff_summary(before, after, [])
	var summary_lines: Array[String] = []
	if _has_any_paths(diff_summary, ["name", "description", "type", "subtype", "rarity"]):
		summary_lines.append("基础信息发生变化")
	if _has_any_paths(diff_summary, [
		"weight",
		"value",
		"level_requirement",
		"max_stack",
		"durability",
		"max_durability"
	]):
		summary_lines.append("数值字段发生变化")
	if _has_any_paths(diff_summary, [
		"equippable",
		"slot",
		"repairable",
		"usable",
		"attributes_bonus",
		"special_effects",
		"consumable_data",
		"repair_materials",
		"crafting_recipe",
		"deconstruct_yield"
	]):
		summary_lines.append("装备/使用效果相关字段发生变化")
	return _build_diff_summary(before, after, summary_lines)
