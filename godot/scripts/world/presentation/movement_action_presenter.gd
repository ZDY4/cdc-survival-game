extends RefCounted

const PresentationTracker = preload("res://scripts/world/presentation/presentation_tracker.gd")
const PresentationMaterials = preload("res://scripts/world/presentation/presentation_materials.gd")
const PresentationNodeFactory = preload("res://scripts/world/presentation/presentation_node_factory.gd")

const GRID_SIZE := 1.0
const DEFAULT_ACTOR_Y := 0.58
const STEP_DURATION_SEC := 0.07
const DOOR_AUTO_OPEN_PHASES := ["approach", "open", "clear"]
const PENDING_MOVEMENT_SEGMENT_PHASES := ["queued", "preview", "hold"]
const DOOR_AUTO_OPEN_PHASE_DURATIONS := [0.04, 0.08, 0.08]
const PENDING_MOVEMENT_SEGMENT_PHASE_DURATIONS := [0.04, 0.08, 0.12]

var _tracker := PresentationTracker.new()
var _materials := PresentationMaterials.new()
var _node_factory := PresentationNodeFactory.new()


func configure(tracker: RefCounted, materials: RefCounted, node_factory: RefCounted) -> void:
	if tracker != null:
		_tracker = tracker
	if materials != null:
		_materials = materials
	if node_factory != null:
		_node_factory = node_factory


func movement_presentation(events: Array, world_root: Node, world_result: Dictionary) -> Dictionary:
	var last_move: Dictionary = {}
	var step_events: Array[Dictionary] = []
	var door_auto_open_events: Array[Dictionary] = []
	var movement_queued_events: Array[Dictionary] = []
	for event_value in events:
		var event: Dictionary = _dictionary_or_empty(event_value)
		match str(event.get("kind", "")):
			"movement_step":
				step_events.append(event)
			"actor_moved":
				last_move = event
			"door_auto_opened":
				door_auto_open_events.append(event)
			"movement_queued":
				movement_queued_events.append(event)
	if last_move.is_empty():
		return {}
	var payload: Dictionary = _dictionary_or_empty(last_move.get("payload", {}))
	var actor_id := int(payload.get("actor_id", 0))
	var actor_node := _actor_node(world_root, world_result, actor_id)
	if actor_node == null:
		return {
			"active": false,
			"kind": "movement",
			"reason": "actor_node_missing",
			"actor_id": actor_id,
		}
	var path := _movement_path(actor_id, payload, step_events)
	var door_auto_opens := _movement_door_auto_opens(actor_id, door_auto_open_events)
	var pending_segment := _movement_pending_segment(actor_id, movement_queued_events, path)
	var movement_facings := _movement_facings_from_path(path)
	var current_facing: Dictionary = _dictionary_or_empty(movement_facings[0]) if not movement_facings.is_empty() else {}
	var final_facing: Dictionary = _dictionary_or_empty(movement_facings[movement_facings.size() - 1]) if not movement_facings.is_empty() else {}
	return {
		"active": path.size() > 1,
		"kind": "movement",
		"actor_id": actor_id,
		"node_path": str(actor_node.get_path()),
		"path": path,
		"step_count": max(0, path.size() - 1),
		"duration_sec": float(max(0, path.size() - 1)) * STEP_DURATION_SEC,
		"movement_facings": movement_facings,
		"current_step_index": int(current_facing.get("step_index", 0)),
		"current_facing_direction": str(current_facing.get("direction", "")),
		"current_facing_yaw_degrees": float(current_facing.get("yaw_degrees", actor_node.rotation_degrees.y)),
		"final_facing_direction": str(final_facing.get("direction", "")),
		"final_facing_yaw_degrees": float(final_facing.get("yaw_degrees", actor_node.rotation_degrees.y)),
		"door_auto_opens": door_auto_opens,
		"door_auto_open_count": door_auto_opens.size(),
		"door_auto_open_door_ids": _door_auto_open_ids(door_auto_opens),
		"pending_movement_segment": pending_segment,
		"pending_movement_segment_active": bool(pending_segment.get("active", false)),
		"pending_movement_remaining_steps": int(pending_segment.get("remaining_steps", 0)),
		"pending_movement_required_ap": float(pending_segment.get("required_ap", 0.0)),
		"pending_movement_available_ap": float(pending_segment.get("available_ap", 0.0)),
		"actor_node": actor_node,
	}


