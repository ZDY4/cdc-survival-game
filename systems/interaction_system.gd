class_name InteractionSystem
extends Node

func is_primary_pressed(event: InputEvent) -> bool:
    if event is InputEventMouseButton:
        return event.button_index == MOUSE_BUTTON_LEFT and event.pressed
    if event is InputEventScreenTouch:
        return event.pressed
    return false

func get_screen_position(event: InputEvent) -> Vector2:
    if event is InputEventMouseButton:
        return event.position
    if event is InputEventScreenTouch:
        return event.position
    return Vector2.ZERO

func raycast_screen_position(
    scene_root: Node,
    screen_pos: Vector2,
    use_collision_mask: bool = false,
    collision_mask: int = 1
) -> Dictionary:
    if not scene_root:
        return {}

    var camera := scene_root.get_viewport().get_camera_3d()
    if not camera:
        return {}
    if not scene_root.get_world_3d():
        return {}

    var from := camera.project_ray_origin(screen_pos)
    var to := from + camera.project_ray_normal(screen_pos) * 1000.0

    var query := PhysicsRayQueryParameters3D.new()
    query.from = from
    query.to = to
    if use_collision_mask:
        query.collision_mask = collision_mask

    return scene_root.get_world_3d().direct_space_state.intersect_ray(query)
