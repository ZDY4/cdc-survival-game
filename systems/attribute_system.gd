extends Node
## AttributeSystem - 统一、可扩展、定义驱动的属性服务。

signal attribute_changed(attr_name: String, new_value: Variant, old_value: Variant)
signal attribute_points_changed(available_points: int)
signal calculated_stats_updated(stats: Dictionary)
signal player_attributes_changed(container: Dictionary, snapshot: Dictionary)

const ATTRIBUTE_CATALOG_PATH: String = "res://data/json/attribute_catalog.json"
const ATTRIBUTE_SETS_PATH: String = "res://data/json/attribute_sets.json"
const ATTRIBUTE_RULES_PATH: String = "res://data/json/attribute_rules.json"
const PLAYER_ACTOR_ID: String = "player"

var _definitions: Dictionary = {}
var _player_container: Dictionary = {}
var _actor_source_modifiers: Dictionary = {}
var _cached_player_snapshot: Dictionary = {}
var _needs_player_recalculation: bool = true


func _ready() -> void:
	_definitions = load_definition_bundle()
	if _definitions.is_empty():
		_definitions = _build_fallback_definition_bundle()
	if _player_container.is_empty():
		_player_container = create_player_default_container(_definitions)
	_mark_player_snapshot_dirty()
	_refresh_player_snapshot()
	_emit_available_points_changed()
	print("[AttributeSystem] Unified attribute framework initialized")


static func load_definition_bundle() -> Dictionary:
	var catalog_raw: Variant = _load_json_file(ATTRIBUTE_CATALOG_PATH)
	var sets_raw: Variant = _load_json_file(ATTRIBUTE_SETS_PATH)
	var rules_raw: Variant = _load_json_file(ATTRIBUTE_RULES_PATH)
	if not (catalog_raw is Dictionary) or not (sets_raw is Dictionary) or not (rules_raw is Dictionary):
		return _build_fallback_definition_bundle()

	var catalog_dict: Dictionary = catalog_raw as Dictionary
	var sets_dict: Dictionary = sets_raw as Dictionary
	var rules_dict: Dictionary = rules_raw as Dictionary
	return {
		"catalog": (catalog_dict.get("attributes", {}) as Dictionary).duplicate(true),
		"sets": (sets_dict.get("sets", {}) as Dictionary).duplicate(true),
		"rules": (rules_dict.get("rules", []) as Array).duplicate(true)
	}


static func _load_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed


static func _build_fallback_definition_bundle() -> Dictionary:
	return {
		"catalog": {
			"hp": {
				"display_name": "生命值",
				"type": "int",
				"default": 100,
				"min": 0,
				"max": 9999,
				"visible": true,
				"is_resource": true,
				"is_combat": true,
				"resource_max_key": "max_hp"
			},
			"max_hp": {
				"display_name": "最大生命值",
				"type": "int",
				"default": 100,
				"min": 1,
				"max": 9999,
				"visible": true,
				"is_combat": true
			},
			"attack_power": {
				"display_name": "攻击力",
				"type": "int",
				"default": 5,
				"min": 0,
				"max": 999,
				"visible": true,
				"is_combat": true
			},
			"defense": {
				"display_name": "防御力",
				"type": "int",
				"default": 0,
				"min": 0,
				"max": 999,
				"visible": true,
				"is_combat": true
			},
			"strength": {
				"display_name": "力量",
				"type": "int",
				"default": 5,
				"min": 1,
				"max": 99,
				"visible": true
			},
			"agility": {
				"display_name": "敏捷",
				"type": "int",
				"default": 5,
				"min": 1,
				"max": 99,
				"visible": true
			},
			"constitution": {
				"display_name": "体质",
				"type": "int",
				"default": 5,
				"min": 1,
				"max": 99,
				"visible": true
			},
			"speed": {
				"display_name": "速度",
				"type": "float",
				"default": 5.0,
				"min": 0.0,
				"max": 99.0,
				"visible": true,
				"is_combat": true
			},
			"accuracy": {
				"display_name": "命中",
				"type": "float",
				"default": 70.0,
				"min": 0.0,
				"max": 100.0,
				"visible": true,
				"is_combat": true
			},
			"crit_chance": {
				"display_name": "暴击率",
				"type": "float",
				"default": 0.05,
				"min": 0.0,
				"max": 1.0,
				"visible": true,
				"is_combat": true
			},
			"crit_damage": {
				"display_name": "暴击伤害",
				"type": "float",
				"default": 1.5,
				"min": 1.0,
				"max": 5.0,
				"visible": true,
				"is_combat": true
			},
			"evasion": {
				"display_name": "闪避",
				"type": "float",
				"default": 0.05,
				"min": 0.0,
				"max": 0.95,
				"visible": true,
				"is_combat": true
			},
			"damage_reduction": {
				"display_name": "伤害减免",
				"type": "float",
				"default": 0.0,
				"min": 0.0,
				"max": 0.95,
				"visible": false,
				"is_combat": true
			},
			"carry_weight": {
				"display_name": "负重",
				"type": "float",
				"default": 50.0,
				"min": 0.0,
				"max": 9999.0,
				"visible": false
			},
			"disease_resistance": {
				"display_name": "疾病抗性",
				"type": "float",
				"default": 0.0,
				"min": 0.0,
				"max": 1.0,
				"visible": false
			}
		},
		"sets": {
			"base": {
				"display_name": "基础属性",
				"required": true,
				"attributes": ["strength", "agility", "constitution"]
			},
			"combat": {
				"display_name": "战斗属性",
				"required": false,
				"attributes": [
					"max_hp",
					"attack_power",
					"defense",
					"speed",
					"accuracy",
					"crit_chance",
					"crit_damage",
					"evasion"
				]
			},
			"survival": {
				"display_name": "生存属性",
				"required": false,
				"attributes": ["carry_weight", "disease_resistance"]
			},
			"social": {
				"display_name": "社交属性",
				"required": false,
				"attributes": []
			}
		},
		"rules": [
			{
				"type": "flat_add",
				"source": "constitution",
				"target": "max_hp",
				"scale": 10.0,
				"source_offset": -5.0
			},
			{
				"type": "flat_add",
				"source": "constitution",
				"target": "damage_reduction",
				"scale": 0.01,
				"source_offset": -5.0
			},
			{
				"type": "flat_add",
				"source": "constitution",
				"target": "disease_resistance",
				"scale": 0.05,
				"source_offset": -5.0
			},
			{
				"type": "flat_add",
				"source": "strength",
				"target": "attack_power",
				"scale": 1.0,
				"source_offset": -5.0
			},
			{
				"type": "flat_add",
				"source": "strength",
				"target": "carry_weight",
				"scale": 10.0,
				"source_offset": -5.0
			},
			{
				"type": "flat_add",
				"source": "agility",
				"target": "speed",
				"scale": 0.5,
				"source_offset": -5.0
			},
			{
				"type": "flat_add",
				"source": "agility",
				"target": "crit_chance",
				"scale": 0.01,
				"source_offset": -5.0
			},
			{
				"type": "flat_add",
				"source": "agility",
				"target": "evasion",
				"scale": 0.02,
				"source_offset": -5.0
			},
			{
				"type": "resource_link",
				"resource": "hp",
				"max_attribute": "max_hp",
				"preserve_ratio": true
			},
			{
				"type": "clamp",
				"target": "accuracy",
				"min": 0.0,
				"max": 100.0
			},
			{
				"type": "clamp",
				"target": "crit_chance",
				"min": 0.0,
				"max": 1.0
			},
			{
				"type": "clamp",
				"target": "crit_damage",
				"min": 1.0,
				"max": 5.0
			},
			{
				"type": "clamp",
				"target": "evasion",
				"min": 0.0,
				"max": 0.95
			},
			{
				"type": "clamp",
				"target": "damage_reduction",
				"min": 0.0,
				"max": 0.95
			}
		]
	}


