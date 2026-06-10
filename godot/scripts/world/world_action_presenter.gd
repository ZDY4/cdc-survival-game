extends RefCounted

const PresentationTracker = preload("res://scripts/world/presentation/presentation_tracker.gd")
const PresentationMaterials = preload("res://scripts/world/presentation/presentation_materials.gd")
const PresentationNodeFactory = preload("res://scripts/world/presentation/presentation_node_factory.gd")
const MovementActionPresenter = preload("res://scripts/world/presentation/movement_action_presenter.gd")
const AttackActionPresenter = preload("res://scripts/world/presentation/attack_action_presenter.gd")
const ReloadActionPresenter = preload("res://scripts/world/presentation/reload_action_presenter.gd")
const CombatEventPresenter = preload("res://scripts/world/presentation/combat_event_presenter.gd")

const GRID_SIZE := 1.0
const DEFAULT_ACTOR_Y := 0.58
const INTERACTION_PHASES := ["start", "pulse", "fade"]
const INTERACTION_PHASE_DURATIONS := [0.06, 0.08, 0.10]

var _tracker := PresentationTracker.new()
var _materials := PresentationMaterials.new()
var _node_factory := PresentationNodeFactory.new()
var _movement_presenter := MovementActionPresenter.new()
var _attack_presenter := AttackActionPresenter.new()
var _reload_presenter := ReloadActionPresenter.new()
var _combat_event_presenter := CombatEventPresenter.new()


func _init() -> void:
	_movement_presenter.configure(_tracker, _materials, _node_factory)
	_attack_presenter.configure(_tracker, _materials, _node_factory)
	_reload_presenter.configure(_tracker, _materials, _node_factory)
	_combat_event_presenter.configure(_tracker, _materials, _node_factory)


func present_result(host: Node, world_root: Node, command_result: Dictionary, world_result: Dictionary) -> Dictionary:
	if host == null or world_root == null:
		return _record_latest({"active": false, "kind": "none", "reason": "presenter_target_missing"})
	var events := _events_from_result(command_result)
	if _result_changes_map(command_result, events):
		return _record_latest({"active": false, "kind": "scene_transition", "event_count": events.size()})
	var movement_cancelled := _movement_presenter.movement_cancelled_presentation(events, world_root, world_result)
	var movement := _movement_presenter.movement_presentation(events, world_root, world_result)
	var interaction := _interaction_presentation(events, world_root, world_result)
	if not movement.is_empty() and not interaction.is_empty():
		_movement_presenter.start_movement_tween(host, world_root, movement)
		_start_interaction_feedback(host, world_root, interaction)
		return _tracker.latest_snapshot()
	if not movement.is_empty():
		_movement_presenter.start_movement_tween(host, world_root, movement)
		return _tracker.latest_snapshot()
	var attack := _attack_presenter.attack_presentation(events, world_root, world_result)
	if not attack.is_empty():
		var combat_event := _combat_event_presenter.combat_event_presentation(events, world_root, world_result)
		if attack.get("target_node", null) == null and not combat_event.is_empty():
			_combat_event_presenter.start_combat_event_feedback(host, world_root, combat_event)
			return _tracker.latest_snapshot()
		_attack_presenter.start_attack_feedback(host, world_root, attack)
		return _tracker.latest_snapshot()
	if not interaction.is_empty():
		_start_interaction_feedback(host, world_root, interaction)
		return _tracker.latest_snapshot()
	var reload := _reload_presenter.reload_presentation(events, world_root, world_result)
	if not reload.is_empty():
		_reload_presenter.start_reload_feedback(host, world_root, reload)
		return _tracker.latest_snapshot()
	var combat_event := _combat_event_presenter.combat_event_presentation(events, world_root, world_result)
	if not combat_event.is_empty():
		_combat_event_presenter.start_combat_event_feedback(host, world_root, combat_event)
		return _tracker.latest_snapshot()
	if not movement_cancelled.is_empty():
		return _record_latest(_movement_presenter.movement_cancelled_public_snapshot(movement_cancelled))
	return _record_latest({"active": false, "kind": "none", "event_count": events.size()})


func snapshot() -> Dictionary:
	return _tracker.snapshot()


func finish_active_presentations() -> Dictionary:
	return _tracker.finish_active_presentations()


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


