extends "res://core/base_module.gd"
## SkillModule - 数据驱动技能系统
## 技能描述目录: res://data/skills/*.json
## 技能树配置目录: res://data/skill_trees/*.json

const InputActions = preload("res://core/input_actions.gd")
const TargetSkillBase = preload("res://systems/target_skill_base.gd")

const SKILLS_DATA_DIR: String = "res://data/skills"
const SKILL_TREES_DATA_DIR: String = "res://data/skill_trees"
const HOTBAR_GROUP_COUNT: int = 5
const HOTBAR_SLOT_COUNT: int = 10
const PLAYER_ENTITY_ID: String = "player"
const ACTIVATION_MODE_PASSIVE: String = "passive"
const ACTIVATION_MODE_ACTIVE: String = "active"
const ACTIVATION_MODE_TOGGLE: String = "toggle"

signal skill_learned(skill_id: String)
signal skill_upgraded(skill_id: String, new_level: int)
signal skill_points_changed(amount: int)
signal skill_data_reloaded(skill_count: int, tree_count: int)
signal hotbar_changed(group_index: int, slots: Array)
signal hotbar_group_changed(group_index: int)
signal skill_activation_succeeded(skill_id: String, result: Dictionary)
signal skill_activation_failed(skill_id: String, reason: String)
signal skill_toggle_changed(skill_id: String, active: bool)
signal skill_targeting_started(skill_id: String, session: Dictionary)
signal skill_targeting_cancelled(skill_id: String, reason: String)

var skill_points: int = 0
var learned_skills: Dictionary = {}
var hotbar_groups: Array = []
var active_hotbar_group: int = 0

var _skills: Dictionary = {}
var _skill_trees: Dictionary = {}
var _active_effects: Dictionary = {}
var _toggle_effects: Dictionary = {}
var _total_effects: Dictionary = {}
var _cooldown_remaining: Dictionary = {}
var _active_toggles: Dictionary = {}
var _effect_system: Node = null
var _targeted_skill_sessions: Dictionary = {}


func _ready() -> void:
	super._ready()
	set_process(true)
	call_deferred("_initialize_skill_framework")


func _process(delta: float) -> void:
	_tick_activation_cooldowns(delta)


func _initialize_skill_framework() -> void:
	_effect_system = get_node_or_null("/root/EffectSystem")
	_ensure_hotbar_state()
	reload_skill_data()


func reload_skill_data() -> bool:
	_skills = _load_skills_from_directory(SKILLS_DATA_DIR)
	if _skills.is_empty():
		push_error("[SkillModule] 技能数据加载失败或为空: %s" % SKILLS_DATA_DIR)
		return false

	_skill_trees = _load_skill_trees_from_directory(SKILL_TREES_DATA_DIR)
	_ensure_hotbar_state()
	_rebuild_all_effects()
	_restore_toggle_effects()
	_purge_invalid_hotbar_assignments()
	skill_data_reloaded.emit(_skills.size(), _skill_trees.size())
	return true


func reload_skill(skill_id: String) -> bool:
	var path: String = "%s/%s.json" % [SKILLS_DATA_DIR, skill_id]
	var data: Variant = _load_json(path)
	if not (data is Dictionary):
		return false

	_skills[skill_id] = _normalize_skill(skill_id, data as Dictionary)
	_refresh_skill_effect(skill_id)
	_refresh_toggle_effect(skill_id)
	_purge_invalid_hotbar_assignments()
	skill_data_reloaded.emit(_skills.size(), _skill_trees.size())
	return true


func reload_skill_tree(tree_id: String) -> bool:
	var path: String = "%s/%s.json" % [SKILL_TREES_DATA_DIR, tree_id]
	var data: Variant = _load_json(path)
	if not (data is Dictionary):
		return false

	_skill_trees[tree_id] = _normalize_tree(tree_id, data as Dictionary)
	skill_data_reloaded.emit(_skills.size(), _skill_trees.size())
	return true


func add_skill_points(amount: int) -> void:
	if amount <= 0:
		return
	skill_points += amount
	skill_points_changed.emit(skill_points)


func set_skill_points(amount: int) -> void:
	skill_points = maxi(0, amount)
	skill_points_changed.emit(skill_points)


func get_available_skill_points() -> int:
	return skill_points


func get_can_learn_result(skill_id: String) -> Dictionary:
	var skill: Dictionary = _skills.get(skill_id, {})
	if skill.is_empty():
		return {"can_learn": false, "reason": "技能不存在"}

	if skill_points <= 0:
		return {"can_learn": false, "reason": "没有可用技能点"}

	var current_level: int = get_skill_level(skill_id)
	var max_level: int = int(skill.get("max_level", 1))
	if current_level >= max_level:
		return {"can_learn": false, "reason": "技能已满级"}

	var prerequisites: Array[String] = _normalize_string_array(skill.get("prerequisites", []))
	for prerequisite_id in prerequisites:
		if get_skill_level(prerequisite_id) <= 0:
			var prerequisite: Dictionary = _skills.get(prerequisite_id, {})
			var prerequisite_name: String = str(prerequisite.get("name", prerequisite_id))
			return {"can_learn": false, "reason": "需要先学习: %s" % prerequisite_name}

	var requirements: Dictionary = skill.get("attribute_requirements", {})
	for attribute_name in requirements.keys():
		var required_value: int = int(requirements.get(attribute_name, 0))
		var current_value: int = _get_attribute_value(str(attribute_name))
		if current_value < required_value:
			return {
				"can_learn": false,
				"reason": "%s 需要达到 %d" % [attribute_name, required_value]
			}

	return {"can_learn": true, "reason": ""}


func can_learn_skill(skill_id: String) -> bool:
	return bool(get_can_learn_result(skill_id).get("can_learn", false))


