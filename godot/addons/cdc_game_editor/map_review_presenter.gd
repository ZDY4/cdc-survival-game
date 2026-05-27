@tool
extends RefCounted

const MapBuilder = preload("res://scripts/world/map_builder.gd")

const MAX_ENTRY_LINES := 8
const MAX_TARGET_LINES := 10
const MAX_SPAWN_LINES := 8

var map_builder := MapBuilder.new()


func build_review(map_data: Dictionary) -> Dictionary:
	var topology: RefCounted = map_builder.build_from_definition(map_data)
	var map: Dictionary = topology.to_dictionary()
	return {
		"summary": _summary_text(map),
		"checklist": _checklist_text(map),
		"map": map,
	}


func _summary_text(map: Dictionary) -> String:
	var lines: Array[String] = [
		"map_review:",
		"bounds: %s" % _bounds_text(_dictionary_or_empty(map.get("bounds", {}))),
		"objects_by_kind: %s" % _counts_text(_dictionary_or_empty(map.get("objects_by_kind", {}))),
		"occupied_cells: %d" % int(map.get("occupied_cell_count", 0)),
		"blocking_cells: %d" % int(map.get("blocking_cell_count", 0)),
		"sight_blocking_cells: %d" % int(map.get("sight_blocking_cell_count", 0)),
	]
	lines.append_array(_entry_point_lines(_dictionary_or_empty(map.get("entry_points", {}))))
	lines.append_array(_interaction_target_lines(_dictionary_or_empty(map.get("interaction_targets", {}))))
	lines.append_array(_ai_spawn_lines(_array_or_empty(map.get("ai_spawn_objects", []))))
	return "\n".join(lines)


func _checklist_text(map: Dictionary) -> String:
	var checks: Array[String] = []
	_add_check(checks, "has entry points", not _dictionary_or_empty(map.get("entry_points", {})).is_empty())
	_add_check(checks, "has map objects", int(map.get("object_count", 0)) > 0)
	_add_check(checks, "has occupied cells", int(map.get("occupied_cell_count", 0)) > 0)
	_add_check(checks, "has interaction targets", not _dictionary_or_empty(map.get("interaction_targets", {})).is_empty())
	return "map_review_checks:\n%s" % "\n".join(checks)


func _entry_point_lines(entry_points: Dictionary) -> Array[String]:
	var lines: Array[String] = ["entry_points: %d" % entry_points.size()]
	var ids: Array[String] = []
	for id in entry_points.keys():
		ids.append(str(id))
	ids.sort()
	var limit: int = min(ids.size(), MAX_ENTRY_LINES)
	for i in range(limit):
		var id: String = ids[i]
		lines.append("- entry %s @ %s" % [id, _grid_text(_dictionary_or_empty(entry_points[id]))])
	if ids.size() > limit:
		lines.append("- ... %d more entries" % (ids.size() - limit))
	return lines


func _interaction_target_lines(targets: Dictionary) -> Array[String]:
	var lines: Array[String] = ["interaction_targets: %d" % targets.size()]
	var ids: Array[String] = []
	for id in targets.keys():
		ids.append(str(id))
	ids.sort()
	var limit: int = min(ids.size(), MAX_TARGET_LINES)
	for i in range(limit):
		var id: String = ids[i]
		var target: Dictionary = _dictionary_or_empty(targets[id])
		lines.append("- target %s kind=%s at=%s" % [
			id,
			target.get("kind", ""),
			_grid_text(_dictionary_or_empty(target.get("anchor", {}))),
		])
	if ids.size() > limit:
		lines.append("- ... %d more targets" % (ids.size() - limit))
	return lines


func _ai_spawn_lines(spawns: Array) -> Array[String]:
	var lines: Array[String] = ["ai_spawns: %d" % spawns.size()]
	var limit: int = min(spawns.size(), MAX_SPAWN_LINES)
	for i in range(limit):
		var spawn: Dictionary = _dictionary_or_empty(spawns[i])
		var props: Dictionary = _dictionary_or_empty(spawn.get("props", {}))
		var ai_spawn: Dictionary = _dictionary_or_empty(props.get("ai_spawn", {}))
		lines.append("- spawn %s character=%s at=%s" % [
			spawn.get("object_id", ""),
			ai_spawn.get("character_id", ""),
			_grid_text(_dictionary_or_empty(spawn.get("anchor", {}))),
		])
	if spawns.size() > limit:
		lines.append("- ... %d more spawns" % (spawns.size() - limit))
	return lines


func _add_check(output: Array[String], label: String, passed: bool) -> void:
	output.append("- [%s] %s" % ["ok" if passed else "warn", label])


func _bounds_text(bounds: Dictionary) -> String:
	return "x=%s..%s z=%s..%s" % [
		bounds.get("min_x", ""),
		bounds.get("max_x", ""),
		bounds.get("min_z", ""),
		bounds.get("max_z", ""),
	]


func _counts_text(counts: Dictionary) -> String:
	var parts: Array[String] = []
	for key in counts.keys():
		parts.append("%s=%d" % [key, int(counts[key])])
	parts.sort()
	if parts.is_empty():
		return "-"
	return ", ".join(parts)


func _grid_text(grid: Dictionary) -> String:
	return "(%s,%s,%s)" % [grid.get("x", ""), grid.get("y", ""), grid.get("z", "")]


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
