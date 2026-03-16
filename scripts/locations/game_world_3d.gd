class_name GameWorld3D
extends Node3D

const CameraController3D = preload("res://systems/camera_controller_3d.gd")
const PlayerController = preload("res://systems/player_controller.gd")
const GridDebugController = preload("res://systems/grid_debug_controller.gd")
const GridVisualizer = preload("res://systems/grid_visualizer.gd")
const AISpawnSystem = preload("res://systems/spawn/ai_spawn_system.gd")

@export var player_scene: PackedScene = null
@export var grid_debug_default_visible: bool = false
@export var max_preview_path_points: int = 200
@export var max_preview_distance: float = 40.0
@export var interaction_preview_min_radius: int = 1
@export var interaction_preview_max_radius: int = 4

@onready var _camera_controller: CameraController3D = $CameraController3D
@onready var _grid_floor: StaticBody3D = $GridFloor

var _player: PlayerController = null
var _grid_visualizer: GridVisualizer = null
var _grid_debug_controller: GridDebugController = null
var _spawn_system: AISpawnSystem = null

func _ready() -> void:
	_setup_world()
	_spawn_player()
	_setup_camera()
	_setup_runtime_systems()

func _exit_tree() -> void:
	if _grid_debug_controller:
		_grid_debug_controller.cleanup()

func _setup_world() -> void:
	_grid_visualizer = GridVisualizer.new()
	add_child(_grid_visualizer)

	_grid_debug_controller = GridDebugController.new()
	add_child(_grid_debug_controller)
	_grid_debug_controller.initialize(_grid_visualizer, _grid_floor, grid_debug_default_visible)

func _spawn_player() -> void:
	if player_scene:
		_player = player_scene.instantiate()
	else:
		_player = PlayerController.new()

	add_child(_player)
	_player.global_position = _resolve_player_spawn_position(_player.global_position)
	_player.set_grid_world(GridMovementSystem.grid_world)
	GameState.player_position_3d = _player.global_position

func _setup_camera() -> void:
	if not _camera_controller:
		push_error("GameWorld3D: CameraController3D node not found")
		return
	_camera_controller.target = _player

func _setup_runtime_systems() -> void:
	_spawn_system = AISpawnSystem.new()
	add_child(_spawn_system)
	_spawn_system.initialize(self)
	_spawn_system.spawn_auto_points()

	if _player:
		_player.set_interaction_context(self)
		_player.configure_path_preview_settings(
			max_preview_path_points,
			max_preview_distance,
			interaction_preview_min_radius,
			interaction_preview_max_radius
		)

func get_player() -> PlayerController:
	return _player

func get_camera() -> CameraController3D:
	return _camera_controller

func _resolve_player_spawn_position(fallback_world_pos: Vector3) -> Vector3:
	var spawn_world_pos: Vector3 = fallback_world_pos
	var player_spawn_node := get_node_or_null("PlayerSpawn")
	if player_spawn_node:
		if player_spawn_node.has_method("get_spawn_position"):
			spawn_world_pos = player_spawn_node.get_spawn_position()
		elif player_spawn_node is Node3D:
			spawn_world_pos = player_spawn_node.global_position

	if not GridMovementSystem or not GridMovementSystem.has_method("snap_to_grid"):
		return spawn_world_pos

	var snapped_world_pos: Vector3 = GridMovementSystem.snap_to_grid(spawn_world_pos)
	snapped_world_pos.y = spawn_world_pos.y
	return snapped_world_pos