func learn_skill(skill_id: String) -> bool:
	var check: Dictionary = get_can_learn_result(skill_id)
	if not bool(check.get("can_learn", false)):
		return false

	var previous_level: int = get_skill_level(skill_id)
	var new_level: int = previous_level + 1
	learned_skills[skill_id] = new_level
	skill_points = maxi(0, skill_points - 1)

	if previous_level == 0:
		skill_learned.emit(skill_id)
	skill_upgraded.emit(skill_id, new_level)
	skill_points_changed.emit(skill_points)
	_refresh_skill_effect(skill_id)
	_refresh_toggle_effect(skill_id)
	return true


func reset_skills() -> void:
	var refunded_points: int = 0
	for skill_id_variant in learned_skills.keys():
		refunded_points += int(learned_skills.get(skill_id_variant, 0))
	learned_skills.clear()
	_remove_all_skill_effects_from_system()
	_remove_all_toggle_effects_from_system()
	_active_effects.clear()
	_toggle_effects.clear()
	_total_effects.clear()
	_cooldown_remaining.clear()
	_active_toggles.clear()
	_targeted_skill_sessions.clear()
	skill_points += refunded_points
	_purge_invalid_hotbar_assignments()
	skill_points_changed.emit(skill_points)


func get_skill_level(skill_id: String) -> int:
	return int(learned_skills.get(skill_id, 0))


func get_skill_effect(skill_id: String) -> Dictionary:
	var effect: Variant = _active_effects.get(skill_id, null)
	if effect is GameplayEffect:
		return (effect as GameplayEffect).get_modifiers()
	if effect is Dictionary:
		return effect as Dictionary
	return {}


func get_total_effect(effect_name: String) -> float:
	if _effect_system != null and _effect_system.has_method("get_total_modifiers"):
		var modifiers: Dictionary = _effect_system.get_total_modifiers(PLAYER_ENTITY_ID)
		var external_value: Variant = modifiers.get(effect_name, 0.0)
		return float(external_value)

	var value: Variant = _total_effects.get(effect_name, 0.0)
	if value is int:
		return float(value)
	if value is float:
		return value
	return 0.0


func get_total_damage_bonus(skill_id: String = "combat") -> float:
	if not skill_id.is_empty():
		var effect: Dictionary = get_skill_effect(skill_id)
		if not effect.is_empty():
			return float(effect.get("damage_bonus", 0.0))
	return get_total_effect("damage_bonus")


func get_consumption_reduction(skill_id: String = "survival") -> float:
	if not skill_id.is_empty():
		var effect: Dictionary = get_skill_effect(skill_id)
		if not effect.is_empty():
			return float(effect.get("consumption_reduction", 0.0))
	return get_total_effect("consumption_reduction")


func get_loot_bonus_chance() -> float:
	return get_total_effect("extra_loot_chance")


func get_crafting_bonus() -> float:
	return get_total_effect("crafting_speed") + get_total_effect("material_efficiency")


func get_skill(skill_id: String) -> Dictionary:
	var base_skill: Dictionary = _skills.get(skill_id, {})
	if base_skill.is_empty():
		return {}

	var result: Dictionary = base_skill.duplicate(true)
	result["current_level"] = get_skill_level(skill_id)
	result["is_learned"] = int(result["current_level"]) > 0
	result["is_maxed"] = int(result["current_level"]) >= int(base_skill.get("max_level", 1))
	result["can_learn"] = can_learn_skill(skill_id)
	result["active_effect"] = get_skill_effect(skill_id)
	result["hotbar_eligible"] = is_hotbar_eligible(skill_id)
	result["cooldown_remaining"] = get_skill_cooldown_remaining(skill_id)
	result["toggle_active"] = is_skill_toggle_active(skill_id)
	return result


func get_skill_definition(skill_id: String) -> Dictionary:
	var skill: Dictionary = _skills.get(skill_id, {})
	if skill.is_empty():
		return {}
	return skill.duplicate(true)


func get_all_skills() -> Dictionary:
	var result: Dictionary = {}
	for skill_id_variant in _skills.keys():
		var skill_id: String = str(skill_id_variant)
		result[skill_id] = get_skill(skill_id)
	return result


func get_available_skills() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for skill_id_variant in _skills.keys():
		var skill_id: String = str(skill_id_variant)
		available.append(get_skill(skill_id))
	return available


func get_skill_tree_data() -> Dictionary:
	var trees: Dictionary = {}

	for tree_id_variant in _skill_trees.keys():
		var tree_id: String = str(tree_id_variant)
		var tree: Dictionary = _skill_trees.get(tree_id, {})
		var tree_skills: Dictionary = {}
		var skill_ids: Array[String] = _normalize_string_array(tree.get("skills", []))
		for skill_id in skill_ids:
			if _skills.has(skill_id):
				tree_skills[skill_id] = get_skill(skill_id)

		trees[tree_id] = {
			"name": tree.get("name", tree_id),
			"description": tree.get("description", ""),
			"skills": tree_skills,
			"links": tree.get("links", []),
			"layout": tree.get("layout", {})
		}

	for skill_id_variant in _skills.keys():
		var skill_id: String = str(skill_id_variant)
		var skill: Dictionary = _skills.get(skill_id, {})
		var tree_id: String = str(skill.get("tree_id", "default"))
		if not trees.has(tree_id):
			trees[tree_id] = {
				"name": tree_id,
				"description": "",
				"skills": {},
				"links": [],
				"layout": {}
			}
		var bucket: Dictionary = trees[tree_id]
		var bucket_skills: Dictionary = bucket.get("skills", {})
		if not bucket_skills.has(skill_id):
			bucket_skills[skill_id] = get_skill(skill_id)
			bucket["skills"] = bucket_skills
			trees[tree_id] = bucket

	return trees


