extends RefCounted

const VisionGeometry = preload("res://scripts/core/vision/vision_geometry.gd")
const SkillTargetPreviewController = preload("res://scripts/app/controllers/runtime_input/skill_target_preview_controller.gd")

const GRID_SIZE := 1.0
const HOVER_COLOR_INTERACTION := Color(1.0, 0.82, 0.18, 0.72)
const HOVER_COLOR_MOVE_REACHABLE := Color(0.24, 0.95, 0.48, 0.72)
const HOVER_COLOR_MOVE_BLOCKED := Color(1.0, 0.22, 0.18, 0.72)
const MOVE_PATH_DOT_COLOR := Color(1.0, 1.0, 1.0, 0.30)
const PENDING_MOVE_PATH_DOT_COLOR := Color(1.0, 1.0, 1.0, 0.34)
const HOVER_COLOR_ATTACK_REACHABLE := Color(1.0, 0.45, 0.16, 0.78)
const HOVER_COLOR_ATTACK_BLOCKED := Color(0.95, 0.12, 0.28, 0.78)
const HOVER_COLOR_PICKUP := Color(0.35, 0.82, 1.0, 0.50)
const HOVER_COLOR_CONTAINER := Color(0.36, 0.95, 0.62, 0.50)
const HOVER_COLOR_TRIGGER := Color(0.70, 0.55, 1.0, 0.50)
const HOVER_COLOR_DOOR := Color(0.95, 0.72, 0.28, 0.56)
const HOVER_COLOR_ACTOR := Color(1.0, 0.88, 0.22, 0.50)

var hover_cursor: MeshInstance3D
var hover_target_outline: MeshInstance3D
var attack_target_marker: MeshInstance3D
var attack_target_outline: MeshInstance3D
var attack_range_markers: Node3D
var skill_target_preview_markers: Node3D
var move_path_preview_markers: Node3D
var pending_movement_path_markers: Node3D

var _vision_geometry := VisionGeometry.new()
var _skill_target_preview_controller: RefCounted = SkillTargetPreviewController.new()


func attach(host: Node) -> void:
	hover_cursor = _build_hover_cursor()
	host.add_child(hover_cursor)
	hover_target_outline = _build_hover_target_outline()
	host.add_child(hover_target_outline)
	attack_target_marker = _build_attack_target_marker()
	host.add_child(attack_target_marker)
	attack_target_outline = _build_attack_target_outline()
	host.add_child(attack_target_outline)
	attack_range_markers = Node3D.new()
	attack_range_markers.name = "AttackRangeMarkers"
	host.add_child(attack_range_markers)
	skill_target_preview_markers = Node3D.new()
	skill_target_preview_markers.name = "SkillTargetPreviewMarkers"
	host.add_child(skill_target_preview_markers)
	move_path_preview_markers = Node3D.new()
	move_path_preview_markers.name = "MovePathPreviewMarkers"
	host.add_child(move_path_preview_markers)
	pending_movement_path_markers = Node3D.new()
	pending_movement_path_markers.name = "PendingMovementPathMarkers"
	host.add_child(pending_movement_path_markers)


func reset_for_world() -> void:
	hide_hover_cursor()
	hide_hover_target_outline()
	if attack_target_marker != null:
		attack_target_marker.visible = false
	if attack_target_outline != null:
		attack_target_outline.visible = false
	clear_attack_range_markers()
	clear_skill_target_preview_markers()
	clear_move_path_preview_markers()


func hide_hover_cursor() -> void:
	if hover_cursor != null:
		hover_cursor.visible = false


func update_hover_cursor(world_position: Vector3, observed_level: int) -> void:
	if hover_cursor == null:
		return
	var grid_x := roundf(world_position.x / GRID_SIZE) * GRID_SIZE
	var grid_z := roundf(world_position.z / GRID_SIZE) * GRID_SIZE
	hover_cursor.global_position = Vector3(grid_x, float(observed_level) + 0.09, grid_z)
	hover_cursor.visible = true


