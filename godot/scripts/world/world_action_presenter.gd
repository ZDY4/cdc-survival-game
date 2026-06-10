extends RefCounted

const PresentationTracker = preload("res://scripts/world/presentation/presentation_tracker.gd")
const PresentationMaterials = preload("res://scripts/world/presentation/presentation_materials.gd")
const PresentationNodeFactory = preload("res://scripts/world/presentation/presentation_node_factory.gd")
const MovementActionPresenter = preload("res://scripts/world/presentation/movement_action_presenter.gd")

const GRID_SIZE := 1.0
const DEFAULT_ACTOR_Y := 0.58
const STEP_DURATION_SEC := 0.07
const ATTACK_PHASES := ["windup", "impact", "fade"]
const INTERACTION_PHASES := ["start", "pulse", "fade"]
const COMBAT_EVENT_PHASES := ["signal", "resolve", "fade"]
const RELOAD_PHASES := ["prepare", "load", "ready"]
const ATTACK_PHASE_DURATIONS := [0.06, 0.08, 0.10]
const INTERACTION_PHASE_DURATIONS := [0.06, 0.08, 0.10]
const COMBAT_EVENT_PHASE_DURATIONS := [0.05, 0.10, 0.12]
const RELOAD_PHASE_DURATIONS := [0.07, 0.12, 0.10]

var _tracker := PresentationTracker.new()
var _materials := PresentationMaterials.new()
var _node_factory := PresentationNodeFactory.new()
var _movement_presenter := MovementActionPresenter.new()


