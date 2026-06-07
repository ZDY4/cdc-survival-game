extends RefCounted

const ContentSchemaMigration = preload("res://scripts/data/content_schema_migration.gd")
const ContentWriteService = preload("res://scripts/data/content_write_service.gd")


func migrate_record(domain: String, id_value: String, record: Dictionary, options: Dictionary = {}) -> Dictionary:
	var schema := ContentSchemaMigration.new()
	var diagnosis := schema.diagnose(domain, id_value, record)
	if not bool(diagnosis.get("needs_migration", false)):
		return {
			"ok": true,
			"changed": false,
			"dry_run": bool(options.get("dry_run", false)),
			"schema_status": str(diagnosis.get("status", "")),
		}
	var roundtrip: Dictionary = _dictionary_or_empty(diagnosis.get("roundtrip", {}))
	if not bool(roundtrip.get("safe_to_roundtrip", false)):
		return _failed(
			"schema_migration_not_safe",
			"schema migration is not safe for %s %s" % [domain, id_value]
		)

	var path := str(record.get("path", ""))
	var migrated_data := schema.migrate_data(_dictionary_or_empty(record.get("data", {})))
	var write_result := ContentWriteService.new().write_json(path, migrated_data, options)
	if not bool(write_result.get("ok", false)):
		return write_result

	return {
		"ok": true,
		"kind": _singular_domain(domain),
		"id": id_value,
		"relative_path": str(write_result.get("relative_path", "")),
		"changed": bool(write_result.get("changed", false)),
		"dry_run": bool(write_result.get("dry_run", false)),
		"schema_status": str(diagnosis.get("status", "")),
		"write_mode": str(write_result.get("write_mode", "")),
		"diff_summary": _dictionary_or_empty(roundtrip.get("diff_summary", {})),
	}


static func diff_text(diff: Dictionary) -> String:
	if diff.is_empty():
		return "added=0 removed=0 changed=0"
	return "added=%d removed=%d changed=%d" % [
		int(diff.get("field_added_count", 0)),
		int(diff.get("field_removed_count", 0)),
		int(diff.get("field_changed_count", 0)),
	]


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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _failed(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": "failed",
		"code": code,
		"message": message,
	}
