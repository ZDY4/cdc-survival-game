extends RefCounted

const GRID_SIZE := 1.0
const OVERLAY_ROOT_NAME := "DebugOverlayRoot"

var overlay_root: Node3D
var walkable_material := _debug_material(Color(0.18, 0.86, 0.36, 0.26))
var blocked_material := _debug_material(Color(0.94, 0.20, 0.18, 0.34))
var visible_material := _debug_material(Color(0.18, 0.66, 1.0, 0.32))
var explored_material := _debug_material(Color(0.95, 0.72, 0.22, 0.22))
var blocked_sight_material := _debug_material(Color(1.0, 0.18, 0.72, 0.42))
var level_material := _debug_material(Color(0.78, 0.48, 1.0, 0.28))


func apply_overlay(parent: Node3D, mode: String, map_snapshot: Dictionary, runtime_snapshot: Dictionary = {}) -> Dictionary:
	if parent == null:
		return {"ok": false, "reason": "parent_missing"}
	_clear_overlay()
	var normalized: String = mode.strip_edges().to_lower()
	if normalized.is_empty() or normalized == "off":
		return {"ok": true, "mode": "off", "cell_count": 0}
	overlay_root = Node3D.new()
	overlay_root.name = OVERLAY_ROOT_NAME
	overlay_root.set_meta("debug_overlay_mode", normalized)
	parent.add_child(overlay_root)
	var result: Dictionary = _build_mode_overlay(normalized, map_snapshot, runtime_snapshot)
	overlay_root.set_meta("cell_count", int(result.get("cell_count", 0)))
	overlay_root.set_meta("visible_cell_count", int(result.get("visible_cell_count", 0)))
	overlay_root.set_meta("explored_cell_count", int(result.get("explored_cell_count", 0)))
	overlay_root.set_meta("blocked_cell_count", int(result.get("blocked_cell_count", 0)))
	overlay_root.set_meta("blocked_sight_cell_count", int(result.get("blocked_sight_cell_count", 0)))
	overlay_root.set_meta("level", int(result.get("level", _default_level(map_snapshot))))
	return result


func clear_overlay() -> void:
	_clear_overlay()


func snapshot() -> Dictionary:
	if overlay_root == null or not is_instance_valid(overlay_root):
		return {"active": false, "mode": "off", "cell_count": 0}
	return {
		"active": true,
		"mode": str(overlay_root.get_meta("debug_overlay_mode", "")),
		"cell_count": int(overlay_root.get_meta("cell_count", 0)),
		"visible_cell_count": int(overlay_root.get_meta("visible_cell_count", 0)),
		"explored_cell_count": int(overlay_root.get_meta("explored_cell_count", 0)),
		"blocked_cell_count": int(overlay_root.get_meta("blocked_cell_count", 0)),
		"blocked_sight_cell_count": int(overlay_root.get_meta("blocked_sight_cell_count", 0)),
		"level": int(overlay_root.get_meta("level", 0)),
	}


func _build_mode_overlay(mode: String, map_snapshot: Dictionary, runtime_snapshot: Dictionary) -> Dictionary:
	match mode:
		"walkable":
			return _build_walkable_overlay(map_snapshot)
		"vision":
			return _build_vision_overlay(map_snapshot, runtime_snapshot)
		"blocked_sight":
			return _build_blocked_sight_overlay(map_snapshot)
		"level":
			return _build_level_overlay(map_snapshot)
		_:
			_clear_overlay()
			return {"ok": false, "reason": "unknown_debug_overlay_mode", "mode": mode, "cell_count": 0}


func _build_walkable_overlay(map_snapshot: Dictionary) -> Dictionary:
	var level: int = _default_level(map_snapshot)
	var blocking_cells: Dictionary = _dictionary_or_empty(map_snapshot.get("blocking_cells", {}))
	var count := 0
	var blocked_count := 0
	for cell in _all_level_cells(map_snapshot, level):
		var key: String = _cell_key(cell)
		var blocked: bool = blocking_cells.has(key)
		_add_cell_quad(_dictionary_or_empty(cell), blocked_material if blocked else walkable_material, "blocked" if blocked else "walkable")
		count += 1
		if blocked:
			blocked_count += 1
	return {"ok": true, "mode": "walkable", "cell_count": count, "blocked_cell_count": blocked_count, "level": level}


func _build_vision_overlay(map_snapshot: Dictionary, runtime_snapshot: Dictionary) -> Dictionary:
	var actor_vision: Dictionary = _actor_vision(runtime_snapshot)
	var visible_cells: Dictionary = _cell_lookup(_array_or_empty(actor_vision.get("visible_cells", [])))
	var explored_cells: Dictionary = _cell_lookup(_explored_cells(actor_vision, str(runtime_snapshot.get("active_map_id", ""))))
	var count := 0
	for key in explored_cells.keys():
		if visible_cells.has(key):
			continue
		_add_cell_quad(_dictionary_or_empty(explored_cells.get(key, {})), explored_material, "explored")
		count += 1
	for key in visible_cells.keys():
		_add_cell_quad(_dictionary_or_empty(visible_cells.get(key, {})), visible_material, "visible")
		count += 1
	return {
		"ok": true,
		"mode": "vision",
		"cell_count": count,
		"visible_cell_count": visible_cells.size(),
		"explored_cell_count": explored_cells.size(),
		"level": _default_level(map_snapshot),
	}