func _init() -> void:
	_movement_presenter.configure(_tracker, _materials, _node_factory)


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
	var attack := _attack_presentation(events, world_root, world_result)
	if not attack.is_empty():
		var combat_event := _combat_event_presentation(events, world_root, world_result)
		if attack.get("target_node", null) == null and not combat_event.is_empty():
			_start_combat_event_feedback(host, world_root, combat_event)
			return _tracker.latest_snapshot()
		_start_attack_feedback(host, world_root, attack)
		return _tracker.latest_snapshot()
	if not interaction.is_empty():
		_start_interaction_feedback(host, world_root, interaction)
		return _tracker.latest_snapshot()
	var reload := _reload_presentation(events, world_root, world_result)
	if not reload.is_empty():
		_start_reload_feedback(host, world_root, reload)
		return _tracker.latest_snapshot()
	var combat_event := _combat_event_presentation(events, world_root, world_result)
	if not combat_event.is_empty():
		_start_combat_event_feedback(host, world_root, combat_event)
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
		var attack_facing := _attack_facing_from_nodes(actor_node, target_node)
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
			"effective_defense": float(payload.get("effective_defense", payload.get("defense", 0.0))),
			"damage_reduction": float(payload.get("damage_reduction", 0.0)),
			"damage_bonus": float(payload.get("damage_bonus", 0.0)),
			"armor_pierce": float(payload.get("armor_pierce", 0.0)),
			"armor_pierced_defense": float(payload.get("armor_pierced_defense", 0.0)),
			"armor_break_chance": float(payload.get("armor_break_chance", 0.0)),
			"armor_break_roll": float(payload.get("armor_break_roll", 1.0)),
			"armor_break_triggered": bool(payload.get("armor_break_triggered", false)),
			"armor_break_defense_reduction": float(payload.get("armor_break_defense_reduction", 0.0)),
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
			"attack_facing": attack_facing,
			"attack_facing_direction": str(attack_facing.get("direction", "")),
			"attack_facing_yaw_degrees": float(attack_facing.get("yaw_degrees", actor_node.rotation_degrees.y if actor_node != null else 0.0)),
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
	var run_sequence := _tracker.next_sequence()
	var actor_node: Node3D = attack.get("actor_node", null)
	if actor_node != null:
		_apply_attack_facing(weakref(actor_node), _dictionary_or_empty(attack.get("attack_facing", {})))
		_track_active_node(actor_node)
	var marker := _node_factory.sphere_marker(
		"WorldActionAttackImpact",
		0.22,
		0.44,
		12,
		6,
		_attack_material(str(attack.get("hit_kind", "")), bool(attack.get("critical", false)), bool(attack.get("defeated", false)))
	)
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
	var muzzle_flash: MeshInstance3D = _attack_muzzle_flash_marker(attack, delivery_marker)
	if muzzle_flash != null:
		muzzle_flash.set_meta("action_presenter_sequence", run_sequence)
		_track_active_node(muzzle_flash)
	var projectile_trail: MeshInstance3D = _attack_projectile_trail_marker(attack, delivery_marker)
	if projectile_trail != null:
		projectile_trail.set_meta("action_presenter_sequence", run_sequence)
		_track_active_node(projectile_trail)
	var shell_eject: MeshInstance3D = _attack_shell_eject_marker(attack, delivery_marker)
	if shell_eject != null:
		shell_eject.set_meta("action_presenter_sequence", run_sequence)
		_track_active_node(shell_eject)
	var damage_label := _attack_damage_label(attack)
	damage_label.position = target_position + Vector3(0.0, 1.52, 0.0)
	damage_label.set_meta("action_presenter_sequence", run_sequence)
	_track_active_node(damage_label)
	var on_hit_label: Label3D = _attack_on_hit_effect_label(attack) as Label3D
	if on_hit_label != null:
		on_hit_label.position = target_position + Vector3(0.0, 1.88, 0.0)
		on_hit_label.set_meta("action_presenter_sequence", run_sequence)
		_track_active_node(on_hit_label)
	var on_hit_pulse: MeshInstance3D = _attack_on_hit_effect_pulse_marker(attack, target_position) as MeshInstance3D
	if on_hit_pulse != null:
		on_hit_pulse.set_meta("action_presenter_sequence", run_sequence)
		_track_active_node(on_hit_pulse)
	var layer := _presentation_layer(world_root)
	layer.add_child(marker)
	if delivery_marker != null:
		layer.add_child(delivery_marker)
	if projectile_trail != null:
		layer.add_child(projectile_trail)
	if muzzle_flash != null:
		layer.add_child(muzzle_flash)
	if shell_eject != null:
		layer.add_child(shell_eject)
	layer.add_child(damage_label)
	if on_hit_label != null:
		layer.add_child(on_hit_label)
	if on_hit_pulse != null:
		layer.add_child(on_hit_pulse)
	var tween := host.create_tween()
	_track_active_tween(tween)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(marker, "scale", Vector3(0.72, 0.72, 0.72), float(ATTACK_PHASE_DURATIONS[0]))
	if delivery_marker != null:
		tween.parallel().tween_property(delivery_marker, "scale", Vector3(1.0, 1.0, 1.0), float(ATTACK_PHASE_DURATIONS[0]))
	if projectile_trail != null:
		tween.parallel().tween_property(projectile_trail, "scale", Vector3(1.0, 1.0, 1.0), float(ATTACK_PHASE_DURATIONS[0]))
	if muzzle_flash != null:
		tween.parallel().tween_property(muzzle_flash, "scale", Vector3(1.32, 1.32, 1.32), float(ATTACK_PHASE_DURATIONS[0]))
	if shell_eject != null:
		tween.parallel().tween_property(shell_eject, "scale", Vector3(0.90, 0.90, 0.90), float(ATTACK_PHASE_DURATIONS[0]))
	tween.parallel().tween_property(damage_label, "position", damage_label.position + Vector3(0.0, 0.16, 0.0), float(ATTACK_PHASE_DURATIONS[0]))
	if on_hit_label != null:
		tween.parallel().tween_property(on_hit_label, "position", on_hit_label.position + Vector3(0.0, 0.12, 0.0), float(ATTACK_PHASE_DURATIONS[0]))
	if on_hit_pulse != null:
		tween.parallel().tween_property(on_hit_pulse, "scale", Vector3(0.74, 1.0, 0.74), float(ATTACK_PHASE_DURATIONS[0]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), ATTACK_PHASES[1]))
	if delivery_marker != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(delivery_marker), ATTACK_PHASES[1]))
	if projectile_trail != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(projectile_trail), ATTACK_PHASES[1]))
	if muzzle_flash != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(muzzle_flash), ATTACK_PHASES[1]))
	if shell_eject != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(shell_eject), ATTACK_PHASES[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(damage_label), ATTACK_PHASES[1]))
	if on_hit_label != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(on_hit_label), ATTACK_PHASES[1]))
	if on_hit_pulse != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(on_hit_pulse), ATTACK_PHASES[1]))
	tween.tween_property(marker, "scale", Vector3(1.45, 1.45, 1.45), float(ATTACK_PHASE_DURATIONS[1]))
	if delivery_marker != null:
		tween.parallel().tween_property(delivery_marker, "scale", Vector3(1.08, 1.08, 1.08), float(ATTACK_PHASE_DURATIONS[1]))
	if projectile_trail != null:
		tween.parallel().tween_property(projectile_trail, "scale", Vector3(1.04, 1.04, 1.04), float(ATTACK_PHASE_DURATIONS[1]))
	if muzzle_flash != null:
		tween.parallel().tween_property(muzzle_flash, "scale", Vector3(1.72, 1.72, 1.72), float(ATTACK_PHASE_DURATIONS[1]))
	if shell_eject != null:
		tween.parallel().tween_property(shell_eject, "position", _vector3_or_default(shell_eject.get_meta("end_position", Vector3.ZERO), shell_eject.position), float(ATTACK_PHASE_DURATIONS[1]))
		tween.parallel().tween_property(shell_eject, "scale", Vector3(1.08, 1.08, 1.08), float(ATTACK_PHASE_DURATIONS[1]))
	tween.parallel().tween_property(damage_label, "position", damage_label.position + Vector3(0.0, 0.36, 0.0), float(ATTACK_PHASE_DURATIONS[1]))
	if on_hit_label != null:
		tween.parallel().tween_property(on_hit_label, "position", on_hit_label.position + Vector3(0.0, 0.30, 0.0), float(ATTACK_PHASE_DURATIONS[1]))
	if on_hit_pulse != null:
		tween.parallel().tween_property(on_hit_pulse, "scale", Vector3(1.56, 1.0, 1.56), float(ATTACK_PHASE_DURATIONS[1]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(marker), ATTACK_PHASES[2]))
	if delivery_marker != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(delivery_marker), ATTACK_PHASES[2]))
	if projectile_trail != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(projectile_trail), ATTACK_PHASES[2]))
	if muzzle_flash != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(muzzle_flash), ATTACK_PHASES[2]))
	if shell_eject != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(shell_eject), ATTACK_PHASES[2]))
	tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(damage_label), ATTACK_PHASES[2]))
	if on_hit_label != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(on_hit_label), ATTACK_PHASES[2]))
	if on_hit_pulse != null:
		tween.tween_callback(Callable(self, "_set_marker_phase").bind(weakref(on_hit_pulse), ATTACK_PHASES[2]))
	tween.tween_property(marker, "scale", Vector3(0.35, 0.35, 0.35), float(ATTACK_PHASE_DURATIONS[2]))
	if delivery_marker != null:
		tween.parallel().tween_property(delivery_marker, "scale", Vector3(0.12, 0.12, 0.12), float(ATTACK_PHASE_DURATIONS[2]))
	if projectile_trail != null:
		tween.parallel().tween_property(projectile_trail, "scale", Vector3(0.16, 0.16, 0.16), float(ATTACK_PHASE_DURATIONS[2]))
	if muzzle_flash != null:
		tween.parallel().tween_property(muzzle_flash, "scale", Vector3(0.10, 0.10, 0.10), float(ATTACK_PHASE_DURATIONS[2]))
	if shell_eject != null:
		tween.parallel().tween_property(shell_eject, "scale", Vector3(0.16, 0.16, 0.16), float(ATTACK_PHASE_DURATIONS[2]))
	tween.parallel().tween_property(damage_label, "modulate", Color(damage_label.modulate.r, damage_label.modulate.g, damage_label.modulate.b, 0.0), float(ATTACK_PHASE_DURATIONS[2]))
	if on_hit_label != null:
		tween.parallel().tween_property(on_hit_label, "modulate", Color(on_hit_label.modulate.r, on_hit_label.modulate.g, on_hit_label.modulate.b, 0.0), float(ATTACK_PHASE_DURATIONS[2]))
	if on_hit_pulse != null:
		tween.parallel().tween_property(on_hit_pulse, "scale", Vector3(1.95, 1.0, 1.95), float(ATTACK_PHASE_DURATIONS[2]))
	var on_hit_label_ref: WeakRef = weakref(on_hit_label) if on_hit_label != null else null
	var on_hit_pulse_ref: WeakRef = weakref(on_hit_pulse) if on_hit_pulse != null else null
	var delivery_marker_ref: WeakRef = weakref(delivery_marker) if delivery_marker != null else null
	var muzzle_flash_ref: WeakRef = weakref(muzzle_flash) if muzzle_flash != null else null
	var projectile_trail_ref: WeakRef = weakref(projectile_trail) if projectile_trail != null else null
	var shell_eject_ref: WeakRef = weakref(shell_eject) if shell_eject != null else null
	tween.finished.connect(Callable(self, "_on_attack_feedback_finished").bind(weakref(marker), weakref(damage_label), on_hit_label_ref, delivery_marker_ref, muzzle_flash_ref, projectile_trail_ref, shell_eject_ref, on_hit_pulse_ref))
	var snapshot_data := _attack_public_snapshot(attack, true, "")
	snapshot_data["marker_path"] = str(marker.get_path())
	if delivery_marker != null:
		snapshot_data["delivery_marker_path"] = str(delivery_marker.get_path())
		snapshot_data["delivery_visual_kind"] = str(delivery_marker.get_meta("delivery_visual_kind", ""))
		snapshot_data["delivery_distance"] = float(delivery_marker.get_meta("delivery_distance", 0.0))
	if muzzle_flash != null:
		snapshot_data["muzzle_flash_path"] = str(muzzle_flash.get_path())
		snapshot_data["muzzle_flash_visual_kind"] = str(muzzle_flash.get_meta("muzzle_flash_visual_kind", ""))
	if projectile_trail != null:
		snapshot_data["projectile_trail_path"] = str(projectile_trail.get_path())
		snapshot_data["projectile_trail_visual_kind"] = str(projectile_trail.get_meta("projectile_trail_visual_kind", ""))
	if shell_eject != null:
		snapshot_data["shell_eject_path"] = str(shell_eject.get_path())
		snapshot_data["shell_eject_visual_kind"] = str(shell_eject.get_meta("shell_eject_visual_kind", ""))
	snapshot_data["damage_label_path"] = str(damage_label.get_path())
	snapshot_data["damage_label_text"] = str(damage_label.text)
	if on_hit_label != null:
		snapshot_data["on_hit_effect_label_path"] = str(on_hit_label.get_path())
		snapshot_data["on_hit_effect_label_text"] = str(on_hit_label.text)
	if on_hit_pulse != null:
		snapshot_data["on_hit_effect_pulse_path"] = str(on_hit_pulse.get_path())
		snapshot_data["on_hit_effect_pulse_visual_kind"] = str(on_hit_pulse.get_meta("visual_kind", ""))
		snapshot_data["on_hit_effect_pulse_effect_count"] = int(on_hit_pulse.get_meta("applied_effect_count", 0))
		snapshot_data["on_hit_effect_ids"] = _array_or_empty(on_hit_pulse.get_meta("effect_ids", [])).duplicate(true)
		snapshot_data["on_hit_effect_names"] = _array_or_empty(on_hit_pulse.get_meta("effect_names", [])).duplicate(true)
		snapshot_data["on_hit_effect_categories"] = _array_or_empty(on_hit_pulse.get_meta("effect_categories", [])).duplicate(true)
	_record_latest(snapshot_data)


