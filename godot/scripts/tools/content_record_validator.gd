extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const NarrativeRecordValidator = preload("res://scripts/tools/narrative_record_validator.gd")
const WorldRecordValidator = preload("res://scripts/tools/world_record_validator.gd")

const EDITOR_DOMAINS := ["items", "recipes", "characters", "maps", "dialogues", "quests", "skills", "skill_trees", "settlements", "overworld"]
const EFFECTS_DOMAIN := "json"

var narrative_validator: NarrativeRecordValidator = NarrativeRecordValidator.new()
var world_validator: WorldRecordValidator = WorldRecordValidator.new()


func supports_domain(domain: String) -> bool:
	return EDITOR_DOMAINS.has(domain)


func validate_record(domain: String, id_value: String, registry: ContentRegistry) -> Dictionary:
	var issues: Array[Dictionary] = []
	var record: Dictionary = registry.get_library(domain).get(id_value, {})
	if record.is_empty():
		return {
			"ok": false,
			"status": "not_found",
			"issues": [_issue("error", "$", "not_found", "record not found in domain %s" % domain)],
		}

	match domain:
		"items":
			_validate_item(id_value, record, registry, issues)
		"recipes":
			_validate_recipe(id_value, record, registry, issues)
		"characters":
			_validate_character(id_value, record, registry, issues)
		"maps":
			_validate_map(id_value, record, registry, issues)
		"dialogues", "quests", "skills", "skill_trees":
			narrative_validator.validate_record(domain, id_value, record, registry, issues)
		"settlements", "overworld":
			world_validator.validate_record(domain, id_value, record, registry, issues)
		_:
			issues.append(_issue("warning", "$", "shallow_validation", "record-level validation not implemented for domain %s" % domain))

	return {
		"ok": _error_count(issues) == 0,
		"status": "ok" if _error_count(issues) == 0 else "invalid",
		"issues": issues,
	}


func _validate_item(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("id", ""), id_value, "$.id")
	_expect_non_empty_string(issues, data, "name", "$.name")
	_expect_number_at_least(issues, data, "value", "$.value", 0.0)
	_expect_number_at_least(issues, data, "weight", "$.weight", 0.0)

	var fragments: Array = data.get("fragments", [])
	if not _expect_array(issues, data, "fragments", "$.fragments"):
		return
	var fragment_kinds: Dictionary = {}
	for i in range(fragments.size()):
		var fragment: Dictionary = _dictionary_or_empty(fragments[i])
		var field := "$.fragments[%d]" % i
		var kind := str(fragment.get("kind", ""))
		if kind.is_empty():
			issues.append(_issue("error", field.path_join("kind"), "missing_fragment_kind", "item fragment kind is required"))
			continue
		fragment_kinds[kind] = true
		match kind:
			"stacking":
				_validate_stacking_fragment(fragment, field, issues)
			"usable":
				_validate_effect_list(fragment.get("effect_ids", []), field.path_join("effect_ids"), registry, issues)
			"equip":
				_validate_equip_fragment(fragment, field, registry, issues)
			"weapon":
				_validate_weapon_fragment(fragment, field, registry, issues)
			"crafting":
				_validate_item_entries(fragment.get("deconstruct_yield", []), field.path_join("deconstruct_yield"), registry, issues)
				var crafting_recipe: Dictionary = _dictionary_or_empty(fragment.get("crafting_recipe", {}))
				_validate_item_entries(crafting_recipe.get("materials", []), field.path_join("crafting_recipe.materials"), registry, issues)
			"durability":
				_validate_durability_fragment(fragment, field, registry, issues)
	if not fragment_kinds.has("stacking"):
		issues.append(_issue("warning", "$.fragments", "missing_stacking_fragment", "item has no stacking fragment"))


