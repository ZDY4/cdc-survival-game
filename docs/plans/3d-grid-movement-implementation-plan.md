# 3D网格移动系统实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use @executing-plans to implement this plan task-by-task.

**Goal:** 将CDC生存游戏改为横屏3D项目，实现基于1米网格的角色移动系统，支持点击移动、寻路、相机缩放和路径预览

**Architecture:** 使用Godot 4.6的3D功能，创建独立的网格移动系统模块。玩家使用Sprite3D配合Billboard模式实现2D角色在3D世界中始终正对相机。采用A*算法实现寻路，使用Tween实现平滑移动插值。

**Tech Stack:** Godot 4.6, GDScript, Sprite3D, CharacterBody3D, Camera3D, A*寻路算法

---

## Task 1: 更新 project.godot 配置

**Files:**
- Modify: `project.godot:71-93`

**Step 1: 备份原配置**

Run: `copy project.godot project.godot.backup`

**Step 2: 修改视口为横屏**

Edit `project.godot` lines 73-74:
```ini
window/size/viewport_width=1920
window/size/viewport_height=1080
```

**Step 3: 添加缩放输入映射**

Add after line 89:
```ini
zoom_in={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":4,"canceled":false,"pressed":false,"double_click":false,"script":null)
]
}
zoom_out={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":5,"canceled":false,"pressed":false,"double_click":false,"script":null)
]
}
```

**Step 4: 添加GridMovementSystem到autoload**

Add after line 68:
```ini
GridMovementSystem="*res://systems/grid_movement_system.gd"
```

**Step 5: Commit**

```bash
git add project.godot
git commit -m "config: update to landscape 3D with zoom inputs"
```

---

## Task 2: 创建 GridNavigator 寻路类

**Files:**
- Create: `systems/grid_navigator.gd`

**Step 1: 创建文件**

Create `systems/grid_navigator.gd`:
```gdscript
class_name GridNavigator
extends RefCounted

const GRID_SIZE := 1.0

func find_path(start_pos: Vector3, end_pos: Vector3, is_walkable: Callable) -> Array[Vector3]:
    var start_grid := world_to_grid(start_pos)
    var end_grid := world_to_grid(end_pos)
    
    if not is_walkable.call(end_grid):
        push_warning("Target position not walkable: " + str(end_grid))
        return []
    
    var open_set: Array[Vector3i] = [start_grid]
    var came_from: Dictionary = {}
    var g_score: Dictionary = {start_grid: 0.0}
    var f_score: Dictionary = {start_grid: _heuristic(start_grid, end_grid)}
    
    while not open_set.is_empty():
        var current := _get_lowest_f_score(open_set, f_score)
        
        if current == end_grid:
            return _reconstruct_path(came_from, current)
        
        open_set.erase(current)
        
        for neighbor in _get_neighbors(current):
            if not is_walkable.call(neighbor):
                continue
                
            var tentative_g := g_score[current] + 1.0
            
            if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
                came_from[neighbor] = current
                g_score[neighbor] = tentative_g
                f_score[neighbor] = tentative_g + _heuristic(neighbor, end_grid)
                
                if not neighbor in open_set:
                    open_set.append(neighbor)
    
    return []

func world_to_grid(world_pos: Vector3) -> Vector3i:
    return Vector3i(
        floor(world_pos.x / GRID_SIZE),
        floor(world_pos.y / GRID_SIZE),
        floor(world_pos.z / GRID_SIZE)
    )

func grid_to_world(grid_pos: Vector3i) -> Vector3:
    return Vector3(
        grid_pos.x * GRID_SIZE + GRID_SIZE / 2.0,
        grid_pos.y * GRID_SIZE + GRID_SIZE / 2.0,
        grid_pos.z * GRID_SIZE + GRID_SIZE / 2.0
    )

func _get_neighbors(grid_pos: Vector3i) -> Array[Vector3i]:
    return [
        grid_pos + Vector3i(1, 0, 0),
        grid_pos + Vector3i(-1, 0, 0),
        grid_pos + Vector3i(0, 0, 1),
        grid_pos + Vector3i(0, 0, -1)
    ]

func _heuristic(a: Vector3i, b: Vector3i) -> float:
    return abs(a.x - b.x) + abs(a.z - b.z)

func _get_lowest_f_score(open_set: Array[Vector3i], f_score: Dictionary) -> Vector3i:
    var lowest := open_set[0]
    var lowest_score: float = f_score.get(lowest, INF)
    
    for pos in open_set:
        var score: float = f_score.get(pos, INF)
        if score < lowest_score:
            lowest = pos
            lowest_score = score
    
    return lowest

func _reconstruct_path(came_from: Dictionary, current: Vector3i) -> Array[Vector3]:
    var path: Array[Vector3] = [grid_to_world(current)]
    
    while came_from.has(current):
        current = came_from[current]
        path.insert(0, grid_to_world(current))
    
    return path
```

