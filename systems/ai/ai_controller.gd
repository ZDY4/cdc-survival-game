class_name AIController
extends Node

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
		ai_config: Dictionary
	) -> void:
	_owner_node = owner_node
	_movement_component = movement_component
	_spawn_pos = spawn_pos
	_character_id = character_id
	_allow_attack = bool(ai_config.get("allow_attack", false))

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
	if now_s - _last_attack_time < attack_cooldown:
		return {"performed": false}
	if CombatSystem == null or not CombatSystem.has_method("perform_attack"):
		return {"performed": false}

	var attack_result: Variant = CombatSystem.perform_attack(_owner_node, _target)
	if attack_result is Dictionary and bool((attack_result as Dictionary).get("success", false)):
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

	if not bool(_movement_component.call("move_along_world_path", path)):
		TurnSystem.request_action(_owner_node, TurnSystem.ACTION_TYPE_MOVE, {
			"phase": TurnSystem.ACTION_PHASE_COMPLETE,
			"success": false
		})
		return {"performed": false}

	await _movement_component.movement_step_completed
	TurnSystem.request_action(_owner_node, TurnSystem.ACTION_TYPE_MOVE, {
		"phase": TurnSystem.ACTION_PHASE_STEP,
		"steps": 1
	})
	await _movement_component.move_finished
	TurnSystem.request_action(_owner_node, TurnSystem.ACTION_TYPE_MOVE, {
		"phase": TurnSystem.ACTION_PHASE_COMPLETE,
		"success": true
	})
	return {"performed": true, "type": "move"}