func movement_cancelled_presentation(events: Array, world_root: Node, world_result: Dictionary) -> Dictionary:
	var selected_payload: Dictionary = {}
	for event_value in events:
		var event: Dictionary = _dictionary_or_empty(event_value)
		if str(event.get("kind", "")) != "movement_cancelled":
			continue
		selected_payload = _dictionary_or_empty(event.get("payload", {}))
	if selected_payload.is_empty():
		return {}
	var actor_id := int(selected_payload.get("actor_id", 0))
	var pending_movement: Dictionary = _dictionary_or_empty(selected_payload.get("pending_movement", {})).duplicate(true)
	var actor_node := _actor_node(world_root, world_result, actor_id)
	var cleared_marker_count := clear_pending_movement_segment_markers(world_root, actor_id)
	var cleared_actor_metadata := clear_pending_movement_actor_metadata(actor_node)
	return {
		"active": false,
		"kind": "movement_cancelled",
		"actor_id": actor_id,
		"reason": str(selected_payload.get("reason", "")),
		"pending_movement": pending_movement,
		"target_position": _dictionary_or_empty(pending_movement.get("target_position", {})).duplicate(true),
		"path": _array_or_empty(pending_movement.get("path", [])).duplicate(true),
		"remaining_steps": int(pending_movement.get("remaining_steps", max(0, _array_or_empty(pending_movement.get("path", [])).size() - 1))),
		"required_ap": float(pending_movement.get("required_ap", 0.0)),
		"available_ap": float(pending_movement.get("available_ap", 0.0)),
		"cleared_marker_count": cleared_marker_count,
		"cleared_actor_metadata": cleared_actor_metadata,
		"node_path": str(actor_node.get_path()) if actor_node != null else "",
	}


func start_movement_tween(host: Node, world_root: Node, movement: Dictionary) -> void:
	var actor_node: Node3D = movement.get("actor_node", null)
	var path: Array = _array_or_empty(movement.get("path", []))
	if actor_node == null or path.size() <= 1:
		_record_latest(movement_public_snapshot(movement, false))
		return
	var run_sequence := _tracker.next_sequence()
	var y := actor_node.position.y
	actor_node.position = _grid_to_world(_dictionary_or_empty(path[0]), y)
	var door_auto_opens: Array = _array_or_empty(movement.get("door_auto_opens", []))
	var door_auto_open_ids: Array = _array_or_empty(movement.get("door_auto_open_door_ids", []))
	var movement_facings: Array = _array_or_empty(movement.get("movement_facings", []))
	var final_facing: Dictionary = _dictionary_or_empty(movement_facings[movement_facings.size() - 1]) if not movement_facings.is_empty() else {}
	actor_node.set_meta("action_presenter_active", true)
	actor_node.set_meta("action_presenter_kind", "movement")
	actor_node.set_meta("action_presenter_sequence", run_sequence)
	actor_node.set_meta("action_presenter_step_count", max(0, path.size() - 1))
	actor_node.set_meta("action_presenter_final_position", _grid_to_world(_dictionary_or_empty(path[path.size() - 1]), y))
	actor_node.set_meta("action_presenter_final_rotation_degrees", Vector3(actor_node.rotation_degrees.x, float(final_facing.get("yaw_degrees", actor_node.rotation_degrees.y)), actor_node.rotation_degrees.z))
	actor_node.set_meta("action_presenter_movement_facings", movement_facings.duplicate(true))
	actor_node.set_meta("action_presenter_final_facing_direction", str(final_facing.get("direction", "")))
	actor_node.set_meta("action_presenter_final_facing_yaw_degrees", float(final_facing.get("yaw_degrees", actor_node.rotation_degrees.y)))
	actor_node.set_meta("action_presenter_auto_opened_door_ids", door_auto_open_ids.duplicate(true))
	actor_node.set_meta("action_presenter_auto_opened_door_count", door_auto_opens.size())
	var pending_segment: Dictionary = _dictionary_or_empty(movement.get("pending_movement_segment", {}))
	actor_node.set_meta("action_presenter_pending_movement_segment_active", bool(pending_segment.get("active", false)))
	actor_node.set_meta("action_presenter_pending_movement_target_position", _dictionary_or_empty(pending_segment.get("target_position", {})).duplicate(true))
	actor_node.set_meta("action_presenter_pending_movement_remaining_steps", int(pending_segment.get("remaining_steps", 0)))
	actor_node.set_meta("action_presenter_pending_movement_required_ap", float(pending_segment.get("required_ap", 0.0)))
	actor_node.set_meta("action_presenter_pending_movement_available_ap", float(pending_segment.get("available_ap", 0.0)))
	if not movement_facings.is_empty():
		_apply_movement_facing(weakref(actor_node), _dictionary_or_empty(movement_facings[0]))
	_track_active_node(actor_node)
	var door_marker_paths := _start_door_auto_open_markers(host, world_root, movement, path)
	var pending_marker_paths := _start_pending_movement_segment_markers(host, world_root, movement)
	var tween := host.create_tween()
	_track_active_tween(tween)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	for index in range(1, path.size()):
		if index - 1 < movement_facings.size():
			tween.tween_callback(Callable(self, "_apply_movement_facing").bind(weakref(actor_node), _dictionary_or_empty(movement_facings[index - 1])))
		tween.tween_property(actor_node, "position", _grid_to_world(_dictionary_or_empty(path[index]), y), STEP_DURATION_SEC)
	tween.finished.connect(Callable(self, "_on_movement_tween_finished").bind(run_sequence, weakref(actor_node)))
	var snapshot_data := movement_public_snapshot(movement, true)
	snapshot_data["door_auto_open_marker_paths"] = door_marker_paths
	snapshot_data["pending_movement_segment_marker_paths"] = pending_marker_paths
	_record_latest(snapshot_data)


