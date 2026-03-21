class_name PathPreviewSystem
extends Node

const PlayerController = preload("res://systems/player_controller.gd")
const GridNavigator = preload("res://systems/grid_navigator.gd")
const PathPreview = preload("res://systems/path_preview.gd")
const GridHoverCornerOverlay = preload("res://systems/grid_hover_corner_overlay.gd")
const InteractionSystem = preload("res://systems/interaction_system.gd")
const InteractableScript = preload("res://modules/interaction/interactable.gd")

@export var max_preview_path_points: int = 200
@export var max_preview_distance: float = 40.0
@export var interaction_preview_min_radius: int = 1
@export var interaction_preview_max_radius: int = 4
@export var preview_update_interval: float = 0.1
@export var hover_overlay_update_interval: float = 0.05
@export var hover_overlay_world_y_offset: float = 0.03

var _scene_root: Node3D = null
var _interaction_system: Node = null
var _navigator: GridNavigator = null
var _player: PlayerController = null
var _path_preview: PathPreview = null
var _hover_overlay: GridHoverCornerOverlay = null

var _preview_update_timer: float = 0.0
var _hover_overlay_update_timer: float = 0.0
var _last_preview_signature: String = ""
var _active_move_target: Vector3 = Vector3.ZERO
var _has_active_move_target: bool = false

func initialize(
    scene_root: Node3D,
    interaction_system: Node,
    navigator: GridNavigator,
    player: PlayerController,
    path_preview: PathPreview,
    hover_overlay: GridHoverCornerOverlay
) -> void:
    _scene_root = scene_root
    _interaction_system = interaction_system
    _navigator = navigator
    _player = player
    _path_preview = path_preview
    _hover_overlay = hover_overlay

func tick(delta: float) -> void:
    if not _scene_root or not _interaction_system or not _navigator or not _player or not _path_preview:
        _hide_hover_overlay()
        return
    if not GridMovementSystem or not GridMovementSystem.grid_world:
        _hide_hover_overlay()
        return
    if _player.is_world_input_blocked():
        clear_active_move_target()
        _hide_preview()
        _hide_hover_overlay()
        return

    _tick_hover_overlay(delta)

    _preview_update_timer += delta
    if _preview_update_timer < preview_update_interval:
        return
    _preview_update_timer = 0.0

    if _has_active_move_target and not _player.is_moving():
        clear_active_move_target()

    if _player.has_navigation_intent():
        var intent_path: Array[Vector3] = _player.get_navigation_intent_path()
        if intent_path.size() > max_preview_path_points:
            _hide_preview()
        elif not intent_path.is_empty():
            _update_preview_from_path(intent_path, "navigation_intent")
        else:
            _hide_preview()
        return

    if _player.is_moving() and _has_active_move_target:
        _update_preview_to_target(_active_move_target, false, "move_target")
        return

    var mouse_pos: Vector2 = _scene_root.get_viewport().get_mouse_position()
    var hover_hit: Dictionary = _interaction_system.raycast_screen_position(_scene_root, mouse_pos)
    if not hover_hit.is_empty():
        var interactable := _resolve_interactable_from_hit(hover_hit)
        if interactable != null:
            var interaction_target_data := _find_nearest_interaction_target(interactable, hover_hit.position)
            if bool(interaction_target_data.get("found", false)):
                var interaction_target: Vector3 = interaction_target_data.get("target", Vector3.ZERO)
                _update_preview_to_target(interaction_target, true, "interactable")
                return

    var ground_hit: Dictionary = _interaction_system.raycast_screen_position(_scene_root, mouse_pos, true, 1)
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

