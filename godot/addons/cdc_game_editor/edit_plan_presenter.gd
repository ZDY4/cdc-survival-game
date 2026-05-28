@tool
extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")

const SUPPORTED_DOMAINS := ["items", "recipes", "characters", "maps", "quests", "skills", "skill_trees"]


func supports_domain(domain: String) -> bool:
	return SUPPORTED_DOMAINS.has(domain)


func build_plan(domain: String, record: Dictionary, references: Array[Dictionary]) -> Dictionary:
	if not supports_domain(domain):
		return {}

	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var lines: Array[String] = [
		"edit_plan:",
		"mode: read_only_handoff",
		"editable_groups: %s" % _editable_groups_for(domain, data),
		"reference_impact: %s" % _reference_impact(references),
	]
	var checks: Array[String] = [
		"edit_plan_checks:",
		"- keep canonical JSON in data/ as the migration source",
		"- run Godot content validate after saving data changes",
	]

	match domain:
		"items":
			_append_item_plan(lines, checks, data, references)
		"recipes":
			_append_recipe_plan(lines, checks, data)
		"characters":
			_append_character_plan(lines, checks, data, references)
		"maps":
			_append_map_plan(lines, checks, data, references)
		"quests":
			_append_quest_plan(lines, checks, data, references)
		"skills":
			_append_skill_plan(lines, checks, data, references)
		"skill_trees":
			_append_skill_tree_plan(lines, checks, data, references)

	return {
		"summary": "\n".join(lines),
		"checklist": "\n".join(checks),
	}


func _append_item_plan(lines: Array[String], checks: Array[String], data: Dictionary, references: Array[Dictionary]) -> void:
	var fragment_kinds: Array[String] = []
	for fragment in data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		fragment_kinds.append(str(fragment_data.get("kind", "")))
	lines.append("fields: name, description, icon_path, value, weight, fragments")
	lines.append("fragment_kinds: %s" % _join_or_dash(fragment_kinds))
	lines.append("recipe_refs: %d" % _count_references_by_kind(references, "recipe"))
	lines.append("map_refs: %d" % _count_references_by_kind(references, "map"))
	checks.append("- changing id affects recipes, maps, shops, bootstrap, quests, and legacy json references")
	checks.append("- usable/crafting fragment changes must still resolve item and effect references")
	checks.append("- economy edits should preserve non-negative value and weight")


func _append_recipe_plan(lines: Array[String], checks: Array[String], data: Dictionary) -> void:
	var output: Dictionary = _dictionary_or_empty(data.get("output", {}))
	lines.append("fields: name, description, category, output, materials, tools, station, skill_requirements, timing")
	lines.append("output: %s x%d" % [ContentRegistry.normalize_content_id(output.get("item_id", "")), int(output.get("count", 0))])
	lines.append("materials: %d" % data.get("materials", []).size())
	lines.append("skill_requirements: %s" % _dictionary_keys_or_dash(_dictionary_or_empty(data.get("skill_requirements", {}))))
	checks.append("- output.item_id and every material item_id must exist in data/items")
	checks.append("- station/tool edits should match runtime crafting affordances")
	checks.append("- unlock condition changes need a progression or content CLI smoke pass")


func _append_character_plan(lines: Array[String], checks: Array[String], data: Dictionary, references: Array[Dictionary]) -> void:
	var identity: Dictionary = _dictionary_or_empty(data.get("identity", {}))
	var faction: Dictionary = _dictionary_or_empty(data.get("faction", {}))
	var combat: Dictionary = _dictionary_or_empty(data.get("combat", {}))
	var ai: Dictionary = _dictionary_or_empty(data.get("ai", {}))
	lines.append("fields: identity, faction, presentation, progression, combat, ai, attributes, life")
	lines.append("display_name: %s" % identity.get("display_name", ""))
	lines.append("faction: %s/%s" % [faction.get("camp_id", ""), faction.get("disposition", "")])
	lines.append("combat_behavior: %s" % combat.get("behavior", ""))
	lines.append("ai_tuning_keys: %s" % _dictionary_keys_or_dash(ai))
	lines.append("spawn_refs: %d" % _count_references_by_kind(references, "map"))
	checks.append("- id changes affect bootstrap spawns, map ai_spawn objects, and dialogue rules")
	checks.append("- combat loot edits must keep item ids and chance/min/max ranges valid")
	checks.append("- ai range/cooldown changes should be checked with AI and combat smoke")


