extends Node
## SkillSystem - 兼容层
## 为旧逻辑提供 /root/SkillSystem 入口，内部转发到 SkillModule。

signal skill_learned(skill_id: String, skill_data: Dictionary)
signal skill_points_changed(available_points: int)

var _module: Node = null


func _ready() -> void:
	_module = get_node_or_null("/root/SkillModule")
	if _module == null:
		push_warning("[SkillSystem] SkillModule 未找到，兼容层不可用")
		return

	_module.skill_learned.connect(_on_skill_learned)
	_module.skill_points_changed.connect(_on_skill_points_changed)


func can_learn_skill(skill_id: String) -> Dictionary:
	if _module == null:
		return {"can_learn": false, "reason": "SkillModule unavailable"}
	return _module.get_can_learn_result(skill_id)


func learn_skill(skill_id: String) -> Dictionary:
	if _module == null:
		return {"success": false, "reason": "SkillModule unavailable"}

	var success: bool = _module.learn_skill(skill_id)
	if not success:
		var check: Dictionary = _module.get_can_learn_result(skill_id)
		return {"success": false, "reason": check.get("reason", "unknown")}

	var skill_data: Dictionary = _module.get_skill(skill_id)
	return {
		"success": true,
		"skill_id": skill_id,
		"skill_name": skill_data.get("name", skill_id),
		"new_level": int(skill_data.get("current_level", 0)),
		"max_level": int(skill_data.get("max_level", 1)),
		"effect": skill_data.get("active_effect", {})
	}


func add_skill_points(points: int) -> void:
	if _module != null:
		_module.add_skill_points(points)


func set_available_points(points: int) -> void:
	if _module != null:
		_module.set_skill_points(points)


func get_available_points() -> int:
	if _module == null:
		return 0
	return _module.get_available_skill_points()


func reset_skills() -> void:
	if _module != null:
		_module.reset_skills()


func get_skill(skill_id: String) -> Dictionary:
	if _module == null:
		return {}
	return _module.get_skill(skill_id)


func get_all_skills() -> Dictionary:
	if _module == null:
		return {}
	return _module.get_all_skills()


func get_skill_level(skill_id: String) -> int:
	if _module == null:
		return 0
	return _module.get_skill_level(skill_id)


func get_skill_tree_data() -> Dictionary:
	if _module == null:
		return {}
	return _module.get_skill_tree_data()


func get_total_effect(effect_name: String) -> float:
	if _module == null:
		return 0.0
	return _module.get_total_effect(effect_name)


func get_damage_bonus() -> float:
	return get_total_effect("damage_bonus")


func get_crit_chance_bonus() -> float:
	return get_total_effect("crit_chance")


func get_damage_reduction_bonus() -> float:
	return get_total_effect("damage_reduction")


func get_healing_bonus() -> float:
	return get_total_effect("healing_bonus")


func get_loot_bonus_chance() -> float:
	if _module == null:
		return 0.0
	return _module.get_loot_bonus_chance()


func get_crafting_bonus() -> float:
	if _module == null:
		return 0.0
	return _module.get_crafting_bonus()


func serialize() -> Dictionary:
	if _module == null:
		return {}
	return _module.serialize()


func deserialize(data: Dictionary) -> void:
	if _module != null:
		_module.deserialize(data)


func _on_skill_learned(skill_id: String) -> void:
	var skill_data: Dictionary = {}
	if _module != null:
		skill_data = _module.get_skill(skill_id)
	skill_learned.emit(skill_id, skill_data)


func _on_skill_points_changed(points: int) -> void:
	skill_points_changed.emit(points)
