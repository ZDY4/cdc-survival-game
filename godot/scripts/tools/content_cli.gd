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
		"references":
			exit_code = _references_command(args, registry)
		_:
			printerr(_usage())
			exit_code = 2
	quit(exit_code)


func _content_args() -> Array[String]:
	var known := ["validate", "locate", "summarize", "references"]
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

	match domain:
		"items":
			_print_references(kind, id_value, record.get("path", ""), _item_references(id_value, registry))
			return 0
		"maps":
			_print_references(kind, id_value, record.get("path", ""), _map_references(id_value, registry))
			return 0
		_:
			printerr("references currently supports item and map, got %s" % kind)
			return 2


func _print_summary(domain: String, id_value: String, record: Dictionary) -> void:
	var data: Dictionary = record["data"]
	print("kind: %s" % _singular_domain(domain))
	print("id: %s" % id_value)
	print("relative_path: %s" % _repo_relative_path(str(record.get("path", ""))))
	match domain:
		"items":
			print("name: %s" % data.get("name", ""))
			print("value: %d" % int(data.get("value", 0)))
			print("weight: %.2f" % float(data.get("weight", 0.0)))
			var fragment_kinds: Array[String] = []
			for fragment in data.get("fragments", []):
				var fragment_data: Dictionary = _dictionary_or_empty(fragment)
				fragment_kinds.append(str(fragment_data.get("kind", "")))
			print("fragment_count: %d" % fragment_kinds.size())
			print("fragment_kinds: %s" % _join_or_dash(fragment_kinds))
		"recipes":
			var output: Dictionary = _dictionary_or_empty(data.get("output", {}))
			print("name: %s" % data.get("name", ""))
			print("output_item_id: %s" % ContentRegistry.normalize_content_id(output.get("item_id", "")))
			print("output_count: %d" % int(output.get("count", 0)))
			print("materials_count: %d" % data.get("materials", []).size())
			print("required_tools_count: %d" % data.get("required_tools", []).size())
			print("optional_tools_count: %d" % data.get("optional_tools", []).size())
		"characters":
			var identity: Dictionary = _dictionary_or_empty(data.get("identity", {}))
			var faction: Dictionary = _dictionary_or_empty(data.get("faction", {}))
			var combat: Dictionary = _dictionary_or_empty(data.get("combat", {}))
			var progression: Dictionary = _dictionary_or_empty(data.get("progression", {}))
			print("display_name: %s" % identity.get("display_name", ""))
			print("archetype: %s" % data.get("archetype", ""))
			print("camp_id: %s" % faction.get("camp_id", ""))
			print("disposition: %s" % faction.get("disposition", ""))
			print("behavior: %s" % combat.get("behavior", ""))
			print("level: %d" % int(progression.get("level", 0)))
			print("loot_entries: %d" % combat.get("loot", []).size())
		"maps":
			var size: Dictionary = _dictionary_or_empty(data.get("size", {}))
			print("name: %s" % data.get("name", ""))
			print("size: %dx%d" % [int(size.get("width", 0)), int(size.get("height", 0))])
			print("default_level: %d" % int(data.get("default_level", 0)))
			print("level_count: %d" % data.get("levels", []).size())
			print("entry_points: %d" % data.get("entry_points", []).size())
			print("objects: %d" % data.get("objects", []).size())
			print("object_kinds: %s" % _map_object_kind_counts(data))