static func get_attribute_catalog(definitions: Dictionary = {}) -> Dictionary:
	return _ensure_definition_bundle(definitions).get("catalog", {})


static func get_attribute_set_definitions(definitions: Dictionary = {}) -> Dictionary:
	return _ensure_definition_bundle(definitions).get("sets", {})


static func get_attribute_rules(definitions: Dictionary = {}) -> Array:
	return _ensure_definition_bundle(definitions).get("rules", [])


static func create_player_default_container(definitions: Dictionary = {}) -> Dictionary:
	return create_default_container(definitions, ["base", "combat"], {"hp": 100})


static func create_default_container(
	definitions: Dictionary = {},
	set_ids: Array = ["base", "combat"],
	resource_overrides: Dictionary = {}
) -> Dictionary:
	var resolved_defs: Dictionary = _ensure_definition_bundle(definitions)
	var catalog: Dictionary = get_attribute_catalog(resolved_defs)
	var set_defs: Dictionary = get_attribute_set_definitions(resolved_defs)
	var result: Dictionary = {
		"sets": {},
		"resources": {}
	}

	for set_id_variant in set_ids:
		var set_id: String = str(set_id_variant)
		var set_def: Dictionary = set_defs.get(set_id, {})
		if set_def.is_empty():
			continue
		var authored_values: Dictionary = {}
		for attribute_key_variant in set_def.get("attributes", []):
			var attribute_key: String = str(attribute_key_variant)
			var catalog_entry: Dictionary = catalog.get(attribute_key, {})
			if catalog_entry.is_empty():
				continue
			authored_values[attribute_key] = _coerce_attribute_value(
				catalog_entry.get("default", 0),
				catalog_entry
			)
		result["sets"][set_id] = authored_values

	for attribute_key in catalog.keys():
		var entry: Dictionary = catalog.get(attribute_key, {})
		if not bool(entry.get("is_resource", false)):
			continue
		var current_value: Variant = resource_overrides.get(attribute_key, entry.get("default", 0))
		result["resources"][attribute_key] = {
			"current": _coerce_attribute_value(current_value, entry)
		}

	return normalize_attribute_container(result, resolved_defs)