func _on_attack_feedback_finished(marker_ref: WeakRef, damage_label_ref: WeakRef = null, on_hit_label_ref: WeakRef = null, delivery_marker_ref: WeakRef = null, muzzle_flash_ref: WeakRef = null, projectile_trail_ref: WeakRef = null, shell_eject_ref: WeakRef = null, on_hit_pulse_ref: WeakRef = null) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker != null and not marker.is_queued_for_deletion():
		marker.set_meta("action_presenter_active", false)
		marker.queue_free()
	if delivery_marker_ref != null:
		var delivery_marker := delivery_marker_ref.get_ref() as Node
		if delivery_marker != null and not delivery_marker.is_queued_for_deletion():
			delivery_marker.set_meta("action_presenter_active", false)
			delivery_marker.queue_free()
	if muzzle_flash_ref != null:
		var muzzle_flash := muzzle_flash_ref.get_ref() as Node
		if muzzle_flash != null and not muzzle_flash.is_queued_for_deletion():
			muzzle_flash.set_meta("action_presenter_active", false)
			muzzle_flash.queue_free()
	if projectile_trail_ref != null:
		var projectile_trail := projectile_trail_ref.get_ref() as Node
		if projectile_trail != null and not projectile_trail.is_queued_for_deletion():
			projectile_trail.set_meta("action_presenter_active", false)
			projectile_trail.queue_free()
	if shell_eject_ref != null:
		var shell_eject := shell_eject_ref.get_ref() as Node
		if shell_eject != null and not shell_eject.is_queued_for_deletion():
			shell_eject.set_meta("action_presenter_active", false)
			shell_eject.queue_free()
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
	if on_hit_pulse_ref != null:
		var on_hit_pulse := on_hit_pulse_ref.get_ref() as Node
		if on_hit_pulse != null and not on_hit_pulse.is_queued_for_deletion():
			on_hit_pulse.set_meta("action_presenter_active", false)
			on_hit_pulse.queue_free()
	_prune_active_refs()
	_tracker.refresh_latest_active()


