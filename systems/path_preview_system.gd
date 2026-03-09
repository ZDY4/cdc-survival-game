class_name PathPreviewSystem
extends Node

const PlayerController3D = preload("res://systems/player_controller_3d.gd")
const GridNavigator = preload("res://systems/grid_navigator.gd")
const PathPreview = preload("res://systems/path_preview.gd")
const InteractionSystem = preload("res://systems/interaction_system.gd")

@export var max_preview_path_points: int = 200
@export var max_preview_distance: float = 40.0
@export var interaction_preview_min_radius: int = 1
@export var interaction_preview_max_radius: int = 4
@export var preview_update_interval: float = 0.1

var _scene_root: Node3D = null
var _interaction_system: InteractionSystem = null
var _navigator: GridNavigator = null
var _player: PlayerController3D = null
var _path_preview: PathPreview = null

var _preview_update_timer: float = 0.0
var _last_preview_signature: String = ""
var _active_move_target: Vector3 = Vector3.ZERO
var _has_active_move_target: bool = false

func initialize(
    scene_root: Node3D,
    interaction_system: InteractionSystem,
    navigator: GridNavigator,
    player: PlayerController3D,
    path_preview: PathPreview
) -> void:
    _scene_root = scene_root
    _interaction_system = interaction_system
    _navigator = navigator
    _player = player
    _path_preview = path_preview

func tick(delta: float) -> void:
    if not _scene_root or not _interaction_system or not _navigator or not _player or not _path_preview:
        return
    if not GridMovementSystem or not GridMovementSystem.grid_world:
        return

    _preview_update_timer += delta
    if _preview_update_timer < preview_update_interval:
        return
    _preview_update_timer = 0.0

    if _has_active_move_target and not _player.is_moving():
        clear_active_move_target()

    if _player.is_moving() and _has_active_move_target:
        _update_preview_to_target(_active_move_target, false, "move_target")
        return

    var mouse_pos := _scene_root.get_viewport().get_mouse_position()
    var hover_hit := _interaction_system.raycast_screen_position(_scene_root, mouse_pos)
    if not hover_hit.is_empty():
        var interactable := _resolve_interactable_from_hit(hover_hit)
        if interactable != null:
            var interaction_target_data := _find_nearest_interaction_target(interactable, hover_hit.position)
            if bool(interaction_target_data.get("found", false)):
                var interaction_target: Vector3 = interaction_target_data.get("target", Vector3.ZERO)
                _update_preview_to_target(interaction_target, true, "interactable")
                return

    var ground_hit := _interaction_system.raycast_screen_position(_scene_root, mouse_pos, true, 1)
    if ground_hit.is_empty():
        _hide_preview()
        return

    var world_pos: Vector3 = ground_hit.position
    _update_preview_to_target(world_pos, true, "mouse")

func on_move_requested(world_pos: Vector3) -> void:
    _active_move_target = world_pos
    _has_active_move_target = true
    _last_preview_signature = ""

func on_movement_completed() -> void:
    clear_active_move_target()

func clear_active_move_target() -> void:
    _has_active_move_target = false
    _active_move_target = Vector3.ZERO
    _last_preview_signature = ""

func _update_preview_to_target(target_world_pos: Vector3, limit_distance: bool, mode: String) -> void:
    if limit_distance and _player.global_position.distance_to(target_world_pos) > max_preview_distance:
        _hide_preview()
        return

    var preview_target := target_world_pos
    preview_target.y = _player.global_position.y

    var player_grid := GridMovementSystem.world_to_grid(_player.global_position)
    var target_grid := GridMovementSystem.world_to_grid(preview_target)
    var preview_signature := "%s|%s|%s" % [mode, str(player_grid), str(target_grid)]
    if preview_signature == _last_preview_signature:
        return
    _last_preview_signature = preview_signature

    var path := _navigator.find_path(
        _player.global_position,
        preview_target,
        GridMovementSystem.grid_world.is_walkable
    )

    if path.size() > max_preview_path_points:
        _hide_preview()
    elif path.size() > 1:
        _path_preview.show_path(path)
    else:
        _hide_preview()

func _hide_preview() -> void:
    _path_preview.hide_path()
    _last_preview_signature = ""

func _resolve_interactable_from_hit(hit: Dictionary) -> Node:
    if not hit.has("collider"):
        return null

    var node := hit.collider as Node
    while node != null:
        if node.is_in_group("interactable"):
            return node
        if node.has_signal("interacted"):
            return node
        if node.has_method("get_interaction_name"):
            return node
        if node.has_meta("interactable") and bool(node.get_meta("interactable")):
            return node
        if node.has_meta("npc_id"):
            return node
        node = node.get_parent()

    return null

func _find_nearest_interaction_target(interactable: Node, hit_position: Vector3) -> Dictionary:
    var anchor_pos := hit_position
    if interactable is Node3D:
        anchor_pos = (interactable as Node3D).global_position

    var player_grid := GridMovementSystem.world_to_grid(_player.global_position)
    var anchor_grid := GridMovementSystem.world_to_grid(anchor_pos)
    anchor_grid.y = player_grid.y

    var grid_world := GridMovementSystem.grid_world
    for radius in range(interaction_preview_min_radius, interaction_preview_max_radius + 1):
        var ring_cells := _collect_ring_cells(anchor_grid, radius)
        var best_path: Array[Vector3] = []
        var best_world := Vector3.ZERO

        for candidate_grid in ring_cells:
            if not grid_world.is_walkable(candidate_grid):
                continue
            var candidate_world := GridMovementSystem.grid_to_world(candidate_grid)
            var path := _navigator.find_path(
                _player.global_position,
                candidate_world,
                grid_world.is_walkable
            )
            if path.size() <= 1:
                continue
            if best_path.is_empty() or path.size() < best_path.size():
                best_path = path
                best_world = candidate_world

        if not best_path.is_empty():
            return {
                "found": true,
                "target": best_world
            }

    return {"found": false}

func _collect_ring_cells(center: Vector3i, radius: int) -> Array[Vector3i]:
    var cells: Array[Vector3i] = []
    for x in range(center.x - radius, center.x + radius + 1):
        for z in range(center.z - radius, center.z + radius + 1):
            var manhattan: int = int(abs(x - center.x) + abs(z - center.z))
            if manhattan != radius:
                continue
            cells.append(Vector3i(x, center.y, z))
    return cells