func get_skill_tree_definition(tree_id: String) -> Dictionary:
	var tree: Dictionary = _skill_trees.get(tree_id, {})
	if tree.is_empty():
		return {}
	return tree.duplicate(true)


func is_hotbar_eligible(skill_id: String) -> bool:
	if get_skill_level(skill_id) <= 0:
		return false
	var activation: Dictionary = _get_activation_config(skill_id)
	return str(activation.get("mode", ACTIVATION_MODE_PASSIVE)) != ACTIVATION_MODE_PASSIVE


func get_hotbar_groups() -> Array:
	_ensure_hotbar_state()
	return hotbar_groups.duplicate(true)


func get_active_hotbar_group() -> int:
	_ensure_hotbar_state()
	return active_hotbar_group


func set_active_hotbar_group(index: int) -> void:
	_ensure_hotbar_state()
	var normalized: int = _normalize_group_index(index)
	if normalized == active_hotbar_group:
		return
	active_hotbar_group = normalized
	hotbar_group_changed.emit(active_hotbar_group)


func cycle_hotbar_group(delta: int) -> int:
	set_active_hotbar_group(active_hotbar_group + delta)
	return active_hotbar_group


func assign_skill_to_hotbar(skill_id: String, group_index: int, slot_index: int) -> Dictionary:
	_ensure_hotbar_state()
	if not _skills.has(skill_id):
		return {"success": false, "reason": "技能不存在"}
	if not is_hotbar_eligible(skill_id):
		return {"success": false, "reason": "只有已学习的主动/开启技能可加入快捷栏"}
	if not _is_group_index_valid(group_index) or not _is_slot_index_valid(slot_index):
		return {"success": false, "reason": "快捷栏位置无效"}

	var slots: Array = hotbar_groups[group_index]
	var existing_slot: int = _find_skill_in_group(skill_id, group_index)
	if existing_slot >= 0:
		if existing_slot == slot_index:
			return {
				"success": true,
				"reason": "",
				"action": "unchanged",
				"group_index": group_index,
				"slot_index": slot_index
			}
		return move_hotbar_skill(group_index, existing_slot, slot_index)

	var previous_skill: String = str(slots[slot_index])
	slots[slot_index] = skill_id
	_emit_hotbar_changed(group_index)
	return {
		"success": true,
		"reason": "",
		"action": "assigned" if previous_skill.is_empty() else "replaced",
		"group_index": group_index,
		"slot_index": slot_index,
		"replaced_skill_id": previous_skill
	}


func move_hotbar_skill(group_index: int, from_slot: int, to_slot: int) -> Dictionary:
	_ensure_hotbar_state()
	if not _is_group_index_valid(group_index):
		return {"success": false, "reason": "快捷栏组无效"}
	if not _is_slot_index_valid(from_slot) or not _is_slot_index_valid(to_slot):
		return {"success": false, "reason": "快捷栏槽位无效"}

	var slots: Array = hotbar_groups[group_index]
	var source_skill: String = str(slots[from_slot])
	if source_skill.is_empty():
		return {"success": false, "reason": "源槽位为空"}
	if from_slot == to_slot:
		return {
			"success": true,
			"reason": "",
			"action": "unchanged",
			"group_index": group_index,
			"slot_index": from_slot
		}
	var target_skill: String = str(slots[to_slot])
	slots[to_slot] = source_skill
	slots[from_slot] = target_skill
	_emit_hotbar_changed(group_index)
	return {
		"success": true,
		"reason": "",
		"action": "moved" if target_skill.is_empty() else "swapped",
		"group_index": group_index,
		"from_slot": from_slot,
		"to_slot": to_slot,
		"target_skill_id": target_skill
	}


func clear_hotbar_slot(group_index: int, slot_index: int) -> void:
	_ensure_hotbar_state()
	if not _is_group_index_valid(group_index) or not _is_slot_index_valid(slot_index):
		return
	var slots: Array = hotbar_groups[group_index]
	if str(slots[slot_index]).is_empty():
		return
	slots[slot_index] = ""
	_emit_hotbar_changed(group_index)


func activate_hotbar_slot(slot_index: int) -> Dictionary:
	_ensure_hotbar_state()
	if not _is_slot_index_valid(slot_index):
		return {"success": false, "reason": "快捷栏槽位无效"}

	var slots: Array = hotbar_groups[active_hotbar_group]
	var skill_id: String = str(slots[slot_index])
	if skill_id.is_empty():
		return {"success": false, "reason": "槽位为空"}
	if not is_hotbar_eligible(skill_id):
		var ineligible_reason: String = "技能尚未学习或不可主动施放"
		skill_activation_failed.emit(skill_id, ineligible_reason)
		return {"success": false, "reason": ineligible_reason}

	var cooldown_remaining: float = get_skill_cooldown_remaining(skill_id)
	if cooldown_remaining > 0.0:
		var cooldown_reason: String = "冷却中"
		skill_activation_failed.emit(skill_id, cooldown_reason)
		return {
			"success": false,
			"reason": cooldown_reason,
			"skill_id": skill_id,
			"cooldown_remaining": cooldown_remaining
		}

	var activation: Dictionary = _get_activation_config(skill_id)
	var mode: String = str(activation.get("mode", ACTIVATION_MODE_PASSIVE))
	var result: Dictionary = {}
	match mode:
		ACTIVATION_MODE_ACTIVE:
			if _is_targeted_activation(activation):
				result = _start_targeted_skill_activation(skill_id, slot_index)
			else:
				result = _activate_active_skill(skill_id)
		ACTIVATION_MODE_TOGGLE:
			result = _activate_toggle_skill(skill_id)
		_:
			result = {"success": false, "reason": "技能不支持快捷栏触发"}

	if bool(result.get("success", false)):
		skill_activation_succeeded.emit(skill_id, result)
	else:
		skill_activation_failed.emit(skill_id, str(result.get("reason", "触发失败")))
	return result