func _attack_facing_from_nodes(actor_node: Node3D, target_node: Node3D) -> Dictionary:
	if actor_node == null or target_node == null:
		return {}
	var actor_position := actor_node.global_position if actor_node.is_inside_tree() else actor_node.position
	var target_position := target_node.global_position if target_node.is_inside_tree() else target_node.position
	var dx := target_position.x - actor_position.x
	var dz := target_position.z - actor_position.z
	if absf(dx) <= 0.001 and absf(dz) <= 0.001:
		return {}
	var direction := _movement_cardinal_direction(1 if dx > 0.0 else -1 if dx < 0.0 else 0, 1 if dz > 0.0 else -1 if dz < 0.0 else 0)
	return {
		"direction": direction,
		"yaw_degrees": _movement_direction_yaw_degrees(direction),
		"source": "attack",
		"from_position": actor_position,
		"to_position": target_position,
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


func _apply_attack_facing(actor_ref: WeakRef, facing: Dictionary) -> void:
	var actor_node := actor_ref.get_ref() as Node3D
	if actor_node == null or actor_node.is_queued_for_deletion() or facing.is_empty():
		return
	var yaw := float(facing.get("yaw_degrees", actor_node.rotation_degrees.y))
	actor_node.rotation_degrees = Vector3(actor_node.rotation_degrees.x, yaw, actor_node.rotation_degrees.z)
	actor_node.set_meta("action_presenter_final_rotation_degrees", actor_node.rotation_degrees)
	actor_node.set_meta("action_presenter_attack_facing", facing.duplicate(true))
	actor_node.set_meta("action_presenter_attack_facing_direction", str(facing.get("direction", "")))
	actor_node.set_meta("action_presenter_attack_facing_yaw_degrees", yaw)
	_tracker.set_latest_value("attack_facing_direction", str(facing.get("direction", "")))
	_tracker.set_latest_value("attack_facing_yaw_degrees", yaw)


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
		"effective_defense": float(attack.get("effective_defense", attack.get("defense", 0.0))),
		"damage_reduction": float(attack.get("damage_reduction", 0.0)),
		"damage_bonus": float(attack.get("damage_bonus", 0.0)),
		"armor_pierce": float(attack.get("armor_pierce", 0.0)),
		"armor_pierced_defense": float(attack.get("armor_pierced_defense", 0.0)),
		"armor_break_chance": float(attack.get("armor_break_chance", 0.0)),
		"armor_break_roll": float(attack.get("armor_break_roll", 1.0)),
		"armor_break_triggered": bool(attack.get("armor_break_triggered", false)),
		"armor_break_defense_reduction": float(attack.get("armor_break_defense_reduction", 0.0)),
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
		"attack_facing": _dictionary_or_empty(attack.get("attack_facing", {})).duplicate(true),
		"attack_facing_direction": str(attack.get("attack_facing_direction", "")),
		"attack_facing_yaw_degrees": float(attack.get("attack_facing_yaw_degrees", 0.0)),
		"phases": ATTACK_PHASES.duplicate(),
		"phase_count": ATTACK_PHASES.size(),
		"current_phase": ATTACK_PHASES[0] if active else "",
		"duration_sec": _duration_sum(ATTACK_PHASE_DURATIONS) if active else 0.0,
	}


