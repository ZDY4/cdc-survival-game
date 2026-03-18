extends Node
## SkillSystem - 兼容层
## 为旧逻辑提供 /root/SkillSystem 入口，内部转发到 SkillModule。

signal skill_learned(skill_id: String, skill_data: Dictionary)
signal skill_points_changed(available_points: int)
signal hotbar_changed(group_index: int, slots: Array)
signal hotbar_group_changed(group_index: int)
signal skill_activation_succeeded(skill_id: String, result: Dictionary)
signal skill_activation_failed(skill_id: String, reason: String)
signal skill_toggle_changed(skill_id: String, active: bool)

var _module: Node = null


func _ready() -> void:
	_module = get_node_or_null("/root/SkillModule")
	if _module == null:
		push_warning("[SkillSystem] SkillModule 未找到，兼容层不可用")
		return

	_module.skill_learned.connect(_on_skill_learned)
	_module.skill_points_changed.connect(_on_skill_points_changed)
	_module.hotbar_changed.connect(_on_hotbar_changed)
	_module.hotbar_group_changed.connect(_on_hotbar_group_changed)
	_module.skill_activation_succeeded.connect(_on_skill_activation_succeeded)
	_module.skill_activation_failed.connect(_on_skill_activation_failed)
	_module.skill_toggle_changed.connect(_on_skill_toggle_changed)


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


func is_hotbar_eligible(skill_id: String) -> bool:
	return _module != null and bool(_module.is_hotbar_eligible(skill_id))


func get_hotbar_groups() -> Array:
	if _module == null:
		return []
	return _module.get_hotbar_groups()


func get_active_hotbar_group() -> int:
	if _module == null:
		return 0
	return int(_module.get_active_hotbar_group())


func set_active_hotbar_group(index: int) -> void:
	if _module != null:
		_module.set_active_hotbar_group(index)


func cycle_hotbar_group(delta: int) -> int:
	if _module == null:
		return 0
	return int(_module.cycle_hotbar_group(delta))


func assign_skill_to_hotbar(skill_id: String, group_index: int, slot_index: int) -> Dictionary:
	if _module == null:
		return {"success": false, "reason": "SkillModule unavailable"}
	return _module.assign_skill_to_hotbar(skill_id, group_index, slot_index)


func move_hotbar_skill(group_index: int, from_slot: int, to_slot: int) -> Dictionary:
	if _module == null:
		return {"success": false, "reason": "SkillModule unavailable"}
	return _module.move_hotbar_skill(group_index, from_slot, to_slot)


func clear_hotbar_slot(group_index: int, slot_index: int) -> void:
	if _module != null:
		_module.clear_hotbar_slot(group_index, slot_index)


func activate_hotbar_slot(slot_index: int) -> Dictionary:
	if _module == null:
		return {"success": false, "reason": "SkillModule unavailable"}
	return _module.activate_hotbar_slot(slot_index)


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


func _on_hotbar_changed(group_index: int, slots: Array) -> void:
	hotbar_changed.emit(group_index, slots)


func _on_hotbar_group_changed(group_index: int) -> void:
	hotbar_group_changed.emit(group_index)


func _on_skill_activation_succeeded(skill_id: String, result: Dictionary) -> void:
	skill_activation_succeeded.emit(skill_id, result)


func _on_skill_activation_failed(skill_id: String, reason: String) -> void:
	skill_activation_failed.emit(skill_id, reason)


func _on_skill_toggle_changed(skill_id: String, active: bool) -> void:
	skill_toggle_changed.emit(skill_id, active)
