extends RefCounted


static func list_json_files(root_path: String, recursive: bool = false) -> Array[String]:
	var files: Array[String] = []
	_collect_json_files(root_path, recursive, files)
	files.sort()
	return files


static func read_json_file(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"__error": "open_failed",
			"path": path,
			"message": error_string(FileAccess.get_open_error()),
		}

	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return {
			"__error": "parse_failed",
			"path": path,
			"message": "invalid JSON or top-level null",
		}
	return parsed


static func _collect_json_files(root_path: String, recursive: bool, output: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(root_path)
	if dir == null:
		return

	dir.list_dir_begin()
	while true:
		var name: String = dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue

		var path: String = root_path.path_join(name)
		if dir.current_is_dir():
			if recursive:
				_collect_json_files(path, recursive, output)
		elif name.get_extension().to_lower() == "json":
			output.append(path)
	dir.list_dir_end()
