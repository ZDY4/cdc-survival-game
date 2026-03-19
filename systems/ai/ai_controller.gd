class_name AIController
extends Node

const TargetAttackAbility = preload("res://systems/target_attack_ability.gd")

enum AIState { IDLE, WANDER, CHASE, ATTACK, RETURN }

@export var decision_interval: float = 0.8
@export var aggro_range: float = 6.0
@export var attack_range: float = 1.3
@export var wander_radius: float = 3.0
@export var leash_distance: float = 8.0
@export var attack_cooldown: float = 1.5

var _owner_node: Node3D = null
var _movement_component: Node = null
var _spawn_pos: Vector3 = Vector3.ZERO
var _character_id: String = ""
var _allow_attack: bool = false
var _skill_runtime: Node = null

var _state: int = AIState.IDLE
var _last_decision_time: float = -999.0
var _last_attack_time: float = -999.0
var _target: Node3D = null

func _ready() -> void:
	set_process(false)

func initialize(
		owner_node: Node3D,
		movement_component: Node,
		spawn_pos: Vector3,
		character_id: String,
		ai_config: Dictionary,
		skill_runtime: Node = null
	) -> void:
	_owner_node = owner_node
	_movement_component = movement_component
	_spawn_pos = spawn_pos
	_character_id = character_id
	_allow_attack = bool(ai_config.get("allow_attack", false))
	_skill_runtime = skill_runtime

	_apply_config(ai_config)

func refresh_runtime_config(ai_config: Dictionary) -> void:
	_apply_config(ai_config)
	if not _allow_attack and _movement_component and _movement_component.has_method("cancel"):
		_movement_component.cancel()

func _apply_config(config: Dictionary) -> void:
	if config.has("decision_interval"):
		decision_interval = float(config.decision_interval)
	if config.has("aggro_range"):
		aggro_range = float(config.aggro_range)
	if config.has("attack_range"):
		attack_range = float(config.attack_range)
	if config.has("wander_radius"):
		wander_radius = float(config.wander_radius)
	if config.has("leash_distance"):
		leash_distance = float(config.leash_distance)
	if config.has("attack_cooldown"):
		attack_cooldown = float(config.attack_cooldown)
	if config.has("allow_attack"):
		_allow_attack = bool(config.allow_attack)

func _refresh_target() -> void:
	if _target and is_instance_valid(_target):
		return
	_target = null
	var candidate := get_tree().get_first_node_in_group("player")
	if candidate and candidate is Node3D:
		_target = candidate

func _decide_state() -> int:
	var dist_from_spawn: float = _owner_node.global_position.distance_to(_spawn_pos)
	if _allow_attack and _target and is_instance_valid(_target):
		var dist_to_player: float = _owner_node.global_position.distance_to(_target.global_position)
		if dist_to_player <= attack_range:
			return AIState.ATTACK
		if dist_to_player <= aggro_range:
			return AIState.CHASE

	if leash_distance > 0.0 and dist_from_spawn > leash_distance:
		return AIState.RETURN
	if wander_radius > 0.0:
		return AIState.WANDER
	return AIState.IDLE

func _execute_state(now_s: float) -> void:
	match _state:
		AIState.ATTACK:
			_try_attack(now_s)
		AIState.CHASE:
			if _target and is_instance_valid(_target):
				_move_to(_target.global_position)
		AIState.RETURN:
			_move_to(_spawn_pos)
		AIState.WANDER:
			_wander()
		AIState.IDLE:
			pass

func _move_to(world_pos: Vector3) -> void:
	if not _movement_component:
		return

	var target_pos := world_pos
	if _owner_node:
		target_pos.y = _owner_node.global_position.y
	if GridMovementSystem and GridMovementSystem.has_method("snap_to_grid"):
		target_pos = GridMovementSystem.snap_to_grid(target_pos)

	if _movement_component.has_method("move_to"):
		_movement_component.move_to(target_pos)

