extends RefCounted

const CameraRigController = preload("res://scripts/world/camera_rig_controller.gd")

var rig_controller: RefCounted = CameraRigController.new()


func attach(camera: Camera3D, focus_position: Vector3, map_size: Vector2, viewport_size: Vector2, level_height: float) -> void:
	rig_controller.call("attach", camera, focus_position, map_size, viewport_size, level_height)


func process_follow(focus_position: Vector3, viewport_size: Vector2, level_height: float, follow_source: String = "focus_position", follow_actor_id: int = 0) -> void:
	rig_controller.call("process_follow", focus_position, viewport_size, level_height, follow_source, follow_actor_id)


func begin_drag(screen_position: Vector2, drag_plane_height: float) -> void:
	rig_controller.call("begin_drag", screen_position, drag_plane_height)


func drag_to_screen_position(screen_position: Vector2, drag_plane_height: float, viewport_size: Vector2, level_height: float) -> void:
	rig_controller.call("drag_to_screen_position", screen_position, drag_plane_height, viewport_size, level_height)


func end_drag() -> void:
	rig_controller.call("end_drag")


func set_dragging(value: bool) -> void:
	rig_controller.set("is_dragging", value)


func is_dragging() -> bool:
	return bool(rig_controller.get("is_dragging"))


func clear_drag_state() -> void:
	rig_controller.call("clear_drag_state")


func zoom_wheel(direction: float, viewport_size: Vector2, level_height: float) -> void:
	rig_controller.call("zoom_wheel", direction, viewport_size, level_height)


func scale_zoom(multiplier: float, viewport_size: Vector2, level_height: float) -> void:
	rig_controller.call("scale_zoom", multiplier, viewport_size, level_height)


func reset_zoom(viewport_size: Vector2, level_height: float) -> void:
	rig_controller.call("reset_zoom", viewport_size, level_height)


func focus(focus_position: Vector3, viewport_size: Vector2, level_height: float, follow_source: String = "focus_position", follow_actor_id: int = 0) -> void:
	rig_controller.call("focus", focus_position, viewport_size, level_height, follow_source, follow_actor_id)


func snapshot() -> Dictionary:
	if rig_controller == null or not rig_controller.has_method("snapshot"):
		return {"has_camera": false, "reason": "camera_rig_snapshot_missing"}
	return rig_controller.call("snapshot")
