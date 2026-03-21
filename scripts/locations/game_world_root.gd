class_name GameWorldRoot
extends Node3D

const CameraController3D = preload("res://systems/camera_controller_3d.gd")
const CameraConfig3D = preload("res://systems/camera_config_3d.gd")
const GameWorld3D = preload("res://scripts/locations/game_world_3d.gd")
const Interactable = preload("res://modules/interaction/interactable.gd")
const EnterOutdoorLocationInteractionOption = preload("res://modules/interaction/options/enter_outdoor_location_interaction_option.gd")
const HoverOutline3D = preload("res://systems/hover_outline_3d.gd")
const OverworldGridWorld = preload("res://systems/overworld_grid_world.gd")
const PlayerController = preload("res://systems/player_controller.gd")

const LOCATION_MARKER_GROUP: StringName = &"overworld_location_marker"
const MARKER_Y: float = 0.35
const MODE_LOCAL: String = "LOCAL"
const MODE_OVERWORLD: String = "OVERWORLD"
const MODE_TRAVELING: String = "TRAVELING"
const MODE_ZOOMING_OUT: String = "ZOOMING_OUT"
const MODE_ZOOMING_IN: String = "ZOOMING_IN"
const TRANSITION_DURATION: float = 0.35
const LOCAL_ZOOM: float = 7.5
const OVERWORLD_ZOOM: float = 15.5
const OVERWORLD_PREVIEW_MAX_POINTS: int = 200
const OVERWORLD_PREVIEW_DISTANCE: float = 80.0
const OVERWORLD_INTERACTION_MIN_RADIUS: int = 1
const OVERWORLD_INTERACTION_MAX_RADIUS: int = 2

@export var pawn_move_speed: float = 4.5

@onready var _camera_controller: CameraController3D = $CameraController3D
@onready var _focus_anchor: Node3D = $FocusAnchor
@onready var _overworld_layer: Node3D = $OverworldLayer
@onready var _locations_root: Node3D = $OverworldLayer/LocationsRoot
@onready var _pawn_anchor: Node3D = $OverworldLayer/OverworldPawn
@onready var _location_instances: Node3D = $LocationInstances
@onready var _status_panel: Control = $CanvasLayer/PanelContainer
@onready var _status_label: Label = $CanvasLayer/PanelContainer/VBoxContainer/StatusLabel
@onready var _location_label: Label = $CanvasLayer/PanelContainer/VBoxContainer/LocationLabel

var _overworld_grid_world: OverworldGridWorld = null
var _overworld_player: PlayerController = null
var _location_nodes: Dictionary = {}
var _active_outdoor_scene: GameWorld3D = null
var _active_outdoor_location_id: String = "safehouse"
var _transition_locked: bool = false

func _ready() -> void:
	add_to_group("world_root")
	_apply_camera_profile()
	_setup_overworld_player()
	_build_location_markers()
	_restore_from_game_state()

func _exit_tree() -> void:
	if CameraConfigService != null and CameraConfigService.has_method("clear_runtime_override"):
		CameraConfigService.clear_runtime_override()

func request_enter_overworld() -> bool:
	if _transition_locked:
		return false
	if GameState == null or GameState.world_mode != MODE_LOCAL:
		return false
	call_deferred("_run_enter_overworld_sequence")
	return true

func request_enter_outdoor_location(location_id: String) -> bool:
	if _transition_locked or MapModule == null:
		return false
	if location_id.is_empty() or not MapModule.is_outdoor_location(location_id):
		return false
	if location_id == _active_outdoor_location_id:
		_run_enter_local_sequence()
		return true

	var validation := MapModule.can_travel_to_outdoor(location_id, true)
	if not bool(validation.get("success", false)):
		_update_status(str(validation.get("message", "当前无法前往该地点。")))
		return false

	if not MapModule.travel_to(location_id, true):
		_update_status("进入地点失败。")
		return false

	var entry_spawn_id := MapModule.get_location_entry_spawn_id(location_id)
	_load_outdoor_scene(location_id, entry_spawn_id)
	_refresh_marker_state()
	_run_enter_local_sequence()
	return true

func get_current_overworld_cell() -> Vector2i:
	if _overworld_player != null and is_instance_valid(_overworld_player):
		var player_grid := GridMovementSystem.world_to_grid(_overworld_player.global_position)
		return Vector2i(player_grid.x, player_grid.z)
	if GameState != null and GameState.overworld_pawn_cell != Vector2i.ZERO:
		return GameState.overworld_pawn_cell
	return MapModule.get_location_overworld_cell(_active_outdoor_location_id)