func _attack_damage_label(attack: Dictionary) -> Label3D:
	var label := _node_factory.label3d(
		"WorldActionDamageText",
		_attack_feedback_text(attack),
		18,
		_attack_feedback_color(str(attack.get("hit_kind", "")), bool(attack.get("critical", false)), bool(attack.get("defeated", false)))
	)
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
	var top_radius := 0.07
	var bottom_radius := 0.18
	var height := 0.62
	if delivery == "ranged":
		top_radius = 0.045
		bottom_radius = 0.045
		height = max(0.35, distance)
	var marker := _node_factory.cylinder_marker(
		"WorldActionAttackDelivery",
		top_radius,
		bottom_radius,
		height,
		10,
		_attack_delivery_material(delivery)
	)
	if delivery == "ranged":
		marker.position = start.lerp(end, 0.5)
	else:
		marker.position = target_position + Vector3(0.0, 1.18, 0.0)
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


func _attack_muzzle_flash_marker(attack: Dictionary, delivery_marker: MeshInstance3D):
	if str(attack.get("attack_delivery", "")) != "ranged" or delivery_marker == null:
		return null
	var start: Variant = delivery_marker.get_meta("start_position", null)
	var end: Variant = delivery_marker.get_meta("end_position", null)
	if typeof(start) != TYPE_VECTOR3 or typeof(end) != TYPE_VECTOR3:
		return null
	var direction: Vector3 = (end as Vector3) - (start as Vector3)
	if direction.length() <= 0.01:
		direction = Vector3.FORWARD
	var marker := _node_factory.sphere_marker("WorldActionMuzzleFlash", 0.13, 0.26, 14, 6, _attack_muzzle_flash_material())
	marker.position = (start as Vector3) + direction.normalized() * 0.18
	marker.basis = _basis_from_y(direction.normalized())
	marker.scale = Vector3(0.24, 0.24, 0.24)
	marker.set_meta("action_presenter_active", true)
	marker.set_meta("action_presenter_kind", "attack_muzzle_flash")
	marker.set_meta("action_presenter_phases", ATTACK_PHASES.duplicate())
	marker.set_meta("action_presenter_phase_count", ATTACK_PHASES.size())
	marker.set_meta("action_presenter_current_phase", ATTACK_PHASES[0])
	marker.set_meta("action_presenter_duration_sec", _duration_sum(ATTACK_PHASE_DURATIONS))
	marker.set_meta("muzzle_flash_visual_kind", "muzzle_flash")
	marker.set_meta("start_position", start)
	marker.set_meta("end_position", end)
	marker.set_meta("direction", direction.normalized())
	marker.set_meta("actor_id", int(attack.get("actor_id", 0)))
	marker.set_meta("target_actor_id", int(attack.get("target_actor_id", 0)))
	_apply_attack_event_meta(marker, attack)
	return marker


