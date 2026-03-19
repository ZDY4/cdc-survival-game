extends Node

const HitReaction3D = preload("res://systems/hit_reaction_3d.gd")

signal presentation_started(job_id: String, action_result: Dictionary)
signal presentation_completed(job_id: String, action_result: Dictionary)

const MODE_COMBAT: String = "combat"
const MODE_NONCOMBAT: String = "noncombat"

const ACTION_TYPE_MOVE: String = "move"
const ACTION_TYPE_ATTACK: String = "attack"

const POLICY_FULL_BLOCKING: String = "FULL_BLOCKING"
const POLICY_FULL_NONBLOCKING: String = "FULL_NONBLOCKING"
const POLICY_MINIMAL_NONBLOCKING: String = "MINIMAL_NONBLOCKING"

@export var move_visual_duration: float = 0.25

var _job_counter: int = 0
var _pending_jobs: Dictionary = {}
var _completed_jobs: Dictionary = {}
var _active_visual_tweens: Dictionary = {}
var _job_actor_ids: Dictionary = {}
var _actor_job_ids: Dictionary = {}

func play(action_result: Dictionary) -> Dictionary:
	if action_result.is_empty():
		return {"started": false, "job_id": ""}

	var payload: Dictionary = action_result.duplicate()
	var job_id: String = "presentation_%d" % _job_counter
	_job_counter += 1
	payload["job_id"] = job_id
	_pending_jobs[job_id] = payload
	_completed_jobs.erase(job_id)
	_register_job_actor(job_id, payload)
	presentation_started.emit(job_id, payload)
	call_deferred("_run_job", job_id)
	return {
		"started": true,
		"job_id": job_id,
		"wait_for_presentation": bool(payload.get("wait_for_presentation", false))
	}

func wait_for_job(job_id: String) -> Dictionary:
	while _pending_jobs.has(job_id) and not _completed_jobs.has(job_id):
		await presentation_completed
	return _completed_jobs.get(job_id, {})

func is_job_pending(job_id: String) -> bool:
	return _pending_jobs.has(job_id)

func get_pending_job_ids_for_actor(actor: Node) -> Array[String]:
	var job_ids: Array[String] = []
	if actor == null or not is_instance_valid(actor):
		return job_ids
	var actor_id: int = actor.get_instance_id()
	var actor_jobs: Variant = _actor_job_ids.get(actor_id, [])
	if not (actor_jobs is Array):
		return job_ids
	for job_variant in actor_jobs:
		var job_id: String = str(job_variant)
		if _pending_jobs.has(job_id):
			job_ids.append(job_id)
	return job_ids

func cancel_jobs_for_actor(actor: Node, action_type_filter: String = "", snap_to_end: bool = true) -> Array[String]:
	var cancelled_job_ids: Array[String] = []
	if actor == null or not is_instance_valid(actor):
		return cancelled_job_ids
	var pending_job_ids: Array[String] = get_pending_job_ids_for_actor(actor)
	for job_id in pending_job_ids:
		var payload: Dictionary = _pending_jobs.get(job_id, {})
		if not action_type_filter.is_empty() and str(payload.get("action_type", "")) != action_type_filter:
			continue
		if _cancel_job(job_id, snap_to_end):
			cancelled_job_ids.append(job_id)
	return cancelled_job_ids

func cancel_jobs_by_mode(mode_filter: String, snap_to_end: bool = true) -> Array[String]:
	var cancelled_job_ids: Array[String] = []
	if mode_filter.is_empty():
		return cancelled_job_ids
	var pending_job_ids: Array[String] = []
	for job_variant in _pending_jobs.keys():
		pending_job_ids.append(str(job_variant))
	for job_id in pending_job_ids:
		var payload: Dictionary = _pending_jobs.get(job_id, {})
		if str(payload.get("mode", "")) != mode_filter:
			continue
		if _cancel_job(job_id, snap_to_end):
			cancelled_job_ids.append(job_id)
	return cancelled_job_ids

func _run_job(job_id: String) -> void:
	if not _pending_jobs.has(job_id):
		return
	var action_result: Dictionary = _pending_jobs[job_id]
	await _play_action_result(action_result)
	if not _pending_jobs.has(job_id):
		return
	_pending_jobs.erase(job_id)
	_completed_jobs[job_id] = action_result
	_unregister_job_actor(job_id)
	presentation_completed.emit(job_id, action_result)

func _play_action_result(action_result: Dictionary) -> void:
	var action_type: String = str(action_result.get("action_type", ""))
	match action_type:
		ACTION_TYPE_MOVE:
			await _play_move(action_result)
		ACTION_TYPE_ATTACK:
			await _play_attack(action_result)
		_:
			return

func _play_move(action_result: Dictionary) -> void:
	var actor: Node3D = action_result.get("actor", null) as Node3D
	if actor == null or not is_instance_valid(actor):
		return

	var policy: String = str(action_result.get("presentation_policy", POLICY_FULL_NONBLOCKING))
	if policy == POLICY_MINIMAL_NONBLOCKING:
		return

	var from_pos: Vector3 = action_result.get("from_pos", actor.global_position)
	var to_pos: Vector3 = action_result.get("to_pos", actor.global_position)
	if from_pos.is_equal_approx(to_pos):
		return

	var visual_root: Node3D = _resolve_visual_root(actor)
	if visual_root == null or not is_instance_valid(visual_root):
		return

	var actor_id: int = actor.get_instance_id()
	_reset_visual_offset(actor_id)
	visual_root.position = from_pos - to_pos

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(visual_root, "position", Vector3.ZERO, move_visual_duration)
	_active_visual_tweens[actor_id] = {
		"tween": tween,
		"root": visual_root
	}

	await tween.finished
	_reset_visual_offset(actor_id)

