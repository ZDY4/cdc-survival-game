class_name CharacterSkillRuntime
extends Node
## Runtime skill state for non-player actors.

const TargetSkillBaseScript = preload("res://systems/target_skill_base.gd")
const GameplayEffectScript = preload("res://core/gameplay_effect.gd")

const ACTIVATION_MODE_PASSIVE: String = "passive"
const ACTIVATION_MODE_ACTIVE: String = "active"
const ACTIVATION_MODE_TOGGLE: String = "toggle"

var entity_id: String = ""

var _effect_system: Node = null
var _skill_source: Node = null
var _owner_actor: Node = null
var _learned_skill_ids: Array[String] = []
var _active_skill_ids: Array[String] = []
var _cooldown_remaining: Dictionary = {}
var _active_toggle_skills: Dictionary = {}
var _next_active_skill_index: int = 0


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	_clear_all_effects()


func _process(delta: float) -> void:
	if _cooldown_remaining.is_empty():
		return

	var keys: Array = _cooldown_remaining.keys()
	for skill_id_variant in keys:
		var skill_id: String = str(skill_id_variant)
		var remaining: float = maxf(0.0, float(_cooldown_remaining.get(skill_id_variant, 0.0)) - delta)
		if remaining <= 0.0:
			_cooldown_remaining.erase(skill_id)
		else:
			_cooldown_remaining[skill_id] = remaining


func initialize(
	actor: Node,
	spawn_id: String,
	skills_config: Dictionary,
	skill_source: Node,
	effect_system: Node
) -> void:
	_owner_actor = actor
	_effect_system = effect_system
	_skill_source = skill_source
	entity_id = "actor:%s" % spawn_id.strip_edges()
	_learned_skill_ids = _resolve_initial_skills(skills_config)
	_active_skill_ids.clear()
	_cooldown_remaining.clear()
	_active_toggle_skills.clear()
	_next_active_skill_index = 0

	if actor != null:
		actor.set_meta("skill_runtime_entity_id", entity_id)

	for skill_id in _learned_skill_ids:
		var skill_definition: Dictionary = _get_skill_definition(skill_id)
		if skill_definition.is_empty():
			continue
		var activation: Dictionary = _get_activation_config(skill_definition)
		var mode: String = str(activation.get("mode", ACTIVATION_MODE_PASSIVE))
		match mode:
			ACTIVATION_MODE_ACTIVE:
				_active_skill_ids.append(skill_id)
			ACTIVATION_MODE_TOGGLE:
				_activate_toggle_skill(skill_id, true)
			_:
				_apply_passive_skill(skill_id)

	set_process(true)


func get_entity_id() -> String:
	return entity_id


func get_learned_skill_ids() -> Array[String]:
	return _learned_skill_ids.duplicate()


func is_skill_learned(skill_id: String) -> bool:
	return _learned_skill_ids.has(skill_id)


func get_cooldown_remaining(skill_id: String) -> float:
	return maxf(0.0, float(_cooldown_remaining.get(skill_id, 0.0)))


func is_toggle_skill_active(skill_id: String) -> bool:
	return bool(_active_toggle_skills.get(skill_id, false))


func get_total_modifiers() -> Dictionary:
	if _effect_system == null or not _effect_system.has_method("get_total_modifiers"):
		return {}
	return (_effect_system.get_total_modifiers(entity_id) as Dictionary).duplicate(true)


func try_activate_next_active_skill(preferred_cell: Vector3i = Vector3i.ZERO, target_actor: Node = null) -> Dictionary:
	if _active_skill_ids.is_empty():
		return {"success": false, "reason": "no_active_skills"}

	var start_index: int = _next_active_skill_index
	for offset in range(_active_skill_ids.size()):
		var index: int = posmod(start_index + offset, _active_skill_ids.size())
		var skill_id: String = _active_skill_ids[index]
		if get_cooldown_remaining(skill_id) > 0.0:
			continue

		var result: Dictionary = _activate_active_skill(skill_id, {
			"caster": _owner_actor,
			"preferred_cell": preferred_cell,
			"target_actor": target_actor
		})
		if bool(result.get("success", false)):
			_next_active_skill_index = posmod(index + 1, _active_skill_ids.size())
			return result
	return {"success": false, "reason": "all_active_skills_on_cooldown"}