func _validate_recipe(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("id", ""), id_value, "$.id")
	_expect_non_empty_string(issues, data, "name", "$.name")
	var output: Dictionary = _dictionary_or_empty(data.get("output", {}))
	_validate_item_ref(output.get("item_id", null), "$.output.item_id", registry, issues)
	_expect_number_at_least(issues, output, "count", "$.output.count", 1.0)
	_validate_item_entries(data.get("materials", []), "$.materials", registry, issues)
	_validate_tool_refs(data.get("required_tools", []), "$.required_tools", registry, issues)
	_validate_tool_refs(data.get("optional_tools", []), "$.optional_tools", registry, issues, true)
	_validate_skill_requirements(_dictionary_or_empty(data.get("skill_requirements", {})), "$.skill_requirements", registry, issues)
	_validate_unlock_conditions(data.get("unlock_conditions", []), "$.unlock_conditions", registry, issues)
	_expect_number_at_least(issues, data, "craft_time", "$.craft_time", 0.0)


func _validate_character(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("id", ""), id_value, "$.id")
	_expect_non_empty_string(issues, data, "archetype", "$.archetype")
	var identity: Dictionary = _dictionary_or_empty(data.get("identity", {}))
	_expect_non_empty_string(issues, identity, "display_name", "$.identity.display_name")
	var faction: Dictionary = _dictionary_or_empty(data.get("faction", {}))
	_expect_non_empty_string(issues, faction, "camp_id", "$.faction.camp_id")
	_expect_non_empty_string(issues, faction, "disposition", "$.faction.disposition")
	var combat: Dictionary = _dictionary_or_empty(data.get("combat", {}))
	_expect_non_empty_string(issues, combat, "behavior", "$.combat.behavior")
	_validate_loot_entries(combat.get("loot", []), "$.combat.loot", registry, issues)
	var attributes: Dictionary = _dictionary_or_empty(data.get("attributes", {}))
	var resources: Dictionary = _dictionary_or_empty(attributes.get("resources", {}))
	if resources.has("hp"):
		var hp: Dictionary = _dictionary_or_empty(resources.get("hp", {}))
		_expect_number_at_least(issues, hp, "current", "$.attributes.resources.hp.current", 0.0)
	var life: Dictionary = _dictionary_or_empty(data.get("life", {}))
	if not life.is_empty():
		var settlement_id := str(life.get("settlement_id", ""))
		if not settlement_id.is_empty() and not registry.has_id("settlements", settlement_id):
			issues.append(_issue("error", "$.life.settlement_id", "unknown_settlement", "unknown settlement id %s" % settlement_id))


func _validate_map(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("id", ""), id_value, "$.id")
	_expect_non_empty_string(issues, data, "name", "$.name")
	var size: Dictionary = _dictionary_or_empty(data.get("size", {}))
	var width := int(size.get("width", 0))
	var height := int(size.get("height", 0))
	if width <= 0:
		issues.append(_issue("error", "$.size.width", "invalid_size", "map width must be greater than 0"))
	if height <= 0:
		issues.append(_issue("error", "$.size.height", "invalid_size", "map height must be greater than 0"))

	var level_ids: Dictionary = {}
	for i in range(data.get("levels", []).size()):
		var level: Dictionary = _dictionary_or_empty(data["levels"][i])
		level_ids[ContentRegistry.normalize_content_id(level.get("y", ""))] = true
	if level_ids.is_empty():
		issues.append(_issue("error", "$.levels", "missing_levels", "map must define at least one level"))

	var entry_ids: Dictionary = {}
	for i in range(data.get("entry_points", []).size()):
		var entry: Dictionary = _dictionary_or_empty(data["entry_points"][i])
		var field := "$.entry_points[%d]" % i
		var entry_id := str(entry.get("id", ""))
		if entry_id.is_empty():
			issues.append(_issue("error", field.path_join("id"), "missing_entry_id", "entry point id is required"))
		elif entry_ids.has(entry_id):
			issues.append(_issue("error", field.path_join("id"), "duplicate_entry_id", "duplicate entry point id %s" % entry_id))
		entry_ids[entry_id] = true
		_validate_grid(_dictionary_or_empty(entry.get("grid", {})), field.path_join("grid"), width, height, level_ids, issues)

	var object_ids: Dictionary = {}
	for i in range(data.get("objects", []).size()):
		var object: Dictionary = _dictionary_or_empty(data["objects"][i])
		_validate_map_object(object, i, width, height, level_ids, object_ids, registry, issues)