func _restore_from_game_state() -> void:
	var location_id := "safehouse"
	var spawn_id := "default_spawn"
	if GameState != null:
		location_id = str(GameState.active_outdoor_location_id).strip_edges()
		spawn_id = str(GameState.active_outdoor_spawn_id).strip_edges()
	if location_id.is_empty():
		location_id = "safehouse"
	if spawn_id.is_empty():
		spawn_id = "default_spawn"

	_load_outdoor_scene(location_id, spawn_id)
	_active_outdoor_location_id = location_id
	_refresh_marker_state()

	if GameState != null and GameState.world_mode == MODE_OVERWORLD:
		_enter_overworld_immediate()
	else:
		_enter_local_immediate()

func _setup_overworld_player() -> void:
	if _overworld_player != null:
		return

	_overworld_grid_world = OverworldGridWorld.new()
	_overworld_grid_world.name = "OverworldGridWorld"
	add_child(_overworld_grid_world)
	_refresh_overworld_walkable_cells()

	_overworld_player = PlayerController.new()
	_overworld_player.name = "OverworldPlayer"
	_overworld_layer.add_child(_overworld_player)
	_overworld_player.set_grid_world(_overworld_grid_world)
	_overworld_player.set_interaction_context(self)
	_overworld_player.configure_path_preview_settings(
		OVERWORLD_PREVIEW_MAX_POINTS,
		OVERWORLD_PREVIEW_DISTANCE,
		OVERWORLD_INTERACTION_MIN_RADIUS,
		OVERWORLD_INTERACTION_MAX_RADIUS
	)
	_overworld_player.movement_step_completed.connect(_on_overworld_player_movement_step_completed)
	_overworld_player.movement_completed.connect(_on_overworld_player_movement_completed)
	_set_overworld_player_active(false)
	if _pawn_anchor != null:
		_pawn_anchor.visible = false

func _refresh_overworld_walkable_cells() -> void:
	if _overworld_grid_world == null or MapModule == null:
		return
	var walkable_cells: Array[Vector2i] = MapModule.get_overworld_walkable_cells()
	for location_id in MapModule.get_outdoor_location_ids():
		walkable_cells.append(MapModule.get_location_overworld_cell(location_id))
	_overworld_grid_world.set_walkable_cells(walkable_cells)

func _load_outdoor_scene(location_id: String, spawn_id: String) -> void:
	var scene_path := MapModule.get_location_scene_path(location_id)
	if scene_path.is_empty():
		push_error("GameWorldRoot: outdoor scene path missing for %s" % location_id)
		return

	if _active_outdoor_scene != null:
		_active_outdoor_scene.queue_free()
		_active_outdoor_scene = null

	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("GameWorldRoot: failed to load %s" % scene_path)
		return

	var instance := packed_scene.instantiate()
	if not (instance is GameWorld3D):
		push_error("GameWorldRoot: scene is not a GameWorld3D instance: %s" % scene_path)
		instance.queue_free()
		return

	var outdoor_scene := instance as GameWorld3D
	outdoor_scene.location_id = location_id
	outdoor_scene.set_hosted_mode(true)
	outdoor_scene.set_runtime_spawn(spawn_id)
	outdoor_scene.position = _get_outdoor_scene_origin(location_id)
	_location_instances.add_child(outdoor_scene)
	_active_outdoor_scene = outdoor_scene
	_active_outdoor_location_id = location_id

func _enter_local_immediate() -> void:
	if _active_outdoor_scene == null:
		return
	_save_overworld_player_state()
	_set_overworld_player_active(false)
	_overworld_layer.visible = false
	_status_panel.visible = false
	_active_outdoor_scene.visible = true
	_active_outdoor_scene.set_detail_level(GameWorld3D.DETAIL_FULL)
	_active_outdoor_scene.set_runtime_active(true)
	if GameState != null:
		GameState.set_world_mode(MODE_LOCAL)
		GameState.set_camera_zoom_level(LOCAL_ZOOM)
		GameState.set_active_outdoor_context(
			_active_outdoor_location_id,
			GameState.active_outdoor_spawn_id
		)
		GameState.active_outdoor_spawn_id = "default_spawn"
	_camera_controller.target = _active_outdoor_scene.get_player()
	_camera_controller.set_zoom(LOCAL_ZOOM)
	_update_location_label()
	_update_status("当前处于 %s，小地图交互点可返回大地图。" % MapModule.get_location_name(_active_outdoor_location_id))

