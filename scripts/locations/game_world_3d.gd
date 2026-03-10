class_name GameWorld3D
extends Node3D

const CameraController3D = preload("res://systems/camera_controller_3d.gd")
const PlayerController3D = preload("res://systems/player_controller_3d.gd")
const GridVisualizer = preload("res://systems/grid_visualizer.gd")
const AISpawnSystem = preload("res://systems/spawn/ai_spawn_system.gd")
const NPCInteractionSystem = preload("res://modules/npc/npc_interaction_system.gd")

@export var player_scene: PackedScene = null
@export var show_grid_debug: bool = false
@export var max_preview_path_points: int = 200
@export var max_preview_distance: float = 40.0
@export var interaction_preview_min_radius: int = 1
@export var interaction_preview_max_radius: int = 4

@onready var _grid_floor: StaticBody3D = $GridFloor

var _camera_controller: CameraController3D = null
var _player: PlayerController3D = null
var _grid_visualizer: GridVisualizer = null
var _spawn_system: AISpawnSystem = null
var _npc_interaction_system: NPCInteractionSystem = null

func _ready() -> void:
    _setup_world()
    _spawn_player()
    _setup_camera()
    _setup_runtime_systems()
    _register_debug_entries()

func _exit_tree() -> void:
    _unregister_debug_entries()

func _setup_world() -> void:
    _setup_grid_floor_collision()

    _grid_visualizer = GridVisualizer.new()
    add_child(_grid_visualizer)
    set_grid_debug_visible(show_grid_debug)

func _setup_grid_floor_collision() -> void:
    var collision_shape := CollisionShape3D.new()
    _grid_floor.add_child(collision_shape)

    var shape := BoxShape3D.new()
    shape.size = Vector3(100, 0.1, 100)
    collision_shape.shape = shape
    collision_shape.position = Vector3(0, -0.05, 0)

func _spawn_player() -> void:
    if player_scene:
        _player = player_scene.instantiate()
    else:
        _player = PlayerController3D.new()

    add_child(_player)
    _player.global_position = Vector3(0, 1, 0)
    _player.set_grid_world(GridMovementSystem.grid_world)
    GameState.player_position_3d = _player.global_position

func _setup_camera() -> void:
    _camera_controller = CameraController3D.new()
    add_child(_camera_controller)
    _camera_controller.target = _player

func _setup_runtime_systems() -> void:
    _npc_interaction_system = NPCInteractionSystem.new()
    add_child(_npc_interaction_system)
    if _player:
        _npc_interaction_system.initialize(self, _player.get_interaction_system())

    _spawn_system = AISpawnSystem.new()
    add_child(_spawn_system)
    _spawn_system.initialize(self)
    _spawn_system.spawn_auto_points()

    if _player:
        _player.set_interaction_context(self, _npc_interaction_system)
        _player.configure_path_preview_settings(
            max_preview_path_points,
            max_preview_distance,
            interaction_preview_min_radius,
            interaction_preview_max_radius
        )


func get_player() -> PlayerController3D:
    return _player

func get_camera() -> CameraController3D:
    return _camera_controller

func set_grid_debug_visible(visible: bool) -> void:
    show_grid_debug = visible
    if not _grid_visualizer:
        return

    if show_grid_debug:
        _grid_visualizer.show_grid()
    else:
        _grid_visualizer.hide_grid()

func toggle_grid_debug() -> bool:
    set_grid_debug_visible(not show_grid_debug)
    return show_grid_debug

func is_grid_debug_visible() -> bool:
    return show_grid_debug

func _register_debug_entries() -> void:
    if not DebugModule:
        return

    DebugModule.register_module("grid", {
        "description": "3D grid debug controls"
    })
    DebugModule.register_command(
        "grid",
        "grid",
        Callable(self, "_debug_cmd_grid"),
        "Show/hide/toggle the 3D debug grid",
        "grid [on|off|toggle|status]"
    )
    DebugModule.register_variable(
        "grid",
        "grid.visible",
        Callable(self, "is_grid_debug_visible"),
        Callable(self, "_set_grid_debug_from_variant"),
        "3D debug grid visibility"
    )

func _unregister_debug_entries() -> void:
    if not DebugModule:
        return

    DebugModule.unregister_variable("grid.visible")
    DebugModule.unregister_command("grid")
    DebugModule.unregister_module("grid")

func _set_grid_debug_from_variant(value: Variant) -> void:
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

    set_grid_debug_visible(parsed_visible)

func _debug_cmd_grid(args: Array[String]) -> Dictionary:
    var action := "toggle"
    if not args.is_empty():
        action = args[0].to_lower()

    match action:
        "on", "show", "true", "1":
            set_grid_debug_visible(true)
        "off", "hide", "false", "0":
            set_grid_debug_visible(false)
        "toggle":
            toggle_grid_debug()
        "status":
            pass
        _:
            return {
                "success": false,
                "error": "Usage: grid [on|off|toggle|status]"
            }

    return {
        "success": true,
        "message": "grid.visible = %s" % ("on" if show_grid_debug else "off")
    }
