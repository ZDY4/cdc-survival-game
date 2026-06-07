extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")


func print_summary(domain: String, id_value: String, record: Dictionary, relative_path: String) -> void:
	for line in summary_lines(domain, id_value, record, relative_path):
		print(line)


func summary_lines(domain: String, id_value: String, record: Dictionary, relative_path: String) -> Array[String]:
	var data := _dictionary_or_empty(record.get("data", {}))
	var lines: Array[String] = [
		"kind: %s" % singular_domain(domain),
		"id: %s" % id_value,
		"relative_path: %s" % relative_path,
	]
	match domain:
		"items":
			lines.append_array(_item_lines(data))
		"recipes":
			lines.append_array(_recipe_lines(data))
		"characters":
			lines.append_array(_character_lines(data))
		"maps":
			lines.append_array(_map_lines(data))
		"dialogues":
			lines.append_array(_dialogue_lines(data))
		"dialogue_rules":
			lines.append_array(_dialogue_rule_lines(data))
		"quests":
			lines.append_array(_quest_lines(data))
		"skills":
			lines.append_array(_skill_lines(data))
		"skill_trees":
			lines.append_array(_skill_tree_lines(data))
		"settlements":
			lines.append_array(_settlement_lines(data))
		"overworld":
			lines.append_array(_overworld_lines(data))
		"shops":
			lines.append_array(_shop_lines(data))
		"world_tiles":
			lines.append_array(_world_tile_lines(data))
		"ai":
			lines.append_array(_ai_lines(data))
	return lines


static func singular_domain(domain: String) -> String:
	match domain:
		"items":
			return "item"
		"characters":
			return "character"
		"dialogues":
			return "dialogue"
		"dialogue_rules":
			return "dialogue_rule"
		"maps":
			return "map"
		"quests":
			return "quest"
		"recipes":
			return "recipe"
		"skills":
			return "skill"
		"skill_trees":
			return "skill_tree"
		"settlements":
			return "settlement"
		"shops":
			return "shop"
		"world_tiles":
			return "world_tile"
		_:
			return domain


func _item_lines(data: Dictionary) -> Array[String]:
	var lines: Array[String] = [
		"name: %s" % data.get("name", ""),
		"value: %d" % int(data.get("value", 0)),
		"weight: %.2f" % float(data.get("weight", 0.0)),
	]
	var fragment_kinds: Array[String] = []
	for fragment in _array_or_empty(data.get("fragments", [])):
		fragment_kinds.append(str(_dictionary_or_empty(fragment).get("kind", "")))
	lines.append("fragment_count: %d" % fragment_kinds.size())
	lines.append("fragment_kinds: %s" % _join_or_dash(fragment_kinds))
	return lines


func _recipe_lines(data: Dictionary) -> Array[String]:
	var output := _dictionary_or_empty(data.get("output", {}))
	return [
		"name: %s" % data.get("name", ""),
		"output_item_id: %s" % ContentRegistry.normalize_content_id(output.get("item_id", "")),
		"output_count: %d" % int(output.get("count", 0)),
		"materials_count: %d" % _array_or_empty(data.get("materials", [])).size(),
		"required_tools_count: %d" % _array_or_empty(data.get("required_tools", [])).size(),
		"optional_tools_count: %d" % _array_or_empty(data.get("optional_tools", [])).size(),
	]


func _character_lines(data: Dictionary) -> Array[String]:
	var identity := _dictionary_or_empty(data.get("identity", {}))
	var faction := _dictionary_or_empty(data.get("faction", {}))
	var combat := _dictionary_or_empty(data.get("combat", {}))
	var progression := _dictionary_or_empty(data.get("progression", {}))
	return [
		"display_name: %s" % identity.get("display_name", ""),
		"archetype: %s" % data.get("archetype", ""),
		"camp_id: %s" % faction.get("camp_id", ""),
		"disposition: %s" % faction.get("disposition", ""),
		"behavior: %s" % combat.get("behavior", ""),
		"level: %d" % int(progression.get("level", 0)),
		"loot_entries: %d" % _array_or_empty(combat.get("loot", [])).size(),
	]


func _map_lines(data: Dictionary) -> Array[String]:
	var size := _dictionary_or_empty(data.get("size", {}))
	return [
		"name: %s" % data.get("name", ""),
		"size: %dx%d" % [int(size.get("width", 0)), int(size.get("height", 0))],
		"default_level: %d" % int(data.get("default_level", 0)),
		"level_count: %d" % _array_or_empty(data.get("levels", [])).size(),
		"entry_points: %d" % _array_or_empty(data.get("entry_points", [])).size(),
		"objects: %d" % _array_or_empty(data.get("objects", [])).size(),
		"object_kinds: %s" % _kind_counts(_array_or_empty(data.get("objects", [])), "kind"),
	]


