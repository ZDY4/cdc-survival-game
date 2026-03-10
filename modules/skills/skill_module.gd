extends "res://core/base_module.gd"
## SkillModule - 数据驱动技能系统
## 技能描述目录: res://data/skills/*.json
## 技能树配置目录: res://data/skill_trees/*.json

# 1. Constants
const SKILLS_DATA_DIR: String = "res://data/skills"
const SKILL_TREES_DATA_DIR: String = "res://data/skill_trees"

# 2. Signals
signal skill_learned(skill_id: String)
signal skill_upgraded(skill_id: String, new_level: int)
signal skill_points_changed(amount: int)
signal skill_data_reloaded(skill_count: int, tree_count: int)

# 3. Public variables
var skill_points: int = 0
var learned_skills: Dictionary = {}  # skill_id -> level

# 4. Private variables
var _skills: Dictionary = {}  # skill_id -> skill config
var _skill_trees: Dictionary = {}  # tree_id -> tree config
var _active_effects: Dictionary = {}  # skill_id -> GameplayEffect
var _total_effects: Dictionary = {}  # effect name -> combined number
var _effect_system: Node = null

# 5. Lifecycle
func _ready() -> void:
	super._ready()
	call_deferred("_initialize_skill_framework")


func _initialize_skill_framework() -> void:
	_effect_system = get_node_or_null("/root/EffectSystem")
	reload_skill_data()


# 6. Public methods
func reload_skill_data() -> bool:
	_skills = _load_skills_from_directory(SKILLS_DATA_DIR)
	if _skills.is_empty():
		push_error("[SkillModule] 技能数据加载失败或为空: %s" % SKILLS_DATA_DIR)
		return false

	_skill_trees = _load_skill_trees_from_directory(SKILL_TREES_DATA_DIR)
	_rebuild_all_effects()
	skill_data_reloaded.emit(_skills.size(), _skill_trees.size())
	return true


func reload_skill(skill_id: String) -> bool:
	var path: String = "%s/%s.json" % [SKILLS_DATA_DIR, skill_id]
	var data: Variant = _load_json(path)
	if not (data is Dictionary):
		return false

	_skills[skill_id] = _normalize_skill(skill_id, data as Dictionary)
	_refresh_skill_effect(skill_id)
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
			var prerequisite_name: String = prerequisite.get("name", prerequisite_id)
			return {"can_learn": false, "reason": "需要先学习: %s" % prerequisite_name}

	var requirements: Dictionary = skill.get("attribute_requirements", {})
	for attribute_name in requirements.keys():
		var required_value: int = int(requirements.get(attribute_name, 0))
		var current_value: int = _get_attribute_value(attribute_name)
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
	if not check.get("can_learn", false):
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
	return true


func reset_skills() -> void:
	var refunded_points: int = 0
	for skill_id in learned_skills.keys():
		refunded_points += int(learned_skills.get(skill_id, 0))
	learned_skills.clear()
	_remove_all_skill_effects_from_system()
	_active_effects.clear()
	_total_effects.clear()
	skill_points += refunded_points
	skill_points_changed.emit(skill_points)


func get_skill_level(skill_id: String) -> int:
	return int(learned_skills.get(skill_id, 0))


func get_skill_effect(skill_id: String) -> Dictionary:
	var effect: Variant = _active_effects.get(skill_id, null)
	if effect is GameplayEffect:
		return effect.get_modifiers()
	if effect is Dictionary:
		return effect as Dictionary
	return {}


func get_total_effect(effect_name: String) -> float:
	if _effect_system != null and _effect_system.has_method("get_total_modifiers"):
		var modifiers: Dictionary = _effect_system.get_total_modifiers("player")
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
	result["is_learned"] = result["current_level"] > 0
	result["is_maxed"] = result["current_level"] >= int(base_skill.get("max_level", 1))
	result["can_learn"] = can_learn_skill(skill_id)
	result["active_effect"] = get_skill_effect(skill_id)
	return result


func get_all_skills() -> Dictionary:
	var result: Dictionary = {}
	for skill_id in _skills.keys():
		result[skill_id] = get_skill(skill_id)
	return result


func get_available_skills() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for skill_id in _skills.keys():
		available.append(get_skill(skill_id))
	return available


func get_skill_tree_data() -> Dictionary:
	var trees: Dictionary = {}

	for tree_id in _skill_trees.keys():
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

	# 将未加入技能树的技能也放入对应 tree_id
	for skill_id in _skills.keys():
		var skill: Dictionary = _skills.get(skill_id, {})
		var tree_id: String = skill.get("tree_id", "default")
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


func serialize() -> Dictionary:
	return {
		"skill_points": skill_points,
		"learned_skills": learned_skills.duplicate(true)
	}