func _interaction_presentation(events: Array, world_root: Node, world_result: Dictionary) -> Dictionary:
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(events[index])
		if str(event.get("kind", "")) != "interaction_succeeded":
			continue
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		var target_id := str(payload.get("target_id", ""))
		var target_type := str(payload.get("target_type", ""))
		var target_node := _interaction_target_node(world_root, world_result, payload)
		var target_grid: Dictionary = _dictionary_or_empty(payload.get("target_grid", {}))
		var option_kind := str(payload.get("option_kind", ""))
		var visual_profile := _interaction_visual_profile(option_kind)
		return {
			"active": false,
			"kind": "interaction",
			"actor_id": int(payload.get("actor_id", 0)),
			"target_id": target_id,
			"target_type": target_type,
			"target_name": str(payload.get("target_name", "")),
			"target_grid": target_grid,
			"option_kind": option_kind,
			"visual_kind": str(visual_profile.get("visual_kind", "")),
			"phase_durations": _array_or_empty(visual_profile.get("phase_durations", [])).duplicate(true),
			"marker_y_offset": float(visual_profile.get("y_offset", 0.22)),
			"target_node": target_node,
			"node_path": str(target_node.get_path()) if target_node != null else "",
		}
	return {}


func _start_interaction_feedback(host: Node, world_root: Node, interaction: Dictionary) -> void:
	var target_node: Node3D = interaction.get("target_node", null)
	var target_grid: Dictionary = _dictionary_or_empty(interaction.get("target_grid", {}))
	if target_node == null and target_grid.is_empty():
		_record_latest(_interaction_public_snapshot(interaction, false, "target_missing"))
		return
	_tracker.next_sequence()
	var visual_profile := _interaction_visual_profile(str(interaction.get("option_kind", "")))
	var phase_durations: Array = _phase_durations_or_default(visual_profile.get("phase_durations", INTERACTION_PHASE_DURATIONS), INTERACTION_PHASE_DURATIONS)
	var marker := _node_factory.cylinder_marker(
		"WorldActionInteractionPulse",
		float(visual_profile.get("top_radius", 0.34)),
		float(visual_profile.get("bottom_radius", 0.34)),
		float(visual_profile.get("height", 0.055)),
		int(visual_profile.get("radial_segments", 24)),
		_interaction_material(str(interaction.get("option_kind", "")))
	)
	var target_position := Vector3.ZERO
	if target_node != null:
		target_position = target_node.global_position if target_node.is_inside_tree() else target_node.position
	else:
		target_position = _grid_to_world(target_grid, 0.12)
	marker.position = target_position + Vector3(0.0, float(visual_profile.get("y_offset", 0.22)), 0.0)
	marker.set_meta("action_presenter_active", true)
	marker.set_meta("action_presenter_kind", "interaction")
	marker.set_meta("action_presenter_phases", INTERACTION_PHASES.duplicate())
	marker.set_meta("action_presenter_phase_count", INTERACTION_PHASES.size())
	marker.set_meta("action_presenter_current_phase", INTERACTION_PHASES[0])
	marker.set_meta("action_presenter_phase_durations", phase_durations.duplicate(true))
	marker.set_meta("action_presenter_duration_sec", _duration_sum(phase_durations))
	marker.set_meta("actor_id", int(interaction.get("actor_id", 0)))
	marker.set_meta("target_id", str(interaction.get("target_id", "")))
	marker.set_meta("target_type", str(interaction.get("target_type", "")))
	marker.set_meta("target_name", str(interaction.get("target_name", "")))
	marker.set_meta("target_grid", target_grid.duplicate(true))
	marker.set_meta("option_kind", str(interaction.get("option_kind", "")))
	marker.set_meta("visual_kind", str(visual_profile.get("visual_kind", "")))
	marker.set_meta("marker_y_offset", float(visual_profile.get("y_offset", 0.22)))
	marker.set_meta("marker_top_radius", float(visual_profile.get("top_radius", 0.34)))
	marker.set_meta("marker_bottom_radius", float(visual_profile.get("bottom_radius", 0.34)))
	marker.set_meta("marker_height", float(visual_profile.get("height", 0.055)))
	_track_active_node(marker)
	var label := _interaction_label(interaction, visual_profile)
	label.position = target_position + Vector3(0.0, float(visual_profile.get("label_y_offset", 1.18)), 0.0)
	_track_active_node(label)
	var layer := _presentation_layer(world_root)
	layer.add_child(marker)
	layer.add_child(label)
	var tween := host.create_tween()
	_track_active_tween(tween)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(marker, "scale", _vector3_or_default(visual_profile.get("start_scale", Vector3(0.82, 1.0, 0.82)), Vector3(0.82, 1.0, 0.82)), float(phase_durations[0]))
	tween.parallel().tween_property(label, "position", label.position + Vector3(0.0, 0.08, 0.0), float(phase_durations[0]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), INTERACTION_PHASES[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(label), INTERACTION_PHASES[1]))
	tween.tween_property(marker, "scale", _vector3_or_default(visual_profile.get("pulse_scale", Vector3(1.35, 1.0, 1.35)), Vector3(1.35, 1.0, 1.35)), float(phase_durations[1]))
	tween.parallel().tween_property(label, "position", label.position + Vector3(0.0, 0.24, 0.0), float(phase_durations[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), INTERACTION_PHASES[2]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(label), INTERACTION_PHASES[2]))
	tween.tween_property(marker, "scale", _vector3_or_default(visual_profile.get("fade_scale", Vector3(0.55, 1.0, 0.55)), Vector3(0.55, 1.0, 0.55)), float(phase_durations[2]))
	tween.parallel().tween_property(label, "modulate", Color(label.modulate.r, label.modulate.g, label.modulate.b, 0.0), float(phase_durations[2]))
	tween.finished.connect(Callable(self, "_on_interaction_feedback_finished").bind(weakref(marker), weakref(label)))
	var snapshot_data := _interaction_public_snapshot(interaction, true, "")
	snapshot_data["marker_path"] = str(marker.get_path())
	snapshot_data["label_path"] = str(label.get_path())
	snapshot_data["label_text"] = str(label.text)
	_record_latest(snapshot_data)