static func normalize_attribute_container(raw_value: Variant, definitions: Dictionary = {}) -> Dictionary:
	var resolved_defs: Dictionary = _ensure_definition_bundle(definitions)
	var catalog: Dictionary = get_attribute_catalog(resolved_defs)
	var set_defs: Dictionary = get_attribute_set_definitions(resolved_defs)
	var result: Dictionary = {
		"sets": {},
		"resources": {}
	}

	var source: Dictionary = {}
	if raw_value is Dictionary:
		source = (raw_value as Dictionary).duplicate(true)
	if source.has("attributes") and source.get("attributes") is Dictionary:
		var nested: Dictionary = source.get("attributes", {})
		if nested.has("sets") or nested.has("resources"):
			source = nested

	for set_id in set_defs.keys():
		var set_def: Dictionary = set_defs.get(set_id, {})
		if bool(set_def.get("required", false)):
			result["sets"][set_id] = {}

	var raw_sets: Variant = source.get("sets", {})
	if raw_sets is Dictionary:
		var source_sets: Dictionary = raw_sets
		for set_id_variant in source_sets.keys():
			var set_id: String = str(set_id_variant)
			var authored_values: Variant = source_sets.get(set_id_variant, {})
			if not (authored_values is Dictionary):
				continue
			var normalized_set: Dictionary = {}
			var authored_dict: Dictionary = authored_values
			for attribute_key_variant in authored_dict.keys():
				var attribute_key: String = str(attribute_key_variant)
				var catalog_entry: Dictionary = catalog.get(attribute_key, {})
				if catalog_entry.is_empty():
					continue
				normalized_set[attribute_key] = _coerce_attribute_value(
					authored_dict.get(attribute_key_variant, catalog_entry.get("default", 0)),
					catalog_entry
				)
			if not normalized_set.is_empty() or result["sets"].has(set_id):
				result["sets"][set_id] = normalized_set

	var raw_resources: Variant = source.get("resources", {})
	if raw_resources is Dictionary:
		var source_resources: Dictionary = raw_resources
		for resource_key_variant in source_resources.keys():
			var resource_key: String = str(resource_key_variant)
			var catalog_entry: Dictionary = catalog.get(resource_key, {})
			if catalog_entry.is_empty() or not bool(catalog_entry.get("is_resource", false)):
				continue
			var resource_value: Variant = source_resources.get(resource_key_variant, {})
			if resource_value is Dictionary:
				var resource_dict: Dictionary = resource_value
				result["resources"][resource_key] = {
					"current": _coerce_attribute_value(
						resource_dict.get("current", catalog_entry.get("default", 0)),
						catalog_entry
					)
				}
			else:
				result["resources"][resource_key] = {
					"current": _coerce_attribute_value(resource_value, catalog_entry)
				}

	for resource_key in catalog.keys():
		var entry: Dictionary = catalog.get(resource_key, {})
		if not bool(entry.get("is_resource", false)):
			continue
		if result["resources"].has(resource_key):
			continue
		result["resources"][resource_key] = {
			"current": _coerce_attribute_value(entry.get("default", 0), entry)
		}

	return result


