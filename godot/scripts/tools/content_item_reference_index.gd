extends RefCounted

const ContentPaths = preload("res://scripts/data/content_paths.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentReferenceSources = preload("res://scripts/tools/content_reference_sources.gd")

var _sources := ContentReferenceSources.new()


func references_for(item_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	_collect_recipe_refs(hits, item_id, registry)
	_collect_item_fragment_refs(hits, item_id, registry)
	_collect_character_refs(hits, item_id, registry)
	_collect_map_refs(hits, item_id, registry)
	_collect_shop_refs(hits, item_id, registry)
	_collect_bootstrap_refs(hits, item_id, registry)
	_collect_quest_refs(hits, item_id, registry)
	_collect_overworld_refs(hits, item_id, registry)
	_collect_legacy_json_refs(hits, item_id)
	return hits


func _collect_recipe_refs(hits: Array[Dictionary], item_id: String, registry: ContentRegistry) -> void:
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
		var conditions: Array = data.get("unlock_conditions", [])
		for i in range(conditions.size()):
			var condition: Dictionary = _dictionary_or_empty(conditions[i])
			if str(condition.get("type", "")) in ["item", "book"] and _normalize_id(condition.get("id", condition.get("item_id", ""))) == item_id:
				hits.append(_reference_hit("recipe", recipe_id, record["path"], "unlock_conditions[%d].id" % i))


func _collect_item_fragment_refs(hits: Array[Dictionary], item_id: String, registry: ContentRegistry) -> void:
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


func _collect_character_refs(hits: Array[Dictionary], item_id: String, registry: ContentRegistry) -> void:
	for character_id in registry.get_library("characters").keys():
		var record: Dictionary = registry.get_library("characters")[character_id]
		var combat: Dictionary = _dictionary_or_empty(record["data"].get("combat", {}))
		_collect_item_entries(hits, item_id, "character", character_id, record["path"], "combat.loot", combat.get("loot", []), "item_id")


func _collect_map_refs(hits: Array[Dictionary], item_id: String, registry: ContentRegistry) -> void:
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


func _collect_shop_refs(hits: Array[Dictionary], item_id: String, registry: ContentRegistry) -> void:
	for shop_id in registry.get_library("shops").keys():
		var record: Dictionary = registry.get_library("shops")[shop_id]
		_collect_item_entries(hits, item_id, "shop", shop_id, record["path"], "inventory", record["data"].get("inventory", []), "item_id")


func _collect_bootstrap_refs(hits: Array[Dictionary], item_id: String, registry: ContentRegistry) -> void:
	var path := ContentPaths.domain_path("bootstrap").path_join("new_game_default.json")
	_collect_item_entries(hits, item_id, "bootstrap", "new_game_default", path, "items", registry.bootstrap_config.get("items", []), "itemId")
	_collect_item_entries(hits, item_id, "bootstrap", "new_game_default", path, "ammo", registry.bootstrap_config.get("ammo", []), "itemId")
	_collect_item_entries(hits, item_id, "bootstrap", "new_game_default", path, "equipment", registry.bootstrap_config.get("equipment", []), "itemId")


func _collect_quest_refs(hits: Array[Dictionary], item_id: String, registry: ContentRegistry) -> void:
	for quest_id in registry.get_library("quests").keys():
		var record: Dictionary = registry.get_library("quests")[quest_id]
		var nodes: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record["data"].get("flow", {})).get("nodes", {}))
		for node_id in nodes.keys():
			var node: Dictionary = _dictionary_or_empty(nodes[node_id])
			if _normalize_id(node.get("item_id", "")) == item_id:
				hits.append(_reference_hit("quest", quest_id, record["path"], "flow.nodes.%s.item_id" % node_id))
			var rewards: Dictionary = _dictionary_or_empty(node.get("rewards", {}))
			_collect_item_entries(hits, item_id, "quest", quest_id, record["path"], "flow.nodes.%s.rewards.items" % node_id, rewards.get("items", []), "id")


func _collect_overworld_refs(hits: Array[Dictionary], item_id: String, registry: ContentRegistry) -> void:
	for overworld_id in registry.get_library("overworld").keys():
		var record: Dictionary = registry.get_library("overworld")[overworld_id]
		var travel_rules: Dictionary = _dictionary_or_empty(record["data"].get("travel_rules", {}))
		if _normalize_id(travel_rules.get("food_item_id", "")) == item_id:
			hits.append(_reference_hit("overworld", overworld_id, record["path"], "travel_rules.food_item_id"))


func _collect_legacy_json_refs(hits: Array[Dictionary], item_id: String) -> void:
	_sources.collect_legacy_json_refs(hits, item_id, "item", ["item_id", "itemId"], ["items", "loot", "rewards", "inventory"])


func _collect_item_entries(hits: Array[Dictionary], item_id: String, source_kind: String, source_id: String, path: String, field: String, values: Array, id_field: String) -> void:
	for i in range(values.size()):
		var entry: Dictionary = _dictionary_or_empty(values[i])
		if _normalize_id(entry.get(id_field, "")) == item_id:
			hits.append(_reference_hit(source_kind, source_id, path, "%s[%d].%s" % [field, i, id_field]))


func _collect_tool_refs(hits: Array[Dictionary], item_id: String, source_kind: String, source_id: String, path: String, field: String, values: Array) -> void:
	for i in range(values.size()):
		if _normalize_id(values[i]) == item_id:
			hits.append(_reference_hit(source_kind, source_id, path, "%s[%d]" % [field, i]))


func _reference_hit(source_kind: String, source_id: String, path: String, detail: String) -> Dictionary:
	return _sources.reference_hit(source_kind, source_id, path, detail)


func _normalize_id(id_value: Variant) -> String:
	return ContentRegistry.normalize_content_id(id_value)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