func apply_hover_cursor_state(move_preview: Dictionary, attack_preview: Dictionary, world_result: Dictionary, runtime_snapshot: Dictionary, observed_level: int) -> void:
	if hover_cursor == null:
		return
	var color := HOVER_COLOR_INTERACTION
	if not move_preview.is_empty():
		color = HOVER_COLOR_MOVE_REACHABLE if bool(move_preview.get("reachable", false)) else HOVER_COLOR_MOVE_BLOCKED
		hover_cursor.set_meta("move_reachable", bool(move_preview.get("reachable", false)))
		hover_cursor.set_meta("move_steps", int(move_preview.get("steps", 0)))
		hover_cursor.set_meta("move_reason", str(move_preview.get("reason", "")))
		hover_cursor.set_meta("move_ap_cost", float(move_preview.get("ap_cost", 0.0)))
		hover_cursor.set_meta("move_ap_available", float(move_preview.get("ap_available", 0.0)))
		update_move_path_preview_markers(move_preview, color, observed_level)
	else:
		hover_cursor.set_meta("move_reachable", false)
		hover_cursor.set_meta("move_steps", 0)
		hover_cursor.set_meta("move_reason", "")
		hover_cursor.set_meta("move_ap_cost", 0.0)
		hover_cursor.set_meta("move_ap_available", 0.0)
		clear_move_path_preview_markers()
	if not attack_preview.is_empty():
		color = HOVER_COLOR_ATTACK_REACHABLE if bool(attack_preview.get("can_attack", false)) else HOVER_COLOR_ATTACK_BLOCKED
		hover_cursor.set_meta("attack_can_attack", bool(attack_preview.get("can_attack", false)))
		hover_cursor.set_meta("attack_target_actor_id", int(attack_preview.get("target_actor_id", 0)))
		hover_cursor.set_meta("attack_reason", str(attack_preview.get("reason", "")))
		hover_cursor.set_meta("attack_hit_chance", float(attack_preview.get("hit_chance", -1.0)))
	else:
		hover_cursor.set_meta("attack_can_attack", false)
		hover_cursor.set_meta("attack_target_actor_id", 0)
		hover_cursor.set_meta("attack_reason", "")
		hover_cursor.set_meta("attack_hit_chance", -1.0)
	var material := hover_cursor.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color
	hover_cursor.set_meta("hover_color", color)
	update_attack_target_marker(attack_preview, color, runtime_snapshot, observed_level)
	update_attack_target_outline(attack_preview, color, runtime_snapshot, observed_level)
	update_attack_range_markers(attack_preview, color, world_result, observed_level)


func update_hover_target_outline(target: Dictionary, grid: Dictionary, target_category: String, attack_preview: Dictionary, observed_level: int) -> void:
	if hover_target_outline == null:
		return
	if not attack_preview.is_empty():
		hide_hover_target_outline()
		return
	if target.is_empty() or grid.is_empty():
		hide_hover_target_outline()
		return
	var color := hover_outline_color(target_category)
	hover_target_outline.global_position = Vector3(
		float(grid.get("x", 0)),
		float(grid.get("y", observed_level)) + hover_outline_height(target_category),
		float(grid.get("z", 0))
	)
	var material := hover_target_outline.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color
	hover_target_outline.visible = true
	hover_target_outline.set_meta("target_type", str(target.get("target_type", "")))
	hover_target_outline.set_meta("target_id", str(target.get("target_id", "")))
	hover_target_outline.set_meta("actor_id", int(target.get("actor_id", 0)))
	hover_target_outline.set_meta("target_category", target_category)
	hover_target_outline.set_meta("hover_color", color)
	var door: Dictionary = _dictionary_or_empty(target.get("door", {}))
	hover_target_outline.set_meta("door_is_open", bool(door.get("is_open", false)))
	hover_target_outline.set_meta("door_locked", bool(door.get("locked", false)))
	hover_target_outline.set_meta("container_visual_id", str(target.get("container_visual_id", "")))
	hover_target_outline.set_meta("container_visual_prototype_id", str(target.get("container_visual_prototype_id", "")))
	hover_target_outline.set_meta("container_model_asset_id", str(target.get("container_model_asset_id", "")))


