@tool
extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentReferenceIndex = preload("res://scripts/tools/content_reference_index.gd")
const MapReviewPresenter = preload("res://addons/cdc_game_editor/map_review_presenter.gd")

const MAX_REFERENCE_LINES := 12


func supported_kinds() -> Array[String]:
	return ["item", "recipe", "character", "dialogue", "quest", "skill", "settlement", "overworld", "map"]


func domain_for_kind(kind: String) -> String:
	match kind:
		"item":
			return "items"
		"recipe":
			return "recipes"
		"character":
			return "characters"
		"dialogue":
			return "dialogues"
		"quest":
			return "quests"
		"skill":
			return "skills"
		"settlement":
			return "settlements"
		"overworld":
			return "overworld"
		"map":
			return "maps"
	return ""


func build_selection(target_kind: String, target_id: String, registry: ContentRegistry, repo_root: String) -> Dictionary:
	var domain := domain_for_kind(target_kind)
	if domain.is_empty():
		return {
			"ok": false,
			"status": "unsupported",
			"message": "Supported kinds: %s." % ", ".join(supported_kinds()),
			"path": "",
		}

	var normalized_id := ContentRegistry.normalize_content_id(target_id)
	var record: Dictionary = registry.get_library(domain).get(normalized_id, {})
	if record.is_empty():
		return {
			"ok": false,
			"status": "not_found",
			"message": "Could not find %s %s in migrated Godot content registry." % [target_kind, target_id],
			"path": "",
		}

	var reference_index: ContentReferenceIndex = ContentReferenceIndex.new()
	var references := reference_index.references_for(domain, normalized_id, registry)
	var review: Dictionary = _review_for_record(domain, record)
	return {
		"ok": true,
		"status": "selected",
		"kind": target_kind,
		"id": normalized_id,
		"path": _repo_relative_path(str(record.get("path", "")), repo_root),
		"summary": _summary_for_record(domain, normalized_id, record, repo_root),
		"references": references,
		"reference_count": references.size(),
		"reference_summary": _references_text(references, repo_root),
		"review_summary": review.get("summary", ""),
		"review_checklist": review.get("checklist", ""),
	}


func _summary_for_record(domain: String, target_id: String, record: Dictionary, repo_root: String) -> String:
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var lines: Array[String] = [
		"kind: %s" % _kind_for_domain(domain),
		"id: %s" % target_id,
		"path: %s" % _repo_relative_path(str(record.get("path", "")), repo_root),
	]
	match domain:
		"items":
			var fragment_kinds: Array[String] = []
			for fragment in data.get("fragments", []):
				var fragment_data: Dictionary = _dictionary_or_empty(fragment)
				fragment_kinds.append(str(fragment_data.get("kind", "")))
			lines.append("name: %s" % data.get("name", ""))
			lines.append("value: %d" % int(data.get("value", 0)))
			lines.append("weight: %.2f" % float(data.get("weight", 0.0)))
			lines.append("fragments: %s" % _join_or_dash(fragment_kinds))
		"recipes":
			var output: Dictionary = _dictionary_or_empty(data.get("output", {}))
			lines.append("name: %s" % data.get("name", ""))
			lines.append("output_item_id: %s x%d" % [ContentRegistry.normalize_content_id(output.get("item_id", "")), int(output.get("count", 0))])
			lines.append("materials: %d" % data.get("materials", []).size())
			lines.append("skill_requirements: %s" % _dictionary_keys_or_dash(_dictionary_or_empty(data.get("skill_requirements", {}))))
		"characters":
			var identity: Dictionary = _dictionary_or_empty(data.get("identity", {}))
			var faction: Dictionary = _dictionary_or_empty(data.get("faction", {}))
			var combat: Dictionary = _dictionary_or_empty(data.get("combat", {}))
			var life: Dictionary = _dictionary_or_empty(data.get("life", {}))
			lines.append("display_name: %s" % identity.get("display_name", ""))
			lines.append("archetype: %s" % data.get("archetype", ""))
			lines.append("camp_id: %s" % faction.get("camp_id", ""))
			lines.append("behavior: %s" % combat.get("behavior", ""))
			if not life.is_empty():
				lines.append("settlement_id: %s" % life.get("settlement_id", ""))
		"dialogues":
			lines.append("nodes: %d" % data.get("nodes", []).size())
			lines.append("start_node: %s" % _dialogue_start_node(data))
			lines.append("actions: %s" % _dialogue_action_kinds(data))
		"quests":
			var flow: Dictionary = _dictionary_or_empty(data.get("flow", {}))
			var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
			lines.append("title: %s" % data.get("title", ""))
			lines.append("prerequisites: %s" % _array_or_dash(data.get("prerequisites", [])))
			lines.append("nodes: %d" % nodes.size())
		"skills":
			lines.append("name: %s" % data.get("name", ""))
			lines.append("tree_id: %s" % data.get("tree_id", ""))
			lines.append("max_level: %d" % int(data.get("max_level", 0)))
			lines.append("prerequisites: %s" % _array_or_dash(data.get("prerequisites", [])))
		"settlements":
			lines.append("map_id: %s" % data.get("map_id", ""))
			lines.append("anchors: %d" % data.get("anchors", []).size())
			lines.append("routes: %d" % data.get("routes", []).size())
			lines.append("smart_objects: %d" % data.get("smart_objects", []).size())
		"overworld":
			var size: Dictionary = _dictionary_or_empty(data.get("size", {}))
			lines.append("size: %sx%s" % [size.get("width", ""), size.get("height", "")])
			lines.append("locations: %d" % data.get("locations", []).size())
			lines.append("cells: %d" % data.get("cells", []).size())
		"maps":
			var size: Dictionary = _dictionary_or_empty(data.get("size", {}))
			lines.append("name: %s" % data.get("name", ""))
			lines.append("size: %sx%s" % [size.get("width", ""), size.get("height", "")])
			lines.append("entry_points: %d" % data.get("entry_points", []).size())
			lines.append("objects: %d" % data.get("objects", []).size())
	return "\n".join(lines)