func _attack_projectile_trail_marker(attack: Dictionary, delivery_marker: MeshInstance3D):
	if str(attack.get("attack_delivery", "")) != "ranged" or delivery_marker == null:
		return null
	var start: Variant = delivery_marker.get_meta("start_position", null)
	var end: Variant = delivery_marker.get_meta("end_position", null)
	if typeof(start) != TYPE_VECTOR3 or typeof(end) != TYPE_VECTOR3:
		return null
	var direction: Vector3 = (end as Vector3) - (start as Vector3)
	var distance := direction.length()
	if distance <= 0.01:
		direction = Vector3.FORWARD
		distance = 0.34
	var marker := _node_factory.cylinder_marker("WorldActionProjectileTrail", 0.025, 0.025, max(0.30, distance), 8, _attack_projectile_trail_material())
	marker.position = (start as Vector3).lerp(end as Vector3, 0.5)
	marker.basis = _basis_from_y(direction.normalized())
	marker.scale = Vector3(0.22, 0.22, 0.22)
	marker.set_meta("action_presenter_active", true)
	marker.set_meta("action_presenter_kind", "attack_projectile_trail")
	marker.set_meta("action_presenter_phases", ATTACK_PHASES.duplicate())
	marker.set_meta("action_presenter_phase_count", ATTACK_PHASES.size())
	marker.set_meta("action_presenter_current_phase", ATTACK_PHASES[0])
	marker.set_meta("action_presenter_duration_sec", _duration_sum(ATTACK_PHASE_DURATIONS))
	marker.set_meta("projectile_trail_visual_kind", "projectile_trail")
	marker.set_meta("trail_distance", distance)
	marker.set_meta("start_position", start)
	marker.set_meta("end_position", end)
	marker.set_meta("actor_id", int(attack.get("actor_id", 0)))
	marker.set_meta("target_actor_id", int(attack.get("target_actor_id", 0)))
	_apply_attack_event_meta(marker, attack)
	return marker


