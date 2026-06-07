extends RefCounted

const CURRENT_SCHEMA_VERSION := 1


func diagnose(domain: String, id_value: String, record: Dictionary) -> Dictionary:
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var explicit_version := data.has("schema_version")
	var source_version := _read_schema_version(data)
	var deprecated_fields := _deprecated_fields(data)
	var defaulted_fields: Array[String] = []
	var migration_log: Array[Dictionary] = []
	var status := "current"
	if not explicit_version:
		status = "legacy_missing_version"
		defaulted_fields.append("schema_version")
		migration_log.append(_migration_event("default_schema_version", "$.schema_version", "defaulted missing schema_version to %d" % CURRENT_SCHEMA_VERSION))
	elif source_version < CURRENT_SCHEMA_VERSION:
		status = "legacy_version"
		migration_log.append(_migration_event("upgrade_schema_version", "$.schema_version", "would upgrade schema_version %d -> %d" % [source_version, CURRENT_SCHEMA_VERSION]))
	elif source_version > CURRENT_SCHEMA_VERSION:
		status = "future_version"
		migration_log.append(_migration_event("future_schema_version", "$.schema_version", "record schema_version %d is newer than supported %d" % [source_version, CURRENT_SCHEMA_VERSION]))
	for field in deprecated_fields:
		migration_log.append(_migration_event("deprecated_field", "$.%s" % field, "deprecated top-level field %s should be migrated or removed" % field))
	return {
		"domain": domain,
		"id": id_value,
		"path": str(record.get("path", "")),
		"current_schema_version": CURRENT_SCHEMA_VERSION,
		"source_schema_version": source_version,
		"explicit_schema_version": explicit_version,
		"status": status,
		"needs_migration": status != "current" or not deprecated_fields.is_empty(),
		"defaulted_fields": defaulted_fields,
		"deprecated_fields": deprecated_fields,
		"migration_log": migration_log,
		"roundtrip": {
			"schema_version_after_migration": CURRENT_SCHEMA_VERSION if source_version <= CURRENT_SCHEMA_VERSION else source_version,
			"would_write_schema_version": not explicit_version or source_version < CURRENT_SCHEMA_VERSION,
			"safe_to_roundtrip": source_version <= CURRENT_SCHEMA_VERSION,
		},
	}


func migrate_data(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	var source_version := _read_schema_version(migrated)
	if source_version <= CURRENT_SCHEMA_VERSION:
		migrated["schema_version"] = CURRENT_SCHEMA_VERSION
	return migrated


func _read_schema_version(data: Dictionary) -> int:
	if data.has("schema_version"):
		return int(data.get("schema_version", CURRENT_SCHEMA_VERSION))
	if data.has("schemaVersion"):
		return int(data.get("schemaVersion", 0))
	if data.has("version"):
		return int(data.get("version", 0))
	return 0


func _deprecated_fields(data: Dictionary) -> Array[String]:
	var fields: Array[String] = []
	for field in ["schemaVersion", "version"]:
		if data.has(field):
			fields.append(field)
	return fields


func _migration_event(kind: String, json_path: String, message: String) -> Dictionary:
	return {
		"kind": kind,
		"json_path": json_path,
		"message": message,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