func _on_interaction_feedback_finished(marker_ref: WeakRef, label_ref: WeakRef = null) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker != null and not marker.is_queued_for_deletion():
		marker.set_meta("action_presenter_active", false)
		marker.queue_free()
	if label_ref != null:
		var label := label_ref.get_ref() as Node
		if label != null and not label.is_queued_for_deletion():
			label.set_meta("action_presenter_active", false)
			label.queue_free()
	_prune_active_refs()
	_tracker.refresh_latest_active()


func _interaction_public_snapshot(interaction: Dictionary, active: bool, reason: String) -> Dictionary:
	return {
		"active": active,
		"kind": "interaction",
		"reason": reason,
		"actor_id": int(interaction.get("actor_id", 0)),
		"target_id": str(interaction.get("target_id", "")),
		"target_type": str(interaction.get("target_type", "")),
		"target_name": str(interaction.get("target_name", "")),
		"target_grid": _dictionary_or_empty(interaction.get("target_grid", {})).duplicate(true),
		"option_kind": str(interaction.get("option_kind", "")),
		"visual_kind": str(interaction.get("visual_kind", _interaction_visual_kind(str(interaction.get("option_kind", ""))))),
		"node_path": str(interaction.get("node_path", "")),
		"phases": INTERACTION_PHASES.duplicate(),
		"phase_count": INTERACTION_PHASES.size(),
		"current_phase": INTERACTION_PHASES[0] if active else "",
		"phase_durations": _phase_durations_or_default(interaction.get("phase_durations", INTERACTION_PHASE_DURATIONS), INTERACTION_PHASE_DURATIONS),
		"duration_sec": _duration_sum(_phase_durations_or_default(interaction.get("phase_durations", INTERACTION_PHASE_DURATIONS), INTERACTION_PHASE_DURATIONS)) if active else 0.0,
		"marker_y_offset": float(interaction.get("marker_y_offset", 0.22)),
		"label_text": _interaction_feedback_text(str(interaction.get("option_kind", ""))),
		"label_y_offset": float(_interaction_visual_profile(str(interaction.get("option_kind", ""))).get("label_y_offset", 1.18)),
	}


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


func _interaction_target_node(world_root: Node, world_result: Dictionary, payload: Dictionary) -> Node3D:
	if str(payload.get("target_type", "")) == "actor":
		return _actor_node(world_root, world_result, int(payload.get("target_id", 0)))
	var target_id := str(payload.get("target_id", ""))
	if target_id.is_empty():
		return null
	for name in ["MapObject_%s" % target_id, target_id]:
		var node := world_root.find_child(name, true, false) as Node3D
		if node != null:
			return node
	return null


func _presentation_layer(world_root: Node) -> Node3D:
	var layer: Node3D = world_root.find_child("WorldActionPresentationLayer", false, false) as Node3D
	if layer == null:
		layer = Node3D.new()
		layer.name = "WorldActionPresentationLayer"
		world_root.add_child(layer)
	return layer