func _enter_overworld_immediate() -> void:
	if _active_outdoor_scene != null:
		_active_outdoor_scene.set_runtime_active(false)
		_active_outdoor_scene.set_detail_level(GameWorld3D.DETAIL_PROXY_ONLY)
	var current_cell := MapModule.get_location_overworld_cell(_active_outdoor_location_id)
	if GameState != null and GameState.overworld_pawn_cell != Vector2i.ZERO:
		current_cell = GameState.overworld_pawn_cell
	_set_overworld_player_cell(current_cell)
	_set_overworld_player_active(true)
	_overworld_layer.visible = true
	_status_panel.visible = true
	if GameState != null:
		GameState.set_world_mode(MODE_OVERWORLD)
		GameState.set_overworld_cell(current_cell)
		GameState.set_camera_zoom_level(OVERWORLD_ZOOM)
	_camera_controller.target = _overworld_player
	_camera_controller.set_zoom(OVERWORLD_ZOOM)
	_refresh_marker_state()
	_update_status("左键点击地面自由移动，点击地点标记会像小地图一样靠近后进入。")

func _run_enter_overworld_sequence() -> void:
	if _transition_locked or _active_outdoor_scene == null or _overworld_player == null:
		return
	_transition_locked = true
	GameState.set_world_mode(MODE_ZOOMING_OUT)
	_focus_anchor.global_position = _active_outdoor_scene.get_runtime_focus_position()
	_set_overworld_player_cell(MapModule.get_location_overworld_cell(_active_outdoor_location_id))
	_set_overworld_player_active(true)
	_overworld_layer.visible = true
	_status_panel.visible = true
	_camera_controller.target = _focus_anchor
	_camera_controller.set_zoom(OVERWORLD_ZOOM)
	_active_outdoor_scene.set_runtime_active(false)
	_active_outdoor_scene.set_detail_level(GameWorld3D.DETAIL_REDUCED)

	var tween := create_tween()
	tween.tween_property(_focus_anchor, "global_position", _overworld_player.global_position, TRANSITION_DURATION)
	await tween.finished

	_active_outdoor_scene.set_detail_level(GameWorld3D.DETAIL_PROXY_ONLY)
	_camera_controller.target = _overworld_player
	GameState.set_world_mode(MODE_OVERWORLD)
	_save_overworld_player_state()
	GameState.set_camera_zoom_level(OVERWORLD_ZOOM)
	_refresh_marker_state()
	_update_status("左键点击地面自由移动，点击地点标记会像小地图一样靠近后进入。")
	_transition_locked = false

func _run_enter_local_sequence() -> void:
	if _transition_locked or _active_outdoor_scene == null:
		return
	_transition_locked = true
	GameState.set_world_mode(MODE_ZOOMING_IN)
	_active_outdoor_scene.visible = true
	_active_outdoor_scene.set_detail_level(GameWorld3D.DETAIL_FULL)
	_active_outdoor_scene.set_runtime_active(true)

	var target_player := _active_outdoor_scene.get_player()
	if target_player == null:
		_transition_locked = false
		return

	_save_overworld_player_state()
	_focus_anchor.global_position = _overworld_player.global_position if _overworld_player != null else _focus_anchor.global_position
	_camera_controller.target = _focus_anchor
	_camera_controller.set_zoom(LOCAL_ZOOM)

	var tween := create_tween()
	tween.tween_property(_focus_anchor, "global_position", target_player.global_position, TRANSITION_DURATION)
	await tween.finished

	_set_overworld_player_active(false)
	_overworld_layer.visible = false
	_status_panel.visible = false
	_camera_controller.target = target_player
	GameState.set_world_mode(MODE_LOCAL)
	GameState.set_camera_zoom_level(LOCAL_ZOOM)
	GameState.active_outdoor_spawn_id = "default_spawn"
	_update_location_label()
	_update_status("当前处于 %s，小地图交互点可返回大地图。" % MapModule.get_location_name(_active_outdoor_location_id))
	_transition_locked = false

func _build_location_markers() -> void:
	_location_nodes.clear()
	for child in _locations_root.get_children():
		child.queue_free()
	if MapModule == null:
		return

	for location_id in MapModule.get_outdoor_locations_for_overworld():
		var marker := _create_location_marker(location_id, MapModule.get_location_descriptor(location_id))
		_locations_root.add_child(marker)
		_location_nodes[location_id] = marker

