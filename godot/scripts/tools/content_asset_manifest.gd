extends RefCounted

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")


func build(registry: RefCounted) -> Dictionary:
	var entries: Array[Dictionary] = []
	_collect_item_assets(entries, registry)
	_collect_character_assets(entries, registry)
	_collect_dialogue_assets(entries, registry)
	_collect_skill_assets(entries, registry)
	_collect_overworld_assets(entries, registry)
	_collect_appearance_assets(entries, registry)
	_collect_world_tile_assets(entries, registry)
	_collect_map_assets(entries, registry)
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


func _collect_character_assets(entries: Array[Dictionary], registry: RefCounted) -> void:
	for character_id in _sorted_keys(registry.get_library("characters")):
		var record: Dictionary = registry.get_library("characters")[character_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var presentation: Dictionary = _dictionary_or_empty(data.get("presentation", {}))
		_add_media_entry(entries, "characters", str(character_id), "presentation.portrait_path", str(presentation.get("portrait_path", "")), "portrait")
		_add_media_entry(entries, "characters", str(character_id), "presentation.avatar_path", str(presentation.get("avatar_path", "")), "portrait")


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


func _collect_map_assets(entries: Array[Dictionary], registry: RefCounted) -> void:
	var prototype_sources: Dictionary = _world_tile_prototype_sources(registry)
	var surface_sets: Dictionary = _world_tile_surface_set_prototypes(registry)
	var wall_sets: Dictionary = _world_tile_wall_set_prototypes(registry)
	for map_id in _sorted_keys(registry.get_library("maps")):
		var record: Dictionary = registry.get_library("maps")[map_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var objects: Array = _array_or_empty(data.get("objects", []))
		for index in range(objects.size()):
			var object: Dictionary = _dictionary_or_empty(objects[index])
			var visual: Dictionary = _dictionary_or_empty(_dictionary_or_empty(object.get("props", {})).get("visual", {}))
			var prototype_id := str(visual.get("prototype_id", "")).strip_edges()
			if prototype_id.is_empty() or not prototype_sources.has(prototype_id):
				pass
			else:
				_add_model_reference_entry(entries, "maps", str(map_id), "objects[%d].props.visual.prototype_id" % index, str(prototype_sources.get(prototype_id, "")), prototype_id)
			var tile_set: Dictionary = _dictionary_or_empty(_dictionary_or_empty(_dictionary_or_empty(object.get("props", {})).get("building", {})).get("tile_set", {}))
			_collect_map_tile_set_assets(entries, "maps", str(map_id), index, tile_set, prototype_sources, surface_sets, wall_sets)


func _collect_map_tile_set_assets(
		entries: Array[Dictionary],
		domain: String,
		record_id: String,
		object_index: int,
		tile_set: Dictionary,
		prototype_sources: Dictionary,
		surface_sets: Dictionary,
		wall_sets: Dictionary) -> void:
	var wall_set_id := str(tile_set.get("wall_set_id", "")).strip_edges()
	if wall_sets.has(wall_set_id):
		var wall_set: Dictionary = _dictionary_or_empty(wall_sets.get(wall_set_id, {}))
		for role in _sorted_keys(wall_set):
			var prototype_id := str(wall_set.get(role, ""))
			if prototype_sources.has(prototype_id):
				_add_model_reference_entry(entries, domain, record_id, "objects[%d].props.building.tile_set.wall_set_id.%s" % [object_index, role], str(prototype_sources.get(prototype_id, "")), "%s:%s" % [wall_set_id, prototype_id])
	var surface_set_id := str(tile_set.get("floor_surface_set_id", "")).strip_edges()
	if surface_sets.has(surface_set_id):
		var surface_set: Dictionary = _dictionary_or_empty(surface_sets.get(surface_set_id, {}))
		for role in _sorted_keys(surface_set):
			var prototype_id := str(surface_set.get(role, ""))
			if prototype_sources.has(prototype_id):
				_add_model_reference_entry(entries, domain, record_id, "objects[%d].props.building.tile_set.floor_surface_set_id.%s" % [object_index, role], str(prototype_sources.get(prototype_id, "")), "%s:%s" % [surface_set_id, prototype_id])


func _world_tile_prototype_sources(registry: RefCounted) -> Dictionary:
	var output := {}
	for world_tile_id in _sorted_keys(registry.get_library("world_tiles")):
		var record: Dictionary = registry.get_library("world_tiles")[world_tile_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var prototypes: Array = _array_or_empty(data.get("prototypes", []))
		for prototype in prototypes:
			var prototype_data: Dictionary = _dictionary_or_empty(prototype)
			var prototype_id := str(prototype_data.get("id", "")).strip_edges()
			var source: Dictionary = _dictionary_or_empty(prototype_data.get("source", {}))
			if prototype_id.is_empty() or str(source.get("kind", "")) != "gltf_scene":
				continue
			output[prototype_id] = str(source.get("path", ""))
	return output


func _world_tile_surface_set_prototypes(registry: RefCounted) -> Dictionary:
	var output := {}
	for world_tile_id in _sorted_keys(registry.get_library("world_tiles")):
		var record: Dictionary = registry.get_library("world_tiles")[world_tile_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		for surface_set_source in _array_or_empty(data.get("surface_sets", [])):
			var surface_set: Dictionary = _dictionary_or_empty(surface_set_source)
			var surface_set_id := str(surface_set.get("id", "")).strip_edges()
			if surface_set_id.is_empty():
				continue
			var prototypes := {}
			for key in ["flat_top_prototype_id", "cliff_inner_corner_prototype_id", "cliff_outer_corner_prototype_id", "cliff_side_prototype_id"]:
				var prototype_id := str(surface_set.get(key, "")).strip_edges()
				if not prototype_id.is_empty():
					prototypes[key] = prototype_id
			var ramp_top_ids: Dictionary = _dictionary_or_empty(surface_set.get("ramp_top_prototype_ids", {}))
			for direction in _sorted_keys(ramp_top_ids):
				var ramp_prototype_id := str(ramp_top_ids.get(direction, "")).strip_edges()
				if not ramp_prototype_id.is_empty():
					prototypes["ramp_top_prototype_ids.%s" % direction] = ramp_prototype_id
			output[surface_set_id] = prototypes
	return output


func _world_tile_wall_set_prototypes(registry: RefCounted) -> Dictionary:
	var output := {}
	for world_tile_id in _sorted_keys(registry.get_library("world_tiles")):
		var record: Dictionary = registry.get_library("world_tiles")[world_tile_id]
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		for wall_set_source in _array_or_empty(data.get("wall_sets", [])):
			var wall_set: Dictionary = _dictionary_or_empty(wall_set_source)
			var wall_set_id := str(wall_set.get("id", "")).strip_edges()
			if wall_set_id.is_empty():
				continue
			var prototypes := {}
			for key in ["isolated_prototype_id", "end_prototype_id", "straight_prototype_id", "corner_prototype_id", "t_junction_prototype_id", "cross_prototype_id"]:
				var prototype_id := str(wall_set.get(key, "")).strip_edges()
				if not prototype_id.is_empty():
					prototypes[key] = prototype_id
			output[wall_set_id] = prototypes
	return output


func _add_media_entry(entries: Array[Dictionary], domain: String, record_id: String, field: String, source_id: String, fallback_key: String) -> void:
	var normalized := source_id.strip_edges()
	if normalized.is_empty():
		return
	entries.append(_entry_from_result(domain, record_id, field, "media", AssetPathResolver.resolve_media_asset(normalized, fallback_key)))


func _add_model_entry(entries: Array[Dictionary], domain: String, record_id: String, field: String, source_id: String) -> void:
	var normalized := source_id.strip_edges()
	if normalized.is_empty():
		return
	var result: Dictionary = AssetPathResolver.resolve_model_asset(normalized)
	entries.append(_entry_from_result(domain, record_id, field, "model", result))


func _add_model_reference_entry(entries: Array[Dictionary], domain: String, record_id: String, field: String, source_id: String, reference_id: String) -> void:
	var normalized := source_id.strip_edges()
	if normalized.is_empty():
		return
	var result: Dictionary = AssetPathResolver.resolve_model_asset(normalized)
	var entry: Dictionary = _entry_from_result(domain, record_id, field, "model", result)
	entry["reference_id"] = reference_id
	entries.append(entry)


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
