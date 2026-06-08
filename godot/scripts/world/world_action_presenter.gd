extends RefCounted

const UIThemeService = preload("res://scripts/ui/ui_theme_service.gd")

const GRID_SIZE := 1.0
const DEFAULT_ACTOR_Y := 0.58
const STEP_DURATION_SEC := 0.07
const ATTACK_PHASES := ["windup", "impact", "fade"]
const INTERACTION_PHASES := ["start", "pulse", "fade"]
const COMBAT_EVENT_PHASES := ["signal", "resolve", "fade"]
const ATTACK_PHASE_DURATIONS := [0.06, 0.08, 0.10]
const INTERACTION_PHASE_DURATIONS := [0.06, 0.08, 0.10]
const COMBAT_EVENT_PHASE_DURATIONS := [0.05, 0.10, 0.12]

var sequence: int = 0
var active_count: int = 0
var active_refs: Array[WeakRef] = []
var active_tweens: Array = []
var latest: Dictionary = {}


func present_result(host: Node, world_root: Node, command_result: Dictionary, world_result: Dictionary) -> Dictionary:
	if host == null or world_root == null:
		return _record_latest({"active": false, "kind": "none", "reason": "presenter_target_missing"})
	var events := _events_from_result(command_result)
	if _result_changes_map(command_result, events):
		return _record_latest({"active": false, "kind": "scene_transition", "event_count": events.size()})
	var movement := _movement_presentation(events, world_root, world_result)
	var interaction := _interaction_presentation(events, world_root, world_result)
	if not movement.is_empty() and not interaction.is_empty():
		_start_movement_tween(host, movement)
		_start_interaction_feedback(host, world_root, interaction)
		return latest.duplicate(true)
	if not movement.is_empty():
		_start_movement_tween(host, movement)
		return latest.duplicate(true)
	var attack := _attack_presentation(events, world_root, world_result)
	if not attack.is_empty():
		var combat_event := _combat_event_presentation(events, world_root, world_result)
		if attack.get("target_node", null) == null and not combat_event.is_empty():
			_start_combat_event_feedback(host, world_root, combat_event)
			return latest.duplicate(true)
		_start_attack_feedback(host, world_root, attack)
		return latest.duplicate(true)
	if not interaction.is_empty():
		_start_interaction_feedback(host, world_root, interaction)
		return latest.duplicate(true)
	var combat_event := _combat_event_presentation(events, world_root, world_result)
	if not combat_event.is_empty():
		_start_combat_event_feedback(host, world_root, combat_event)
		return latest.duplicate(true)
	return _record_latest({"active": false, "kind": "none", "event_count": events.size()})


func snapshot() -> Dictionary:
	_prune_active_refs()
	var output := latest.duplicate(true)
	output["active"] = active_count > 0
	output["active_count"] = active_count
	output["sequence"] = sequence
	return output


func finish_active_presentations() -> Dictionary:
	for tween_value in active_tweens:
		var tween := tween_value as Tween
		if tween != null and tween.is_valid():
			tween.kill()
	active_tweens.clear()
	for node_ref in active_refs:
		var node := node_ref.get_ref() as Node
		if node == null or node.is_queued_for_deletion():
			continue
		if node is Node3D and node.has_meta("action_presenter_final_position"):
			var final_position: Variant = node.get_meta("action_presenter_final_position")
			if typeof(final_position) == TYPE_VECTOR3:
				(node as Node3D).position = final_position
		node.set_meta("action_presenter_active", false)
		if str(node.name).begins_with("WorldAction"):
			node.queue_free()
	active_refs.clear()
	active_count = 0
	latest["active"] = false
	latest["active_count"] = 0
	latest["fast_forwarded"] = true
	return snapshot()


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
	var run_sequence := sequence
	var y := actor_node.position.y
	actor_node.position = _grid_to_world(_dictionary_or_empty(path[0]), y)
	actor_node.set_meta("action_presenter_active", true)
	actor_node.set_meta("action_presenter_kind", "movement")
	actor_node.set_meta("action_presenter_sequence", run_sequence)
	actor_node.set_meta("action_presenter_step_count", max(0, path.size() - 1))
	actor_node.set_meta("action_presenter_final_position", _grid_to_world(_dictionary_or_empty(path[path.size() - 1]), y))
	_track_active_node(actor_node)
	var tween := host.create_tween()
	_track_active_tween(tween)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	for index in range(1, path.size()):
		tween.tween_property(actor_node, "position", _grid_to_world(_dictionary_or_empty(path[index]), y), STEP_DURATION_SEC)
	tween.finished.connect(Callable(self, "_on_movement_tween_finished").bind(run_sequence, weakref(actor_node)))
	_record_latest(_presentation_public_snapshot(movement, true))