func _dialogue_lines(data: Dictionary) -> Array[String]:
	var nodes := _array_or_empty(data.get("nodes", []))
	return [
		"node_count: %d" % nodes.size(),
		"node_types: %s" % _kind_counts(nodes, "type"),
		"start_node: %s" % _dialogue_start_node(nodes),
		"action_types: %s" % _dialogue_action_types(nodes),
		"connection_count: %d" % _array_or_empty(data.get("connections", [])).size(),
	]


func _dialogue_rule_lines(data: Dictionary) -> Array[String]:
	var variants := _array_or_empty(data.get("variants", []))
	return [
		"dialogue_key: %s" % data.get("dialogue_key", ""),
		"default_dialogue_id: %s" % data.get("default_dialogue_id", ""),
		"variant_count: %d" % variants.size(),
		"variant_dialogues: %s" % _join_or_dash(_dialogue_rule_variant_dialogues(variants)),
		"condition_fields: %s" % _join_or_dash(_dialogue_rule_condition_fields(variants)),
	]


func _quest_lines(data: Dictionary) -> Array[String]:
	var flow := _dictionary_or_empty(data.get("flow", {}))
	var nodes := _dictionary_or_empty(flow.get("nodes", {}))
	return [
		"title: %s" % data.get("title", ""),
		"prerequisites: %s" % _join_or_dash(_string_array(_array_or_empty(data.get("prerequisites", [])))),
		"start_node: %s" % flow.get("start_node_id", ""),
		"node_count: %d" % nodes.size(),
		"node_types: %s" % _quest_node_type_counts(nodes),
		"connection_count: %d" % _array_or_empty(flow.get("connections", [])).size(),
	]


func _skill_lines(data: Dictionary) -> Array[String]:
	return [
		"name: %s" % data.get("name", ""),
		"tree_id: %s" % data.get("tree_id", ""),
		"max_level: %d" % int(data.get("max_level", 0)),
		"prerequisites: %s" % _join_or_dash(_string_array(_array_or_empty(data.get("prerequisites", [])))),
		"activation_mode: %s" % _dictionary_or_empty(data.get("activation", {})).get("mode", "passive"),
	]


func _skill_tree_lines(data: Dictionary) -> Array[String]:
	return [
		"name: %s" % data.get("name", ""),
		"skill_count: %d" % _array_or_empty(data.get("skills", [])).size(),
		"skills: %s" % _join_or_dash(_string_array(_array_or_empty(data.get("skills", [])))),
		"link_count: %d" % _array_or_empty(data.get("links", [])).size(),
	]


func _settlement_lines(data: Dictionary) -> Array[String]:
	return [
		"map_id: %s" % data.get("map_id", ""),
		"anchors: %d" % _array_or_empty(data.get("anchors", [])).size(),
		"routes: %d" % _array_or_empty(data.get("routes", [])).size(),
		"smart_objects: %d" % _array_or_empty(data.get("smart_objects", [])).size(),
		"smart_object_kinds: %s" % _kind_counts(_array_or_empty(data.get("smart_objects", [])), "kind"),
	]


func _overworld_lines(data: Dictionary) -> Array[String]:
	var size := _dictionary_or_empty(data.get("size", {}))
	var locations := _array_or_empty(data.get("locations", []))
	return [
		"size: %dx%d" % [int(size.get("width", 0)), int(size.get("height", 0))],
		"locations: %d" % locations.size(),
		"location_kinds: %s" % _kind_counts(locations, "kind"),
		"default_unlocked: %d" % _count_truthy(locations, "default_unlocked"),
		"tiles: %d" % _array_or_empty(data.get("tiles", [])).size(),
	]


func _shop_lines(data: Dictionary) -> Array[String]:
	return [
		"money: %d" % int(data.get("money", 0)),
		"buy_price_modifier: %.2f" % float(data.get("buy_price_modifier", 1.0)),
		"sell_price_modifier: %.2f" % float(data.get("sell_price_modifier", 1.0)),
		"inventory_count: %d" % _array_or_empty(data.get("inventory", [])).size(),
		"required_world_flags: %s" % _join_or_dash(_string_array(_array_or_empty(data.get("required_world_flags", [])))),
		"blocked_world_flags: %s" % _join_or_dash(_string_array(_array_or_empty(data.get("blocked_world_flags", [])))),
		"target_actor_definition_id: %s" % str(data.get("target_actor_definition_id", "-")),
	]


