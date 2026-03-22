class_name GameWorld3D
extends Node3D

const CameraController3D = preload("res://systems/camera_controller_3d.gd")
const PlayerController = preload("res://systems/player_controller.gd")
const GridDebugController = preload("res://systems/grid_debug_controller.gd")
const GridVisualizer = preload("res://systems/grid_visualizer.gd")
const AISpawnSystem = preload("res://systems/spawn/ai_spawn_system.gd")
const ShopComponentScript = preload("res://modules/npc/components/shop_component.gd")
const PlayerSpawnPoint = preload("res://systems/spawn/player_spawn_point.gd")

const MERCHANT_SPAWN_ID: String = "gw3d_merchant_spawn"
const DETAIL_FULL: int = 0
const DETAIL_REDUCED: int = 1
const DETAIL_PROXY_ONLY: int = 2

@export var location_id: String = "safehouse"
@export var player_scene: PackedScene = null
@export var grid_debug_default_visible: bool = false
@export var max_preview_path_points: int = 200
@export var max_preview_distance: float = 40.0
@export var interaction_preview_min_radius: int = 1
@export var interaction_preview_max_radius: int = 4
@export var hosted_mode: bool = false

@onready var _camera_controller: CameraController3D = $CameraController3D
@onready var _grid_floor: StaticBody3D = $GridFloor
@onready var _merchant_shop: ShopComponentScript = get_node_or_null("MerchantShop") as ShopComponentScript

var runtime_spawn_id: String = ""
var _player: PlayerController = null
var _grid_visualizer: GridVisualizer = null
var _grid_debug_controller: GridDebugController = null
var _spawn_system: AISpawnSystem = null
var _runtime_active: bool = true
var _detail_level: int = DETAIL_FULL

func _ready() -> void:
	_sync_location_state()
	_setup_world()
	_spawn_player()
	_setup_camera()
	_setup_runtime_systems()
	_apply_hosted_mode_state()
	set_runtime_active(true)
	set_detail_level(DETAIL_FULL)

func _exit_tree() -> void:
	if _grid_debug_controller:
		_grid_debug_controller.cleanup()

func set_hosted_mode(value: bool) -> void:
	hosted_mode = value
	if is_inside_tree():
		_apply_hosted_mode_state()

func set_runtime_spawn(spawn_id: String) -> void:
	runtime_spawn_id = spawn_id.strip_edges()

func set_runtime_active(active: bool) -> void:
	_runtime_active = active
	if _player != null:
		if not active:
			_save_player_runtime_state()
		_player.visible = active
		_player.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if _spawn_system != null:
		_spawn_system.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		if not active:
			_despawn_runtime_actors()

func set_detail_level(level: int) -> void:
	_detail_level = level
	match level:
		DETAIL_FULL:
			visible = true
			_set_environment_visibility(true)
			_set_runtime_visual_nodes_visible(true)
		DETAIL_REDUCED:
			visible = true
			_set_environment_visibility(true)
			_set_runtime_visual_nodes_visible(false)
		DETAIL_PROXY_ONLY:
			visible = false
			_set_environment_visibility(false)
		_:
			visible = true

func get_player() -> PlayerController:
	return _player

func get_camera() -> CameraController3D:
	return _camera_controller

func get_location_id() -> String:
	return location_id

func get_runtime_focus_position() -> Vector3:
	if _player != null:
		return _player.global_position
	var spawn_point := resolve_spawn_point(runtime_spawn_id)
	if spawn_point != null:
		return spawn_point.global_position
	return global_position

func resolve_spawn_point(spawn_id: String) -> Node3D:
	var normalized_spawn_id := spawn_id.strip_edges()
	if not normalized_spawn_id.is_empty():
		var matching_spawn := _find_spawn_point_by_id(normalized_spawn_id)
		if matching_spawn != null:
			return matching_spawn
	if not hosted_mode and location_id == "safehouse" and not GameState.player_local_position.is_zero_approx():
		return null
	var default_spawn := _find_spawn_point_by_id("default_spawn")
	if default_spawn != null:
		return default_spawn
	return get_node_or_null("PlayerSpawn") as Node3D

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
	_player.set_interaction_context(self)
	_player.configure_path_preview_settings(
		max_preview_path_points,
		max_preview_distance,
		interaction_preview_min_radius,
		interaction_preview_max_radius
	)
	_player.movement_step_completed.connect(_on_player_movement_step_completed)
	_save_player_runtime_state()

