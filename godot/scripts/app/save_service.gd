extends RefCounted

const SAVE_SCHEMA_VERSION := 1

var save_root: String = "user://saves"


func _init(p_save_root: String = "user://saves") -> void:
	save_root = p_save_root


func save_snapshot(slot_id: String, snapshot: Dictionary) -> bool:
	var slot_key: String = _slot_key(slot_id)
	if slot_key.is_empty():
		push_error("存档失败: slot_id 为空")
		return false
	_ensure_save_root()

	var envelope: Dictionary = {
		"schema_version": SAVE_SCHEMA_VERSION,
		"slot_id": slot_key,
		"runtime_snapshot": snapshot,
	}
	var file := FileAccess.open(_slot_path(slot_key), FileAccess.WRITE)
	if file == null:
		push_error("存档失败: 无法写入 %s" % _slot_path(slot_key))
		return false
	file.store_string(JSON.stringify(envelope, "\t"))
	return true


func load_snapshot(slot_id: String) -> Dictionary:
	var slot_key: String = _slot_key(slot_id)
	if slot_key.is_empty():
		return _failed("slot_id_empty")

	var path: String = _slot_path(slot_key)
	if not FileAccess.file_exists(path):
		return _failed("save_file_missing")

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failed("save_file_unreadable")

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failed("save_json_invalid")

	var envelope: Dictionary = parsed
	if int(envelope.get("schema_version", 0)) != SAVE_SCHEMA_VERSION:
		return _failed("save_schema_unsupported")

	var runtime_snapshot: Dictionary = _dictionary_or_empty(envelope.get("runtime_snapshot", {}))
	if runtime_snapshot.is_empty():
		return _failed("runtime_snapshot_missing")

	return {
		"ok": true,
		"slot_id": str(envelope.get("slot_id", slot_key)),
		"runtime_snapshot": runtime_snapshot,
	}


func delete_snapshot(slot_id: String) -> bool:
	var slot_key: String = _slot_key(slot_id)
	if slot_key.is_empty():
		return false
	var path: String = _slot_path(slot_key)
	if FileAccess.file_exists(path):
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
	return true


func _ensure_save_root() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_root))


func _slot_path(slot_id: String) -> String:
	return save_root.path_join("%s.json" % slot_id)


func _slot_key(slot_id: String) -> String:
	return slot_id.strip_edges().replace("\\", "_").replace("/", "_").replace(":", "_")


func _failed(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
