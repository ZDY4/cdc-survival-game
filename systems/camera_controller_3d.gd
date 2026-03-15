class_name CameraController3D
extends Node3D

const CameraConfig3D = preload("res://systems/camera_config_3d.gd")

@export var target: Node3D = null

var _config: CameraConfig3D = CameraConfig3D.new()
var _current_zoom: float = 0.0
var _target_zoom: float
var _camera: Camera3D = null
var _config_bound: bool = false

func _ready() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.make_current()
	_camera.near = 0.05
	_camera.far = 2000.0

	_bind_config_service()
	_reload_config_from_service()

func _exit_tree() -> void:
	if not _config_bound:
		return
	var config_service := _get_camera_config_service()
	if config_service and config_service.config_changed.is_connected(_on_config_changed):
		config_service.config_changed.disconnect(_on_config_changed)

func _process(delta: float) -> void:
	_update_zoom(delta)
	_update_follow(delta)

func _input(event: InputEvent) -> void:
	_handle_zoom_input(event)

func _handle_zoom_input(event: InputEvent) -> void:
	var min_value := _get_min_zoom_value()
	var max_value := _get_max_zoom_value()
	if event.is_action_pressed("zoom_in"):
		_target_zoom = max(_target_zoom - _config.zoom_speed, min_value)
	elif event.is_action_pressed("zoom_out"):
		_target_zoom = min(_target_zoom + _config.zoom_speed, max_value)

	if event is InputEventMagnifyGesture:
		if event.factor > 1.0:
			_target_zoom = max(_target_zoom - _config.zoom_speed, min_value)
		else:
			_target_zoom = min(_target_zoom + _config.zoom_speed, max_value)

func _update_zoom(delta: float) -> void:
	_current_zoom = lerp(_current_zoom, _target_zoom, _get_smoothing_weight(_config.zoom_smoothing, delta))
	_apply_zoom_value()

func _update_follow(delta: float) -> void:
	if not target:
		return

	var viewpoint_world := _get_viewpoint_world()
	var desired_camera_pos := viewpoint_world + _get_arm_direction_world() * _config.arm_length
	global_position = lerp(global_position, desired_camera_pos, _get_smoothing_weight(_config.follow_smoothing, delta))

func set_zoom(zoom: float) -> void:
	_target_zoom = clamp(zoom, _get_min_zoom_value(), _get_max_zoom_value())

func get_zoom() -> float:
	return _current_zoom

func _bind_config_service() -> void:
	var config_service := _get_camera_config_service()
	if not config_service:
		return
	if config_service.config_changed.is_connected(_on_config_changed):
		return
	config_service.config_changed.connect(_on_config_changed)
	_config_bound = true

func _on_config_changed() -> void:
	_reload_config_from_service()

func _reload_config_from_service() -> void:
	var config: CameraConfig3D = null
	var config_service := _get_camera_config_service()
	if config_service and config_service.has_method("get_effective_config"):
		config = config_service.get_effective_config()
	if not config:
		config = CameraConfig3D.new()
	_config = config
	rotation_degrees = _config.rotation
	_current_zoom = _get_initial_zoom_value()
	_target_zoom = _current_zoom
	_apply_projection_settings()
	if target:
		var viewpoint_world := _get_viewpoint_world()
		global_position = viewpoint_world + _get_arm_direction_world() * _config.arm_length

func _get_initial_zoom_value() -> float:
	if _config.projection_type == CameraConfig3D.ProjectionType.PERSPECTIVE:
		return clamp(_config.initial_fov, _config.min_fov, _config.max_fov)
	return clamp(_config.initial_zoom, _config.min_zoom, _config.max_zoom)

func _get_min_zoom_value() -> float:
	if _config.projection_type == CameraConfig3D.ProjectionType.PERSPECTIVE:
		return _config.min_fov
	return _config.min_zoom

func _get_max_zoom_value() -> float:
	if _config.projection_type == CameraConfig3D.ProjectionType.PERSPECTIVE:
		return _config.max_fov
	return _config.max_zoom

func _apply_projection_settings() -> void:
	if not _camera:
		return
	if _config.projection_type == CameraConfig3D.ProjectionType.PERSPECTIVE:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	else:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_apply_zoom_value()

func _apply_zoom_value() -> void:
	if not _camera:
		return
	if _config.projection_type == CameraConfig3D.ProjectionType.PERSPECTIVE:
		_camera.fov = _current_zoom
	else:
		_camera.size = _current_zoom

func _get_viewpoint_world() -> Vector3:
	if not target:
		return global_position
	return target.global_position + target.global_transform.basis * _config.viewpoint_offset

func _get_arm_direction_world() -> Vector3:
	var euler := Vector3(
		deg_to_rad(_config.rotation.x),
		deg_to_rad(_config.rotation.y),
		deg_to_rad(_config.rotation.z)
	)
	var arm_basis := Basis.from_euler(euler)
	return (arm_basis * Vector3.BACK).normalized()

func _get_smoothing_weight(smoothing: float, delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	if smoothing <= 0.0:
		return 1.0
	if smoothing >= 1.0:
		return 1.0
	# Convert the existing frame-based smoothing value into a frame-rate independent weight.
	return 1.0 - pow(1.0 - smoothing, delta * 60.0)

func _get_camera_config_service() -> Node:
	return get_node_or_null("/root/CameraConfigService")