func _build_blocked_sight_overlay(map_snapshot: Dictionary) -> Dictionary:
	var sight_blocking_cells: Dictionary = _dictionary_or_empty(map_snapshot.get("sight_blocking_cells", {}))
	var count := 0
	for key in sight_blocking_cells.keys():
		var cell: Dictionary = _cell_from_key(str(key), _default_level(map_snapshot))
		_add_cell_quad(cell, blocked_sight_material, "blocked_sight")
		count += 1
	return {"ok": true, "mode": "blocked_sight", "cell_count": count, "blocked_sight_cell_count": count, "level": _default_level(map_snapshot)}


func _build_level_overlay(map_snapshot: Dictionary) -> Dictionary:
	var count := 0
	for level_data in _array_or_empty(map_snapshot.get("levels", [])):
		var level: int = int(_dictionary_or_empty(level_data).get("y", _default_level(map_snapshot)))
		for cell in _all_level_cells(map_snapshot, level):
			_add_cell_quad(_dictionary_or_empty(cell), level_material, "level_%d" % level)
			count += 1
	return {"ok": true, "mode": "level", "cell_count": count, "level": _default_level(map_snapshot)}


func _all_level_cells(map_snapshot: Dictionary, level: int) -> Array[Dictionary]:
	var explicit_cells: Array[Dictionary] = []
	for level_data in _array_or_empty(map_snapshot.get("levels", [])):
		var level_dict: Dictionary = _dictionary_or_empty(level_data)
		if int(level_dict.get("y", level)) != level:
			continue
		for cell in _array_or_empty(level_dict.get("cells", [])):
			explicit_cells.append(_normalized_cell(_dictionary_or_empty(cell), level))
	if not explicit_cells.is_empty():
		return explicit_cells
	var size: Dictionary = _dictionary_or_empty(map_snapshot.get("size", {}))
	var width: int = max(1, int(size.get("width", 1)))
	var height: int = max(1, int(size.get("height", 1)))
	var output: Array[Dictionary] = []
	for x in range(width):
		for z in range(height):
			output.append({"x": x, "y": level, "z": z})
	return output


func _add_cell_quad(cell: Dictionary, material: Material, kind: String) -> void:
	if overlay_root == null or not is_instance_valid(overlay_root):
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(GRID_SIZE * 0.92, 0.025, GRID_SIZE * 0.92)
	var node := MeshInstance3D.new()
	node.name = "DebugCell_%s_%d_%d_%d" % [kind, int(cell.get("x", 0)), int(cell.get("y", 0)), int(cell.get("z", 0))]
	node.mesh = mesh
	node.material_override = material
	node.position = Vector3(float(cell.get("x", 0)) * GRID_SIZE, 0.055 + float(cell.get("y", 0)) * 0.02, float(cell.get("z", 0)) * GRID_SIZE)
	node.set_meta("debug_overlay_kind", kind)
	node.set_meta("grid", _normalized_cell(cell, int(cell.get("y", 0))))
	overlay_root.add_child(node)


func _actor_vision(runtime_snapshot: Dictionary) -> Dictionary:
	var vision: Dictionary = _dictionary_or_empty(runtime_snapshot.get("vision", {}))
	for actor in _array_or_empty(vision.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data
	return {}


func _explored_cells(actor_vision: Dictionary, active_map_id: String) -> Array:
	for map_data in _array_or_empty(actor_vision.get("explored_maps", [])):
		var explored_map: Dictionary = _dictionary_or_empty(map_data)
		if str(explored_map.get("map_id", "")) == active_map_id:
			return _array_or_empty(explored_map.get("explored_cells", []))
	return []


func _cell_lookup(cells: Array) -> Dictionary:
	var output: Dictionary = {}
	for cell in cells:
		var cell_data: Dictionary = _dictionary_or_empty(cell)
		output[_cell_key(cell_data)] = cell_data
	return output


func _cell_key(cell: Dictionary) -> String:
	return "%d:%d:%d" % [int(cell.get("x", 0)), int(cell.get("y", 0)), int(cell.get("z", 0))]


func _cell_from_key(key: String, fallback_level: int) -> Dictionary:
	var parts: PackedStringArray = key.split(":")
	if parts.size() >= 3:
		return {"x": int(parts[0]), "y": int(parts[1]), "z": int(parts[2])}
	if parts.size() >= 2:
		return {"x": int(parts[0]), "y": fallback_level, "z": int(parts[1])}
	return {"x": 0, "y": fallback_level, "z": 0}


func _normalized_cell(cell: Dictionary, fallback_level: int) -> Dictionary:
	return {
		"x": int(cell.get("x", 0)),
		"y": int(cell.get("y", fallback_level)),
		"z": int(cell.get("z", 0)),
	}


func _default_level(map_snapshot: Dictionary) -> int:
	return int(map_snapshot.get("default_level", 0))


func _clear_overlay() -> void:
	if overlay_root != null and is_instance_valid(overlay_root):
		var parent: Node = overlay_root.get_parent()
		if parent != null:
			parent.remove_child(overlay_root)
		overlay_root.free()
	overlay_root = null


static func _debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
