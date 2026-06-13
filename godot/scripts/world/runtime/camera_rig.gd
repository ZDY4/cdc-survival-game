class_name WorldCameraRig
extends Node3D

const CameraRigController = preload("res://scripts/world/camera_rig_controller.gd")
const GRID_SIZE := 1.0
const LEVEL_PLANE_HEIGHT := GRID_SIZE * 0.5

var camera: Camera3D
var controller: RefCounted = CameraRigController.new()


func sync_camera(map_snapshot: Dictionary, focus_position: Vector3, viewport_size: Vector2) -> Dictionary:
	if camera == null or not is_instance_valid(camera):
		camera = Camera3D.new()
		camera.name = "WorldCamera"
		add_child(camera)
	camera.current = true
	var size := _dictionary_or_empty(map_snapshot.get("size", {}))
	var map_size := Vector2(float(size.get("width", 48)), float(size.get("height", 42)))
	controller.call("attach", camera, focus_position, map_size, viewport_size, LEVEL_PLANE_HEIGHT)
	return {"count": 1}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