**Step 2: Commit**

```bash
git add systems/grid_navigator.gd
git commit -m "feat: add A* grid navigator for pathfinding"
```

---

## Task 3: 创建 GridMovement 移动控制类

**Files:**
- Create: `systems/grid_movement.gd`

**Step 1: 创建文件**

Create `systems/grid_movement.gd`:
```gdscript
class_name GridMovement
extends Node

signal movement_started(path: Array[Vector3])
signal step_completed(world_pos: Vector3, step_index: int, total_steps: int)
signal movement_finished
signal movement_cancelled

@export var step_duration := 0.4

var _current_path: Array[Vector3] = []
var _current_step := 0
var _is_moving := false
var _tween: Tween = null

func move_along_path(path: Array[Vector3], target_node: Node3D) -> void:
    if path.is_empty():
        push_warning("Cannot move along empty path")
        return
    
    if _is_moving:
        cancel_movement()
    
    _current_path = path
    _current_step = 0
    _is_moving = true
    
    movement_started.emit(path.duplicate())
    
    _execute_next_step(target_node)

func cancel_movement() -> void:
    if not _is_moving:
        return
    
    if _tween and _tween.is_valid():
        _tween.kill()
    
    _is_moving = false
    _current_path.clear()
    _current_step = 0
    
    movement_cancelled.emit()

func is_moving() -> bool:
    return _is_moving

func get_current_path() -> Array[Vector3]:
    return _current_path.duplicate()

func get_remaining_steps() -> int:
    return _current_path.size() - _current_step

func _execute_next_step(target_node: Node3D) -> void:
    if _current_step >= _current_path.size():
        _is_moving = false
        _current_path.clear()
        _current_step = 0
        movement_finished.emit()
        return
    
    var target_pos := _current_path[_current_step]
    
    _tween = create_tween()
    _tween.set_trans(Tween.TRANS_QUAD)
    _tween.set_ease(Tween.EASE_IN_OUT)
    
    _tween.tween_property(target_node, "position", target_pos, step_duration)
    _tween.finished.connect(_on_step_completed.bind(target_node))

func _on_step_completed(target_node: Node3D) -> void:
    step_completed.emit(_current_path[_current_step], _current_step, _current_path.size())
    _current_step += 1
    _execute_next_step(target_node)
```

**Step 2: Commit**

```bash
git add systems/grid_movement.gd
git commit -m "feat: add grid movement with smooth interpolation"
```

---

## Task 4: 创建 GridWorld 网格世界管理类

**Files:**
- Create: `systems/grid_world.gd`

**Step 1: 创建文件**