func _resolve_initial_skills(skills_config: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var selected_skill_ids: Dictionary = {}
	var initial_skills_by_tree: Dictionary = {}
	var raw_skills_by_tree: Variant = skills_config.get("initial_skills_by_tree", {})
	if raw_skills_by_tree is Dictionary:
		initial_skills_by_tree = (raw_skills_by_tree as Dictionary).duplicate(true)

	var raw_tree_ids: Variant = skills_config.get("initial_tree_ids", [])
	var tree_ids: Array[String] = _normalize_string_array(raw_tree_ids)
	for tree_id in tree_ids:
		var tree_skill_ids: Array[String] = _normalize_string_array(initial_skills_by_tree.get(tree_id, []))
		for skill_id in tree_skill_ids:
			selected_skill_ids[skill_id] = true

	var seen_skill_ids: Dictionary = {}
	for tree_id in tree_ids:
		var tree_definition: Dictionary = _get_tree_definition(tree_id)
		if tree_definition.is_empty():
			continue
		var tree_skill_ids: Array[String] = _normalize_string_array(tree_definition.get("skills", []))
		var selected_in_tree: Dictionary = {}
		for skill_id in _normalize_string_array(initial_skills_by_tree.get(tree_id, [])):
			selected_in_tree[skill_id] = true

		for skill_id in tree_skill_ids:
			if not selected_in_tree.has(skill_id):
				continue
			if seen_skill_ids.has(skill_id):
				continue
			if not _is_skill_unlock_valid(skill_id, selected_skill_ids, {}):
				continue
			if not _meets_attribute_requirements(skill_id):
				continue
			seen_skill_ids[skill_id] = true
			result.append(skill_id)
	return result


func _is_skill_unlock_valid(skill_id: String, selected_skill_ids: Dictionary, visited: Dictionary) -> bool:
	if visited.has(skill_id):
		return true
	if not selected_skill_ids.has(skill_id):
		return false

	var skill_definition: Dictionary = _get_skill_definition(skill_id)
	if skill_definition.is_empty():
		return false

	visited[skill_id] = true
	for prerequisite_id in _normalize_string_array(skill_definition.get("prerequisites", [])):
		if not selected_skill_ids.has(prerequisite_id):
			return false
		if not _is_skill_unlock_valid(prerequisite_id, selected_skill_ids, visited):
			return false
	return true


func _meets_attribute_requirements(skill_id: String) -> bool:
	var skill_definition: Dictionary = _get_skill_definition(skill_id)
	if skill_definition.is_empty():
		return false
	var requirements: Variant = skill_definition.get("attribute_requirements", {})
	if not (requirements is Dictionary):
		return true
	if AttributeSystem == null or not AttributeSystem.has_method("get_actor_attribute"):
		return true
	for attribute_name_variant in (requirements as Dictionary).keys():
		var attribute_name: String = str(attribute_name_variant)
		var required_value: float = float((requirements as Dictionary).get(attribute_name_variant, 0))
		var current_value: float = float(AttributeSystem.get_actor_attribute(_owner_actor, attribute_name))
		if current_value < required_value:
			return false
	return true


func _apply_passive_skill(skill_id: String) -> void:
	var skill_definition: Dictionary = _get_skill_definition(skill_id)
	if skill_definition.is_empty():
		return

	var effect: GameplayEffect = _build_effect_from_config(
		"character_skill_%s" % skill_id,
		skill_id,
		skill_definition.get("gameplay_effect", {}),
		true
	)
	_upsert_effect(effect)


func _activate_toggle_skill(skill_id: String, activate_on_init: bool = false) -> Dictionary:
	var skill_definition: Dictionary = _get_skill_definition(skill_id)
	if skill_definition.is_empty():
		return {"success": false, "reason": "missing_skill_definition"}
	var activation: Dictionary = _get_activation_config(skill_definition)
	if str(activation.get("mode", ACTIVATION_MODE_PASSIVE)) != ACTIVATION_MODE_TOGGLE:
		return {"success": false, "reason": "not_toggle_skill"}

	var effect: GameplayEffect = _build_effect_from_config(
		"character_skill_toggle_%s" % skill_id,
		skill_id,
		activation.get("effect", {}),
		true
	)
	if effect == null:
		return {"success": false, "reason": "missing_toggle_effect"}
	_upsert_effect(effect)
	_active_toggle_skills[skill_id] = true
	if activate_on_init:
		_start_cooldown(skill_id, activation)
	return {"success": true, "skill_id": skill_id, "mode": ACTIVATION_MODE_TOGGLE, "active": true}


func _activate_active_skill(skill_id: String, context: Dictionary = {}) -> Dictionary:
	var skill_definition: Dictionary = _get_skill_definition(skill_id)
	if skill_definition.is_empty():
		return {"success": false, "reason": "missing_skill_definition"}
	var activation: Dictionary = _get_activation_config(skill_definition)
	if str(activation.get("mode", ACTIVATION_MODE_PASSIVE)) != ACTIVATION_MODE_ACTIVE:
		return {"success": false, "reason": "not_active_skill"}
	if _is_targeted_activation(activation):
		var handler: TargetSkillBase = _create_targeted_skill_handler(skill_id, skill_definition)
		if handler == null:
			return {"success": false, "reason": "missing_target_handler", "skill_id": skill_id}
		var preferred_cell: Vector3i = _resolve_preferred_target_cell(context)
		var selection: Dictionary = handler.auto_select_for_ai(
			context.get("caster", _owner_actor) as Node,
			preferred_cell,
			context
		)
		if not bool(selection.get("success", false)):
			return {
				"success": false,
				"reason": str(selection.get("reason", "invalid_target_preview")),
				"skill_id": skill_id
			}
		return handler.confirm_target(selection.get("preview", {}), context)

	var effect: GameplayEffect = _build_effect_from_config(
		"character_skill_active_%s" % skill_id,
		skill_id,
		activation.get("effect", {}),
		false
	)
	if effect == null:
		return {"success": false, "reason": "missing_active_effect"}
	if _effect_system == null or not _effect_system.has_method("apply_gameplay_effect"):
		return {"success": false, "reason": "effect_system_unavailable"}
	if not _effect_system.apply_gameplay_effect(effect, entity_id):
		return {"success": false, "reason": "effect_apply_failed"}

	_start_cooldown(skill_id, activation)
	return {
		"success": true,
		"skill_id": skill_id,
		"mode": ACTIVATION_MODE_ACTIVE,
		"cooldown": get_cooldown_remaining(skill_id)
	}


func execute_targeted_skill_preview(skill_id: String, preview: Dictionary, context: Dictionary) -> Dictionary:
	var skill_definition: Dictionary = _get_skill_definition(skill_id)
	if skill_definition.is_empty():
		return {"success": false, "reason": "missing_skill_definition", "skill_id": skill_id}
	if get_cooldown_remaining(skill_id) > 0.0:
		return {
			"success": false,
			"reason": "cooldown_active",
			"skill_id": skill_id,
			"cooldown": get_cooldown_remaining(skill_id)
		}

	var activation: Dictionary = _get_activation_config(skill_definition)
	if not _is_targeted_activation(activation):
		return {"success": false, "reason": "not_targeted_skill", "skill_id": skill_id}

	var handler: TargetSkillBase = context.get("handler", null) as TargetSkillBase
	if handler == null:
		handler = _create_targeted_skill_handler(skill_id, skill_definition)
	if handler == null:
		return {"success": false, "reason": "missing_target_handler", "skill_id": skill_id}

	var validation: Dictionary = handler.is_preview_valid(preview, context)
	if not bool(validation.get("valid", false)):
		return {"success": false, "reason": str(validation.get("reason", "invalid_preview")), "skill_id": skill_id}

	var effect: GameplayEffect = _build_effect_from_config(
		"character_skill_active_%s" % skill_id,
		skill_id,
		activation.get("effect", {}),
		false
	)
	if effect == null:
		return {"success": false, "reason": "missing_active_effect", "skill_id": skill_id}
	if _effect_system == null or not _effect_system.has_method("apply_gameplay_effect"):
		return {"success": false, "reason": "effect_system_unavailable", "skill_id": skill_id}
	if not _effect_system.apply_gameplay_effect(effect, entity_id):
		return {"success": false, "reason": "effect_apply_failed", "skill_id": skill_id}

	_start_cooldown(skill_id, activation)
	return {
		"success": true,
		"skill_id": skill_id,
		"mode": ACTIVATION_MODE_ACTIVE,
		"state": "cast_confirmed",
		"cooldown": get_cooldown_remaining(skill_id),
		"preview": preview.duplicate(true)
	}


func _create_targeted_skill_handler(skill_id: String, skill_definition: Dictionary) -> TargetSkillBase:
	var activation: Dictionary = _get_activation_config(skill_definition)
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
		handler = TargetSkillBaseScript.new()
	handler.configure_from_skill(skill_id, skill_definition)
	handler.bind_skill_runtime(self)
	return handler


func _resolve_preferred_target_cell(context: Dictionary) -> Vector3i:
	var preferred: Variant = context.get("preferred_cell", null)
	if preferred is Vector3i:
		return preferred
	var target_actor: Node = context.get("target_actor", null) as Node
	if target_actor != null and is_instance_valid(target_actor) and target_actor is Node3D:
		return GridMovementSystem.world_to_grid((target_actor as Node3D).global_position)
	return Vector3i.ZERO


func _is_targeted_activation(activation: Dictionary) -> bool:
	var targeting: Dictionary = activation.get("targeting", {})
	return bool(targeting.get("enabled", false))


func _build_effect_from_config(
	effect_id: String,
	skill_id: String,
	raw_config: Variant,
	is_infinite_default: bool
) -> GameplayEffect:
	if not (raw_config is Dictionary):
		return null
	var config: Dictionary = (raw_config as Dictionary).duplicate(true)
	var modifiers: Dictionary = _build_modifiers(config)
	if modifiers.is_empty():
		return null

	var effect_definition: Dictionary = config.duplicate(true)
	effect_definition["id"] = effect_id
	effect_definition["source_type"] = "character_skill"
	effect_definition["source_id"] = skill_id
	if not effect_definition.has("category"):
		effect_definition["category"] = "skill"
	if not effect_definition.has("is_stackable"):
		effect_definition["is_stackable"] = false
	if not effect_definition.has("max_stacks"):
		effect_definition["max_stacks"] = 1
	if not effect_definition.has("stack_mode"):
		effect_definition["stack_mode"] = "refresh"
	if not effect_definition.has("is_infinite"):
		effect_definition["is_infinite"] = is_infinite_default
	effect_definition["modifiers"] = modifiers

	var effect := GameplayEffectScript.new()
	effect.configure(effect_definition)
	return effect


func _build_modifiers(config: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var raw_modifiers: Variant = config.get("modifiers", config.get("stat_modifiers", {}))
	if not (raw_modifiers is Dictionary):
		return result

	var source: Dictionary = raw_modifiers
	for modifier_key_variant in source.keys():
		var modifier_key: String = str(modifier_key_variant)
		var modifier_value: Variant = source.get(modifier_key_variant)
		if modifier_value is Dictionary:
			var modifier_dict: Dictionary = modifier_value
			var base_value: float = float(modifier_dict.get("base", 0.0))
			var per_level: float = float(modifier_dict.get("per_level", 0.0))
			var max_value: float = float(modifier_dict.get("max_value", 0.0))
			var computed: float = base_value + per_level
			if max_value > 0.0:
				computed = minf(computed, max_value)
			result[modifier_key] = computed
		elif modifier_value is int or modifier_value is float:
			result[modifier_key] = float(modifier_value)
	return result


func _upsert_effect(effect: GameplayEffect) -> void:
	if effect == null:
		return
	if _effect_system == null or not _effect_system.has_method("upsert_gameplay_effect"):
		return
	_effect_system.upsert_gameplay_effect(effect, entity_id)


func _start_cooldown(skill_id: String, activation: Dictionary) -> void:
	var cooldown: float = maxf(0.0, float(activation.get("cooldown", 0.0)))
	if cooldown <= 0.0:
		_cooldown_remaining.erase(skill_id)
		return
	_cooldown_remaining[skill_id] = cooldown


func _clear_all_effects() -> void:
	if entity_id.is_empty():
		return
	if _effect_system == null or not _effect_system.has_method("remove_effect"):
		return
	_effect_system.remove_effect("", entity_id)


func _get_skill_definition(skill_id: String) -> Dictionary:
	if _skill_source == null or not _skill_source.has_method("get_skill_definition"):
		return {}
	var result: Variant = _skill_source.get_skill_definition(skill_id)
	if result is Dictionary:
		return (result as Dictionary).duplicate(true)
	return {}


func _get_tree_definition(tree_id: String) -> Dictionary:
	if _skill_source == null or not _skill_source.has_method("get_skill_tree_definition"):
		return {}
	var result: Variant = _skill_source.get_skill_tree_definition(tree_id)
	if result is Dictionary:
		return (result as Dictionary).duplicate(true)
	return {}


func _get_activation_config(skill_definition: Dictionary) -> Dictionary:
	var activation: Variant = skill_definition.get("activation", {})
	if activation is Dictionary:
		return (activation as Dictionary).duplicate(true)
	return {}


func _normalize_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			var text: String = str(item).strip_edges()
			if not text.is_empty():
				result.append(text)
	return result
