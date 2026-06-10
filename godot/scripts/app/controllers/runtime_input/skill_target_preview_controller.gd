extends RefCounted

const HOVER_COLOR_SKILL_VALID := Color(0.38, 0.68, 1.0, 0.58)
const HOVER_COLOR_SKILL_BLOCKED := Color(0.96, 0.18, 0.55, 0.52)


func update_preview_markers(layer: Node3D, preview: Dictionary, runtime_snapshot: Dictionary, observed_level: int) -> void:
	if layer == null:
		return
	clear_preview_markers(layer)
	if preview.is_empty():
		return
	var color := HOVER_COLOR_SKILL_VALID if bool(preview.get("success", false)) else HOVER_COLOR_SKILL_BLOCKED
	var skill_id := str(preview.get("skill_id", ""))
	var target_shape := str(preview.get("target_shape", preview.get("shape", "")))
	var cell_count := 0
	for cell in _array_or_empty(preview.get("affected_cells", [])):
		var grid: Dictionary = _dictionary_or_empty(cell)
		if grid.is_empty():
			continue
		var marker := _build_skill_target_cell_marker(color)
		marker.position = Vector3(
			float(grid.get("x", 0)),
			float(grid.get("y", observed_level)) + 0.16,
			float(grid.get("z", 0))
		)
		marker.set_meta("grid", grid.duplicate(true))
		marker.set_meta("skill_id", skill_id)
		marker.set_meta("target_shape", target_shape)
		marker.set_meta("preview_success", bool(preview.get("success", false)))
		marker.set_meta("reason", str(preview.get("reason", "")))
		layer.add_child(marker)
		cell_count += 1
	var actor_count := 0
	for actor_id_value in _array_or_empty(preview.get("affected_actor_ids", [])):
		var actor_id := int(actor_id_value)
		var actor_grid := _actor_grid(actor_id, runtime_snapshot)
		if actor_grid.is_empty():
			continue
		var outline := _build_skill_target_actor_marker(color)
		outline.position = Vector3(
			float(actor_grid.get("x", 0)),
			float(actor_grid.get("y", observed_level)) + 0.84,
			float(actor_grid.get("z", 0))
		)
		outline.set_meta("actor_id", actor_id)
		outline.set_meta("skill_id", skill_id)
		outline.set_meta("target_shape", target_shape)
		outline.set_meta("preview_success", bool(preview.get("success", false)))
		outline.set_meta("reason", str(preview.get("reason", "")))
		layer.add_child(outline)
		actor_count += 1
	layer.set_meta("skill_id", skill_id)
	layer.set_meta("target_shape", target_shape)
	layer.set_meta("preview_success", bool(preview.get("success", false)))
	layer.set_meta("reason", str(preview.get("reason", "")))
	layer.set_meta("cell_marker_count", cell_count)
	layer.set_meta("actor_marker_count", actor_count)


func clear_preview_markers(layer: Node3D) -> void:
	if layer == null:
		return
	for child in layer.get_children():
		child.queue_free()
	layer.set_meta("skill_id", "")
	layer.set_meta("target_shape", "")
	layer.set_meta("preview_success", false)
	layer.set_meta("reason", "")
	layer.set_meta("cell_marker_count", 0)
	layer.set_meta("actor_marker_count", 0)


func _actor_grid(actor_id: int, runtime_snapshot: Dictionary) -> Dictionary:
	for actor in _array_or_empty(runtime_snapshot.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return _dictionary_or_empty(actor_data.get("grid_position", {})).duplicate(true)
	return {}


func _build_skill_target_cell_marker(color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.78, 0.04, 0.78)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "SkillTargetCellMarker"
	node.mesh = mesh
	node.material_override = material
	return node


func _build_skill_target_actor_marker(color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.52
	mesh.bottom_radius = 0.52
	mesh.height = 1.50
	mesh.radial_segments = 24
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, minf(0.32, color.a))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "SkillTargetActorMarker"
	node.mesh = mesh
	node.material_override = material
	return node


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
