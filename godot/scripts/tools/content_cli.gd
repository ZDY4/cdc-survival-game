extends SceneTree

const ContentPaths = preload("res://scripts/data/content_paths.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentCliDomains = preload("res://scripts/tools/content_cli_domains.gd")
const ContentDiffSummary = preload("res://scripts/tools/content_diff_summary.gd")
const ContentJsonFormatter = preload("res://scripts/tools/content_json_formatter.gd")
const ContentRecordCliCommands = preload("res://scripts/tools/content_record_cli_commands.gd")
const ContentAssetManifest = preload("res://scripts/tools/content_asset_manifest.gd")

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
		"asset-manifest":
			var registry: ContentRegistry = _load_registry_or_null()
			if registry == null:
				quit(1)
				return
			exit_code = _asset_manifest_command(args, registry)
		_:
			printerr(_usage())
			exit_code = 2
	quit(exit_code)


func _content_args() -> Array[String]:
	var known := ["validate", "locate", "summarize", "references", "format", "diff-summary", "asset-manifest"]
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
	var options := _parse_format_options(args)
	var positional: Array[String] = options.get("args", [])
	var dry_run := bool(options.get("dry_run", false))
	if positional.size() == 2 and positional[1] == "changed":
		return _format_changed_command(registry, dry_run)
	if positional.size() != 3:
		printerr(_usage())
		return 2

	var domain := _normalize_domain(positional[1])
	var id_value := ContentRegistry.normalize_content_id(positional[2])
	var record: Dictionary = registry.get_library(domain).get(id_value, {})
	if record.is_empty():
		printerr("not found: %s %s" % [positional[1], id_value])
		return 1
	if not ContentCliDomains.supports_format_domain(domain):
		printerr("format currently supports %s, got %s" % [ContentCliDomains.format_domain_names(), positional[1]])
		return 2

	var report: Dictionary = _format_record(domain, id_value, record, {"dry_run": dry_run})
	print("mode: format")
	print("kind: %s" % _singular_domain(domain))
	print("id: %s" % id_value)
	print("relative_path: %s" % report.get("relative_path", ""))
	print("changed: %s" % str(report.get("changed", false)).to_lower())
	print("dry_run: %s" % str(report.get("dry_run", false)).to_lower())
	return 0


func _format_changed_command(registry: ContentRegistry, dry_run: bool = false) -> int:
	var paths := _changed_supported_paths()
	print("mode: format_changed")
	print("dry_run: %s" % str(dry_run).to_lower())
	print("changed_supported_files: %d" % paths.size())
	if paths.is_empty():
		if dry_run:
			print("would_rewrite_files: 0")
		print("status: no_supported_changes")
		return 0

	var rewritten_files := 0
	var would_rewrite_files := 0
	for relative_path in paths:
		var report: Dictionary = _format_relative_path(relative_path, registry, {"dry_run": dry_run})
		if report.is_empty():
			printerr("unsupported changed content path: %s" % relative_path)
			return 1
		if bool(report.get("changed", false)):
			would_rewrite_files += 1
			if not dry_run:
				rewritten_files += 1
		var label := "unchanged"
		if bool(report.get("changed", false)):
			label = "would_change" if dry_run else "changed"
		print("- [%s] %s %s @ %s" % [
			label,
			report.get("kind", ""),
			report.get("id", ""),
			report.get("relative_path", ""),
		])
	print("rewritten_files: %d" % rewritten_files)
	if dry_run:
		print("would_rewrite_files: %d" % would_rewrite_files)
	print("status: ok")
	return 0


func _diff_summary_command(args: Array[String]) -> int:
	if args.size() == 2 and args[1] == "changed":
		return _diff_summary_changed_command()
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


func _diff_summary_changed_command() -> int:
	var entries: Array[Dictionary] = []
	for changed_entry in ContentDiffSummary.new().changed_path_entries(ContentCliDomains.git_status_paths_for_validate()):
		var path := str(changed_entry.get("path", "")).replace("\\", "/").simplify_path()
		if path.is_empty() or ContentCliDomains.validate_domain_for_relative_path(path).is_empty():
			continue
		var summary: Dictionary = ContentDiffSummary.new().summarize_path(path)
		if not bool(summary.get("ok", false)):
			printerr(summary.get("message", "diff summary failed"))
			return 1
		summary["source_path"] = str(changed_entry.get("source_path", ""))
		summary["status_code"] = str(changed_entry.get("status_code", ""))
		entries.append(summary)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("path", "")) < str(b.get("path", ""))
	)
	print("mode: diff_summary_changed")
	print("changed_supported_files: %d" % entries.size())
	if entries.is_empty():
		print("total_added_lines: 0")
		print("total_removed_lines: 0")
		print("total_changed_hunks: 0")
		print("status: no_supported_changes")
		return 0

	for summary in entries:
		var source_path := str(summary.get("source_path", ""))
		var source_suffix := " <- %s" % source_path if not source_path.is_empty() else ""
		print("- [%s] %s +%d -%d hunks:%d%s" % [
			str(summary.get("status", "")),
			str(summary.get("path", "")),
			int(summary.get("added_lines", 0)),
			int(summary.get("removed_lines", 0)),
			int(summary.get("changed_hunks", 0)),
			source_suffix,
		])
	var aggregate: Dictionary = ContentDiffSummary.new().aggregate_summaries(entries)
	print("total_added_lines: %d" % int(aggregate.get("total_added_lines", 0)))
	print("total_removed_lines: %d" % int(aggregate.get("total_removed_lines", 0)))
	print("total_changed_hunks: %d" % int(aggregate.get("total_changed_hunks", 0)))
	print("status: ok")
	return 0