func hide_hover_overlay() -> void:
    _hide_hover_overlay()

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

    var path: Array[Vector3] = _navigator.find_path(
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

func _update_preview_from_path(path: Array[Vector3], mode: String) -> void:
    if path.is_empty():
        _hide_preview()
        return

    var player_grid := GridMovementSystem.world_to_grid(_player.global_position)
    var target_grid := GridMovementSystem.world_to_grid(path[path.size() - 1])
    var preview_signature := "%s|%s|%s|%d" % [mode, str(player_grid), str(target_grid), path.size()]
    if preview_signature == _last_preview_signature:
        return
    _last_preview_signature = preview_signature
    _path_preview.show_path(path)

func _hide_preview() -> void:
    _path_preview.hide_path()
    _last_preview_signature = ""

func _tick_hover_overlay(delta: float) -> void:
    _hover_overlay_update_timer += delta
    if _hover_overlay_update_timer < hover_overlay_update_interval:
        return
    _hover_overlay_update_timer = 0.0
    _update_hover_overlay()

func _update_hover_overlay() -> void:
    if not _hover_overlay:
        return
    if not _scene_root or not _interaction_system:
        _hide_hover_overlay()
        return

    var viewport := _scene_root.get_viewport()
    if not viewport:
        _hide_hover_overlay()
        return

    var camera := viewport.get_camera_3d()
    if not camera:
        _hide_hover_overlay()
        return

    var mouse_pos: Vector2 = viewport.get_mouse_position()
    var ground_hit: Dictionary = _interaction_system.raycast_screen_position(_scene_root, mouse_pos, true, 1)
    if ground_hit.is_empty() or not ground_hit.has("position"):
        _hide_hover_overlay()
        return

    var hit_pos: Vector3 = ground_hit.position
    var grid_pos := GridMovementSystem.world_to_grid(hit_pos)
    var corner_y := hit_pos.y + hover_overlay_world_y_offset
    var corners_world := _compute_grid_cell_world_corners(grid_pos, corner_y)
    _hover_overlay.show_cell(corners_world, camera)

func _hide_hover_overlay() -> void:
    if _hover_overlay:
        _hover_overlay.hide_cell()

func _compute_grid_cell_world_corners(grid_pos: Vector3i, world_y: float) -> Array[Vector3]:
    var center_world := GridMovementSystem.grid_to_world(grid_pos)
    var half_cell := GridNavigator.GRID_SIZE * 0.5
    return [
        Vector3(center_world.x - half_cell, world_y, center_world.z - half_cell),
        Vector3(center_world.x + half_cell, world_y, center_world.z - half_cell),
        Vector3(center_world.x + half_cell, world_y, center_world.z + half_cell),
        Vector3(center_world.x - half_cell, world_y, center_world.z + half_cell)
    ]


func _resolve_interactable_from_hit(hit: Dictionary) -> Node:
    if not hit.has("collider"):
        return null

    var node: Node = hit.collider as Node
    var component: Node = _find_interactable_component(node)
    if component != null:
        return component

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

func _find_interactable_component(node: Node) -> Node:
    if not node:
        return null
    if node is InteractableScript:
        return node
    for child in node.get_children():
        if child is InteractableScript:
            return child
    var current := node.get_parent()
    while current != null:
        if current is InteractableScript:
            return current
        for child in current.get_children():
            if child is InteractableScript:
                return child
        current = current.get_parent()
    return null

func _find_nearest_interaction_target(interactable: Node, hit_position: Vector3) -> Dictionary:
    var anchor_pos := hit_position
    if interactable is Node3D:
        anchor_pos = (interactable as Node3D).global_position

    var min_radius: int = interaction_preview_min_radius
    var max_radius: int = interaction_preview_max_radius
    var required_distance: float = -1.0
    if interactable.has_method("get_primary_option"):
        var primary_option = interactable.get_primary_option()
        if primary_option != null and primary_option.requires_proximity(interactable):
            anchor_pos = primary_option.get_interaction_anchor_position(interactable)
            required_distance = maxf(0.0, primary_option.get_required_distance(interactable))
            min_radius = 1
            max_radius = max(1, int(ceil(required_distance / GridNavigator.GRID_SIZE)))

    var player_grid := GridMovementSystem.world_to_grid(_player.global_position)
    var anchor_grid := GridMovementSystem.world_to_grid(anchor_pos)
    anchor_grid.y = player_grid.y

    var grid_world := GridMovementSystem.grid_world
    for radius in range(min_radius, max_radius + 1):
        var ring_cells := _collect_ring_cells(anchor_grid, radius)
        var best_path: Array[Vector3] = []
        var best_world := Vector3.ZERO

        for candidate_grid in ring_cells:
            if not grid_world.is_walkable(candidate_grid):
                continue
            var candidate_world := GridMovementSystem.grid_to_world(candidate_grid)
            if required_distance >= 0.0:
                var anchor_world := anchor_pos
                anchor_world.y = candidate_world.y
                if candidate_world.distance_to(anchor_world) > required_distance + 0.05:
                    continue
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
