extends RefCounted

const ContentPaths = preload("res://scripts/data/content_paths.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const JsonLoader = preload("res://scripts/data/json_loader.gd")


func references_for(domain: String, id_value: String, registry: ContentRegistry) -> Array[Dictionary]:
	match domain:
		"items":
			return _item_references(id_value, registry)
		"recipes":
			return _recipe_references(id_value, registry)
		"characters":
			return _character_references(id_value, registry)
		"maps":
			return _map_references(id_value, registry)
		"dialogues":
			return _dialogue_references(id_value, registry)
		"quests":
			return _quest_references(id_value, registry)
		"skills":
			return _skill_references(id_value, registry)
		"settlements":
			return _settlement_references(id_value, registry)
		"overworld":
			return _overworld_references(id_value, registry)
	return []


func supports_domain(domain: String) -> bool:
	return [
		"items",
		"recipes",
		"characters",
		"maps",
		"dialogues",
		"quests",
		"skills",
		"settlements",
		"overworld",
	].has(domain)


func _item_references(item_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for recipe_id in registry.get_library("recipes").keys():
		var record: Dictionary = registry.get_library("recipes")[recipe_id]
		var data: Dictionary = record["data"]
		var output: Dictionary = _dictionary_or_empty(data.get("output", {}))
		if _normalize_id(output.get("item_id", "")) == item_id:
			hits.append(_reference_hit("recipe", recipe_id, record["path"], "output.item_id"))
		for i in range(data.get("materials", []).size()):
			var material: Dictionary = _dictionary_or_empty(data["materials"][i])
			if _normalize_id(material.get("item_id", "")) == item_id:
				hits.append(_reference_hit("recipe", recipe_id, record["path"], "materials[%d].item_id" % i))
		_collect_tool_refs(hits, item_id, "recipe", recipe_id, record["path"], "required_tools", data.get("required_tools", []))
		_collect_tool_refs(hits, item_id, "recipe", recipe_id, record["path"], "optional_tools", data.get("optional_tools", []))

	for source_item_id in registry.get_library("items").keys():
		var record: Dictionary = registry.get_library("items")[source_item_id]
		var data: Dictionary = record["data"]
		var fragments: Array = data.get("fragments", [])
		for fragment_index in range(fragments.size()):
			var fragment: Dictionary = _dictionary_or_empty(fragments[fragment_index])
			match str(fragment.get("kind", "")):
				"weapon":
					if _normalize_id(fragment.get("ammo_type", "")) == item_id:
						hits.append(_reference_hit("item", source_item_id, record["path"], "fragments[%d].weapon.ammo_type" % fragment_index))
				"crafting":
					var crafting_recipe: Dictionary = _dictionary_or_empty(fragment.get("crafting_recipe", {}))
					_collect_item_entries(hits, item_id, "item", source_item_id, record["path"], "fragments[%d].crafting.crafting_recipe.materials" % fragment_index, crafting_recipe.get("materials", []), "item_id")
					_collect_item_entries(hits, item_id, "item", source_item_id, record["path"], "fragments[%d].crafting.deconstruct_yield" % fragment_index, fragment.get("deconstruct_yield", []), "item_id")

	for character_id in registry.get_library("characters").keys():
		var record: Dictionary = registry.get_library("characters")[character_id]
		var combat: Dictionary = _dictionary_or_empty(record["data"].get("combat", {}))
		_collect_item_entries(hits, item_id, "character", character_id, record["path"], "combat.loot", combat.get("loot", []), "item_id")

	for map_id in registry.get_library("maps").keys():
		var record: Dictionary = registry.get_library("maps")[map_id]
		var objects: Array = record["data"].get("objects", [])
		for object_index in range(objects.size()):
			var object: Dictionary = _dictionary_or_empty(objects[object_index])
			var props: Dictionary = _dictionary_or_empty(object.get("props", {}))
			var pickup: Dictionary = _dictionary_or_empty(props.get("pickup", {}))
			if _normalize_id(pickup.get("item_id", "")) == item_id:
				hits.append(_reference_hit("map", map_id, record["path"], "objects[%d].props.pickup.item_id" % object_index))
			var container: Dictionary = _dictionary_or_empty(props.get("container", {}))
			_collect_item_entries(hits, item_id, "map", map_id, record["path"], "objects[%d].props.container.initial_inventory" % object_index, container.get("initial_inventory", []), "item_id")

	for shop_id in registry.get_library("shops").keys():
		var record: Dictionary = registry.get_library("shops")[shop_id]
		_collect_item_entries(hits, item_id, "shop", shop_id, record["path"], "inventory", record["data"].get("inventory", []), "item_id")

	_collect_bootstrap_item_refs(hits, item_id, registry)
	_collect_quest_item_refs(hits, item_id, registry)
	_collect_overworld_item_refs(hits, item_id, registry)
	_collect_legacy_json_item_refs(hits, item_id)
	return hits


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
	for rule_id in _dialogue_rule_records().keys():
		var record: Dictionary = _dictionary_or_empty(_dialogue_rule_records()[rule_id])
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
	for rule_id in _dialogue_rule_records().keys():
		var record: Dictionary = _dictionary_or_empty(_dialogue_rule_records()[rule_id])
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		if str(data.get("default_dialogue_id", "")) == dialogue_id:
			hits.append(_reference_hit("dialogue_rule", rule_id, record.get("path", ""), "default_dialogue_id"))
		var variants: Array = data.get("variants", [])
		for i in range(variants.size()):
			var variant: Dictionary = _dictionary_or_empty(variants[i])
			if str(variant.get("dialogue_id", "")) == dialogue_id:
				hits.append(_reference_hit("dialogue_rule", rule_id, record.get("path", ""), "variants[%d].dialogue_id" % i))
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

	for rule_id in _dialogue_rule_records().keys():
		var record: Dictionary = _dictionary_or_empty(_dialogue_rule_records()[rule_id])
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


func _collect_bootstrap_item_refs(hits: Array[Dictionary], item_id: String, registry: ContentRegistry) -> void:
	var path := ContentPaths.domain_path("bootstrap").path_join("new_game_default.json")
	_collect_item_entries(hits, item_id, "bootstrap", "new_game_default", path, "items", registry.bootstrap_config.get("items", []), "itemId")
	_collect_item_entries(hits, item_id, "bootstrap", "new_game_default", path, "ammo", registry.bootstrap_config.get("ammo", []), "itemId")
	_collect_item_entries(hits, item_id, "bootstrap", "new_game_default", path, "equipment", registry.bootstrap_config.get("equipment", []), "itemId")


func _collect_quest_item_refs(hits: Array[Dictionary], item_id: String, registry: ContentRegistry) -> void:
	for quest_id in registry.get_library("quests").keys():
		var record: Dictionary = registry.get_library("quests")[quest_id]
		var nodes: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record["data"].get("flow", {})).get("nodes", {}))
		for node_id in nodes.keys():
			var node: Dictionary = _dictionary_or_empty(nodes[node_id])
			if _normalize_id(node.get("item_id", "")) == item_id:
				hits.append(_reference_hit("quest", quest_id, record["path"], "flow.nodes.%s.item_id" % node_id))
			var rewards: Dictionary = _dictionary_or_empty(node.get("rewards", {}))
			_collect_item_entries(hits, item_id, "quest", quest_id, record["path"], "flow.nodes.%s.rewards.items" % node_id, rewards.get("items", []), "id")