Create `systems/grid_world.gd`:
```gdscript
class_name GridWorld
extends Node

const GRID_SIZE := 1.0

var _walkable_grids: Dictionary = {}
var _obstacles: Array[Vector3i] = []

func register_obstacle(world_pos: Vector3) -> void:
    var grid_pos := GridNavigator.new().world_to_grid(world_pos)
    if not grid_pos in _obstacles:
        _obstacles.append(grid_pos)

func unregister_obstacle(world_pos: Vector3) -> void:
    var grid_pos := GridNavigator.new().world_to_grid(world_pos)
    _obstacles.erase(grid_pos)

func is_walkable(grid_pos: Vector3i) -> bool:
    return not grid_pos in _obstacles

func world_to_grid(world_pos: Vector3) -> Vector3i:
    return Vector3i(
        floor(world_pos.x / GRID_SIZE),
        floor(world_pos.y / GRID_SIZE),
        floor(world_pos.z / GRID_SIZE)
    )

func grid_to_world(grid_pos: Vector3i) -> Vector3:
    return Vector3(
        grid_pos.x * GRID_SIZE + GRID_SIZE / 2.0,
        grid_pos.y * GRID_SIZE + GRID_SIZE / 2.0,
        grid_pos.z * GRID_SIZE + GRID_SIZE / 2.0
    )

func snap_to_grid(world_pos: Vector3) -> Vector3:
    var grid_pos := world_to_grid(world_pos)
    return grid_to_world(grid_pos)

func get_all_obstacles() -> Array[Vector3i]:
    return _obstacles.duplicate()

func clear_obstacles() -> void:
    _obstacles.clear()
```

**Step 2: Commit**

```bash
git add systems/grid_world.gd
git commit -m "feat: add grid world manager for obstacle tracking"
```

---

## Task 5: 创建 PathPreview 路径预览类

**Files:**
- Create: `systems/path_preview.gd`

**Step 1: 创建文件**

Create `systems/path_preview.gd`:
```gdscript
class_name PathPreview
extends Node3D

@export var line_color := Color(0.2, 0.8, 1.0, 0.8)
@export var line_width := 0.1
@export var point_size := 0.2
@export var point_color := Color(0.2, 0.8, 1.0, 0.5)

var _line_mesh: MeshInstance3D = null
var _points: Array[MeshInstance3D] = []

func _ready() -> void:
    _line_mesh = MeshInstance3D.new()
    add_child(_line_mesh)

func show_path(path: Array[Vector3]) -> void:
    if path.is_empty():
        hide_path()
        return
    
    _clear_points()
    _draw_line(path)
    _draw_points(path)
    visible = true

func hide_path() -> void:
    visible = false
    _clear_points()
    if _line_mesh:
        _line_mesh.mesh = null

func _draw_line(path: Array[Vector3]) -> void:
    if path.size() < 2:
        return
    
    var immediate_mesh := ImmediateMesh.new()
    _line_mesh.mesh = immediate_mesh
    _line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    
    var material := StandardMaterial3D.new()
    material.albedo_color = line_color
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _line_mesh.material_override = material
    
    immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
    
    for pos in path:
        immediate_mesh.surface_add_vertex(pos + Vector3.UP * 0.1)
    
    immediate_mesh.surface_end()

func _draw_points(path: Array[Vector3]) -> void:
    for pos in path:
        var point := MeshInstance3D.new()
        point.mesh = SphereMesh.new()
        point.mesh.radius = point_size
        point.mesh.height = point_size * 2
        
        var material := StandardMaterial3D.new()
        material.albedo_color = point_color
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        point.material_override = material
        
        point.position = pos + Vector3.UP * 0.1
        point.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        
        add_child(point)
        _points.append(point)

func _clear_points() -> void:
    for point in _points:
        point.queue_free()
    _points.clear()
```

**Step 2: Commit**

```bash
git add systems/path_preview.gd
git commit -m "feat: add path preview visualization"
```

---

## Task 6: 创建 CameraController3D 相机控制器

**Files:**
- Create: `systems/camera_controller_3d.gd`

**Step 1: 创建文件**