func _create_location_marker(location_id: String, location_data: Dictionary) -> StaticBody3D:
	var marker := StaticBody3D.new()
	marker.name = "Location_%s" % location_id
	marker.add_to_group(LOCATION_MARKER_GROUP)
	marker.set_meta("location_id", location_id)
	marker.position = _cell_to_world(MapModule.get_location_overworld_cell(location_id))

	var collision := CollisionShape3D.new()
	var collision_shape := CylinderShape3D.new()
	collision_shape.radius = 0.45
	collision_shape.height = 1.2
	collision.shape = collision_shape
	collision.position = Vector3(0.0, 0.6, 0.0)
	marker.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MarkerMesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.35
	mesh.bottom_radius = 0.45
	mesh.height = 0.3
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, MARKER_Y, 0.0)
	mesh_instance.material_override = _build_marker_material(Color(0.35, 0.35, 0.35))
	marker.add_child(mesh_instance)

	var label := Label3D.new()
	label.name = "MarkerLabel"
	label.position = Vector3(0.0, 1.2, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = str(location_data.get("name", location_id))
	marker.add_child(label)

	var interactable := Interactable.new()
	interactable.name = "Interactable"
	interactable.interaction_name = "进入%s" % str(location_data.get("name", location_id))
	interactable.hover_outline_target_path = NodePath("../HoverOutline3D")
	marker.add_child(interactable)

	var option: Resource = EnterOutdoorLocationInteractionOption.new()
	option.display_name = "进入%s" % str(location_data.get("name", location_id))
	option.target_location_id = location_id
	interactable.set_options([option])

	var hover_outline := HoverOutline3D.new()
	hover_outline.name = "HoverOutline3D"
	hover_outline.target_node_paths = [NodePath("../MarkerMesh"), NodePath("../MarkerLabel")]
	marker.add_child(hover_outline)

	return marker

func _refresh_marker_state() -> void:
	if MapModule == null:
		return
	for location_id in _location_nodes.keys():
		var marker := _location_nodes[location_id] as StaticBody3D
		if marker == null:
			continue
		var mesh_instance := marker.get_node_or_null("MarkerMesh") as MeshInstance3D
		var label := marker.get_node_or_null("MarkerLabel") as Label3D
		var marker_color := Color(0.35, 0.35, 0.35)
		if location_id == _active_outdoor_location_id:
			marker_color = Color(0.15, 0.75, 1.0)
		elif MapModule.is_location_unlocked(location_id):
			marker_color = Color(0.20, 0.78, 0.28)
		if mesh_instance != null:
			mesh_instance.material_override = _build_marker_material(marker_color)
		if label != null:
			label.modulate = marker_color.lightened(0.15)
	_update_location_label()

func _update_location_label() -> void:
	if _location_label == null:
		return
	_location_label.text = "当前位置：%s" % MapModule.get_location_name(_active_outdoor_location_id)

func _build_marker_material(albedo_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo_color
	material.metallic = 0.1
	material.roughness = 0.35
	return material

func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)

func _get_outdoor_scene_origin(location_id: String) -> Vector3:
	var cell := MapModule.get_location_world_origin_cell(location_id)
	return Vector3(float(cell.x), 0.0, float(cell.y))

func _update_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message

func _is_menu_overlay_open() -> bool:
	if MenuHotkeyService != null and MenuHotkeyService.has_method("is_any_menu_open"):
		return bool(MenuHotkeyService.is_any_menu_open())
	return false

func _set_overworld_player_active(active: bool) -> void:
	if _overworld_player == null:
		return
	_overworld_player.visible = active
	_overworld_player.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if not active:
		_overworld_player.clear_world_input_feedback()

func _set_overworld_player_cell(cell: Vector2i) -> void:
	if _overworld_player == null:
		return
	if _overworld_player.is_moving():
		_overworld_player.cancel_movement()
	_overworld_player.global_position = _cell_to_world(cell)
	_save_overworld_player_state()

func _save_overworld_player_state() -> void:
	if GameState == null or _overworld_player == null:
		return
	GameState.set_overworld_cell(get_current_overworld_cell())

func _on_overworld_player_movement_step_completed(
	grid_pos: Vector3i,
	_world_pos: Vector3,
	_step_index: int,
	_total_steps: int
) -> void:
	if GameState == null:
		return
	GameState.set_overworld_cell(Vector2i(grid_pos.x, grid_pos.z))

func _on_overworld_player_movement_completed() -> void:
	_save_overworld_player_state()

func _apply_camera_profile() -> void:
	if CameraConfigService == null or not CameraConfigService.has_method("set_runtime_override"):
		return
	CameraConfigService.set_runtime_override(
		{
			"projection_type": CameraConfig3D.ProjectionType.ORTHOGRAPHIC,
			"rotation": Vector3(-70.0, 0.0, 0.0),
			"arm_length": 18.0,
			"min_zoom": 5.0,
			"max_zoom": 20.0,
			"initial_zoom": 11.0,
			"zoom_speed": 1.5,
			"zoom_smoothing": 0.18,
			"follow_smoothing": 0.16
		}
	)
