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


func snapshot() -> Dictionary:
	var output: Dictionary = _dictionary_or_empty(controller.call("snapshot")) if controller != null and controller.has_method("snapshot") else {}
	output["has_camera"] = camera != null and is_instance_valid(camera)
	output["camera_node_path"] = str(camera.get_path()) if camera != null and is_instance_valid(camera) else ""
	if camera != null and is_instance_valid(camera):
		output["following_focus"] = bool(camera.get_meta("following_focus", output.get("following_focus", false)))
		output["follow_source"] = str(camera.get_meta("follow_source", output.get("follow_source", "")))
		output["follow_actor_id"] = int(camera.get_meta("follow_actor_id", output.get("follow_actor_id", 0)))
		output["follow_node_active"] = bool(camera.get_meta("follow_node_active", output.get("follow_node_active", false)))
		output["follow_node_instance_id"] = int(camera.get_meta("follow_node_instance_id", output.get("follow_node_instance_id", 0)))
		output["focus_position"] = camera.get_meta("focus_position", output.get("focus_position", Vector3.ZERO))
		output["zoom_factor"] = float(camera.get_meta("zoom_factor", output.get("zoom_factor", 1.0)))
		output["camera_position"] = camera.global_position
		output["camera_instance_id"] = camera.get_instance_id()
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