Create `systems/camera_controller_3d.gd`:
```gdscript
class_name CameraController3D
extends Node3D

@export var target: Node3D = null
@export var isometric_rotation := Vector3(-45, 45, 0)
@export var min_zoom := 10.0
@export var max_zoom := 50.0
@export var zoom_speed := 2.0
@export var zoom_smoothing := 0.1
@export var follow_smoothing := 0.1
@export var initial_zoom := 20.0
@export var initial_offset := Vector3(20, 20, 20)

var _current_zoom: float
var _target_zoom: float
var _camera: Camera3D = null

func _ready() -> void:
    _camera = Camera3D.new()
    add_child(_camera)
    
    _camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    _current_zoom = initial_zoom
    _target_zoom = initial_zoom
    _camera.size = _current_zoom
    
    rotation_degrees = isometric_rotation
    
    if target:
        global_position = target.global_position + initial_offset
        look_at(target.global_position)

func _process(delta: float) -> void:
    _update_zoom(delta)
    _update_follow(delta)

func _input(event: InputEvent) -> void:
    _handle_zoom_input(event)

func _handle_zoom_input(event: InputEvent) -> void:
    if event.is_action_pressed("zoom_in"):
        _target_zoom = max(_target_zoom - zoom_speed, min_zoom)
    elif event.is_action_pressed("zoom_out"):
        _target_zoom = min(_target_zoom + zoom_speed, max_zoom)
    
    if event is InputEventMagnifyGesture:
        if event.factor > 1.0:
            _target_zoom = max(_target_zoom - zoom_speed, min_zoom)
        else:
            _target_zoom = min(_target_zoom + zoom_speed, max_zoom)

func _update_zoom(delta: float) -> void:
    _current_zoom = lerp(_current_zoom, _target_zoom, zoom_smoothing)
    if _camera:
        _camera.size = _current_zoom

func _update_follow(delta: float) -> void:
    if not target:
        return
    
    var target_pos := target.global_position + initial_offset
    global_position = lerp(global_position, target_pos, follow_smoothing)
    look_at(target.global_position)

func set_zoom(zoom: float) -> void:
    _target_zoom = clamp(zoom, min_zoom, max_zoom)

func get_zoom() -> float:
    return _current_zoom
```

**Step 2: Commit**

```bash
git add systems/camera_controller_3d.gd
git commit -m "feat: add isometric camera controller with zoom"
```

---

## Task 7: 创建 PlayerController3D 玩家控制器

**Files:**
- Create: `systems/player_controller_3d.gd`

**Step 1: 创建文件**

Create `systems/player_controller_3d.gd`:
```gdscript
class_name PlayerController3D
extends CharacterBody3D

signal move_requested(world_pos: Vector3)
signal movement_completed

@export var sprite_texture: Texture2D = null
@export var sprite_scale := 1.0

@onready var _sprite: Sprite3D
@onready var _movement: GridMovement
@onready var _navigator: GridNavigator
@onready var _collision: CollisionShape3D

var _grid_world: GridWorld = null

func _ready() -> void:
    _setup_sprite()
    _setup_collision()
    _setup_movement()
    _navigator = GridNavigator.new()
    
    if not _grid_world:
        _grid_world = GridWorld.new()

func _setup_sprite() -> void:
    _sprite = Sprite3D.new()
    add_child(_sprite)
    
    _sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    _sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
    
    if sprite_texture:
        _sprite.texture = sprite_texture
    else:
        _create_placeholder_texture()
    
    _sprite.pixel_size = 0.01 * sprite_scale
    _sprite.position = Vector3.UP * 1.0

func _setup_collision() -> void:
    _collision = CollisionShape3D.new()
    add_child(_collision)
    
    var shape := CylinderShape3D.new()
    shape.radius = 0.3
    shape.height = 1.0
    _collision.shape = shape

func _setup_movement() -> void:
    _movement = GridMovement.new()
    add_child(_movement)
    
    _movement.movement_finished.connect(_on_movement_finished)

func _create_placeholder_texture() -> void:
    var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.2, 0.6, 1.0, 1.0))
    
    for x in range(64):
        image.set_pixel(x, 0, Color.BLACK)
        image.set_pixel(x, 63, Color.BLACK)
    for y in range(64):
        image.set_pixel(0, y, Color.BLACK)
        image.set_pixel(63, y, Color.BLACK)
    
    _sprite.texture = ImageTexture.create_from_image(image)

func move_to(world_pos: Vector3) -> void:
    var start_pos := global_position
    var path := _navigator.find_path(start_pos, world_pos, _grid_world.is_walkable)
    
    if path.is_empty():
        push_warning("No path found to: " + str(world_pos))
        return
    
    move_requested.emit(world_pos)
    _movement.move_along_path(path, self)

func cancel_movement() -> void:
    _movement.cancel_movement()

func is_moving() -> bool:
    return _movement.is_moving()

func get_grid_position() -> Vector3i:
    return _navigator.world_to_grid(global_position)

func get_grid_world() -> GridWorld:
    return _grid_world

func set_grid_world(world: GridWorld) -> void:
    _grid_world = world

func _on_movement_finished() -> void:
    movement_completed.emit()
    EventBus.emit(EventBus.EventType.PLAYER_MOVED, {
        "position": global_position,
        "grid_position": get_grid_position()
    })
```

