extends RefCounted

const ContentPaths = preload("res://scripts/data/content_paths.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentItemReferenceIndex = preload("res://scripts/tools/content_item_reference_index.gd")
const ContentReferenceSources = preload("res://scripts/tools/content_reference_sources.gd")

var _item_index := ContentItemReferenceIndex.new()
var _sources := ContentReferenceSources.new()


func references_for(domain: String, id_value: String, registry: ContentRegistry) -> Array[Dictionary]:
	match domain:
		"items":
			return _item_index.references_for(id_value, registry)
		"recipes":
			return _recipe_references(id_value, registry)
		"characters":
			return _character_references(id_value, registry)
		"maps":
			return _map_references(id_value, registry)
		"dialogues":
			return _dialogue_references(id_value, registry)
		"dialogue_rules":
			return _dialogue_rule_references(id_value, registry)
		"quests":
			return _quest_references(id_value, registry)
		"skills":
			return _skill_references(id_value, registry)
		"skill_trees":
			return _skill_tree_references(id_value, registry)
		"settlements":
			return _settlement_references(id_value, registry)
		"overworld":
			return _overworld_references(id_value, registry)
		"shops":
			return _shop_references(id_value, registry)
		"world_tiles":
			return _world_tile_references(id_value, registry)
		"appearance":
			return _appearance_references(id_value, registry)
		"ai":
			return _ai_references(id_value, registry)
	return []


func supports_domain(domain: String) -> bool:
	return [
		"items",
		"recipes",
		"characters",
		"maps",
		"dialogues",
		"dialogue_rules",
		"quests",
		"skills",
		"skill_trees",
		"settlements",
		"overworld",
		"shops",
		"world_tiles",
		"appearance",
		"ai",
	].has(domain)


func _recipe_references(recipe_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for source_recipe_id in registry.get_library("recipes").keys():
		var record: Dictionary = registry.get_library("recipes")[source_recipe_id]
		var conditions: Array = record["data"].get("unlock_conditions", [])
		for i in range(conditions.size()):
			var condition: Dictionary = _dictionary_or_empty(conditions[i])
			if str(condition.get("type", "")) == "recipe" and str(condition.get("id", "")) == recipe_id:
				hits.append(_reference_hit("recipe", source_recipe_id, record["path"], "unlock_conditions[%d].id" % i))
	_collect_legacy_json_scalar_refs(hits, recipe_id, ["unlocks_craft", "recipe_id", "recipeId"], "recipe")
	return hits


func _character_references(character_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var bootstrap_path := ContentPaths.domain_path("bootstrap").path_join("new_game_default.json")
	var spawn_entries: Array = registry.bootstrap_config.get("spawnEntries", [])
	for i in range(spawn_entries.size()):
		var entry: Dictionary = _dictionary_or_empty(spawn_entries[i])
		if str(entry.get("definitionId", "")) == character_id:
			hits.append(_reference_hit("bootstrap", "new_game_default", bootstrap_path, "spawnEntries[%d].definitionId" % i))

	for map_id in registry.get_library("maps").keys():
		var record: Dictionary = registry.get_library("maps")[map_id]
		var objects: Array = record["data"].get("objects", [])
		for object_index in range(objects.size()):
			var object: Dictionary = _dictionary_or_empty(objects[object_index])
			var props: Dictionary = _dictionary_or_empty(object.get("props", {}))
			var ai_spawn: Dictionary = _dictionary_or_empty(props.get("ai_spawn", {}))
			if str(ai_spawn.get("character_id", "")) == character_id:
				hits.append(_reference_hit("map", map_id, record["path"], "objects[%d].props.ai_spawn.character_id" % object_index))

	# Actor talk currently resolves dialogue by definition id, so dialogue rules keyed to the character id are hard references.
	var dialogue_rules := _sources.dialogue_rule_records()
	for rule_id in dialogue_rules.keys():
		var record: Dictionary = _dictionary_or_empty(dialogue_rules[rule_id])
		if str(record.get("data", {}).get("dialogue_key", "")) == character_id:
			hits.append(_reference_hit("dialogue_rule", rule_id, record.get("path", ""), "dialogue_key"))
	return hits


func _map_references(map_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for overworld_id in registry.get_library("overworld").keys():
		var record: Dictionary = registry.get_library("overworld")[overworld_id]
		var locations: Array = record["data"].get("locations", [])
		for i in range(locations.size()):
			var location: Dictionary = _dictionary_or_empty(locations[i])
			if str(location.get("map_id", "")) == map_id:
				hits.append(_reference_hit("overworld", overworld_id, record["path"], "locations[%d] id=%s entry_point_id=%s kind=%s" % [
					i,
					location.get("id", ""),
					location.get("entry_point_id", ""),
					location.get("kind", ""),
				]))

	for settlement_id in registry.get_library("settlements").keys():
		var record: Dictionary = registry.get_library("settlements")[settlement_id]
		if str(record["data"].get("map_id", "")) == map_id:
			hits.append(_reference_hit("settlement", settlement_id, record["path"], "map_id"))

	var bootstrap_path := ContentPaths.domain_path("bootstrap").path_join("new_game_default.json")
	if str(registry.bootstrap_config.get("startupMapId", "")) == map_id:
		hits.append(_reference_hit("bootstrap", "new_game_default", bootstrap_path, "startupMapId"))
	return hits


func _dialogue_references(dialogue_id: String, _registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var dialogue_rules := _sources.dialogue_rule_records()
	for rule_id in dialogue_rules.keys():
		var record: Dictionary = _dictionary_or_empty(dialogue_rules[rule_id])
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		if str(data.get("default_dialogue_id", "")) == dialogue_id:
			hits.append(_reference_hit("dialogue_rule", rule_id, record.get("path", ""), "default_dialogue_id"))
		var variants: Array = data.get("variants", [])
		for i in range(variants.size()):
			var variant: Dictionary = _dictionary_or_empty(variants[i])
			if str(variant.get("dialogue_id", "")) == dialogue_id:
				hits.append(_reference_hit("dialogue_rule", rule_id, record.get("path", ""), "variants[%d].dialogue_id" % i))
	return hits


func _dialogue_rule_references(dialogue_rule_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var record: Dictionary = registry.get_library("dialogue_rules").get(dialogue_rule_id, {})
	if record.is_empty():
		return hits
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var dialogue_key := ContentRegistry.normalize_content_id(data.get("dialogue_key", ""))
	if registry.has_id("characters", dialogue_key):
		var character_record: Dictionary = registry.get_library("characters").get(dialogue_key, {})
		hits.append(_reference_hit("character", dialogue_key, character_record.get("path", ""), "derived_dialogue_rule"))
	var default_dialogue_id := ContentRegistry.normalize_content_id(data.get("default_dialogue_id", ""))
	if registry.has_id("dialogues", default_dialogue_id):
		var dialogue_record: Dictionary = registry.get_library("dialogues").get(default_dialogue_id, {})
		hits.append(_reference_hit("dialogue", default_dialogue_id, dialogue_record.get("path", ""), "resolved_by_default_dialogue_id"))
	var variants: Array = data.get("variants", [])
	for i in range(variants.size()):
		var dialogue_id := ContentRegistry.normalize_content_id(_dictionary_or_empty(variants[i]).get("dialogue_id", ""))
		if registry.has_id("dialogues", dialogue_id):
			var variant_record: Dictionary = registry.get_library("dialogues").get(dialogue_id, {})
			hits.append(_reference_hit("dialogue", dialogue_id, variant_record.get("path", ""), "resolved_by_variants[%d].dialogue_id" % i))
	return hits


func _quest_references(quest_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for source_quest_id in registry.get_library("quests").keys():
		var record: Dictionary = registry.get_library("quests")[source_quest_id]
		var prerequisites: Array = record["data"].get("prerequisites", [])
		for i in range(prerequisites.size()):
			if str(prerequisites[i]) == quest_id:
				hits.append(_reference_hit("quest", source_quest_id, record["path"], "prerequisites[%d]" % i))

	for dialogue_id in registry.get_library("dialogues").keys():
		var record: Dictionary = registry.get_library("dialogues")[dialogue_id]
		var nodes: Array = record["data"].get("nodes", [])
		for node_index in range(nodes.size()):
			var node: Dictionary = _dictionary_or_empty(nodes[node_index])
			var actions: Array = node.get("actions", [])
			for action_index in range(actions.size()):
				var action: Dictionary = _dictionary_or_empty(actions[action_index])
				if str(action.get("quest_id", action.get("questId", ""))) == quest_id:
					hits.append(_reference_hit("dialogue", dialogue_id, record["path"], "nodes[%d].actions[%d].quest_id type=%s" % [node_index, action_index, action.get("type", "")]))

	for recipe_id in registry.get_library("recipes").keys():
		var recipe_record: Dictionary = registry.get_library("recipes")[recipe_id]
		var conditions: Array = recipe_record["data"].get("unlock_conditions", [])
		for i in range(conditions.size()):
			var condition: Dictionary = _dictionary_or_empty(conditions[i])
			if str(condition.get("type", "")) == "quest" and str(condition.get("id", "")) == quest_id:
				hits.append(_reference_hit("recipe", recipe_id, recipe_record["path"], "unlock_conditions[%d].id" % i))

	var dialogue_rules := _sources.dialogue_rule_records()
	for rule_id in dialogue_rules.keys():
		var record: Dictionary = _dictionary_or_empty(dialogue_rules[rule_id])
		var variants: Array = record.get("data", {}).get("variants", [])
		for variant_index in range(variants.size()):
			var when: Dictionary = _dictionary_or_empty(_dictionary_or_empty(variants[variant_index]).get("when", {}))
			_collect_string_array_refs(hits, quest_id, "dialogue_rule", rule_id, record.get("path", ""), "variants[%d].when.player_active_quests_any" % variant_index, when.get("player_active_quests_any", []))
			_collect_string_array_refs(hits, quest_id, "dialogue_rule", rule_id, record.get("path", ""), "variants[%d].when.player_completed_quests_any" % variant_index, when.get("player_completed_quests_any", []))
	return hits


func _skill_references(skill_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for source_skill_id in registry.get_library("skills").keys():
		var record: Dictionary = registry.get_library("skills")[source_skill_id]
		_collect_string_array_refs(hits, skill_id, "skill", source_skill_id, record["path"], "prerequisites", record["data"].get("prerequisites", []))

	for tree_id in registry.get_library("skill_trees").keys():
		var record: Dictionary = registry.get_library("skill_trees")[tree_id]
		_collect_string_array_refs(hits, skill_id, "skill_tree", tree_id, record["path"], "skills", record["data"].get("skills", []))
		var links: Array = record["data"].get("links", [])
		for i in range(links.size()):
			var link: Dictionary = _dictionary_or_empty(links[i])
			if str(link.get("from", "")) == skill_id:
				hits.append(_reference_hit("skill_tree", tree_id, record["path"], "links[%d].from" % i))
			if str(link.get("to", "")) == skill_id:
				hits.append(_reference_hit("skill_tree", tree_id, record["path"], "links[%d].to" % i))
		if _dictionary_or_empty(record["data"].get("layout", {})).has(skill_id):
			hits.append(_reference_hit("skill_tree", tree_id, record["path"], "layout.%s" % skill_id))

	for recipe_id in registry.get_library("recipes").keys():
		var record: Dictionary = registry.get_library("recipes")[recipe_id]
		if _dictionary_or_empty(record["data"].get("skill_requirements", {})).has(skill_id):
			hits.append(_reference_hit("recipe", recipe_id, record["path"], "skill_requirements.%s" % skill_id))
		var conditions: Array = record["data"].get("unlock_conditions", [])
		for i in range(conditions.size()):
			var condition: Dictionary = _dictionary_or_empty(conditions[i])
			if str(condition.get("type", "")) == "skill" and str(condition.get("id", "")) == skill_id:
				hits.append(_reference_hit("recipe", recipe_id, record["path"], "unlock_conditions[%d].id" % i))
	return hits


func _skill_tree_references(skill_tree_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for skill_id in registry.get_library("skills").keys():
		var record: Dictionary = registry.get_library("skills")[skill_id]
		if str(record["data"].get("tree_id", "")) == skill_tree_id:
			hits.append(_reference_hit("skill", skill_id, record["path"], "tree_id"))
	return hits


func _settlement_references(settlement_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for character_id in registry.get_library("characters").keys():
		var record: Dictionary = registry.get_library("characters")[character_id]
		var life: Dictionary = _dictionary_or_empty(record["data"].get("life", {}))
		if str(life.get("settlement_id", "")) == settlement_id:
			hits.append(_reference_hit("character", character_id, record["path"], "life.settlement_id"))
	return hits


func _overworld_references(overworld_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if not registry.get_library("overworld").has(overworld_id):
		return hits
	var record: Dictionary = registry.get_library("overworld")[overworld_id]
	var locations: Array = record["data"].get("locations", [])
	var location_ids: Dictionary = {}
	for location in locations:
		var location_data: Dictionary = _dictionary_or_empty(location)
		var location_id: String = str(location_data.get("id", ""))
		if not location_id.is_empty():
			location_ids[location_id] = true

	var bootstrap_path := ContentPaths.domain_path("bootstrap").path_join("new_game_default.json")
	for i in range(registry.bootstrap_config.get("unlockedLocations", []).size()):
		var location_id: String = str(registry.bootstrap_config["unlockedLocations"][i])
		if location_ids.has(location_id):
			hits.append(_reference_hit("bootstrap", "new_game_default", bootstrap_path, "unlockedLocations[%d]=%s" % [i, location_id]))

	for dialogue_id in registry.get_library("dialogues").keys():
		var dialogue_record: Dictionary = registry.get_library("dialogues")[dialogue_id]
		var nodes: Array = dialogue_record["data"].get("nodes", [])
		for node_index in range(nodes.size()):
			var node: Dictionary = _dictionary_or_empty(nodes[node_index])
			var actions: Array = node.get("actions", [])
			for action_index in range(actions.size()):
				var action: Dictionary = _dictionary_or_empty(actions[action_index])
				var location_id: String = str(action.get("location_id", action.get("locationId", "")))
				if location_ids.has(location_id):
					hits.append(_reference_hit("dialogue", dialogue_id, dialogue_record["path"], "nodes[%d].actions[%d].location_id=%s" % [node_index, action_index, location_id]))

	for map_id in registry.get_library("maps").keys():
		var map_record: Dictionary = registry.get_library("maps")[map_id]
		var objects: Array = map_record["data"].get("objects", [])
		for object_index in range(objects.size()):
			var object: Dictionary = _dictionary_or_empty(objects[object_index])
			_collect_location_refs_from_props(hits, location_ids, "map", map_id, map_record["path"], object_index, object)
	return hits


func _appearance_references(appearance_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for character_id in registry.get_library("characters").keys():
		var record: Dictionary = registry.get_library("characters")[character_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		if ContentRegistry.normalize_content_id(data.get("appearance_profile_id", "")) == appearance_id:
			hits.append(_reference_hit("character", character_id, record.get("path", ""), "appearance_profile_id"))
	_collect_legacy_json_scalar_refs(
		hits,
		appearance_id,
		["appearance_profile_id", "appearanceProfileId", "appearance_id", "appearanceId"],
		"appearance"
	)
	return hits


func _shop_references(shop_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var inferred_actor_id := ""
	var inferred_dialogue_ids := {}
	if shop_id.ends_with("_shop"):
		inferred_actor_id = shop_id.trim_suffix("_shop")
		if registry.has_id("characters", inferred_actor_id):
			var actor_record: Dictionary = registry.get_library("characters")[inferred_actor_id]
			hits.append(_reference_hit("character", inferred_actor_id, actor_record.get("path", ""), "derived_shop_id"))
			inferred_dialogue_ids = _dialogue_ids_for_character(inferred_actor_id)
	for dialogue_id in registry.get_library("dialogues").keys():
		var record: Dictionary = registry.get_library("dialogues")[dialogue_id]
		var nodes: Array = record["data"].get("nodes", [])
		for node_index in range(nodes.size()):
			var node: Dictionary = _dictionary_or_empty(nodes[node_index])
			var actions: Array = node.get("actions", [])
			for action_index in range(actions.size()):
				var action: Dictionary = _dictionary_or_empty(actions[action_index])
				if str(action.get("type", "")) != "open_trade":
					continue
				var action_shop_id := _shop_id_from_action(action)
				if action_shop_id == shop_id:
					hits.append(_reference_hit("dialogue", dialogue_id, record["path"], "nodes[%d].actions[%d].shop_id" % [node_index, action_index]))
				elif action_shop_id.is_empty() and inferred_dialogue_ids.has(str(dialogue_id)):
					hits.append(_reference_hit("dialogue", dialogue_id, record["path"], "nodes[%d].actions[%d].open_trade implicit_actor=%s" % [node_index, action_index, inferred_actor_id]))
	_collect_legacy_json_scalar_refs(
		hits,
		shop_id,
		["shop_id", "shopId", "target_shop_id", "targetShopId"],
		"shop"
	)
	return hits


func _world_tile_references(world_tile_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var target_ids := _world_tile_nested_ids(world_tile_id, registry)
	if target_ids.is_empty():
		target_ids[world_tile_id] = true
	for map_id in registry.get_library("maps").keys():
		var record: Dictionary = registry.get_library("maps")[map_id]
		var objects: Array = record["data"].get("objects", [])
		for object_index in range(objects.size()):
			var object: Dictionary = _dictionary_or_empty(objects[object_index])
			var props: Dictionary = _dictionary_or_empty(object.get("props", {}))
			var visual: Dictionary = _dictionary_or_empty(props.get("visual", {}))
			_collect_world_tile_ref(hits, target_ids, "map", map_id, record["path"], "objects[%d].props.visual.prototype_id" % object_index, visual.get("prototype_id", ""))
			var building: Dictionary = _dictionary_or_empty(props.get("building", {}))
			var tile_set: Dictionary = _dictionary_or_empty(building.get("tile_set", {}))
			_collect_world_tile_ref(hits, target_ids, "map", map_id, record["path"], "objects[%d].props.building.tile_set.wall_set_id" % object_index, tile_set.get("wall_set_id", ""))
			_collect_world_tile_ref(hits, target_ids, "map", map_id, record["path"], "objects[%d].props.building.tile_set.floor_surface_set_id" % object_index, tile_set.get("floor_surface_set_id", ""))
	for overworld_id in registry.get_library("overworld").keys():
		var record: Dictionary = registry.get_library("overworld")[overworld_id]
		var cells: Array = record["data"].get("cells", [])
		for cell_index in range(cells.size()):
			var cell: Dictionary = _dictionary_or_empty(cells[cell_index])
			var visual: Dictionary = _dictionary_or_empty(cell.get("visual", {}))
			_collect_world_tile_ref(hits, target_ids, "overworld", overworld_id, record["path"], "cells[%d].visual.surface_set_id" % cell_index, visual.get("surface_set_id", ""))
	return hits


func _ai_references(ai_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for character_id in registry.get_library("characters").keys():
		var record: Dictionary = _dictionary_or_empty(registry.get_library("characters").get(character_id, {}))
		var life: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record.get("data", {})).get("life", {}))
		for field in ["ai_behavior_profile_id", "schedule_profile_id", "personality_profile_id", "need_profile_id", "smart_object_access_profile_id"]:
			if ContentRegistry.normalize_content_id(life.get(field, "")) == ai_id:
				hits.append(_reference_hit("character", character_id, record.get("path", ""), "life.%s" % field))
	for record_id in registry.get_library("ai").keys():
		var record: Dictionary = _dictionary_or_empty(registry.get_library("ai").get(record_id, {}))
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var path := str(record.get("path", ""))
		if data.has("id"):
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "included_behavior_ids", _array_or_empty(data.get("included_behavior_ids", [])))
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "fact_group_ids", _array_or_empty(data.get("fact_group_ids", [])))
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "fact_ids", _array_or_empty(data.get("fact_ids", [])))
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "goal_group_ids", _array_or_empty(data.get("goal_group_ids", [])))
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "goal_ids", _array_or_empty(data.get("goal_ids", [])))
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "action_group_ids", _array_or_empty(data.get("action_group_ids", [])))
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "action_ids", _array_or_empty(data.get("action_ids", [])))
			_collect_scalar_ref(hits, ai_id, "ai", record_id, path, "default_goal_id", data.get("default_goal_id", ""))
			_collect_scalar_ref(hits, ai_id, "ai", record_id, path, "alert_goal_id", data.get("alert_goal_id", ""))
		for i in range(_array_or_empty(data.get("fact_groups", [])).size()):
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "fact_groups[%d].fact_ids" % i, _array_or_empty(_dictionary_or_empty(data["fact_groups"][i]).get("fact_ids", [])))
		for i in range(_array_or_empty(data.get("goal_groups", [])).size()):
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "goal_groups[%d].goal_ids" % i, _array_or_empty(_dictionary_or_empty(data["goal_groups"][i]).get("goal_ids", [])))
		for i in range(_array_or_empty(data.get("action_groups", [])).size()):
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "action_groups[%d].action_ids" % i, _array_or_empty(_dictionary_or_empty(data["action_groups"][i]).get("action_ids", [])))
		for i in range(_array_or_empty(data.get("goals", [])).size()):
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "goals[%d].score_rule_ids" % i, _array_or_empty(_dictionary_or_empty(data["goals"][i]).get("score_rule_ids", [])))
		for i in range(_array_or_empty(data.get("actions", [])).size()):
			var action: Dictionary = _dictionary_or_empty(data["actions"][i])
			_collect_scalar_ref(hits, ai_id, "ai", record_id, path, "actions[%d].executor_binding_id" % i, action.get("executor_binding_id", ""))
			_collect_string_array_refs(hits, ai_id, "ai", record_id, path, "actions[%d].expected_fact_ids" % i, _array_or_empty(action.get("expected_fact_ids", [])))
	return hits


func _collect_legacy_json_scalar_refs(hits: Array[Dictionary], target_id: String, field_names: Array[String], source_kind: String) -> void:
	_sources.collect_legacy_json_refs(hits, target_id, source_kind, field_names, [])


func _collect_location_refs_from_props(hits: Array[Dictionary], location_ids: Dictionary, source_kind: String, source_id: String, path: String, object_index: int, object: Dictionary) -> void:
	var props: Dictionary = _dictionary_or_empty(object.get("props", {}))
	for prop_name in ["interactive", "trigger"]:
		var prop_data: Dictionary = _dictionary_or_empty(props.get(prop_name, {}))
		if location_ids.has(str(prop_data.get("target_id", ""))):
			hits.append(_reference_hit(source_kind, source_id, path, "objects[%d].props.%s.target_id=%s" % [object_index, prop_name, prop_data.get("target_id", "")]))
		var options: Array = prop_data.get("options", [])
		for option_index in range(options.size()):
			var option: Dictionary = _dictionary_or_empty(options[option_index])
			if location_ids.has(str(option.get("target_id", ""))):
				hits.append(_reference_hit(source_kind, source_id, path, "objects[%d].props.%s.options[%d].target_id=%s" % [object_index, prop_name, option_index, option.get("target_id", "")]))


func _collect_string_array_refs(hits: Array[Dictionary], target_id: String, source_kind: String, source_id: String, path: String, field: String, values: Array) -> void:
	for i in range(values.size()):
		if str(values[i]) == target_id:
			hits.append(_reference_hit(source_kind, source_id, path, "%s[%d]" % [field, i]))


func _collect_scalar_ref(hits: Array[Dictionary], target_id: String, source_kind: String, source_id: String, path: String, field: String, value: Variant) -> void:
	if ContentRegistry.normalize_content_id(value) == target_id:
		hits.append(_reference_hit(source_kind, source_id, path, field))


func _shop_id_from_action(action: Dictionary) -> String:
	return ContentRegistry.normalize_content_id(action.get("shop_id", action.get("shopId", action.get("action_key", action.get("actionKey", "")))))


func _world_tile_nested_ids(world_tile_id: String, registry: ContentRegistry) -> Dictionary:
	var output := {}
	var record: Dictionary = registry.get_library("world_tiles").get(world_tile_id, {})
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	for prototype in data.get("prototypes", []):
		var prototype_id := ContentRegistry.normalize_content_id(_dictionary_or_empty(prototype).get("id", ""))
		if not prototype_id.is_empty():
			output[prototype_id] = true
	for surface_set in data.get("surface_sets", []):
		var surface_set_id := ContentRegistry.normalize_content_id(_dictionary_or_empty(surface_set).get("id", ""))
		if not surface_set_id.is_empty():
			output[surface_set_id] = true
	for wall_set in data.get("wall_sets", []):
		var wall_set_id := ContentRegistry.normalize_content_id(_dictionary_or_empty(wall_set).get("id", ""))
		if not wall_set_id.is_empty():
			output[wall_set_id] = true
	return output


func _collect_world_tile_ref(hits: Array[Dictionary], target_ids: Dictionary, source_kind: String, source_id: String, path: String, detail: String, value: Variant) -> void:
	var normalized := ContentRegistry.normalize_content_id(value)
	if not normalized.is_empty() and target_ids.has(normalized):
		hits.append(_reference_hit(source_kind, source_id, path, detail))


func _dialogue_ids_for_character(character_id: String) -> Dictionary:
	var output := {}
	var dialogue_rules := _sources.dialogue_rule_records()
	for rule_id in dialogue_rules.keys():
		var record: Dictionary = _dictionary_or_empty(dialogue_rules[rule_id])
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		if ContentRegistry.normalize_content_id(data.get("dialogue_key", "")) != character_id:
			continue
		var default_dialogue_id := ContentRegistry.normalize_content_id(data.get("default_dialogue_id", ""))
		if not default_dialogue_id.is_empty():
			output[default_dialogue_id] = true
		var variants: Array = data.get("variants", [])
		for variant in variants:
			var dialogue_id := ContentRegistry.normalize_content_id(_dictionary_or_empty(variant).get("dialogue_id", ""))
			if not dialogue_id.is_empty():
				output[dialogue_id] = true
	return output


func _reference_hit(source_kind: String, source_id: String, path: String, detail: String) -> Dictionary:
	return _sources.reference_hit(source_kind, source_id, path, detail)


func _normalize_id(id_value: Variant) -> String:
	return ContentRegistry.normalize_content_id(id_value)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
