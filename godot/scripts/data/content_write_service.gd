extends RefCounted

const ContentPaths = preload("res://scripts/data/content_paths.gd")


func write_json(path: String, data: Dictionary, options: Dictionary = {}) -> Dictionary:
	var path_check := validate_path(path, options)
	if not bool(path_check.get("ok", false)):
		return path_check

	var formatted := JSON.stringify(data, "  ") + "\n"
	if formatted.strip_edges().is_empty():
		return _failed("serialize_failed", "failed to serialize patched content")

	var before_text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var changed := before_text != formatted
	if not bool(options.get("dry_run", false)) and changed:
		var atomic := _atomic_write_text(path, formatted, options)
		if not bool(atomic.get("ok", false)):
			return atomic

	return {
		"ok": true,
		"status": "ok",
		"path": path,
		"relative_path": repo_relative_path(path),
		"changed": changed,
		"dry_run": bool(options.get("dry_run", false)),
		"write_mode": "dry_run" if bool(options.get("dry_run", false)) else ("atomic_replace" if changed else "unchanged"),
	}


func validate_path(path: String, options: Dictionary = {}) -> Dictionary:
	if path.is_empty():
		return _failed("missing_path", "record has no source path")
	if not bool(options.get("allow_external_path", false)) and not _is_under_data_root(path):
		return _failed("path_outside_data", "refusing to write outside data root: %s" % path)

	return {
		"ok": true,
		"status": "ok",
		"path": path,
		"relative_path": repo_relative_path(path),
	}


func repo_relative_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	var repo_root := ContentPaths.repo_root().replace("\\", "/")
	if normalized.begins_with(repo_root + "/"):
		return normalized.substr(repo_root.length() + 1)
	return normalized


func _is_under_data_root(path: String) -> bool:
	var normalized := path.replace("\\", "/").simplify_path()
	var root := ContentPaths.data_root().replace("\\", "/").simplify_path()
	return normalized == root or normalized.begins_with(root + "/")


func _atomic_write_text(path: String, text: String, options: Dictionary = {}) -> Dictionary:
	var directory := path.get_base_dir()
	if directory.is_empty():
		return _failed("missing_directory", "target path has no directory: %s" % path)
	if not DirAccess.dir_exists_absolute(directory):
		return _failed("directory_missing", "target directory does not exist: %s" % directory)

	var temp_path := _temp_path_for(path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _failed("temp_write_failed", "failed to open temp file %s: %s" % [temp_path, error_string(FileAccess.get_open_error())])
	file.store_string(text)
	file.flush()
	file.close()

	var injected_failure := str(options.get("inject_failure", ""))
	if injected_failure == "before_replace":
		_cleanup_temp(temp_path)
		return _failed("injected_before_replace", "injected write failure before replacing %s" % path)
	var backup_path := ""
	if FileAccess.file_exists(path):
		if injected_failure == "before_remove":
			_cleanup_temp(temp_path)
			return _failed("injected_before_remove", "injected write failure before removing %s" % path)
		backup_path = _backup_path_for(path)
		var backup_error := DirAccess.rename_absolute(path, backup_path)
		if backup_error != OK:
			_cleanup_temp(temp_path)
			return _failed("replace_backup_failed", "failed to stage existing file %s as %s: %s" % [path, backup_path, error_string(backup_error)])
	if injected_failure == "before_rename":
		_restore_backup(path, backup_path)
		_cleanup_temp(temp_path)
		return _failed("injected_before_rename", "injected write failure before renaming %s" % path)
	var rename_error := DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		_cleanup_temp(temp_path)
		_restore_backup(path, backup_path)
		return _failed("replace_rename_failed", "failed to replace %s with %s: %s" % [path, temp_path, error_string(rename_error)])
	_cleanup_temp(backup_path)
	return {
		"ok": true,
		"status": "ok",
		"write_mode": "atomic_replace",
		"temp_path": temp_path,
	}


func _temp_path_for(path: String) -> String:
	return "%s.tmp-%d-%d" % [path, Time.get_ticks_usec(), randi()]


func _backup_path_for(path: String) -> String:
	return "%s.backup-%d-%d" % [path, Time.get_ticks_usec(), randi()]


func _cleanup_temp(temp_path: String) -> void:
	if not temp_path.is_empty() and FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)


func _restore_backup(path: String, backup_path: String) -> void:
	if backup_path.is_empty() or not FileAccess.file_exists(backup_path):
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(backup_path, path)


func _failed(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": "failed",
		"code": code,
		"message": message,
	}