func cast_targeted_skill(skill_id: String, preview: Dictionary) -> Dictionary:
	var session: Dictionary = _get_targeted_skill_session(skill_id)
	if session.is_empty():
		return {"success": false, "reason": "missing_target_session", "skill_id": skill_id}
	return execute_targeted_skill_preview(skill_id, preview, session.get("context", {}))


func cancel_targeted_skill(skill_id: String, reason: String = "cancelled") -> void:
	if not _targeted_skill_sessions.has(skill_id):
		return
	_targeted_skill_sessions.erase(skill_id)
	skill_targeting_cancelled.emit(skill_id, reason)


func get_targeted_skill_handler(skill_id: String) -> TargetSkillBase:
	var skill_definition: Dictionary = get_skill_definition(skill_id)
	if skill_definition.is_empty():
		return null
	return _create_targeted_skill_handler(skill_id, skill_definition)


func execute_targeted_skill_preview(skill_id: String, preview: Dictionary, context: Dictionary) -> Dictionary:
	if get_skill_level(skill_id) <= 0:
		return {"success": false, "reason": "技能尚未学习", "skill_id": skill_id}
	if get_skill_cooldown_remaining(skill_id) > 0.0:
		return {
			"success": false,
			"reason": "冷却中",
			"skill_id": skill_id,
			"cooldown_remaining": get_skill_cooldown_remaining(skill_id)
		}

	var skill_definition: Dictionary = get_skill_definition(skill_id)
	if skill_definition.is_empty():
		return {"success": false, "reason": "技能不存在", "skill_id": skill_id}
	var activation: Dictionary = skill_definition.get("activation", {})
	if not _is_targeted_activation(activation):
		return {"success": false, "reason": "技能不是目标型技能", "skill_id": skill_id}

	var handler: TargetSkillBase = context.get("handler", null) as TargetSkillBase
	if handler == null:
		handler = _create_targeted_skill_handler(skill_id, skill_definition)
	if handler == null:
		return {"success": false, "reason": "目标处理器创建失败", "skill_id": skill_id}

	var validation: Dictionary = handler.is_preview_valid(preview, context)
	if not bool(validation.get("valid", false)):
		return {"success": false, "reason": str(validation.get("reason", "invalid_preview")), "skill_id": skill_id}

	var result: Dictionary = _apply_active_skill(skill_id)
	if bool(result.get("success", false)):
		result["preview"] = preview.duplicate(true)
		result["state"] = "cast_confirmed"
		_targeted_skill_sessions.erase(skill_id)
	return result


func get_skill_cooldown_remaining(skill_id: String) -> float:
	return maxf(0.0, float(_cooldown_remaining.get(skill_id, 0.0)))


func is_skill_toggle_active(skill_id: String) -> bool:
	return bool(_active_toggles.get(skill_id, false))


func serialize() -> Dictionary:
	return {
		"skill_points": skill_points,
		"learned_skills": learned_skills.duplicate(true),
		"hotbar": {
			"groups": hotbar_groups.duplicate(true),
			"active_group": active_hotbar_group
		},
		"activation_state": {
			"cooldowns": _cooldown_remaining.duplicate(true),
			"active_toggles": _active_toggles.keys()
		}
	}


func deserialize(data: Dictionary) -> void:
	skill_points = int(data.get("skill_points", 0))
	var loaded_levels: Dictionary = data.get("learned_skills", {})
	learned_skills.clear()
	for skill_id_variant in loaded_levels.keys():
		var skill_id: String = str(skill_id_variant)
		learned_skills[skill_id] = maxi(0, int(loaded_levels.get(skill_id_variant, 0)))

	_deserialize_hotbar_state(data.get("hotbar", {}))
	_deserialize_activation_state(data.get("activation_state", {}))
	_targeted_skill_sessions.clear()
	_rebuild_all_effects()
	_restore_toggle_effects()
	_purge_invalid_hotbar_assignments()
	skill_points_changed.emit(skill_points)
	hotbar_group_changed.emit(active_hotbar_group)
	for group_index in range(HOTBAR_GROUP_COUNT):
		_emit_hotbar_changed(group_index)


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("[SkillModule] 数据文件不存在: %s" % path)
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SkillModule] 无法打开文件: %s" % path)
		return null

	var json_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null:
		push_error("[SkillModule] JSON解析失败: %s" % path)
	return parsed