func hide_hover_target_outline() -> void:
	if hover_target_outline == null:
		return
	hover_target_outline.visible = false
	hover_target_outline.set_meta("target_type", "")
	hover_target_outline.set_meta("target_id", "")
	hover_target_outline.set_meta("actor_id", 0)
	hover_target_outline.set_meta("target_category", "")
	hover_target_outline.set_meta("door_is_open", false)
	hover_target_outline.set_meta("door_locked", false)
	hover_target_outline.set_meta("container_visual_id", "")
	hover_target_outline.set_meta("container_visual_prototype_id", "")
	hover_target_outline.set_meta("container_model_asset_id", "")


func hover_outline_color(target_category: String) -> Color:
	if target_category.begins_with("actor"):
		return HOVER_COLOR_ACTOR
	match target_category:
		"pickup":
			return HOVER_COLOR_PICKUP
		"container":
			return HOVER_COLOR_CONTAINER
		"trigger":
			return HOVER_COLOR_TRIGGER
		"door":
			return HOVER_COLOR_DOOR
	return HOVER_COLOR_INTERACTION


func hover_outline_height(target_category: String) -> float:
	if target_category.begins_with("actor"):
		return 0.82
	return 0.38


func update_attack_target_marker(attack_preview: Dictionary, color: Color, runtime_snapshot: Dictionary, observed_level: int) -> void:
	if attack_target_marker == null:
		return
	if attack_preview.is_empty():
		attack_target_marker.visible = false
		attack_target_marker.set_meta("attack_target_actor_id", 0)
		attack_target_marker.set_meta("attack_can_attack", false)
		return
	var target_grid: Dictionary = attack_target_grid_from_preview(attack_preview, runtime_snapshot)
	if target_grid.is_empty():
		attack_target_marker.visible = false
		return
	attack_target_marker.global_position = Vector3(
		float(target_grid.get("x", 0)),
		float(target_grid.get("y", observed_level)) + 1.42,
		float(target_grid.get("z", 0))
	)
	var material := attack_target_marker.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color
	attack_target_marker.visible = true
	attack_target_marker.set_meta("attack_target_actor_id", int(attack_preview.get("target_actor_id", 0)))
	attack_target_marker.set_meta("attack_can_attack", bool(attack_preview.get("can_attack", false)))
	attack_target_marker.set_meta("hover_color", color)


func update_attack_target_outline(attack_preview: Dictionary, color: Color, runtime_snapshot: Dictionary, observed_level: int) -> void:
	if attack_target_outline == null:
		return
	if attack_preview.is_empty():
		attack_target_outline.visible = false
		attack_target_outline.set_meta("attack_target_actor_id", 0)
		attack_target_outline.set_meta("attack_can_attack", false)
		return
	var target_grid: Dictionary = attack_target_grid_from_preview(attack_preview, runtime_snapshot)
	if target_grid.is_empty():
		attack_target_outline.visible = false
		return
	attack_target_outline.global_position = Vector3(
		float(target_grid.get("x", 0)),
		float(target_grid.get("y", observed_level)) + 0.82,
		float(target_grid.get("z", 0))
	)
	var material := attack_target_outline.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(color.r, color.g, color.b, 0.24)
	attack_target_outline.visible = true
	attack_target_outline.set_meta("attack_target_actor_id", int(attack_preview.get("target_actor_id", 0)))
	attack_target_outline.set_meta("attack_can_attack", bool(attack_preview.get("can_attack", false)))
	attack_target_outline.set_meta("hover_color", color)