func _collect_overworld_item_refs(hits: Array[Dictionary], item_id: String, registry: ContentRegistry) -> void:
	for overworld_id in registry.get_library("overworld").keys():
		var record: Dictionary = registry.get_library("overworld")[overworld_id]
		var travel_rules: Dictionary = _dictionary_or_empty(record["data"].get("travel_rules", {}))
		if _normalize_id(travel_rules.get("food_item_id", "")) == item_id:
			hits.append(_reference_hit("overworld", overworld_id, record["path"], "travel_rules.food_item_id"))


func _collect_legacy_json_item_refs(hits: Array[Dictionary], item_id: String) -> void:
	for record in _legacy_json_records():
		_collect_recursive_refs(hits, item_id, "item", record, ["item_id", "itemId"], ["items", "loot", "rewards", "inventory"])


func _collect_legacy_json_scalar_refs(hits: Array[Dictionary], target_id: String, field_names: Array[String], source_kind: String) -> void:
	for record in _legacy_json_records():
		_collect_recursive_refs(hits, target_id, source_kind, record, field_names, [])


func _collect_recursive_refs(hits: Array[Dictionary], target_id: String, target_kind: String, record: Dictionary, field_names: Array[String], contextual_parent_names: Array[String]) -> void:
	_walk_recursive_refs(hits, target_id, target_kind, record, _dictionary_or_empty(record.get("data", {})), "$", "", field_names, contextual_parent_names)


