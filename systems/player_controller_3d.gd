class_name PlayerController3D
extends "res://systems/character_actor.gd"

const GridWorld = preload("res://systems/grid_world.gd")
const MovementComponent = preload("res://systems/movement_component.gd")
const InteractionSystem = preload("res://systems/interaction_system.gd")

signal move_requested(world_pos: Vector3)
signal movement_completed

@onready var _movement_component: MovementComponent
@onready var _collision: CollisionShape3D

var _grid_world: GridWorld = null

func _ready() -> void:
    super()
    set_placeholder_colors(Color(0.80, 0.90, 1.0, 1.0), Color(0.20, 0.60, 1.0, 1.0))
    _setup_collision()
    _setup_movement_component()
    
    if not _grid_world:
        _grid_world = GridWorld.new()
    _movement_component.set_grid_world(_grid_world)

func _setup_collision() -> void:
    _collision = CollisionShape3D.new()
    add_child(_collision)
    
    var shape := CylinderShape3D.new()
    shape.radius = 0.3
    shape.height = 1.0
    _collision.shape = shape

func _setup_movement_component() -> void:
    _movement_component = MovementComponent.new()
    add_child(_movement_component)
    _movement_component.initialize(self, _grid_world)
    _movement_component.move_requested.connect(_on_move_requested)
    _movement_component.move_finished.connect(_on_movement_finished)

func move_to(world_pos: Vector3) -> bool:
    if not _movement_component:
        return false
    return _movement_component.move_to(world_pos)

func move_to_screen_position(screen_pos: Vector2, interaction_system: InteractionSystem, scene_root: Node) -> bool:
    if not interaction_system or not scene_root or not _grid_world:
        return false

    var ground_hit := interaction_system.raycast_screen_position(scene_root, screen_pos, true, 1)
    if ground_hit.is_empty():
        return false

    var world_pos: Vector3 = ground_hit.position
    world_pos.y = global_position.y
    var snapped_pos := GridMovementSystem.snap_to_grid(world_pos)
    snapped_pos.y = global_position.y
    var started := move_to(snapped_pos)
    if not started:
        return false

    EventBus.emit(EventBus.EventType.GRID_CLICKED, {
        "world_position": snapped_pos,
        "grid_position": GridMovementSystem.world_to_grid(snapped_pos)
    })
    return true

func cancel_movement() -> void:
    if _movement_component:
        _movement_component.cancel()

func is_moving() -> bool:
    return _movement_component != null and _movement_component.is_moving()

func get_grid_position() -> Vector3i:
    return GridMovementSystem.world_to_grid(global_position)

func get_grid_world() -> GridWorld:
    return _grid_world

func set_grid_world(world: GridWorld) -> void:
    _grid_world = world
    if _movement_component:
        _movement_component.set_grid_world(world)

func _on_move_requested(world_pos: Vector3) -> void:
    move_requested.emit(world_pos)

func _on_movement_finished() -> void:
    movement_completed.emit()
    EventBus.emit(EventBus.EventType.PLAYER_MOVED, {
        "position": global_position,
        "grid_position": get_grid_position()
    })