func _item_references(item_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for recipe_id in registry.get_library("recipes").keys():
		var record: Dictionary = registry.get_library("recipes")[recipe_id]
		var data: Dictionary = record["data"]
		var output: Dictionary = _dictionary_or_empty(data.get("output", {}))
		if ContentRegistry.normalize_content_id(output.get("item_id", "")) == item_id:
			hits.append(_reference_hit("recipe", recipe_id, record["path"], "output.item_id"))
		for i in range(data.get("materials", []).size()):
			var material: Dictionary = _dictionary_or_empty(data["materials"][i])
			if ContentRegistry.normalize_content_id(material.get("item_id", "")) == item_id:
				hits.append(_reference_hit("recipe", recipe_id, record["path"], "materials[%d].item_id" % i))
		_collect_tool_refs(hits, item_id, "recipe", recipe_id, record["path"], "required_tools", data.get("required_tools", []))
		_collect_tool_refs(hits, item_id, "recipe", recipe_id, record["path"], "optional_tools", data.get("optional_tools", []))

	for source_item_id in registry.get_library("items").keys():
		var record: Dictionary = registry.get_library("items")[source_item_id]
		var data: Dictionary = record["data"]
		var fragments: Array = data.get("fragments", [])
		for fragment_index in range(fragments.size()):
			var fragment: Dictionary = _dictionary_or_empty(fragments[fragment_index])
			match str(fragment.get("kind", "")):
				"weapon":
					if ContentRegistry.normalize_content_id(fragment.get("ammo_type", "")) == item_id:
						hits.append(_reference_hit("item", source_item_id, record["path"], "fragments[%d].weapon.ammo_type" % fragment_index))
				"crafting":
					var crafting_recipe: Dictionary = _dictionary_or_empty(fragment.get("crafting_recipe", {}))
					var materials: Array = crafting_recipe.get("materials", [])
					for material_index in range(materials.size()):
						var material: Dictionary = _dictionary_or_empty(materials[material_index])
						if ContentRegistry.normalize_content_id(material.get("item_id", "")) == item_id:
							hits.append(_reference_hit("item", source_item_id, record["path"], "fragments[%d].crafting.crafting_recipe.materials[%d].item_id" % [fragment_index, material_index]))
					var yields: Array = fragment.get("deconstruct_yield", [])
					for yield_index in range(yields.size()):
						var yield_item: Dictionary = _dictionary_or_empty(yields[yield_index])
						if ContentRegistry.normalize_content_id(yield_item.get("item_id", "")) == item_id:
							hits.append(_reference_hit("item", source_item_id, record["path"], "fragments[%d].crafting.deconstruct_yield[%d].item_id" % [fragment_index, yield_index]))

	for character_id in registry.get_library("characters").keys():
		var record: Dictionary = registry.get_library("characters")[character_id]
		var combat: Dictionary = _dictionary_or_empty(record["data"].get("combat", {}))
		var loot: Array = combat.get("loot", [])
		for i in range(loot.size()):
			var entry: Dictionary = _dictionary_or_empty(loot[i])
			if ContentRegistry.normalize_content_id(entry.get("item_id", "")) == item_id:
				hits.append(_reference_hit("character", character_id, record["path"], "combat.loot[%d].item_id" % i))

	for map_id in registry.get_library("maps").keys():
		var record: Dictionary = registry.get_library("maps")[map_id]
		var objects: Array = record["data"].get("objects", [])
		for object_index in range(objects.size()):
			var object: Dictionary = _dictionary_or_empty(objects[object_index])
			var props: Dictionary = _dictionary_or_empty(object.get("props", {}))
			var pickup: Dictionary = _dictionary_or_empty(props.get("pickup", {}))
			if ContentRegistry.normalize_content_id(pickup.get("item_id", "")) == item_id:
				hits.append(_reference_hit("map", map_id, record["path"], "objects[%d].props.pickup.item_id" % object_index))
			var container: Dictionary = _dictionary_or_empty(props.get("container", {}))
			var inventory: Array = container.get("initial_inventory", [])
			for item_index in range(inventory.size()):
				var entry: Dictionary = _dictionary_or_empty(inventory[item_index])
				if ContentRegistry.normalize_content_id(entry.get("item_id", "")) == item_id:
					hits.append(_reference_hit("map", map_id, record["path"], "objects[%d].props.container.initial_inventory[%d].item_id" % [object_index, item_index]))
	return hits


func _map_references(map_id: String, registry: ContentRegistry) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for overworld_id in registry.get_library("overworld").keys():
		var record: Dictionary = registry.get_library("overworld")[overworld_id]
		var locations: Array = record["data"].get("locations", [])
		for i in range(locations.size()):
			var location: Dictionary = _dictionary_or_empty(locations[i])
			if str(location.get("map_id", "")) == map_id:
				hits.append(_reference_hit("overworld", overworld_id, record["path"], "locations[%d] id=%s entry_point_id=%s kind=%s" % [
					i,
					location.get("id", ""),
					location.get("entry_point_id", ""),
					location.get("kind", ""),
				]))
	return hits


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


func _reference_hit(source_kind: String, source_id: String, path: String, detail: String) -> Dictionary:
	return {
		"source_kind": source_kind,
		"source_id": source_id,
		"path": path,
		"detail": detail,
	}


func _collect_tool_refs(hits: Array[Dictionary], item_id: String, source_kind: String, source_id: String, path: String, field: String, values: Array) -> void:
	for i in range(values.size()):
		if ContentRegistry.normalize_content_id(values[i]) == item_id:
			hits.append(_reference_hit(source_kind, source_id, path, "%s[%d]" % [field, i]))


func _map_object_kind_counts(data: Dictionary) -> String:
	var counts: Dictionary = {}
	for object in data.get("objects", []):
		var object_data: Dictionary = _dictionary_or_empty(object)
		var kind: String = str(object_data.get("kind", ""))
		counts[kind] = int(counts.get(kind, 0)) + 1
	var parts: Array[String] = []
	for kind in counts.keys():
		parts.append("%s=%d" % [kind, int(counts[kind])])
	parts.sort()
	return _join_or_dash(parts)


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


func _singular_domain(domain: String) -> String:
	match domain:
		"items":
			return "item"
		"characters":
			return "character"
		"maps":
			return "map"
		"recipes":
			return "recipe"
		_:
			return domain


func _join_or_dash(values: Array[String]) -> String:
	if values.is_empty():
		return "-"
	return ", ".join(values)


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


func _usage() -> String:
	return "usage: content_cli <validate|locate|summarize|references> <item|recipe|character|map> <id> | content_cli validate changed"