func _walk_recursive_refs(hits: Array[Dictionary], target_id: String, target_kind: String, record: Dictionary, value: Variant, path: String, parent_key: String, field_names: Array[String], contextual_parent_names: Array[String]) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		for key in dict.keys():
			var key_string := str(key)
			var next_path := "%s.%s" % [path, key_string]
			var next_value: Variant = dict[key]
			if field_names.has(key_string) and _normalize_id(next_value) == target_id:
				hits.append(_reference_hit("json", record.get("id", ""), record.get("path", ""), "%s -> %s" % [next_path, target_kind]))
			elif key_string == "id" and contextual_parent_names.has(parent_key) and _normalize_id(next_value) == target_id:
				hits.append(_reference_hit("json", record.get("id", ""), record.get("path", ""), "%s -> %s" % [next_path, target_kind]))
			_walk_recursive_refs(hits, target_id, target_kind, record, next_value, next_path, key_string, field_names, contextual_parent_names)
	elif typeof(value) == TYPE_ARRAY:
		var values: Array = value
		for i in range(values.size()):
			var next_path := "%s[%d]" % [path, i]
			var next_value: Variant = values[i]
			if contextual_parent_names.has(parent_key) and _normalize_id(next_value) == target_id:
				hits.append(_reference_hit("json", record.get("id", ""), record.get("path", ""), "%s -> %s" % [next_path, target_kind]))
			_walk_recursive_refs(hits, target_id, target_kind, record, next_value, next_path, parent_key, field_names, contextual_parent_names)


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


func _collect_item_entries(hits: Array[Dictionary], item_id: String, source_kind: String, source_id: String, path: String, field: String, values: Array, id_field: String) -> void:
	for i in range(values.size()):
		var entry: Dictionary = _dictionary_or_empty(values[i])
		if _normalize_id(entry.get(id_field, "")) == item_id:
			hits.append(_reference_hit(source_kind, source_id, path, "%s[%d].%s" % [field, i, id_field]))


func _collect_tool_refs(hits: Array[Dictionary], item_id: String, source_kind: String, source_id: String, path: String, field: String, values: Array) -> void:
	for i in range(values.size()):
		if _normalize_id(values[i]) == item_id:
			hits.append(_reference_hit(source_kind, source_id, path, "%s[%d]" % [field, i]))


func _collect_string_array_refs(hits: Array[Dictionary], target_id: String, source_kind: String, source_id: String, path: String, field: String, values: Array) -> void:
	for i in range(values.size()):
		if str(values[i]) == target_id:
			hits.append(_reference_hit(source_kind, source_id, path, "%s[%d]" % [field, i]))


func _reference_hit(source_kind: String, source_id: String, path: String, detail: String) -> Dictionary:
	return {
		"source_kind": source_kind,
		"source_id": source_id,
		"path": path,
		"detail": detail,
	}


func _dialogue_rule_records() -> Dictionary:
	var output: Dictionary = {}
	var root := ContentPaths.domain_path("dialogue_rules")
	for path in JsonLoader.list_json_files(root, false):
		var parsed: Variant = JsonLoader.read_json_file(path)
		if typeof(parsed) != TYPE_DICTIONARY or parsed.has("__error"):
			continue
		var data: Dictionary = parsed
		var id_value: String = str(data.get("dialogue_key", path.get_file().get_basename()))
		output[id_value] = {
			"path": path,
			"data": data,
		}
	return output


func _legacy_json_records() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var root := ContentPaths.domain_path("json")
	for path in JsonLoader.list_json_files(root, true):
		var parsed: Variant = JsonLoader.read_json_file(path)
		if typeof(parsed) != TYPE_DICTIONARY or parsed.has("__error"):
			continue
		output.append({
			"id": path.get_file().get_basename(),
			"path": path,
			"data": parsed,
		})
	return output


func _normalize_id(id_value: Variant) -> String:
	return ContentRegistry.normalize_content_id(id_value)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
