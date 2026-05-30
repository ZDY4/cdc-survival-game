extends SceneTree

const REQUIRED_GODOT_VERSION := "4.6.3"
const REQUIRED_MAIN_SCENE := "res://scenes/game/game_root.tscn"
const REQUIRED_GODOT_CMD := "D:\\godot\\godot.cmd"
const ROOT_SCRIPT_EXPECTATIONS := {
	"run_godot_game.bat": ["call \"%GODOT_EXE%\" --path \"%ROOT_DIR%godot\""],
	"run_godot_editor.bat": ["call \"%GODOT_EXE%\" --editor --path \"%ROOT_DIR%godot\""],
	"run_godot_validate.bat": [
		"call \"%GODOT_EXE%\" --headless --path \"%ROOT_DIR%godot\" --script res://scripts/tools/validate_all.gd",
		"call \"%GODOT_EXE%\" --headless --path \"%ROOT_DIR%godot\" --script res://scripts/tools/mainline_migration_guard.gd",
	],
}
const FORBIDDEN_FILENAMES := {
	"Cargo.toml": true,
	"Cargo.lock": true,
}
const FORBIDDEN_EXTENSIONS := {
	"rs": true,
	"wgsl": true,
	"ron": true,
}
const FORBIDDEN_ROOTS := {
	"server": true,
	"client": true,
}
const FORBIDDEN_DIRECTORIES := {
	"bevy": true,
	"tauri_editor": true,
	"narrative_lab": true,
	"editor_shared": true,
}
const FORBIDDEN_FILE_KEYWORDS := [
	"bevy",
	"cargo",
	"tauri",
	"narrative_lab",
]
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
	var errors := _godot_version_errors()
	errors.append_array(_project_entry_errors(root_path))
	errors.append_array(_root_script_errors(root_path))
	errors.append_array(_map_scene_authority_errors(root_path))
	errors.append_array(_scan_directory(root_path, ""))
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		printerr("Godot migration guard failed: %d issue(s)" % errors.size())
		quit(1)
		return

	print("Godot migration guard passed: Godot %s, Godot root entrypoints, Godot map scenes, and no Rust/Cargo/Bevy source files in active mainline" % _godot_version_string())
	quit(0)


func _godot_version_errors() -> Array[String]:
	var actual := _godot_version_string()
	if actual.begins_with(REQUIRED_GODOT_VERSION + "."):
		return []
	if actual == REQUIRED_GODOT_VERSION:
		return []
	return ["Godot version mismatch: expected %s.x, got %s" % [REQUIRED_GODOT_VERSION, actual]]


func _godot_version_string() -> String:
	var version_info := Engine.get_version_info()
	return "%s.%s.%s.%s.%s" % [
		version_info.get("major", 0),
		version_info.get("minor", 0),
		version_info.get("patch", 0),
		version_info.get("status", ""),
		version_info.get("hash", ""),
	]


func _project_entry_errors(root_path: String) -> Array[String]:
	var errors: Array[String] = []
	var project_path := root_path.path_join("godot/project.godot")
	if not FileAccess.file_exists(project_path):
		return ["godot/project.godot is missing"]
	var config := ConfigFile.new()
	var load_error := config.load(project_path)
	if load_error != OK:
		return ["cannot load godot/project.godot: %s" % error_string(load_error)]
	var main_scene := str(config.get_value("application", "run/main_scene", ""))
	if main_scene != REQUIRED_MAIN_SCENE:
		errors.append("Godot main scene mismatch: expected %s, got %s" % [REQUIRED_MAIN_SCENE, main_scene])
	return errors


func _root_script_errors(root_path: String) -> Array[String]:
	var errors: Array[String] = []
	for script_name in ROOT_SCRIPT_EXPECTATIONS.keys():
		var path := root_path.path_join(script_name)
		if not FileAccess.file_exists(path):
			errors.append("%s is missing" % script_name)
			continue
		var content := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
		if not content.contains("set \"GODOT_EXE=%s\"" % REQUIRED_GODOT_CMD):
			errors.append("%s does not pin GODOT_EXE to %s" % [script_name, REQUIRED_GODOT_CMD])
		if not content.contains("if not exist \"%ROOT_DIR%godot\\project.godot\""):
			errors.append("%s does not verify godot/project.godot" % script_name)
		for expected in ROOT_SCRIPT_EXPECTATIONS[script_name]:
			if not content.contains(str(expected)):
				errors.append("%s missing expected command: %s" % [script_name, expected])
	return errors


func _map_scene_authority_errors(root_path: String) -> Array[String]:
	var errors: Array[String] = []
	var data_maps_path := root_path.path_join("data/maps")
	var scene_maps_path := root_path.path_join("godot/scenes/maps")
	var data_dir := DirAccess.open(data_maps_path)
	if data_dir == null:
		return ["data/maps directory is missing"]
	if not DirAccess.dir_exists_absolute(scene_maps_path):
		return ["godot/scenes/maps directory is missing"]

	data_dir.list_dir_begin()
	var name := data_dir.get_next()
	while not name.is_empty():
		if not data_dir.current_is_dir() and name.get_extension().to_lower() == "json":
			var map_id := name.get_basename()
			var scene_path := scene_maps_path.path_join("%s.tscn" % map_id)
			if not FileAccess.file_exists(scene_path):
				errors.append("map %s has data/maps backup but no Godot scene at godot/scenes/maps/%s.tscn" % [map_id, map_id])
		name = data_dir.get_next()
	data_dir.list_dir_end()
	return errors


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
			var directory_reason := _forbidden_directory_reason(name, child_relative)
			if not directory_reason.is_empty():
				errors.append("%s: %s" % [child_relative, directory_reason])
			elif _should_skip_directory(name, child_relative):
				name = dir.get_next()
				continue
			else:
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


func _forbidden_directory_reason(directory_name: String, relative_path: String) -> String:
	if not relative_path.contains("/") and FORBIDDEN_ROOTS.has(directory_name):
		return "legacy runtime root is not part of the Godot mainline"
	if FORBIDDEN_DIRECTORIES.has(directory_name):
		return "legacy editor/runtime directory is not part of the Godot mainline"
	return ""


func _forbidden_file_reason(file_name: String) -> String:
	if FORBIDDEN_FILENAMES.has(file_name):
		return "Cargo manifest/lockfile is not part of the Godot mainline"
	var extension := file_name.get_extension().to_lower()
	if FORBIDDEN_EXTENSIONS.has(extension):
		return "Rust/Bevy-era source asset extension is not part of the Godot mainline"
	var lower_name := file_name.to_lower()
	for keyword in FORBIDDEN_FILE_KEYWORDS:
		if lower_name.contains(keyword):
			return "legacy stack script/name is not part of the Godot mainline"
	return ""
