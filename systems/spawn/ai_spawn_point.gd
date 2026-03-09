class_name AISpawnPoint
extends Marker3D

@export var spawn_id: String = ""
@export_enum("npc", "enemy") var role_kind: String = "npc"
@export var role_id: String = ""
@export var auto_spawn: bool = true
@export var respawn_enabled: bool = false
@export var respawn_delay: float = 10.0
@export var spawn_radius: float = 0.0

func get_effective_spawn_id() -> String:
    if spawn_id.is_empty():
        return name
    return spawn_id

func get_spawn_position() -> Vector3:
    if spawn_radius <= 0.0:
        return global_position

    var offset := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.0, spawn_radius)
    return global_position + Vector3(offset.x, 0.0, offset.y)
