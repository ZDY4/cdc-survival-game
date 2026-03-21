class_name GridDebugController
extends Node

const GridVisualizerScript = preload("res://systems/grid_visualizer.gd")

const GRID_MODULE_ID := "grid_debug"
const GRID_COMMAND_ID := "grid_debug"
const GRID_VARIABLE_ID := "grid.debug_visible"
const GRID_FLOOR_COLLISION_NAME := "GridFloorCollision"
const GRID_FLOOR_SIZE := Vector3(100, 0.1, 100)
const GRID_FLOOR_OFFSET := Vector3(0, -0.05, 0)

var _grid_visualizer: Node = null
var _grid_floor: StaticBody3D = null

func initialize(grid_visualizer: Node, grid_floor: StaticBody3D, default_visible: bool) -> void:
	_grid_visualizer = grid_visualizer
	_grid_floor = grid_floor
	_setup_grid_floor_collision()
	set_debug_visible(default_visible)
	_register_debug_entries()

func cleanup() -> void:
	_unregister_debug_entries()

func set_debug_visible(visible: bool) -> void:
	if not _grid_visualizer:
		return
	_grid_visualizer.set_debug_visible(visible)

func is_debug_visible() -> bool:
	return _grid_visualizer != null and _grid_visualizer.is_debug_visible()

func toggle_debug_visible() -> bool:
	if not _grid_visualizer:
		return false
	return _grid_visualizer.toggle_debug_visible()

func _setup_grid_floor_collision() -> void:
	if not _grid_floor:
		push_error("GridDebugController: GridFloor is required")
		return

	var collision_shape := _grid_floor.get_node_or_null(GRID_FLOOR_COLLISION_NAME) as CollisionShape3D
	if not collision_shape:
		for child in _grid_floor.get_children():
			if child is CollisionShape3D:
				collision_shape = child
				break

	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = GRID_FLOOR_COLLISION_NAME
		_grid_floor.add_child(collision_shape)

	_ensure_floor_collision_shape(collision_shape)

func _ensure_floor_collision_shape(collision_shape: CollisionShape3D) -> void:
	if not collision_shape.shape or not (collision_shape.shape is BoxShape3D):
		collision_shape.shape = BoxShape3D.new()

	var box_shape := collision_shape.shape as BoxShape3D
	box_shape.size = GRID_FLOOR_SIZE
	collision_shape.position = GRID_FLOOR_OFFSET

func _register_debug_entries() -> void:
	if not DebugModule:
		return

	_unregister_debug_entries()
	DebugModule.register_module(GRID_MODULE_ID, {
		"description": "3D grid debug controls"
	})
	DebugModule.register_command(
		GRID_MODULE_ID,
		GRID_COMMAND_ID,
		Callable(self, "_debug_cmd_grid"),
		"Show/hide/toggle the 3D debug grid",
		"%s [on|off|toggle|status]" % GRID_COMMAND_ID
	)
	DebugModule.register_variable(
		GRID_MODULE_ID,
		GRID_VARIABLE_ID,
		Callable(self, "is_debug_visible"),
		Callable(self, "_set_debug_visible_from_variant"),
		"3D debug grid visibility"
	)

func _unregister_debug_entries() -> void:
	if not DebugModule:
		return

	DebugModule.unregister_variable(GRID_VARIABLE_ID)
	DebugModule.unregister_command(GRID_COMMAND_ID)
	DebugModule.unregister_module(GRID_MODULE_ID)

func _set_debug_visible_from_variant(value: Variant) -> void:
	var parsed_visible := false
	if value is bool:
		parsed_visible = value
	elif value is int:
		parsed_visible = value != 0
	elif value is float:
		parsed_visible = value != 0.0
	else:
		var text_value := str(value).to_lower().strip_edges()
		parsed_visible = text_value in ["on", "show", "true", "1", "yes"]

	set_debug_visible(parsed_visible)

func _debug_cmd_grid(args: Array[String]) -> Dictionary:
	var action := "toggle"
	if not args.is_empty():
		action = args[0].to_lower()

	match action:
		"on", "show", "true", "1":
			set_debug_visible(true)
		"off", "hide", "false", "0":
			set_debug_visible(false)
		"toggle":
			toggle_debug_visible()
		"status":
			pass
		_:
			return {
				"success": false,
				"error": "Usage: %s [on|off|toggle|status]" % GRID_COMMAND_ID
			}

	return {
		"success": true,
		"message": "%s = %s" % [GRID_VARIABLE_ID, "on" if is_debug_visible() else "off"]
	}