func execute_turn_step() -> Dictionary:
	if not _owner_node or not is_instance_valid(_owner_node):
		return {"performed": false}
	if _movement_component == null:
		return {"performed": false}

	var now_s: float = float(Time.get_ticks_msec()) / 1000.0
	if now_s - _last_decision_time < decision_interval:
		return {"performed": false}
	_last_decision_time = now_s

	_refresh_target()
	_state = _decide_state()

	match _state:
		AIState.ATTACK:
			return _perform_attack_step(now_s)
		AIState.CHASE:
			if _target and is_instance_valid(_target):
				return await _perform_move_step(_target.global_position)
		AIState.RETURN:
			return await _perform_move_step(_spawn_pos)
		AIState.WANDER:
			return await _perform_wander_step()
		_:
			return {"performed": false}
	return {"performed": false}

func _wander() -> void:
	if wander_radius <= 0.0:
		return
	if _movement_component and _movement_component.has_method("is_moving"):
		if _movement_component.is_moving():
			return

	var offset := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.0, wander_radius)
	var target := _spawn_pos + Vector3(offset.x, 0.0, offset.y)
	_move_to(target)

func _try_attack(now_s: float) -> void:
	if not _allow_attack:
		return
	if now_s - _last_attack_time < attack_cooldown:
		return
	if CombatSystem and CombatSystem.has_method("start_combat"):
		CombatSystem.start_combat(_character_id)
		_last_attack_time = now_s

func _perform_attack_step(now_s: float) -> Dictionary:
	if not _allow_attack:
		return {"performed": false}
	if _target == null or not is_instance_valid(_target):
		return {"performed": false}
	if _skill_runtime != null and _skill_runtime.has_method("try_activate_next_active_skill"):
		var preferred_cell := GridMovementSystem.world_to_grid(_target.global_position)
		var skill_result: Variant = _skill_runtime.call("try_activate_next_active_skill", preferred_cell, _target)
		if skill_result is Dictionary and bool((skill_result as Dictionary).get("success", false)):
			return {"performed": true, "type": "skill", "result": (skill_result as Dictionary).duplicate(true)}
	if now_s - _last_attack_time < attack_cooldown:
		return {"performed": false}
	if CombatSystem == null or not CombatSystem.has_method("begin_targeted_attack"):
		return {"performed": false}

	var preferred_attack_cell := GridMovementSystem.world_to_grid(_target.global_position)
	var session_result: Variant = CombatSystem.begin_targeted_attack(_owner_node, {
		"ai": true,
		"preferred_cell": preferred_attack_cell,
		"target_actor": _target,
		"attack_range_cells": maxi(1, int(ceil(attack_range)))
	})
	if not (session_result is Dictionary):
		return {"performed": false}
	var session_payload: Dictionary = session_result as Dictionary
	if not bool(session_payload.get("success", false)):
		return {"performed": false, "result": session_payload}
	var attack_session: Dictionary = session_payload.get("session", {})
	var attack_handler: TargetAttackAbility = attack_session.get("handler", null) as TargetAttackAbility
	if attack_handler == null:
		return {"performed": false}
	var attack_preview_result: Dictionary = attack_handler.auto_select_for_ai(_owner_node, preferred_attack_cell, attack_session.get("context", {}))
	if not bool(attack_preview_result.get("success", false)):
		return {"performed": false, "result": attack_preview_result}

	var attack_result: Variant = attack_handler.confirm_target(
		attack_preview_result.get("preview", {}),
		attack_session.get("context", {})
	)
	if attack_result is Dictionary and bool((attack_result as Dictionary).get("success", false)):
		var attack_payload: Dictionary = attack_result as Dictionary
		var presentation_data: Dictionary = attack_payload.get("presentation", {}) as Dictionary
		var presentation_job_id: String = str(attack_payload.get("presentation_job_id", ""))
		if bool(presentation_data.get("wait_for_presentation", false)) \
		and not presentation_job_id.is_empty() \
		and ActionPresentationSystem != null \
		and ActionPresentationSystem.has_method("wait_for_job"):
			await ActionPresentationSystem.wait_for_job(presentation_job_id)
		_last_attack_time = now_s
		return {"performed": true, "type": "attack"}
	return {"performed": false}

func _perform_wander_step() -> Dictionary:
	if wander_radius <= 0.0:
		return {"performed": false}
	var offset := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.0, wander_radius)
	var target := _spawn_pos + Vector3(offset.x, 0.0, offset.y)
	return await _perform_move_step(target)