func _setup_camera() -> void:
	if _camera_controller == null:
		push_error("GameWorld3D: CameraController3D node not found")
		return
	if hosted_mode:
		_camera_controller.process_mode = Node.PROCESS_MODE_DISABLED
		_camera_controller.target = null
		return
	_camera_controller.target = _player

func _setup_runtime_systems() -> void:
	_spawn_system = AISpawnSystem.new()
	add_child(_spawn_system)
	_spawn_system.initialize(self)
	_spawn_system.actor_spawned.connect(_on_actor_spawned)
	_spawn_system.actor_despawned.connect(_on_actor_despawned)
	_spawn_system.spawn_auto_points()

func _apply_hosted_mode_state() -> void:
	if _camera_controller != null:
		_camera_controller.make_current_on_ready = not hosted_mode
		if hosted_mode:
			_camera_controller.process_mode = Node.PROCESS_MODE_DISABLED
			_camera_controller.target = null
		elif _player != null:
			_camera_controller.process_mode = Node.PROCESS_MODE_INHERIT
			_camera_controller.target = _player

func _on_actor_spawned(spawn_id: String, actor: Node3D) -> void:
	if spawn_id != MERCHANT_SPAWN_ID:
		return
	if _merchant_shop == null:
		return
	_merchant_shop.bind_actor(actor)

func _on_actor_despawned(spawn_id: String) -> void:
	if spawn_id != MERCHANT_SPAWN_ID:
		return
	if _merchant_shop == null:
		return
	_merchant_shop.unbind_actor()

func _resolve_player_spawn_position(fallback_world_pos: Vector3) -> Vector3:
	if hosted_mode and location_id == GameState.active_outdoor_location_id:
		var use_saved_local := runtime_spawn_id.is_empty() or runtime_spawn_id == "default_spawn"
		if use_saved_local and GameState.world_mode == GameState.WORLD_MODE_LOCAL:
			var saved_local := GameState.player_local_position
			if not saved_local.is_zero_approx():
				return to_global(saved_local)

	var spawn_world_pos: Vector3 = fallback_world_pos
	var player_spawn_node := resolve_spawn_point(runtime_spawn_id)
	if player_spawn_node:
		if player_spawn_node.has_method("get_spawn_position"):
			spawn_world_pos = player_spawn_node.get_spawn_position()
		else:
			spawn_world_pos = player_spawn_node.global_position

	if _player == null:
		return spawn_world_pos
	if not _player.has_method("snap_world_to_grid"):
		return spawn_world_pos

	var snapped_world_pos: Vector3 = _player.snap_world_to_grid(spawn_world_pos)
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

func _sync_location_state() -> void:
	if GameState == null:
		return
	if location_id.is_empty():
		location_id = "safehouse"
	GameState.player_position = location_id
	if hosted_mode:
		GameState.active_outdoor_location_id = location_id

func _on_player_movement_step_completed(
	_grid_pos: Vector3i,
	_world_pos: Vector3,
	_step_index: int,
	_total_steps: int
) -> void:
	_save_player_runtime_state()

func _save_player_runtime_state() -> void:
	if GameState == null or _player == null:
		return
	GameState.player_position = location_id
	GameState.player_position_3d = _player.global_position
	GameState.player_grid_position = _player.get_grid_position()
	GameState.player_local_position = to_local(_player.global_position)

func _set_environment_visibility(active: bool) -> void:
	var light := get_node_or_null("DirectionalLight3D") as Node3D
	if light != null:
		light.visible = active

func _set_runtime_visual_nodes_visible(active: bool) -> void:
	for node in get_children():
		if node == _camera_controller:
			continue
		if node == _grid_floor:
			continue
		if node == _player:
			continue
		if node is Marker3D:
			node.visible = active
			continue
		if node is Node3D:
			(node as Node3D).visible = active

func _despawn_runtime_actors() -> void:
	if _spawn_system == null:
		return
	var active_instances: Dictionary = _spawn_system.get("_active_instances")
	for spawn_id_variant in active_instances.keys():
		_spawn_system.despawn_actor(str(spawn_id_variant))
