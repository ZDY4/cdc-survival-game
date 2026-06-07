extends RefCounted

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")

const SAVE_SCHEMA_VERSION := 1

var save_root: String = "user://saves"


func _init(p_save_root: String = "user://saves") -> void:
	save_root = p_save_root


func save_snapshot(slot_id: String, snapshot: Dictionary, metadata_overrides: Dictionary = {}) -> bool:
	var slot_key: String = _slot_key(slot_id)
	if slot_key.is_empty():
		push_error("存档失败: slot_id 为空")
		return false
	_ensure_save_root()
	var metadata := _metadata_from_snapshot(slot_key, snapshot)
	for key in metadata_overrides.keys():
		metadata[key] = metadata_overrides[key]

	var envelope: Dictionary = {
		"schema_version": SAVE_SCHEMA_VERSION,
		"slot_id": slot_key,
		"metadata": metadata,
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
	var parsed: Variant = _parse_json_silent(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failed_slot(slot_key, path, "save_json_invalid")
	var envelope: Dictionary = parsed
	var envelope_metadata: Dictionary = _dictionary_or_empty(envelope.get("metadata", {}))
	if int(envelope.get("schema_version", 0)) != SAVE_SCHEMA_VERSION:
		return _failed_slot(slot_key, path, "save_schema_unsupported", envelope_metadata)
	var snapshot: Dictionary = _dictionary_or_empty(envelope.get("runtime_snapshot", {}))
	if snapshot.is_empty():
		return _failed_slot(slot_key, path, "runtime_snapshot_missing", envelope_metadata)
	var metadata: Dictionary = envelope_metadata
	if metadata.is_empty() and not snapshot.is_empty():
		metadata = _metadata_from_snapshot(slot_key, snapshot)
	var output := {
		"ok": true,
		"loadable": true,
		"can_delete": true,
		"recoverable": false,
		"failure_category": "",
		"slot_id": str(envelope.get("slot_id", slot_key)),
		"slot_display_name": _slot_display_name(str(envelope.get("slot_id", slot_key)), metadata),
		"path": path,
	}
	for key in metadata.keys():
		output[key] = metadata[key]
	output["slot_display_name"] = _slot_display_name(str(output.get("slot_id", slot_key)), output)
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

	var parsed: Variant = _parse_json_silent(file.get_as_text())
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
		"metadata": _load_metadata(str(envelope.get("slot_id", slot_key)), envelope, runtime_snapshot),
		"runtime_snapshot": runtime_snapshot,
	}


func rename_slot(slot_id: String, display_name: String) -> Dictionary:
	var slot_key: String = _slot_key(slot_id)
	if slot_key.is_empty():
		return _failed("slot_id_empty")
	var normalized_name := display_name.strip_edges()
	if normalized_name.is_empty():
		return _failed("slot_display_name_empty")
	var path: String = _slot_path(slot_key)
	if not FileAccess.file_exists(path):
		return _failed("save_file_missing")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failed("save_file_unreadable")
	var parsed: Variant = _parse_json_silent(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failed("save_json_invalid")
	var envelope: Dictionary = parsed
	var metadata: Dictionary = _dictionary_or_empty(envelope.get("metadata", {})).duplicate(true)
	metadata["slot_display_name"] = normalized_name
	envelope["metadata"] = metadata
	var write_file := FileAccess.open(path, FileAccess.WRITE)
	if write_file == null:
		return _failed("save_file_unwritable")
	write_file.store_string(JSON.stringify(envelope, "\t"))
	return {
		"ok": true,
		"slot_id": str(envelope.get("slot_id", slot_key)),
		"slot_display_name": normalized_name,
		"path": path,
	}


func delete_snapshot(slot_id: String) -> bool:
	var slot_key: String = _slot_key(slot_id)
	if slot_key.is_empty():
		return false
	var path: String = _slot_path(slot_key)
	if FileAccess.file_exists(path):
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
	return true


func export_slot_for_recovery(slot_id: String) -> Dictionary:
	var slot_key: String = _slot_key(slot_id)
	if slot_key.is_empty():
		return _failed("slot_id_empty")
	var source_path: String = _slot_path(slot_key)
	if not FileAccess.file_exists(source_path):
		return _failed("save_file_missing")
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return _failed("save_file_unreadable")
	var recovery_dir := save_root.path_join("recoveries")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recovery_dir))
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace("T", "_")
	var export_path := recovery_dir.path_join("%s_%s.json" % [slot_key, stamp])
	var target := FileAccess.open(export_path, FileAccess.WRITE)
	if target == null:
		return _failed("save_file_unwritable")
	target.store_buffer(source.get_buffer(source.get_length()))
	return {
		"ok": true,
		"slot_id": slot_key,
		"source_path": source_path,
		"export_path": export_path,
		"absolute_export_path": ProjectSettings.globalize_path(export_path),
		"recovery_suggestion": _recovery_suggestion(str(slot_summary(slot_key).get("reason", ""))),
	}