func update_attack_range_markers(attack_preview: Dictionary, color: Color, world_result: Dictionary, observed_level: int) -> void:
	if attack_range_markers == null:
		return
	clear_attack_range_markers()
	if attack_preview.is_empty():
		return
	var target_grid: Dictionary = _dictionary_or_empty(attack_preview.get("target_grid", {}))
	var attack_range: int = int(attack_preview.get("range", -1))
	if target_grid.is_empty() or attack_range < 0:
		return
	var markers := 0
	var candidates: Array[Dictionary] = attack_range_candidate_grids(target_grid, attack_range, world_result, observed_level)
	for grid in candidates:
		var marker := _build_attack_range_marker(color)
		marker.position = Vector3(
			float(grid.get("x", 0)),
			float(grid.get("y", observed_level)) + 0.13,
			float(grid.get("z", 0))
		)
		marker.set_meta("grid", grid.duplicate(true))
		marker.set_meta("attack_target_actor_id", int(attack_preview.get("target_actor_id", 0)))
		attack_range_markers.add_child(marker)
		markers += 1
	attack_range_markers.set_meta("marker_count", markers)
	attack_range_markers.set_meta("candidate_count", candidates.size())
	attack_range_markers.set_meta("attack_target_actor_id", int(attack_preview.get("target_actor_id", 0)))


func attack_target_grid_from_preview(attack_preview: Dictionary, runtime_snapshot: Dictionary) -> Dictionary:
	var target_grid: Dictionary = _dictionary_or_empty(attack_preview.get("target_grid", {}))
	if not target_grid.is_empty():
		return target_grid
	for actor in _array_or_empty(runtime_snapshot.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == int(attack_preview.get("target_actor_id", 0)):
			return _dictionary_or_empty(actor_data.get("grid_position", {}))
	return {}


func attack_range_candidate_grids(target_grid: Dictionary, attack_range: int, world_result: Dictionary, observed_level: int) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var target_x := int(target_grid.get("x", 0))
	var target_y := int(target_grid.get("y", observed_level))
	var target_z := int(target_grid.get("z", 0))
	var bounds: Dictionary = _dictionary_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("bounds", {}))
	var blocking: Dictionary = _dictionary_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("blocking_cells", {}))
	var topology: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	for x in range(target_x - attack_range, target_x + attack_range + 1):
		for z in range(target_z - attack_range, target_z + attack_range + 1):
			var distance: int = abs(x - target_x) + abs(z - target_z)
			if distance > attack_range:
				continue
			var candidate := {"x": x, "y": target_y, "z": z}
			if not _grid_in_bounds(candidate, bounds):
				continue
			var key := "%d:%d:%d" % [x, target_y, z]
			if blocking.has(key):
				continue
			if not _vision_geometry.has_line_of_sight(candidate, target_grid, topology):
				continue
			output.append(candidate)
	return output


func clear_attack_range_markers() -> void:
	if attack_range_markers == null:
		return
	for child in attack_range_markers.get_children():
		child.queue_free()
	attack_range_markers.set_meta("marker_count", 0)
	attack_range_markers.set_meta("candidate_count", 0)
	attack_range_markers.set_meta("attack_target_actor_id", 0)


func update_move_path_preview_markers(move_preview: Dictionary, _color: Color, observed_level: int) -> void:
	if move_path_preview_markers == null:
		return
	clear_move_path_preview_markers()
	var path: Array = _array_or_empty(move_preview.get("path", []))
	if path.is_empty():
		return
	var index := 0
	for cell in path:
		var grid: Dictionary = _dictionary_or_empty(cell)
		if grid.is_empty():
			continue
		var step_index: int = max(0, index)
		var marker := _build_move_path_preview_marker(index, path.size())
		marker.position = Vector3(
			float(grid.get("x", 0)),
			float(grid.get("y", observed_level)) + 0.12,
			float(grid.get("z", 0))
		)
		marker.set_meta("grid", grid.duplicate(true))
		marker.set_meta("path_index", index)
		marker.set_meta("step_cost", step_index)
		marker.set_meta("reachable", bool(move_preview.get("reachable", false)))
		marker.set_meta("reason", str(move_preview.get("reason", "")))
		move_path_preview_markers.add_child(marker)
		index += 1
	move_path_preview_markers.set_meta("marker_count", index)
	move_path_preview_markers.set_meta("path_length", path.size())
	move_path_preview_markers.set_meta("reachable", bool(move_preview.get("reachable", false)))
	move_path_preview_markers.set_meta("reason", str(move_preview.get("reason", "")))
	move_path_preview_markers.set_meta("steps", int(move_preview.get("steps", 0)))
	move_path_preview_markers.set_meta("ap_cost", float(move_preview.get("ap_cost", 0.0)))
	move_path_preview_markers.set_meta("ap_available", float(move_preview.get("ap_available", 0.0)))


