class_name GameWorldRoot
extends Node3D

const CameraController3D = preload("res://systems/camera_controller_3d.gd")
const CameraConfig3D = preload("res://systems/camera_config_3d.gd")
const GameWorld3D = preload("res://scripts/locations/game_world_3d.gd")

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

@export var pawn_move_speed: float = 4.5

@onready var _camera_controller: CameraController3D = $CameraController3D
@onready var _focus_anchor: Node3D = $FocusAnchor
@onready var _overworld_layer: Node3D = $OverworldLayer
@onready var _locations_root: Node3D = $OverworldLayer/LocationsRoot
@onready var _pawn: Node3D = $OverworldLayer/OverworldPawn
@onready var _location_instances: Node3D = $LocationInstances
@onready var _status_panel: Control = $CanvasLayer/PanelContainer
@onready var _status_label: Label = $CanvasLayer/PanelContainer/VBoxContainer/StatusLabel
@onready var _location_label: Label = $CanvasLayer/PanelContainer/VBoxContainer/LocationLabel

var _walkable_cells: Dictionary = {}
var _location_nodes: Dictionary = {}
var _active_outdoor_scene: GameWorld3D = null
var _active_outdoor_location_id: String = "safehouse"
var _travel_path: Array[Vector3] = []
var _travel_target_location_id: String = ""
var _travel_step_index: int = 0
var _is_traveling: bool = false
var _transition_locked: bool = false

func _ready() -> void:
	add_to_group("world_root")
	_apply_camera_profile()
	_build_walkable_cells()
	_build_location_markers()
	_restore_from_game_state()

func _exit_tree() -> void:
	if CameraConfigService != null and CameraConfigService.has_method("clear_runtime_override"):
		CameraConfigService.clear_runtime_override()

func _process(delta: float) -> void:
	if not _is_traveling:
		return
	_advance_travel(delta)

func _unhandled_input(event: InputEvent) -> void:
	if _transition_locked or _is_traveling:
		return
	if GameState == null or GameState.world_mode != MODE_OVERWORLD:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT or not mouse_button.pressed:
		return
	if _is_menu_overlay_open():
		return
	var hit := _raycast_mouse(mouse_button.position)
	if hit.is_empty():
		return
	var location_id := _resolve_location_id_from_hit(hit)
	if location_id.is_empty():
		return
	if travel_to_location(location_id) and get_viewport() != null:
		get_viewport().set_input_as_handled()

func request_enter_overworld() -> bool:
	if _transition_locked or _is_traveling:
		return false
	if GameState == null or GameState.world_mode != MODE_LOCAL:
		return false
	call_deferred("_run_enter_overworld_sequence")
	return true

func travel_to_location(location_id: String) -> bool:
	if _transition_locked or _is_traveling or MapModule == null:
		return false
	if location_id == _active_outdoor_location_id:
		call_deferred("_run_enter_local_sequence")
		return true

	var validation := MapModule.can_travel_to_outdoor(location_id, true)
	if not bool(validation.get("success", false)):
		_update_status(str(validation.get("message", "当前无法前往该地点。")))
		return false

	var reachable_locations: Array[String] = MapModule.get_reachable_outdoor_locations(_active_outdoor_location_id)
	if location_id not in reachable_locations:
		_update_status("当前无法从这里直达该地点。")
		return false

	var from_cell := get_current_overworld_cell()
	var to_cell := MapModule.get_location_overworld_cell(location_id)
	var cell_path: Array[Vector2i] = MapModule.find_overworld_path(from_cell, to_cell)
	if cell_path.size() <= 1:
		_update_status("没有找到通往该地点的大地图路径。")
		return false

	_travel_path.clear()
	for cell in cell_path:
		_travel_path.append(_cell_to_world(cell))
	if not _travel_path.is_empty() and _travel_path[0].distance_to(_pawn.global_position) <= 0.01:
		_travel_path.remove_at(0)
	if _travel_path.is_empty():
		return false

	_travel_target_location_id = location_id
	_travel_step_index = 0
	_is_traveling = true
	_transition_locked = true
	GameState.set_world_mode(MODE_TRAVELING)
	_update_status("正在前往 %s..." % MapModule.get_location_name(location_id))
	return true

func get_current_overworld_cell() -> Vector2i:
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
	_pawn.global_position = _cell_to_world(current_cell)
	_overworld_layer.visible = true
	_status_panel.visible = true
	if GameState != null:
		GameState.set_world_mode(MODE_OVERWORLD)
		GameState.set_overworld_cell(current_cell)
		GameState.set_camera_zoom_level(OVERWORLD_ZOOM)
	_camera_controller.target = _pawn
	_camera_controller.set_zoom(OVERWORLD_ZOOM)
	_refresh_marker_state()
	_update_status("左键点击一个已解锁的露天地点即可移动并进入该地点。")