func _validate_map_object(object: Dictionary, index: int, width: int, height: int, level_ids: Dictionary, object_ids: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var field := "$.objects[%d]" % index
	var object_id := str(object.get("object_id", ""))
	if object_id.is_empty():
		issues.append(_issue("error", field.path_join("object_id"), "missing_object_id", "map object id is required"))
	elif object_ids.has(object_id):
		issues.append(_issue("error", field.path_join("object_id"), "duplicate_object_id", "duplicate object id %s" % object_id))
	object_ids[object_id] = true
	_expect_non_empty_string(issues, object, "kind", field.path_join("kind"))
	_validate_grid(_dictionary_or_empty(object.get("anchor", {})), field.path_join("anchor"), width, height, level_ids, issues)
	var footprint: Dictionary = _dictionary_or_empty(object.get("footprint", {}))
	if not footprint.is_empty():
		_expect_number_at_least(issues, footprint, "width", field.path_join("footprint.width"), 1.0)
		_expect_number_at_least(issues, footprint, "height", field.path_join("footprint.height"), 1.0)

	var props: Dictionary = _dictionary_or_empty(object.get("props", {}))
	var pickup: Dictionary = _dictionary_or_empty(props.get("pickup", {}))
	if not pickup.is_empty():
		_validate_item_ref(pickup.get("item_id", null), field.path_join("props.pickup.item_id"), registry, issues)
		_validate_min_max(pickup, "min_count", "max_count", field.path_join("props.pickup"), issues)
	var container: Dictionary = _dictionary_or_empty(props.get("container", {}))
	if not container.is_empty():
		_validate_item_entries(container.get("initial_inventory", []), field.path_join("props.container.initial_inventory"), registry, issues)
	var ai_spawn: Dictionary = _dictionary_or_empty(props.get("ai_spawn", {}))
	if not ai_spawn.is_empty():
		var character_id := str(ai_spawn.get("character_id", ""))
		if character_id.is_empty() or not registry.has_id("characters", character_id):
			issues.append(_issue("error", field.path_join("props.ai_spawn.character_id"), "unknown_character", "unknown character id %s" % character_id))
	var trigger: Dictionary = _dictionary_or_empty(props.get("trigger", {}))
	if not trigger.is_empty():
		_validate_map_target(trigger.get("target_id", null), field.path_join("props.trigger.target_id"), registry, issues, true)
		for option_index in range(trigger.get("options", []).size()):
			var option: Dictionary = _dictionary_or_empty(trigger["options"][option_index])
			_validate_map_target(option.get("target_id", null), field.path_join("props.trigger.options[%d].target_id" % option_index), registry, issues, false)


func _validate_stacking_fragment(fragment: Dictionary, field: String, issues: Array[Dictionary]) -> void:
	if fragment.has("max_stack"):
		_expect_number_at_least(issues, fragment, "max_stack", field.path_join("max_stack"), 1.0)
	if bool(fragment.get("stackable", false)) and int(fragment.get("max_stack", 0)) <= 1:
		issues.append(_issue("warning", field.path_join("max_stack"), "stackable_single_stack", "stackable item usually needs max_stack greater than 1"))


func _validate_equip_fragment(fragment: Dictionary, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var slots: Array = fragment.get("slots", [])
	if slots.is_empty():
		issues.append(_issue("error", field.path_join("slots"), "missing_equip_slots", "equip fragment must define at least one slot"))
	_validate_effect_list(fragment.get("equip_effect_ids", []), field.path_join("equip_effect_ids"), registry, issues)
	_validate_effect_list(fragment.get("unequip_effect_ids", []), field.path_join("unequip_effect_ids"), registry, issues)


func _validate_weapon_fragment(fragment: Dictionary, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	_expect_number_at_least(issues, fragment, "damage", field.path_join("damage"), 0.0)
	_expect_number_at_least(issues, fragment, "range", field.path_join("range"), 0.0)
	var ammo_type := ContentRegistry.normalize_content_id(fragment.get("ammo_type", ""))
	if not ammo_type.is_empty() and ammo_type != "<null>" and not registry.has_id("items", ammo_type):
		issues.append(_issue("error", field.path_join("ammo_type"), "unknown_item", "unknown ammo item id %s" % ammo_type))
	_validate_effect_list(fragment.get("on_hit_effect_ids", []), field.path_join("on_hit_effect_ids"), registry, issues)


func _validate_durability_fragment(fragment: Dictionary, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	_expect_number_at_least(issues, fragment, "durability", field.path_join("durability"), 0.0)
	_expect_number_at_least(issues, fragment, "max_durability", field.path_join("max_durability"), 1.0)
	if float(fragment.get("durability", 0.0)) > float(fragment.get("max_durability", 0.0)):
		issues.append(_issue("error", field.path_join("durability"), "durability_over_max", "durability cannot exceed max_durability"))
	_validate_item_entries(fragment.get("repair_materials", []), field.path_join("repair_materials"), registry, issues)


func _validate_item_entries(entries: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	if typeof(entries) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of item entries"))
		return
	var values: Array = entries
	for i in range(values.size()):
		var entry: Dictionary = _dictionary_or_empty(values[i])
		var entry_field := field.path_join("[%d]" % i)
		_validate_item_ref(entry.get("item_id", entry.get("id", null)), entry_field.path_join("item_id"), registry, issues)
		_expect_number_at_least(issues, entry, "count", entry_field.path_join("count"), 1.0)


func _validate_loot_entries(entries: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	if typeof(entries) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of loot entries"))
		return
	var values: Array = entries
	for i in range(values.size()):
		var entry: Dictionary = _dictionary_or_empty(values[i])
		var entry_field := field.path_join("[%d]" % i)
		_validate_item_ref(entry.get("item_id", null), entry_field.path_join("item_id"), registry, issues)
		_expect_number_at_least(issues, entry, "chance", entry_field.path_join("chance"), 0.0)
		if float(entry.get("chance", 0.0)) > 1.0:
			issues.append(_issue("error", entry_field.path_join("chance"), "chance_over_one", "loot chance must be <= 1"))
		_validate_min_max(entry, "min", "max", entry_field, issues)


func _validate_tool_refs(values: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary], allow_symbolic: bool = false) -> void:
	if typeof(values) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of tool references"))
		return
	var array: Array = values
	for i in range(array.size()):
		var tool_id := ContentRegistry.normalize_content_id(array[i])
		if allow_symbolic and not tool_id.is_valid_int():
			continue
		if not registry.has_id("items", tool_id):
			issues.append(_issue("error", field.path_join("[%d]" % i), "unknown_tool_item", "unknown tool item id %s" % tool_id))


func _validate_skill_requirements(requirements: Dictionary, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	for skill_id in requirements.keys():
		var normalized := str(skill_id)
		if not registry.has_id("skills", normalized):
			issues.append(_issue("error", field.path_join(normalized), "unknown_skill", "unknown skill id %s" % normalized))
		if float(requirements[skill_id]) < 0.0:
			issues.append(_issue("error", field.path_join(normalized), "negative_skill_level", "skill requirement must be non-negative"))


func _validate_unlock_conditions(values: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	if typeof(values) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of unlock conditions"))
		return
	var array: Array = values
	for i in range(array.size()):
		var condition: Dictionary = _dictionary_or_empty(array[i])
		var condition_field := field.path_join("[%d]" % i)
		match str(condition.get("type", "")):
			"recipe":
				var recipe_id := str(condition.get("id", ""))
				if not registry.has_id("recipes", recipe_id):
					issues.append(_issue("error", condition_field.path_join("id"), "unknown_recipe", "unknown recipe id %s" % recipe_id))
			"skill":
				var skill_id := str(condition.get("id", ""))
				if not registry.has_id("skills", skill_id):
					issues.append(_issue("error", condition_field.path_join("id"), "unknown_skill", "unknown skill id %s" % skill_id))
			"":
				issues.append(_issue("error", condition_field.path_join("type"), "missing_condition_type", "unlock condition type is required"))


func _validate_effect_list(values: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	if typeof(values) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of effect ids"))
		return
	var effects := registry.get_library(EFFECTS_DOMAIN)
	var array: Array = values
	for i in range(array.size()):
		var effect_id := str(array[i])
		if not effects.has(effect_id):
			issues.append(_issue("error", field.path_join("[%d]" % i), "unknown_effect", "unknown effect id %s" % effect_id))


func _validate_item_ref(item_id: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var normalized := ContentRegistry.normalize_content_id(item_id)
	if normalized.is_empty() or normalized == "<null>" or not registry.has_id("items", normalized):
		issues.append(_issue("error", field, "unknown_item", "unknown item id %s" % normalized))


func _validate_map_target(target_id: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary], allow_null: bool) -> void:
	if target_id == null and allow_null:
		return
	var normalized := str(target_id)
	if normalized.is_empty() and allow_null:
		return
	if not registry.has_id("maps", normalized):
		issues.append(_issue("error", field, "unknown_map", "unknown map id %s" % normalized))


func _validate_grid(grid: Dictionary, field: String, width: int, height: int, level_ids: Dictionary, issues: Array[Dictionary]) -> void:
	if grid.is_empty():
		issues.append(_issue("error", field, "missing_grid", "grid coordinate is required"))
		return
	var x := int(grid.get("x", -1))
	var y := int(grid.get("y", 0))
	var z := int(grid.get("z", -1))
	if x < 0 or x >= width:
		issues.append(_issue("error", field.path_join("x"), "grid_out_of_bounds", "x %d outside width %d" % [x, width]))
	if z < 0 or z >= height:
		issues.append(_issue("error", field.path_join("z"), "grid_out_of_bounds", "z %d outside height %d" % [z, height]))
	if not level_ids.has(ContentRegistry.normalize_content_id(y)):
		issues.append(_issue("error", field.path_join("y"), "unknown_level", "y %d does not match a map level" % y))


func _validate_min_max(data: Dictionary, min_field: String, max_field: String, field: String, issues: Array[Dictionary]) -> void:
	_expect_number_at_least(issues, data, min_field, field.path_join(min_field), 0.0)
	_expect_number_at_least(issues, data, max_field, field.path_join(max_field), 0.0)
	if float(data.get(min_field, 0.0)) > float(data.get(max_field, 0.0)):
		issues.append(_issue("error", field.path_join(min_field), "min_greater_than_max", "%s cannot be greater than %s" % [min_field, max_field]))


func _expect_id_matches(issues: Array[Dictionary], value: Variant, expected: String, field: String) -> void:
	if ContentRegistry.normalize_content_id(value) != expected:
		issues.append(_issue("error", field, "id_mismatch", "record id must match requested id %s" % expected))


func _expect_non_empty_string(issues: Array[Dictionary], data: Dictionary, key: String, field: String) -> void:
	if str(data.get(key, "")).strip_edges().is_empty():
		issues.append(_issue("error", field, "missing_text", "%s must be a non-empty string" % key))


func _expect_number_at_least(issues: Array[Dictionary], data: Dictionary, key: String, field: String, minimum: float) -> void:
	if not data.has(key):
		issues.append(_issue("error", field, "missing_number", "%s is required" % key))
		return
	if float(data.get(key, 0.0)) < minimum:
		issues.append(_issue("error", field, "number_too_small", "%s must be >= %.2f" % [key, minimum]))


func _expect_array(issues: Array[Dictionary], data: Dictionary, key: String, field: String) -> bool:
	if typeof(data.get(key, null)) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "%s must be an array" % key))
		return false
	return true


func _error_count(issues: Array[Dictionary]) -> int:
	var count := 0
	for issue in issues:
		var data: Dictionary = _dictionary_or_empty(issue)
		if str(data.get("severity", "")) == "error":
			count += 1
	return count


func _issue(severity: String, field: String, code: String, message: String) -> Dictionary:
	return {
		"severity": severity,
		"field": field,
		"code": code,
		"message": message,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
