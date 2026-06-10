extends RefCounted

const PresentationTracker = preload("res://scripts/world/presentation/presentation_tracker.gd")
const PresentationMaterials = preload("res://scripts/world/presentation/presentation_materials.gd")
const PresentationNodeFactory = preload("res://scripts/world/presentation/presentation_node_factory.gd")

const GRID_SIZE := 1.0
const DEFAULT_ACTOR_Y := 0.58
const COMBAT_EVENT_PHASES := ["signal", "resolve", "fade"]
const COMBAT_EVENT_PHASE_DURATIONS := [0.05, 0.10, 0.12]

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


func combat_event_presentation(events: Array, world_root: Node, world_result: Dictionary) -> Dictionary:
	var event_kinds: Array[String] = []
	var selected_event: Dictionary = {}
	var priority := {
		"corpse_created": 4,
		"actor_defeated": 3,
		"combat_ended": 2,
		"combat_started": 1,
	}
	var selected_priority := 0
	for event_value in events:
		var event: Dictionary = _dictionary_or_empty(event_value)
		var kind := str(event.get("kind", ""))
		if not priority.has(kind):
			continue
		event_kinds.append(kind)
		var event_priority: int = int(priority.get(kind, 0))
		if event_priority >= selected_priority:
			selected_event = event
			selected_priority = event_priority
	if selected_event.is_empty():
		return {}
	var payload: Dictionary = _dictionary_or_empty(selected_event.get("payload", {}))
	var event_kind := str(selected_event.get("kind", ""))
	var participants := _int_array(payload.get("participants", []))
	var added_participants := _int_array(payload.get("added_participants", []))
	var turn_order := _int_array(payload.get("turn_order", []))
	var actor_candidates := _combat_event_actor_candidates(event_kind, payload, participants, added_participants, turn_order)
	var target_node := _combat_event_node(world_root, world_result, event_kind, payload)
	if target_node == null:
		target_node = _first_actor_node(world_root, world_result, actor_candidates)
	var grid := _combat_event_grid(payload, world_result, actor_candidates, target_node)
	var primary_actor_id := int(payload.get("actor_id", payload.get("source_actor_id", 0)))
	if primary_actor_id <= 0 and not actor_candidates.is_empty():
		primary_actor_id = int(actor_candidates[0])
	var source_actor_id := int(payload.get("source_actor_id", payload.get("actor_id", primary_actor_id)))
	return {
		"active": false,
		"kind": "combat_event",
		"event_kind": event_kind,
		"event_kinds": event_kinds,
		"actor_id": primary_actor_id,
		"source_actor_id": source_actor_id,
		"defeated_by_actor_id": int(payload.get("defeated_by_actor_id", payload.get("defeated_by", 0))),
		"container_id": str(payload.get("container_id", "")),
		"reason": str(payload.get("reason", "")),
		"participants": participants,
		"participant_count": participants.size(),
		"added_participants": added_participants,
		"turn_order": turn_order,
		"current_combat_actor_id": int(payload.get("current_combat_actor_id", 0)),
		"next_combat_actor_id": int(payload.get("next_combat_actor_id", 0)),
		"round": int(payload.get("round", 0)),
		"target_node": target_node,
		"target_grid": grid,
		"node_path": str(target_node.get_path()) if target_node != null else "",
	}