func deserialize(data: Dictionary) -> void:
	skill_points = int(data.get("skill_points", 0))
	var loaded_levels: Dictionary = data.get("learned_skills", {})
	learned_skills.clear()
	for skill_id in loaded_levels.keys():
		learned_skills[skill_id] = maxi(0, int(loaded_levels.get(skill_id, 0)))
	_rebuild_all_effects()
	skill_points_changed.emit(skill_points)


# 7. Private methods
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


func _extract_skills(doc: Dictionary) -> Dictionary:
	var raw_skills: Dictionary = doc.get("skills", doc)
	var result: Dictionary = {}
	for skill_id in raw_skills.keys():
		var value: Variant = raw_skills.get(skill_id, {})
		if value is Dictionary:
			result[skill_id] = _normalize_skill(skill_id, value as Dictionary)
	return result


func _extract_trees(doc: Dictionary) -> Dictionary:
	var raw_trees: Dictionary = doc.get("trees", doc)
	var result: Dictionary = {}
	for tree_id in raw_trees.keys():
		var value: Variant = raw_trees.get(tree_id, {})
		if value is Dictionary:
			result[tree_id] = _normalize_tree(tree_id, value as Dictionary)
	return result


func _normalize_skill(skill_id: String, data: Dictionary) -> Dictionary:
	var prerequisites: Array[String] = _normalize_string_array(data.get("prerequisites", []))
	var attribute_requirements: Dictionary = _normalize_int_dictionary(
		data.get("attribute_requirements", {})
	)
	var effect_config: Dictionary = _normalize_effect_config(data)

	return {
		"id": skill_id,
		"name": data.get("name", skill_id),
		"icon": data.get("icon", ""),
		"description": data.get("description", ""),
		"tree_id": data.get("tree_id", "default"),
		"max_level": maxi(1, int(data.get("max_level", 1))),
		"prerequisites": prerequisites,
		"attribute_requirements": attribute_requirements,
		"gameplay_effect": effect_config
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


func _rebuild_all_effects() -> void:
	_remove_all_skill_effects_from_system()
	_active_effects.clear()
	_total_effects.clear()
	for skill_id in _skills.keys():
		_refresh_skill_effect(skill_id)


func _refresh_skill_effect(skill_id: String) -> void:
	var level: int = get_skill_level(skill_id)
	var effect: GameplayEffect = null
	if level > 0:
		effect = _compute_effect(skill_id, level)
	
	var previous: Variant = _active_effects.get(skill_id, null)
	if level <= 0 and previous is GameplayEffect and _effect_system != null:
		_effect_system.remove_effect(previous.id, "player")
	
	_active_effects[skill_id] = effect
	if effect != null and _effect_system != null:
		_effect_system.upsert_gameplay_effect(effect, "player")
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
	effect_def["id"] = "skill_" + skill_id
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


func _recalculate_total_effects() -> void:
	_total_effects.clear()
	for effect in _active_effects.values():
		if effect is GameplayEffect:
			var modifiers: Dictionary = effect.get_modifiers()
			for key in modifiers.keys():
				var value: Variant = modifiers.get(key, 0)
				if value is int or value is float:
					var current: float = float(_total_effects.get(key, 0.0))
					_total_effects[key] = current + float(value)
		elif effect is Dictionary:
			var dictionary: Dictionary = effect
			for key in dictionary.keys():
				var value: Variant = dictionary.get(key, 0)
				if value is int or value is float:
					var current: float = float(_total_effects.get(key, 0.0))
					_total_effects[key] = current + float(value)


func _normalize_effect_config(data: Dictionary) -> Dictionary:
	var config: Dictionary = {}
	var raw: Variant = data.get("gameplay_effect", null)
	if raw is Dictionary:
		config = raw.duplicate(true)
		return config

	# 兼容旧字段：effect_params -> gameplay_effect.modifiers
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


func _build_modifiers_from_config(config: Dictionary, level: int) -> Dictionary:
	var result: Dictionary = {}
	var raw: Variant = config.get("modifiers", config.get("stat_modifiers", {}))
	if not (raw is Dictionary):
		return result

	for key in raw.keys():
		var value: Variant = raw.get(key)
		if value is Dictionary:
			var base_value: float = float(value.get("base", 0.0))
			var per_level: float = float(value.get("per_level", 0.0))
			var max_value: float = float(value.get("max_value", 0.0))
			var computed: float = base_value + per_level * float(level)
			if max_value > 0.0:
				computed = minf(computed, max_value)
			result[key] = computed
		elif value is int or value is float:
			result[key] = float(value)
	return result


func _remove_all_skill_effects_from_system() -> void:
	if _effect_system == null:
		return
	for effect in _active_effects.values():
		if effect is GameplayEffect:
			_effect_system.remove_effect(effect.id, "player")


func _get_attribute_value(attribute_name: String) -> int:
	var attribute_system: Node = get_node_or_null("/root/AttributeSystem")
	if attribute_system == null:
		return 0
	var value: Variant = attribute_system.get(attribute_name)
	if value is int:
		return value
	return 0