func _run_enter_overworld_sequence() -> void:
	if _transition_locked or _active_outdoor_scene == null:
		return
	_transition_locked = true
	GameState.set_world_mode(MODE_ZOOMING_OUT)
	_focus_anchor.global_position = _active_outdoor_scene.get_runtime_focus_position()
	_pawn.global_position = _cell_to_world(MapModule.get_location_overworld_cell(_active_outdoor_location_id))
	_overworld_layer.visible = true
	_status_panel.visible = true
	_camera_controller.target = _focus_anchor
	_camera_controller.set_zoom(OVERWORLD_ZOOM)
	_active_outdoor_scene.set_runtime_active(false)
	_active_outdoor_scene.set_detail_level(GameWorld3D.DETAIL_REDUCED)

	var tween := create_tween()
	tween.tween_property(_focus_anchor, "global_position", _pawn.global_position, TRANSITION_DURATION)
	await tween.finished

	_active_outdoor_scene.set_detail_level(GameWorld3D.DETAIL_PROXY_ONLY)
	_camera_controller.target = _pawn
	GameState.set_world_mode(MODE_OVERWORLD)
	GameState.set_overworld_cell(MapModule.get_location_overworld_cell(_active_outdoor_location_id))
	GameState.set_camera_zoom_level(OVERWORLD_ZOOM)
	_refresh_marker_state()
	_update_status("左键点击一个已解锁的露天地点即可移动并进入该地点。")
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

	_focus_anchor.global_position = _pawn.global_position
	_camera_controller.target = _focus_anchor
	_camera_controller.set_zoom(LOCAL_ZOOM)

	var tween := create_tween()
	tween.tween_property(_focus_anchor, "global_position", target_player.global_position, TRANSITION_DURATION)
	await tween.finished

	_overworld_layer.visible = false
	_status_panel.visible = false
	_camera_controller.target = target_player
	GameState.set_world_mode(MODE_LOCAL)
	GameState.set_camera_zoom_level(LOCAL_ZOOM)
	GameState.active_outdoor_spawn_id = "default_spawn"
	_update_location_label()
	_update_status("当前处于 %s，小地图交互点可返回大地图。" % MapModule.get_location_name(_active_outdoor_location_id))
	_transition_locked = false

func _advance_travel(delta: float) -> void:
	if _travel_step_index >= _travel_path.size():
		_finish_travel()
		return
	var next_point := _travel_path[_travel_step_index]
	_pawn.global_position = _pawn.global_position.move_toward(next_point, pawn_move_speed * delta)
	if _pawn.global_position.distance_to(next_point) <= 0.02:
		_pawn.global_position = next_point
		_travel_step_index += 1

func _finish_travel() -> void:
	_is_traveling = false
	var target_location_id := _travel_target_location_id
	_travel_path.clear()
	_travel_step_index = 0
	_travel_target_location_id = ""

	if not MapModule.travel_to(target_location_id, true):
		_transition_locked = false
		_update_status("进入地点失败。")
		return

	var entry_spawn_id := MapModule.get_location_entry_spawn_id(target_location_id)
	GameState.set_active_outdoor_context(target_location_id, entry_spawn_id)
	GameState.set_overworld_cell(MapModule.get_location_overworld_cell(target_location_id))
	_load_outdoor_scene(target_location_id, entry_spawn_id)
	_refresh_marker_state()
	_transition_locked = false
	call_deferred("_run_enter_local_sequence")

func _build_walkable_cells() -> void:
	_walkable_cells.clear()
	if MapModule == null:
		return
	for cell in MapModule.get_overworld_walkable_cells():
		_walkable_cells[_cell_key(cell)] = true
	for location_id in MapModule.get_outdoor_location_ids():
		_walkable_cells[_cell_key(MapModule.get_location_overworld_cell(location_id))] = true

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

	return marker

func _refresh_marker_state() -> void:
	if MapModule == null:
		return
	var reachable_locations: Array[String] = MapModule.get_reachable_outdoor_locations(_active_outdoor_location_id)
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
			marker_color = Color(0.20, 0.78, 0.28) if location_id in reachable_locations else Color(0.82, 0.66, 0.25)
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

func _raycast_mouse(screen_pos: Vector2) -> Dictionary:
	var viewport := get_viewport()
	if viewport == null:
		return {}
	var camera := viewport.get_camera_3d()
	if camera == null:
		return {}
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	return get_world_3d().direct_space_state.intersect_ray(query)

func _resolve_location_id_from_hit(hit: Dictionary) -> String:
	if not hit.has("collider"):
		return ""
	var node := hit.collider as Node
	while node != null:
		if node.has_meta("location_id"):
			return str(node.get_meta("location_id"))
		node = node.get_parent()
	return ""

func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)

func _get_outdoor_scene_origin(location_id: String) -> Vector3:
	var cell := MapModule.get_location_world_origin_cell(location_id)
	return Vector3(float(cell.x), 0.0, float(cell.y))

func _cell_key(cell: Vector2i) -> String:
	return "%d|%d" % [cell.x, cell.y]

func _update_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message

func _is_menu_overlay_open() -> bool:
	if MenuHotkeyService != null and MenuHotkeyService.has_method("is_any_menu_open"):
		return bool(MenuHotkeyService.is_any_menu_open())
	return false

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
