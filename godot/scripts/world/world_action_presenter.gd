extends RefCounted

const GRID_SIZE := 1.0
const DEFAULT_ACTOR_Y := 0.58
const STEP_DURATION_SEC := 0.07

var sequence: int = 0
var active_count: int = 0
var latest: Dictionary = {}


func present_result(host: Node, world_root: Node, command_result: Dictionary, world_result: Dictionary) -> Dictionary:
	if host == null or world_root == null:
		return _record_latest({"active": false, "kind": "none", "reason": "presenter_target_missing"})
	var events := _events_from_result(command_result)
	if _result_changes_map(command_result, events):
		return _record_latest({"active": false, "kind": "scene_transition", "event_count": events.size()})
	var movement := _movement_presentation(events, world_root, world_result)
	if not movement.is_empty():
		_start_movement_tween(host, movement)
		return latest.duplicate(true)
	var attack := _attack_presentation(events, world_root, world_result)
	if not attack.is_empty():
		_start_attack_feedback(host, world_root, attack)
		return latest.duplicate(true)
	var interaction := _interaction_presentation(events)
	if not interaction.is_empty():
		return _record_latest(interaction)
	return _record_latest({"active": false, "kind": "none", "event_count": events.size()})


func snapshot() -> Dictionary:
	var output := latest.duplicate(true)
	output["active"] = active_count > 0
	output["active_count"] = active_count
	output["sequence"] = sequence
	return output


func _events_from_result(command_result: Dictionary) -> Array:
	var direct_events := _array_or_empty(command_result.get("events", []))
	if not direct_events.is_empty():
		return direct_events
	var result: Dictionary = _dictionary_or_empty(command_result.get("result", {}))
	var nested_events := _array_or_empty(result.get("events", []))
	if not nested_events.is_empty():
		return nested_events
	var runtime_delta: Dictionary = _dictionary_or_empty(result.get("runtime_snapshot_delta", {}))
	return _array_or_empty(runtime_delta.get("events", []))


