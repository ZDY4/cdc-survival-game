class_name CharacterActor
extends CharacterBody3D
## Shared runtime character base for player, NPC and enemy.
## Provides temporary 4-sprite placeholder visuals (head + body + legs).

const InteractionSystem = preload("res://systems/interaction_system.gd")
const GameplayTagStackContainer = preload("res://addons/gameplay_tags/runtime/gameplay_tag_stack_container.gd")

const STATE_INTERACTING_TAG_NAME: String = "State.Interacting"

@export var head_color: Color = Color(0.95, 0.84, 0.70, 1.0)
@export var body_color: Color = Color(0.30, 0.58, 0.90, 1.0)
@export var leg_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var sprite_pixel_size: float = 0.01
@export var body_sprite_size: Vector2i = Vector2i(44, 67)
@export var head_sprite_size: Vector2i = Vector2i(40, 40)
@export var leg_sprite_size: Vector2i = Vector2i(14, 34)
@export var leg_spacing: float = 0.22
@export var leg_height: float = 0.0

var _head_sprite: Sprite3D = null
var _body_sprite: Sprite3D = null
var _left_leg_sprite: Sprite3D = null
var _right_leg_sprite: Sprite3D = null
var _interaction_system: InteractionSystem = null
var _gameplay_tag_stack: GameplayTagStackContainer = GameplayTagStackContainer.new()
var _cached_interacting_tag: StringName = StringName()
var _warned_missing_gameplay_tags: bool = false

func _ready() -> void:
    _setup_interaction_system()
    _ensure_placeholder_sprites()
    _refresh_placeholder_textures()

func set_placeholder_colors(new_head_color: Color, new_body_color: Color) -> void:
    head_color = new_head_color
    body_color = new_body_color
    if _head_sprite and _body_sprite and _left_leg_sprite and _right_leg_sprite:
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

    _left_leg_sprite = get_node_or_null("LeftLegSprite")
    if not _left_leg_sprite:
        _left_leg_sprite = Sprite3D.new()
        _left_leg_sprite.name = "LeftLegSprite"
        add_child(_left_leg_sprite)

    _right_leg_sprite = get_node_or_null("RightLegSprite")
    if not _right_leg_sprite:
        _right_leg_sprite = Sprite3D.new()
        _right_leg_sprite.name = "RightLegSprite"
        add_child(_right_leg_sprite)

    for sprite in [_body_sprite, _head_sprite, _left_leg_sprite, _right_leg_sprite]:
        sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
        sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
        sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
        sprite.pixel_size = sprite_pixel_size

    _layout_placeholder_sprites()

func _refresh_placeholder_textures() -> void:
    _body_sprite.texture = _create_body_texture(body_sprite_size, body_color)
    _head_sprite.texture = _create_head_texture(head_sprite_size, head_color)
    var resolved_leg_color: Color = _resolve_leg_color()
    _left_leg_sprite.texture = _create_leg_texture(leg_sprite_size, resolved_leg_color)
    _right_leg_sprite.texture = _create_leg_texture(leg_sprite_size, resolved_leg_color)

func get_interaction_system() -> InteractionSystem:
    return _interaction_system

func begin_interaction_state() -> void:
    var interacting_tag: StringName = _resolve_interacting_tag()
    if String(interacting_tag).is_empty():
        return
    _gameplay_tag_stack.add_stack(interacting_tag, 1)

func end_interaction_state() -> void:
    var interacting_tag: StringName = _resolve_interacting_tag()
    if String(interacting_tag).is_empty():
        return
    if _gameplay_tag_stack.get_stack_count(interacting_tag) <= 0:
        return
    _gameplay_tag_stack.remove_stack(interacting_tag, 1)

func is_interacting_state() -> bool:
    var interacting_tag: StringName = _resolve_interacting_tag()
    if String(interacting_tag).is_empty():
        return false
    return _gameplay_tag_stack.get_stack_count(interacting_tag) > 0

func has_gameplay_tag(tag: StringName, exact: bool = false) -> bool:
    return _gameplay_tag_stack.has_tag(tag, exact)

func _setup_interaction_system() -> void:
    var existing := get_node_or_null("InteractionSystem")
    if existing and existing is InteractionSystem:
        _interaction_system = existing
        return
    _interaction_system = InteractionSystem.new()
    _interaction_system.name = "InteractionSystem"
    add_child(_interaction_system)

func _resolve_interacting_tag() -> StringName:
    if not String(_cached_interacting_tag).is_empty():
        return _cached_interacting_tag

    var manager: Node = _get_gameplay_tags_manager()
    if manager == null or not manager.has_method("request_tag"):
        if not _warned_missing_gameplay_tags:
            _warned_missing_gameplay_tags = true
            push_warning("[CharacterActor] GameplayTags manager unavailable; interaction tag disabled.")
        return StringName()

    var requested_tag: StringName = manager.call("request_tag", STATE_INTERACTING_TAG_NAME, false)
    if String(requested_tag).is_empty():
        if not _warned_missing_gameplay_tags:
            _warned_missing_gameplay_tags = true
            push_warning("[CharacterActor] Tag '%s' is not registered." % STATE_INTERACTING_TAG_NAME)
        return StringName()

    _cached_interacting_tag = requested_tag
    return _cached_interacting_tag

func _get_gameplay_tags_manager() -> Node:
    var tree := get_tree()
    if tree == null or tree.root == null:
        return null
    return tree.root.get_node_or_null("GameplayTags")

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

func _create_leg_texture(size: Vector2i, color: Color) -> Texture2D:
    var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))

    var margin := 1
    var min_x := margin
    var max_x := size.x - margin - 1
    var min_y := margin
    var max_y := size.y - margin - 1
    for y in range(size.y):
        for x in range(size.x):
            if x >= min_x and x <= max_x and y >= min_y and y <= max_y:
                image.set_pixel(x, y, color)

    return ImageTexture.create_from_image(image)

func _resolve_leg_color() -> Color:
    if leg_color.a > 0.0:
        return leg_color
    return body_color.darkened(0.22)

func _layout_placeholder_sprites() -> void:
    var leg_total_height: float = float(leg_sprite_size.y) * sprite_pixel_size
    var body_total_height: float = float(body_sprite_size.y) * sprite_pixel_size
    var head_total_height: float = float(head_sprite_size.y) * sprite_pixel_size

    var leg_center_y: float = (leg_total_height * 0.5) + leg_height
    var body_center_y: float = leg_total_height + (body_total_height * 0.5) - 0.02 + leg_height
    var head_center_y: float = body_center_y + (body_total_height * 0.5) + (head_total_height * 0.5) - 0.01

    _left_leg_sprite.position = Vector3(-leg_spacing * 0.5, leg_center_y, 0.0)
    _right_leg_sprite.position = Vector3(leg_spacing * 0.5, leg_center_y, 0.0)
    _body_sprite.position = Vector3(0.0, body_center_y, 0.0)
    _head_sprite.position = Vector3(0.0, head_center_y, 0.0)
