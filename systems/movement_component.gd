class_name MovementComponent
extends Node

const GridMovement = preload("res://systems/grid_movement.gd")
const GridNavigator = preload("res://systems/grid_navigator.gd")
const GridWorld = preload("res://systems/grid_world.gd")

signal move_requested(world_pos: Vector3)
signal move_started(path: Array[Vector3])
signal move_finished
signal move_cancelled
signal move_failed(target_pos: Vector3)

@export var step_duration: float = 0.25

var _grid_world: GridWorld = null
var _navigator: GridNavigator = null
var _grid_movement: GridMovement = null
var _owner_node: Node3D = null

func _ready() -> void:
    _navigator = GridNavigator.new()
    _grid_movement = GridMovement.new()
    _grid_movement.step_duration = step_duration
    add_child(_grid_movement)

    _grid_movement.movement_started.connect(_on_movement_started)
    _grid_movement.movement_finished.connect(_on_movement_finished)
    _grid_movement.movement_cancelled.connect(_on_movement_cancelled)

func initialize(owner_node: Node3D, grid_world: GridWorld) -> void:
    _owner_node = owner_node
    _grid_world = grid_world

func set_grid_world(grid_world: GridWorld) -> void:
    _grid_world = grid_world

func move_to(world_pos: Vector3) -> bool:
    if not _owner_node or not _grid_world or not _navigator or not _grid_movement:
        move_failed.emit(world_pos)
        return false

    var start_pos := _owner_node.global_position
    var target_pos := world_pos
    target_pos.y = start_pos.y

    var path := _navigator.find_path(start_pos, target_pos, _grid_world.is_walkable)
    if path.is_empty():
        move_failed.emit(target_pos)
        return false

    for i in range(path.size()):
        var point: Vector3 = path[i]
        point.y = start_pos.y
        path[i] = point

    move_requested.emit(target_pos)
    _grid_movement.move_along_path(path, _owner_node)
    return true

func cancel() -> void:
    if _grid_movement:
        _grid_movement.cancel_movement()

func is_moving() -> bool:
    return _grid_movement != null and _grid_movement.is_moving()

func _on_movement_started(path: Array[Vector3]) -> void:
    move_started.emit(path)

func _on_movement_finished() -> void:
    move_finished.emit()

func _on_movement_cancelled() -> void:
    move_cancelled.emit()