func _on_movement_tween_finished(run_sequence: int, actor_ref: WeakRef) -> void:
	var actor_node := actor_ref.get_ref() as Node3D
	if actor_node != null and not actor_node.is_queued_for_deletion() and int(actor_node.get_meta("action_presenter_sequence", 0)) == run_sequence:
		actor_node.set_meta("action_presenter_active", false)
	_prune_active_refs()
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
		var actor_node := _actor_node(world_root, world_result, actor_id)
		var target_node := _actor_node(world_root, world_result, target_actor_id)
		var triggered_effect_ids := _string_array(payload.get("triggered_on_hit_effect_ids", []))
		var applied_effects := _array_or_empty(payload.get("applied_on_hit_effects", [])).duplicate(true)
		var attack_range := int(payload.get("range", 1))
		return {
			"active": false,
			"kind": "attack",
			"actor_id": actor_id,
			"target_actor_id": target_actor_id,
			"damage": float(payload.get("damage", 0.0)),
			"hit_kind": str(payload.get("hit_kind", "")),
			"critical": bool(payload.get("critical", false)),
			"defeated": bool(payload.get("defeated", false)),
			"attack_delivery": _attack_delivery(attack_range),
			"range": attack_range,
			"weapon_item_id": str(payload.get("weapon_item_id", "")),
			"base_damage": float(payload.get("base_damage", 0.0)),
			"crit_multiplier": float(payload.get("crit_multiplier", 1.0)),
			"crit_roll": float(payload.get("crit_roll", 1.0)),
			"crit_chance": float(payload.get("crit_chance", 0.0)),
			"defense": float(payload.get("defense", 0.0)),
			"damage_reduction": float(payload.get("damage_reduction", 0.0)),
			"damage_bonus": float(payload.get("damage_bonus", 0.0)),
			"hit_roll": float(payload.get("hit_roll", 0.0)),
			"hit_chance": float(payload.get("hit_chance", 1.0)),
			"accuracy": float(payload.get("accuracy", 0.0)),
			"evasion": float(payload.get("evasion", 0.0)),
			"triggered_on_hit_effect_ids": triggered_effect_ids,
			"triggered_on_hit_effect_count": triggered_effect_ids.size(),
			"applied_on_hit_effects": applied_effects,
			"applied_on_hit_effect_count": applied_effects.size(),
			"combat_rng_seed": int(payload.get("combat_rng_seed", 0)),
			"combat_rng_counter": int(payload.get("combat_rng_counter", 0)),
			"combat_rng_salt": int(payload.get("combat_rng_salt", 0)),
			"friendly_fire": bool(payload.get("friendly_fire", false)),
			"relationship_consequence": _dictionary_or_empty(payload.get("relationship_consequence", {})).duplicate(true),
			"actor_node": actor_node,
			"actor_node_path": str(actor_node.get_path()) if actor_node != null else "",
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
	var run_sequence := sequence
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
	marker.set_meta("action_presenter_phases", ATTACK_PHASES.duplicate())
	marker.set_meta("action_presenter_phase_count", ATTACK_PHASES.size())
	marker.set_meta("action_presenter_current_phase", ATTACK_PHASES[0])
	marker.set_meta("action_presenter_duration_sec", _duration_sum(ATTACK_PHASE_DURATIONS))
	marker.set_meta("actor_id", int(attack.get("actor_id", 0)))
	marker.set_meta("target_actor_id", int(attack.get("target_actor_id", 0)))
	marker.set_meta("damage", float(attack.get("damage", 0.0)))
	marker.set_meta("hit_kind", str(attack.get("hit_kind", "")))
	marker.set_meta("critical", bool(attack.get("critical", false)))
	marker.set_meta("defeated", bool(attack.get("defeated", false)))
	_apply_attack_event_meta(marker, attack)
	_track_active_node(marker)
	var delivery_marker: MeshInstance3D = _attack_delivery_marker(attack, target_position)
	if delivery_marker != null:
		delivery_marker.set_meta("action_presenter_sequence", run_sequence)
		_track_active_node(delivery_marker)
	var damage_label := _attack_damage_label(attack)
	damage_label.position = target_position + Vector3(0.0, 1.52, 0.0)
	damage_label.set_meta("action_presenter_sequence", run_sequence)
	_track_active_node(damage_label)
	var on_hit_label: Label3D = _attack_on_hit_effect_label(attack) as Label3D
	if on_hit_label != null:
		on_hit_label.position = target_position + Vector3(0.0, 1.88, 0.0)
		on_hit_label.set_meta("action_presenter_sequence", run_sequence)
		_track_active_node(on_hit_label)
	var layer := _presentation_layer(world_root)
	layer.add_child(marker)
	if delivery_marker != null:
		layer.add_child(delivery_marker)
	layer.add_child(damage_label)
	if on_hit_label != null:
		layer.add_child(on_hit_label)
	var tween := host.create_tween()
	_track_active_tween(tween)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(marker, "scale", Vector3(0.72, 0.72, 0.72), float(ATTACK_PHASE_DURATIONS[0]))
	if delivery_marker != null:
		tween.parallel().tween_property(delivery_marker, "scale", Vector3(1.0, 1.0, 1.0), float(ATTACK_PHASE_DURATIONS[0]))
	tween.parallel().tween_property(damage_label, "position", damage_label.position + Vector3(0.0, 0.16, 0.0), float(ATTACK_PHASE_DURATIONS[0]))
	if on_hit_label != null:
		tween.parallel().tween_property(on_hit_label, "position", on_hit_label.position + Vector3(0.0, 0.12, 0.0), float(ATTACK_PHASE_DURATIONS[0]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), ATTACK_PHASES[1]))
	if delivery_marker != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(delivery_marker), ATTACK_PHASES[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(damage_label), ATTACK_PHASES[1]))
	if on_hit_label != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(on_hit_label), ATTACK_PHASES[1]))
	tween.tween_property(marker, "scale", Vector3(1.45, 1.45, 1.45), float(ATTACK_PHASE_DURATIONS[1]))
	if delivery_marker != null:
		tween.parallel().tween_property(delivery_marker, "scale", Vector3(1.08, 1.08, 1.08), float(ATTACK_PHASE_DURATIONS[1]))
	tween.parallel().tween_property(damage_label, "position", damage_label.position + Vector3(0.0, 0.36, 0.0), float(ATTACK_PHASE_DURATIONS[1]))
	if on_hit_label != null:
		tween.parallel().tween_property(on_hit_label, "position", on_hit_label.position + Vector3(0.0, 0.30, 0.0), float(ATTACK_PHASE_DURATIONS[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), ATTACK_PHASES[2]))
	if delivery_marker != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(delivery_marker), ATTACK_PHASES[2]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(damage_label), ATTACK_PHASES[2]))
	if on_hit_label != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(on_hit_label), ATTACK_PHASES[2]))
	tween.tween_property(marker, "scale", Vector3(0.35, 0.35, 0.35), float(ATTACK_PHASE_DURATIONS[2]))
	if delivery_marker != null:
		tween.parallel().tween_property(delivery_marker, "scale", Vector3(0.12, 0.12, 0.12), float(ATTACK_PHASE_DURATIONS[2]))
	tween.parallel().tween_property(damage_label, "modulate", Color(damage_label.modulate.r, damage_label.modulate.g, damage_label.modulate.b, 0.0), float(ATTACK_PHASE_DURATIONS[2]))
	if on_hit_label != null:
		tween.parallel().tween_property(on_hit_label, "modulate", Color(on_hit_label.modulate.r, on_hit_label.modulate.g, on_hit_label.modulate.b, 0.0), float(ATTACK_PHASE_DURATIONS[2]))
	var on_hit_label_ref: WeakRef = weakref(on_hit_label) if on_hit_label != null else null
	var delivery_marker_ref: WeakRef = weakref(delivery_marker) if delivery_marker != null else null
	tween.finished.connect(Callable(self, "_on_attack_feedback_finished").bind(weakref(marker), weakref(damage_label), on_hit_label_ref, delivery_marker_ref))
	var snapshot_data := _attack_public_snapshot(attack, true, "")
	snapshot_data["marker_path"] = str(marker.get_path())
	if delivery_marker != null:
		snapshot_data["delivery_marker_path"] = str(delivery_marker.get_path())
		snapshot_data["delivery_visual_kind"] = str(delivery_marker.get_meta("delivery_visual_kind", ""))
		snapshot_data["delivery_distance"] = float(delivery_marker.get_meta("delivery_distance", 0.0))
	snapshot_data["damage_label_path"] = str(damage_label.get_path())
	snapshot_data["damage_label_text"] = str(damage_label.text)
	if on_hit_label != null:
		snapshot_data["on_hit_effect_label_path"] = str(on_hit_label.get_path())
		snapshot_data["on_hit_effect_label_text"] = str(on_hit_label.text)
	_record_latest(snapshot_data)


