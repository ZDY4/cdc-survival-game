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
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return _failed("write_failed", "failed to open %s for write: %s" % [path, error_string(FileAccess.get_open_error())])
		file.store_string(formatted)

	return {
		"ok": true,
		"status": "ok",
		"path": path,
		"relative_path": repo_relative_path(path),
		"changed": changed,
		"dry_run": bool(options.get("dry_run", false)),
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


func _failed(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": "failed",
		"code": code,
		"message": message,
	}