func start_combat_event_feedback(host: Node, world_root: Node, combat_event: Dictionary) -> void:
	var target_node: Node3D = combat_event.get("target_node", null)
	var target_grid: Dictionary = _dictionary_or_empty(combat_event.get("target_grid", {}))
	if target_node == null and target_grid.is_empty():
		_record_latest(combat_event_public_snapshot(combat_event, false, "target_missing"))
		return
	_tracker.next_sequence()
	var marker := _node_factory.sphere_marker(
		"WorldActionCombatEvent",
		0.18,
		0.36,
		10,
		5,
		_materials.combat_event_material(str(combat_event.get("event_kind", "")))
	)
	var target_position := Vector3.ZERO
	if target_node != null:
		target_position = target_node.global_position if target_node.is_inside_tree() else target_node.position
	else:
		target_position = _grid_to_world(target_grid, 0.42)
	marker.position = target_position + Vector3(0.0, 1.16, 0.0)
	marker.set_meta("action_presenter_active", true)
	marker.set_meta("action_presenter_kind", "combat_event")
	marker.set_meta("action_presenter_phases", COMBAT_EVENT_PHASES.duplicate())
	marker.set_meta("action_presenter_phase_count", COMBAT_EVENT_PHASES.size())
	marker.set_meta("action_presenter_current_phase", COMBAT_EVENT_PHASES[0])
	marker.set_meta("action_presenter_duration_sec", _duration_sum(COMBAT_EVENT_PHASE_DURATIONS))
	marker.set_meta("event_kind", str(combat_event.get("event_kind", "")))
	marker.set_meta("event_kinds", _array_or_empty(combat_event.get("event_kinds", [])).duplicate(true))
	marker.set_meta("actor_id", int(combat_event.get("actor_id", 0)))
	marker.set_meta("source_actor_id", int(combat_event.get("source_actor_id", 0)))
	marker.set_meta("defeated_by_actor_id", int(combat_event.get("defeated_by_actor_id", 0)))
	marker.set_meta("container_id", str(combat_event.get("container_id", "")))
	marker.set_meta("reason", str(combat_event.get("reason", "")))
	marker.set_meta("participants", _array_or_empty(combat_event.get("participants", [])).duplicate(true))
	marker.set_meta("participant_count", int(combat_event.get("participant_count", 0)))
	marker.set_meta("added_participants", _array_or_empty(combat_event.get("added_participants", [])).duplicate(true))
	marker.set_meta("turn_order", _array_or_empty(combat_event.get("turn_order", [])).duplicate(true))
	marker.set_meta("current_combat_actor_id", int(combat_event.get("current_combat_actor_id", 0)))
	marker.set_meta("next_combat_actor_id", int(combat_event.get("next_combat_actor_id", 0)))
	marker.set_meta("round", int(combat_event.get("round", 0)))
	marker.set_meta("target_grid", target_grid.duplicate(true))
	_track_active_node(marker)
	var label := _combat_event_label(combat_event)
	label.position = target_position + Vector3(0.0, _combat_event_label_y_offset(str(combat_event.get("event_kind", ""))), 0.0)
	_track_active_node(label)
	var layer := _presentation_layer(world_root)
	layer.add_child(marker)
	layer.add_child(label)
	var tween := host.create_tween()
	_track_active_tween(tween)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(marker, "scale", Vector3(0.82, 0.82, 0.82), float(COMBAT_EVENT_PHASE_DURATIONS[0]))
	tween.parallel().tween_property(label, "position", label.position + Vector3(0.0, 0.08, 0.0), float(COMBAT_EVENT_PHASE_DURATIONS[0]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), COMBAT_EVENT_PHASES[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(label), COMBAT_EVENT_PHASES[1]))
	tween.tween_property(marker, "scale", Vector3(1.55, 1.55, 1.55), float(COMBAT_EVENT_PHASE_DURATIONS[1]))
	tween.parallel().tween_property(label, "position", label.position + Vector3(0.0, 0.22, 0.0), float(COMBAT_EVENT_PHASE_DURATIONS[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), COMBAT_EVENT_PHASES[2]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(label), COMBAT_EVENT_PHASES[2]))
	tween.tween_property(marker, "scale", Vector3(0.42, 0.42, 0.42), float(COMBAT_EVENT_PHASE_DURATIONS[2]))
	tween.parallel().tween_property(label, "modulate", Color(label.modulate.r, label.modulate.g, label.modulate.b, 0.0), float(COMBAT_EVENT_PHASE_DURATIONS[2]))
	tween.finished.connect(Callable(self, "_on_combat_event_feedback_finished").bind(weakref(marker), weakref(label)))
	var snapshot_data := combat_event_public_snapshot(combat_event, true, "")
	snapshot_data["marker_path"] = str(marker.get_path())
	snapshot_data["label_path"] = str(label.get_path())
	snapshot_data["label_text"] = str(label.text)
	_record_latest(snapshot_data)