func _append_map_plan(lines: Array[String], checks: Array[String], data: Dictionary, references: Array[Dictionary]) -> void:
	var size: Dictionary = _dictionary_or_empty(data.get("size", {}))
	lines.append("fields: name, size, levels, entry_points, objects, props")
	lines.append("size: %sx%s" % [size.get("width", ""), size.get("height", "")])
	lines.append("entry_points: %d" % data.get("entry_points", []).size())
	lines.append("object_kinds: %s" % _map_object_kind_counts(data))
	lines.append("overworld_refs: %d" % _count_references_by_kind(references, "overworld"))
	checks.append("- entry point ids must stay aligned with overworld locations and scene transitions")
	checks.append("- object position edits should pass map review occupied/blocking/sight checks")
	checks.append("- pickup/container/ai_spawn props must reference existing items or characters")


func _append_quest_plan(lines: Array[String], checks: Array[String], data: Dictionary, references: Array[Dictionary]) -> void:
	var flow: Dictionary = _dictionary_or_empty(data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	lines.append("fields: title, description, time_limit")
	lines.append("title: %s" % data.get("title", ""))
	lines.append("flow_nodes: %d" % nodes.size())
	lines.append("dialogue_refs: %d" % _count_references_by_kind(references, "dialogue"))
	checks.append("- metadata edits should keep title non-empty and preserve quest id")
	checks.append("- flow, rewards, prerequisites, and objective graph remain JSON/manual edit territory")
	checks.append("- quest metadata changes should pass Godot content validate and quest smoke")


func _append_skill_plan(lines: Array[String], checks: Array[String], data: Dictionary, references: Array[Dictionary]) -> void:
	lines.append("fields: name, icon, description, max_level")
	lines.append("tree_id: %s" % data.get("tree_id", ""))
	lines.append("max_level: %d" % int(data.get("max_level", 0)))
	lines.append("skill_tree_refs: %d" % _count_references_by_kind(references, "skill_tree"))
	checks.append("- max_level must stay >= 1 and should not strand existing learned skill levels")
	checks.append("- tree_id, prerequisites, requirements, and gameplay_effect remain JSON/manual edit territory")
	checks.append("- skill metadata changes should pass Godot content validate and progression smoke")


func _append_skill_tree_plan(lines: Array[String], checks: Array[String], data: Dictionary, references: Array[Dictionary]) -> void:
	lines.append("fields: name, description")
	lines.append("skills: %d" % data.get("skills", []).size())
	lines.append("links: %d" % data.get("links", []).size())
	lines.append("skill_refs: %d" % _count_references_by_kind(references, "skill"))
	checks.append("- skill list, links, and layout remain JSON/manual edit territory")
	checks.append("- metadata edits should keep name non-empty and preserve tree id")
	checks.append("- skill tree metadata changes should pass Godot content validate and progression smoke")


func _editable_groups_for(domain: String, data: Dictionary) -> String:
	match domain:
		"items":
			return "identity, economy, stack/use/crafting fragments"
		"recipes":
			return "identity, output, ingredients, tools, unlocks"
		"characters":
			var groups := "identity, faction, presentation, combat, ai, attributes"
			if data.has("life"):
				groups += ", life"
			return groups
		"maps":
			return "metadata, levels, entry points, objects, interactions, spawns"
		"quests":
			return "metadata"
		"skills":
			return "metadata, level cap"
		"skill_trees":
			return "metadata"
	return "-"


func _reference_impact(references: Array[Dictionary]) -> String:
	if references.is_empty():
		return "none"
	return "%d inbound reference(s)" % references.size()


func _count_references_by_kind(references: Array[Dictionary], source_kind: String) -> int:
	var count := 0
	for reference in references:
		var hit: Dictionary = _dictionary_or_empty(reference)
		if str(hit.get("source_kind", "")) == source_kind:
			count += 1
	return count


func _map_object_kind_counts(data: Dictionary) -> String:
	var counts: Dictionary = {}
	for object in data.get("objects", []):
		var object_data: Dictionary = _dictionary_or_empty(object)
		var kind := str(object_data.get("kind", ""))
		if kind.is_empty():
			kind = "<empty>"
		counts[kind] = int(counts.get(kind, 0)) + 1
	var parts: Array[String] = []
	for kind in counts.keys():
		parts.append("%s=%d" % [kind, int(counts[kind])])
	parts.sort()
	return _join_or_dash(parts)


func _dictionary_keys_or_dash(values: Dictionary) -> String:
	var keys: Array[String] = []
	for key in values.keys():
		keys.append(str(key))
	keys.sort()
	return _join_or_dash(keys)


func _join_or_dash(values: Array[String]) -> String:
	if values.is_empty():
		return "-"
	return ", ".join(values)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