func _on_attack_feedback_finished(marker_ref: WeakRef, damage_label_ref: WeakRef = null, on_hit_label_ref: WeakRef = null, delivery_marker_ref: WeakRef = null) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker != null and not marker.is_queued_for_deletion():
		marker.set_meta("action_presenter_active", false)
		marker.queue_free()
	if delivery_marker_ref != null:
		var delivery_marker := delivery_marker_ref.get_ref() as Node
		if delivery_marker != null and not delivery_marker.is_queued_for_deletion():
			delivery_marker.set_meta("action_presenter_active", false)
			delivery_marker.queue_free()
	if damage_label_ref != null:
		var damage_label := damage_label_ref.get_ref() as Node
		if damage_label != null and not damage_label.is_queued_for_deletion():
			damage_label.set_meta("action_presenter_active", false)
			damage_label.queue_free()
	if on_hit_label_ref != null:
		var on_hit_label := on_hit_label_ref.get_ref() as Node
		if on_hit_label != null and not on_hit_label.is_queued_for_deletion():
			on_hit_label.set_meta("action_presenter_active", false)
			on_hit_label.queue_free()
	_prune_active_refs()
	latest["active"] = active_count > 0
	latest["active_count"] = active_count


func _attack_public_snapshot(attack: Dictionary, active: bool, reason: String) -> Dictionary:
	return {
		"active": active,
		"kind": "attack",
		"reason": reason,
		"actor_id": int(attack.get("actor_id", 0)),
		"target_actor_id": int(attack.get("target_actor_id", 0)),
		"actor_node_path": str(attack.get("actor_node_path", "")),
		"node_path": str(attack.get("node_path", "")),
		"damage": float(attack.get("damage", 0.0)),
		"damage_label_text": _attack_feedback_text(attack),
		"on_hit_effect_label_text": _on_hit_effect_feedback_text(attack),
		"hit_kind": str(attack.get("hit_kind", "")),
		"critical": bool(attack.get("critical", false)),
		"defeated": bool(attack.get("defeated", false)),
		"attack_delivery": str(attack.get("attack_delivery", "")),
		"delivery_visual_kind": _attack_delivery_visual_kind(attack),
		"range": int(attack.get("range", 0)),
		"weapon_item_id": str(attack.get("weapon_item_id", "")),
		"base_damage": float(attack.get("base_damage", 0.0)),
		"crit_multiplier": float(attack.get("crit_multiplier", 1.0)),
		"crit_roll": float(attack.get("crit_roll", 1.0)),
		"crit_chance": float(attack.get("crit_chance", 0.0)),
		"defense": float(attack.get("defense", 0.0)),
		"damage_reduction": float(attack.get("damage_reduction", 0.0)),
		"damage_bonus": float(attack.get("damage_bonus", 0.0)),
		"hit_roll": float(attack.get("hit_roll", 0.0)),
		"hit_chance": float(attack.get("hit_chance", 1.0)),
		"accuracy": float(attack.get("accuracy", 0.0)),
		"evasion": float(attack.get("evasion", 0.0)),
		"triggered_on_hit_effect_ids": _array_or_empty(attack.get("triggered_on_hit_effect_ids", [])).duplicate(true),
		"triggered_on_hit_effect_count": int(attack.get("triggered_on_hit_effect_count", 0)),
		"applied_on_hit_effects": _array_or_empty(attack.get("applied_on_hit_effects", [])).duplicate(true),
		"applied_on_hit_effect_count": int(attack.get("applied_on_hit_effect_count", 0)),
		"combat_rng_seed": int(attack.get("combat_rng_seed", 0)),
		"combat_rng_counter": int(attack.get("combat_rng_counter", 0)),
		"combat_rng_salt": int(attack.get("combat_rng_salt", 0)),
		"friendly_fire": bool(attack.get("friendly_fire", false)),
		"relationship_consequence": _dictionary_or_empty(attack.get("relationship_consequence", {})).duplicate(true),
		"phases": ATTACK_PHASES.duplicate(),
		"phase_count": ATTACK_PHASES.size(),
		"current_phase": ATTACK_PHASES[0] if active else "",
		"duration_sec": _duration_sum(ATTACK_PHASE_DURATIONS) if active else 0.0,
	}


