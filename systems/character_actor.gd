class_name CharacterActor
extends CharacterBody3D
## Shared runtime character base for player, NPC and enemy.
## Provides temporary 2-sprite placeholder visuals (head + body).

@export var head_color: Color = Color(0.95, 0.84, 0.70, 1.0)
@export var body_color: Color = Color(0.30, 0.58, 0.90, 1.0)
@export var sprite_pixel_size: float = 0.01
@export var body_sprite_size: Vector2i = Vector2i(44, 84)
@export var head_sprite_size: Vector2i = Vector2i(40, 40)

var _head_sprite: Sprite3D = null
var _body_sprite: Sprite3D = null

func _ready() -> void:
    _ensure_placeholder_sprites()
    _refresh_placeholder_textures()

func set_placeholder_colors(new_head_color: Color, new_body_color: Color) -> void:
    head_color = new_head_color
    body_color = new_body_color
    if _head_sprite and _body_sprite:
        _refresh_placeholder_textures()

func _ensure_placeholder_sprites() -> void:
    _body_sprite = get_node_or_null("BodySprite")
    if not _body_sprite:
        _body_sprite = Sprite3D.new()
        _body_sprite.name = "BodySprite"
        add_child(_body_sprite)

    _head_sprite = get_node_or_null("HeadSprite")
    if not _head_sprite:
        _head_sprite = Sprite3D.new()
        _head_sprite.name = "HeadSprite"
        add_child(_head_sprite)

    for sprite in [_body_sprite, _head_sprite]:
        sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
        sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
        sprite.pixel_size = sprite_pixel_size

    _body_sprite.position = Vector3(0.0, 1.0, 0.0)
    _head_sprite.position = Vector3(0.0, 1.72, 0.0)

func _refresh_placeholder_textures() -> void:
    _body_sprite.texture = _create_body_texture(body_sprite_size, body_color)
    _head_sprite.texture = _create_head_texture(head_sprite_size, head_color)

func _create_head_texture(size: Vector2i, color: Color) -> Texture2D:
    var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))

    var center := Vector2((size.x - 1) * 0.5, (size.y - 1) * 0.5)
    var radius := float(mini(size.x, size.y)) * 0.45
    for y in range(size.y):
        for x in range(size.x):
            if Vector2(x, y).distance_to(center) <= radius:
                image.set_pixel(x, y, color)

    return ImageTexture.create_from_image(image)

func _create_body_texture(size: Vector2i, color: Color) -> Texture2D:
    var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))

    var margin := 2
    var min_x := margin
    var max_x := size.x - margin - 1
    var min_y := margin
    var max_y := size.y - margin - 1
    for y in range(size.y):
        for x in range(size.x):
            if x >= min_x and x <= max_x and y >= min_y and y <= max_y:
                image.set_pixel(x, y, color)

    return ImageTexture.create_from_image(image)
