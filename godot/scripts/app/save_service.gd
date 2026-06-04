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
		"metadata": _metadata_from_snapshot(slot_key, snapshot),
		"runtime_snapshot": snapshot,
	}
	var file := FileAccess.open(_slot_path(slot_key), FileAccess.WRITE)
	if file == null:
		push_error("存档失败: 无法写入 %s" % _slot_path(slot_key))
		return false
	file.store_string(JSON.stringify(envelope, "\t"))
	return true


func list_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var root_path := ProjectSettings.globalize_path(save_root)
	if not DirAccess.dir_exists_absolute(root_path):
		return slots
	var dir := DirAccess.open(root_path)
	if dir == null:
		return slots
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "json":
			var slot_id := file_name.get_basename()
			var summary := slot_summary(slot_id)
			slots.append(summary)
		file_name = dir.get_next()
	dir.list_dir_end()
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("updated_at", "")) > str(b.get("updated_at", ""))
	)
	return slots


func slot_summary(slot_id: String) -> Dictionary:
	var slot_key: String = _slot_key(slot_id)
	if slot_key.is_empty():
		return _failed("slot_id_empty")
	var path: String = _slot_path(slot_key)
	if not FileAccess.file_exists(path):
		return _failed_slot(slot_key, path, "save_file_missing")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failed_slot(slot_key, path, "save_file_unreadable")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failed_slot(slot_key, path, "save_json_invalid")
	var envelope: Dictionary = parsed
	if int(envelope.get("schema_version", 0)) != SAVE_SCHEMA_VERSION:
		return _failed_slot(slot_key, path, "save_schema_unsupported")
	var snapshot: Dictionary = _dictionary_or_empty(envelope.get("runtime_snapshot", {}))
	if snapshot.is_empty():
		return _failed_slot(slot_key, path, "runtime_snapshot_missing")
	var metadata: Dictionary = _dictionary_or_empty(envelope.get("metadata", {}))
	if metadata.is_empty() and not snapshot.is_empty():
		metadata = _metadata_from_snapshot(slot_key, snapshot)
	var output := {
		"ok": true,
		"slot_id": str(envelope.get("slot_id", slot_key)),
		"path": path,
	}
	for key in metadata.keys():
		output[key] = metadata[key]
	return output


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
		"metadata": _dictionary_or_empty(envelope.get("metadata", _metadata_from_snapshot(slot_key, runtime_snapshot))).duplicate(true),
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


func _metadata_from_snapshot(slot_id: String, snapshot: Dictionary) -> Dictionary:
	var player := _player_actor(snapshot)
	return {
		"slot_id": slot_id,
		"updated_at": Time.get_datetime_string_from_system(false, true),
		"active_map_id": str(snapshot.get("active_map_id", "")),
		"active_location_id": str(snapshot.get("active_location_id", "")),
		"active_entry_point_id": str(snapshot.get("active_entry_point_id", "")),
		"round": int(_dictionary_or_empty(snapshot.get("turn_state", {})).get("round", 0)),
		"event_count": _array_or_empty(snapshot.get("events", [])).size(),
		"actor_count": _array_or_empty(snapshot.get("actors", [])).size(),
		"player_level": int(_dictionary_or_empty(player.get("progression", {})).get("level", 1)),
	}


func _player_actor(snapshot: Dictionary) -> Dictionary:
	for actor in _array_or_empty(snapshot.get("actors", [])):
		var actor_data := _dictionary_or_empty(actor)
		if str(actor_data.get("kind", "")) == "player":
			return actor_data
	return {}


func _failed(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}


func _failed_slot(slot_id: String, path: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"slot_id": slot_id,
		"path": path,
		"reason": reason,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