func _attack_damage_label(attack: Dictionary) -> Label3D:
	var label := Label3D.new()
	label.name = "WorldActionDamageText"
	label.text = _attack_feedback_text(attack)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 18
	label.modulate = _attack_feedback_color(str(attack.get("hit_kind", "")), bool(attack.get("critical", false)), bool(attack.get("defeated", false)))
	label.outline_size = 4
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.78)
	var font_result := UIThemeService.apply_label3d_font(label)
	label.set_meta("font_resource_path", str(font_result.get("font_resource_path", "")))
	label.set_meta("action_presenter_active", true)
	label.set_meta("action_presenter_kind", "attack_damage_text")
	label.set_meta("action_presenter_phases", ATTACK_PHASES.duplicate())
	label.set_meta("action_presenter_phase_count", ATTACK_PHASES.size())
	label.set_meta("action_presenter_current_phase", ATTACK_PHASES[0])
	label.set_meta("action_presenter_duration_sec", _duration_sum(ATTACK_PHASE_DURATIONS))
	label.set_meta("actor_id", int(attack.get("actor_id", 0)))
	label.set_meta("target_actor_id", int(attack.get("target_actor_id", 0)))
	label.set_meta("damage", float(attack.get("damage", 0.0)))
	label.set_meta("hit_kind", str(attack.get("hit_kind", "")))
	label.set_meta("critical", bool(attack.get("critical", false)))
	label.set_meta("defeated", bool(attack.get("defeated", false)))
	_apply_attack_event_meta(label, attack)
	label.set_meta("text", label.text)
	return label


