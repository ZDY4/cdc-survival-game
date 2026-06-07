extends SceneTree

const ContentPaths = preload("res://scripts/data/content_paths.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentCliDomains = preload("res://scripts/tools/content_cli_domains.gd")
const ContentDiffSummary = preload("res://scripts/tools/content_diff_summary.gd")
const ContentJsonFormatter = preload("res://scripts/tools/content_json_formatter.gd")
const ContentRecordCliCommands = preload("res://scripts/tools/content_record_cli_commands.gd")

var _record_commands := ContentRecordCliCommands.new()


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
			exit_code = _record_commands.validate_command(args, registry)
		"locate":
			var registry: ContentRegistry = _load_registry_or_null()
			if registry == null:
				quit(1)
				return
			exit_code = _record_commands.locate_command(args, registry)
		"summarize":
			var registry: ContentRegistry = _load_registry_or_null()
			if registry == null:
				quit(1)
				return
			exit_code = _record_commands.summarize_command(args, registry)
		"references":
			var registry: ContentRegistry = _load_registry_or_null()
			if registry == null:
				quit(1)
				return
			exit_code = _record_commands.references_command(args, registry)
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

	var summary: Dictionary = ContentDiffSummary.new().summarize_path(args[2])
	if not bool(summary.get("ok", false)):
		printerr(summary.get("message", "diff summary failed"))
		return 1
	print("mode: diff_summary")
	print("path: %s" % summary.get("path", ""))
	print("status: %s" % summary.get("status", ""))
	print("added_lines: %d" % int(summary.get("added_lines", 0)))
	print("removed_lines: %d" % int(summary.get("removed_lines", 0)))
	print("changed_hunks: %d" % int(summary.get("changed_hunks", 0)))
	return 0


func _format_record(domain: String, id_value: String, record: Dictionary) -> Dictionary:
	var path: String = str(record.get("path", ""))
	var format_result := ContentJsonFormatter.write_formatted_file(path)
	if not bool(format_result.get("ok", false)):
		printerr(format_result.get("message", "failed to format JSON text: %s" % path))
		return {}
	return {
		"kind": _singular_domain(domain),
		"id": id_value,
		"relative_path": _repo_relative_path(path),
		"changed": bool(format_result.get("changed", false)),
	}


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
	var paths: Array[String] = []
	for path in ContentDiffSummary.new().changed_paths(ContentCliDomains.git_status_paths_for_format()):
		if not path.is_empty() and _domain_for_relative_path(path) != "":
			paths.append(path)
	return paths


func _domain_for_relative_path(relative_path: String) -> String:
	return ContentCliDomains.domain_for_relative_path(relative_path)


func _normalize_domain(kind: String) -> String:
	match kind:
		"item":
			return "items"
		"character":
			return "characters"
		"dialogue":
			return "dialogues"
		"dialogue_rule":
			return "dialogue_rules"
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
		"shop":
			return "shops"
		"world_tile":
			return "world_tiles"
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
		"dialogue_rules":
			return "dialogue_rule"
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
		"shops":
			return "shop"
		"world_tiles":
			return "world_tile"
		_:
			return domain


func _repo_relative_path(path: String) -> String:
	var normalized: String = path.replace("\\", "/")
	var marker := "/data/"
	var index := normalized.find(marker)
	if index >= 0:
		return normalized.substr(index + 1)
	return normalized


func _usage() -> String:
	return "usage: content_cli <locate|validate|summarize|references|format> <item|recipe|character|dialogue|dialogue_rule|quest|skill|skill_tree|settlement|overworld|map|shop|world_tile|appearance> <id> | content_cli validate changed | content_cli format changed | content_cli diff-summary --path <repo-relative-or-absolute-path>"
