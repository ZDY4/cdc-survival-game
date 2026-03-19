class_name TargetAbilityBase
extends RefCounted

const SHAPE_SINGLE: String = "single"
const SHAPE_DIAMOND: String = "diamond"
const SHAPE_SQUARE: String = "square"

var ability_id: String = ""
var ability_kind: String = ""
var range_cells: int = 0
var shape: String = SHAPE_SINGLE
var radius: int = 0


func begin_targeting(context: Dictionary) -> Dictionary:
	var session_context: Dictionary = context.duplicate(true)
	var caster: Node = session_context.get("caster", null) as Node
	if caster == null and session_context.has("attacker"):
		caster = session_context.get("attacker", null) as Node
		session_context["caster"] = caster
	return {
		"success": true,
		"state": "targeting_started",
		"ability_kind": ability_kind,
		"ability_id": ability_id,
		"handler": self,
		"context": session_context
	}


func build_preview(caster: Node, center_cell: Vector3i, context: Dictionary) -> Dictionary:
	var caster_cell: Vector3i = _resolve_caster_cell(caster, context)
	var preview: Dictionary = {
		"valid": false,
		"center_cell": center_cell,
		"affected_cells": _build_affected_cells(center_cell),
		"reason": "",
		"shape": shape,
		"range_cells": _build_range_cells(caster_cell)
	}
	var validation: Dictionary = is_preview_valid(preview, context)
	preview["valid"] = bool(validation.get("valid", false))
	preview["reason"] = str(validation.get("reason", ""))
	return preview


func is_preview_valid(preview: Dictionary, context: Dictionary) -> Dictionary:
	var caster: Node = context.get("caster", null) as Node
	var caster_cell: Vector3i = _resolve_caster_cell(caster, context)
	if caster_cell == Vector3i.ZERO and caster == null:
		return {"valid": false, "reason": "missing_caster"}

	var center_cell: Vector3i = Vector3i.ZERO
	var center_value: Variant = preview.get("center_cell", Vector3i.ZERO)
	if center_value is Vector3i:
		center_cell = center_value
	if not _is_center_in_range(caster_cell, center_cell):
		return {"valid": false, "reason": "out_of_range"}

	var affected_cells: Array[Vector3i] = _extract_cells(preview.get("affected_cells", []))
	if affected_cells.is_empty():
		return {"valid": false, "reason": "empty_preview"}

	return {"valid": true, "reason": ""}


func confirm_target(_preview: Dictionary, _context: Dictionary) -> Dictionary:
	return {"success": false, "reason": "confirm_not_implemented", "ability_id": ability_id}


func auto_select_for_ai(caster: Node, preferred_cell: Vector3i, context: Dictionary) -> Dictionary:
	var preview: Dictionary = build_preview(caster, preferred_cell, context)
	return {
		"success": bool(preview.get("valid", false)),
		"reason": str(preview.get("reason", "")),
		"preview": preview
	}


func _configure_targeting(config: Dictionary) -> void:
	range_cells = maxi(0, int(config.get("range_cells", range_cells)))
	shape = _normalize_shape(str(config.get("shape", shape)))
	radius = maxi(0, int(config.get("radius", radius)))


func _build_affected_cells(center_cell: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	match shape:
		SHAPE_DIAMOND:
			for dx in range(-radius, radius + 1):
				for dz in range(-radius, radius + 1):
					if abs(dx) + abs(dz) > radius:
						continue
					_append_unique_cell(cells, Vector3i(center_cell.x + dx, center_cell.y, center_cell.z + dz))
		SHAPE_SQUARE:
			for dx in range(-radius, radius + 1):
				for dz in range(-radius, radius + 1):
					_append_unique_cell(cells, Vector3i(center_cell.x + dx, center_cell.y, center_cell.z + dz))
		_:
			_append_unique_cell(cells, center_cell)
	return cells


func _build_range_cells(caster_cell: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for dx in range(-range_cells, range_cells + 1):
		for dz in range(-range_cells, range_cells + 1):
			if abs(dx) + abs(dz) > range_cells:
				continue
			_append_unique_cell(cells, Vector3i(caster_cell.x + dx, caster_cell.y, caster_cell.z + dz))
	return cells


func _append_unique_cell(cells: Array[Vector3i], cell: Vector3i) -> void:
	if not cells.has(cell):
		cells.append(cell)


func _extract_cells(raw_cells: Variant) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if not (raw_cells is Array):
		return result
	for cell_variant in raw_cells:
		if cell_variant is Vector3i:
			result.append(cell_variant)
	return result


func _resolve_caster_cell(caster: Node, context: Dictionary) -> Vector3i:
	if context.has("caster_cell"):
		var provided_cell: Variant = context.get("caster_cell", Vector3i.ZERO)
		if provided_cell is Vector3i:
			return provided_cell
	return _resolve_grid_cell_from_node(caster)


func _resolve_grid_cell_from_node(node: Node) -> Vector3i:
	if node == null or not is_instance_valid(node):
		return Vector3i.ZERO
	if node.has_method("get_grid_position"):
		var result: Variant = node.call("get_grid_position")
		if result is Vector3i:
			return result
	if node is Node3D:
		return GridMovementSystem.world_to_grid((node as Node3D).global_position)
	return Vector3i.ZERO


func _is_center_in_range(caster_cell: Vector3i, center_cell: Vector3i) -> bool:
	return abs(center_cell.x - caster_cell.x) + abs(center_cell.z - caster_cell.z) <= range_cells


func _normalize_shape(raw_shape: String) -> String:
	var normalized: String = raw_shape.strip_edges().to_lower()
	if normalized in [SHAPE_SINGLE, SHAPE_DIAMOND, SHAPE_SQUARE]:
		return normalized
	return SHAPE_SINGLE