static func resolve_attribute_snapshot(
	container: Dictionary,
	definitions: Dictionary = {},
	modifier_payload: Variant = {}
) -> Dictionary:
	var resolved_defs: Dictionary = _ensure_definition_bundle(definitions)
	var normalized_container: Dictionary = normalize_attribute_container(container, resolved_defs)
	var catalog: Dictionary = get_attribute_catalog(resolved_defs)
	var rules: Array = get_attribute_rules(resolved_defs)
	var snapshot: Dictionary = {}
	var rule_clamps: Array[Dictionary] = []
	var resource_links: Array[Dictionary] = []
	var multiplier_payload: Dictionary = {}

	for attribute_key in catalog.keys():
		var entry: Dictionary = catalog.get(attribute_key, {})
		snapshot[attribute_key] = _coerce_attribute_value(entry.get("default", 0), entry)

	var authored_sets: Dictionary = normalized_container.get("sets", {})
	for set_id_variant in authored_sets.keys():
		var authored_set: Variant = authored_sets.get(set_id_variant, {})
		if not (authored_set is Dictionary):
			continue
		var set_values: Dictionary = authored_set
		for attribute_key_variant in set_values.keys():
			var attribute_key: String = str(attribute_key_variant)
			if not catalog.has(attribute_key):
				continue
			var catalog_entry: Dictionary = catalog.get(attribute_key, {})
			snapshot[attribute_key] = _coerce_attribute_value(
				float(snapshot.get(attribute_key, 0.0)) + float(set_values.get(attribute_key_variant, 0.0)),
				catalog_entry
			)

	for rule_variant in rules:
		if not (rule_variant is Dictionary):
			continue
		var rule: Dictionary = rule_variant
		var rule_type: String = str(rule.get("type", "")).strip_edges()
		match rule_type:
			"flat_add":
				var target_key: String = str(rule.get("target", ""))
				var source_key: String = str(rule.get("source", ""))
				if target_key.is_empty() or source_key.is_empty() or not catalog.has(target_key):
					continue
				var source_value: float = float(snapshot.get(source_key, 0.0))
				var source_offset: float = float(rule.get("source_offset", 0.0))
				var scale: float = float(rule.get("scale", 1.0))
				var catalog_entry: Dictionary = catalog.get(target_key, {})
				snapshot[target_key] = _coerce_attribute_value(
					float(snapshot.get(target_key, 0.0)) + (source_value + source_offset) * scale,
					catalog_entry
				)
			"mult_add":
				var target_mult_key: String = str(rule.get("target", ""))
				var source_mult_key: String = str(rule.get("source", ""))
				if target_mult_key.is_empty() or source_mult_key.is_empty():
					continue
				var mult_value: float = (
					float(snapshot.get(source_mult_key, 0.0)) + float(rule.get("source_offset", 0.0))
				) * float(rule.get("scale", 1.0))
				multiplier_payload[target_mult_key] = float(multiplier_payload.get(target_mult_key, 0.0)) + mult_value
			"clamp":
				rule_clamps.append(rule.duplicate(true))
			"resource_link":
				resource_links.append(rule.duplicate(true))

	var pre_modifier_snapshot: Dictionary = snapshot.duplicate(true)
	var normalized_modifiers: Dictionary = _normalize_modifier_payload(modifier_payload)
	var flat_modifiers: Dictionary = normalized_modifiers.get("flat", {})
	for modifier_key_variant in flat_modifiers.keys():
		var modifier_key: String = str(modifier_key_variant)
		if not catalog.has(modifier_key):
			continue
		var catalog_entry: Dictionary = catalog.get(modifier_key, {})
		snapshot[modifier_key] = _coerce_attribute_value(
			float(snapshot.get(modifier_key, 0.0)) + float(flat_modifiers.get(modifier_key_variant, 0.0)),
			catalog_entry
		)

	var external_mult: Dictionary = normalized_modifiers.get("mult", {})
	for modifier_key_variant in external_mult.keys():
		var modifier_key: String = str(modifier_key_variant)
		multiplier_payload[modifier_key] = float(multiplier_payload.get(modifier_key, 0.0)) + float(external_mult.get(modifier_key_variant, 0.0))

	for modifier_key_variant in multiplier_payload.keys():
		var modifier_key: String = str(modifier_key_variant)
		if not catalog.has(modifier_key):
			continue
		var multiplier: float = 1.0 + float(multiplier_payload.get(modifier_key_variant, 0.0))
		var catalog_entry: Dictionary = catalog.get(modifier_key, {})
		snapshot[modifier_key] = _coerce_attribute_value(
			float(snapshot.get(modifier_key, 0.0)) * multiplier,
			catalog_entry
		)

	for attribute_key in catalog.keys():
		snapshot[attribute_key] = _clamp_attribute_value(snapshot.get(attribute_key, 0), catalog.get(attribute_key, {}))
	for clamp_rule in rule_clamps:
		var target_key: String = str(clamp_rule.get("target", ""))
		if not snapshot.has(target_key):
			continue
		snapshot[target_key] = clampf(
			float(snapshot.get(target_key, 0.0)),
			float(clamp_rule.get("min", snapshot.get(target_key, 0.0))),
			float(clamp_rule.get("max", snapshot.get(target_key, 0.0)))
		)
		snapshot[target_key] = _coerce_attribute_value(snapshot[target_key], catalog.get(target_key, {}))

	var resource_state: Dictionary = {}
	var raw_resources: Dictionary = normalized_container.get("resources", {})
	for resource_key in catalog.keys():
		var catalog_entry: Dictionary = catalog.get(resource_key, {})
		if not bool(catalog_entry.get("is_resource", false)):
			continue
		var current_value: float = float((raw_resources.get(resource_key, {}) as Dictionary).get("current", snapshot.get(resource_key, 0.0)))
		var max_key: String = str(catalog_entry.get("resource_max_key", ""))
		var preserve_ratio: bool = true
		for resource_link in resource_links:
			if str(resource_link.get("resource", "")) != resource_key:
				continue
			max_key = str(resource_link.get("max_attribute", max_key))
			preserve_ratio = bool(resource_link.get("preserve_ratio", true))
			break
		var final_max: float = float(snapshot.get(max_key, current_value)) if not max_key.is_empty() else float(snapshot.get(resource_key, current_value))
		var old_max: float = final_max
		if not max_key.is_empty():
			old_max = float(pre_modifier_snapshot.get(max_key, final_max))
		if preserve_ratio and old_max > 0.0 and final_max >= 0.0:
			current_value = current_value / old_max * final_max
		var min_value: float = float(catalog_entry.get("min", 0.0))
		current_value = clampf(current_value, min_value, final_max if final_max >= min_value else min_value)
		var coerced_current: Variant = _coerce_attribute_value(current_value, catalog_entry)
		snapshot[resource_key] = coerced_current
		resource_state[resource_key] = {
			"current": coerced_current,
			"max": _coerce_attribute_value(final_max, catalog.get(max_key, catalog_entry))
		}

	snapshot["resources"] = resource_state
	return snapshot