**Step 2: Commit**

```bash
git add systems/player_controller_3d.gd
git commit -m "feat: add 3D player controller with sprite billboard"
```

---

## Task 8: 创建 GridMovementSystem 系统总入口

**Files:**
- Create: `systems/grid_movement_system.gd`

**Step 1: 创建文件**

Create `systems/grid_movement_system.gd`:
```gdscript
extends Node

var navigator: GridNavigator
var grid_world: GridWorld

func _ready() -> void:
    navigator = GridNavigator.new()
    grid_world = GridWorld.new()
    add_child(grid_world)

func find_path(start: Vector3, end: Vector3) -> Array[Vector3]:
    return navigator.find_path(start, end, grid_world.is_walkable)

func world_to_grid(world_pos: Vector3) -> Vector3i:
    return navigator.world_to_grid(world_pos)

func grid_to_world(grid_pos: Vector3i) -> Vector3:
    return navigator.grid_to_world(grid_pos)

func snap_to_grid(world_pos: Vector3) -> Vector3:
    return grid_world.snap_to_grid(world_pos)

func register_obstacle(world_pos: Vector3) -> void:
    grid_world.register_obstacle(world_pos)

func unregister_obstacle(world_pos: Vector3) -> void:
    grid_world.unregister_obstacle(world_pos)

func is_walkable(grid_pos: Vector3i) -> bool:
    return grid_world.is_walkable(grid_pos)
```

**Step 2: Commit**

```bash
git add systems/grid_movement_system.gd
git commit -m "feat: add grid movement system autoload"
```

---

## Task 9: 创建 GameWorld3D 主场景脚本

**Files:**
- Create: `scripts/locations/game_world_3d.gd`

**Step 1: 创建文件**

Create `scripts/locations/game_world_3d.gd`:
```gdscript
class_name GameWorld3D
extends Node3D

@export var player_scene: PackedScene = null
@export var show_grid_debug := false

@onready var _camera_controller: CameraController3D
@onready var _player: PlayerController3D
@onready var _grid_floor: StaticBody3D
@onready var _path_preview: PathPreview
@onready var _navigator: GridNavigator

var _is_mouse_pressed := false
var _last_hover_pos: Vector3

func _ready() -> void:
    _setup_world()
    _spawn_player()
    _setup_camera()
    _setup_input()

func _setup_world() -> void:
    _navigator = GridNavigator.new()
    
    _grid_floor = $GridFloor
    _setup_grid_floor_collision()

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
                _handle_ground_click()
    
    if event is InputEventScreenTouch:
        if event.pressed:
            _handle_touch_click(event.position)

func _process(_delta: float) -> void:
    _update_path_preview()

func _update_path_preview() -> void:
    if not _player or not _path_preview:
        return
    
    var mouse_pos := get_viewport().get_mouse_position()
    var camera := get_viewport().get_camera_3d()
    
    if not camera:
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
        _last_hover_pos = world_pos
        
        var path := _navigator.find_path(
            _player.global_position,
            world_pos,
            GridMovementSystem.grid_world.is_walkable
        )
        
        if path.size() > 1:
            _path_preview.show_path(path)
        else:
            _path_preview.hide_path()
    else:
        _path_preview.hide_path()

func _handle_ground_click() -> void:
    var mouse_pos := get_viewport().get_mouse_position()
    _try_move_to_screen_position(mouse_pos)

func _handle_touch_click(screen_pos: Vector2) -> void:
    _try_move_to_screen_position(screen_pos)

func _try_move_to_screen_position(screen_pos: Vector2) -> void:
    var camera := get_viewport().get_camera_3d()
    if not camera:
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
```