func _load_skills_from_directory(directory_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(directory_path)
	if dir == null:
		push_error("[SkillModule] 技能目录不存在或无法访问: %s" % directory_path)
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path: String = "%s/%s" % [directory_path, file_name]
			var data: Variant = _load_json(full_path)
			if data is Dictionary:
				var default_id: String = file_name.trim_suffix(".json")
				var skill_doc: Dictionary = data
				var skill_id: String = str(skill_doc.get("id", default_id))
				result[skill_id] = _normalize_skill(skill_id, skill_doc)
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func _load_skill_trees_from_directory(directory_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(directory_path)
	if dir == null:
		push_warning("[SkillModule] 技能树目录不存在或无法访问: %s" % directory_path)
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path: String = "%s/%s" % [directory_path, file_name]
			var data: Variant = _load_json(full_path)
			if data is Dictionary:
				var default_id: String = file_name.trim_suffix(".json")
				var tree_doc: Dictionary = data
				var tree_id: String = str(tree_doc.get("id", default_id))
				result[tree_id] = _normalize_tree(tree_id, tree_doc)
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func _normalize_skill(skill_id: String, data: Dictionary) -> Dictionary:
	var prerequisites: Array[String] = _normalize_string_array(data.get("prerequisites", []))
	var attribute_requirements: Dictionary = _normalize_int_dictionary(
		data.get("attribute_requirements", {})
	)
	var effect_config: Dictionary = _normalize_effect_config(data)
	var activation_config: Dictionary = _normalize_activation_config(data)

	return {
		"id": skill_id,
		"name": data.get("name", skill_id),
		"icon": data.get("icon", ""),
		"description": data.get("description", ""),
		"tree_id": data.get("tree_id", "default"),
		"max_level": maxi(1, int(data.get("max_level", 1))),
		"prerequisites": prerequisites,
		"attribute_requirements": attribute_requirements,
		"gameplay_effect": effect_config,
		"activation": activation_config
	}


func _normalize_tree(tree_id: String, data: Dictionary) -> Dictionary:
	var skills: Array[String] = _normalize_string_array(data.get("skills", []))
	var links: Array = data.get("links", [])
	if not (links is Array):
		links = []

	var layout: Dictionary = data.get("layout", {})
	if not (layout is Dictionary):
		layout = {}

	return {
		"id": tree_id,
		"name": data.get("name", tree_id),
		"description": data.get("description", ""),
		"skills": skills,
		"links": links,
		"layout": layout
	}


func _normalize_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func _normalize_int_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is Dictionary:
		var source: Dictionary = value
		for key in source.keys():
			result[str(key)] = int(source.get(key, 0))
	return result


func _normalize_effect_config(data: Dictionary) -> Dictionary:
	var config: Dictionary = {}
	var raw: Variant = data.get("gameplay_effect", null)
	if raw is Dictionary:
		config = (raw as Dictionary).duplicate(true)
		return config

	var legacy_params: Variant = data.get("effect_params", {})
	if not (legacy_params is Dictionary):
		return config

	var modifiers: Dictionary = {}
	if legacy_params.has("effect_name"):
		var effect_name: String = str(legacy_params.get("effect_name", ""))
		if not effect_name.is_empty():
			modifiers[effect_name] = {
				"per_level": float(legacy_params.get("per_level", 0.0)),
				"max_value": float(legacy_params.get("max_value", 0.0))
			}
	elif legacy_params.has("damage_bonus_per_level"):
		modifiers["damage_bonus"] = {
			"per_level": float(legacy_params.get("damage_bonus_per_level", 0.0))
		}
	elif legacy_params.has("consumption_reduction_per_level"):
		modifiers["consumption_reduction"] = {
			"per_level": float(legacy_params.get("consumption_reduction_per_level", 0.0)),
			"max_value": float(legacy_params.get("max_reduction", 0.0))
		}

	if not modifiers.is_empty():
		config["modifiers"] = modifiers

	return config


func _normalize_activation_config(data: Dictionary) -> Dictionary:
	var raw: Variant = data.get("activation", {})
	var config: Dictionary = {}
	if raw is Dictionary:
		config = (raw as Dictionary).duplicate(true)

	var mode: String = str(config.get("mode", ACTIVATION_MODE_PASSIVE)).to_lower()
	if mode != ACTIVATION_MODE_ACTIVE and mode != ACTIVATION_MODE_TOGGLE:
		mode = ACTIVATION_MODE_PASSIVE

	var normalized: Dictionary = {
		"mode": mode,
		"cooldown": maxf(0.0, float(config.get("cooldown", 0.0))),
		"effect": {},
		"targeting": _normalize_targeting_config(config.get("targeting", {}))
	}
	var effect: Variant = config.get("effect", {})
	if effect is Dictionary:
		normalized["effect"] = (effect as Dictionary).duplicate(true)
	if mode == ACTIVATION_MODE_PASSIVE:
		normalized["cooldown"] = 0.0
		normalized["effect"] = {}
		normalized["targeting"] = _normalize_targeting_config({})
	return normalized


func _normalize_targeting_config(value: Variant) -> Dictionary:
	var targeting: Dictionary = {}
	if value is Dictionary:
		targeting = (value as Dictionary).duplicate(true)
	var enabled: bool = bool(targeting.get("enabled", false))
	var shape: String = str(targeting.get("shape", "single")).to_lower()
	if shape not in ["single", "diamond", "square"]:
		shape = "single"
	return {
		"enabled": enabled,
		"range_cells": maxi(0, int(targeting.get("range_cells", 0))),
		"shape": shape,
		"radius": maxi(0, int(targeting.get("radius", 0))),
		"handler_script": str(targeting.get("handler_script", ""))
	}


func _rebuild_all_effects() -> void:
	_remove_all_skill_effects_from_system()
	_active_effects.clear()
	_total_effects.clear()
	for skill_id_variant in _skills.keys():
		_refresh_skill_effect(str(skill_id_variant))
	_recalculate_total_effects()


func _refresh_skill_effect(skill_id: String) -> void:
	var level: int = get_skill_level(skill_id)
	var effect: GameplayEffect = null
	if level > 0:
		effect = _compute_effect(skill_id, level)

	var previous: Variant = _active_effects.get(skill_id, null)
	if level <= 0 and previous is GameplayEffect and _effect_system != null:
		_effect_system.remove_effect((previous as GameplayEffect).id, PLAYER_ENTITY_ID)

	_active_effects[skill_id] = effect
	if effect != null and _effect_system != null:
		_effect_system.upsert_gameplay_effect(effect, PLAYER_ENTITY_ID)
	_recalculate_total_effects()


func _refresh_toggle_effect(skill_id: String) -> void:
	if not is_skill_toggle_active(skill_id):
		return
	if get_skill_level(skill_id) <= 0 or str(_get_activation_config(skill_id).get("mode", "")) != ACTIVATION_MODE_TOGGLE:
		_deactivate_toggle_skill(skill_id)
		return

	var effect: GameplayEffect = _compute_activation_effect(skill_id)
	if effect == null:
		_deactivate_toggle_skill(skill_id)
		return

	_toggle_effects[skill_id] = effect
	if _effect_system != null:
		_effect_system.upsert_gameplay_effect(effect, PLAYER_ENTITY_ID)
	_recalculate_total_effects()


func _compute_effect(skill_id: String, level: int) -> GameplayEffect:
	var skill: Dictionary = _skills.get(skill_id, {})
	if skill.is_empty():
		return null

	var config: Dictionary = skill.get("gameplay_effect", {})
	var modifiers: Dictionary = _build_modifiers_from_config(config, level)
	if modifiers.is_empty():
		return null

	var effect_def: Dictionary = config.duplicate(true)
	effect_def["id"] = "skill_%s" % skill_id
	effect_def["source_type"] = "skill"
	effect_def["source_id"] = skill_id
	if not effect_def.has("category"):
		effect_def["category"] = "skill"
	if not effect_def.has("is_infinite"):
		effect_def["is_infinite"] = true
	if not effect_def.has("is_stackable"):
		effect_def["is_stackable"] = false
	if not effect_def.has("max_stacks"):
		effect_def["max_stacks"] = 1
	if not effect_def.has("stack_mode"):
		effect_def["stack_mode"] = "refresh"

	effect_def["modifiers"] = modifiers

	var effect := GameplayEffect.new()
	effect.configure(effect_def)
	return effect


func _compute_activation_effect(skill_id: String) -> GameplayEffect:
	var level: int = get_skill_level(skill_id)
	if level <= 0:
		return null

	var skill: Dictionary = _skills.get(skill_id, {})
	if skill.is_empty():
		return null

	var activation: Dictionary = skill.get("activation", {})
	var mode: String = str(activation.get("mode", ACTIVATION_MODE_PASSIVE))
	if mode == ACTIVATION_MODE_PASSIVE:
		return null

	var config: Dictionary = (activation.get("effect", {}) as Dictionary).duplicate(true)
	var modifiers: Dictionary = _build_modifiers_from_config(config, level)
	if modifiers.is_empty():
		return null

	var effect_def: Dictionary = config.duplicate(true)
	effect_def["id"] = "skill_activation_%s" % skill_id
	effect_def["source_type"] = "skill_activation"
	effect_def["source_id"] = skill_id
	if not effect_def.has("category"):
		effect_def["category"] = "skill_activation"
	if not effect_def.has("is_stackable"):
		effect_def["is_stackable"] = false
	if not effect_def.has("max_stacks"):
		effect_def["max_stacks"] = 1
	if not effect_def.has("stack_mode"):
		effect_def["stack_mode"] = "refresh"
	if mode == ACTIVATION_MODE_TOGGLE and not effect_def.has("is_infinite"):
		effect_def["is_infinite"] = true

	effect_def["modifiers"] = modifiers

	var effect := GameplayEffect.new()
	effect.configure(effect_def)
	return effect


func _build_modifiers_from_config(config: Dictionary, level: int) -> Dictionary:
	var result: Dictionary = {}
	var raw: Variant = config.get("modifiers", config.get("stat_modifiers", {}))
	if not (raw is Dictionary):
		return result

	for key_variant in raw.keys():
		var key: String = str(key_variant)
		var value: Variant = raw.get(key_variant)
		if value is Dictionary:
			var value_dict: Dictionary = value
			var base_value: float = float(value_dict.get("base", 0.0))
			var per_level: float = float(value_dict.get("per_level", 0.0))
			var max_value: float = float(value_dict.get("max_value", 0.0))
			var computed: float = base_value + per_level * float(level)
			if max_value > 0.0:
				computed = minf(computed, max_value)
			result[key] = computed
		elif value is int or value is float:
			result[key] = float(value)
	return result


func _recalculate_total_effects() -> void:
	_total_effects.clear()
	for effect in _active_effects.values():
		_accumulate_effect_modifiers(effect)
	for effect in _toggle_effects.values():
		_accumulate_effect_modifiers(effect)


func _accumulate_effect_modifiers(effect: Variant) -> void:
	if effect is GameplayEffect:
		var modifiers: Dictionary = (effect as GameplayEffect).get_modifiers()
		for key_variant in modifiers.keys():
			var key: String = str(key_variant)
			var value: Variant = modifiers.get(key_variant, 0)
			if value is int or value is float:
				var current: float = float(_total_effects.get(key, 0.0))
				_total_effects[key] = current + float(value)
	elif effect is Dictionary:
		var dictionary: Dictionary = effect
		for key_variant in dictionary.keys():
			var key: String = str(key_variant)
			var value: Variant = dictionary.get(key_variant, 0)
			if value is int or value is float:
				var current: float = float(_total_effects.get(key, 0.0))
				_total_effects[key] = current + float(value)


func _remove_all_skill_effects_from_system() -> void:
	if _effect_system == null:
		return
	for effect in _active_effects.values():
		if effect is GameplayEffect:
			_effect_system.remove_effect((effect as GameplayEffect).id, PLAYER_ENTITY_ID)


func _remove_all_toggle_effects_from_system() -> void:
	if _effect_system == null:
		return
	for effect in _toggle_effects.values():
		if effect is GameplayEffect:
			_effect_system.remove_effect((effect as GameplayEffect).id, PLAYER_ENTITY_ID)


func _start_targeted_skill_activation(skill_id: String, slot_index: int) -> Dictionary:
	if AbilityTargetingSystem == null or not AbilityTargetingSystem.has_method("begin_skill_targeting"):
		return {"success": false, "reason": "AbilityTargetingSystem unavailable", "skill_id": skill_id}

	var skill_definition: Dictionary = get_skill_definition(skill_id)
	if skill_definition.is_empty():
		return {"success": false, "reason": "技能不存在", "skill_id": skill_id}

	var handler: TargetSkillBase = _create_targeted_skill_handler(skill_id, skill_definition)
	if handler == null:
		return {"success": false, "reason": "目标处理器创建失败", "skill_id": skill_id}

	var context: Dictionary = _build_targeted_skill_context(skill_id, slot_index, handler)
	var session_result: Dictionary = AbilityTargetingSystem.begin_skill_targeting(skill_id, handler, context)
	if not bool(session_result.get("success", false)):
		return session_result

	_targeted_skill_sessions[skill_id] = {
		"handler": handler,
		"context": context.duplicate(true)
	}
	skill_targeting_started.emit(skill_id, session_result.get("session", {}))
	return {
		"success": true,
		"skill_id": skill_id,
		"mode": ACTIVATION_MODE_ACTIVE,
		"state": "targeting_started",
		"session": session_result.get("session", {})
	}


func _build_targeted_skill_context(skill_id: String, slot_index: int, handler: TargetSkillBase) -> Dictionary:
	var caster: Node = _resolve_player_actor()
	return {
		"caster": caster,
		"skill_id": skill_id,
		"slot_index": slot_index,
		"activation_action": str(InputActions.get_hotbar_action_for_slot(slot_index)),
		"scene_root": _resolve_player_scene_root(caster),
		"handler": handler
	}


func _create_targeted_skill_handler(skill_id: String, skill_definition: Dictionary) -> TargetSkillBase:
	var activation: Dictionary = skill_definition.get("activation", {})
	var targeting: Dictionary = activation.get("targeting", {})
	var handler_script_path: String = str(targeting.get("handler_script", ""))
	var handler: TargetSkillBase = null
	if not handler_script_path.is_empty() and ResourceLoader.exists(handler_script_path):
		var loaded_script: Variant = load(handler_script_path)
		if loaded_script != null and loaded_script.has_method("new"):
			var scripted_handler: Variant = loaded_script.new()
			if scripted_handler is TargetSkillBase:
				handler = scripted_handler as TargetSkillBase
	if handler == null:
		handler = TargetSkillBase.new()
	handler.configure_from_skill(skill_id, skill_definition)
	handler.bind_skill_module(self)
	return handler


func _is_targeted_activation(activation: Dictionary) -> bool:
	var targeting: Dictionary = activation.get("targeting", {})
	return bool(targeting.get("enabled", false))


func _activate_active_skill(skill_id: String) -> Dictionary:
	return _apply_active_skill(skill_id)


func _apply_active_skill(skill_id: String) -> Dictionary:
	var effect: GameplayEffect = _compute_activation_effect(skill_id)
	if effect == null:
		return {"success": false, "reason": "技能缺少主动效果配置", "skill_id": skill_id}
	if _effect_system == null:
		return {"success": false, "reason": "EffectSystem unavailable", "skill_id": skill_id}
	if not _effect_system.apply_gameplay_effect(effect, PLAYER_ENTITY_ID):
		return {"success": false, "reason": "主动效果应用失败", "skill_id": skill_id}

	_start_skill_cooldown(skill_id)
	return {
		"success": true,
		"reason": "",
		"skill_id": skill_id,
		"mode": ACTIVATION_MODE_ACTIVE,
		"cooldown": get_skill_cooldown_remaining(skill_id)
	}


func _activate_toggle_skill(skill_id: String) -> Dictionary:
	if is_skill_toggle_active(skill_id):
		_deactivate_toggle_skill(skill_id)
		return {
			"success": true,
			"reason": "",
			"skill_id": skill_id,
			"mode": ACTIVATION_MODE_TOGGLE,
			"active": false
		}

	var effect: GameplayEffect = _compute_activation_effect(skill_id)
	if effect == null:
		return {"success": false, "reason": "技能缺少开启效果配置", "skill_id": skill_id}
	if _effect_system == null:
		return {"success": false, "reason": "EffectSystem unavailable", "skill_id": skill_id}
	if not _effect_system.upsert_gameplay_effect(effect, PLAYER_ENTITY_ID):
		return {"success": false, "reason": "开启效果应用失败", "skill_id": skill_id}

	_toggle_effects[skill_id] = effect
	_active_toggles[skill_id] = true
	_start_skill_cooldown(skill_id)
	_recalculate_total_effects()
	skill_toggle_changed.emit(skill_id, true)
	return {
		"success": true,
		"reason": "",
		"skill_id": skill_id,
		"mode": ACTIVATION_MODE_TOGGLE,
		"active": true,
		"cooldown": get_skill_cooldown_remaining(skill_id)
	}


func _deactivate_toggle_skill(skill_id: String) -> void:
	var effect: Variant = _toggle_effects.get(skill_id, null)
	if effect is GameplayEffect and _effect_system != null:
		_effect_system.remove_effect((effect as GameplayEffect).id, PLAYER_ENTITY_ID)
	_toggle_effects.erase(skill_id)
	if _active_toggles.erase(skill_id):
		skill_toggle_changed.emit(skill_id, false)
	_recalculate_total_effects()


func _restore_toggle_effects() -> void:
	var active_skill_ids: Array = _active_toggles.keys()
	_remove_all_toggle_effects_from_system()
	_toggle_effects.clear()
	for skill_id_variant in active_skill_ids:
		var skill_id: String = str(skill_id_variant)
		if get_skill_level(skill_id) <= 0:
			_active_toggles.erase(skill_id)
			continue
		if str(_get_activation_config(skill_id).get("mode", ACTIVATION_MODE_PASSIVE)) != ACTIVATION_MODE_TOGGLE:
			_active_toggles.erase(skill_id)
			continue
		var effect: GameplayEffect = _compute_activation_effect(skill_id)
		if effect == null:
			_active_toggles.erase(skill_id)
			continue
		_toggle_effects[skill_id] = effect
		if _effect_system != null:
			_effect_system.upsert_gameplay_effect(effect, PLAYER_ENTITY_ID)
	_recalculate_total_effects()


func _start_skill_cooldown(skill_id: String) -> void:
	var activation: Dictionary = _get_activation_config(skill_id)
	var duration: float = maxf(0.0, float(activation.get("cooldown", 0.0)))
	if duration <= 0.0:
		_cooldown_remaining.erase(skill_id)
		return
	_cooldown_remaining[skill_id] = duration


func _tick_activation_cooldowns(delta: float) -> void:
	if _cooldown_remaining.is_empty():
		return

	var keys: Array = _cooldown_remaining.keys()
	for skill_id_variant in keys:
		var skill_id: String = str(skill_id_variant)
		var remaining: float = maxf(0.0, float(_cooldown_remaining.get(skill_id, 0.0)) - delta)
		if remaining <= 0.0:
			_cooldown_remaining.erase(skill_id)
		else:
			_cooldown_remaining[skill_id] = remaining


func _get_activation_config(skill_id: String) -> Dictionary:
	return _skills.get(skill_id, {}).get("activation", {})


func _get_targeted_skill_session(skill_id: String) -> Dictionary:
	var session: Variant = _targeted_skill_sessions.get(skill_id, {})
	if session is Dictionary:
		return (session as Dictionary).duplicate(true)
	return {}


func _resolve_player_actor() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player")


func _resolve_player_scene_root(player_actor: Node) -> Node:
	if player_actor != null and is_instance_valid(player_actor) and player_actor.has_method("get_targeting_scene_root"):
		var result: Variant = player_actor.call("get_targeting_scene_root")
		if result is Node and is_instance_valid(result):
			return result as Node
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.current_scene


func _ensure_hotbar_state() -> void:
	if hotbar_groups.size() != HOTBAR_GROUP_COUNT:
		hotbar_groups.clear()
		for _index in range(HOTBAR_GROUP_COUNT):
			hotbar_groups.append(_create_empty_hotbar_group())
		active_hotbar_group = 0
		return

	for group_index in range(HOTBAR_GROUP_COUNT):
		var group_variant: Variant = hotbar_groups[group_index]
		var normalized_group: Array = _create_empty_hotbar_group()
		if group_variant is Array:
			var group_array: Array = group_variant
			for slot_index in range(mini(group_array.size(), HOTBAR_SLOT_COUNT)):
				normalized_group[slot_index] = _normalize_hotbar_slot_value(group_array[slot_index])
		hotbar_groups[group_index] = normalized_group

	active_hotbar_group = _normalize_group_index(active_hotbar_group)


func _create_empty_hotbar_group() -> Array:
	var group: Array = []
	for _index in range(HOTBAR_SLOT_COUNT):
		group.append("")
	return group


func _normalize_hotbar_slot_value(value: Variant) -> String:
	return str(value).strip_edges() if value != null else ""


func _normalize_group_index(index: int) -> int:
	return posmod(index, HOTBAR_GROUP_COUNT)


func _is_group_index_valid(index: int) -> bool:
	return index >= 0 and index < HOTBAR_GROUP_COUNT


func _is_slot_index_valid(index: int) -> bool:
	return index >= 0 and index < HOTBAR_SLOT_COUNT


func _find_skill_in_group(skill_id: String, group_index: int) -> int:
	if not _is_group_index_valid(group_index):
		return -1
	var slots: Array = hotbar_groups[group_index]
	for slot_index in range(slots.size()):
		if str(slots[slot_index]) == skill_id:
			return slot_index
	return -1


func _emit_hotbar_changed(group_index: int) -> void:
	if not _is_group_index_valid(group_index):
		return
	var slots: Array = (hotbar_groups[group_index] as Array).duplicate()
	hotbar_changed.emit(group_index, slots)


func _purge_invalid_hotbar_assignments() -> void:
	_ensure_hotbar_state()
	for group_index in range(HOTBAR_GROUP_COUNT):
		var changed: bool = false
		var seen_skills: Dictionary = {}
		var slots: Array = hotbar_groups[group_index]
		for slot_index in range(HOTBAR_SLOT_COUNT):
			var skill_id: String = str(slots[slot_index])
			if skill_id.is_empty():
				continue
			if not is_hotbar_eligible(skill_id) or seen_skills.has(skill_id):
				slots[slot_index] = ""
				changed = true
				continue
			seen_skills[skill_id] = true
		if changed:
			_emit_hotbar_changed(group_index)


func _deserialize_hotbar_state(value: Variant) -> void:
	hotbar_groups.clear()
	active_hotbar_group = 0
	if value is Dictionary:
		var hotbar_data: Dictionary = value
		var groups_value: Variant = hotbar_data.get("groups", [])
		if groups_value is Array:
			for group_variant in groups_value:
				hotbar_groups.append(group_variant if group_variant is Array else [])
		active_hotbar_group = int(hotbar_data.get("active_group", 0))
	_ensure_hotbar_state()


func _deserialize_activation_state(value: Variant) -> void:
	_cooldown_remaining.clear()
	_active_toggles.clear()
	if not (value is Dictionary):
		return

	var activation_state: Dictionary = value
	var cooldowns_value: Variant = activation_state.get("cooldowns", {})
	if cooldowns_value is Dictionary:
		var cooldowns_dict: Dictionary = cooldowns_value
		for skill_id_variant in cooldowns_dict.keys():
			var skill_id: String = str(skill_id_variant)
			var remaining: float = maxf(0.0, float(cooldowns_dict.get(skill_id_variant, 0.0)))
			if remaining > 0.0:
				_cooldown_remaining[skill_id] = remaining

	var toggles_value: Variant = activation_state.get("active_toggles", [])
	if toggles_value is Array:
		for skill_id_variant in toggles_value:
			_active_toggles[str(skill_id_variant)] = true


func _get_attribute_value(attribute_name: String) -> int:
	var attribute_system: Node = get_node_or_null("/root/AttributeSystem")
	if attribute_system == null:
		return 0
	var value: Variant = attribute_system.get(attribute_name)
	if value is int:
		return value
	return 0
