extends SceneTree

const ContentPaths = preload("res://scripts/data/content_paths.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentCliDomains = preload("res://scripts/tools/content_cli_domains.gd")
const ContentReferenceIndex = preload("res://scripts/tools/content_reference_index.gd")
const ContentRecordValidator = preload("res://scripts/tools/content_record_validator.gd")
const ContentSummaryPresenter = preload("res://scripts/tools/content_summary_presenter.gd")


func _init() -> void:
	var args := _content_args()
	if args.size() < 1:
		printerr(_usage())
		quit(2)
		return

	var command := args[0]
	var exit_code := 0
	match command:
		"diff-summary":
			exit_code = _diff_summary_command(args)
		"validate":
			var registry: ContentRegistry = _load_registry_or_null()
			if registry == null:
				quit(1)
				return
			exit_code = _validate_command(args, registry)
		"locate":
			var registry: ContentRegistry = _load_registry_or_null()
			if registry == null:
				quit(1)
				return
			exit_code = _locate_command(args, registry)
		"summarize":
			var registry: ContentRegistry = _load_registry_or_null()
			if registry == null:
				quit(1)
				return
			exit_code = _summarize_command(args, registry)
		"references":
			var registry: ContentRegistry = _load_registry_or_null()
			if registry == null:
				quit(1)
				return
			exit_code = _references_command(args, registry)
		"format":
			var registry: ContentRegistry = _load_registry_or_null()
			if registry == null:
				quit(1)
				return
			exit_code = _format_command(args, registry)
		_:
			printerr(_usage())
			exit_code = 2
	quit(exit_code)


func _content_args() -> Array[String]:
	var known := ["validate", "locate", "summarize", "references", "format", "diff-summary"]
	var raw := OS.get_cmdline_user_args()
	if raw.is_empty():
		raw = OS.get_cmdline_args()
	for i in range(raw.size()):
		if known.has(raw[i]):
			var output: Array[String] = []
			for j in range(i, raw.size()):
				output.append(raw[j])
			return output
	return []


func _load_registry_or_null() -> ContentRegistry:
	var registry: ContentRegistry = ContentRegistry.new()
	var result := registry.load_all()
	if result.has_errors():
		for error in result.errors:
			printerr(error)
		return null
	return registry


func _validate_command(args: Array[String], registry: ContentRegistry) -> int:
	if args.size() == 2 and args[1] == "changed":
		return _validate_changed_command(registry)
	if args.size() == 3:
		var domain := _normalize_domain(args[1])
		var id_value := ContentRegistry.normalize_content_id(args[2])
		var record: Dictionary = registry.get_library(domain).get(id_value, {})
		if record.is_empty():
			printerr("not found: %s %s" % [args[1], id_value])
			return 1
		return _print_validation(args[1], domain, id_value, record, registry)
	printerr(_usage())
	return 2


func _validate_changed_command(registry: ContentRegistry) -> int:
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var checked_records := 0
	var invalid_records := 0
	print("mode: validate_changed")
	print("domains: %s" % ContentCliDomains.format_domain_names())
	for domain in ContentCliDomains.VALIDATE_CHANGED_DOMAINS:
		for id_value in registry.get_library(domain).keys():
			var id_string := str(id_value)
			var record: Dictionary = registry.get_library(domain).get(id_string, {})
			var validation := validator.validate_record(domain, id_string, registry)
			checked_records += 1
			if not bool(validation.get("ok", false)):
				invalid_records += 1
				print("- [%s] %s @ %s" % [_singular_domain(domain), id_string, _repo_relative_path(str(record.get("path", "")))])
				for issue in validation.get("issues", []):
					var data: Dictionary = _dictionary_or_empty(issue)
					print("  - [%s] %s: %s (%s)" % [
						data.get("severity", "error"),
						data.get("code", "validation_error"),
						data.get("message", ""),
						data.get("field", "$"),
					])
	print("checked_records: %d" % checked_records)
	print("invalid_records: %d" % invalid_records)
	print("status: %s" % ("ok" if invalid_records == 0 else "invalid"))
	return 0 if invalid_records == 0 else 2


func _locate_command(args: Array[String], registry: ContentRegistry) -> int:
	if args.size() != 3:
		printerr(_usage())
		return 2
	var domain := _normalize_domain(args[1])
	var id_value := ContentRegistry.normalize_content_id(args[2])
	var record: Dictionary = registry.get_library(domain).get(id_value, {})
	if record.is_empty():
		printerr("not found: %s %s" % [args[1], id_value])
		return 1
	print(record.get("path", ""))
	return 0


func _summarize_command(args: Array[String], registry: ContentRegistry) -> int:
	if args.size() != 3:
		printerr(_usage())
		return 2
	var domain := _normalize_domain(args[1])
	var id_value := ContentRegistry.normalize_content_id(args[2])
	var record: Dictionary = registry.get_library(domain).get(id_value, {})
	if record.is_empty():
		printerr("not found: %s %s" % [args[1], id_value])
		return 1
	_print_summary(domain, id_value, record)
	return 0


func _references_command(args: Array[String], registry: ContentRegistry) -> int:
	if args.size() != 3:
		printerr(_usage())
		return 2
	var kind: String = args[1]
	var domain := _normalize_domain(kind)
	var id_value := ContentRegistry.normalize_content_id(args[2])
	var record: Dictionary = registry.get_library(domain).get(id_value, {})
	if record.is_empty():
		printerr("not found: %s %s" % [kind, id_value])
		return 1

	var reference_index: ContentReferenceIndex = ContentReferenceIndex.new()
	if not reference_index.supports_domain(domain):
		printerr("references currently supports %s, got %s" % [_reference_domain_list(), kind])
		return 2
	_print_references(kind, id_value, record.get("path", ""), reference_index.references_for(domain, id_value, registry))
	return 0


func _format_command(args: Array[String], registry: ContentRegistry) -> int:
	if args.size() == 2 and args[1] == "changed":
		return _format_changed_command(registry)
	if args.size() != 3:
		printerr(_usage())
		return 2

	var domain := _normalize_domain(args[1])
	var id_value := ContentRegistry.normalize_content_id(args[2])
	var record: Dictionary = registry.get_library(domain).get(id_value, {})
	if record.is_empty():
		printerr("not found: %s %s" % [args[1], id_value])
		return 1
	if not ContentCliDomains.supports_format_domain(domain):
		printerr("format currently supports %s, got %s" % [ContentCliDomains.format_domain_names(), args[1]])
		return 2

	var report: Dictionary = _format_record(domain, id_value, record)
	print("mode: format")
	print("kind: %s" % _singular_domain(domain))
	print("id: %s" % id_value)
	print("relative_path: %s" % report.get("relative_path", ""))
	print("changed: %s" % str(report.get("changed", false)).to_lower())
	return 0


func _format_changed_command(registry: ContentRegistry) -> int:
	var paths := _changed_supported_paths()
	print("mode: format_changed")
	print("changed_supported_files: %d" % paths.size())
	if paths.is_empty():
		print("status: no_supported_changes")
		return 0

	var rewritten_files := 0
	for relative_path in paths:
		var report: Dictionary = _format_relative_path(relative_path, registry)
		if report.is_empty():
			printerr("unsupported changed content path: %s" % relative_path)
			return 1
		if bool(report.get("changed", false)):
			rewritten_files += 1
		print("- [%s] %s %s @ %s" % [
			"changed" if bool(report.get("changed", false)) else "unchanged",
			report.get("kind", ""),
			report.get("id", ""),
			report.get("relative_path", ""),
		])
	print("rewritten_files: %d" % rewritten_files)
	print("status: ok")
	return 0


func _diff_summary_command(args: Array[String]) -> int:
	if args.size() != 3 or args[1] != "--path":
		printerr(_usage())
		return 2

	var relative_path := _normalize_repo_path(args[2])
	if relative_path.is_empty():
		printerr("path is outside repo root: %s" % args[2])
		return 1

	var status_output := _git_output(["status", "--short", "--untracked-files=all", "--", relative_path])
	if int(status_output.get("exit_code", 1)) != 0:
		printerr(status_output.get("error", "git status failed"))
		return 1
	var status_line := _first_line(str(status_output.get("stdout", ""))).strip_edges()

	print("mode: diff_summary")
	print("path: %s" % relative_path)
	if status_line.is_empty():
		print("status: clean")
		print("added_lines: 0")
		print("removed_lines: 0")
		print("changed_hunks: 0")
		return 0
	if status_line.begins_with("??"):
		var raw := FileAccess.get_file_as_string(ContentPaths.repo_root().path_join(relative_path))
		print("status: untracked")
		print("added_lines: %d" % raw.split("\n", false).size())
		print("removed_lines: 0")
		print("changed_hunks: 1")
		return 0

	var numstat := _git_output(["diff", "--numstat", "HEAD", "--", relative_path])
	if int(numstat.get("exit_code", 1)) != 0:
		printerr(numstat.get("error", "git diff --numstat failed"))
		return 1
	var counts := _parse_numstat(str(numstat.get("stdout", "")))
	var diff := _git_output(["diff", "--no-ext-diff", "--unified=0", "HEAD", "--", relative_path])
	if int(diff.get("exit_code", 1)) != 0:
		printerr(diff.get("error", "git diff failed"))
		return 1

	print("status: %s" % _normalize_status_code(status_line))
	print("added_lines: %d" % int(counts.get("added", 0)))
	print("removed_lines: %d" % int(counts.get("removed", 0)))
	print("changed_hunks: %d" % _changed_hunk_count(str(diff.get("stdout", ""))))
	return 0


func _print_summary(domain: String, id_value: String, record: Dictionary) -> void:
	var presenter: ContentSummaryPresenter = ContentSummaryPresenter.new()
	presenter.print_summary(domain, id_value, record, _repo_relative_path(str(record.get("path", ""))))


func _print_references(kind: String, id_value: String, path: String, hits: Array[Dictionary]) -> void:
	print("kind: %s" % kind)
	print("id: %s" % id_value)
	print("relative_path: %s" % _repo_relative_path(path))
	print("reference_count: %d" % hits.size())
	if hits.is_empty():
		print("status: no_references_found")
		return
	for hit in hits:
		print("- %s %s @ %s [%s]" % [
			hit.get("source_kind", ""),
			hit.get("source_id", ""),
			_repo_relative_path(str(hit.get("path", ""))),
			hit.get("detail", ""),
		])


func _print_validation(kind: String, domain: String, id_value: String, record: Dictionary, registry: ContentRegistry) -> int:
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var validation := validator.validate_record(domain, id_value, registry)
	var issues: Array = validation.get("issues", [])
	print("kind: %s" % _singular_domain(domain))
	print("id: %s" % id_value)
	print("relative_path: %s" % _repo_relative_path(str(record.get("path", ""))))
	print("status: %s" % validation.get("status", "invalid"))
	if not validator.supports_domain(domain):
		print("- [warning] shallow_validation: validate currently checks existence only for %s" % kind)
	for issue in issues:
		var data: Dictionary = _dictionary_or_empty(issue)
		print("- [%s] %s: %s (%s)" % [
			data.get("severity", "error"),
			data.get("code", "validation_error"),
			data.get("message", ""),
			data.get("field", "$"),
		])
	return 0 if bool(validation.get("ok", false)) else 2


func _format_record(domain: String, id_value: String, record: Dictionary) -> Dictionary:
	var path: String = str(record.get("path", ""))
	var before := FileAccess.get_file_as_string(path)
	var formatted := _format_json_text(before)
	if formatted.is_empty():
		printerr("failed to format JSON text: %s" % path)
		return {}
	var changed := before != formatted
	if changed:
		# 内容格式化是 agent 复核入口，写入失败必须带路径，方便直接定位坏文件。
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			printerr("failed to open for write: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			return {}
		file.store_string(formatted)
	return {
		"kind": _singular_domain(domain),
		"id": id_value,
		"relative_path": _repo_relative_path(path),
		"changed": changed,
	}


func _format_json_text(raw: String) -> String:
	var output := ""
	var depth := 0
	var in_string := false
	var escaped := false
	var pending_space := false
	for i in range(raw.length()):
		var ch := raw.substr(i, 1)
		if in_string:
			output += ch
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == "\"":
				in_string = false
			continue

		match ch:
			" ", "\t", "\n", "\r":
				continue
			"\"":
				if pending_space:
					output += " "
					pending_space = false
				output += ch
				in_string = true
			"{", "[":
				if pending_space:
					output += " "
					pending_space = false
				output += ch
				depth += 1
				output += "\n" + _indent(depth)
			"}", "]":
				pending_space = false
				depth -= 1
				if depth < 0:
					return ""
				output = output.rstrip(" \t\r\n")
				output += "\n" + _indent(depth) + ch
			",":
				pending_space = false
				output += ch + "\n" + _indent(depth)
			":":
				output = output.rstrip(" \t\r\n")
				output += ": "
				pending_space = false
			_:
				if pending_space:
					output += " "
					pending_space = false
				output += ch
				var next_index := i + 1
				if next_index < raw.length():
					var next := raw.substr(next_index, 1)
					if next in [" ", "\t", "\n", "\r"]:
						pending_space = true
	if in_string or depth != 0:
		return ""
	return output.rstrip(" \t\r\n") + "\n"


func _indent(depth: int) -> String:
	return "  ".repeat(max(0, depth))


func _format_relative_path(relative_path: String, registry: ContentRegistry) -> Dictionary:
	var path_domain := _domain_for_relative_path(relative_path)
	if path_domain.is_empty():
		return {}
	var full_path := ContentPaths.repo_root().path_join(relative_path)
	for id_value in registry.get_library(path_domain).keys():
		var record: Dictionary = registry.get_library(path_domain)[id_value]
		if str(record.get("path", "")).replace("\\", "/") == full_path.replace("\\", "/"):
			return _format_record(path_domain, id_value, record)
	return {}


func _changed_supported_paths() -> Array[String]:
	var git_args: Array[String] = ["status", "--short", "--untracked-files=all", "--"]
	git_args.append_array(ContentCliDomains.git_status_paths_for_format())
	var status := _git_output(git_args)
	var paths: Array[String] = []
	if int(status.get("exit_code", 1)) != 0:
		printerr(status.get("error", "git status failed"))
		return paths
	for line in str(status.get("stdout", "")).split("\n", false):
		var path := _path_from_status_line(line)
		if not path.is_empty() and _domain_for_relative_path(path) != "":
			paths.append(path)
	paths.sort()
	return paths


func _path_from_status_line(line: String) -> String:
	if line.length() < 4:
		return ""
	var value := line.substr(3).strip_edges()
	if value.find(" -> ") >= 0:
		value = value.split(" -> ", false)[-1]
	return value.replace("\\", "/")


func _domain_for_relative_path(relative_path: String) -> String:
	return ContentCliDomains.domain_for_relative_path(relative_path)


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


func _normalize_domain(kind: String) -> String:
	match kind:
		"item":
			return "items"
		"character":
			return "characters"
		"dialogue":
			return "dialogues"
		"map":
			return "maps"
		"quest":
			return "quests"
		"recipe":
			return "recipes"
		"skill":
			return "skills"
		"skill_tree":
			return "skill_trees"
		"settlement":
			return "settlements"
		_:
			return kind


func _singular_domain(domain: String) -> String:
	match domain:
		"items":
			return "item"
		"characters":
			return "character"
		"dialogues":
			return "dialogue"
		"maps":
			return "map"
		"quests":
			return "quest"
		"recipes":
			return "recipe"
		"skills":
			return "skill"
		"skill_trees":
			return "skill_tree"
		"settlements":
			return "settlement"
		_:
			return domain


func _repo_relative_path(path: String) -> String:
	var normalized: String = path.replace("\\", "/")
	var marker := "/data/"
	var index := normalized.find(marker)
	if index >= 0:
		return normalized.substr(index + 1)
	return normalized


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _reference_domain_list() -> String:
	return "item, recipe, character, dialogue, quest, skill, settlement, overworld, and map"


func _usage() -> String:
	return "usage: content_cli <locate|validate|summarize|references|format> <item|recipe|character|dialogue|quest|skill|skill_tree|settlement|overworld|map> <id> | content_cli validate changed | content_cli format changed | content_cli diff-summary --path <repo-relative-or-absolute-path>"
