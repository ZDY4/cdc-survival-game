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
var _role_kind: String = ""
var _character_id: String = ""
var _allow_attack: bool = false

var _state: int = AIState.IDLE
var _last_decision_time: float = -999.0
var _last_attack_time: float = -999.0
var _target: Node3D = null

func _ready() -> void:
	set_process(true)

func initialize(
		owner_node: Node3D,
		movement_component: Node,
		spawn_pos: Vector3,
		role_kind: String,
		character_id: String,
		ai_config: Dictionary
	) -> void:
	_owner_node = owner_node
	_movement_component = movement_component
	_spawn_pos = spawn_pos
	_role_kind = role_kind
	_character_id = character_id
	_allow_attack = role_kind.to_lower() == "enemy"

	_apply_config(ai_config)

func _process(_delta: float) -> void:
	if not _owner_node or not _movement_component:
		return

	if CombatSystem and CombatSystem.has_method("is_in_combat") and CombatSystem.is_in_combat():
		return

	var now_s: float = float(Time.get_ticks_msec()) / 1000.0
	if now_s - _last_decision_time < decision_interval:
		return
	_last_decision_time = now_s

	_refresh_target()

	_state = _decide_state()
	_execute_state(now_s)

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