func _movement_presentation(events: Array, world_root: Node, world_result: Dictionary) -> Dictionary:
	var last_move: Dictionary = {}
	var step_events: Array[Dictionary] = []
	for event_value in events:
		var event: Dictionary = _dictionary_or_empty(event_value)
		match str(event.get("kind", "")):
			"movement_step":
				step_events.append(event)
			"actor_moved":
				last_move = event
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
	return {
		"active": path.size() > 1,
		"kind": "movement",
		"actor_id": actor_id,
		"node_path": str(actor_node.get_path()),
		"path": path,
		"step_count": max(0, path.size() - 1),
		"duration_sec": float(max(0, path.size() - 1)) * STEP_DURATION_SEC,
		"actor_node": actor_node,
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


func _start_movement_tween(host: Node, movement: Dictionary) -> void:
	var actor_node: Node3D = movement.get("actor_node", null)
	var path: Array = _array_or_empty(movement.get("path", []))
	if actor_node == null or path.size() <= 1:
		_record_latest(_presentation_public_snapshot(movement, false))
		return
	sequence += 1
	active_count += 1
	var run_sequence := sequence
	var y := actor_node.position.y
	actor_node.position = _grid_to_world(_dictionary_or_empty(path[0]), y)
	actor_node.set_meta("action_presenter_active", true)
	actor_node.set_meta("action_presenter_kind", "movement")
	actor_node.set_meta("action_presenter_sequence", run_sequence)
	actor_node.set_meta("action_presenter_step_count", max(0, path.size() - 1))
	var tween := host.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	for index in range(1, path.size()):
		tween.tween_property(actor_node, "position", _grid_to_world(_dictionary_or_empty(path[index]), y), STEP_DURATION_SEC)
	tween.finished.connect(Callable(self, "_on_movement_tween_finished").bind(run_sequence, weakref(actor_node)))
	_record_latest(_presentation_public_snapshot(movement, true))


func _on_movement_tween_finished(run_sequence: int, actor_ref: WeakRef) -> void:
	active_count = max(0, active_count - 1)
	var actor_node := actor_ref.get_ref() as Node3D
	if actor_node != null and not actor_node.is_queued_for_deletion() and int(actor_node.get_meta("action_presenter_sequence", 0)) == run_sequence:
		actor_node.set_meta("action_presenter_active", false)
	latest["active"] = active_count > 0
	latest["active_count"] = active_count


func _result_changes_map(command_result: Dictionary, events: Array) -> bool:
	var result: Dictionary = _dictionary_or_empty(command_result.get("result", command_result))
	var context_snapshot: Dictionary = _dictionary_or_empty(result.get("context_snapshot", {}))
	if context_snapshot.has("active_map_id") or context_snapshot.has("active_location_id"):
		return true
	for event_value in events:
		var event: Dictionary = _dictionary_or_empty(event_value)
		var kind := str(event.get("kind", ""))
		if kind == "scene_transition" or kind == "map_changed":
			return true
	return false


func _attack_presentation(events: Array, world_root: Node, world_result: Dictionary) -> Dictionary:
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(events[index])
		if str(event.get("kind", "")) != "attack_resolved":
			continue
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		var actor_id := int(payload.get("actor_id", 0))
		var target_actor_id := int(payload.get("target_actor_id", 0))
		var target_node := _actor_node(world_root, world_result, target_actor_id)
		return {
			"active": false,
			"kind": "attack",
			"actor_id": actor_id,
			"target_actor_id": target_actor_id,
			"damage": float(payload.get("damage", 0.0)),
			"hit_kind": str(payload.get("hit_kind", "")),
			"critical": bool(payload.get("critical", false)),
			"defeated": bool(payload.get("defeated", false)),
			"target_node": target_node,
			"node_path": str(target_node.get_path()) if target_node != null else "",
		}
	return {}


func _start_attack_feedback(host: Node, world_root: Node, attack: Dictionary) -> void:
	var target_node: Node3D = attack.get("target_node", null)
	if target_node == null:
		_record_latest(_attack_public_snapshot(attack, false, "target_node_missing"))
		return
	sequence += 1
	active_count += 1
	var marker := MeshInstance3D.new()
	marker.name = "WorldActionAttackImpact"
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	mesh.radial_segments = 12
	mesh.rings = 6
	marker.mesh = mesh
	marker.material_override = _attack_material(str(attack.get("hit_kind", "")), bool(attack.get("critical", false)), bool(attack.get("defeated", false)))
	var target_position := target_node.global_position if target_node.is_inside_tree() else target_node.position
	marker.position = target_position + Vector3(0.0, 1.05, 0.0)
	marker.set_meta("action_presenter_active", true)
	marker.set_meta("action_presenter_kind", "attack")
	marker.set_meta("actor_id", int(attack.get("actor_id", 0)))
	marker.set_meta("target_actor_id", int(attack.get("target_actor_id", 0)))
	marker.set_meta("damage", float(attack.get("damage", 0.0)))
	marker.set_meta("hit_kind", str(attack.get("hit_kind", "")))
	marker.set_meta("critical", bool(attack.get("critical", false)))
	marker.set_meta("defeated", bool(attack.get("defeated", false)))
	_presentation_layer(world_root).add_child(marker)
	var tween := host.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(marker, "scale", Vector3(1.45, 1.45, 1.45), 0.08)
	tween.tween_property(marker, "scale", Vector3(0.35, 0.35, 0.35), 0.10)
	tween.finished.connect(Callable(self, "_on_attack_feedback_finished").bind(weakref(marker)))
	var snapshot_data := _attack_public_snapshot(attack, true, "")
	snapshot_data["marker_path"] = str(marker.get_path())
	_record_latest(snapshot_data)


func _on_attack_feedback_finished(marker_ref: WeakRef) -> void:
	active_count = max(0, active_count - 1)
	var marker := marker_ref.get_ref() as Node
	if marker != null and not marker.is_queued_for_deletion():
		marker.queue_free()
	latest["active"] = active_count > 0
	latest["active_count"] = active_count


func _attack_public_snapshot(attack: Dictionary, active: bool, reason: String) -> Dictionary:
	return {
		"active": active,
		"kind": "attack",
		"reason": reason,
		"actor_id": int(attack.get("actor_id", 0)),
		"target_actor_id": int(attack.get("target_actor_id", 0)),
		"node_path": str(attack.get("node_path", "")),
		"damage": float(attack.get("damage", 0.0)),
		"hit_kind": str(attack.get("hit_kind", "")),
		"critical": bool(attack.get("critical", false)),
		"defeated": bool(attack.get("defeated", false)),
	}


func _interaction_presentation(events: Array) -> Dictionary:
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(events[index])
		if str(event.get("kind", "")) != "interaction_succeeded":
			continue
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		return {
			"active": false,
			"kind": "interaction",
			"actor_id": int(payload.get("actor_id", 0)),
			"target_id": str(payload.get("target_id", "")),
			"option_kind": str(payload.get("option_kind", "")),
		}
	return {}


func _actor_node(world_root: Node, world_result: Dictionary, actor_id: int) -> Node3D:
	if actor_id <= 0:
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


func _attack_material(hit_kind: String, critical: bool, defeated: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if defeated:
		material.albedo_color = Color(0.96, 0.12, 0.08, 0.92)
	elif critical:
		material.albedo_color = Color(1.0, 0.86, 0.18, 0.94)
	elif hit_kind == "miss":
		material.albedo_color = Color(0.64, 0.78, 0.94, 0.84)
	elif hit_kind == "blocked":
		material.albedo_color = Color(0.55, 0.57, 0.66, 0.86)
	else:
		material.albedo_color = Color(1.0, 0.34, 0.18, 0.9)
	return material


func _presentation_public_snapshot(presentation: Dictionary, active: bool) -> Dictionary:
	return {
		"active": active,
		"kind": str(presentation.get("kind", "")),
		"actor_id": int(presentation.get("actor_id", 0)),
		"node_path": str(presentation.get("node_path", "")),
		"path": _array_or_empty(presentation.get("path", [])).duplicate(true),
		"step_count": int(presentation.get("step_count", 0)),
		"duration_sec": float(presentation.get("duration_sec", 0.0)),
	}


func _record_latest(snapshot_data: Dictionary) -> Dictionary:
	latest = snapshot_data.duplicate(true)
	latest["active_count"] = active_count
	latest["sequence"] = sequence
	return latest.duplicate(true)


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