func _review_for_record(domain: String, record: Dictionary) -> Dictionary:
	if domain != "maps":
		return {}
	return MapReviewPresenter.new().build_review(_dictionary_or_empty(record.get("data", {})))


func _references_text(references: Array[Dictionary], repo_root: String) -> String:
	if references.is_empty():
		return "references: none"
	var lines: Array[String] = ["references: %d" % references.size()]
	var limit := min(references.size(), MAX_REFERENCE_LINES)
	for i in range(limit):
		var hit: Dictionary = references[i]
		lines.append("- %s %s @ %s [%s]" % [
			hit.get("source_kind", ""),
			hit.get("source_id", ""),
			_repo_relative_path(str(hit.get("path", "")), repo_root),
			hit.get("detail", ""),
		])
	if references.size() > limit:
		lines.append("- ... %d more" % (references.size() - limit))
	return "\n".join(lines)


func _dialogue_start_node(data: Dictionary) -> String:
	for node in data.get("nodes", []):
		var node_data: Dictionary = _dictionary_or_empty(node)
		if bool(node_data.get("is_start", false)):
			return str(node_data.get("id", ""))
	return ""


func _dialogue_action_kinds(data: Dictionary) -> String:
	var kinds: Dictionary = {}
	for node in data.get("nodes", []):
		var node_data: Dictionary = _dictionary_or_empty(node)
		for action in node_data.get("actions", []):
			var action_data: Dictionary = _dictionary_or_empty(action)
			var kind := str(action_data.get("type", action_data.get("action_type", "")))
			if not kind.is_empty():
				kinds[kind] = true
	return _dictionary_keys_or_dash(kinds)


func _kind_for_domain(domain: String) -> String:
	match domain:
		"items":
			return "item"
		"recipes":
			return "recipe"
		"characters":
			return "character"
		"dialogues":
			return "dialogue"
		"quests":
			return "quest"
		"skills":
			return "skill"
		"settlements":
			return "settlement"
		"maps":
			return "map"
	return domain


func _repo_relative_path(path: String, repo_root: String) -> String:
	var normalized := path.replace("\\", "/")
	var root := repo_root.replace("\\", "/")
	if normalized.begins_with(root + "/"):
		return normalized.substr(root.length() + 1)
	return normalized


func _dictionary_keys_or_dash(values: Dictionary) -> String:
	var keys: Array[String] = []
	for key in values.keys():
		keys.append(str(key))
	keys.sort()
	return _join_or_dash(keys)


func _array_or_dash(values: Array) -> String:
	var output: Array[String] = []
	for value in values:
		output.append(str(value))
	return _join_or_dash(output)


func _join_or_dash(values: Array[String]) -> String:
	if values.is_empty():
		return "-"
	return ", ".join(values)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