static func validate_attribute_container(container: Dictionary, definitions: Dictionary = {}) -> Array[String]:
	var resolved_defs: Dictionary = _ensure_definition_bundle(definitions)
	var catalog: Dictionary = get_attribute_catalog(resolved_defs)
	var set_defs: Dictionary = get_attribute_set_definitions(resolved_defs)
	var errors: Array[String] = []

	var source: Dictionary = container
	if container.has("attributes") and container.get("attributes") is Dictionary:
		source = container.get("attributes", {})

	var raw_sets: Variant = source.get("sets", {})
	if raw_sets is Dictionary:
		var sets_dict: Dictionary = raw_sets
		for set_id_variant in sets_dict.keys():
			var set_id: String = str(set_id_variant)
			var set_values: Variant = sets_dict.get(set_id_variant, {})
			if not set_defs.has(set_id):
				errors.append("未知属性集: %s" % set_id)
				continue
			if not (set_values is Dictionary):
				errors.append("属性集 %s 必须是 Dictionary" % set_id)
				continue
			for attribute_key_variant in (set_values as Dictionary).keys():
				var attribute_key: String = str(attribute_key_variant)
				if not catalog.has(attribute_key):
					errors.append("未知属性键: %s" % attribute_key)
					continue
				var catalog_entry: Dictionary = catalog.get(attribute_key, {})
				var value: Variant = (set_values as Dictionary).get(attribute_key_variant)
				var clamped_value: Variant = _clamp_attribute_value(value, catalog_entry)
				if str(value) != str(clamped_value):
					errors.append("属性 %s 超出范围" % attribute_key)

	for set_id in set_defs.keys():
		var set_def: Dictionary = set_defs.get(set_id, {})
		if bool(set_def.get("required", false)):
			if not (raw_sets is Dictionary) or not (raw_sets as Dictionary).has(set_id):
				errors.append("缺少必选属性集: %s" % set_id)

	var preview: Dictionary = resolve_attribute_snapshot(source, resolved_defs)
	for resource_key_variant in preview.get("resources", {}).keys():
		var resource_key: String = str(resource_key_variant)
		var resource_state: Dictionary = preview.get("resources", {}).get(resource_key, {})
		if float(resource_state.get("current", 0.0)) > float(resource_state.get("max", 0.0)):
			errors.append("资源 %s 超出上限" % resource_key)

	return errors


func get_definitions() -> Dictionary:
	return _definitions.duplicate(true)


func get_player_attributes_container() -> Dictionary:
	return _player_container.duplicate(true)


func set_player_attributes_container(container: Dictionary) -> void:
	_player_container = normalize_attribute_container(container, _definitions)
	_mark_player_snapshot_dirty()
	_refresh_player_snapshot()


func reset_player_attributes() -> void:
	_player_container = create_player_default_container(_definitions)
	_actor_source_modifiers.erase(PLAYER_ACTOR_ID)
	_mark_player_snapshot_dirty()
	_refresh_player_snapshot()


func get_available_points() -> int:
	var xp_system := get_node_or_null("/root/ExperienceSystem")
	if xp_system == null or not xp_system.has_method("get_available_points"):
		return 0
	var points: Variant = xp_system.get_available_points()
	if points is Dictionary:
		return int((points as Dictionary).get("stat_points", 0))
	return 0


func get_actor_attribute(actor_or_id: Variant, key: String) -> Variant:
	var snapshot: Dictionary = get_actor_attributes_snapshot(actor_or_id)
	if snapshot.has(key):
		return snapshot.get(key)
	return 0


func get_actor_attributes_snapshot(actor_or_id: Variant) -> Dictionary:
	if _is_player_actor_ref(actor_or_id):
		if _needs_player_recalculation:
			_refresh_player_snapshot()
		return _cached_player_snapshot.duplicate(true)

	var container: Dictionary = _resolve_actor_container(actor_or_id)
	if container.is_empty():
		return {}
	var modifier_payload: Dictionary = _collect_modifier_payload_for_actor(actor_or_id)
	return resolve_attribute_snapshot(container, _definitions, modifier_payload)


func apply_actor_attribute_delta(actor_or_id: Variant, source: String, values: Variant) -> bool:
	var actor_key: String = _resolve_actor_key(actor_or_id)
	if actor_key.is_empty() or source.is_empty():
		return false
	if not _actor_source_modifiers.has(actor_key):
		_actor_source_modifiers[actor_key] = {}
	(_actor_source_modifiers[actor_key] as Dictionary)[source] = _normalize_modifier_payload(values)
	if actor_key == PLAYER_ACTOR_ID:
		_mark_player_snapshot_dirty()
		_refresh_player_snapshot()
	return true


func clear_actor_attribute_delta(actor_or_id: Variant, source: String) -> void:
	var actor_key: String = _resolve_actor_key(actor_or_id)
	if actor_key.is_empty() or not _actor_source_modifiers.has(actor_key):
		return
	(_actor_source_modifiers[actor_key] as Dictionary).erase(source)
	if actor_key == PLAYER_ACTOR_ID:
		_mark_player_snapshot_dirty()
		_refresh_player_snapshot()


