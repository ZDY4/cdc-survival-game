class_name CameraConfig3D
extends Resource

enum ProjectionType {
	ORTHOGRAPHIC,
	PERSPECTIVE
}

@export var projection_type: int = ProjectionType.PERSPECTIVE
@export var rotation: Vector3 = Vector3(-35, 0, 0)
@export var viewpoint_offset: Vector3 = Vector3(0, 0, 0)
@export var arm_length: float = 500
@export var min_zoom: float = 10.0
@export var max_zoom: float = 50.0
@export var initial_zoom: float = 20.0
@export var min_fov: float = 1.0
@export var max_fov: float = 90.0
@export var initial_fov: float = 20.0
@export var zoom_speed: float = 2.0
@export var zoom_smoothing: float = 0.1
@export var follow_smoothing: float = 0.1
