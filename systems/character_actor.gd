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
@export var hover_outline_scale: float = 1.14
@export var hover_outline_depth_offset: float = -0.002

var _head_sprite: Sprite3D = null
var _body_sprite: Sprite3D = null
var _left_leg_sprite: Sprite3D = null
var _right_leg_sprite: Sprite3D = null
var _head_outline_sprite: Sprite3D = null
var _body_outline_sprite: Sprite3D = null
var _left_leg_outline_sprite: Sprite3D = null
var _right_leg_outline_sprite: Sprite3D = null
var _interaction_system: InteractionSystem = null
var _gameplay_tag_stack: GameplayTagStackContainer = GameplayTagStackContainer.new()
var _cached_interacting_tag: StringName = StringName()
var _warned_missing_gameplay_tags: bool = false
var _character_id: String = ""
var _character_data: Dictionary = {}
var _resolver_result: Dictionary = {}
var _hover_outline_visible: bool = false
var _hover_outline_color: Color = Color(1.0, 1.0, 1.0, 1.0)

func _ready() -> void:
	_setup_interaction_system()
	_ensure_placeholder_sprites()
	_refresh_placeholder_textures()

func set_placeholder_colors(new_head_color: Color, new_body_color: Color) -> void:
	head_color = new_head_color
	body_color = new_body_color
	if _head_sprite and _body_sprite and _left_leg_sprite and _right_leg_sprite:
		_refresh_placeholder_textures()

func set_hover_outline_visible(visible: bool) -> void:
	_hover_outline_visible = visible
	_apply_hover_outline_visibility()

func set_hover_outline_color(color: Color) -> void:
	if _hover_outline_color == color:
		return
	_hover_outline_color = color
	_refresh_hover_outline_textures()

func initialize_from_character_data(
	character_id: String,
	character_data: Dictionary,
	resolver_result: Dictionary,
	context: Dictionary = {}
) -> void:
	_character_id = character_id
	_character_data = character_data.duplicate(true)
	_resolver_result = resolver_result.duplicate(true)

	set_meta("character_id", _character_id)
	set_meta("character_data", _character_data.duplicate(true))
	set_meta("relation_result", _resolver_result.duplicate(true))
	set_meta("spawn_id", str(context.get("spawn_id", "")))
	set_meta("resolved_attitude", str(_resolver_result.get("resolved_attitude", "neutral")))

	var visual: Dictionary = _character_data.get("visual", {})
	var placeholder: Dictionary = visual.get("placeholder", {})
	var resolved_head: Color = _parse_color(str(placeholder.get("head_color", "")), head_color)
	var resolved_body: Color = _parse_color(str(placeholder.get("body_color", "")), body_color)
	var resolved_leg: Color = _parse_color(str(placeholder.get("leg_color", "")), Color(0.0, 0.0, 0.0, 0.0))
	leg_color = resolved_leg
	set_placeholder_colors(resolved_head, resolved_body)

func refresh_relation_state(resolver_result: Dictionary) -> void:
	_resolver_result = resolver_result.duplicate(true)
	set_meta("relation_result", _resolver_result.duplicate(true))
	set_meta("resolved_attitude", str(_resolver_result.get("resolved_attitude", "neutral")))

func _ensure_placeholder_sprites() -> void:
	_body_outline_sprite = get_node_or_null("BodyOutlineSprite")
	if not _body_outline_sprite:
		_body_outline_sprite = Sprite3D.new()
		_body_outline_sprite.name = "BodyOutlineSprite"
		add_child(_body_outline_sprite)

	_head_outline_sprite = get_node_or_null("HeadOutlineSprite")
	if not _head_outline_sprite:
		_head_outline_sprite = Sprite3D.new()
		_head_outline_sprite.name = "HeadOutlineSprite"
		add_child(_head_outline_sprite)

	_left_leg_outline_sprite = get_node_or_null("LeftLegOutlineSprite")
	if not _left_leg_outline_sprite:
		_left_leg_outline_sprite = Sprite3D.new()
		_left_leg_outline_sprite.name = "LeftLegOutlineSprite"
		add_child(_left_leg_outline_sprite)

	_right_leg_outline_sprite = get_node_or_null("RightLegOutlineSprite")
	if not _right_leg_outline_sprite:
		_right_leg_outline_sprite = Sprite3D.new()
		_right_leg_outline_sprite.name = "RightLegOutlineSprite"
		add_child(_right_leg_outline_sprite)

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

	for sprite in [
		_body_outline_sprite,
		_head_outline_sprite,
		_left_leg_outline_sprite,
		_right_leg_outline_sprite,
		_body_sprite,
		_head_sprite,
		_left_leg_sprite,
		_right_leg_sprite
	]:
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		sprite.pixel_size = sprite_pixel_size

	_layout_placeholder_sprites()
	_apply_hover_outline_visibility()

func _refresh_placeholder_textures() -> void:
	_body_sprite.texture = _create_body_texture(body_sprite_size, body_color)
	_head_sprite.texture = _create_head_texture(head_sprite_size, head_color)
	var resolved_leg_color: Color = _resolve_leg_color()
	_left_leg_sprite.texture = _create_leg_texture(leg_sprite_size, resolved_leg_color)
	_right_leg_sprite.texture = _create_leg_texture(leg_sprite_size, resolved_leg_color)
	_refresh_hover_outline_textures()

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

func _parse_color(color_text: String, fallback: Color) -> Color:
	if color_text.strip_edges().is_empty():
		return fallback
	return Color.from_string(color_text, fallback)

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

	var outline_scale_vector := Vector3(hover_outline_scale, hover_outline_scale, 1.0)
	_left_leg_outline_sprite.position = _left_leg_sprite.position + Vector3(0.0, 0.0, hover_outline_depth_offset)
	_right_leg_outline_sprite.position = _right_leg_sprite.position + Vector3(0.0, 0.0, hover_outline_depth_offset)
	_body_outline_sprite.position = _body_sprite.position + Vector3(0.0, 0.0, hover_outline_depth_offset)
	_head_outline_sprite.position = _head_sprite.position + Vector3(0.0, 0.0, hover_outline_depth_offset)
	_left_leg_outline_sprite.scale = outline_scale_vector
	_right_leg_outline_sprite.scale = outline_scale_vector
	_body_outline_sprite.scale = outline_scale_vector
	_head_outline_sprite.scale = outline_scale_vector

func _refresh_hover_outline_textures() -> void:
	if _body_outline_sprite == null or _head_outline_sprite == null:
		return
	_body_outline_sprite.texture = _create_body_texture(body_sprite_size, _hover_outline_color)
	_head_outline_sprite.texture = _create_head_texture(head_sprite_size, _hover_outline_color)
	_left_leg_outline_sprite.texture = _create_leg_texture(leg_sprite_size, _hover_outline_color)
	_right_leg_outline_sprite.texture = _create_leg_texture(leg_sprite_size, _hover_outline_color)

func _apply_hover_outline_visibility() -> void:
	for sprite in [
		_body_outline_sprite,
		_head_outline_sprite,
		_left_leg_outline_sprite,
		_right_leg_outline_sprite
	]:
		if sprite != null:
			sprite.visible = _hover_outline_visible
