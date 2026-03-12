class_name PlayerController
extends "res://systems/character_actor.gd"

const GridWorld = preload("res://systems/grid_world.gd")
const GridNavigator = preload("res://systems/grid_navigator.gd")
const MovementComponent = preload("res://systems/movement_component.gd")
const EquipmentSystem = preload("res://systems/equipment_system.gd")
const VisionSystemScript = preload("res://systems/vision_system.gd")
const Interactable = preload("res://modules/interaction/interactable.gd")
const PathPreviewSystem = preload("res://systems/path_preview_system.gd")
const PathPreview = preload("res://systems/path_preview.gd")
const GridHoverCornerOverlay = preload("res://systems/grid_hover_corner_overlay.gd")

signal move_requested(world_pos: Vector3)
signal movement_completed
signal movement_step_completed(grid_pos: Vector3i, world_pos: Vector3, step_index: int, total_steps: int)

@onready var _movement_component: MovementComponent
@onready var _collision: CollisionShape3D

var _grid_world: GridWorld = null
var _equipment_system: Node = null
var _vision_system: Node = null
var _scene_root: Node = null
var _path_preview_system: PathPreviewSystem = null
var _navigator: GridNavigator = null
var _path_preview: PathPreview = null
var _hover_corner_overlay: GridHoverCornerOverlay = null
var _is_interaction_in_progress: bool = false
var _is_dialog_active: bool = false
var _interaction_state_tag_applied: bool = false
var _interaction_target_actor: CharacterActor = null
var _interaction_target_state_tag_applied: bool = false
var _active_hover_cursor: Texture2D = null
var _active_hover_hotspot: Vector2 = Vector2.ZERO
var _hover_cursor_update_timer: float = 0.0

@export var max_preview_path_points: int = 200
@export var max_preview_distance: float = 40.0
@export var interaction_preview_min_radius: int = 1
@export var interaction_preview_max_radius: int = 4
@export var hover_cursor_update_interval: float = 0.05

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
	_setup_dialog_state_tracking()

	if not _grid_world:
		_grid_world = GridWorld.new()
	_movement_component.set_grid_world(_grid_world)

func _input(event: InputEvent) -> void:
	if not _scene_root:
		return
	var interaction_system := get_interaction_system()
	if not interaction_system:
		return
	if event is InputEventMouseMotion:
		_update_hover_cursor()
	handle_input(event)

func _process(delta: float) -> void:
	if _path_preview_system:
		_path_preview_system.tick(delta)
	_hover_cursor_update_timer += delta
	if _hover_cursor_update_timer >= hover_cursor_update_interval:
		_hover_cursor_update_timer = 0.0
		_update_hover_cursor()
	if _interaction_target_actor != null and not is_instance_valid(_interaction_target_actor):
		_interaction_target_actor = null
		_interaction_target_state_tag_applied = false

func set_interaction_context(scene_root: Node) -> void:
	_scene_root = scene_root
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

func is_movement_input_blocked() -> bool:
	return _is_interaction_in_progress or _is_dialog_active

func _setup_collision() -> void:
	_collision = CollisionShape3D.new()
	add_child(_collision)

	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = 1.0
	_collision.shape = shape
	_collision.position = Vector3(0.0, shape.height * 0.5, 0.0)

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
	if is_movement_input_blocked():
		return false
	if not _movement_component:
		return false
	return _movement_component.move_to(world_pos)

func move_to_screen_position(screen_pos: Vector2, interaction_system: InteractionSystem, scene_root: Node) -> bool:
	if is_movement_input_blocked():
		return false
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
	if is_movement_input_blocked():
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

	var interactable := _resolve_interactable_from_hit(hit)
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

	_set_interaction_target_from_interactable(interactable)
	_set_interaction_in_progress(true)
	var chosen_index: int = await DialogModule.show_choices(option_names)
	_set_interaction_in_progress(false)
	if chosen_index < 0 or chosen_index >= options.size():
		return
	var chosen = options[chosen_index]
	if not chosen:
		return
	_set_interaction_target_from_interactable(interactable)
	if interactable.has_method("execute_option"):
		interactable.execute_option(chosen)
	elif interactable.has_method("_execute_option"):
		interactable._execute_option(chosen)
	if not is_movement_input_blocked():
		_set_interaction_target_actor(null)

func _setup_dialog_state_tracking() -> void:
	if not DialogModule:
		return
	if DialogModule.has_signal("dialog_started") and not DialogModule.dialog_started.is_connected(_on_dialog_started):
		DialogModule.dialog_started.connect(_on_dialog_started)
	if DialogModule.has_signal("dialog_hidden") and not DialogModule.dialog_hidden.is_connected(_on_dialog_hidden):
		DialogModule.dialog_hidden.connect(_on_dialog_hidden)
	if DialogModule.has_method("is_dialog_active"):
		_is_dialog_active = bool(DialogModule.is_dialog_active())
		_refresh_movement_block_state()

