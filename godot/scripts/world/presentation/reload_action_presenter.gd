extends RefCounted

const PresentationTracker = preload("res://scripts/world/presentation/presentation_tracker.gd")
const PresentationMaterials = preload("res://scripts/world/presentation/presentation_materials.gd")
const PresentationNodeFactory = preload("res://scripts/world/presentation/presentation_node_factory.gd")

const GRID_SIZE := 1.0
const DEFAULT_ACTOR_Y := 0.58
const RELOAD_PHASES := ["prepare", "load", "ready"]
const RELOAD_PHASE_DURATIONS := [0.07, 0.12, 0.10]

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


func reload_presentation(events: Array, world_root: Node, world_result: Dictionary) -> Dictionary:
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(events[index])
		if str(event.get("kind", "")) != "weapon_reloaded":
			continue
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		var actor_id := int(payload.get("actor_id", 0))
		var actor_node := _actor_node(world_root, world_result, actor_id)
		var actor_grid := _actor_grid(world_result, actor_id)
		if actor_grid.is_empty() and actor_node != null:
			actor_grid = _node_grid(actor_node)
		return {
			"active": false,
			"kind": "reload",
			"event_kind": "weapon_reloaded",
			"actor_id": actor_id,
			"slot_id": str(payload.get("slot_id", "")),
			"weapon_item_id": str(payload.get("weapon_item_id", "")),
			"ammo_type": str(payload.get("ammo_type", "")),
			"loaded": int(payload.get("loaded", 0)),
			"loaded_before": int(payload.get("loaded_before", 0)),
			"loaded_count": int(payload.get("loaded_count", 0)),
			"capacity": int(payload.get("capacity", 0)),
			"remaining_inventory": int(payload.get("remaining_inventory", 0)),
			"ap_cost": float(payload.get("ap_cost", 0.0)),
			"actor_node": actor_node,
			"node_path": str(actor_node.get_path()) if actor_node != null else "",
			"target_grid": actor_grid.duplicate(true),
		}
	return {}


func start_reload_feedback(host: Node, world_root: Node, reload: Dictionary) -> void:
	var actor_node: Node3D = reload.get("actor_node", null)
	var target_grid: Dictionary = _dictionary_or_empty(reload.get("target_grid", {}))
	if actor_node == null and target_grid.is_empty():
		_record_latest(reload_public_snapshot(reload, false, "actor_missing"))
		return
	_tracker.next_sequence()
	var marker := _node_factory.cylinder_marker("WorldActionReloadPulse", 0.30, 0.30, 0.08, 20, _materials.reload_material())
	var target_position := Vector3.ZERO
	if actor_node != null:
		target_position = actor_node.global_position if actor_node.is_inside_tree() else actor_node.position
	else:
		target_position = _grid_to_world(target_grid, 0.58)
	marker.position = target_position + Vector3(0.0, 1.08, 0.0)
	marker.scale = Vector3(0.70, 0.70, 0.70)
	marker.set_meta("action_presenter_active", true)
	marker.set_meta("action_presenter_kind", "reload")
	marker.set_meta("action_presenter_phases", RELOAD_PHASES.duplicate())
	marker.set_meta("action_presenter_phase_count", RELOAD_PHASES.size())
	marker.set_meta("action_presenter_current_phase", RELOAD_PHASES[0])
	marker.set_meta("action_presenter_duration_sec", _duration_sum(RELOAD_PHASE_DURATIONS))
	_apply_reload_event_meta(marker, reload)
	_track_active_node(marker)
	var label := _reload_label(reload)
	label.position = target_position + Vector3(0.0, 1.44, 0.0)
	_track_active_node(label)
	var layer := _presentation_layer(world_root)
	layer.add_child(marker)
	layer.add_child(label)
	var tween := host.create_tween()
	_track_active_tween(tween)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(marker, "scale", Vector3(1.05, 1.05, 1.05), float(RELOAD_PHASE_DURATIONS[0]))
	tween.parallel().tween_property(label, "position", label.position + Vector3(0.0, 0.08, 0.0), float(RELOAD_PHASE_DURATIONS[0]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), RELOAD_PHASES[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(label), RELOAD_PHASES[1]))
	tween.tween_property(marker, "scale", Vector3(1.44, 1.18, 1.44), float(RELOAD_PHASE_DURATIONS[1]))
	tween.parallel().tween_property(label, "position", label.position + Vector3(0.0, 0.24, 0.0), float(RELOAD_PHASE_DURATIONS[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), RELOAD_PHASES[2]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(label), RELOAD_PHASES[2]))
	tween.tween_property(marker, "scale", Vector3(0.38, 0.38, 0.38), float(RELOAD_PHASE_DURATIONS[2]))
	tween.parallel().tween_property(label, "modulate", Color(label.modulate.r, label.modulate.g, label.modulate.b, 0.0), float(RELOAD_PHASE_DURATIONS[2]))
	tween.finished.connect(Callable(self, "_on_reload_feedback_finished").bind(weakref(marker), weakref(label)))
	var snapshot_data := reload_public_snapshot(reload, true, "")
	snapshot_data["marker_path"] = str(marker.get_path())
	snapshot_data["label_path"] = str(label.get_path())
	snapshot_data["label_text"] = str(label.text)
	_record_latest(snapshot_data)