func clear_move_path_preview_markers() -> void:
	if move_path_preview_markers == null:
		return
	for child in move_path_preview_markers.get_children():
		child.queue_free()
	move_path_preview_markers.set_meta("marker_count", 0)
	move_path_preview_markers.set_meta("path_length", 0)
	move_path_preview_markers.set_meta("reachable", false)
	move_path_preview_markers.set_meta("reason", "")
	move_path_preview_markers.set_meta("steps", 0)
	move_path_preview_markers.set_meta("ap_cost", 0.0)
	move_path_preview_markers.set_meta("ap_available", 0.0)
	move_path_preview_markers.set_meta("current_movement_step_index", 0)
	move_path_preview_markers.set_meta("visible_marker_count", 0)


func sync_move_path_preview_with_active_movement(movement_snapshot: Dictionary) -> void:
	if move_path_preview_markers == null:
		return
	if move_path_preview_markers.get_child_count() <= 0:
		return
	if not bool(movement_snapshot.get("active", false)) or str(movement_snapshot.get("kind", "")) != "movement":
		if _move_path_preview_reached_presenter_target(movement_snapshot):
			clear_move_path_preview_markers()
		return
	var current_step_index := int(movement_snapshot.get("current_step_index", 0))
	var path: Array = _array_or_empty(movement_snapshot.get("path", []))
	var target_key := _grid_key(_dictionary_or_empty(path[path.size() - 1])) if not path.is_empty() else ""
	for child in move_path_preview_markers.get_children():
		var marker := child as Node
		if marker == null:
			continue
		var marker_index := int(marker.get_meta("path_index", -1))
		var marker_grid: Dictionary = _dictionary_or_empty(marker.get_meta("grid", {}))
		var marker_key := _grid_key(marker_grid)
		var passed_step := marker_index >= 0 and marker_index <= current_step_index
		if target_key != "" and marker_key == target_key and marker_index == current_step_index:
			passed_step = false
		if marker is Node3D:
			(marker as Node3D).visible = not passed_step
		elif marker is CanvasItem:
			(marker as CanvasItem).visible = not passed_step
	move_path_preview_markers.set_meta("current_movement_step_index", current_step_index)
	move_path_preview_markers.set_meta("visible_marker_count", _visible_child_count(move_path_preview_markers))


func sync_move_path_preview_with_action_queue(queue_snapshot: Dictionary, observed_level: int) -> void:
	if move_path_preview_markers == null:
		return
	if queue_snapshot.is_empty() or not bool(queue_snapshot.get("active", false)):
		clear_move_path_preview_markers()
		return
	var path: Array = _array_or_empty(queue_snapshot.get("remaining_move_path", []))
	if path.is_empty():
		clear_move_path_preview_markers()
		return
	var signature := "%s|%s|%d" % [
		str(queue_snapshot.get("queue_id", 0)),
		str(_dictionary_or_empty(queue_snapshot.get("current_action", {})).get("action_id", 0)),
		path.size(),
	]
	if str(move_path_preview_markers.get_meta("queue_signature", "")) == signature:
		return
	clear_move_path_preview_markers()
	var index := 0
	for cell in path:
		var grid: Dictionary = _dictionary_or_empty(cell)
		if grid.is_empty():
			continue
		var marker := _build_move_path_preview_marker(index, path.size())
		marker.position = Vector3(
			float(grid.get("x", 0)),
			float(grid.get("y", observed_level)) + 0.12,
			float(grid.get("z", 0))
		)
		marker.set_meta("grid", grid.duplicate(true))
		marker.set_meta("path_index", index)
		marker.set_meta("step_cost", index + 1)
		marker.set_meta("reachable", true)
		marker.set_meta("source", "action_queue")
		move_path_preview_markers.add_child(marker)
		index += 1
	move_path_preview_markers.set_meta("queue_signature", signature)
	move_path_preview_markers.set_meta("marker_count", index)
	move_path_preview_markers.set_meta("path_length", path.size())
	move_path_preview_markers.set_meta("reachable", true)
	move_path_preview_markers.set_meta("reason", "")
	move_path_preview_markers.set_meta("steps", path.size())
	move_path_preview_markers.set_meta("ap_cost", float(path.size()))
	move_path_preview_markers.set_meta("ap_available", float(path.size()))
	move_path_preview_markers.set_meta("current_movement_step_index", int(_dictionary_or_empty(queue_snapshot.get("compat", {})).get("completed_steps", 0)))
	move_path_preview_markers.set_meta("visible_marker_count", index)