func movement_public_snapshot(presentation: Dictionary, active: bool) -> Dictionary:
	return {
		"active": active,
		"kind": str(presentation.get("kind", "")),
		"actor_id": int(presentation.get("actor_id", 0)),
		"node_path": str(presentation.get("node_path", "")),
		"path": _array_or_empty(presentation.get("path", [])).duplicate(true),
		"step_count": int(presentation.get("step_count", 0)),
		"duration_sec": float(presentation.get("duration_sec", 0.0)),
		"movement_facings": _array_or_empty(presentation.get("movement_facings", [])).duplicate(true),
		"final_facing_direction": str(presentation.get("final_facing_direction", "")),
		"final_facing_yaw_degrees": float(presentation.get("final_facing_yaw_degrees", 0.0)),
		"current_step_index": int(presentation.get("current_step_index", 0)),
		"current_facing_direction": str(presentation.get("current_facing_direction", "")),
		"current_facing_yaw_degrees": float(presentation.get("current_facing_yaw_degrees", 0.0)),
		"door_auto_opens": _array_or_empty(presentation.get("door_auto_opens", [])).duplicate(true),
		"door_auto_open_count": int(presentation.get("door_auto_open_count", 0)),
		"door_auto_open_door_ids": _array_or_empty(presentation.get("door_auto_open_door_ids", [])).duplicate(true),
		"pending_movement_segment": _dictionary_or_empty(presentation.get("pending_movement_segment", {})).duplicate(true),
		"pending_movement_segment_active": bool(presentation.get("pending_movement_segment_active", false)),
		"pending_movement_remaining_steps": int(presentation.get("pending_movement_remaining_steps", 0)),
		"pending_movement_required_ap": float(presentation.get("pending_movement_required_ap", 0.0)),
		"pending_movement_available_ap": float(presentation.get("pending_movement_available_ap", 0.0)),
	}


func movement_cancelled_public_snapshot(presentation: Dictionary) -> Dictionary:
	return {
		"active": false,
		"kind": "movement_cancelled",
		"actor_id": int(presentation.get("actor_id", 0)),
		"reason": str(presentation.get("reason", "")),
		"node_path": str(presentation.get("node_path", "")),
		"pending_movement": _dictionary_or_empty(presentation.get("pending_movement", {})).duplicate(true),
		"target_position": _dictionary_or_empty(presentation.get("target_position", {})).duplicate(true),
		"path": _array_or_empty(presentation.get("path", [])).duplicate(true),
		"remaining_steps": int(presentation.get("remaining_steps", 0)),
		"required_ap": float(presentation.get("required_ap", 0.0)),
		"available_ap": float(presentation.get("available_ap", 0.0)),
		"cleared_marker_count": int(presentation.get("cleared_marker_count", 0)),
		"cleared_actor_metadata": bool(presentation.get("cleared_actor_metadata", false)),
	}


