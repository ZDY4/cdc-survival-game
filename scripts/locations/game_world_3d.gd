class_name GameWorld3D
extends Node3D

@export var player_scene: PackedScene = null
@export var show_grid_debug := false
@export var max_preview_path_points := 200
@export var max_preview_distance := 40.0
@export var interaction_preview_min_radius := 1
@export var interaction_preview_max_radius := 4

@onready var _camera_controller: CameraController3D
@onready var _player: PlayerController3D
@onready var _grid_floor: StaticBody3D
@onready var _path_preview: PathPreview
@onready var _navigator: GridNavigator

var _is_mouse_pressed := false
var _last_hover_pos: Vector3
var _active_move_target: Vector3 = Vector3.ZERO
var _has_active_move_target := false

func _ready() -> void:
    _setup_world()
    _spawn_player()
    _setup_camera()
    _setup_input()

func _setup_world() -> void:
    _navigator = GridNavigator.new()
    
    _grid_floor = $GridFloor
    _setup_grid_floor_collision()
    
    # Add grid visualizer
    if show_grid_debug:
        var visualizer := GridVisualizer.new()
        add_child(visualizer)
        visualizer.show_grid()

func _setup_grid_floor_collision() -> void:
    var collision_shape := CollisionShape3D.new()
    _grid_floor.add_child(collision_shape)
    
    var shape := BoxShape3D.new()
    shape.size = Vector3(100, 0.1, 100)
    collision_shape.shape = shape
    collision_shape.position = Vector3(0, -0.05, 0)

func _spawn_player() -> void:
    if player_scene:
        _player = player_scene.instantiate()
    else:
        _player = PlayerController3D.new()
    
    add_child(_player)
    _player.global_position = Vector3(0, 1, 0)
    _player.set_grid_world(GridMovementSystem.grid_world)
    _player.move_requested.connect(_on_player_move_requested)
    _player.movement_completed.connect(_on_player_movement_completed)
    
    GameState.player_position_3d = _player.global_position

func _setup_camera() -> void:
    _camera_controller = CameraController3D.new()
    add_child(_camera_controller)
    _camera_controller.target = _player

func _setup_input() -> void:
    _path_preview = PathPreview.new()
    add_child(_path_preview)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            _is_mouse_pressed = event.pressed
            if event.pressed:
                if _player and _player.is_moving():
                    _player.cancel_movement()
                    _clear_active_move_target()
                    return
                _handle_ground_click()
    
    if event is InputEventScreenTouch:
        if event.pressed:
            if _player and _player.is_moving():
                _player.cancel_movement()
                _clear_active_move_target()
                return
            _handle_touch_click(event.position)

func _process(delta: float) -> void:
    _update_path_preview(delta)

var _last_preview_signature := ""
var _preview_update_timer: float = 0.0
const PREVIEW_UPDATE_INTERVAL: float = 0.1

func _update_path_preview(delta: float) -> void:
    if not _player or not _path_preview:
        return
    
    # Throttle updates
    _preview_update_timer += delta
    if _preview_update_timer < PREVIEW_UPDATE_INTERVAL:
        return
    _preview_update_timer = 0.0

    if not GridMovementSystem or not GridMovementSystem.grid_world:
        return
    if not get_world_3d():
        return

    if _has_active_move_target and not _player.is_moving():
        _clear_active_move_target()

    if _player.is_moving() and _has_active_move_target:
        _update_preview_to_target(_active_move_target, false, "move_target")
        return

    var mouse_pos := get_viewport().get_mouse_position()
    var hover_hit := _raycast_screen_position(mouse_pos)
    if not hover_hit.is_empty():
        var interactable := _resolve_interactable_from_hit(hover_hit)
        if interactable != null:
            var interaction_target_data := _find_nearest_interaction_target(interactable, hover_hit.position)
            if bool(interaction_target_data.get("found", false)):
                var interaction_target: Vector3 = interaction_target_data.get("target", Vector3.ZERO)
                _last_hover_pos = interaction_target
                _update_preview_to_target(interaction_target, true, "interactable")
                return

    var ground_hit := _raycast_screen_position(mouse_pos, true, 1)
    if ground_hit.is_empty():
        _hide_preview()
        return

    var world_pos: Vector3 = ground_hit.position
    _last_hover_pos = world_pos
    _update_preview_to_target(world_pos, true, "mouse")

func _handle_ground_click() -> void:
    var mouse_pos := get_viewport().get_mouse_position()
    _try_move_to_screen_position(mouse_pos)

func _handle_touch_click(screen_pos: Vector2) -> void:
    _try_move_to_screen_position(screen_pos)

func _try_move_to_screen_position(screen_pos: Vector2) -> void:
    if not GridMovementSystem or not GridMovementSystem.grid_world:
        return

    var hover_hit := _raycast_screen_position(screen_pos)
    if not hover_hit.is_empty():
        var interactable := _resolve_interactable_from_hit(hover_hit)
        if interactable != null:
            var interaction_target_data := _find_nearest_interaction_target(interactable, hover_hit.position)
            if bool(interaction_target_data.get("found", false)):
                var interaction_target: Vector3 = interaction_target_data.get("target", Vector3.ZERO)
                _request_player_move(interaction_target)
                return

    var ground_hit := _raycast_screen_position(screen_pos, true, 1)
    if ground_hit.is_empty():
        return

    _request_player_move(ground_hit.position)