func _world_tile_lines(data: Dictionary) -> Array[String]:
	var prototypes := _array_or_empty(data.get("prototypes", []))
	var surface_sets := _array_or_empty(data.get("surface_sets", []))
	var wall_sets := _array_or_empty(data.get("wall_sets", []))
	return [
		"prototype_count: %d" % prototypes.size(),
		"surface_set_count: %d" % surface_sets.size(),
		"wall_set_count: %d" % wall_sets.size(),
		"prototype_ids: %s" % _join_or_dash(_ids_from_records(prototypes)),
		"surface_set_ids: %s" % _join_or_dash(_ids_from_records(surface_sets)),
		"wall_set_ids: %s" % _join_or_dash(_ids_from_records(wall_sets)),
	]


func _ai_lines(data: Dictionary) -> Array[String]:
	if data.has("id"):
		return [
			"behavior_id: %s" % data.get("id", ""),
			"display_name: %s" % _dictionary_or_empty(data.get("meta", {})).get("display_name", ""),
			"included_behaviors: %s" % _join_or_dash(_string_array(_array_or_empty(data.get("included_behavior_ids", [])))),
			"action_groups: %s" % _join_or_dash(_string_array(_array_or_empty(data.get("action_group_ids", [])))),
			"default_goal_id: %s" % str(data.get("default_goal_id", "-")),
			"alert_goal_id: %s" % str(data.get("alert_goal_id", "-")),
		]
	var lines: Array[String] = []
	for collection in [
		"conditions",
		"facts",
		"fact_groups",
		"score_rules",
		"goals",
		"goal_groups",
		"actions",
		"action_groups",
		"executors",
		"schedule_templates",
		"need_profiles",
		"personality_profiles",
		"smart_object_access_profiles",
	]:
		var values := _array_or_empty(data.get(collection, []))
		if values.is_empty():
			continue
		lines.append("%s_count: %d" % [collection, values.size()])
		lines.append("%s_ids: %s" % [collection, _join_or_dash(_ids_from_records(values))])
	if lines.is_empty():
		lines.append("ai_collections: -")
	return lines


func _dialogue_start_node(nodes: Array) -> String:
	for node in nodes:
		var data := _dictionary_or_empty(node)
		if bool(data.get("is_start", false)):
			return str(data.get("id", ""))
	return "-"


func _dialogue_action_types(nodes: Array) -> String:
	var types := {}
	for node in nodes:
		for action in _array_or_empty(_dictionary_or_empty(node).get("actions", [])):
			var action_type := str(_dictionary_or_empty(action).get("type", ""))
			if not action_type.is_empty():
				types[action_type] = true
	var values: Array[String] = []
	for action_type in types.keys():
		values.append(str(action_type))
	values.sort()
	return _join_or_dash(values)


func _dialogue_rule_variant_dialogues(variants: Array) -> Array[String]:
	var output: Array[String] = []
	for variant in variants:
		var dialogue_id := ContentRegistry.normalize_content_id(_dictionary_or_empty(variant).get("dialogue_id", ""))
		if not dialogue_id.is_empty() and not output.has(dialogue_id):
			output.append(dialogue_id)
	output.sort()
	return output


func _dialogue_rule_condition_fields(variants: Array) -> Array[String]:
	var output: Array[String] = []
	for variant in variants:
		var when := _dictionary_or_empty(_dictionary_or_empty(variant).get("when", {}))
		for key in when.keys():
			var key_string := str(key)
			if not key_string.is_empty() and not output.has(key_string):
				output.append(key_string)
	output.sort()
	return output


func _quest_node_type_counts(nodes: Dictionary) -> String:
	var values: Array = []
	for node in nodes.values():
		values.append(node)
	return _kind_counts(values, "type")


func _kind_counts(values: Array, key: String) -> String:
	var counts := {}
	for value in values:
		var kind := str(_dictionary_or_empty(value).get(key, ""))
		if not kind.is_empty():
			counts[kind] = int(counts.get(kind, 0)) + 1
	var parts: Array[String] = []
	for kind in counts.keys():
		parts.append("%s=%d" % [kind, int(counts[kind])])
	parts.sort()
	return _join_or_dash(parts)


func _count_truthy(values: Array, key: String) -> int:
	var count := 0
	for value in values:
		if bool(_dictionary_or_empty(value).get(key, false)):
			count += 1
	return count


func _string_array(values: Array) -> Array[String]:
	var output: Array[String] = []
	for value in values:
		output.append(ContentRegistry.normalize_content_id(value))
	return output


func _ids_from_records(values: Array) -> Array[String]:
	var output: Array[String] = []
	for value in values:
		var id_value := ContentRegistry.normalize_content_id(_dictionary_or_empty(value).get("id", ""))
		if not id_value.is_empty():
			output.append(id_value)
	output.sort()
	return output


func _join_or_dash(values: Array[String]) -> String:
	if values.is_empty():
		return "-"
	return ", ".join(values)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