func reload_public_snapshot(reload: Dictionary, active: bool, reason: String) -> Dictionary:
	return {
		"active": active,
		"kind": "reload",
		"reason": reason,
		"event_kind": str(reload.get("event_kind", "weapon_reloaded")),
		"actor_id": int(reload.get("actor_id", 0)),
		"slot_id": str(reload.get("slot_id", "")),
		"weapon_item_id": str(reload.get("weapon_item_id", "")),
		"ammo_type": str(reload.get("ammo_type", "")),
		"loaded": int(reload.get("loaded", 0)),
		"loaded_before": int(reload.get("loaded_before", 0)),
		"loaded_count": int(reload.get("loaded_count", 0)),
		"capacity": int(reload.get("capacity", 0)),
		"remaining_inventory": int(reload.get("remaining_inventory", 0)),
		"ap_cost": float(reload.get("ap_cost", 0.0)),
		"target_grid": _dictionary_or_empty(reload.get("target_grid", {})).duplicate(true),
		"node_path": str(reload.get("node_path", "")),
		"phases": RELOAD_PHASES.duplicate(),
		"phase_count": RELOAD_PHASES.size(),
		"current_phase": RELOAD_PHASES[0] if active else "",
		"duration_sec": _duration_sum(RELOAD_PHASE_DURATIONS) if active else 0.0,
		"visual_kind": "reload_pulse",
	}


func _on_reload_feedback_finished(marker_ref: WeakRef, label_ref: WeakRef) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker != null and not marker.is_queued_for_deletion():
		marker.set_meta("action_presenter_active", false)
		marker.queue_free()
	var label := label_ref.get_ref() as Node
	if label != null and not label.is_queued_for_deletion():
		label.set_meta("action_presenter_active", false)
		label.queue_free()
	_tracker.prune_active_refs()
	_tracker.refresh_latest_active()


func _reload_label(reload: Dictionary) -> Label3D:
	var label := _node_factory.label3d(
		"WorldActionReloadText",
		_reload_feedback_text(reload),
		14,
		Color(0.48, 0.88, 1.0, 0.94)
	)
	label.set_meta("action_presenter_active", true)
	label.set_meta("action_presenter_kind", "reload_text")
	label.set_meta("action_presenter_phases", RELOAD_PHASES.duplicate())
	label.set_meta("action_presenter_phase_count", RELOAD_PHASES.size())
	label.set_meta("action_presenter_current_phase", RELOAD_PHASES[0])
	label.set_meta("action_presenter_duration_sec", _duration_sum(RELOAD_PHASE_DURATIONS))
	_apply_reload_event_meta(label, reload)
	label.set_meta("text", label.text)
	return label


func _apply_reload_event_meta(node: Node, reload: Dictionary) -> void:
	node.set_meta("event_kind", str(reload.get("event_kind", "weapon_reloaded")))
	node.set_meta("visual_kind", "reload_pulse")
	node.set_meta("actor_id", int(reload.get("actor_id", 0)))
	node.set_meta("slot_id", str(reload.get("slot_id", "")))
	node.set_meta("weapon_item_id", str(reload.get("weapon_item_id", "")))
	node.set_meta("ammo_type", str(reload.get("ammo_type", "")))
	node.set_meta("loaded", int(reload.get("loaded", 0)))
	node.set_meta("loaded_before", int(reload.get("loaded_before", 0)))
	node.set_meta("loaded_count", int(reload.get("loaded_count", 0)))
	node.set_meta("capacity", int(reload.get("capacity", 0)))
	node.set_meta("remaining_inventory", int(reload.get("remaining_inventory", 0)))
	node.set_meta("ap_cost", float(reload.get("ap_cost", 0.0)))
	node.set_meta("target_grid", _dictionary_or_empty(reload.get("target_grid", {})).duplicate(true))


func _reload_feedback_text(reload: Dictionary) -> String:
	var loaded := int(reload.get("loaded", 0))
	var capacity := int(reload.get("capacity", 0))
	var loaded_count := int(reload.get("loaded_count", 0))
	if capacity > 0:
		return "RELOAD +%d  %d/%d" % [loaded_count, loaded, capacity]
	return "RELOAD +%d" % loaded_count


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
