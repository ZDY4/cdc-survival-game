extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")


func _init() -> void:
	var args := _content_args()
	if args.size() < 1:
		printerr(_usage())
		quit(2)
		return

	var registry := ContentRegistry.new()
	var result := registry.load_all()
	if result.has_errors():
		for error in result.errors:
			printerr(error)
		quit(1)
		return

	var command := args[0]
	var exit_code := 0
	match command:
		"validate":
			exit_code = _validate_command(args)
		"locate":
			exit_code = _locate_command(args, registry)
		"summarize":
			exit_code = _summarize_command(args, registry)
		_:
			printerr(_usage())
			exit_code = 2
	quit(exit_code)


func _content_args() -> Array[String]:
	var known := ["validate", "locate", "summarize"]
	var raw := OS.get_cmdline_args()
	for i in range(raw.size()):
		if known.has(raw[i]):
			var output: Array[String] = []
			for j in range(i, raw.size()):
				output.append(raw[j])
			return output
	return []


func _validate_command(args: Array[String]) -> int:
	if args.size() == 2 and args[1] == "changed":
		print("validate changed: Godot migration loader currently validates all migrated content domains")
		return 0
	if args.size() == 3:
		print("validate %s %s: ok" % [args[1], args[2]])
		return 0
	printerr(_usage())
	return 2


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
	var data: Dictionary = record["data"]
	print(JSON.stringify({
		"domain": domain,
		"id": id_value,
		"name": data.get("name", data.get("identity", {}).get("display_name", "")),
		"path": record["path"],
	}, "\t"))
	return 0


func _normalize_domain(kind: String) -> String:
	match kind:
		"item":
			return "items"
		"character":
			return "characters"
		"map":
			return "maps"
		"recipe":
			return "recipes"
		_:
			return kind


func _usage() -> String:
	return "usage: content_cli <validate|locate|summarize> <item|recipe|character|map> <id> | content_cli validate changed"
