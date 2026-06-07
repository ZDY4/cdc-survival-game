extends RefCounted

const ContentCliDomains = preload("res://scripts/tools/content_cli_domains.gd")
const ContentReferenceIndex = preload("res://scripts/tools/content_reference_index.gd")
const ContentRecordValidator = preload("res://scripts/tools/content_record_validator.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentSummaryPresenter = preload("res://scripts/tools/content_summary_presenter.gd")
const MapSceneLoader = preload("res://scripts/world/map_scene_loader.gd")

const USAGE := "usage: content_cli <locate|validate|summarize|references|format> <item|recipe|character|dialogue|quest|skill|skill_tree|settlement|overworld|map|appearance> <id> | content_cli validate changed | content_cli format changed | content_cli diff-summary --path <repo-relative-or-absolute-path>"


func validate_command(args: Array[String], registry: ContentRegistry) -> int:
	if args.size() == 2 and args[1] == "changed":
		return _validate_changed_command(registry)
	var lookup := _record_lookup(args, registry)
	if not bool(lookup.get("ok", false)):
		return int(lookup.get("exit_code", 1))
	return _print_validation(
		str(lookup.get("kind", "")),
		str(lookup.get("domain", "")),
		str(lookup.get("id", "")),
		_dictionary_or_empty(lookup.get("record", {})),
		registry
	)


func locate_command(args: Array[String], registry: ContentRegistry) -> int:
	var lookup := _record_lookup(args, registry)
	if not bool(lookup.get("ok", false)):
		return int(lookup.get("exit_code", 1))
	if str(lookup.get("domain", "")) == "maps":
		print(_repo_relative_path(str(lookup.get("scene_path", ""))))
		return 0
	var record: Dictionary = _dictionary_or_empty(lookup.get("record", {}))
	print(record.get("path", ""))
	return 0


func locate_path(args: Array[String], registry: ContentRegistry) -> Dictionary:
	var lookup := _record_lookup(args, registry)
	if not bool(lookup.get("ok", false)):
		return lookup
	if str(lookup.get("domain", "")) == "maps":
		return {
			"ok": true,
			"path": _repo_relative_path(str(lookup.get("scene_path", ""))),
		}
	var record: Dictionary = _dictionary_or_empty(lookup.get("record", {}))
	return {
		"ok": true,
		"path": str(record.get("path", "")),
	}


func summarize_command(args: Array[String], registry: ContentRegistry) -> int:
	var lookup := _record_lookup(args, registry)
	if not bool(lookup.get("ok", false)):
		return int(lookup.get("exit_code", 1))
	var presenter: ContentSummaryPresenter = ContentSummaryPresenter.new()
	var record: Dictionary = _dictionary_or_empty(lookup.get("record", {}))
	if str(lookup.get("domain", "")) == "maps":
		record = _map_scene_record(str(lookup.get("id", "")))
		if record.is_empty():
			return 1
	presenter.print_summary(
		str(lookup.get("domain", "")),
		str(lookup.get("id", "")),
		record,
		_repo_relative_path(str(record.get("path", "")))
	)
	return 0


func references_command(args: Array[String], registry: ContentRegistry) -> int:
	var lookup := _record_lookup(args, registry)
	if not bool(lookup.get("ok", false)):
		return int(lookup.get("exit_code", 1))

	var kind := str(lookup.get("kind", ""))
	var domain := str(lookup.get("domain", ""))
	var id_value := str(lookup.get("id", ""))
	var record: Dictionary = _dictionary_or_empty(lookup.get("record", {}))
	var reference_index: ContentReferenceIndex = ContentReferenceIndex.new()
	if not reference_index.supports_domain(domain):
		printerr("references currently supports %s, got %s" % [_reference_domain_list(), kind])
		return 2
	_print_references(kind, id_value, record.get("path", ""), reference_index.references_for(domain, id_value, registry))
	return 0


func _validate_changed_command(registry: ContentRegistry) -> int:
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var checked_records := 0
	var invalid_records := 0
	print("mode: validate_changed")
	print("domains: %s" % ContentCliDomains.validate_domain_names())
	for domain in ContentCliDomains.VALIDATE_CHANGED_DOMAINS:
		for id_value in registry.get_library(domain).keys():
			var id_string := str(id_value)
			var record: Dictionary = registry.get_library(domain).get(id_string, {})
			var validation := validator.validate_record(domain, id_string, registry)
			checked_records += 1
			if not bool(validation.get("ok", false)):
				invalid_records += 1
				print("- [%s] %s @ %s" % [_singular_domain(domain), id_string, _repo_relative_path(str(record.get("path", "")))])
				for issue in validation.get("issues", []):
					var data: Dictionary = _dictionary_or_empty(issue)
					print("  - [%s] %s: %s (%s)" % [
						data.get("severity", "error"),
						data.get("code", "validation_error"),
						data.get("message", ""),
						data.get("field", "$"),
					])
	print("checked_records: %d" % checked_records)
	print("invalid_records: %d" % invalid_records)
	print("status: %s" % ("ok" if invalid_records == 0 else "invalid"))
	return 0 if invalid_records == 0 else 2


func _record_lookup(args: Array[String], registry: ContentRegistry) -> Dictionary:
	if args.size() != 3:
		printerr(USAGE)
		return {"ok": false, "exit_code": 2}
	var kind := str(args[1])
	var domain := _normalize_domain(kind)
	var id_value := ContentRegistry.normalize_content_id(args[2])
	var record: Dictionary = registry.get_library(domain).get(id_value, {})
	var scene_path := ""
	if domain == "maps":
		scene_path = MapSceneLoader.new().scene_path(id_value)
	if record.is_empty() and (domain != "maps" or not ResourceLoader.exists(scene_path)):
		printerr("not found: %s %s" % [kind, id_value])
		return {"ok": false, "exit_code": 1}
	return {
		"ok": true,
		"kind": kind,
		"domain": domain,
		"id": id_value,
		"record": record,
		"scene_path": scene_path,
	}


func _map_scene_record(map_id: String) -> Dictionary:
	var result: Dictionary = MapSceneLoader.new().load_map_definition(map_id)
	if not bool(result.get("ok", false)):
		printerr(result.get("error", "failed to load map scene: %s" % map_id))
		return {}
	return {
		"path": str(result.get("path", "")),
		"data": _dictionary_or_empty(result.get("data", {})),
	}


func _print_references(kind: String, id_value: String, path: String, hits: Array[Dictionary]) -> void:
	print("kind: %s" % kind)
	print("id: %s" % id_value)
	print("relative_path: %s" % _repo_relative_path(path))
	print("reference_count: %d" % hits.size())
	if hits.is_empty():
		print("status: no_references_found")
		return
	for hit in hits:
		print("- %s %s @ %s [%s]" % [
			hit.get("source_kind", ""),
			hit.get("source_id", ""),
			_repo_relative_path(str(hit.get("path", ""))),
			hit.get("detail", ""),
		])


func _print_validation(kind: String, domain: String, id_value: String, record: Dictionary, registry: ContentRegistry) -> int:
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var validation := validator.validate_record(domain, id_value, registry)
	var issues: Array = validation.get("issues", [])
	print("kind: %s" % _singular_domain(domain))
	print("id: %s" % id_value)
	print("relative_path: %s" % _repo_relative_path(str(record.get("path", ""))))
	print("status: %s" % validation.get("status", "invalid"))
	if not validator.supports_domain(domain):
		print("- [warning] shallow_validation: validate currently checks existence only for %s" % kind)
	for issue in issues:
		var data: Dictionary = _dictionary_or_empty(issue)
		print("- [%s] %s: %s (%s)" % [
			data.get("severity", "error"),
			data.get("code", "validation_error"),
			data.get("message", ""),
			data.get("field", "$"),
		])
	return 0 if bool(validation.get("ok", false)) else 2


func _normalize_domain(kind: String) -> String:
	match kind:
		"item":
			return "items"
		"character":
			return "characters"
		"dialogue":
			return "dialogues"
		"map":
			return "maps"
		"quest":
			return "quests"
		"recipe":
			return "recipes"
		"skill":
			return "skills"
		"skill_tree":
			return "skill_trees"
		"settlement":
			return "settlements"
		_:
			return kind


func _singular_domain(domain: String) -> String:
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


func _repo_relative_path(path: String) -> String:
	var normalized: String = path.replace("\\", "/")
	if normalized.begins_with("res://"):
		return "godot/%s" % normalized.substr("res://".length())
	var marker := "/data/"
	var index := normalized.find(marker)
	if index >= 0:
		return normalized.substr(index + 1)
	return normalized


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _reference_domain_list() -> String:
	return "item, recipe, character, dialogue, quest, skill, skill_tree, settlement, overworld, map, and appearance"
