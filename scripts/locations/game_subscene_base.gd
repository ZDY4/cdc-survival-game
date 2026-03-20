class_name GameSubsceneBase
extends Node3D

const CameraController3D = preload("res://systems/camera_controller_3d.gd")
const PlayerController = preload("res://systems/player_controller.gd")
const GridDebugController = preload("res://systems/grid_debug_controller.gd")
const GridVisualizer = preload("res://systems/grid_visualizer.gd")
const PlayerSpawnPoint = preload("res://systems/spawn/player_spawn_point.gd")

@export var location_id: String = ""
@export var scene_kind: String = "interior"
@export var player_scene: PackedScene = null

@onready var _camera_controller: CameraController3D = $CameraController3D
@onready var _grid_floor: StaticBody3D = $GridFloor

var _player: PlayerController = null
var _grid_visualizer: GridVisualizer = null
var _grid_debug_controller: GridDebugController = null

func _ready() -> void:
	_sync_subscene_state()
	_setup_world()
	_spawn_player()
	_setup_camera()

func _exit_tree() -> void:
	if _grid_debug_controller != null:
		_grid_debug_controller.cleanup()

func get_player() -> PlayerController:
	return _player

func _setup_world() -> void:
	_grid_visualizer = GridVisualizer.new()
	add_child(_grid_visualizer)

	_grid_debug_controller = GridDebugController.new()
	add_child(_grid_debug_controller)
	_grid_debug_controller.initialize(_grid_visualizer, _grid_floor, false)

func _spawn_player() -> void:
	if player_scene:
		_player = player_scene.instantiate()
	else:
		_player = PlayerController.new()

	add_child(_player)
	_player.global_position = _resolve_player_spawn_position(_player.global_position)
	_player.set_grid_world(GridMovementSystem.grid_world)
	_player.set_interaction_context(self)

func _setup_camera() -> void:
	if _camera_controller == null:
		push_error("GameSubsceneBase: CameraController3D node not found")
		return
	_camera_controller.target = _player

func _resolve_player_spawn_position(fallback_world_pos: Vector3) -> Vector3:
	var spawn_world_pos: Vector3 = fallback_world_pos
	var spawn_id := "default_spawn"
	if MapModule != null and location_id == GameState.current_subscene_location_id:
		spawn_id = MapModule.get_location_entry_spawn_id(location_id)

	var player_spawn_node := _find_spawn_point_by_id(spawn_id)
	if player_spawn_node != null:
		spawn_world_pos = player_spawn_node.get_spawn_position()

	if not GridMovementSystem or not GridMovementSystem.has_method("snap_to_grid"):
		return spawn_world_pos

	var snapped_world_pos: Vector3 = GridMovementSystem.snap_to_grid(spawn_world_pos)
	snapped_world_pos.y = spawn_world_pos.y
	return snapped_world_pos

func _find_spawn_point_by_id(requested_spawn_id: String) -> PlayerSpawnPoint:
	var spawn_points := find_children("*", "PlayerSpawnPoint", true, false)
	for node in spawn_points:
		if node is PlayerSpawnPoint:
			var spawn_point := node as PlayerSpawnPoint
			if spawn_point.matches_spawn_id(requested_spawn_id):
				return spawn_point
	return null

func _sync_subscene_state() -> void:
	if GameState == null:
		return
	if location_id.is_empty():
		location_id = GameState.current_subscene_location_id
	GameState.active_scene_kind = scene_kind
	GameState.current_subscene_location_id = location_id
	GameState.player_position = location_id