func _interaction_visual_profile(option_kind: String) -> Dictionary:
	var profile := {
		"visual_kind": _interaction_visual_kind(option_kind),
		"phase_durations": INTERACTION_PHASE_DURATIONS.duplicate(),
		"top_radius": 0.34,
		"bottom_radius": 0.34,
		"height": 0.055,
		"radial_segments": 24,
		"y_offset": 0.22,
		"start_scale": Vector3(0.82, 1.0, 0.82),
		"pulse_scale": Vector3(1.35, 1.0, 1.35),
		"fade_scale": Vector3(0.55, 1.0, 0.55),
		"color": Color(0.9, 0.86, 0.34, 0.8),
		"label_color": Color(1.0, 0.92, 0.44, 0.94),
		"label_y_offset": 1.18,
	}
	match option_kind:
		"pickup":
			profile["color"] = Color(0.22, 0.74, 1.0, 0.82)
			profile["label_color"] = Color(0.70, 0.92, 1.0, 0.96)
			profile["pulse_scale"] = Vector3(1.42, 1.0, 1.42)
		"open_container":
			profile["color"] = Color(0.34, 0.92, 0.42, 0.82)
			profile["label_color"] = Color(0.66, 1.0, 0.62, 0.96)
			profile["height"] = 0.08
			profile["y_offset"] = 0.36
			profile["label_y_offset"] = 1.24
			profile["pulse_scale"] = Vector3(1.24, 1.18, 1.24)
		"door_toggle":
			profile["color"] = Color(0.98, 0.66, 0.22, 0.86)
			profile["label_color"] = Color(1.0, 0.78, 0.38, 0.96)
			profile["top_radius"] = 0.24
			profile["bottom_radius"] = 0.42
			profile["height"] = 0.11
			profile["y_offset"] = 0.42
			profile["label_y_offset"] = 1.30
			profile["pulse_scale"] = Vector3(1.18, 1.34, 1.18)
		"talk":
			profile["color"] = Color(0.72, 0.54, 1.0, 0.84)
			profile["label_color"] = Color(0.86, 0.74, 1.0, 0.96)
			profile["y_offset"] = 0.92
			profile["label_y_offset"] = 1.58
			profile["pulse_scale"] = Vector3(1.15, 1.26, 1.15)
		"open_trade":
			profile["color"] = Color(0.26, 0.86, 0.76, 0.84)
			profile["label_color"] = Color(0.62, 1.0, 0.92, 0.96)
			profile["y_offset"] = 0.86
			profile["label_y_offset"] = 1.50
			profile["pulse_scale"] = Vector3(1.22, 1.16, 1.22)
		"open_crafting":
			profile["color"] = Color(0.96, 0.78, 0.26, 0.84)
			profile["label_color"] = Color(1.0, 0.88, 0.48, 0.96)
			profile["height"] = 0.075
			profile["label_y_offset"] = 1.22
			profile["pulse_scale"] = Vector3(1.18, 1.28, 1.18)
		"enter_subscene", "scene_transition":
			profile["color"] = Color(0.42, 0.8, 1.0, 0.86)
			profile["label_color"] = Color(0.70, 0.90, 1.0, 0.96)
			profile["top_radius"] = 0.22
			profile["bottom_radius"] = 0.48
			profile["height"] = 0.14
			profile["y_offset"] = 0.3
			profile["label_y_offset"] = 1.26
			profile["phase_durations"] = [0.05, 0.12, 0.14]
			profile["pulse_scale"] = Vector3(1.52, 1.0, 1.52)
		"wait":
			profile["color"] = Color(0.7, 0.76, 0.86, 0.78)
			profile["label_color"] = Color(0.84, 0.88, 0.96, 0.94)
			profile["top_radius"] = 0.26
			profile["bottom_radius"] = 0.26
			profile["height"] = 0.045
			profile["y_offset"] = 0.74
			profile["label_y_offset"] = 1.34
			profile["phase_durations"] = [0.05, 0.07, 0.08]
	return profile


func _interaction_visual_kind(option_kind: String) -> String:
	match option_kind:
		"pickup":
			return "item_pickup"
		"open_container":
			return "container_open"
		"door_toggle":
			return "door_toggle"
		"talk":
			return "dialogue_start"
		"open_trade":
			return "trade_open"
		"open_crafting":
			return "crafting_station"
		"enter_subscene", "scene_transition":
			return "scene_transition"
		"wait":
			return "wait"
	return "interaction_pulse"