**Step 2: Commit**

```bash
git add scripts/locations/game_world_3d.gd
git commit -m "feat: add game world 3D scene controller"
```

---

## Task 10: 创建 game_world_3d.tscn 场景文件

**Files:**
- Create: `scenes/locations/game_world_3d.tscn`

**Step 1: 创建场景文件**

Create `scenes/locations/game_world_3d.tscn`:
```
[gd_scene load_steps=3 format=3 uid="uid://c8yvxg3ulq3a2"]

[ext_resource type="Script" path="res://scripts/locations/game_world_3d.gd" id="1_abc12"]

[sub_resource type="BoxMesh" id="BoxMesh_1"]
size = Vector3(100, 0.1, 100)

[node name="GameWorld3D" type="Node3D"]
script = ExtResource("1_abc12")

[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.707107, -0.5, 0.5, 0, 0.707107, 0.707107, -0.707107, -0.5, 0.5, 0, 10, 0)
shadow_enabled = true
shadow_bias = 0.05

[node name="GridFloor" type="StaticBody3D" parent="."]
collision_layer = 1

[node name="MeshInstance3D" type="MeshInstance3D" parent="GridFloor"]
mesh = SubResource("BoxMesh_1")
skeleton = NodePath("../..")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
```

**Step 2: Commit**

```bash
git add scenes/locations/game_world_3d.tscn
git commit -m "feat: add game world 3D scene"
```

---

## Task 11: 更新 EventBus 添加新事件类型

**Files:**
- Modify: `core/event_bus.gd`

**Step 1: 添加新事件类型**

Add to `EventBus.EventType` enum in `core/event_bus.gd`:
```gdscript
enum EventType {
    # ... existing events ...
    
    # Grid Movement Events
    PLAYER_MOVED,
    GRID_CLICKED,
    MOVEMENT_STARTED,
    MOVEMENT_FINISHED,
    PATH_PREVIEW_UPDATED,
}
```

**Step 2: Commit**

```bash
git add core/event_bus.gd
git commit -m "feat: add grid movement event types to EventBus"
```

---

## Task 12: 更新 GameState 添加3D位置存储

**Files:**
- Modify: `core/game_state.gd`

**Step 1: 添加3D位置变量**

Add to `core/game_state.gd`:
```gdscript
# 3D Player Position
var player_position_3d: Vector3 = Vector3.ZERO
var player_grid_position: Vector3i = Vector3i.ZERO
var is_player_moving: bool = false

func save_3d_position(pos: Vector3, grid_pos: Vector3i) -> void:
    player_position_3d = pos
    player_grid_position = grid_pos

func get_saved_3d_position() -> Vector3:
    return player_position_3d
```

**Step 2: Commit**

```bash
git add core/game_state.gd
git commit -m "feat: add 3D position tracking to GameState"
```

---

## Task 13: 更新主菜单按钮进入3D世界

**Files:**
- Modify: `scenes/ui/main_menu.gd`

**Step 1: 修改开始游戏逻辑**

Find the start game function in `scenes/ui/main_menu.gd` and modify:
```gdscript
func _on_start_game_pressed() -> void:
    # 进入3D游戏世界
    get_tree().change_scene_to_file("res://scenes/locations/game_world_3d.tscn")
```

**Step 2: Commit**

```bash
git add scenes/ui/main_menu.gd
git commit -m "feat: update main menu to enter 3D world"
```

---

## Task 14: 创建网格可视化调试工具

**Files:**
- Create: `systems/grid_visualizer.gd`

**Step 1: 创建文件**

