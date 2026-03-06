class_name GameWorld3D
extends Node3D

const MERCHANT_TRADE_COMPONENT_SCRIPT := preload("res://scripts/locations/game_world_merchant_trade_component.gd")
const NPC_INTERACTION_MASK: int = 1 << 1

@export var player_scene: PackedScene = null
@export var show_grid_debug := false
@export var max_preview_path_points := 200
@export var max_preview_distance := 40.0

@onready var _camera_controller: CameraController3D
@onready var _player: PlayerController3D
@onready var _grid_floor: StaticBody3D
@onready var _path_preview: PathPreview
@onready var _navigator: GridNavigator

var _is_mouse_pressed := false
var _last_hover_pos: Vector3
var _is_npc_interaction_active := false
var _merchant_data: NPCData
var _merchant_trade_component: NPCTradeComponent = null

var _last_preview_grid: Vector3i = Vector3i.ZERO
var _preview_update_timer: float = 0.0
const PREVIEW_UPDATE_INTERVAL: float = 0.1

func _ready() -> void:
    _setup_world()
    _spawn_player()
    _setup_camera()
    _setup_input()
    _setup_npcs()

func _setup_world() -> void:
    _navigator = GridNavigator.new()

    _grid_floor = $GridFloor
    _setup_grid_floor_collision()

    if show_grid_debug:
        var visualizer := GridVisualizer.new()
        add_child(visualizer)
        visualizer.show_grid()

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

func _setup_input() -> void:
    _path_preview = PathPreview.new()
    add_child(_path_preview)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            _is_mouse_pressed = event.pressed
            if event.pressed:
                _handle_primary_click(event.position)

    if event is InputEventScreenTouch:
        if event.pressed:
            _handle_primary_click(event.position)

func _process(delta: float) -> void:
    _update_path_preview(delta)

func _update_path_preview(delta: float) -> void:
    if not _player or not _path_preview:
        return

    _preview_update_timer += delta
    if _preview_update_timer < PREVIEW_UPDATE_INTERVAL:
        return
    _preview_update_timer = 0.0

    var mouse_pos := get_viewport().get_mouse_position()
    var camera := get_viewport().get_camera_3d()

    if not camera:
        return
    if not GridMovementSystem or not GridMovementSystem.grid_world:
        return
    if not get_world_3d():
        return

    var from := camera.project_ray_origin(mouse_pos)
    var to := from + camera.project_ray_normal(mouse_pos) * 1000

    var space_state := get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.new()
    query.from = from
    query.to = to
    query.collision_mask = 1

    var result := space_state.intersect_ray(query)

    if result:
        var world_pos: Vector3 = result.position
        if _player.global_position.distance_to(world_pos) > max_preview_distance:
            _path_preview.hide_path()
            _last_preview_grid = Vector3i.ZERO
            return
        var current_grid := GridMovementSystem.world_to_grid(world_pos)

        if current_grid == _last_preview_grid:
            return
        _last_preview_grid = current_grid

        _last_hover_pos = world_pos

        var path := _navigator.find_path(
            _player.global_position,
            world_pos,
            GridMovementSystem.grid_world.is_walkable
        )

        if path.size() > max_preview_path_points:
            _path_preview.hide_path()
        elif path.size() > 1:
            _path_preview.show_path(path)
        else:
            _path_preview.hide_path()
    else:
        _path_preview.hide_path()
        _last_preview_grid = Vector3i.ZERO

func _handle_primary_click(screen_pos: Vector2) -> void:
    if _is_npc_interaction_active:
        return

    if _try_interact_npc(screen_pos):
        return

    _try_move_to_screen_position(screen_pos)

func _try_interact_npc(screen_pos: Vector2) -> bool:
    var camera := get_viewport().get_camera_3d()
    if not camera:
        return false
    if not get_world_3d():
        return false

    var from := camera.project_ray_origin(screen_pos)
    var to := from + camera.project_ray_normal(screen_pos) * 1000

    var space_state := get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.new()
    query.from = from
    query.to = to
    query.collision_mask = NPC_INTERACTION_MASK

    var result := space_state.intersect_ray(query)
    if result.is_empty():
        return false

    var collider: Object = result.get("collider", null)
    if not collider or not collider.has_meta("npc_role"):
        return false

    var npc_role: String = str(collider.get_meta("npc_role"))
    if npc_role.is_empty():
        return false

    _start_npc_interaction(npc_role)
    return true

func _start_npc_interaction(npc_role: String) -> void:
    if _is_npc_interaction_active:
        return

    _is_npc_interaction_active = true
    _run_npc_interaction(npc_role)

func _run_npc_interaction(npc_role: String) -> void:
    match npc_role:
        "merchant":
            await _run_merchant_dialog()
        "civilian":
            await _run_civilian_dialog()
        _:
            DialogModule.show_dialog("No response.", "Civilian")
            await DialogModule.dialog_finished

    _is_npc_interaction_active = false