func _play_attack(action_result: Dictionary) -> void:
	var attacker: Node = action_result.get("actor", null) as Node
	var target: Node3D = action_result.get("target", null) as Node3D
	var wait_for_presentation: bool = bool(action_result.get("wait_for_presentation", false))
	var policy: String = str(action_result.get("presentation_policy", POLICY_FULL_NONBLOCKING))
	var target_pos: Vector3 = action_result.get("target_pos", Vector3.ZERO)
	if target != null and is_instance_valid(target):
		target_pos = target.global_position

	if attacker != null and is_instance_valid(attacker) and policy != POLICY_MINIMAL_NONBLOCKING and attacker.has_method("play_attack_lunge"):
		var attack_motion: Variant = attacker.call("play_attack_lunge", target_pos)
		if wait_for_presentation and attack_motion is Object and (attack_motion as Object).get_class() == "GDScriptFunctionState":
			await attack_motion

	if target != null and is_instance_valid(target):
		_play_hit_feedback(
			target,
			int(action_result.get("damage", 0)),
			bool(action_result.get("is_critical", false))
		)

func _resolve_visual_root(actor: Node3D) -> Node3D:
	if actor == null or not is_instance_valid(actor):
		return null
	if actor.has_method("get_visual_root"):
		var visual_root: Variant = actor.call("get_visual_root")
		if visual_root is Node3D and is_instance_valid(visual_root):
			return visual_root as Node3D
	return null

func _reset_visual_offset(actor_id: int) -> void:
	if not _active_visual_tweens.has(actor_id):
		return
	var tween_data: Dictionary = _active_visual_tweens[actor_id]
	var tween: Tween = tween_data.get("tween", null) as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	var visual_root: Node3D = tween_data.get("root", null) as Node3D
	if visual_root != null and is_instance_valid(visual_root):
		visual_root.position = Vector3.ZERO
	_active_visual_tweens.erase(actor_id)

func _resolve_world_damage_text_controller() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var player_actor := tree.get_first_node_in_group("player")
	if player_actor != null and player_actor.has_method("get_world_damage_text_controller"):
		var controller: Variant = player_actor.call("get_world_damage_text_controller")
		if controller is Node and is_instance_valid(controller):
			return controller as Node
	return null

func _play_hit_feedback(target: Node3D, damage: int, is_critical: bool) -> void:
	var hit_reaction: Variant = HitReaction3D.get_or_create(target)
	if hit_reaction != null:
		hit_reaction.play_hit_shake()

	var damage_text_controller: Node = _resolve_world_damage_text_controller()
	if damage_text_controller != null and damage_text_controller.has_method("show_damage_number"):
		damage_text_controller.show_damage_number(target, damage, is_critical)

func _cancel_job(job_id: String, snap_to_end: bool) -> bool:
	if not _pending_jobs.has(job_id):
		return false
	var action_result: Dictionary = _pending_jobs[job_id]
	action_result["cancelled"] = true
	_pending_jobs.erase(job_id)
	_completed_jobs[job_id] = action_result
	_settle_job_visual_state(action_result, snap_to_end)
	_unregister_job_actor(job_id)
	presentation_completed.emit(job_id, action_result)
	return true

func _settle_job_visual_state(action_result: Dictionary, snap_to_end: bool) -> void:
	var action_type: String = str(action_result.get("action_type", ""))
	match action_type:
		ACTION_TYPE_MOVE:
			var actor: Node3D = action_result.get("actor", null) as Node3D
			if actor == null or not is_instance_valid(actor):
				return
			if snap_to_end:
				var visual_root: Node3D = _resolve_visual_root(actor)
				if visual_root != null and is_instance_valid(visual_root):
					visual_root.position = Vector3.ZERO
			_reset_visual_offset(actor.get_instance_id())
		ACTION_TYPE_ATTACK:
			var attacker: Node3D = action_result.get("actor", null) as Node3D
			if attacker == null or not is_instance_valid(attacker):
				return
			var attacker_visual_root: Node3D = _resolve_visual_root(attacker)
			if attacker_visual_root != null and is_instance_valid(attacker_visual_root):
				attacker_visual_root.position = Vector3.ZERO
		_:
			return

func _register_job_actor(job_id: String, action_result: Dictionary) -> void:
	var actor: Node = action_result.get("actor", null) as Node
	if actor == null or not is_instance_valid(actor):
		return
	var actor_id: int = actor.get_instance_id()
	_job_actor_ids[job_id] = actor_id
	var actor_jobs: Array = _actor_job_ids.get(actor_id, [])
	actor_jobs.append(job_id)
	_actor_job_ids[actor_id] = actor_jobs

func _unregister_job_actor(job_id: String) -> void:
	if not _job_actor_ids.has(job_id):
		return
	var actor_id: int = int(_job_actor_ids.get(job_id, 0))
	_job_actor_ids.erase(job_id)
	var actor_jobs: Variant = _actor_job_ids.get(actor_id, [])
	if not (actor_jobs is Array):
		return
	var remaining_jobs: Array[String] = []
	for job_variant in actor_jobs:
		var existing_job_id: String = str(job_variant)
		if existing_job_id == job_id:
			continue
		remaining_jobs.append(existing_job_id)
	if remaining_jobs.is_empty():
		_actor_job_ids.erase(actor_id)
		return
	_actor_job_ids[actor_id] = remaining_jobs