func _attack_delivery_marker(attack: Dictionary, target_position: Vector3):
	var actor_node: Node3D = attack.get("actor_node", null)
	var target_node: Node3D = attack.get("target_node", null)
	if actor_node == null or target_node == null:
		return null
	var actor_position := actor_node.global_position if actor_node.is_inside_tree() else actor_node.position
	var end_position := target_node.global_position if target_node.is_inside_tree() else target_node.position
	var start := actor_position + Vector3(0.0, 1.02, 0.0)
	var end := end_position + Vector3(0.0, 1.02, 0.0)
	var direction := end - start
	var distance := direction.length()
	if distance <= 0.01:
		direction = Vector3.FORWARD
		distance = 0.34
	var delivery := str(attack.get("attack_delivery", ""))
	var visual_kind := _attack_delivery_visual_kind(attack)
	var marker := MeshInstance3D.new()
	marker.name = "WorldActionAttackDelivery"
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 10
	if delivery == "ranged":
		mesh.top_radius = 0.045
		mesh.bottom_radius = 0.045
		mesh.height = max(0.35, distance)
		marker.position = start.lerp(end, 0.5)
	else:
		mesh.top_radius = 0.07
		mesh.bottom_radius = 0.18
		mesh.height = 0.62
		marker.position = target_position + Vector3(0.0, 1.18, 0.0)
	marker.mesh = mesh
	marker.material_override = _attack_delivery_material(delivery)
	marker.basis = _basis_from_y(direction.normalized())
	if delivery != "ranged":
		marker.rotate_object_local(Vector3.RIGHT, deg_to_rad(28.0))
	marker.scale = Vector3(0.28, 0.28, 0.28)
	marker.set_meta("action_presenter_active", true)
	marker.set_meta("action_presenter_kind", "attack_delivery")
	marker.set_meta("action_presenter_phases", ATTACK_PHASES.duplicate())
	marker.set_meta("action_presenter_phase_count", ATTACK_PHASES.size())
	marker.set_meta("action_presenter_current_phase", ATTACK_PHASES[0])
	marker.set_meta("action_presenter_duration_sec", _duration_sum(ATTACK_PHASE_DURATIONS))
	marker.set_meta("delivery_visual_kind", visual_kind)
	marker.set_meta("delivery_distance", distance)
	marker.set_meta("actor_node_path", str(actor_node.get_path()))
	marker.set_meta("target_node_path", str(target_node.get_path()))
	marker.set_meta("start_position", start)
	marker.set_meta("end_position", end)
	marker.set_meta("actor_id", int(attack.get("actor_id", 0)))
	marker.set_meta("target_actor_id", int(attack.get("target_actor_id", 0)))
	_apply_attack_event_meta(marker, attack)
	return marker


func _attack_on_hit_effect_label(attack: Dictionary):
	var effects: Array = _array_or_empty(attack.get("applied_on_hit_effects", []))
	if effects.is_empty():
		return null
	var label := Label3D.new()
	label.name = "WorldActionOnHitEffect"
	label.text = _on_hit_effect_feedback_text(attack)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 14
	label.modulate = _on_hit_effect_feedback_color(effects)
	label.outline_size = 4
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.78)
	var font_result := UIThemeService.apply_label3d_font(label)
	label.set_meta("font_resource_path", str(font_result.get("font_resource_path", "")))
	label.set_meta("action_presenter_active", true)
	label.set_meta("action_presenter_kind", "attack_on_hit_effect")
	label.set_meta("action_presenter_phases", ATTACK_PHASES.duplicate())
	label.set_meta("action_presenter_phase_count", ATTACK_PHASES.size())
	label.set_meta("action_presenter_current_phase", ATTACK_PHASES[0])
	label.set_meta("action_presenter_duration_sec", _duration_sum(ATTACK_PHASE_DURATIONS))
	label.set_meta("actor_id", int(attack.get("actor_id", 0)))
	label.set_meta("target_actor_id", int(attack.get("target_actor_id", 0)))
	_apply_attack_event_meta(label, attack)
	label.set_meta("effect_ids", _on_hit_effect_ids(effects))
	label.set_meta("effect_names", _on_hit_effect_names(effects))
	label.set_meta("effect_categories", _on_hit_effect_categories(effects))
	label.set_meta("applied_effect_count", effects.size())
	label.set_meta("text", label.text)
	return label