func clear_pending_movement_segment_markers(world_root: Node, actor_id: int) -> int:
	if world_root == null:
		return 0
	var cleared := 0
	var layer := world_root.find_child("WorldActionPresentationLayer", false, false)
	if layer == null:
		return 0
	for child in layer.get_children():
		var node := child as Node
		if node == null:
			continue
		if str(node.name) != "WorldActionPendingMovementSegment":
			continue
		if actor_id > 0 and int(node.get_meta("actor_id", 0)) != actor_id:
			continue
		node.set_meta("action_presenter_active", false)
		node.set_meta("action_presenter_cancelled", true)
		node.queue_free()
		cleared += 1
	_tracker.prune_active_refs()
	return cleared


func clear_pending_movement_actor_metadata(actor_node: Node3D) -> bool:
	if actor_node == null:
		return false
	actor_node.set_meta("action_presenter_pending_movement_segment_active", false)
	actor_node.set_meta("action_presenter_pending_movement_target_position", {})
	actor_node.set_meta("action_presenter_pending_movement_remaining_steps", 0)
	actor_node.set_meta("action_presenter_pending_movement_required_ap", 0.0)
	actor_node.set_meta("action_presenter_pending_movement_available_ap", 0.0)
	actor_node.set_meta("action_presenter_pending_movement_cancelled", true)
	return true