func _attack_shell_eject_marker(attack: Dictionary, delivery_marker: MeshInstance3D):
	if str(attack.get("attack_delivery", "")) != "ranged" or delivery_marker == null:
		return null
	var start: Variant = delivery_marker.get_meta("start_position", null)
	var end: Variant = delivery_marker.get_meta("end_position", null)
	if typeof(start) != TYPE_VECTOR3 or typeof(end) != TYPE_VECTOR3:
		return null
	var forward: Vector3 = (end as Vector3) - (start as Vector3)
	if forward.length() <= 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	if right.length() <= 0.01:
		right = Vector3.RIGHT
	var upward := Vector3.UP
	var eject_vector := (right * 0.34 + upward * 0.20 - forward * 0.08).normalized()
	var shell_start := (start as Vector3) + right * 0.16 + upward * 0.06
	var shell_end := shell_start + eject_vector * 0.56
	var marker := _node_factory.cylinder_marker("WorldActionShellEject", 0.026, 0.032, 0.16, 8, _attack_shell_eject_material())
	marker.position = shell_start
	marker.basis = _basis_from_y(eject_vector)
	marker.scale = Vector3(0.34, 0.34, 0.34)
	marker.set_meta("action_presenter_active", true)
	marker.set_meta("action_presenter_kind", "attack_shell_eject")
	marker.set_meta("action_presenter_phases", ATTACK_PHASES.duplicate())
	marker.set_meta("action_presenter_phase_count", ATTACK_PHASES.size())
	marker.set_meta("action_presenter_current_phase", ATTACK_PHASES[0])
	marker.set_meta("action_presenter_duration_sec", _duration_sum(ATTACK_PHASE_DURATIONS))
	marker.set_meta("shell_eject_visual_kind", "shell_eject")
	marker.set_meta("start_position", shell_start)
	marker.set_meta("end_position", shell_end)
	marker.set_meta("eject_vector", eject_vector)
	marker.set_meta("actor_id", int(attack.get("actor_id", 0)))
	marker.set_meta("target_actor_id", int(attack.get("target_actor_id", 0)))
	_apply_attack_event_meta(marker, attack)
	return marker


func _attack_on_hit_effect_label(attack: Dictionary):
	var effects: Array = _array_or_empty(attack.get("applied_on_hit_effects", []))
	if effects.is_empty():
		return null
	var label := _node_factory.label3d(
		"WorldActionOnHitEffect",
		_on_hit_effect_feedback_text(attack),
		14,
		_on_hit_effect_feedback_color(effects)
	)
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


func _attack_on_hit_effect_pulse_marker(attack: Dictionary, target_position: Vector3):
	var effects: Array = _array_or_empty(attack.get("applied_on_hit_effects", []))
	if effects.is_empty():
		return null
	var marker := _node_factory.cylinder_marker("WorldActionOnHitEffectPulse", 0.46, 0.46, 0.04, 32, _attack_on_hit_effect_pulse_material(effects))
	var mesh := marker.mesh as CylinderMesh
	marker.position = target_position + Vector3(0.0, 0.78, 0.0)
	marker.scale = Vector3(0.42, 1.0, 0.42)
	marker.set_meta("action_presenter_active", true)
	marker.set_meta("action_presenter_kind", "attack_on_hit_effect_pulse")
	marker.set_meta("action_presenter_phases", ATTACK_PHASES.duplicate())
	marker.set_meta("action_presenter_phase_count", ATTACK_PHASES.size())
	marker.set_meta("action_presenter_current_phase", ATTACK_PHASES[0])
	marker.set_meta("action_presenter_duration_sec", _duration_sum(ATTACK_PHASE_DURATIONS))
	marker.set_meta("visual_kind", "on_hit_effect_pulse")
	marker.set_meta("actor_id", int(attack.get("actor_id", 0)))
	marker.set_meta("target_actor_id", int(attack.get("target_actor_id", 0)))
	_apply_attack_event_meta(marker, attack)
	marker.set_meta("effect_ids", _on_hit_effect_ids(effects))
	marker.set_meta("effect_names", _on_hit_effect_names(effects))
	marker.set_meta("effect_categories", _on_hit_effect_categories(effects))
	marker.set_meta("applied_effect_count", effects.size())
	marker.set_meta("pulse_y_offset", 0.78)
	marker.set_meta("pulse_radius", mesh.top_radius)
	marker.set_meta("pulse_height", mesh.height)
	return marker