func _ensure_save_root() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_root))


func _slot_path(slot_id: String) -> String:
	return save_root.path_join("%s.json" % slot_id)


func _slot_key(slot_id: String) -> String:
	return slot_id.strip_edges().replace("\\", "_").replace("/", "_").replace(":", "_")


func _parse_json_silent(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data


func _metadata_from_snapshot(slot_id: String, snapshot: Dictionary) -> Dictionary:
	var player := _player_actor(snapshot)
	var player_combat := _dictionary_or_empty(player.get("combat", {}))
	var player_progression := _dictionary_or_empty(player.get("progression", {}))
	var turn_state := _dictionary_or_empty(snapshot.get("turn_state", {}))
	var combat_state := _dictionary_or_empty(snapshot.get("combat_state", {}))
	var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	var thumbnail_asset := _save_thumbnail_asset(snapshot)
	return {
		"slot_id": slot_id,
		"slot_display_name": _default_slot_display_name(slot_id, snapshot),
		"thumbnail_asset": thumbnail_asset,
		"updated_at": Time.get_datetime_string_from_system(false, true),
		"active_map_id": str(snapshot.get("active_map_id", "")),
		"active_location_id": str(snapshot.get("active_location_id", "")),
		"active_entry_point_id": str(snapshot.get("active_entry_point_id", "")),
		"round": int(turn_state.get("round", 0)),
		"turn_phase": str(turn_state.get("phase", "")),
		"active_actor_id": int(turn_state.get("active_actor_id", 0)),
		"combat_active": bool(combat_state.get("active", false)),
		"combat_round": int(combat_state.get("round", 0)),
		"event_count": _array_or_empty(snapshot.get("events", [])).size(),
		"actor_count": _array_or_empty(snapshot.get("actors", [])).size(),
		"player": {
			"actor_id": int(player.get("actor_id", 0)),
			"display_name": str(player.get("display_name", "")),
			"grid_position": _dictionary_or_empty(player.get("grid_position", {})).duplicate(true),
			"level": int(player_progression.get("level", 1)),
			"current_xp": int(player_progression.get("current_xp", 0)),
			"hp": float(player_combat.get("hp", 0.0)),
			"max_hp": float(player_combat.get("max_hp", 0.0)),
			"ap": float(player.get("ap", 0.0)),
			"money": int(player.get("money", 0)),
			"inventory_stack_count": inventory.keys().size(),
			"inventory_item_count": _inventory_item_count(inventory),
		},
		"player_level": int(player_progression.get("level", 1)),
		"active_quest_count": _array_or_empty(snapshot.get("active_quests", [])).size(),
		"completed_quest_count": _array_or_empty(snapshot.get("completed_quests", [])).size(),
		"container_session_count": _array_or_empty(snapshot.get("container_sessions", [])).size(),
		"shop_session_count": _array_or_empty(snapshot.get("shop_sessions", [])).size(),
		"corpse_container_count": _array_or_empty(snapshot.get("corpse_containers", [])).size(),
		"consumed_target_count": _array_or_empty(snapshot.get("consumed_interaction_targets", [])).size(),
		"unlocked_location_count": _array_or_empty(snapshot.get("unlocked_locations", [])).size(),
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


func _failed_slot(slot_id: String, path: String, reason: String, metadata: Dictionary = {}) -> Dictionary:
	var recovery_export_path := _recovery_export_path(slot_id)
	return {
		"ok": false,
		"loadable": false,
		"can_delete": true,
		"recoverable": true,
		"failure_category": _failure_category(reason),
		"metadata_recovered": not metadata.is_empty(),
		"can_export_recovery": FileAccess.file_exists(path),
		"recovery_export_path": recovery_export_path,
		"absolute_recovery_export_path": ProjectSettings.globalize_path(recovery_export_path),
		"recovery_suggestion": _recovery_suggestion(reason),
		"slot_id": slot_id,
		"slot_display_name": _slot_display_name(slot_id, metadata),
		"thumbnail_asset": _dictionary_or_empty(metadata.get("thumbnail_asset", _save_fallback_thumbnail_asset())),
		"path": path,
		"reason": reason,
	}


func _failure_category(reason: String) -> String:
	match reason:
		"save_file_missing":
			return "missing"
		"save_file_unreadable":
			return "io"
		"save_json_invalid":
			return "json"
		"save_schema_unsupported":
			return "schema"
		"runtime_snapshot_missing":
			return "snapshot"
		"slot_id_empty":
			return "slot"
		_:
			return "unknown"


func _recovery_export_path(slot_id: String) -> String:
	return save_root.path_join("recoveries").path_join("%s_<timestamp>.json" % slot_id)


func _recovery_suggestion(reason: String) -> String:
	match reason:
		"save_json_invalid":
			return "建议先导出坏档备份，再删除或手工检查 JSON。"
		"save_schema_unsupported":
			return "建议先导出旧版本存档，等待后续迁移器或手工转换。"
		"runtime_snapshot_missing":
			return "建议导出 envelope 备份；该槽缺少运行时快照，当前不能继续游戏。"
		"save_file_unreadable":
			return "建议检查文件权限或磁盘状态，再尝试导出备份。"
		"save_file_missing":
			return "存档文件已缺失，可清理该槽位记录。"
		_:
			return "建议先导出备份，再删除或进一步排查。"


func _load_metadata(slot_id: String, envelope: Dictionary, runtime_snapshot: Dictionary) -> Dictionary:
	var metadata: Dictionary = _dictionary_or_empty(envelope.get("metadata", _metadata_from_snapshot(slot_id, runtime_snapshot))).duplicate(true)
	metadata["slot_display_name"] = _slot_display_name(slot_id, metadata)
	if _dictionary_or_empty(metadata.get("thumbnail_asset", {})).is_empty():
		metadata["thumbnail_asset"] = _save_thumbnail_asset(runtime_snapshot)
	return metadata


func _save_thumbnail_asset(snapshot: Dictionary) -> Dictionary:
	var path := _save_thumbnail_path(snapshot)
	var thumbnail := AssetPathResolver.resolve_media_asset(path, "location")
	thumbnail["thumbnail"] = true
	thumbnail["thumbnail_domain"] = "save_slot"
	thumbnail["source"] = "save_metadata"
	return thumbnail


func _save_fallback_thumbnail_asset() -> Dictionary:
	return _save_thumbnail_asset({})


func _save_thumbnail_path(snapshot: Dictionary) -> String:
	var location_id := str(snapshot.get("active_location_id", "")).strip_edges()
	match location_id:
		"survivor_outpost", "survivor_outpost_01":
			return "res://assets/icons/location_safehouse.svg"
		"hospital":
			return "res://assets/icons/location_hospital.svg"
		"school":
			return "res://assets/icons/location_school.svg"
		"factory":
			return "res://assets/icons/location_factory.svg"
		"forest":
			return "res://assets/icons/location_forest.svg"
		"subway":
			return "res://assets/icons/location_subway.svg"
		"supermarket":
			return "res://assets/icons/location_supermarket.svg"
	var map_id := str(snapshot.get("active_map_id", "")).strip_edges()
	if map_id.contains("hospital"):
		return "res://assets/icons/location_hospital.svg"
	if map_id.contains("school"):
		return "res://assets/icons/location_school.svg"
	if map_id.contains("factory"):
		return "res://assets/icons/location_factory.svg"
	if map_id.contains("forest"):
		return "res://assets/icons/location_forest.svg"
	if map_id.contains("subway"):
		return "res://assets/icons/location_subway.svg"
	if map_id.contains("supermarket"):
		return "res://assets/icons/location_supermarket.svg"
	if map_id.contains("outpost"):
		return "res://assets/icons/location_safehouse.svg"
	if map_id.contains("ruins"):
		return "res://assets/icons/location_ruins.svg"
	return "res://assets/icons/location_safehouse.svg"


func _slot_display_name(slot_id: String, metadata: Dictionary) -> String:
	var explicit_name := str(metadata.get("slot_display_name", metadata.get("display_name", ""))).strip_edges()
	if not explicit_name.is_empty():
		return explicit_name
	var player := _dictionary_or_empty(metadata.get("player", {}))
	var player_name := str(player.get("display_name", "")).strip_edges()
	if not player_name.is_empty():
		return "%s 的存档" % player_name
	return _default_slot_display_name(slot_id, {})


func _default_slot_display_name(slot_id: String, snapshot: Dictionary) -> String:
	var player := _player_actor(snapshot)
	var player_name := str(player.get("display_name", "")).strip_edges()
	if not player_name.is_empty():
		return "%s 的存档" % player_name
	return "存档 %s" % slot_id


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _inventory_item_count(inventory: Dictionary) -> int:
	var total := 0
	for item_id in inventory.keys():
		total += max(0, int(inventory[item_id]))
	return total