func _request_player_move(world_pos: Vector3) -> void:
    var move_target := world_pos
    move_target.y = _player.global_position.y
    var snapped_pos := GridMovementSystem.snap_to_grid(move_target)
    snapped_pos.y = _player.global_position.y
    _player.move_to(snapped_pos)
    if not _player.is_moving():
        return

    EventBus.emit(EventBus.EventType.GRID_CLICKED, {
        "world_position": snapped_pos,
        "grid_position": GridMovementSystem.world_to_grid(snapped_pos)
    })

func _update_preview_to_target(target_world_pos: Vector3, limit_distance: bool, mode: String) -> void:
    if limit_distance and _player.global_position.distance_to(target_world_pos) > max_preview_distance:
        _hide_preview()
        return

    var preview_target := target_world_pos
    preview_target.y = _player.global_position.y

    var player_grid := GridMovementSystem.world_to_grid(_player.global_position)
    var target_grid := GridMovementSystem.world_to_grid(preview_target)
    var preview_signature := "%s|%s|%s" % [mode, str(player_grid), str(target_grid)]
    if preview_signature == _last_preview_signature:
        return
    _last_preview_signature = preview_signature

    var path := _navigator.find_path(
        _player.global_position,
        preview_target,
        GridMovementSystem.grid_world.is_walkable
    )

    if path.size() > max_preview_path_points:
        _hide_preview()
    elif path.size() > 1:
        _path_preview.show_path(path)
    else:
        _hide_preview()

func _hide_preview() -> void:
    _path_preview.hide_path()
    _last_preview_signature = ""

func _raycast_screen_position(screen_pos: Vector2, use_collision_mask: bool = false, collision_mask: int = 1) -> Dictionary:
    var camera := get_viewport().get_camera_3d()
    if not camera:
        return {}
    if not get_world_3d():
        return {}

    var from := camera.project_ray_origin(screen_pos)
    var to := from + camera.project_ray_normal(screen_pos) * 1000.0

    var query := PhysicsRayQueryParameters3D.new()
    query.from = from
    query.to = to
    if use_collision_mask:
        query.collision_mask = collision_mask

    return get_world_3d().direct_space_state.intersect_ray(query)

func _resolve_interactable_from_hit(hit: Dictionary) -> Node:
    if not hit.has("collider"):
        return null

    var node := hit.collider as Node
    while node != null:
        if node.is_in_group("interactable"):
            return node
        if node.has_signal("interacted"):
            return node
        if node.has_method("get_interaction_name"):
            return node
        if node.has_meta("interactable") and bool(node.get_meta("interactable")):
            return node
        node = node.get_parent()

    return null

func _find_nearest_interaction_target(interactable: Node, hit_position: Vector3) -> Dictionary:
    var anchor_pos := hit_position
    if interactable is Node3D:
        anchor_pos = (interactable as Node3D).global_position

    var player_grid := GridMovementSystem.world_to_grid(_player.global_position)
    var anchor_grid := GridMovementSystem.world_to_grid(anchor_pos)
    anchor_grid.y = player_grid.y

    var grid_world := GridMovementSystem.grid_world
    for radius in range(interaction_preview_min_radius, interaction_preview_max_radius + 1):
        var ring_cells := _collect_ring_cells(anchor_grid, radius)
        var best_path: Array[Vector3] = []
        var best_world := Vector3.ZERO

        for candidate_grid in ring_cells:
            if not grid_world.is_walkable(candidate_grid):
                continue
            var candidate_world := GridMovementSystem.grid_to_world(candidate_grid)
            var path := _navigator.find_path(
                _player.global_position,
                candidate_world,
                grid_world.is_walkable
            )
            if path.size() <= 1:
                continue
            if best_path.is_empty() or path.size() < best_path.size():
                best_path = path
                best_world = candidate_world

        if not best_path.is_empty():
            return {
                "found": true,
                "target": best_world
            }

    return {"found": false}

func _collect_ring_cells(center: Vector3i, radius: int) -> Array[Vector3i]:
    var cells: Array[Vector3i] = []
    for x in range(center.x - radius, center.x + radius + 1):
        for z in range(center.z - radius, center.z + radius + 1):
            var manhattan := abs(x - center.x) + abs(z - center.z)
            if manhattan != radius:
                continue
            cells.append(Vector3i(x, center.y, z))
    return cells

func _on_player_move_requested(world_pos: Vector3) -> void:
    _active_move_target = world_pos
    _has_active_move_target = true
    _last_preview_signature = ""

func _on_player_movement_completed() -> void:
    _clear_active_move_target()

func _clear_active_move_target() -> void:
    _has_active_move_target = false
    _active_move_target = Vector3.ZERO
    _last_preview_signature = ""

func get_player() -> PlayerController3D:
    return _player

func get_camera() -> CameraController3D:
    return _camera_controller