func _perform_move_step(world_pos: Vector3) -> Dictionary:
	if _movement_component == null or not _movement_component.has_method("find_path") or TurnSystem == null:
		return {"performed": false}

	var target_pos := world_pos
	if _owner_node:
		target_pos.y = _owner_node.global_position.y
	if GridMovementSystem and GridMovementSystem.has_method("snap_to_grid"):
		target_pos = GridMovementSystem.snap_to_grid(target_pos)

	var full_path: Variant = _movement_component.call("find_path", target_pos)
	if not (full_path is Array) or (full_path as Array).is_empty():
		return {"performed": false}

	var start_result: Dictionary = TurnSystem.request_action(_owner_node, TurnSystem.ACTION_TYPE_MOVE, {
		"phase": TurnSystem.ACTION_PHASE_START,
		"target_pos": target_pos
	})
	if not bool(start_result.get("success", false)):
		return {"performed": false, "result": start_result}

	var available_steps: int = int(TurnSystem.get_actor_available_steps(_owner_node))
	if available_steps <= 0:
		TurnSystem.request_action(_owner_node, TurnSystem.ACTION_TYPE_MOVE, {
			"phase": TurnSystem.ACTION_PHASE_COMPLETE,
			"success": false
		})
		return {"performed": false}

	var path: Array[Vector3] = []
	for point_variant in full_path:
		if point_variant is Vector3:
			path.append(point_variant)
		if path.size() >= available_steps:
			break
	if path.is_empty():
		TurnSystem.request_action(_owner_node, TurnSystem.ACTION_TYPE_MOVE, {
			"phase": TurnSystem.ACTION_PHASE_COMPLETE,
			"success": false
		})
		return {"performed": false}

	var from_pos: Vector3 = _owner_node.global_position
	var final_pos: Vector3 = path[path.size() - 1]
	_owner_node.global_position = final_pos
	var step_result: Dictionary = TurnSystem.request_action(_owner_node, TurnSystem.ACTION_TYPE_MOVE, {
		"phase": TurnSystem.ACTION_PHASE_STEP,
		"steps": path.size()
	})
	if not bool(step_result.get("success", false)):
		_owner_node.global_position = from_pos
		TurnSystem.request_action(_owner_node, TurnSystem.ACTION_TYPE_MOVE, {
			"phase": TurnSystem.ACTION_PHASE_COMPLETE,
			"success": false
		})
		return {"performed": false, "result": step_result}

	var action_result: Dictionary = _build_move_action_result(from_pos, final_pos, path)
	await _play_action_presentation(action_result)
	TurnSystem.request_action(_owner_node, TurnSystem.ACTION_TYPE_MOVE, {
		"phase": TurnSystem.ACTION_PHASE_COMPLETE,
		"success": true
	})
	return {
		"performed": true,
		"type": "move",
		"result": action_result
	}

func _build_move_action_result(from_pos: Vector3, to_pos: Vector3, path: Array[Vector3]) -> Dictionary:
	var in_combat: bool = bool(TurnSystem != null and TurnSystem.is_in_combat())
	return {
		"actor": _owner_node,
		"action_type": "move",
		"mode": "combat" if in_combat else "noncombat",
		"wait_for_presentation": in_combat,
		"presentation_policy": "FULL_BLOCKING" if in_combat else "FULL_NONBLOCKING",
		"from_pos": from_pos,
		"to_pos": to_pos,
		"path": path.duplicate()
	}

func _play_action_presentation(action_result: Dictionary) -> void:
	if ActionPresentationSystem == null or not ActionPresentationSystem.has_method("play"):
		return
	var handle: Variant = ActionPresentationSystem.play(action_result)
	if not (handle is Dictionary):
		return
	if not bool((handle as Dictionary).get("started", false)):
		return
	if not bool(action_result.get("wait_for_presentation", false)):
		return
	var job_id: String = str((handle as Dictionary).get("job_id", ""))
	if job_id.is_empty() or not ActionPresentationSystem.has_method("wait_for_job"):
		return
	await ActionPresentationSystem.wait_for_job(job_id)