func _set_interaction_in_progress(is_in_progress: bool) -> void:
	if _is_interaction_in_progress == is_in_progress:
		return
	_is_interaction_in_progress = is_in_progress
	_refresh_movement_block_state()

func _on_dialog_started(_text: String, _speaker: String) -> void:
	_is_dialog_active = true
	_refresh_movement_block_state()

func _on_dialog_hidden() -> void:
	_is_dialog_active = false
	_refresh_movement_block_state()

func _refresh_movement_block_state() -> void:
	_sync_interaction_state_tags()
	if not is_movement_input_blocked():
		_update_hover_cursor()
		return
	if is_moving():
		cancel_movement()
	if _path_preview_system:
		_path_preview_system.clear_active_move_target()
	if _path_preview:
		_path_preview.hide_path()
	if _path_preview_system:
		_path_preview_system.hide_hover_overlay()
	_apply_hover_cursor(null, Vector2.ZERO)

func _sync_interaction_state_tags() -> void:
	var blocked: bool = is_movement_input_blocked()
	if blocked:
		if not _interaction_state_tag_applied:
			begin_interaction_state()
			_interaction_state_tag_applied = true
		if _interaction_target_actor != null and is_instance_valid(_interaction_target_actor):
			if not _interaction_target_state_tag_applied:
				_interaction_target_actor.begin_interaction_state()
				_interaction_target_state_tag_applied = true
		elif _interaction_target_state_tag_applied:
			_interaction_target_state_tag_applied = false
		return

	if _interaction_state_tag_applied:
		end_interaction_state()
		_interaction_state_tag_applied = false
	if _interaction_target_state_tag_applied and _interaction_target_actor != null and is_instance_valid(_interaction_target_actor):
		_interaction_target_actor.end_interaction_state()
	_interaction_target_state_tag_applied = false
	_interaction_target_actor = null

func _setup_path_preview_system() -> void:
	_navigator = GridNavigator.new()
	_path_preview = PathPreview.new()
	_path_preview.name = "PathPreview"
	_path_preview.top_level = true
	add_child(_path_preview)

	_hover_corner_overlay = GridHoverCornerOverlay.new()
	_hover_corner_overlay.name = "GridHoverCornerOverlay"
	add_child(_hover_corner_overlay)

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
	_attach_hover_overlay_to_scene_root()
	_path_preview_system.initialize(
		_scene_root,
		interaction_system,
		_navigator,
		self,
		_path_preview,
		_hover_corner_overlay
	)
	_apply_preview_settings()

func _attach_hover_overlay_to_scene_root() -> void:
	if not _hover_corner_overlay or not _scene_root:
		return
	if _hover_corner_overlay.get_parent() == _scene_root:
		return
	var current_parent := _hover_corner_overlay.get_parent()
	if current_parent:
		current_parent.remove_child(_hover_corner_overlay)
	_scene_root.add_child(_hover_corner_overlay)

func _apply_preview_settings() -> void:
	if not _path_preview_system:
		return
	_path_preview_system.max_preview_path_points = max_preview_path_points
	_path_preview_system.max_preview_distance = max_preview_distance
	_path_preview_system.interaction_preview_min_radius = interaction_preview_min_radius
	_path_preview_system.interaction_preview_max_radius = interaction_preview_max_radius

func _update_hover_cursor() -> void:
	if not _scene_root:
		_apply_hover_cursor(null, Vector2.ZERO)
		_hide_hover_overlay()
		return
	if is_movement_input_blocked():
		_apply_hover_cursor(null, Vector2.ZERO)
		_hide_hover_overlay()
		return

	var interaction_system := get_interaction_system()
	if not interaction_system:
		_apply_hover_cursor(null, Vector2.ZERO)
		_hide_hover_overlay()
		return

	var viewport := _scene_root.get_viewport()
	if not viewport:
		_apply_hover_cursor(null, Vector2.ZERO)
		_hide_hover_overlay()
		return
	if _is_hovering_blocking_ui(viewport):
		_apply_hover_cursor(null, Vector2.ZERO)
		_hide_hover_overlay()
		return

	var mouse_pos := viewport.get_mouse_position()
	var hit := interaction_system.raycast_screen_position(_scene_root, mouse_pos)
	if hit.is_empty():
		_apply_hover_cursor(null, Vector2.ZERO)
		_update_hover_overlay_from_mouse(interaction_system, viewport)
		return

	var interactable := _resolve_interactable_from_hit(hit)
	if not interactable:
		_apply_hover_cursor(null, Vector2.ZERO)
		_update_hover_overlay_from_mouse(interaction_system, viewport)
		return
	if not interactable.has_method("get_available_options"):
		_apply_hover_cursor(null, Vector2.ZERO)
		_update_hover_overlay_from_mouse(interaction_system, viewport)
		return

	var options: Array = interactable.get_available_options()
	if options.is_empty():
		_apply_hover_cursor(null, Vector2.ZERO)
		_update_hover_overlay_from_mouse(interaction_system, viewport)
		return

	var option := options[0] as InteractionOption
	if not option:
		_apply_hover_cursor(null, Vector2.ZERO)
		_update_hover_overlay_from_mouse(interaction_system, viewport)
		return

	var cursor_texture := option.get_cursor_texture(interactable)
	var cursor_hotspot := option.get_cursor_hotspot(interactable)
	_apply_hover_cursor(cursor_texture, cursor_hotspot)
	_update_hover_overlay_from_mouse(interaction_system, viewport)

