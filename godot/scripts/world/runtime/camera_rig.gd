class_name WorldCameraRig
extends Node3D

const CameraRigController = preload("res://scripts/world/camera_rig_controller.gd")
const GRID_SIZE := 1.0
const LEVEL_PLANE_HEIGHT := GRID_SIZE * 0.5

var camera: Camera3D
var controller: RefCounted = CameraRigController.new()
var current_map_id := ""


func sync_camera(map_snapshot: Dictionary, focus_position: Vector3, viewport_size: Vector2) -> Dictionary:
	var map_id := str(map_snapshot.get("map_id", map_snapshot.get("id", ""))).strip_edges()
	var map_changed := not map_id.is_empty() and map_id != current_map_id
	if camera == null or not is_instance_valid(camera):
		camera = Camera3D.new()
		camera.name = "WorldCamera"
		add_child(camera)
	if map_changed:
		current_map_id = map_id
		camera.set_meta("zoom_factor", 1.0)
		camera.set_meta("following_focus", true)
		camera.set_meta("follow_source", "map_changed")
		camera.set_meta("follow_actor_id", 0)
	camera.current = true
	var size := _dictionary_or_empty(map_snapshot.get("size", {}))
	var map_size := Vector2(float(size.get("width", 48)), float(size.get("height", 42)))
	controller.call("attach", camera, focus_position, map_size, viewport_size, LEVEL_PLANE_HEIGHT)
	return {"count": 1}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
