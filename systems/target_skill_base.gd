class_name TargetSkillBase
extends "res://systems/target_ability_base.gd"

var _skill_id: String = ""
var _skill_definition: Dictionary = {}
var _skill_module: Node = null
var _skill_runtime: Node = null


func configure_from_skill(skill_id: String, skill_definition: Dictionary) -> void:
	_skill_id = skill_id
	_skill_definition = skill_definition.duplicate(true)
	ability_id = skill_id
	ability_kind = "skill"
	var activation: Dictionary = _skill_definition.get("activation", {})
	var targeting: Dictionary = activation.get("targeting", {})
	_configure_targeting(targeting)


func bind_skill_module(skill_module: Node) -> void:
	_skill_module = skill_module


func bind_skill_runtime(skill_runtime: Node) -> void:
	_skill_runtime = skill_runtime


func confirm_target(preview: Dictionary, context: Dictionary) -> Dictionary:
	if not bool(preview.get("valid", false)):
		return {"success": false, "reason": str(preview.get("reason", "invalid_preview")), "skill_id": _skill_id}
	if _skill_module != null and _skill_module.has_method("execute_targeted_skill_preview"):
		return _skill_module.execute_targeted_skill_preview(_skill_id, preview, context)
	if _skill_runtime != null and _skill_runtime.has_method("execute_targeted_skill_preview"):
		return _skill_runtime.execute_targeted_skill_preview(_skill_id, preview, context)
	return {"success": false, "reason": "missing_skill_target_executor", "skill_id": _skill_id}