func _update_hover_overlay_from_mouse(interaction_system: InteractionSystem, viewport: Viewport) -> void:
	if not _hover_corner_overlay or not _scene_root or not interaction_system or not viewport:
		return
	var camera := viewport.get_camera_3d()
	if not camera:
		_hide_hover_overlay()
		return
	var mouse_pos := viewport.get_mouse_position()
	var ground_hit := interaction_system.raycast_screen_position(_scene_root, mouse_pos, true, 1)
	if ground_hit.is_empty() or not ground_hit.has("position"):
		_hide_hover_overlay()
		return
	var hit_pos: Vector3 = ground_hit.position
	var grid_pos := GridMovementSystem.world_to_grid(hit_pos)
	var center_world := GridMovementSystem.grid_to_world(grid_pos)
	var half_cell := GridNavigator.GRID_SIZE * 0.5
	var world_y := hit_pos.y + 0.03
	var corners_world: Array[Vector3] = [
		Vector3(center_world.x - half_cell, world_y, center_world.z - half_cell),
		Vector3(center_world.x + half_cell, world_y, center_world.z - half_cell),
		Vector3(center_world.x + half_cell, world_y, center_world.z + half_cell),
		Vector3(center_world.x - half_cell, world_y, center_world.z + half_cell)
	]
	_hover_corner_overlay.show_cell(corners_world, camera)

func _hide_hover_overlay() -> void:
	if _hover_corner_overlay:
		_hover_corner_overlay.hide_cell()

func _is_hovering_blocking_ui(viewport: Viewport) -> bool:
	if not viewport:
		return false

	var hovered := viewport.gui_get_hovered_control()
	if hovered == null or not is_instance_valid(hovered):
		return false
	if _hover_corner_overlay and _hover_corner_overlay.owns_control(hovered):
		return false

	var control: Control = hovered
	while control != null:
		if not control.visible:
			control = control.get_parent() as Control
			continue
		if control.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
		control = control.get_parent() as Control

	return false

func _apply_hover_cursor(cursor_texture: Texture2D, hotspot: Vector2) -> void:
	if _active_hover_cursor == cursor_texture and _active_hover_hotspot.is_equal_approx(hotspot):
		return
	_active_hover_cursor = cursor_texture
	_active_hover_hotspot = hotspot
	if cursor_texture:
		Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW, hotspot)
		return
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)

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
		_set_interaction_target_from_interactable(interactable)
		var interacted_primary: bool = bool(interactable.interact_primary())
		if interacted_primary and not is_movement_input_blocked():
			_set_interaction_target_actor(null)
		return interacted_primary
	if interactable.has_signal("interacted"):
		_set_interaction_target_from_interactable(interactable)
		interactable.interacted.emit()
		if not is_movement_input_blocked():
			_set_interaction_target_actor(null)
		return true
	if interactable.has_method("_on_click"):
		_set_interaction_target_from_interactable(interactable)
		interactable._on_click()
		if not is_movement_input_blocked():
			_set_interaction_target_actor(null)
		return true
	return false

func _set_interaction_target_from_interactable(interactable: Node) -> void:
	var target_actor := _resolve_character_actor_from_interactable(interactable)
	_set_interaction_target_actor(target_actor)

func _set_interaction_target_actor(target_actor: CharacterActor) -> void:
	if _interaction_target_actor == target_actor:
		return
	if _interaction_target_state_tag_applied and _interaction_target_actor != null and is_instance_valid(_interaction_target_actor):
		_interaction_target_actor.end_interaction_state()
	_interaction_target_state_tag_applied = false
	_interaction_target_actor = target_actor
	if not is_movement_input_blocked():
		return
	if _interaction_target_actor == null or not is_instance_valid(_interaction_target_actor):
		return
	_interaction_target_actor.begin_interaction_state()
	_interaction_target_state_tag_applied = true

func _resolve_character_actor_from_interactable(interactable: Node) -> CharacterActor:
	if interactable == null:
		return null
	var node: Node = interactable
	while node != null:
		if node is CharacterActor:
			return node as CharacterActor
		node = node.get_parent()
	return null

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
