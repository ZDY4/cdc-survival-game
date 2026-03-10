class_name PlayerController3D
extends "res://systems/character_actor.gd"

const GridWorld = preload("res://systems/grid_world.gd")
const GridNavigator = preload("res://systems/grid_navigator.gd")
const MovementComponent = preload("res://systems/movement_component.gd")
const InteractionSystem = preload("res://systems/interaction_system.gd")
const EquipmentSystem = preload("res://systems/equipment_system.gd")
const VisionSystemScript = preload("res://systems/vision_system.gd")
const Interactable = preload("res://modules/interaction/interactable.gd")
const PathPreviewSystem = preload("res://systems/path_preview_system.gd")
const PathPreview = preload("res://systems/path_preview.gd")

signal move_requested(world_pos: Vector3)
signal movement_completed
signal movement_step_completed(grid_pos: Vector3i, world_pos: Vector3, step_index: int, total_steps: int)

@onready var _movement_component: MovementComponent
@onready var _collision: CollisionShape3D

var _grid_world: GridWorld = null
var _equipment_system: Node = null
var _vision_system: Node = null
var _scene_root: Node = null
var _npc_interaction_system: Node = null
var _path_preview_system: PathPreviewSystem = null
var _navigator: GridNavigator = null
var _path_preview: PathPreview = null

@export var max_preview_path_points: int = 200
@export var max_preview_distance: float = 40.0
@export var interaction_preview_min_radius: int = 1
@export var interaction_preview_max_radius: int = 4

@export var vision_radius_tiles: int = 10

func _ready() -> void:
	super()
	add_to_group("player")
	set_process_input(true)
	set_process(true)
	set_placeholder_colors(Color(0.80, 0.90, 1.0, 1.0), Color(0.20, 0.60, 1.0, 1.0))
	_setup_collision()
	_setup_movement_component()
	_setup_equipment_system()
	_setup_vision_system()
	_setup_path_preview_system()

	if not _grid_world:
		_grid_world = GridWorld.new()
	_movement_component.set_grid_world(_grid_world)

func _input(event: InputEvent) -> void:
	if not _scene_root:
		return
	var interaction_system := get_interaction_system()
	if not interaction_system:
		return
	handle_input(event)

func _process(delta: float) -> void:
	if _path_preview_system:
		_path_preview_system.tick(delta)

func set_interaction_context(scene_root: Node, npc_interaction_system: Node) -> void:
	_scene_root = scene_root
	_npc_interaction_system = npc_interaction_system
	_initialize_path_preview_system()

func configure_path_preview_settings(
	max_points: int,
	max_distance: float,
	min_radius: int,
	max_radius: int
) -> void:
	max_preview_path_points = max_points
	max_preview_distance = max_distance
	interaction_preview_min_radius = min_radius
	interaction_preview_max_radius = max_radius
	_apply_preview_settings()

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

func handle_input(event: InputEvent) -> bool:
	var interaction_system := get_interaction_system()
	if not interaction_system or not _scene_root:
		return false
	if handle_secondary_input(event):
		return true

	if not interaction_system.is_primary_pressed(event):
		return false

	var screen_pos := interaction_system.get_screen_position(event)
	if is_moving():
		cancel_movement()
		if _path_preview_system:
			_path_preview_system.clear_active_move_target()
		return true

	if _try_interact_screen_position(screen_pos, interaction_system, _scene_root):
		return true

	if _npc_interaction_system and _npc_interaction_system.has_method("try_interact"):
		if _npc_interaction_system.try_interact(screen_pos):
			return true

	return move_to_screen_position(screen_pos, interaction_system, _scene_root)

func handle_secondary_input(event: InputEvent) -> bool:
	if not _is_secondary_pressed(event):
		return false
	var interaction_system := get_interaction_system()
	if not interaction_system or not _scene_root:
		return true
	var screen_pos := interaction_system.get_screen_position(event)
	call_deferred("_show_interaction_options", screen_pos, interaction_system, _scene_root)
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

func _show_interaction_options(screen_pos: Vector2, interaction_system: InteractionSystem, scene_root: Node) -> void:
	if not interaction_system or not scene_root or not DialogModule:
		return
	var hit := interaction_system.raycast_screen_position(scene_root, screen_pos)
	if hit.is_empty():
		return

	var interactable := _resolve_interactable_from_hit(scene_root, hit)
	if not interactable:
		return
	if not interactable.has_method("get_available_options"):
		return

	var options: Array = interactable.get_available_options()
	if options.is_empty():
		return

	var option_names: Array[String] = []
	for option in options:
		if option:
			option_names.append(option.get_option_name(interactable))
	if option_names.is_empty():
		return

	var chosen_index: int = await DialogModule.show_choices(option_names)
	if chosen_index < 0 or chosen_index >= options.size():
		return
	var chosen = options[chosen_index]
	if not chosen:
		return
	if interactable.has_method("execute_option"):
		interactable.execute_option(chosen)
	elif interactable.has_method("_execute_option"):
		interactable._execute_option(chosen)

func _setup_path_preview_system() -> void:
	_navigator = GridNavigator.new()
	_path_preview = PathPreview.new()
	_path_preview.name = "PathPreview"
	_path_preview.top_level = true
	add_child(_path_preview)

	_path_preview_system = PathPreviewSystem.new()
	add_child(_path_preview_system)
	move_requested.connect(_path_preview_system.on_move_requested)
	movement_completed.connect(_path_preview_system.on_movement_completed)
	_apply_preview_settings()

func _initialize_path_preview_system() -> void:
	if not _scene_root or not _path_preview_system:
		return
	var interaction_system := get_interaction_system()
	if not interaction_system:
		return
	_path_preview_system.initialize(_scene_root, interaction_system, _navigator, self, _path_preview)
	_apply_preview_settings()

func _apply_preview_settings() -> void:
	if not _path_preview_system:
		return
	_path_preview_system.max_preview_path_points = max_preview_path_points
	_path_preview_system.max_preview_distance = max_preview_distance
	_path_preview_system.interaction_preview_min_radius = interaction_preview_min_radius
	_path_preview_system.interaction_preview_max_radius = interaction_preview_max_radius

func _try_interact_screen_position(
	screen_pos: Vector2,
	interaction_system: InteractionSystem,
	scene_root: Node
) -> bool:
	if not interaction_system or not scene_root:
		return false
	var hit := interaction_system.raycast_screen_position(scene_root, screen_pos)
	if hit.is_empty():
		return false

	var interactable := _resolve_interactable_from_hit(hit)
	if not interactable:
		return false

	if interactable.has_method("interact_primary"):
		return bool(interactable.interact_primary())
	if interactable.has_signal("interacted"):
		interactable.interacted.emit()
		return true
	if interactable.has_method("_on_click"):
		interactable._on_click()
		return true
	return false

func _resolve_interactable_from_hit(hit: Dictionary) -> Node:
	if not hit.has("collider"):
		return null
	var node := hit.collider as Node
	var component := _find_interactable_component(node)
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

func _find_interactable_component(node: Node) -> Interactable:
	if not node:
		return null
	if node is Interactable:
		return node
	for child in node.get_children():
		if child is Interactable:
			return child
	var current := node.get_parent()
	while current != null:
		if current is Interactable:
			return current
		for child in current.get_children():
			if child is Interactable:
				return child
		current = current.get_parent()
	return null

func _is_secondary_pressed(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_RIGHT and event.pressed
	return false