func combat_event_public_snapshot(combat_event: Dictionary, active: bool, reason: String) -> Dictionary:
	var event_reason := str(combat_event.get("reason", ""))
	return {
		"active": active,
		"kind": "combat_event",
		"reason": reason if not reason.is_empty() else event_reason,
		"event_reason": event_reason,
		"event_kind": str(combat_event.get("event_kind", "")),
		"event_kinds": _array_or_empty(combat_event.get("event_kinds", [])).duplicate(true),
		"actor_id": int(combat_event.get("actor_id", 0)),
		"source_actor_id": int(combat_event.get("source_actor_id", 0)),
		"defeated_by_actor_id": int(combat_event.get("defeated_by_actor_id", 0)),
		"container_id": str(combat_event.get("container_id", "")),
		"participants": _array_or_empty(combat_event.get("participants", [])).duplicate(true),
		"participant_count": int(combat_event.get("participant_count", 0)),
		"added_participants": _array_or_empty(combat_event.get("added_participants", [])).duplicate(true),
		"turn_order": _array_or_empty(combat_event.get("turn_order", [])).duplicate(true),
		"current_combat_actor_id": int(combat_event.get("current_combat_actor_id", 0)),
		"next_combat_actor_id": int(combat_event.get("next_combat_actor_id", 0)),
		"round": int(combat_event.get("round", 0)),
		"target_grid": _dictionary_or_empty(combat_event.get("target_grid", {})).duplicate(true),
		"node_path": str(combat_event.get("node_path", "")),
		"phases": COMBAT_EVENT_PHASES.duplicate(),
		"phase_count": COMBAT_EVENT_PHASES.size(),
		"current_phase": COMBAT_EVENT_PHASES[0] if active else "",
		"duration_sec": _duration_sum(COMBAT_EVENT_PHASE_DURATIONS) if active else 0.0,
		"label_text": _combat_event_feedback_text(str(combat_event.get("event_kind", ""))),
		"label_y_offset": _combat_event_label_y_offset(str(combat_event.get("event_kind", ""))),
	}


func _on_combat_event_feedback_finished(marker_ref: WeakRef, label_ref: WeakRef = null) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker != null and not marker.is_queued_for_deletion():
		marker.set_meta("action_presenter_active", false)
		marker.queue_free()
	if label_ref != null:
		var label := label_ref.get_ref() as Node
		if label != null and not label.is_queued_for_deletion():
			label.set_meta("action_presenter_active", false)
			label.queue_free()
	_tracker.prune_active_refs()
	_tracker.refresh_latest_active()


func _combat_event_label(combat_event: Dictionary) -> Label3D:
	var event_kind := str(combat_event.get("event_kind", ""))
	var label := _node_factory.label3d(
		"WorldActionCombatEventText",
		_combat_event_feedback_text(event_kind),
		15,
		_combat_event_label_color(event_kind)
	)
	label.set_meta("action_presenter_active", true)
	label.set_meta("action_presenter_kind", "combat_event_text")
	label.set_meta("action_presenter_phases", COMBAT_EVENT_PHASES.duplicate())
	label.set_meta("action_presenter_phase_count", COMBAT_EVENT_PHASES.size())
	label.set_meta("action_presenter_current_phase", COMBAT_EVENT_PHASES[0])
	label.set_meta("action_presenter_duration_sec", _duration_sum(COMBAT_EVENT_PHASE_DURATIONS))
	label.set_meta("event_kind", event_kind)
	label.set_meta("event_kinds", _array_or_empty(combat_event.get("event_kinds", [])).duplicate(true))
	label.set_meta("actor_id", int(combat_event.get("actor_id", 0)))
	label.set_meta("source_actor_id", int(combat_event.get("source_actor_id", 0)))
	label.set_meta("defeated_by_actor_id", int(combat_event.get("defeated_by_actor_id", 0)))
	label.set_meta("container_id", str(combat_event.get("container_id", "")))
	label.set_meta("reason", str(combat_event.get("reason", "")))
	label.set_meta("participants", _array_or_empty(combat_event.get("participants", [])).duplicate(true))
	label.set_meta("participant_count", int(combat_event.get("participant_count", 0)))
	label.set_meta("target_grid", _dictionary_or_empty(combat_event.get("target_grid", {})).duplicate(true))
	label.set_meta("text", label.text)
	return label