func _movement_door_auto_opens(actor_id: int, events: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for event in events:
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		if int(payload.get("actor_id", 0)) != actor_id:
			continue
		var grid: Dictionary = _dictionary_or_empty(payload.get("grid", {}))
		output.append({
			"actor_id": actor_id,
			"door_id": str(payload.get("door_id", "")),
			"grid": grid.duplicate(true),
			"is_open": true,
		})
	return output


func _door_auto_open_ids(entries: Array[Dictionary]) -> Array[String]:
	var output: Array[String] = []
	for entry in entries:
		var door_id := str(entry.get("door_id", ""))
		if door_id.is_empty() or output.has(door_id):
			continue
		output.append(door_id)
	return output


func _movement_pending_segment(actor_id: int, events: Array[Dictionary], completed_path: Array[Dictionary]) -> Dictionary:
	var queued_payload: Dictionary = {}
	for event in events:
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		if int(payload.get("actor_id", 0)) != actor_id:
			continue
		queued_payload = payload
	if queued_payload.is_empty():
		return {}
	var pending_path: Array[Dictionary] = []
	for grid_value in _array_or_empty(queued_payload.get("path", [])):
		var grid: Dictionary = _dictionary_or_empty(grid_value)
		if not grid.is_empty():
			pending_path.append(grid.duplicate(true))
	var completed_end: Dictionary = _dictionary_or_empty(completed_path[completed_path.size() - 1]) if not completed_path.is_empty() else {}
	if not completed_end.is_empty():
		if pending_path.is_empty() or _grid_key(_dictionary_or_empty(pending_path[0])) != _grid_key(completed_end):
			pending_path.push_front(completed_end.duplicate(true))
	pending_path = _dedupe_grid_path(pending_path)
	var target_position: Dictionary = _dictionary_or_empty(queued_payload.get("target_position", {})).duplicate(true)
	if target_position.is_empty() and not pending_path.is_empty():
		target_position = _dictionary_or_empty(pending_path[pending_path.size() - 1]).duplicate(true)
	var remaining_steps := int(queued_payload.get("remaining_steps", max(0, pending_path.size() - 1)))
	var next_grid: Dictionary = {}
	if pending_path.size() > 1:
		next_grid = _dictionary_or_empty(pending_path[1]).duplicate(true)
	elif not pending_path.is_empty():
		next_grid = _dictionary_or_empty(pending_path[0]).duplicate(true)
	return {
		"active": remaining_steps > 0 and not target_position.is_empty(),
		"actor_id": actor_id,
		"target_position": target_position,
		"path": pending_path,
		"next_grid": next_grid,
		"remaining_steps": remaining_steps,
		"required_ap": float(queued_payload.get("required_ap", 0.0)),
		"available_ap": float(queued_payload.get("available_ap", 0.0)),
		"completed_step_count": max(0, completed_path.size() - 1),
		"queued_step_count": remaining_steps,
	}


func _movement_path(actor_id: int, moved_payload: Dictionary, step_events: Array[Dictionary]) -> Array[Dictionary]:
	var path: Array[Dictionary] = []
	var from: Dictionary = _dictionary_or_empty(moved_payload.get("from", {}))
	if not from.is_empty():
		path.append(from.duplicate(true))
	for event in step_events:
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		if int(payload.get("actor_id", 0)) != actor_id:
			continue
		var step: Dictionary = _dictionary_or_empty(payload.get("to", {}))
		if not step.is_empty():
			path.append(step.duplicate(true))
	var to: Dictionary = _dictionary_or_empty(moved_payload.get("to", {}))
	if not to.is_empty():
		path.append(to.duplicate(true))
	return _dedupe_grid_path(path)


func _movement_facings_from_path(path: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for index in range(1, path.size()):
		var facing := _movement_facing_from_grids(_dictionary_or_empty(path[index - 1]), _dictionary_or_empty(path[index]), index)
		if not facing.is_empty():
			output.append(facing)
	return output


func _movement_facing_from_grids(from_grid: Dictionary, to_grid: Dictionary, step_index: int) -> Dictionary:
	if from_grid.is_empty() or to_grid.is_empty():
		return {}
	var dx := int(to_grid.get("x", 0)) - int(from_grid.get("x", 0))
	var dz := int(to_grid.get("z", 0)) - int(from_grid.get("z", 0))
	if dx == 0 and dz == 0:
		return {}
	var direction := _movement_cardinal_direction(dx, dz)
	return {
		"step_index": step_index,
		"direction": direction,
		"yaw_degrees": _movement_direction_yaw_degrees(direction),
		"from": from_grid.duplicate(true),
		"to": to_grid.duplicate(true),
	}


func _movement_cardinal_direction(dx: int, dz: int) -> String:
	if abs(dx) >= abs(dz):
		return "east" if dx > 0 else "west"
	return "south" if dz > 0 else "north"


func _movement_direction_yaw_degrees(direction: String) -> float:
	match direction:
		"east":
			return 90.0
		"south":
			return 180.0
		"west":
			return 270.0
	return 0.0


func _dedupe_grid_path(path: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var last_key := ""
	for grid in path:
		var key := _grid_key(grid)
		if key.is_empty() or key == last_key:
			continue
		output.append(grid.duplicate(true))
		last_key = key
	return output


func _apply_movement_facing(actor_ref: WeakRef, facing: Dictionary) -> void:
	var actor_node := actor_ref.get_ref() as Node3D
	if actor_node == null or actor_node.is_queued_for_deletion() or facing.is_empty():
		return
	var yaw := float(facing.get("yaw_degrees", actor_node.rotation_degrees.y))
	actor_node.rotation_degrees = Vector3(actor_node.rotation_degrees.x, yaw, actor_node.rotation_degrees.z)
	actor_node.set_meta("action_presenter_current_step_index", int(facing.get("step_index", 0)))
	actor_node.set_meta("action_presenter_current_facing_direction", str(facing.get("direction", "")))
	actor_node.set_meta("action_presenter_current_facing_yaw_degrees", yaw)
	_tracker.set_latest_value("current_step_index", int(facing.get("step_index", 0)))
	_tracker.set_latest_value("current_facing_direction", str(facing.get("direction", "")))
	_tracker.set_latest_value("current_facing_yaw_degrees", yaw)


func _start_door_auto_open_markers(host: Node, world_root: Node, movement: Dictionary, path: Array) -> Array[String]:
	var marker_paths: Array[String] = []
	var door_auto_opens: Array = _array_or_empty(movement.get("door_auto_opens", []))
	if host == null or world_root == null or door_auto_opens.is_empty():
		return marker_paths
	var layer := _presentation_layer(world_root)
	for index in range(door_auto_opens.size()):
		var entry: Dictionary = _dictionary_or_empty(door_auto_opens[index])
		var grid: Dictionary = _dictionary_or_empty(entry.get("grid", {}))
		if grid.is_empty():
			continue
		var marker := _node_factory.cylinder_marker("WorldActionDoorAutoOpen", 0.30, 0.46, 0.08, 24, _materials.door_auto_open_material())
		marker.position = _grid_to_world(grid, 0.36)
		marker.scale = Vector3(0.72, 1.0, 0.72)
		marker.set_meta("action_presenter_active", true)
		marker.set_meta("action_presenter_kind", "door_auto_open")
		marker.set_meta("action_presenter_phases", DOOR_AUTO_OPEN_PHASES.duplicate())
		marker.set_meta("action_presenter_phase_count", DOOR_AUTO_OPEN_PHASES.size())
		marker.set_meta("action_presenter_current_phase", DOOR_AUTO_OPEN_PHASES[0])
		marker.set_meta("action_presenter_duration_sec", _duration_sum(DOOR_AUTO_OPEN_PHASE_DURATIONS))
		marker.set_meta("action_presenter_sequence", _tracker.current_sequence())
		marker.set_meta("actor_id", int(entry.get("actor_id", 0)))
		marker.set_meta("door_id", str(entry.get("door_id", "")))
		marker.set_meta("door_grid", grid.duplicate(true))
		marker.set_meta("movement_step_index", _path_index_for_grid(path, grid))
		_track_active_node(marker)
		layer.add_child(marker)
		marker_paths.append(str(marker.get_path()))
		var tween := host.create_tween()
		_track_active_tween(tween)
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(marker, "scale", Vector3(0.95, 1.0, 0.95), float(DOOR_AUTO_OPEN_PHASE_DURATIONS[0]))
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), DOOR_AUTO_OPEN_PHASES[1]))
		tween.tween_property(marker, "scale", Vector3(1.34, 1.12, 1.34), float(DOOR_AUTO_OPEN_PHASE_DURATIONS[1]))
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), DOOR_AUTO_OPEN_PHASES[2]))
		tween.tween_property(marker, "scale", Vector3(0.45, 0.8, 0.45), float(DOOR_AUTO_OPEN_PHASE_DURATIONS[2]))
		tween.finished.connect(Callable(self, "_on_door_auto_open_marker_finished").bind(weakref(marker)))
	return marker_paths


