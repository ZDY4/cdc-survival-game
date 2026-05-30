extends SceneTree

const FORBIDDEN_FILENAMES := {
	"Cargo.toml": true,
	"Cargo.lock": true,
}
const FORBIDDEN_EXTENSIONS := {
	"rs": true,
	"wgsl": true,
	"ron": true,
}
const SKIPPED_DIRS := {
	".git": true,
	".godot": true,
	".local": true,
	".local_backup": true,
	".vscode": true,
	"node_modules": true,
	"target": true,
	"tmp": true,
}
const SKIPPED_ROOTS := {
	"logs": true,
	"saves": true,
}


func _init() -> void:
	var root_path := ProjectSettings.globalize_path("res://..")
	var errors := _scan_directory(root_path, "")
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		printerr("Godot migration guard failed: %d forbidden legacy file(s)" % errors.size())
		quit(1)
		return

	print("Godot migration guard passed: no Rust/Cargo/Bevy source files in active mainline")
	quit(0)


func _scan_directory(absolute_path: String, relative_path: String) -> Array[String]:
	var errors: Array[String] = []
	var dir := DirAccess.open(absolute_path)
	if dir == null:
		errors.append("cannot open directory: %s" % absolute_path)
		return errors

	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name == "." or name == "..":
			name = dir.get_next()
			continue

		var child_relative := name if relative_path.is_empty() else "%s/%s" % [relative_path, name]
		var child_absolute := absolute_path.path_join(name)
		if dir.current_is_dir():
			if _should_skip_directory(name, child_relative):
				name = dir.get_next()
				continue
			errors.append_array(_scan_directory(child_absolute, child_relative))
		else:
			var reason := _forbidden_file_reason(name)
			if not reason.is_empty():
				errors.append("%s: %s" % [child_relative, reason])
		name = dir.get_next()
	dir.list_dir_end()
	return errors


func _should_skip_directory(name: String, relative_path: String) -> bool:
	if SKIPPED_DIRS.has(name):
		return true
	return not relative_path.contains("/") and SKIPPED_ROOTS.has(name)


func _forbidden_file_reason(file_name: String) -> String:
	if FORBIDDEN_FILENAMES.has(file_name):
		return "Cargo manifest/lockfile is not part of the Godot mainline"
	var extension := file_name.get_extension().to_lower()
	if FORBIDDEN_EXTENSIONS.has(extension):
		return "Rust/Bevy-era source asset extension is not part of the Godot mainline"
	return ""