func _combat_event_node(world_root: Node, world_result: Dictionary, event_kind: String, payload: Dictionary) -> Node3D:
	if event_kind == "corpse_created":
		var container_id := str(payload.get("container_id", ""))
		if not container_id.is_empty():
			var corpse_node := world_root.find_child("Corpse_%s" % container_id, true, false) as Node3D
			if corpse_node != null:
				return corpse_node
	var actor_id := int(payload.get("actor_id", payload.get("source_actor_id", 0)))
	return _actor_node(world_root, world_result, actor_id)


func _first_actor_node(world_root: Node, world_result: Dictionary, actor_ids: Array) -> Node3D:
	for actor_id_value in actor_ids:
		var node := _actor_node(world_root, world_result, int(actor_id_value))
		if node != null:
			return node
	return null


func _combat_event_actor_candidates(event_kind: String, payload: Dictionary, participants: Array, added_participants: Array, turn_order: Array) -> Array:
	var candidates: Array = []
	for key in ["actor_id", "source_actor_id", "current_combat_actor_id", "next_combat_actor_id", "defeated_by_actor_id", "defeated_by"]:
		_append_actor_candidate(candidates, int(payload.get(key, 0)))
	if event_kind == "combat_started":
		for actor_id in _int_array(payload.get("seed_participants", [])):
			_append_actor_candidate(candidates, int(actor_id))
		for actor_id in added_participants:
			_append_actor_candidate(candidates, int(actor_id))
	if event_kind == "combat_ended":
		for actor_id in participants:
			_append_actor_candidate(candidates, int(actor_id))
	for actor_id in turn_order:
		_append_actor_candidate(candidates, int(actor_id))
	for actor_id in participants:
		_append_actor_candidate(candidates, int(actor_id))
	_append_actor_candidate(candidates, 1)
	return candidates


func _append_actor_candidate(candidates: Array, actor_id: int) -> void:
	if actor_id <= 0 or candidates.has(actor_id):
		return
	candidates.append(actor_id)


func _combat_event_grid(payload: Dictionary, world_result: Dictionary, actor_ids: Array, target_node: Node3D = null) -> Dictionary:
	var grid: Dictionary = _dictionary_or_empty(payload.get("grid_position", {}))
	if grid.is_empty():
		grid = _dictionary_or_empty(payload.get("target_grid", {}))
	if grid.is_empty():
		for actor_id in actor_ids:
			grid = _actor_grid(world_result, int(actor_id))
			if not grid.is_empty():
				break
	if grid.is_empty() and target_node != null:
		grid = _node_grid(target_node)
	return grid.duplicate(true)


func _combat_event_feedback_text(event_kind: String) -> String:
	match event_kind:
		"corpse_created":
			return "掉落"
		"actor_defeated":
			return "击败"
		"combat_started":
			return "战斗"
		"combat_ended":
			return "脱战"
	return "战斗"


func _combat_event_label_color(event_kind: String) -> Color:
	match event_kind:
		"corpse_created":
			return Color(1.0, 0.52, 0.42, 0.96)
		"actor_defeated":
			return Color(1.0, 0.34, 0.30, 0.96)
		"combat_started":
			return Color(1.0, 0.68, 0.34, 0.96)
		"combat_ended":
			return Color(0.58, 1.0, 0.74, 0.96)
	return Color(1.0, 0.90, 0.46, 0.94)


func _combat_event_label_y_offset(event_kind: String) -> float:
	match event_kind:
		"corpse_created", "actor_defeated":
			return 1.58
		"combat_started", "combat_ended":
			return 1.44
	return 1.48


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


func _actor_grid(world_result: Dictionary, actor_id: int) -> Dictionary:
	if actor_id <= 0:
		return {}
	for actor in _array_or_empty(world_result.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return _dictionary_or_empty(actor_data.get("grid_position", {})).duplicate(true)
	return {}


func _node_grid(node: Node3D) -> Dictionary:
	if node == null:
		return {}
	var position := node.global_position if node.is_inside_tree() else node.position
	return {
		"x": int(round(position.x / GRID_SIZE)),
		"y": int(floor(position.y)),
		"z": int(round(position.z / GRID_SIZE)),
	}


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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _int_array(value: Variant) -> Array:
	var output: Array = []
	for item in _array_or_empty(value):
		var normalized := int(item)
		if normalized > 0 and not output.has(normalized):
			output.append(normalized)
	return output