func allocate_player_attributes(delta_map: Dictionary) -> Dictionary:
	var xp_system := get_node_or_null("/root/ExperienceSystem")
	if xp_system == null:
		return {"success": false, "reason": "experience_system_missing"}

	var catalog: Dictionary = get_attribute_catalog(_definitions)
	var current_container: Dictionary = get_player_attributes_container()
	var next_container: Dictionary = current_container.duplicate(true)
	var total_cost: int = 0

	for attribute_key_variant in delta_map.keys():
		var attribute_key: String = str(attribute_key_variant)
		var delta: int = int(delta_map.get(attribute_key_variant, 0))
		if delta <= 0:
			continue
		if not catalog.has(attribute_key):
			return {"success": false, "reason": "unknown_attribute:%s" % attribute_key}
		var set_id: String = _find_primary_set_for_attribute(attribute_key)
		if set_id.is_empty():
			return {"success": false, "reason": "unmapped_attribute:%s" % attribute_key}
		if not next_container["sets"].has(set_id):
			next_container["sets"][set_id] = {}
		var authored_set: Dictionary = next_container["sets"].get(set_id, {}).duplicate(true)
		var current_value: int = int(authored_set.get(attribute_key, catalog.get(attribute_key, {}).get("default", 0)))
		var next_value: int = current_value + delta
		var clamped_value: int = int(_clamp_attribute_value(next_value, catalog.get(attribute_key, {})))
		if clamped_value != next_value:
			return {"success": false, "reason": "attribute_out_of_range:%s" % attribute_key}
		authored_set[attribute_key] = next_value
		next_container["sets"][set_id] = authored_set
		total_cost += delta

	if total_cost <= 0:
		return {"success": false, "reason": "empty_delta"}
	if not xp_system.has_method("spend_stat_points") or not xp_system.spend_stat_points(total_cost):
		return {"success": false, "reason": "insufficient_points"}

	set_player_attributes_container(next_container)
	_emit_available_points_changed()
	return {
		"success": true,
		"spent": total_cost,
		"snapshot": get_actor_attributes_snapshot(PLAYER_ACTOR_ID)
	}


func get_player_resource_current(resource_key: String) -> float:
	var resources: Dictionary = _player_container.get("resources", {})
	if resources.get(resource_key, {}) is Dictionary:
		return float((resources.get(resource_key, {}) as Dictionary).get("current", 0.0))
	return 0.0


func set_player_resource_current(resource_key: String, value: Variant) -> void:
	var catalog_entry: Dictionary = get_attribute_catalog(_definitions).get(resource_key, {})
	if catalog_entry.is_empty() or not bool(catalog_entry.get("is_resource", false)):
		return
	var snapshot: Dictionary = get_actor_attributes_snapshot(PLAYER_ACTOR_ID)
	var max_key: String = str(catalog_entry.get("resource_max_key", ""))
	var max_value: float = float(snapshot.get(max_key, value))
	var clamped_value: float = clampf(float(value), float(catalog_entry.get("min", 0.0)), max_value)
	if not _player_container["resources"].has(resource_key):
		_player_container["resources"][resource_key] = {}
	_player_container["resources"][resource_key]["current"] = _coerce_attribute_value(clamped_value, catalog_entry)
	_mark_player_snapshot_dirty()
	_refresh_player_snapshot()


func serialize() -> Dictionary:
	return {
		"player_attributes": get_player_attributes_container()
	}


func deserialize(data: Dictionary) -> void:
	set_player_attributes_container(data.get("player_attributes", {}))
	_emit_available_points_changed()


func _refresh_player_snapshot() -> void:
	var previous_snapshot: Dictionary = _cached_player_snapshot.duplicate(true)
	_cached_player_snapshot = resolve_attribute_snapshot(
		_player_container,
		_definitions,
		_collect_modifier_payload_for_actor(PLAYER_ACTOR_ID)
	)
	_needs_player_recalculation = false
	for attr_name_variant in _cached_player_snapshot.keys():
		var attr_name: String = str(attr_name_variant)
		if attr_name == "resources":
			continue
		var new_value: Variant = _cached_player_snapshot.get(attr_name_variant)
		var old_value: Variant = previous_snapshot.get(attr_name_variant, null)
		if old_value != new_value:
			attribute_changed.emit(attr_name, new_value, old_value)
	calculated_stats_updated.emit(_cached_player_snapshot.duplicate(true))
	player_attributes_changed.emit(get_player_attributes_container(), _cached_player_snapshot.duplicate(true))


func _mark_player_snapshot_dirty() -> void:
	_needs_player_recalculation = true


func _emit_available_points_changed() -> void:
	attribute_points_changed.emit(get_available_points())


func _collect_modifier_payload_for_actor(actor_or_id: Variant) -> Dictionary:
	var actor_key: String = _resolve_actor_key(actor_or_id)
	var merged: Dictionary = {
		"flat": {},
		"mult": {},
		"resources": {}
	}

	if _actor_source_modifiers.has(actor_key):
		var sources: Dictionary = _actor_source_modifiers.get(actor_key, {})
		for source_key_variant in sources.keys():
			var payload: Dictionary = _normalize_modifier_payload(sources.get(source_key_variant, {}))
			_merge_modifier_payload(merged, payload)

	if actor_key == PLAYER_ACTOR_ID:
		_merge_modifier_payload(merged, _build_player_runtime_modifiers())
	else:
		_merge_modifier_payload(merged, _build_non_player_runtime_modifiers(actor_or_id))

	return merged


func _build_player_runtime_modifiers() -> Dictionary:
	var payload: Dictionary = {
		"flat": {},
		"mult": {},
		"resources": {}
	}
	var equipment_system = GameState.get_equipment_system() if GameState else null
	if equipment_system and equipment_system.has_method("get_attribute_modifier_payload"):
		var equipment_payload: Variant = equipment_system.get_attribute_modifier_payload()
		_merge_modifier_payload(payload, _normalize_modifier_payload(equipment_payload))

	var effect_system := get_node_or_null("/root/EffectSystem")
	if effect_system != null and effect_system.has_method("get_total_modifiers"):
		var effect_modifiers: Variant = effect_system.get_total_modifiers(PLAYER_ACTOR_ID)
		_merge_modifier_payload(payload, _map_effect_modifiers_to_attribute_payload(effect_modifiers))

	return payload