func _asset_manifest_command(args: Array[String], registry: ContentRegistry) -> int:
	if args.size() != 2 or args[1] != "all":
		printerr(_usage())
		return 2
	var manifest := ContentAssetManifest.new().build(registry)
	print("mode: asset_manifest")
	print("status: ok")
	print("entry_count: %d" % int(manifest.get("entry_count", 0)))
	print("unique_asset_count: %d" % int(manifest.get("unique_asset_count", 0)))
	print("missing_count: %d" % int(manifest.get("missing_count", 0)))
	print("invalid_count: %d" % int(manifest.get("invalid_count", 0)))
	print("manifest_json: %s" % JSON.stringify(manifest))
	return 0


func _format_record(domain: String, id_value: String, record: Dictionary, options: Dictionary = {}) -> Dictionary:
	var path: String = str(record.get("path", ""))
	var format_result := ContentJsonFormatter.write_formatted_file(path, options)
	if not bool(format_result.get("ok", false)):
		printerr(format_result.get("message", "failed to format JSON text: %s" % path))
		return {}
	return {
		"kind": _singular_domain(domain),
		"id": id_value,
		"relative_path": _repo_relative_path(path),
		"changed": bool(format_result.get("changed", false)),
		"dry_run": bool(format_result.get("dry_run", false)),
	}


func _format_relative_path(relative_path: String, registry: ContentRegistry, options: Dictionary = {}) -> Dictionary:
	var path_domain := _domain_for_relative_path(relative_path)
	if path_domain.is_empty():
		return {}
	var full_path := ContentPaths.repo_root().path_join(relative_path)
	for id_value in registry.get_library(path_domain).keys():
		var record: Dictionary = registry.get_library(path_domain)[id_value]
		if str(record.get("path", "")).replace("\\", "/") == full_path.replace("\\", "/"):
			return _format_record(path_domain, id_value, record, options)
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


func _parse_format_options(args: Array[String]) -> Dictionary:
	var positional: Array[String] = []
	var dry_run := false
	for arg in args:
		if arg == "--dry-run":
			dry_run = true
			continue
		positional.append(arg)
	return {
		"args": positional,
		"dry_run": dry_run,
	}


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
	return "usage: content_cli <locate|validate|summarize|references|format> <item|recipe|character|dialogue|dialogue_rule|quest|skill|skill_tree|settlement|overworld|map|shop|world_tile|appearance|ai|json> <id> | content_cli validate changed | content_cli format [--dry-run] changed | content_cli format [--dry-run] <kind> <id> | content_cli diff-summary changed | content_cli diff-summary --path <repo-relative-or-absolute-path> | content_cli asset-manifest all"
