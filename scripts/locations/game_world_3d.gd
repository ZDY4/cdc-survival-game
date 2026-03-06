class_name GameWorld3D
extends Node3D

@export var player_scene: PackedScene = null
@export var show_grid_debug := false
@export var max_preview_path_points := 200
@export var max_preview_distance := 40.0

@onready var _camera_controller: CameraController3D
@onready var _player: PlayerController3D
@onready var _grid_floor: StaticBody3D
@onready var _path_preview: PathPreview
@onready var _navigator: GridNavigator

var _is_mouse_pressed := false
var _last_hover_pos: Vector3

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
                _handle_ground_click()
    
    if event is InputEventScreenTouch:
        if event.pressed:
            _handle_touch_click(event.position)

func _process(delta: float) -> void:
    _update_path_preview(delta)

var _last_preview_grid: Vector3i = Vector3i.ZERO
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
    
    var mouse_pos := get_viewport().get_mouse_position()
    var camera := get_viewport().get_camera_3d()
    
    if not camera:
        return
    if not GridMovementSystem or not GridMovementSystem.grid_world:
        return
    if not get_world_3d():
        return
    
    var from := camera.project_ray_origin(mouse_pos)
    var to := from + camera.project_ray_normal(mouse_pos) * 1000
    
    var space_state := get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.new()
    query.from = from
    query.to = to
    query.collision_mask = 1
    
    var result := space_state.intersect_ray(query)
    
    if result:
        var world_pos: Vector3 = result.position
        if _player.global_position.distance_to(world_pos) > max_preview_distance:
            _path_preview.hide_path()
            _last_preview_grid = Vector3i.ZERO
            return
        var current_grid := GridMovementSystem.world_to_grid(world_pos)
        
        # Only update if grid position changed
        if current_grid == _last_preview_grid:
            return
        _last_preview_grid = current_grid
        
        _last_hover_pos = world_pos
        
        var path := _navigator.find_path(
            _player.global_position,
            world_pos,
            GridMovementSystem.grid_world.is_walkable
        )
        
        if path.size() > max_preview_path_points:
            _path_preview.hide_path()
        elif path.size() > 1:
            _path_preview.show_path(path)
        else:
            _path_preview.hide_path()
    else:
        _path_preview.hide_path()
        _last_preview_grid = Vector3i.ZERO

func _handle_ground_click() -> void:
    var mouse_pos := get_viewport().get_mouse_position()
    _try_move_to_screen_position(mouse_pos)

func _handle_touch_click(screen_pos: Vector2) -> void:
    _try_move_to_screen_position(screen_pos)

func _try_move_to_screen_position(screen_pos: Vector2) -> void:
    var camera := get_viewport().get_camera_3d()
    if not camera:
        return
    if not GridMovementSystem or not GridMovementSystem.grid_world:
        return
    if not get_world_3d():
        return
    
    var from := camera.project_ray_origin(screen_pos)
    var to := from + camera.project_ray_normal(screen_pos) * 1000
    
    var space_state := get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.new()
    query.from = from
    query.to = to
    query.collision_mask = 1
    
    var result := space_state.intersect_ray(query)
    
    if result:
        var world_pos: Vector3 = result.position
        world_pos = GridMovementSystem.snap_to_grid(world_pos)
        _player.move_to(world_pos)
        
        EventBus.emit(EventBus.EventType.GRID_CLICKED, {
            "world_position": world_pos,
            "grid_position": GridMovementSystem.world_to_grid(world_pos)
        })

func get_player() -> PlayerController3D:
    return _player

func get_camera() -> CameraController3D:
    return _camera_controller