func _build_non_player_runtime_modifiers(actor_or_id: Variant) -> Dictionary:
	var payload: Dictionary = {
		"flat": {},
		"mult": {},
		"resources": {}
	}
	if actor_or_id is Node:
		var actor: Node = actor_or_id
		if actor.has_method("get_equipment_component"):
			var equipment_component: Variant = actor.get_equipment_component()
			if equipment_component is Node and (equipment_component as Node).has_method("get_attribute_modifier_payload"):
				_merge_modifier_payload(
					payload,
					_normalize_modifier_payload((equipment_component as Node).get_attribute_modifier_payload())
				)
		var runtime = actor.get_node_or_null("CharacterSkillRuntime")
		if runtime != null and runtime.has_method("get_total_modifiers"):
			var effect_modifiers: Variant = runtime.get_total_modifiers()
			_merge_modifier_payload(payload, _map_effect_modifiers_to_attribute_payload(effect_modifiers))
	return payload


func _resolve_actor_container(actor_or_id: Variant) -> Dictionary:
	if _is_player_actor_ref(actor_or_id):
		return get_player_attributes_container()

	if actor_or_id is Node:
		var actor: Node = actor_or_id
		if actor.has_meta("attribute_container"):
			var raw_container: Variant = actor.get_meta("attribute_container")
			if raw_container is Dictionary:
				return normalize_attribute_container(raw_container, _definitions)
		if actor.has_meta("character_data"):
			var character_data: Variant = actor.get_meta("character_data")
			if character_data is Dictionary and (character_data as Dictionary).has("attributes"):
				return normalize_attribute_container((character_data as Dictionary).get("attributes", {}), _definitions)
		if actor.has_meta("character_id"):
			var character_id: String = str(actor.get_meta("character_id", ""))
			return _load_character_attributes(character_id)

	if actor_or_id is Dictionary:
		var source: Dictionary = actor_or_id
		if source.has("attributes"):
			return normalize_attribute_container(source.get("attributes", {}), _definitions)
		if source.has("sets") or source.has("resources"):
			return normalize_attribute_container(source, _definitions)

	if actor_or_id is String:
		return _load_character_attributes(str(actor_or_id))

	return {}


