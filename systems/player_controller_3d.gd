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