func _interaction_material(option_kind: String) -> StandardMaterial3D:
	return _materials.interaction_material(_interaction_visual_profile(option_kind))


func _interaction_label(interaction: Dictionary, visual_profile: Dictionary) -> Label3D:
	var label_color: Variant = visual_profile.get("label_color", Color(1.0, 0.92, 0.44, 0.94))
	var label := _node_factory.label3d(
		"WorldActionInteractionText",
		_interaction_feedback_text(str(interaction.get("option_kind", ""))),
		14,
		label_color if typeof(label_color) == TYPE_COLOR else Color(1.0, 0.92, 0.44, 0.94)
	)
	label.set_meta("action_presenter_active", true)
	label.set_meta("action_presenter_kind", "interaction_text")
	label.set_meta("action_presenter_phases", INTERACTION_PHASES.duplicate())
	label.set_meta("action_presenter_phase_count", INTERACTION_PHASES.size())
	label.set_meta("action_presenter_current_phase", INTERACTION_PHASES[0])
	label.set_meta("action_presenter_duration_sec", _duration_sum(_phase_durations_or_default(visual_profile.get("phase_durations", INTERACTION_PHASE_DURATIONS), INTERACTION_PHASE_DURATIONS)))
	label.set_meta("actor_id", int(interaction.get("actor_id", 0)))
	label.set_meta("target_id", str(interaction.get("target_id", "")))
	label.set_meta("target_type", str(interaction.get("target_type", "")))
	label.set_meta("target_name", str(interaction.get("target_name", "")))
	label.set_meta("target_grid", _dictionary_or_empty(interaction.get("target_grid", {})).duplicate(true))
	label.set_meta("option_kind", str(interaction.get("option_kind", "")))
	label.set_meta("visual_kind", str(visual_profile.get("visual_kind", "")))
	label.set_meta("text", label.text)
	return label


func _interaction_feedback_text(option_kind: String) -> String:
	match option_kind:
		"pickup":
			return "拾取"
		"open_container":
			return "打开"
		"door_toggle":
			return "开关"
		"talk":
			return "对话"
		"open_trade":
			return "交易"
		"open_crafting":
			return "制作"
		"enter_subscene", "scene_transition":
			return "进入"
		"wait":
			return "等待"
	return "互动"


func _set_marker_phase(marker_ref: WeakRef, phase: String) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker == null or marker.is_queued_for_deletion():
		return
	marker.set_meta("action_presenter_current_phase", phase)
	if str(_tracker.latest_value("marker_path", "")) == str(marker.get_path()):
		_tracker.set_latest_value("current_phase", phase)


func _duration_sum(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += float(value)
	return total


func _phase_durations_or_default(value: Variant, fallback: Array) -> Array:
	var source := _array_or_empty(value)
	if source.size() < 3:
		source = fallback
	var output: Array = []
	for index in range(3):
		output.append(max(0.001, float(source[index])))
	return output


func _vector3_or_default(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) == TYPE_VECTOR3:
		return value
	return fallback


func _track_active_node(node: Node) -> void:
	_tracker.track_active_node(node)


func _track_active_tween(tween: Tween) -> void:
	_tracker.track_active_tween(tween)


func _prune_active_refs() -> void:
	_tracker.prune_active_refs()


func _prune_active_tweens() -> void:
	_tracker.prune_active_tweens()


func _record_latest(snapshot_data: Dictionary) -> Dictionary:
	return _tracker.record_latest(snapshot_data)


func _grid_to_world(grid: Dictionary, y: float = DEFAULT_ACTOR_Y) -> Vector3:
	return Vector3(float(grid.get("x", 0)) * GRID_SIZE, float(grid.get("y", 0)) + y, float(grid.get("z", 0)) * GRID_SIZE)


func _basis_from_y(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	if y_axis.length() <= 0.001:
		y_axis = Vector3.UP
	var helper := Vector3.UP
	if absf(y_axis.dot(helper)) > 0.96:
		helper = Vector3.RIGHT
	var x_axis := helper.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


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


func _string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	for item in _array_or_empty(value):
		output.append(str(item))
	return output


func _int_array(value: Variant) -> Array:
	var output: Array = []
	for item in _array_or_empty(value):
		var normalized := int(item)
		if normalized > 0 and not output.has(normalized):
			output.append(normalized)
	return output