func _on_door_auto_open_marker_finished(marker_ref: WeakRef) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker != null and not marker.is_queued_for_deletion():
		marker.set_meta("action_presenter_active", false)
		marker.queue_free()
	_tracker.prune_active_refs()
	_tracker.refresh_latest_active()


func _start_pending_movement_segment_markers(host: Node, world_root: Node, movement: Dictionary) -> Array[String]:
	var marker_paths: Array[String] = []
	var segment: Dictionary = _dictionary_or_empty(movement.get("pending_movement_segment", {}))
	if host == null or world_root == null or not bool(segment.get("active", false)):
		return marker_paths
	var path: Array = _array_or_empty(segment.get("path", []))
	if path.is_empty():
		return marker_paths
	var layer := _presentation_layer(world_root)
	var target_grid: Dictionary = _dictionary_or_empty(segment.get("target_position", {}))
	var next_grid: Dictionary = _dictionary_or_empty(segment.get("next_grid", target_grid))
	for index in range(path.size()):
		var grid: Dictionary = _dictionary_or_empty(path[index])
		if grid.is_empty():
			continue
		var marker := _node_factory.cylinder_marker("WorldActionPendingMovementSegment", 0.18, 0.28, 0.045, 20, _materials.pending_movement_segment_material(index, path.size()))
		marker.position = _grid_to_world(grid, 0.18)
		marker.scale = Vector3(0.72, 1.0, 0.72)
		marker.set_meta("action_presenter_active", true)
		marker.set_meta("action_presenter_kind", "pending_movement_segment")
		marker.set_meta("action_presenter_phases", PENDING_MOVEMENT_SEGMENT_PHASES.duplicate())
		marker.set_meta("action_presenter_phase_count", PENDING_MOVEMENT_SEGMENT_PHASES.size())
		marker.set_meta("action_presenter_current_phase", PENDING_MOVEMENT_SEGMENT_PHASES[0])
		marker.set_meta("action_presenter_duration_sec", _duration_sum(PENDING_MOVEMENT_SEGMENT_PHASE_DURATIONS))
		marker.set_meta("action_presenter_sequence", _tracker.current_sequence())
		marker.set_meta("actor_id", int(segment.get("actor_id", 0)))
		marker.set_meta("grid", grid.duplicate(true))
		marker.set_meta("path_index", index)
		marker.set_meta("target_position", target_grid.duplicate(true))
		marker.set_meta("next_grid", next_grid.duplicate(true))
		marker.set_meta("remaining_steps", int(segment.get("remaining_steps", 0)))
		marker.set_meta("required_ap", float(segment.get("required_ap", 0.0)))
		marker.set_meta("available_ap", float(segment.get("available_ap", 0.0)))
		marker.set_meta("completed_step_count", int(segment.get("completed_step_count", 0)))
		marker.set_meta("queued_step_count", int(segment.get("queued_step_count", 0)))
		_track_active_node(marker)
		layer.add_child(marker)
		marker_paths.append(str(marker.get_path()))
		var tween := host.create_tween()
		_track_active_tween(tween)
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_OUT)
		var delay := float(index) * 0.015
		if delay > 0.0:
			tween.tween_interval(delay)
		tween.tween_property(marker, "scale", Vector3(0.92, 1.0, 0.92), float(PENDING_MOVEMENT_SEGMENT_PHASE_DURATIONS[0]))
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), PENDING_MOVEMENT_SEGMENT_PHASES[1]))
		tween.tween_property(marker, "scale", Vector3(1.08, 1.0, 1.08), float(PENDING_MOVEMENT_SEGMENT_PHASE_DURATIONS[1]))
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), PENDING_MOVEMENT_SEGMENT_PHASES[2]))
		tween.tween_property(marker, "scale", Vector3(0.55, 1.0, 0.55), float(PENDING_MOVEMENT_SEGMENT_PHASE_DURATIONS[2]))
		tween.finished.connect(Callable(self, "_on_pending_movement_segment_marker_finished").bind(weakref(marker)))
	return marker_paths


