class_name GameWorld3D
extends Node3D

const CameraController3D = preload("res://systems/camera_controller_3d.gd")
const PlayerController3D = preload("res://systems/player_controller_3d.gd")
const PathPreview = preload("res://systems/path_preview.gd")
const GridNavigator = preload("res://systems/grid_navigator.gd")
const GridVisualizer = preload("res://systems/grid_visualizer.gd")
const GameWorldMerchantTradeComponent = preload("res://scripts/locations/game_world_merchant_trade_component.gd")
const NPC_INTERACTION_MASK: int = 1 << 1

@export var player_scene: PackedScene = null
@export var show_grid_debug := false
@export var max_preview_path_points := 200
@export var max_preview_distance := 40.0
@export var interaction_preview_min_radius := 1
@export var interaction_preview_max_radius := 4

@onready var _camera_controller: CameraController3D
@onready var _player: PlayerController3D
@onready var _grid_floor: StaticBody3D
@onready var _path_preview: PathPreview
@onready var _navigator: GridNavigator

var _is_mouse_pressed := false
var _last_hover_pos: Vector3
var _active_move_target: Vector3 = Vector3.ZERO
var _has_active_move_target := false
var _grid_visualizer: GridVisualizer = null
var _is_npc_interaction_active := false
var _merchant_data: NPCData
var _merchant_trade_component: NPCTradeComponent = null

func _ready() -> void:
    _setup_world()
    _spawn_player()
    _setup_camera()
    _setup_input()
    _setup_npcs()
    _register_debug_entries()

func _exit_tree() -> void:
    _unregister_debug_entries()

func _setup_world() -> void:
    _navigator = GridNavigator.new()
    
    _grid_floor = $GridFloor
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
    _player.move_requested.connect(_on_player_move_requested)
    _player.movement_completed.connect(_on_player_movement_completed)
    
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
                if _player and _player.is_moving():
                    _player.cancel_movement()
                    _clear_active_move_target()
                    return
                _handle_ground_click()
    
    if event is InputEventScreenTouch:
        if event.pressed:
            if _player and _player.is_moving():
                _player.cancel_movement()
                _clear_active_move_target()
                return
            _handle_touch_click(event.position)

func _process(delta: float) -> void:
    _update_path_preview(delta)

var _last_preview_signature := ""
var _preview_update_timer: float = 0.0
const PREVIEW_UPDATE_INTERVAL: float = 0.1

func _update_path_preview(delta: float) -> void:
    if not _player or not _path_preview:
        return
    
    # Throttle updates
    _preview_update_timer += delta
    if _preview_update_timer < PREVIEW_UPDATE_INTERVAL:
        return
    _preview_update_timer = 0.0

    if not GridMovementSystem or not GridMovementSystem.grid_world:
        return
    if not get_world_3d():
        return

    if _has_active_move_target and not _player.is_moving():
        _clear_active_move_target()

    if _player.is_moving() and _has_active_move_target:
        _update_preview_to_target(_active_move_target, false, "move_target")
        return

    var mouse_pos := get_viewport().get_mouse_position()
    var hover_hit := _raycast_screen_position(mouse_pos)
    if not hover_hit.is_empty():
        var interactable := _resolve_interactable_from_hit(hover_hit)
        if interactable != null:
            var interaction_target_data := _find_nearest_interaction_target(interactable, hover_hit.position)
            if bool(interaction_target_data.get("found", false)):
                var interaction_target: Vector3 = interaction_target_data.get("target", Vector3.ZERO)
                _last_hover_pos = interaction_target
                _update_preview_to_target(interaction_target, true, "interactable")
                return

    var ground_hit := _raycast_screen_position(mouse_pos, true, 1)
    if ground_hit.is_empty():
        _hide_preview()
        return

    var world_pos: Vector3 = ground_hit.position
    _last_hover_pos = world_pos
    _update_preview_to_target(world_pos, true, "mouse")

func _handle_ground_click() -> void:
    var mouse_pos := get_viewport().get_mouse_position()
    _handle_primary_click(mouse_pos)

func _handle_touch_click(screen_pos: Vector2) -> void:
    _handle_primary_click(screen_pos)

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
    var to := from + camera.project_ray_normal(screen_pos) * 1000.0

    var query := PhysicsRayQueryParameters3D.new()
    query.from = from
    query.to = to
    query.collision_mask = NPC_INTERACTION_MASK

    var result := get_world_3d().direct_space_state.intersect_ray(query)
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
    _merchant_trade_component = GameWorldMerchantTradeComponent.new() as NPCTradeComponent
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
    if not GridMovementSystem or not GridMovementSystem.grid_world:
        return

    var hover_hit := _raycast_screen_position(screen_pos)
    if not hover_hit.is_empty():
        var interactable := _resolve_interactable_from_hit(hover_hit)
        if interactable != null:
            var interaction_target_data := _find_nearest_interaction_target(interactable, hover_hit.position)
            if bool(interaction_target_data.get("found", false)):
                var interaction_target: Vector3 = interaction_target_data.get("target", Vector3.ZERO)
                _request_player_move(interaction_target)
                return

    var ground_hit := _raycast_screen_position(screen_pos, true, 1)
    if ground_hit.is_empty():
        return

    _request_player_move(ground_hit.position)

func _request_player_move(world_pos: Vector3) -> void:
    var move_target := world_pos
    move_target.y = _player.global_position.y
    var snapped_pos := GridMovementSystem.snap_to_grid(move_target)
    snapped_pos.y = _player.global_position.y
    _player.move_to(snapped_pos)
    if not _player.is_moving():
        return

    EventBus.emit(EventBus.EventType.GRID_CLICKED, {
        "world_position": snapped_pos,
        "grid_position": GridMovementSystem.world_to_grid(snapped_pos)
    })

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

func _raycast_screen_position(screen_pos: Vector2, use_collision_mask: bool = false, collision_mask: int = 1) -> Dictionary:
    var camera := get_viewport().get_camera_3d()
    if not camera:
        return {}
    if not get_world_3d():
        return {}

    var from := camera.project_ray_origin(screen_pos)
    var to := from + camera.project_ray_normal(screen_pos) * 1000.0

    var query := PhysicsRayQueryParameters3D.new()
    query.from = from
    query.to = to
    if use_collision_mask:
        query.collision_mask = collision_mask

    return get_world_3d().direct_space_state.intersect_ray(query)

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

func _on_player_move_requested(world_pos: Vector3) -> void:
    _active_move_target = world_pos
    _has_active_move_target = true
    _last_preview_signature = ""

func _on_player_movement_completed() -> void:
    _clear_active_move_target()

func _clear_active_move_target() -> void:
    _has_active_move_target = false
    _active_move_target = Vector3.ZERO
    _last_preview_signature = ""

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
