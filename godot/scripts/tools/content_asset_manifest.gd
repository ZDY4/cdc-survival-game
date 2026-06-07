extends RefCounted

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")


func build(registry: RefCounted) -> Dictionary:
	var entries: Array[Dictionary] = []
	_collect_item_assets(entries, registry)
	_collect_dialogue_assets(entries, registry)
	_collect_skill_assets(entries, registry)
	_collect_overworld_assets(entries, registry)
	_collect_appearance_assets(entries, registry)
	_collect_world_tile_assets(entries, registry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := "%s/%s/%s" % [a.get("domain", ""), a.get("record_id", ""), a.get("field", "")]
		var right := "%s/%s/%s" % [b.get("domain", ""), b.get("record_id", ""), b.get("field", "")]
		return left < right
	)
	return {
		"schema_version": 1,
		"entry_count": entries.size(),
		"unique_asset_count": _unique_asset_count(entries),
		"missing_count": _count_where(entries, "exists", false),
		"invalid_count": _invalid_count(entries),
		"by_kind": _count_by_key(entries, "asset_kind"),
		"by_domain": _count_by_key(entries, "domain"),
		"entries": entries,
	}


func _collect_item_assets(entries: Array[Dictionary], registry: RefCounted) -> void:
	for item_id in _sorted_keys(registry.get_library("items")):
		var record: Dictionary = registry.get_library("items")[item_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		_add_media_entry(entries, "items", str(item_id), "icon_path", str(data.get("icon_path", "")), "item")
		var fragments: Array = _array_or_empty(data.get("fragments", []))
		for index in range(fragments.size()):
			var fragment: Dictionary = _dictionary_or_empty(fragments[index])
			if str(fragment.get("kind", "")) != "appearance":
				continue
			var definition: Dictionary = _dictionary_or_empty(fragment.get("definition", {}))
			_add_model_entry(entries, "items", str(item_id), "fragments[%d].definition.visual_asset" % index, str(definition.get("visual_asset", "")))


func _collect_dialogue_assets(entries: Array[Dictionary], registry: RefCounted) -> void:
	for dialogue_id in _sorted_keys(registry.get_library("dialogues")):
		var record: Dictionary = registry.get_library("dialogues")[dialogue_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var nodes: Array = _array_or_empty(data.get("nodes", []))
		for index in range(nodes.size()):
			var node: Dictionary = _dictionary_or_empty(nodes[index])
			_add_media_entry(entries, "dialogues", str(dialogue_id), "nodes[%d].portrait" % index, str(node.get("portrait", "")), "portrait")


func _collect_skill_assets(entries: Array[Dictionary], registry: RefCounted) -> void:
	for skill_id in _sorted_keys(registry.get_library("skills")):
		var record: Dictionary = registry.get_library("skills")[skill_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		_add_media_entry(entries, "skills", str(skill_id), "icon", str(data.get("icon", "")), "skill")


func _collect_overworld_assets(entries: Array[Dictionary], registry: RefCounted) -> void:
	for overworld_id in _sorted_keys(registry.get_library("overworld")):
		var record: Dictionary = registry.get_library("overworld")[overworld_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var locations: Array = _array_or_empty(data.get("locations", []))
		for index in range(locations.size()):
			var location: Dictionary = _dictionary_or_empty(locations[index])
			_add_media_entry(entries, "overworld", str(overworld_id), "locations[%d].icon" % index, str(location.get("icon", "")), "location")


func _collect_appearance_assets(entries: Array[Dictionary], registry: RefCounted) -> void:
	for appearance_id in _sorted_keys(registry.get_library("appearance")):
		var record: Dictionary = registry.get_library("appearance")[appearance_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		_add_model_entry(entries, "appearance", str(appearance_id), "base_model_asset", str(data.get("base_model_asset", "")))


func _collect_world_tile_assets(entries: Array[Dictionary], registry: RefCounted) -> void:
	for world_tile_id in _sorted_keys(registry.get_library("world_tiles")):
		var record: Dictionary = registry.get_library("world_tiles")[world_tile_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var prototypes: Array = _array_or_empty(data.get("prototypes", []))
		for index in range(prototypes.size()):
			var prototype: Dictionary = _dictionary_or_empty(prototypes[index])
			var source: Dictionary = _dictionary_or_empty(prototype.get("source", {}))
			if str(source.get("kind", "")) != "gltf_scene":
				continue
			var prototype_id := str(prototype.get("id", index))
			_add_model_entry(entries, "world_tiles", str(world_tile_id), "prototypes[%s].source.path" % prototype_id, str(source.get("path", "")))


func _add_media_entry(entries: Array[Dictionary], domain: String, record_id: String, field: String, source_id: String, fallback_key: String) -> void:
	var normalized := source_id.strip_edges()
	if normalized.is_empty():
		return
	entries.append(_entry_from_result(domain, record_id, field, "media", AssetPathResolver.resolve_media_asset(normalized, fallback_key)))


func _add_model_entry(entries: Array[Dictionary], domain: String, record_id: String, field: String, source_id: String) -> void:
	var normalized := source_id.strip_edges()
	if normalized.is_empty():
		return
	var result: Dictionary
	if normalized.begins_with("builtin:"):
		result = AssetPathResolver.resolve_model_asset(normalized)
	else:
		result = AssetPathResolver.resolve_gltf_source_path(normalized)
	entries.append(_entry_from_result(domain, record_id, field, "model", result))


func _entry_from_result(domain: String, record_id: String, field: String, asset_kind: String, result: Dictionary) -> Dictionary:
	return {
		"domain": domain,
		"record_id": record_id,
		"field": field,
		"asset_kind": asset_kind,
		"source_id": str(result.get("source_id", "")),
		"ok": bool(result.get("ok", false)),
		"exists": bool(result.get("exists", false)),
		"relative_path": str(result.get("relative_path", "")),
		"resource_path": str(result.get("resource_path", "")),
		"reason": str(result.get("reason", "")),
		"fallback_key": str(result.get("fallback_key", "")),
	}


func _unique_asset_count(entries: Array[Dictionary]) -> int:
	var seen := {}
	for entry in entries:
		var key := str(entry.get("resource_path", entry.get("source_id", "")))
		if key.is_empty():
			key = str(entry.get("source_id", ""))
		if not key.is_empty():
			seen[key] = true
	return seen.size()


func _count_where(entries: Array[Dictionary], key: String, expected: Variant) -> int:
	var count := 0
	for entry in entries:
		if entry.get(key) == expected:
			count += 1
	return count


func _invalid_count(entries: Array[Dictionary]) -> int:
	var count := 0
	for entry in entries:
		if not bool(entry.get("ok", false)):
			count += 1
	return count


func _count_by_key(entries: Array[Dictionary], key: String) -> Dictionary:
	var counts := {}
	for entry in entries:
		var value := str(entry.get(key, ""))
		if value.is_empty():
			value = "<empty>"
		counts[value] = int(counts.get(value, 0)) + 1
	return counts


func _sorted_keys(source: Dictionary) -> Array:
	var keys: Array = source.keys()
	keys.sort()
	return keys


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
