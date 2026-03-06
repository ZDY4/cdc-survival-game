class_name CameraController3D
extends Node3D

@export var target: Node3D = null
@export var isometric_rotation := Vector3(-45, 45, 0)
@export var min_zoom := 10.0
@export var max_zoom := 50.0
@export var zoom_speed := 2.0
@export var zoom_smoothing := 0.1
@export var follow_smoothing := 0.1
@export var initial_zoom := 20.0
@export var initial_offset := Vector3(20, 20, 20)

var _current_zoom: float
var _target_zoom: float
var _camera: Camera3D = null

func _ready() -> void:
    _camera = Camera3D.new()
    add_child(_camera)
    _camera.make_current()
    
    _camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    _current_zoom = initial_zoom
    _target_zoom = initial_zoom
    _camera.size = _current_zoom
    
    rotation_degrees = isometric_rotation
    
    if target:
        global_position = target.global_position + initial_offset
        look_at(target.global_position)

func _process(delta: float) -> void:
    _update_zoom(delta)
    _update_follow(delta)

func _input(event: InputEvent) -> void:
    _handle_zoom_input(event)

func _handle_zoom_input(event: InputEvent) -> void:
    if event.is_action_pressed("zoom_in"):
        _target_zoom = max(_target_zoom - zoom_speed, min_zoom)
    elif event.is_action_pressed("zoom_out"):
        _target_zoom = min(_target_zoom + zoom_speed, max_zoom)
    
    if event is InputEventMagnifyGesture:
        if event.factor > 1.0:
            _target_zoom = max(_target_zoom - zoom_speed, min_zoom)
        else:
            _target_zoom = min(_target_zoom + zoom_speed, max_zoom)

func _update_zoom(_delta: float) -> void:
    _current_zoom = lerp(_current_zoom, _target_zoom, zoom_smoothing)
    if _camera:
        _camera.size = _current_zoom

func _update_follow(_delta: float) -> void:
    if not target:
        return
    
    var target_pos := target.global_position + initial_offset
    global_position = lerp(global_position, target_pos, follow_smoothing)
    look_at(target.global_position)

func set_zoom(zoom: float) -> void:
    _target_zoom = clamp(zoom, min_zoom, max_zoom)

func get_zoom() -> float:
    return _current_zoom