func update_pending_movement_path_markers(pending: Dictionary, observed_level: int) -> void:
	if pending_movement_path_markers == null:
		return
	if pending.is_empty():
		clear_pending_movement_path_markers()
		return
	var path: Array = _array_or_empty(pending.get("path", []))
	if path.is_empty():
		clear_pending_movement_path_markers()
		return
	var signature := "%s|%s|%d|%.2f|%.2f" % [
		str(pending.get("actor_id", 0)),
		JSON.stringify(pending.get("target_position", {})),
		path.size(),
		float(pending.get("required_ap", 0.0)),
		float(pending.get("available_ap", 0.0)),
	]
	if str(pending_movement_path_markers.get_meta("signature", "")) == signature:
		return
	clear_pending_movement_path_markers()
	var index := 0
	for cell in path:
		var grid: Dictionary = _dictionary_or_empty(cell)
		if grid.is_empty():
			continue
		var marker := _build_pending_movement_path_marker(index, path.size())
		marker.position = Vector3(
			float(grid.get("x", 0)),
			float(grid.get("y", observed_level)) + 0.18,
			float(grid.get("z", 0))
		)
		marker.set_meta("grid", grid.duplicate(true))
		marker.set_meta("path_index", index)
		marker.set_meta("step_cost", max(0, index))
		marker.set_meta("actor_id", int(pending.get("actor_id", 0)))
		marker.set_meta("target_position", _dictionary_or_empty(pending.get("target_position", {})).duplicate(true))
		marker.set_meta("required_ap", float(pending.get("required_ap", 0.0)))
		marker.set_meta("available_ap", float(pending.get("available_ap", 0.0)))
		pending_movement_path_markers.add_child(marker)
		index += 1
	pending_movement_path_markers.set_meta("signature", signature)
	pending_movement_path_markers.set_meta("marker_count", index)
	pending_movement_path_markers.set_meta("path_length", path.size())
	pending_movement_path_markers.set_meta("actor_id", int(pending.get("actor_id", 0)))
	pending_movement_path_markers.set_meta("target_position", _dictionary_or_empty(pending.get("target_position", {})).duplicate(true))
	pending_movement_path_markers.set_meta("required_ap", float(pending.get("required_ap", 0.0)))
	pending_movement_path_markers.set_meta("available_ap", float(pending.get("available_ap", 0.0)))
	pending_movement_path_markers.set_meta("remaining_steps", max(0, path.size() - 1))


func clear_pending_movement_path_markers() -> void:
	if pending_movement_path_markers == null:
		return
	for child in pending_movement_path_markers.get_children():
		child.queue_free()
	pending_movement_path_markers.set_meta("signature", "")
	pending_movement_path_markers.set_meta("marker_count", 0)
	pending_movement_path_markers.set_meta("path_length", 0)
	pending_movement_path_markers.set_meta("actor_id", 0)
	pending_movement_path_markers.set_meta("target_position", {})
	pending_movement_path_markers.set_meta("required_ap", 0.0)
	pending_movement_path_markers.set_meta("available_ap", 0.0)
	pending_movement_path_markers.set_meta("remaining_steps", 0)


func update_skill_target_preview_markers(preview: Dictionary, runtime_snapshot: Dictionary, observed_level: int) -> void:
	_skill_target_preview_controller.update_preview_markers(skill_target_preview_markers, preview, runtime_snapshot, observed_level)


