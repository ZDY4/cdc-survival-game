class_name PlayerController3D
extends "res://systems/character_actor.gd"

const GridWorld = preload("res://systems/grid_world.gd")
const MovementComponent = preload("res://systems/movement_component.gd")
const InteractionSystem = preload("res://systems/interaction_system.gd")
const EquipmentSystem = preload("res://systems/equipment_system.gd")
const VisionSystemScript = preload("res://systems/vision_system.gd")

signal move_requested(world_pos: Vector3)
signal movement_completed
signal movement_step_completed(grid_pos: Vector3i, world_pos: Vector3, step_index: int, total_steps: int)

@onready var _movement_component: MovementComponent
@onready var _collision: CollisionShape3D

var _grid_world: GridWorld = null
var _equipment_system: Node = null
var _vision_system: Node = null

@export var vision_radius_tiles: int = 10

func _ready() -> void:
	super()
	add_to_group("player")
	set_placeholder_colors(Color(0.80, 0.90, 1.0, 1.0), Color(0.20, 0.60, 1.0, 1.0))
	_setup_collision()
	_setup_movement_component()
	_setup_equipment_system()
	_setup_vision_system()

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
	_movement_component.movement_step_completed.connect(_on_movement_step_completed)

func _setup_vision_system() -> void:
	if not _vision_system:
		var existing = find_children("*", "VisionSystem", true, false)
		if not existing.is_empty():
			_vision_system = existing[0]
		else:
			_vision_system = VisionSystemScript.new()
			_vision_system.name = "VisionSystem"
			add_child(_vision_system)
	_vision_system.vision_radius = vision_radius_tiles
	if _movement_component:
		_vision_system.bind_to_movement_component(_movement_component)

func _setup_equipment_system() -> void:
	_equipment_system = EquipmentSystem.new()
	_equipment_system.name = "EquipmentSystem"
	call_deferred("add_child", _equipment_system)

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
	if _vision_system and _movement_component:
		_vision_system.bind_to_movement_component(_movement_component)

func get_vision_system() -> Node:
	return _vision_system

func _on_move_requested(world_pos: Vector3) -> void:
	move_requested.emit(world_pos)

func _on_movement_finished() -> void:
	movement_completed.emit()
	EventBus.emit(EventBus.EventType.PLAYER_MOVED, {
		"position": global_position,
		"grid_position": get_grid_position()
	})

func _on_movement_step_completed(grid_pos: Vector3i, world_pos: Vector3, step_index: int, total_steps: int) -> void:
	movement_step_completed.emit(grid_pos, world_pos, step_index, total_steps)