func _apply_attack_event_meta(node: Node, attack: Dictionary) -> void:
	node.set_meta("attack_delivery", str(attack.get("attack_delivery", "")))
	node.set_meta("range", int(attack.get("range", 0)))
	node.set_meta("weapon_item_id", str(attack.get("weapon_item_id", "")))
	node.set_meta("base_damage", float(attack.get("base_damage", 0.0)))
	node.set_meta("crit_multiplier", float(attack.get("crit_multiplier", 1.0)))
	node.set_meta("crit_roll", float(attack.get("crit_roll", 1.0)))
	node.set_meta("crit_chance", float(attack.get("crit_chance", 0.0)))
	node.set_meta("defense", float(attack.get("defense", 0.0)))
	node.set_meta("effective_defense", float(attack.get("effective_defense", attack.get("defense", 0.0))))
	node.set_meta("damage_reduction", float(attack.get("damage_reduction", 0.0)))
	node.set_meta("damage_bonus", float(attack.get("damage_bonus", 0.0)))
	node.set_meta("armor_pierce", float(attack.get("armor_pierce", 0.0)))
	node.set_meta("armor_pierced_defense", float(attack.get("armor_pierced_defense", 0.0)))
	node.set_meta("armor_break_chance", float(attack.get("armor_break_chance", 0.0)))
	node.set_meta("armor_break_roll", float(attack.get("armor_break_roll", 1.0)))
	node.set_meta("armor_break_triggered", bool(attack.get("armor_break_triggered", false)))
	node.set_meta("armor_break_defense_reduction", float(attack.get("armor_break_defense_reduction", 0.0)))
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
	node.set_meta("attack_facing", _dictionary_or_empty(attack.get("attack_facing", {})).duplicate(true))
	node.set_meta("attack_facing_direction", str(attack.get("attack_facing_direction", "")))
	node.set_meta("attack_facing_yaw_degrees", float(attack.get("attack_facing_yaw_degrees", 0.0)))


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
	return _materials.on_hit_effect_feedback_color(effects)


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


func _reload_presentation(events: Array, world_root: Node, world_result: Dictionary) -> Dictionary:
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


func _start_reload_feedback(host: Node, world_root: Node, reload: Dictionary) -> void:
	var actor_node: Node3D = reload.get("actor_node", null)
	var target_grid: Dictionary = _dictionary_or_empty(reload.get("target_grid", {}))
	if actor_node == null and target_grid.is_empty():
		_record_latest(_reload_public_snapshot(reload, false, "actor_missing"))
		return
	_tracker.next_sequence()
	var marker := _node_factory.cylinder_marker("WorldActionReloadPulse", 0.30, 0.30, 0.08, 20, _reload_material())
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
	var snapshot_data := _reload_public_snapshot(reload, true, "")
	snapshot_data["marker_path"] = str(marker.get_path())
	snapshot_data["label_path"] = str(label.get_path())
	snapshot_data["label_text"] = str(label.text)
	_record_latest(snapshot_data)


func _on_reload_feedback_finished(marker_ref: WeakRef, label_ref: WeakRef) -> void:
	var marker := marker_ref.get_ref() as Node
	if marker != null and not marker.is_queued_for_deletion():
		marker.set_meta("action_presenter_active", false)
		marker.queue_free()
	var label := label_ref.get_ref() as Node
	if label != null and not label.is_queued_for_deletion():
		label.set_meta("action_presenter_active", false)
		label.queue_free()
	_prune_active_refs()
	_tracker.refresh_latest_active()


func _reload_public_snapshot(reload: Dictionary, active: bool, reason: String) -> Dictionary:
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
	_tracker.next_sequence()
	var marker := _node_factory.sphere_marker(
		"WorldActionCombatEvent",
		0.18,
		0.36,
		10,
		5,
		_combat_event_material(str(combat_event.get("event_kind", "")))
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
	var snapshot_data := _combat_event_public_snapshot(combat_event, true, "")
	snapshot_data["marker_path"] = str(marker.get_path())
	snapshot_data["label_path"] = str(label.get_path())
	snapshot_data["label_text"] = str(label.text)
	_record_latest(snapshot_data)


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
	_prune_active_refs()
	_tracker.refresh_latest_active()


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
		"label_text": _combat_event_feedback_text(str(combat_event.get("event_kind", ""))),
		"label_y_offset": _combat_event_label_y_offset(str(combat_event.get("event_kind", ""))),
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
	return _materials.attack_material(hit_kind, critical, defeated)


func _attack_delivery_material(delivery: String) -> StandardMaterial3D:
	return _materials.attack_delivery_material(delivery)


func _attack_muzzle_flash_material() -> StandardMaterial3D:
	return _materials.attack_muzzle_flash_material()


func _attack_projectile_trail_material() -> StandardMaterial3D:
	return _materials.attack_projectile_trail_material()


func _attack_shell_eject_material() -> StandardMaterial3D:
	return _materials.attack_shell_eject_material()


func _attack_on_hit_effect_pulse_material(effects: Array) -> StandardMaterial3D:
	return _materials.attack_on_hit_effect_pulse_material(effects)


func _reload_material() -> StandardMaterial3D:
	return _materials.reload_material()


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


func _combat_event_material(event_kind: String) -> StandardMaterial3D:
	return _materials.combat_event_material(event_kind)


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