func _load_character_attributes(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	var data_manager := get_node_or_null("/root/DataManager")
	if data_manager == null or not data_manager.has_method("get_character"):
		return {}
	var character_data: Variant = data_manager.get_character(character_id)
	if not (character_data is Dictionary) or not (character_data as Dictionary).has("attributes"):
		return {}
	return normalize_attribute_container((character_data as Dictionary).get("attributes", {}), _definitions)


func _resolve_actor_key(actor_or_id: Variant) -> String:
	if _is_player_actor_ref(actor_or_id):
		return PLAYER_ACTOR_ID
	if actor_or_id is Node:
		var actor_node: Node = actor_or_id as Node
		if actor_node.has_method("get_actor_id"):
			var actor_id: String = str(actor_node.get_actor_id()).strip_edges()
			if not actor_id.is_empty():
				return "actor:%s" % actor_id
		if actor_node.has_meta("actor_id"):
			var meta_actor_id: String = str(actor_node.get_meta("actor_id", "")).strip_edges()
			if not meta_actor_id.is_empty():
				return "actor:%s" % meta_actor_id
		if actor_node.has_meta("character_id"):
			var character_id: String = str(actor_node.get_meta("character_id", "")).strip_edges()
			if not character_id.is_empty():
				return "character:%s" % character_id
		return "actor:%s" % str(actor_node.get_instance_id())
	if actor_or_id is Dictionary:
		var payload: Dictionary = actor_or_id
		var dict_id: String = str(payload.get("id", payload.get("character_id", "")))
		if not dict_id.is_empty():
			return "character:%s" % dict_id
	if actor_or_id is String:
		var key: String = str(actor_or_id).strip_edges()
		if key.is_empty():
			return ""
		return "character:%s" % key
	return ""


func _is_player_actor_ref(actor_or_id: Variant) -> bool:
	if actor_or_id == null:
		return true
	if actor_or_id is String:
		return str(actor_or_id).strip_edges().is_empty() or str(actor_or_id) == PLAYER_ACTOR_ID
	if actor_or_id is Node:
		return (actor_or_id as Node).is_in_group("player")
	return false


func _find_primary_set_for_attribute(attribute_key: String) -> String:
	var set_defs: Dictionary = get_attribute_set_definitions(_definitions)
	for set_id in set_defs.keys():
		var set_def: Dictionary = set_defs.get(set_id, {})
		var attributes: Array = set_def.get("attributes", [])
		if attributes.has(attribute_key):
			return str(set_id)
	return ""


func _map_effect_modifiers_to_attribute_payload(modifiers_value: Variant) -> Dictionary:
	var payload: Dictionary = {
		"flat": {},
		"mult": {},
		"resources": {}
	}
	if not (modifiers_value is Dictionary):
		return payload

	var modifiers: Dictionary = modifiers_value
	for modifier_key_variant in modifiers.keys():
		var modifier_key: String = str(modifier_key_variant)
		var numeric_value: float = float(modifiers.get(modifier_key_variant, 0.0))
		match modifier_key:
			"damage_bonus":
				payload["mult"]["attack_power"] = float(payload["mult"].get("attack_power", 0.0)) + numeric_value
			"damage":
				payload["flat"]["attack_power"] = float(payload["flat"].get("attack_power", 0.0)) + numeric_value
			"melee_damage":
				payload["mult"]["attack_power"] = float(payload["mult"].get("attack_power", 0.0)) + numeric_value
			"defense":
				payload["flat"]["defense"] = float(payload["flat"].get("defense", 0.0)) + numeric_value
			"damage_reduction":
				payload["flat"]["damage_reduction"] = float(payload["flat"].get("damage_reduction", 0.0)) + numeric_value
			"crit_chance":
				payload["flat"]["crit_chance"] = float(payload["flat"].get("crit_chance", 0.0)) + numeric_value
			"crit_damage":
				payload["flat"]["crit_damage"] = float(payload["flat"].get("crit_damage", 0.0)) + numeric_value
			"accuracy":
				payload["flat"]["accuracy"] = float(payload["flat"].get("accuracy", 0.0)) + numeric_value
			"evasion":
				payload["flat"]["evasion"] = float(payload["flat"].get("evasion", 0.0)) + numeric_value
			"speed":
				payload["flat"]["speed"] = float(payload["flat"].get("speed", 0.0)) + numeric_value
			"speed_mult":
				payload["mult"]["speed"] = float(payload["mult"].get("speed", 0.0)) + numeric_value
			"max_hp":
				payload["flat"]["max_hp"] = float(payload["flat"].get("max_hp", 0.0)) + numeric_value
			"carry_bonus":
				payload["flat"]["carry_weight"] = float(payload["flat"].get("carry_weight", 0.0)) + numeric_value
			"disease_resistance":
				payload["flat"]["disease_resistance"] = float(payload["flat"].get("disease_resistance", 0.0)) + numeric_value
			_:
				payload["flat"][modifier_key] = float(payload["flat"].get(modifier_key, 0.0)) + numeric_value

	return payload


static func _normalize_modifier_payload(modifier_payload: Variant) -> Dictionary:
	var normalized: Dictionary = {
		"flat": {},
		"mult": {},
		"resources": {}
	}
	if not (modifier_payload is Dictionary):
		return normalized
	var payload: Dictionary = modifier_payload
	var has_named_buckets: bool = (
		payload.get("flat") is Dictionary
		or payload.get("mult") is Dictionary
		or payload.get("resources") is Dictionary
	)
	if has_named_buckets:
		normalized["flat"] = (payload.get("flat", {}) as Dictionary).duplicate(true) if payload.get("flat") is Dictionary else {}
		normalized["mult"] = (payload.get("mult", {}) as Dictionary).duplicate(true) if payload.get("mult") is Dictionary else {}
		normalized["resources"] = (payload.get("resources", {}) as Dictionary).duplicate(true) if payload.get("resources") is Dictionary else {}
		return normalized

	for key_variant in payload.keys():
		var key: String = str(key_variant)
		var value: Variant = payload.get(key_variant, 0)
		if value is int or value is float:
			normalized["flat"][key] = float(value)
	return normalized


static func _merge_modifier_payload(target: Dictionary, incoming: Dictionary) -> void:
	for bucket_name in ["flat", "mult", "resources"]:
		if not incoming.has(bucket_name):
			continue
		if not target.has(bucket_name):
			target[bucket_name] = {}
		var target_bucket: Dictionary = target.get(bucket_name, {})
		var incoming_bucket: Variant = incoming.get(bucket_name, {})
		if not (incoming_bucket is Dictionary):
			continue
		for key_variant in (incoming_bucket as Dictionary).keys():
			var key: String = str(key_variant)
			var incoming_value: Variant = (incoming_bucket as Dictionary).get(key_variant)
			if incoming_value is Dictionary:
				var merged_nested: Dictionary = target_bucket.get(key, {})
				merged_nested.merge(incoming_value, true)
				target_bucket[key] = merged_nested
			else:
				target_bucket[key] = float(target_bucket.get(key, 0.0)) + float(incoming_value)
		target[bucket_name] = target_bucket


static func _coerce_attribute_value(value: Variant, catalog_entry: Dictionary) -> Variant:
	var value_type: String = str(catalog_entry.get("type", "float"))
	if value_type == "int":
		return int(round(float(value)))
	return float(value)


static func _clamp_attribute_value(value: Variant, catalog_entry: Dictionary) -> Variant:
	if catalog_entry.is_empty():
		return value
	var min_value: float = float(catalog_entry.get("min", -INF))
	var max_value: float = float(catalog_entry.get("max", INF))
	var clamped: float = clampf(float(value), min_value, max_value)
	return _coerce_attribute_value(clamped, catalog_entry)


static func _ensure_definition_bundle(definitions: Dictionary) -> Dictionary:
	if not definitions.is_empty():
		return definitions
	return load_definition_bundle()
