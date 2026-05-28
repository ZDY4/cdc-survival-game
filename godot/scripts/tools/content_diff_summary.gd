extends RefCounted

const ContentPaths = preload("res://scripts/data/content_paths.gd")


func summarize_path(input_path: String) -> Dictionary:
	var relative_path := _normalize_repo_path(input_path)
	if relative_path.is_empty():
		return _failed("path_outside_repo", "path is outside repo root: %s" % input_path)

	var status_output := _git_output(["status", "--short", "--untracked-files=all", "--", relative_path])
	if int(status_output.get("exit_code", 1)) != 0:
		return _failed("git_status_failed", str(status_output.get("error", "git status failed")))
	var status_line := _first_line(str(status_output.get("stdout", ""))).strip_edges()

	if status_line.is_empty():
		return _report(relative_path, "clean", 0, 0, 0)
	if status_line.begins_with("??"):
		var raw := FileAccess.get_file_as_string(ContentPaths.repo_root().path_join(relative_path))
		return _report(relative_path, "untracked", raw.split("\n", false).size(), 0, 1)

	var numstat := _git_output(["diff", "--numstat", "HEAD", "--", relative_path])
	if int(numstat.get("exit_code", 1)) != 0:
		return _failed("git_numstat_failed", str(numstat.get("error", "git diff --numstat failed")))
	var counts := _parse_numstat(str(numstat.get("stdout", "")))
	var diff := _git_output(["diff", "--no-ext-diff", "--unified=0", "HEAD", "--", relative_path])
	if int(diff.get("exit_code", 1)) != 0:
		return _failed("git_diff_failed", str(diff.get("error", "git diff failed")))

	return _report(
		relative_path,
		_normalize_status_code(status_line),
		int(counts.get("added", 0)),
		int(counts.get("removed", 0)),
		_changed_hunk_count(str(diff.get("stdout", "")))
	)


func changed_paths(path_roots: Array[String]) -> Array[String]:
	var git_args: Array[String] = ["status", "--short", "--untracked-files=all", "--"]
	git_args.append_array(path_roots)
	var status := _git_output(git_args)
	var paths: Array[String] = []
	if int(status.get("exit_code", 1)) != 0:
		printerr(status.get("error", "git status failed"))
		return paths
	for line in str(status.get("stdout", "")).split("\n", false):
		var path := _path_from_status_line(line)
		if not path.is_empty():
			paths.append(path)
	paths.sort()
	return paths


func _report(relative_path: String, status: String, added_lines: int, removed_lines: int, changed_hunks: int) -> Dictionary:
	return {
		"ok": true,
		"status": status,
		"path": relative_path,
		"added_lines": added_lines,
		"removed_lines": removed_lines,
		"changed_hunks": changed_hunks,
	}


func _git_output(args: Array[String]) -> Dictionary:
	var output: Array = []
	var packed := PackedStringArray(["-C", ContentPaths.repo_root()])
	for arg in args:
		packed.append(arg)
	var exit_code := OS.execute("git", packed, output, true)
	return {
		"exit_code": exit_code,
		"stdout": "\n".join(output),
		"error": "git %s failed" % " ".join(args),
	}


func _normalize_repo_path(input_path: String) -> String:
	var normalized := input_path.replace("\\", "/")
	var repo_root := ContentPaths.repo_root().replace("\\", "/")
	if normalized.is_absolute_path():
		if not normalized.begins_with(repo_root + "/"):
			return ""
		return normalized.substr(repo_root.length() + 1)
	return normalized.simplify_path()


func _path_from_status_line(line: String) -> String:
	if line.length() < 4:
		return ""
	var value := line.substr(3).strip_edges()
	if value.find(" -> ") >= 0:
		value = value.split(" -> ", false)[-1]
	return value.replace("\\", "/")


func _first_line(raw: String) -> String:
	var lines := raw.split("\n", false)
	if lines.is_empty():
		return ""
	return lines[0]


func _parse_numstat(raw: String) -> Dictionary:
	var first := _first_line(raw)
	var parts := first.split("\t", false)
	if parts.size() < 2:
		parts = first.split(" ", false)
	if parts.size() < 2:
		return {"added": 0, "removed": 0}
	return {
		"added": int(parts[0]),
		"removed": int(parts[1]),
	}


func _changed_hunk_count(raw: String) -> int:
	var count := 0
	for line in raw.split("\n", false):
		if line.begins_with("@@"):
			count += 1
	return count


func _normalize_status_code(status_line: String) -> String:
	var code := status_line.substr(0, min(2, status_line.length()))
	match code:
		" M", "M ", "MM":
			return "modified"
		"A ", "AM":
			return "added"
		"R ", "RM":
			return "renamed"
		" D", "D ":
			return "deleted"
		_:
			return "changed(%s)" % code.strip_edges()


func _failed(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": "failed",
		"code": code,
		"message": message,
	}