func _apply_attack_event_meta(node: Node, attack: Dictionary) -> void:
	node.set_meta("attack_delivery", str(attack.get("attack_delivery", "")))
	node.set_meta("range", int(attack.get("range", 0)))
	node.set_meta("weapon_item_id", str(attack.get("weapon_item_id", "")))
	node.set_meta("base_damage", float(attack.get("base_damage", 0.0)))
	node.set_meta("crit_multiplier", float(attack.get("crit_multiplier", 1.0)))
	node.set_meta("crit_roll", float(attack.get("crit_roll", 1.0)))
	node.set_meta("crit_chance", float(attack.get("crit_chance", 0.0)))
	node.set_meta("defense", float(attack.get("defense", 0.0)))
	node.set_meta("damage_reduction", float(attack.get("damage_reduction", 0.0)))
	node.set_meta("damage_bonus", float(attack.get("damage_bonus", 0.0)))
	node.set_meta("hit_roll", float(attack.get("hit_roll", 0.0)))
	node.set_meta("hit_chance", float(attack.get("hit_chance", 1.0)))
	node.set_meta("accuracy", float(attack.get("accuracy", 0.0)))
	node.set_meta("evasion", float(attack.get("evasion", 0.0)))
	node.set_meta("triggered_on_hit_effect_ids", _array_or_empty(attack.get("triggered_on_hit_effect_ids", [])).duplicate(true))
	node.set_meta("triggered_on_hit_effect_count", int(attack.get("triggered_on_hit_effect_count", 0)))
	node.set_meta("applied_on_hit_effects", _array_or_empty(attack.get("applied_on_hit_effects", [])).duplicate(true))
	node.set_meta("applied_on_hit_effect_count", int(attack.get("applied_on_hit_effect_count", 0)))
	node.set_meta("combat_rng_seed", int(attack.get("combat_rng_seed", 0)))
	node.set_meta("combat_rng_counter", int(attack.get("combat_rng_counter", 0)))
	node.set_meta("combat_rng_salt", int(attack.get("combat_rng_salt", 0)))
	node.set_meta("friendly_fire", bool(attack.get("friendly_fire", false)))
	node.set_meta("relationship_consequence", _dictionary_or_empty(attack.get("relationship_consequence", {})).duplicate(true))


func _attack_delivery(attack_range: int) -> String:
	return "ranged" if attack_range > 1 else "melee"


func _attack_delivery_visual_kind(attack: Dictionary) -> String:
	return "ranged_projectile" if str(attack.get("attack_delivery", "")) == "ranged" else "melee_swing"


func _attack_feedback_text(attack: Dictionary) -> String:
	var hit_kind := str(attack.get("hit_kind", "hit"))
	if hit_kind == "miss":
		return "MISS"
	if hit_kind == "blocked":
		return "BLOCK"
	var amount := int(round(max(0.0, float(attack.get("damage", 0.0)))))
	var text := "-%d" % amount
	if bool(attack.get("critical", false)):
		text = "CRIT %s" % text
	if bool(attack.get("defeated", false)):
		text = "%s KO" % text
	return text


func _on_hit_effect_feedback_text(attack: Dictionary) -> String:
	var effects: Array = _array_or_empty(attack.get("applied_on_hit_effects", []))
	if effects.is_empty():
		return ""
	var names := _on_hit_effect_names(effects)
	if names.is_empty():
		return "EFFECT x%d" % effects.size()
	if names.size() == 1:
		return "+%s" % str(names[0])
	return "+%s +%d" % [str(names[0]), names.size() - 1]


func _on_hit_effect_feedback_color(effects: Array) -> Color:
	for effect in effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		var applied: Dictionary = _dictionary_or_empty(effect_data.get("effect", {}))
		var category := str(applied.get("category", effect_data.get("category", "")))
		if category in ["debuff", "negative", "harmful"]:
			return Color(0.92, 0.22, 0.18, 0.94)
		if category in ["buff", "positive", "beneficial"]:
			return Color(0.36, 0.92, 0.42, 0.94)
	return Color(0.74, 0.54, 1.0, 0.92)


func _on_hit_effect_ids(effects: Array) -> Array[String]:
	var output: Array[String] = []
	for effect in effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		var effect_id := str(effect_data.get("effect_id", ""))
		if effect_id.is_empty():
			effect_id = str(_dictionary_or_empty(effect_data.get("effect", {})).get("base_effect_id", ""))
		if not effect_id.is_empty():
			output.append(effect_id)
	return output


func _on_hit_effect_names(effects: Array) -> Array[String]:
	var output: Array[String] = []
	for effect in effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		var applied: Dictionary = _dictionary_or_empty(effect_data.get("effect", {}))
		var name := str(applied.get("name", effect_data.get("name", effect_data.get("effect_id", "")))).strip_edges()
		if not name.is_empty():
			output.append(name)
	return output


func _on_hit_effect_categories(effects: Array) -> Array[String]:
	var output: Array[String] = []
	for effect in effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		var applied: Dictionary = _dictionary_or_empty(effect_data.get("effect", {}))
		var category := str(applied.get("category", effect_data.get("category", ""))).strip_edges()
		if not category.is_empty():
			output.append(category)
	return output