func _run_merchant_dialog() -> void:
    DialogModule.show_dialog("Need supplies? I still have goods to trade.", "Old Wang")
    await DialogModule.dialog_finished

    var choice: int = await DialogModule.show_choices(["Open shop", "Ask for rumors", "Leave"])
    match choice:
        0:
            if _merchant_trade_component:
                var opened: bool = await _merchant_trade_component.open_trade_ui()
                if not opened:
                    DialogModule.show_dialog("Shop is closed for now.", "Old Wang")
                    await DialogModule.dialog_finished
        1:
            DialogModule.show_dialog("The streets are dangerous at night. Get back before dark.", "Old Wang")
            await DialogModule.dialog_finished
        _:
            DialogModule.show_dialog("Stay alive and come back.", "Old Wang")
            await DialogModule.dialog_finished

func _run_civilian_dialog() -> void:
    var lines: Array[String] = [
        "Do not go too far from the safe route.",
        "I am looking for my family. Tell me if you find clues.",
        "Surviving one more day is already a win."
    ]
    DialogModule.show_dialog(lines[randi() % lines.size()], "Civilian")
    await DialogModule.dialog_finished

func _setup_npcs() -> void:
    _merchant_data = _create_merchant_data()
    _merchant_trade_component = MERCHANT_TRADE_COMPONENT_SCRIPT.new() as NPCTradeComponent
    add_child(_merchant_trade_component)
    if _merchant_trade_component and _merchant_trade_component.has_method("initialize_with_data"):
        _merchant_trade_component.call("initialize_with_data", _merchant_data)

    _spawn_npc_actor(
        "MerchantNPC",
        Vector3(5.0, 0.0, 3.0),
        Color(0.86, 0.73, 0.33, 1.0),
        "Old Wang (Trader)",
        "merchant"
    )
    _spawn_npc_actor(
        "CivilianNPC",
        Vector3(-4.0, 0.0, 2.0),
        Color(0.58, 0.72, 0.88, 1.0),
        "Civilian",
        "civilian"
    )

func _create_merchant_data() -> NPCData:
    var data := NPCData.new()
    data.id = "gw3d_merchant"
    data.name = "Old Wang"
    data.title = "Trader"
    data.npc_type = NPCData.Type.TRADER
    data.can_trade = true
    data.default_location = "game_world_3d"
    data.current_location = "game_world_3d"

    data.trade_data["buy_price_modifier"] = 1.15
    data.trade_data["sell_price_modifier"] = 0.80
    data.trade_data["money"] = 1200
    data.trade_data["inventory"] = [
        {"id": "bandage", "count": 10, "price": 18},
        {"id": "water_bottle", "count": 8, "price": 12},
        {"id": "food_canned", "count": 6, "price": 20},
        {"id": "medkit", "count": 2, "price": 60}
    ]
    data.mood["friendliness"] = 55
    data.mood["trust"] = 35
    return data

func _spawn_npc_actor(
    node_name: String,
    world_position: Vector3,
    color: Color,
    display_name: String,
    npc_role: String
) -> void:
    var npc_body := StaticBody3D.new()
    npc_body.name = node_name
    npc_body.collision_layer = 2
    npc_body.collision_mask = 0
    npc_body.global_position = world_position
    npc_body.set_meta("npc_role", npc_role)
    add_child(npc_body)

    var collision_shape := CollisionShape3D.new()
    var collider := CapsuleShape3D.new()
    collider.radius = 0.45
    collider.height = 1.0
    collision_shape.shape = collider
    collision_shape.position = Vector3(0, 1.0, 0)
    npc_body.add_child(collision_shape)

    var mesh_instance := MeshInstance3D.new()
    var capsule_mesh := CapsuleMesh.new()
    capsule_mesh.radius = 0.45
    capsule_mesh.height = 1.0
    mesh_instance.mesh = capsule_mesh
    mesh_instance.position = Vector3(0, 1.0, 0)
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    mesh_instance.material_override = material
    npc_body.add_child(mesh_instance)

    var name_label := Label3D.new()
    name_label.text = display_name
    name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    name_label.font_size = 36
    name_label.position = Vector3(0, 2.2, 0)
    npc_body.add_child(name_label)

func _try_move_to_screen_position(screen_pos: Vector2) -> void:
    var camera := get_viewport().get_camera_3d()
    if not camera:
        return
    if not GridMovementSystem or not GridMovementSystem.grid_world:
        return
    if not get_world_3d():
        return

    var from := camera.project_ray_origin(screen_pos)
    var to := from + camera.project_ray_normal(screen_pos) * 1000

    var space_state := get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.new()
    query.from = from
    query.to = to
    query.collision_mask = 1

    var result := space_state.intersect_ray(query)

    if result:
        var world_pos: Vector3 = result.position
        world_pos = GridMovementSystem.snap_to_grid(world_pos)
        _player.move_to(world_pos)

        EventBus.emit(EventBus.EventType.GRID_CLICKED, {
            "world_position": world_pos,
            "grid_position": GridMovementSystem.world_to_grid(world_pos)
        })

func get_player() -> PlayerController3D:
    return _player

func get_camera() -> CameraController3D:
    return _camera_controller
