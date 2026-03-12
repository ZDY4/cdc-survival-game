class_name AISpawnSystem
extends Node

const AISpawnPoint = preload("res://systems/spawn/ai_spawn_point.gd")
const AIManager = preload("res://systems/ai/ai_manager.gd")

signal actor_spawned(spawn_id: String, actor: Node3D)
signal actor_despawned(spawn_id: String)

var _scene_root: Node = null
var _ai_manager: AIManager = null
var _spawn_points: Dictionary = {}
var _active_instances: Dictionary = {}
var _respawn_deadlines: Dictionary = {}

func _ready() -> void:
    _ai_manager = AIManager.new()
    add_child(_ai_manager)

func _process(_delta: float) -> void:
    if _respawn_deadlines.is_empty():
        return

    var now_s: float = float(Time.get_ticks_msec()) / 1000.0
    var due_spawn_ids: Array[String] = []
    for spawn_id in _respawn_deadlines.keys():
        if now_s >= float(_respawn_deadlines[spawn_id]):
            due_spawn_ids.append(spawn_id)

    for spawn_id in due_spawn_ids:
        _respawn_deadlines.erase(spawn_id)
        var point: AISpawnPoint = _spawn_points.get(spawn_id, null)
        if point:
            spawn_from_point(point)

func initialize(scene_root: Node) -> void:
    _scene_root = scene_root
    _rebuild_spawn_points()

func spawn_auto_points() -> void:
    _rebuild_spawn_points()
    for point in _spawn_points.values():
        if point.auto_spawn:
            spawn_from_point(point)

func spawn_from_point(point: AISpawnPoint) -> Node3D:
    if not point:
        return null

    var spawn_id := point.get_effective_spawn_id()
    if _active_instances.has(spawn_id):
        var existing: Node3D = _active_instances[spawn_id].get("node", null)
        if existing and is_instance_valid(existing):
            return existing
        _active_instances.erase(spawn_id)

    if point.character_id.is_empty():
        push_warning("[AISpawnSystem] character_id is empty for spawn point: %s" % spawn_id)
        return null

    var actor: Node3D = null
    var role_kind := point.role_kind.to_lower()
    var spawn_pos := point.get_spawn_position()
    var context := {
        "spawn_id": spawn_id
    }

    if _ai_manager and _ai_manager.has_method("is_character_id_valid_for_kind"):
        if not bool(_ai_manager.is_character_id_valid_for_kind(role_kind, point.character_id)):
            push_warning(
                "[AISpawnSystem] character_id '%s' does not match role_kind '%s' at spawn point: %s" %
                [point.character_id, role_kind, spawn_id]
            )
            return null

    match role_kind:
        "npc", "enemy":
            if _ai_manager:
                actor = _ai_manager.spawn_actor(role_kind, point.character_id, spawn_pos, context)
        _:
            push_warning("[AISpawnSystem] Unknown role_kind '%s' for spawn point: %s" % [role_kind, spawn_id])
            return null

    if not actor:
        return null

    if not actor.get_parent() and _scene_root:
        _scene_root.add_child(actor)

    _active_instances[spawn_id] = {
        "node": actor,
        "point": point
    }
    actor.tree_exited.connect(_on_actor_tree_exited.bind(spawn_id), CONNECT_ONE_SHOT)
    actor_spawned.emit(spawn_id, actor)
    return actor

func despawn_actor(spawn_id: String) -> void:
    if not _active_instances.has(spawn_id):
        return

    var entry: Dictionary = _active_instances[spawn_id]
    var actor: Node3D = entry.get("node", null)
    _active_instances.erase(spawn_id)

    if _ai_manager:
        _ai_manager.despawn_actor(spawn_id)
    elif actor and is_instance_valid(actor):
        actor.queue_free()

    actor_despawned.emit(spawn_id)

func _rebuild_spawn_points() -> void:
    _spawn_points.clear()
    if not _scene_root:
        return

    var points := _collect_spawn_points(_scene_root)
    for point in points:
        var spawn_id := point.get_effective_spawn_id()
        _spawn_points[spawn_id] = point

func _collect_spawn_points(root: Node) -> Array[AISpawnPoint]:
    var result: Array[AISpawnPoint] = []
    for child in root.get_children():
        if child is AISpawnPoint:
            result.append(child)
        result.append_array(_collect_spawn_points(child))
    return result

func _on_actor_tree_exited(spawn_id: String) -> void:
    if not _active_instances.has(spawn_id):
        return

    var entry: Dictionary = _active_instances[spawn_id]
    var point: AISpawnPoint = entry.get("point", null)
    _active_instances.erase(spawn_id)
    actor_despawned.emit(spawn_id)

    if not point or not is_instance_valid(point):
        return
    if not point.respawn_enabled:
        return

    _respawn_deadlines[spawn_id] = float(Time.get_ticks_msec()) / 1000.0 + maxf(point.respawn_delay, 0.0)