func clear_skill_target_preview_markers() -> void:
	_skill_target_preview_controller.clear_preview_markers(skill_target_preview_markers)


func _grid_in_bounds(grid: Dictionary, bounds: Dictionary) -> bool:
	if bounds.is_empty():
		return true
	var x := int(grid.get("x", 0))
	var z := int(grid.get("z", 0))
	return x >= int(bounds.get("min_x", x)) \
		and x <= int(bounds.get("max_x", x)) \
		and z >= int(bounds.get("min_z", z)) \
		and z <= int(bounds.get("max_z", z))


func _build_hover_cursor() -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.92, 0.045, 0.92)
	var material := StandardMaterial3D.new()
	material.albedo_color = HOVER_COLOR_INTERACTION
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "HoverGridCursor"
	node.mesh = mesh
	node.material_override = material
	node.visible = false
	return node


func _build_hover_target_outline() -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.50
	mesh.bottom_radius = 0.50
	mesh.height = 0.72
	mesh.radial_segments = 20
	var material := StandardMaterial3D.new()
	material.albedo_color = HOVER_COLOR_INTERACTION
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "HoverTargetOutline"
	node.mesh = mesh
	node.material_override = material
	node.visible = false
	return node


func _build_attack_target_marker() -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.38
	mesh.outer_radius = 0.48
	var material := StandardMaterial3D.new()
	material.albedo_color = HOVER_COLOR_ATTACK_REACHABLE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "AttackTargetMarker"
	node.mesh = mesh
	node.material_override = material
	node.visible = false
	node.rotation_degrees.x = 90.0
	return node


func _build_attack_target_outline() -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.48
	mesh.bottom_radius = 0.48
	mesh.height = 1.48
	mesh.radial_segments = 24
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(HOVER_COLOR_ATTACK_REACHABLE.r, HOVER_COLOR_ATTACK_REACHABLE.g, HOVER_COLOR_ATTACK_REACHABLE.b, 0.24)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "AttackTargetOutline"
	node.mesh = mesh
	node.material_override = material
	node.visible = false
	return node


func _build_attack_range_marker(color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.66, 0.035, 0.66)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.34)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "AttackRangeMarker"
	node.mesh = mesh
	node.material_override = material
	return node


func _build_move_path_preview_marker(index: int, path_length: int) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	var radius := 0.24 if index == 0 or index == path_length - 1 else 0.19
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.032
	mesh.radial_segments = 24
	var material := StandardMaterial3D.new()
	material.albedo_color = MOVE_PATH_DOT_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "MovePathPreviewMarker"
	node.mesh = mesh
	node.material_override = material
	return node


func _build_pending_movement_path_marker(index: int, path_length: int) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	var radius := 0.28 if index == path_length - 1 else 0.21
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.036
	mesh.radial_segments = 24
	var material := StandardMaterial3D.new()
	material.albedo_color = PENDING_MOVE_PATH_DOT_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var node := MeshInstance3D.new()
	node.name = "PendingMovementPathMarker"
	node.mesh = mesh
	node.material_override = material
	return node


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _move_path_preview_reached_presenter_target(movement_snapshot: Dictionary) -> bool:
	if str(movement_snapshot.get("kind", "")) != "movement":
		return false
	var path: Array = _array_or_empty(movement_snapshot.get("path", []))
	if path.is_empty():
		return false
	var target_key := _grid_key(_dictionary_or_empty(path[path.size() - 1]))
	if target_key == "":
		return false
	for child in move_path_preview_markers.get_children():
		var marker := child as Node
		if marker != null and _grid_key(_dictionary_or_empty(marker.get_meta("grid", {}))) == target_key:
			return true
	return false


func _visible_child_count(parent: Node) -> int:
	var count := 0
	for child in parent.get_children():
		if child is CanvasItem and (child as CanvasItem).visible:
			count += 1
		elif child is Node3D and (child as Node3D).visible:
			count += 1
	return count


func _grid_key(grid: Dictionary) -> String:
	if grid.is_empty():
		return ""
	return "%d:%d:%d" % [int(grid.get("x", 0)), int(grid.get("y", 0)), int(grid.get("z", 0))]