func _on_pending_movement_segment_marker_finished(marker_ref: WeakRef) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker != null and not marker.is_queued_for_deletion():
		marker.set_meta("action_presenter_active", false)
		marker.queue_free()
	_tracker.prune_active_refs()
	_tracker.refresh_latest_active()


func _path_index_for_grid(path: Array, grid: Dictionary) -> int:
	var key := _grid_key(grid)
	if key.is_empty():
		return -1
	for index in range(path.size()):
		if _grid_key(_dictionary_or_empty(path[index])) == key:
			return index
	return -1


func _on_movement_tween_finished(run_sequence: int, actor_ref: WeakRef) -> void:
	var actor_node := actor_ref.get_ref() as Node3D
	if actor_node != null and not actor_node.is_queued_for_deletion() and int(actor_node.get_meta("action_presenter_sequence", 0)) == run_sequence:
		actor_node.set_meta("action_presenter_active", false)
	_tracker.prune_active_refs()
	_tracker.refresh_latest_active()


func _set_marker_phase(marker_ref: WeakRef, phase: String) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker == null or marker.is_queued_for_deletion():
		return
	marker.set_meta("action_presenter_current_phase", phase)
	if str(_tracker.latest_value("marker_path", "")) == str(marker.get_path()):
		_tracker.set_latest_value("current_phase", phase)


func _actor_node(world_root: Node, world_result: Dictionary, actor_id: int) -> Node3D:
	if actor_id <= 0 or world_root == null:
		return null
	for actor in _array_or_empty(world_result.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) != actor_id:
			continue
		var definition_id := str(actor_data.get("definition_id", ""))
		return world_root.find_child("Actor_%s_%d" % [definition_id, actor_id], true, false) as Node3D
	return null


func _presentation_layer(world_root: Node) -> Node3D:
	var layer: Node3D = world_root.find_child("WorldActionPresentationLayer", false, false) as Node3D
	if layer == null:
		layer = Node3D.new()
		layer.name = "WorldActionPresentationLayer"
		world_root.add_child(layer)
	return layer


func _track_active_node(node: Node) -> void:
	_tracker.track_active_node(node)


func _track_active_tween(tween: Tween) -> void:
	_tracker.track_active_tween(tween)


func _record_latest(snapshot_data: Dictionary) -> Dictionary:
	return _tracker.record_latest(snapshot_data)


func _duration_sum(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += float(value)
	return total


func _grid_to_world(grid: Dictionary, y: float = DEFAULT_ACTOR_Y) -> Vector3:
	return Vector3(float(grid.get("x", 0)) * GRID_SIZE, float(grid.get("y", 0)) + y, float(grid.get("z", 0)) * GRID_SIZE)


func _grid_key(grid: Dictionary) -> String:
	if grid.is_empty():
		return ""
	return "%d:%d:%d" % [int(grid.get("x", 0)), int(grid.get("y", 0)), int(grid.get("z", 0))]


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
