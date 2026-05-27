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
	return lines


static func singular_domain(domain: String) -> String:
	match domain:
		"items":
			return "item"
		"characters":
			return "character"
		"dialogues":
			return "dialogue"
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