func _attack_feedback_color(hit_kind: String, critical: bool, defeated: bool) -> Color:
	if defeated:
		return Color(1.0, 0.16, 0.12, 0.96)
	if critical:
		return Color(1.0, 0.86, 0.18, 0.96)
	if hit_kind == "miss":
		return Color(0.66, 0.82, 1.0, 0.9)
	if hit_kind == "blocked":
		return Color(0.72, 0.74, 0.82, 0.9)
	return Color(1.0, 0.38, 0.22, 0.94)


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
	sequence += 1
	var visual_profile := _interaction_visual_profile(str(interaction.get("option_kind", "")))
	var phase_durations: Array = _phase_durations_or_default(visual_profile.get("phase_durations", INTERACTION_PHASE_DURATIONS), INTERACTION_PHASE_DURATIONS)
	var marker := MeshInstance3D.new()
	marker.name = "WorldActionInteractionPulse"
	var mesh := CylinderMesh.new()
	mesh.top_radius = float(visual_profile.get("top_radius", 0.34))
	mesh.bottom_radius = float(visual_profile.get("bottom_radius", 0.34))
	mesh.height = float(visual_profile.get("height", 0.055))
	mesh.radial_segments = int(visual_profile.get("radial_segments", 24))
	marker.mesh = mesh
	marker.material_override = _interaction_material(str(interaction.get("option_kind", "")))
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
	_presentation_layer(world_root).add_child(marker)
	var tween := host.create_tween()
	_track_active_tween(tween)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(marker, "scale", _vector3_or_default(visual_profile.get("start_scale", Vector3(0.82, 1.0, 0.82)), Vector3(0.82, 1.0, 0.82)), float(phase_durations[0]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), INTERACTION_PHASES[1]))
	tween.tween_property(marker, "scale", _vector3_or_default(visual_profile.get("pulse_scale", Vector3(1.35, 1.0, 1.35)), Vector3(1.35, 1.0, 1.35)), float(phase_durations[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), INTERACTION_PHASES[2]))
	tween.tween_property(marker, "scale", _vector3_or_default(visual_profile.get("fade_scale", Vector3(0.55, 1.0, 0.55)), Vector3(0.55, 1.0, 0.55)), float(phase_durations[2]))
	tween.finished.connect(Callable(self, "_on_interaction_feedback_finished").bind(weakref(marker)))
	var snapshot_data := _interaction_public_snapshot(interaction, true, "")
	snapshot_data["marker_path"] = str(marker.get_path())
	_record_latest(snapshot_data)


func _on_interaction_feedback_finished(marker_ref: WeakRef) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker != null and not marker.is_queued_for_deletion():
		marker.set_meta("action_presenter_active", false)
		marker.queue_free()
	_prune_active_refs()
	latest["active"] = active_count > 0
	latest["active_count"] = active_count


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
	}


func _combat_event_presentation(events: Array, world_root: Node, world_result: Dictionary) -> Dictionary:
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


func _start_combat_event_feedback(host: Node, world_root: Node, combat_event: Dictionary) -> void:
	var target_node: Node3D = combat_event.get("target_node", null)
	var target_grid: Dictionary = _dictionary_or_empty(combat_event.get("target_grid", {}))
	if target_node == null and target_grid.is_empty():
		_record_latest(_combat_event_public_snapshot(combat_event, false, "target_missing"))
		return
	sequence += 1
	var marker := MeshInstance3D.new()
	marker.name = "WorldActionCombatEvent"
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	mesh.radial_segments = 10
	mesh.rings = 5
	marker.mesh = mesh
	marker.material_override = _combat_event_material(str(combat_event.get("event_kind", "")))
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
	_presentation_layer(world_root).add_child(marker)
	var tween := host.create_tween()
	_track_active_tween(tween)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(marker, "scale", Vector3(0.82, 0.82, 0.82), float(COMBAT_EVENT_PHASE_DURATIONS[0]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), COMBAT_EVENT_PHASES[1]))
	tween.tween_property(marker, "scale", Vector3(1.55, 1.55, 1.55), float(COMBAT_EVENT_PHASE_DURATIONS[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), COMBAT_EVENT_PHASES[2]))
	tween.tween_property(marker, "scale", Vector3(0.42, 0.42, 0.42), float(COMBAT_EVENT_PHASE_DURATIONS[2]))
	tween.finished.connect(Callable(self, "_on_combat_event_feedback_finished").bind(weakref(marker)))
	var snapshot_data := _combat_event_public_snapshot(combat_event, true, "")
	snapshot_data["marker_path"] = str(marker.get_path())
	_record_latest(snapshot_data)


func _on_combat_event_feedback_finished(marker_ref: WeakRef) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker != null and not marker.is_queued_for_deletion():
		marker.set_meta("action_presenter_active", false)
		marker.queue_free()
	_prune_active_refs()
	latest["active"] = active_count > 0
	latest["active_count"] = active_count