Create `systems/grid_visualizer.gd`:
```gdscript
class_name GridVisualizer
extends Node3D

@export var grid_size := 1.0
@export var grid_range := 20
@export var line_color := Color(0.5, 0.5, 0.5, 0.3)
@export var line_width := 0.02

var _grid_mesh: MeshInstance3D = null

func _ready() -> void:
    visible = false
    _create_grid_mesh()

func show_grid() -> void:
    visible = true

func hide_grid() -> void:
    visible = false

func toggle_grid() -> void:
    visible = not visible

func _create_grid_mesh() -> void:
    _grid_mesh = MeshInstance3D.new()
    add_child(_grid_mesh)
    
    var immediate_mesh := ImmediateMesh.new()
    _grid_mesh.mesh = immediate_mesh
    _grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    
    var material := StandardMaterial3D.new()
    material.albedo_color = line_color
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _grid_mesh.material_override = material
    
    immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
    
    var start := -grid_range * grid_size
    var end := grid_range * grid_size
    
    for i in range(-grid_range, grid_range + 1):
        var pos := i * grid_size
        
        # Horizontal lines
        immediate_mesh.surface_add_vertex(Vector3(start, 0.01, pos))
        immediate_mesh.surface_add_vertex(Vector3(end, 0.01, pos))
        
        # Vertical lines
        immediate_mesh.surface_add_vertex(Vector3(pos, 0.01, start))
        immediate_mesh.surface_add_vertex(Vector3(pos, 0.01, end))
    
    immediate_mesh.surface_end()
```

**Step 2: 添加到GameWorld3D**

Modify `scripts/locations/game_world_3d.gd` _setup_world():
```gdscript
func _setup_world() -> void:
    _navigator = GridNavigator.new()
    
    _grid_floor = $GridFloor
    _setup_grid_floor_collision()
    
    # Add grid visualizer
    if show_grid_debug:
        var visualizer := GridVisualizer.new()
        add_child(visualizer)
        visualizer.show_grid()
```

**Step 3: Commit**

```bash
git add systems/grid_visualizer.gd scripts/locations/game_world_3d.gd
git commit -m "feat: add grid visualizer debug tool"
```

---

## Task 15: 测试和验证

**Files:**
- Run tests: Use existing test framework

**Step 1: 运行Godot项目**

Run: `godot --path .`

**Step 2: 验证清单**

Check these items:
- [ ] 游戏以1920x1080横屏启动
- [ ] 进入主菜单后可以点击"开始游戏"
- [ ] 进入3D世界后看到地面网格
- [ ] 玩家角色出现在场景中（蓝色方块精灵）
- [ ] 点击地面角色移动到对应网格位置
- [ ] 角色一格一格平滑移动
- [ ] 鼠标滚轮可以缩放相机
- [ ] 鼠标悬浮时显示路径预览
- [ ] 寻路可以绕过障碍物
- [ ] 2D Sprite始终正对相机

**Step 3: 修复问题**

If any check fails, fix the issue and commit:
```bash
git add [fixed files]
git commit -m "fix: resolve [issue description]"
```

**Step 4: 最终提交**

```bash
git add .
git commit -m "feat: complete 3D grid movement system implementation

- Add A* pathfinding with GridNavigator
- Implement smooth grid-based movement with GridMovement
- Create 3D player controller with Sprite3D billboard
- Add isometric camera with zoom controls
- Implement path preview on hover
- Update project to landscape 1920x1080
- Add grid movement events to EventBus
- Create 3D game world scene
- Integrate with existing GameState and EventBus"
```

---

## Summary

This plan implements a complete 3D grid-based movement system with:
- **Core Systems**: A* pathfinding, grid movement, world management
- **Controllers**: Player with 2D Sprite billboard, isometric camera with zoom
- **Interaction**: Click/touch to move, hover path preview
- **Integration**: EventBus events, GameState persistence
- **Scene**: Full 3D world scene with lighting and ground

All tasks are bite-sized (2-5 minutes each) and can be implemented sequentially.
