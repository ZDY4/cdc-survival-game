extends RefCounted

const ContentCliDomains = preload("res://scripts/tools/content_cli_domains.gd")
const ContentDiffSummary = preload("res://scripts/tools/content_diff_summary.gd")
const ContentReferenceIndex = preload("res://scripts/tools/content_reference_index.gd")
const ContentRecordValidator = preload("res://scripts/tools/content_record_validator.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentSummaryPresenter = preload("res://scripts/tools/content_summary_presenter.gd")
const MapSceneLoader = preload("res://scripts/world/map_scene_loader.gd")

const USAGE := "usage: content_cli <locate|validate|summarize|references|format> <item|recipe|character|dialogue|dialogue_rule|quest|skill|skill_tree|settlement|overworld|map|shop|world_tile|appearance|ai|json> <id> | content_cli validate changed | content_cli format changed | content_cli diff-summary --path <repo-relative-or-absolute-path>"


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
	var nested_ai_lookup := _nested_ai_reference_lookup(args, registry)
	if bool(nested_ai_lookup.get("ok", false)):
		return 0
	if bool(nested_ai_lookup.get("handled", false)):
		return int(nested_ai_lookup.get("exit_code", 1))
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


func _nested_ai_reference_lookup(args: Array[String], registry: ContentRegistry) -> Dictionary:
	if args.size() != 3:
		return {"handled": false}
	var kind := str(args[1])
	var domain := _normalize_domain(kind)
	if domain != "ai":
		return {"handled": false}
	var id_value := ContentRegistry.normalize_content_id(args[2])
	if registry.get_library("ai").has(id_value):
		return {"handled": false}
	var reference_index: ContentReferenceIndex = ContentReferenceIndex.new()
	var hits := reference_index.references_for("ai", id_value, registry)
	if hits.is_empty():
		return {"handled": false}
	_print_references(kind, id_value, "", hits)
	return {"handled": true, "ok": true}


func _validate_changed_command(registry: ContentRegistry) -> int:
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var entries := changed_validation_records_for_paths(registry, ContentDiffSummary.new().changed_path_entries(ContentCliDomains.git_status_paths_for_validate()))
	var status_summary := changed_status_summary(entries)
	var invalid_records := 0
	print("mode: validate_changed")
	print("domains: %s" % ContentCliDomains.validate_domain_names())
	print("changed_supported_files: %d" % entries.size())
	print("change_status_summary: %s" % status_summary.get("text", "none"))
	if entries.is_empty():
		print("checked_records: 0")
		print("invalid_records: 0")
		print("status: no_supported_changes")
		return 0
	for entry in entries:
		var domain := str(entry.get("domain", ""))
		var id_string := str(entry.get("id", ""))
		var record: Dictionary = _dictionary_or_empty(entry.get("record", {}))
		var relative_path := str(entry.get("relative_path", ""))
		if not bool(entry.get("found", false)):
			invalid_records += 1
			var change_status := str(entry.get("change_status", "changed"))
			print("- [%s] %s @ %s" % [_missing_changed_label(change_status), _singular_domain(domain), relative_path])
			print("  - [error] %s: %s (%s:$)" % [
				_missing_changed_code(change_status),
				_missing_changed_message(entry),
				relative_path,
			])
			continue
		var validation := validator.validate_record(domain, id_string, registry)
		var schema: Dictionary = _dictionary_or_empty(validation.get("schema_migration", {}))
		if not bool(validation.get("ok", false)):
			invalid_records += 1
			print("- [%s] %s @ %s" % [_singular_domain(domain), id_string, _repo_relative_path(str(record.get("path", "")))])
			_print_schema_migration_summary(schema, "  ")
			for issue in validation.get("issues", []):
				var data: Dictionary = _dictionary_or_empty(issue)
				print("  - [%s] %s: %s (%s)" % [
					data.get("severity", "error"),
					data.get("code", "validation_error"),
					data.get("message", ""),
					_issue_location(data),
				])
	print("checked_records: %d" % entries.size())
	print("invalid_records: %d" % invalid_records)
	print("status: %s" % ("ok" if invalid_records == 0 else "invalid"))
	return 0 if invalid_records == 0 else 2


func changed_status_summary(entries: Array) -> Dictionary:
	var counts: Dictionary = {}
	var domains: Dictionary = {}
	for entry_value in entries:
		var entry := _dictionary_or_empty(entry_value)
		var status := str(entry.get("change_status", entry.get("status", "changed")))
		if status.is_empty():
			status = "changed"
		counts[status] = int(counts.get(status, 0)) + 1
		var domain := str(entry.get("domain", ""))
		if not domain.is_empty():
			var domain_counts: Dictionary = _dictionary_or_empty(domains.get(domain, {}))
			domain_counts[status] = int(domain_counts.get(status, 0)) + 1
			domains[domain] = domain_counts
	return {
		"total": entries.size(),
		"counts": counts,
		"domains": domains,
		"text": _changed_status_summary_text(counts),
	}


func changed_validation_records_for_paths(registry: ContentRegistry, changed_paths: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	for path_value in changed_paths:
		var changed_entry := _changed_path_entry(path_value)
		var relative_path := str(changed_entry.get("path", "")).replace("\\", "/").simplify_path()
		var domain := ContentCliDomains.validate_domain_for_relative_path(relative_path)
		if domain.is_empty():
			continue
		var key := "%s:%s" % [domain, relative_path]
		if seen.has(key):
			continue
		seen[key] = true
		var record_entry := _record_for_relative_path(registry, domain, relative_path)
		record_entry["domain"] = domain
		record_entry["relative_path"] = relative_path
		record_entry["change_status"] = str(changed_entry.get("status", "changed"))
		record_entry["change_status_code"] = str(changed_entry.get("status_code", ""))
		record_entry["source_relative_path"] = str(changed_entry.get("source_path", ""))
		entries.append(record_entry)
	return entries


func _changed_path_entry(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var entry: Dictionary = value
		return {
			"path": str(entry.get("path", "")).replace("\\", "/"),
			"source_path": str(entry.get("source_path", "")).replace("\\", "/"),
			"status": str(entry.get("status", "changed")),
			"status_code": str(entry.get("status_code", "")),
		}
	return {
		"path": str(value).replace("\\", "/"),
		"source_path": "",
		"status": "changed",
		"status_code": "",
	}


func _changed_status_summary_text(counts: Dictionary) -> String:
	if counts.is_empty():
		return "none"
	var order: Array[String] = ["modified", "added", "untracked", "deleted", "renamed", "changed"]
	var parts: Array[String] = []
	var emitted: Dictionary = {}
	for status in order:
		if counts.has(status):
			parts.append("%s=%d" % [status, int(counts.get(status, 0))])
			emitted[status] = true
	var extra_statuses: Array[String] = []
	for status_value in counts.keys():
		var status := str(status_value)
		if not emitted.has(status):
			extra_statuses.append(status)
	extra_statuses.sort()
	for status in extra_statuses:
		parts.append("%s=%d" % [status, int(counts.get(status, 0))])
	return ", ".join(parts)


func _missing_changed_label(change_status: String) -> String:
	match change_status:
		"added":
			return "added_missing"
		"untracked":
			return "untracked_missing"
		"modified":
			return "modified_missing"
		"deleted":
			return "deleted"
		"renamed":
			return "renamed_missing"
	return "missing"


func _missing_changed_code(change_status: String) -> String:
	match change_status:
		"added":
			return "added_content_file_not_loaded"
		"untracked":
			return "untracked_content_file_not_loaded"
		"modified":
			return "modified_content_file_not_loaded"
		"deleted":
			return "content_file_deleted"
		"renamed":
			return "renamed_content_file_not_loaded"
	return "content_file_not_loaded"


func _missing_changed_message(entry: Dictionary) -> String:
	var source_path := str(entry.get("source_relative_path", ""))
	match str(entry.get("change_status", "")):
		"added":
			return "added content file is not loaded by registry"
		"untracked":
			return "untracked content file is not loaded by registry"
		"modified":
			return "modified content file is not loaded by registry"
		"deleted":
			return "changed content file was deleted and is no longer loaded by registry"
		"renamed":
			if not source_path.is_empty():
				return "renamed content file is not loaded by registry; source was %s" % source_path
			return "renamed content file is not loaded by registry"
	return "changed content file is not loaded by registry"


func _record_for_relative_path(registry: ContentRegistry, domain: String, relative_path: String) -> Dictionary:
	var normalized_path := relative_path.replace("\\", "/")
	for id_value in registry.get_library(domain).keys():
		var id_string := str(id_value)
		var record: Dictionary = _dictionary_or_empty(registry.get_library(domain).get(id_string, {}))
		var record_path := _repo_relative_path(str(record.get("path", ""))).replace("\\", "/")
		if record_path == normalized_path:
			return {
				"found": true,
				"id": id_string,
				"record": record,
			}
	return {
		"found": false,
		"id": normalized_path.get_file().get_basename(),
		"record": {},
	}


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
	_print_schema_migration_summary(_dictionary_or_empty(validation.get("schema_migration", {})), "")
	if not validator.supports_domain(domain):
		print("- [warning] shallow_validation: validate currently checks existence only for %s" % kind)
	for issue in issues:
		var data: Dictionary = _dictionary_or_empty(issue)
		print("- [%s] %s: %s (%s)" % [
			data.get("severity", "error"),
			data.get("code", "validation_error"),
			data.get("message", ""),
			_issue_location(data),
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
		"dialogue_rule":
			return "dialogue_rules"
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
		"shop":
			return "shops"
		"world_tile":
			return "world_tiles"
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


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _issue_location(issue: Dictionary) -> String:
	var location := str(issue.get("location", "")).strip_edges()
	if not location.is_empty():
		return location
	var json_path := str(issue.get("json_path", issue.get("field", "$"))).strip_edges()
	var relative_path := str(issue.get("relative_path", "")).strip_edges()
	if not relative_path.is_empty():
		return "%s:%s" % [relative_path, json_path]
	return json_path if not json_path.is_empty() else "$"


func _print_schema_migration_summary(schema: Dictionary, indent: String = "") -> void:
	if schema.is_empty():
		return
	print("%sschema_status: %s source=%d current=%d needs_migration=%s" % [
		indent,
		schema.get("status", "unknown"),
		int(schema.get("source_schema_version", 0)),
		int(schema.get("current_schema_version", 0)),
		str(bool(schema.get("needs_migration", false))).to_lower(),
	])
	var defaulted: Array = schema.get("defaulted_fields", [])
	var deprecated: Array = schema.get("deprecated_fields", [])
	if not defaulted.is_empty():
		print("%sschema_defaulted_fields: %s" % [indent, ", ".join(defaulted)])
	if not deprecated.is_empty():
		print("%sschema_deprecated_fields: %s" % [indent, ", ".join(deprecated)])
	var roundtrip: Dictionary = _dictionary_or_empty(schema.get("roundtrip", {}))
	var diff: Dictionary = _dictionary_or_empty(roundtrip.get("diff_summary", {}))
	if not diff.is_empty():
		print("%sschema_roundtrip_diff: added=%d removed=%d changed=%d" % [
			indent,
			int(diff.get("field_added_count", 0)),
			int(diff.get("field_removed_count", 0)),
			int(diff.get("field_changed_count", 0)),
		])
		var added: Array = _array_or_empty(diff.get("fields_added", []))
		var removed: Array = _array_or_empty(diff.get("fields_removed", []))
		var changed: Array = _array_or_empty(diff.get("fields_changed", []))
		if not added.is_empty():
			print("%sschema_roundtrip_added_fields: %s" % [indent, ", ".join(added)])
		if not removed.is_empty():
			print("%sschema_roundtrip_removed_fields: %s" % [indent, ", ".join(removed)])
		if not changed.is_empty():
			print("%sschema_roundtrip_changed_fields: %s" % [indent, ", ".join(changed)])


func _reference_domain_list() -> String:
	return "item, recipe, character, dialogue, dialogue_rule, quest, skill, skill_tree, settlement, overworld, map, shop, world_tile, appearance, ai, and json"
