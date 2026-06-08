extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")

const EFFECTS_DOMAIN := "json"


func supports_domain(domain: String) -> bool:
	return ["items", "recipes", "characters", "maps", "shops", "world_tiles"].has(domain)


func validate_record(domain: String, id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	match domain:
		"items":
			_validate_item(id_value, record, registry, issues)
		"recipes":
			_validate_recipe(id_value, record, registry, issues)
		"characters":
			_validate_character(id_value, record, registry, issues)
		"maps":
			_validate_map(id_value, record, registry, issues)
		"shops":
			_validate_shop(id_value, record, registry, issues)
		"world_tiles":
			_validate_world_tiles(id_value, record, registry, issues)


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
			"appearance":
				_validate_appearance_fragment(fragment, field, issues)
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
	var appearance_profile_id := ContentRegistry.normalize_content_id(data.get("appearance_profile_id", ""))
	if not appearance_profile_id.is_empty() and not registry.has_id("appearance", appearance_profile_id):
		issues.append(_issue("error", "$.appearance_profile_id", "unknown_appearance", "unknown appearance profile id %s" % appearance_profile_id))


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
	var world_tile_index := _world_tile_index(registry)
	var visual: Dictionary = _dictionary_or_empty(props.get("visual", {}))
	if not visual.is_empty():
		_validate_world_tile_id(
			visual.get("prototype_id", ""),
			field.path_join("props.visual.prototype_id"),
			"prototypes",
			"unknown_world_tile_prototype",
			world_tile_index,
			issues
		)
	var building: Dictionary = _dictionary_or_empty(props.get("building", {}))
	var tile_set: Dictionary = _dictionary_or_empty(building.get("tile_set", {}))
	if not tile_set.is_empty():
		_validate_world_tile_id(
			tile_set.get("wall_set_id", ""),
			field.path_join("props.building.tile_set.wall_set_id"),
			"wall_sets",
			"unknown_wall_set",
			world_tile_index,
			issues
		)
		_validate_world_tile_id(
			tile_set.get("floor_surface_set_id", ""),
			field.path_join("props.building.tile_set.floor_surface_set_id"),
			"surface_sets",
			"unknown_surface_set",
			world_tile_index,
			issues
		)
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


func _validate_shop(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("id", ""), id_value, "$.id")
	_expect_number_at_least(issues, data, "money", "$.money", 0.0)
	_expect_number_at_least(issues, data, "buy_price_modifier", "$.buy_price_modifier", 0.0)
	_expect_number_at_least(issues, data, "sell_price_modifier", "$.sell_price_modifier", 0.0)
	_validate_shop_inventory(data.get("inventory", []), "$.inventory", registry, issues)
	var target_actor_definition_id := ContentRegistry.normalize_content_id(data.get("target_actor_definition_id", ""))
	if not target_actor_definition_id.is_empty() and not registry.has_id("characters", target_actor_definition_id):
		issues.append(_issue("error", "$.target_actor_definition_id", "unknown_character", "unknown character id %s" % target_actor_definition_id))
	_validate_string_array(data.get("required_world_flags", []), "$.required_world_flags", "world flag", issues, true)
	_validate_string_array(data.get("blocked_world_flags", []), "$.blocked_world_flags", "world flag", issues, true)
	if data.has("required_relationship_min") and data.has("required_relationship_max"):
		var minimum := float(data.get("required_relationship_min", 0.0))
		var maximum := float(data.get("required_relationship_max", 0.0))
		if minimum > maximum:
			issues.append(_issue("error", "$.required_relationship_min", "invalid_relationship_range", "required_relationship_min must be <= required_relationship_max"))


func _validate_world_tiles(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var prototype_ids := {}
	var prototypes: Array = data.get("prototypes", [])
	if not _expect_array(issues, data, "prototypes", "$.prototypes"):
		return
	if prototypes.is_empty():
		issues.append(_issue("error", "$.prototypes", "missing_prototypes", "world tile catalog must define at least one prototype"))
	for i in range(prototypes.size()):
		var prototype: Dictionary = _dictionary_or_empty(prototypes[i])
		var field := "$.prototypes[%d]" % i
		var prototype_id := ContentRegistry.normalize_content_id(prototype.get("id", ""))
		if prototype_id.is_empty():
			issues.append(_issue("error", field.path_join("id"), "missing_prototype_id", "world tile prototype id is required"))
		elif prototype_ids.has(prototype_id):
			issues.append(_issue("error", field.path_join("id"), "duplicate_prototype_id", "duplicate world tile prototype id %s" % prototype_id))
		prototype_ids[prototype_id] = true
		_validate_world_tile_source(_dictionary_or_empty(prototype.get("source", {})), field.path_join("source"), issues)
		_validate_bounds(_dictionary_or_empty(prototype.get("bounds", {})), field.path_join("bounds"), issues)

	for i in range(data.get("surface_sets", []).size()):
		var surface_set: Dictionary = _dictionary_or_empty(data["surface_sets"][i])
		var field := "$.surface_sets[%d]" % i
		if ContentRegistry.normalize_content_id(surface_set.get("id", "")).is_empty():
			issues.append(_issue("error", field.path_join("id"), "missing_surface_set_id", "surface set id is required"))
		_validate_prototype_ref(surface_set.get("flat_top_prototype_id", ""), field.path_join("flat_top_prototype_id"), prototype_ids, issues, true)
		_validate_prototype_ref(surface_set.get("cliff_inner_corner_prototype_id", ""), field.path_join("cliff_inner_corner_prototype_id"), prototype_ids, issues, true)
		_validate_prototype_ref(surface_set.get("cliff_outer_corner_prototype_id", ""), field.path_join("cliff_outer_corner_prototype_id"), prototype_ids, issues, true)
		_validate_prototype_ref(surface_set.get("cliff_side_prototype_id", ""), field.path_join("cliff_side_prototype_id"), prototype_ids, issues, true)
		var ramp_top_ids: Dictionary = _dictionary_or_empty(surface_set.get("ramp_top_prototype_ids", {}))
		for direction in ramp_top_ids.keys():
			_validate_prototype_ref(ramp_top_ids[direction], field.path_join("ramp_top_prototype_ids.%s" % direction), prototype_ids, issues, false)

	for i in range(data.get("wall_sets", []).size()):
		var wall_set: Dictionary = _dictionary_or_empty(data["wall_sets"][i])
		var field := "$.wall_sets[%d]" % i
		if ContentRegistry.normalize_content_id(wall_set.get("id", "")).is_empty():
			issues.append(_issue("error", field.path_join("id"), "missing_wall_set_id", "wall set id is required"))
		for key in ["isolated_prototype_id", "end_prototype_id", "straight_prototype_id", "corner_prototype_id", "t_junction_prototype_id", "cross_prototype_id"]:
			_validate_prototype_ref(wall_set.get(key, ""), field.path_join(key), prototype_ids, issues, false)


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


func _validate_appearance_fragment(fragment: Dictionary, field: String, issues: Array[Dictionary]) -> void:
	var definition: Dictionary = _dictionary_or_empty(fragment.get("definition", {}))
	if definition.is_empty():
		issues.append(_issue("error", field.path_join("definition"), "missing_appearance_definition", "appearance fragment must define a definition object"))
		return
	var visual_asset := str(definition.get("visual_asset", "")).strip_edges()
	if visual_asset.is_empty():
		issues.append(_issue("error", field.path_join("definition.visual_asset"), "missing_asset", "appearance visual_asset is required"))
	else:
		var resolved_asset := AssetPathResolver.resolve_equipment_visual_asset(visual_asset)
		if not bool(resolved_asset.get("ok", false)):
			issues.append(_issue("error", field.path_join("definition.visual_asset"), str(resolved_asset.get("reason", "unknown_visual_asset")), str(resolved_asset.get("message", "unsupported appearance visual_asset %s" % visual_asset))))
		elif not bool(resolved_asset.get("exists", false)):
			issues.append(_issue("error", field.path_join("definition.visual_asset"), "missing_asset_file", "appearance model asset does not exist: %s" % str(resolved_asset.get("absolute_path", ""))))
	var attach_target := str(definition.get("attach_target", "")).strip_edges()
	if not attach_target.is_empty() and not ["main_hand", "off_hand", "head", "body", "legs", "feet", "hands", "back", "accessory"].has(attach_target):
		issues.append(_issue("warning", field.path_join("definition.attach_target"), "unknown_attach_target", "unknown appearance attach target %s" % attach_target))
	var presentation_mode := str(definition.get("presentation_mode", "")).strip_edges()
	if not presentation_mode.is_empty() and not ["attach", "replace_region"].has(presentation_mode):
		issues.append(_issue("warning", field.path_join("definition.presentation_mode"), "unknown_presentation_mode", "unknown appearance presentation mode %s" % presentation_mode))


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


func _validate_shop_inventory(entries: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	if typeof(entries) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of shop inventory entries"))
		return
	var values: Array = entries
	for i in range(values.size()):
		var entry: Dictionary = _dictionary_or_empty(values[i])
		var entry_field := field.path_join("[%d]" % i)
		_validate_item_ref(entry.get("item_id", entry.get("id", null)), entry_field.path_join("item_id"), registry, issues)
		_expect_number_at_least(issues, entry, "count", entry_field.path_join("count"), 1.0)
		if entry.has("price"):
			_expect_number_at_least(issues, entry, "price", entry_field.path_join("price"), 0.0)


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


func _validate_string_array(values: Variant, field: String, label: String, issues: Array[Dictionary], allow_missing: bool = false) -> void:
	if values == null and allow_missing:
		return
	if typeof(values) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of %s ids" % label))
		return
	var array: Array = values
	for i in range(array.size()):
		if str(array[i]).strip_edges().is_empty():
			issues.append(_issue("error", field.path_join("[%d]" % i), "missing_text", "%s id must be non-empty" % label))


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
				if condition.has("level") and int(condition.get("level", 0)) < 1:
					issues.append(_issue("error", condition_field.path_join("level"), "invalid_skill_level", "skill unlock level must be at least 1"))
				if condition.has("required_level") and int(condition.get("required_level", 0)) < 1:
					issues.append(_issue("error", condition_field.path_join("required_level"), "invalid_skill_level", "skill unlock level must be at least 1"))
			"quest":
				var quest_id := str(condition.get("id", ""))
				if not registry.has_id("quests", quest_id):
					issues.append(_issue("error", condition_field.path_join("id"), "unknown_quest", "unknown quest id %s" % quest_id))
			"item", "book":
				_validate_item_ref(condition.get("id", condition.get("item_id", "")), condition_field.path_join("id"), registry, issues)
			"world_flag", "flag":
				if str(condition.get("id", "")).strip_edges().is_empty():
					issues.append(_issue("error", condition_field.path_join("id"), "missing_world_flag", "world flag id is required"))
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


func _validate_world_tile_source(source: Dictionary, field: String, issues: Array[Dictionary]) -> void:
	if source.is_empty():
		issues.append(_issue("error", field, "missing_source", "world tile prototype source is required"))
		return
	if str(source.get("kind", "")) != "gltf_scene":
		issues.append(_issue("error", field.path_join("kind"), "unsupported_source_kind", "world tile source kind must be gltf_scene"))
	var path := str(source.get("path", "")).strip_edges()
	if path.is_empty():
		issues.append(_issue("error", field.path_join("path"), "missing_asset", "world tile source asset is required"))
	else:
		var resolved_asset := AssetPathResolver.resolve_model_asset(path)
		if not bool(resolved_asset.get("ok", false)):
			issues.append(_issue("error", field.path_join("path"), str(resolved_asset.get("reason", "invalid_asset_path")), str(resolved_asset.get("message", "invalid asset path"))))
		elif not bool(resolved_asset.get("exists", false)):
			issues.append(_issue("error", field.path_join("path"), "missing_asset_file", "asset file does not exist: %s" % str(resolved_asset.get("absolute_path", ""))))
	if source.has("scene_index") and int(source.get("scene_index", 0)) < 0:
		issues.append(_issue("error", field.path_join("scene_index"), "negative_scene_index", "scene_index must be >= 0"))


func _model_asset_for_equipment_visual(visual_asset: String) -> String:
	return AssetPathResolver.relative_path_from_result(AssetPathResolver.resolve_equipment_visual_asset(visual_asset))


func _validate_bounds(bounds: Dictionary, field: String, issues: Array[Dictionary]) -> void:
	if bounds.is_empty():
		issues.append(_issue("error", field, "missing_bounds", "world tile bounds are required"))
		return
	_validate_vector3(_dictionary_or_empty(bounds.get("center", {})), field.path_join("center"), issues, false)
	_validate_vector3(_dictionary_or_empty(bounds.get("size", {})), field.path_join("size"), issues, true)


func _validate_vector3(value: Dictionary, field: String, issues: Array[Dictionary], non_negative: bool) -> void:
	for axis in ["x", "y", "z"]:
		if not value.has(axis):
			issues.append(_issue("error", field.path_join(axis), "missing_number", "%s is required" % axis))
			continue
		if non_negative and float(value.get(axis, 0.0)) < 0.0:
			issues.append(_issue("error", field.path_join(axis), "number_too_small", "%s must be >= 0" % axis))


func _validate_prototype_ref(prototype_id: Variant, field: String, prototype_ids: Dictionary, issues: Array[Dictionary], allow_empty: bool) -> void:
	var normalized := ContentRegistry.normalize_content_id(prototype_id)
	if normalized.is_empty():
		if not allow_empty:
			issues.append(_issue("error", field, "missing_prototype_ref", "prototype id is required"))
		return
	if not prototype_ids.has(normalized):
		issues.append(_issue("error", field, "unknown_world_tile_prototype", "unknown world tile prototype id %s" % normalized))


func _validate_world_tile_id(id_value: Variant, field: String, bucket: String, code: String, world_tile_index: Dictionary, issues: Array[Dictionary]) -> void:
	var normalized := ContentRegistry.normalize_content_id(id_value)
	if normalized.is_empty():
		return
	var ids: Dictionary = _dictionary_or_empty(world_tile_index.get(bucket, {}))
	if not ids.has(normalized):
		issues.append(_issue("error", field, code, "unknown world tile %s id %s" % [bucket.trim_suffix("s"), normalized]))


func _world_tile_index(registry: ContentRegistry) -> Dictionary:
	var output := {
		"prototypes": {},
		"surface_sets": {},
		"wall_sets": {},
	}
	for record in registry.get_library("world_tiles").values():
		var data: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record).get("data", {}))
		for prototype in data.get("prototypes", []):
			var prototype_id := ContentRegistry.normalize_content_id(_dictionary_or_empty(prototype).get("id", ""))
			if not prototype_id.is_empty():
				output["prototypes"][prototype_id] = true
		for surface_set in data.get("surface_sets", []):
			var surface_set_id := ContentRegistry.normalize_content_id(_dictionary_or_empty(surface_set).get("id", ""))
			if not surface_set_id.is_empty():
				output["surface_sets"][surface_set_id] = true
		for wall_set in data.get("wall_sets", []):
			var wall_set_id := ContentRegistry.normalize_content_id(_dictionary_or_empty(wall_set).get("id", ""))
			if not wall_set_id.is_empty():
				output["wall_sets"][wall_set_id] = true
	return output


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