func _combat_event_public_snapshot(combat_event: Dictionary, active: bool, reason: String) -> Dictionary:
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


func _attack_delivery_material(delivery: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	if delivery == "ranged":
		material.albedo_color = Color(1.0, 0.88, 0.32, 0.88)
	else:
		material.albedo_color = Color(1.0, 0.44, 0.18, 0.82)
	return material


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
	}
	match option_kind:
		"pickup":
			profile["color"] = Color(0.22, 0.74, 1.0, 0.82)
			profile["pulse_scale"] = Vector3(1.42, 1.0, 1.42)
		"open_container":
			profile["color"] = Color(0.34, 0.92, 0.42, 0.82)
			profile["height"] = 0.08
			profile["y_offset"] = 0.36
			profile["pulse_scale"] = Vector3(1.24, 1.18, 1.24)
		"door_toggle":
			profile["color"] = Color(0.98, 0.66, 0.22, 0.86)
			profile["top_radius"] = 0.24
			profile["bottom_radius"] = 0.42
			profile["height"] = 0.11
			profile["y_offset"] = 0.42
			profile["pulse_scale"] = Vector3(1.18, 1.34, 1.18)
		"talk":
			profile["color"] = Color(0.72, 0.54, 1.0, 0.84)
			profile["y_offset"] = 0.92
			profile["pulse_scale"] = Vector3(1.15, 1.26, 1.15)
		"open_trade":
			profile["color"] = Color(0.26, 0.86, 0.76, 0.84)
			profile["y_offset"] = 0.86
			profile["pulse_scale"] = Vector3(1.22, 1.16, 1.22)
		"open_crafting":
			profile["color"] = Color(0.96, 0.78, 0.26, 0.84)
			profile["height"] = 0.075
			profile["pulse_scale"] = Vector3(1.18, 1.28, 1.18)
		"enter_subscene", "scene_transition":
			profile["color"] = Color(0.42, 0.8, 1.0, 0.86)
			profile["top_radius"] = 0.22
			profile["bottom_radius"] = 0.48
			profile["height"] = 0.14
			profile["y_offset"] = 0.3
			profile["phase_durations"] = [0.05, 0.12, 0.14]
			profile["pulse_scale"] = Vector3(1.52, 1.0, 1.52)
		"wait":
			profile["color"] = Color(0.7, 0.76, 0.86, 0.78)
			profile["top_radius"] = 0.26
			profile["bottom_radius"] = 0.26
			profile["height"] = 0.045
			profile["y_offset"] = 0.74
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
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var profile := _interaction_visual_profile(option_kind)
	var color: Variant = profile.get("color", Color(0.9, 0.86, 0.34, 0.8))
	material.albedo_color = color if typeof(color) == TYPE_COLOR else Color(0.9, 0.86, 0.34, 0.8)
	return material


func _combat_event_material(event_kind: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match event_kind:
		"corpse_created":
			material.albedo_color = Color(0.82, 0.18, 0.14, 0.88)
		"actor_defeated":
			material.albedo_color = Color(0.96, 0.1, 0.1, 0.9)
		"combat_started":
			material.albedo_color = Color(1.0, 0.45, 0.16, 0.86)
		"combat_ended":
			material.albedo_color = Color(0.2, 0.86, 0.58, 0.84)
		_:
			material.albedo_color = Color(0.9, 0.86, 0.34, 0.82)
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


func _set_marker_phase(marker_ref: WeakRef, phase: String) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker == null or marker.is_queued_for_deletion():
		return
	marker.set_meta("action_presenter_current_phase", phase)
	if str(latest.get("marker_path", "")) == str(marker.get_path()):
		latest["current_phase"] = phase


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
	if node == null:
		return
	_prune_active_refs()
	active_refs.append(weakref(node))
	active_count = active_refs.size()


func _track_active_tween(tween: Tween) -> void:
	if tween == null:
		return
	_prune_active_tweens()
	active_tweens.append(tween)


func _prune_active_refs() -> void:
	var retained: Array[WeakRef] = []
	for node_ref in active_refs:
		var node := node_ref.get_ref() as Node
		if node == null:
			continue
		if node.is_queued_for_deletion():
			continue
		if not bool(node.get_meta("action_presenter_active", false)):
			continue
		retained.append(node_ref)
	active_refs = retained
	active_count = active_refs.size()
	_prune_active_tweens()


func _prune_active_tweens() -> void:
	var retained: Array = []
	for tween_value in active_tweens:
		var tween := tween_value as Tween
		if tween != null and tween.is_valid() and tween.is_running():
			retained.append(tween)
	active_tweens = retained


func _record_latest(snapshot_data: Dictionary) -> Dictionary:
	_prune_active_refs()
	latest = snapshot_data.duplicate(true)
	latest["active_count"] = active_count
	latest["sequence"] = sequence
	return latest.duplicate(true)


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
