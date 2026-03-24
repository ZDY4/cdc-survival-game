class_name CharacterActor
extends CharacterBody3D
## Shared runtime character base for player, NPC and enemy.
## Provides temporary 4-sprite placeholder visuals (head + body + legs).
## LEGACY AUTHORITY BOUNDARY:
## Actor-side interaction helpers are temporary compatibility glue for the
## current Godot client. Avoid growing local authority here; future interaction
## and simulation ownership should continue moving to Rust runtime/protocol.

const DEFAULT_INTERACTION_STATE_TAG_NAME: StringName = &"State.Interacting"
const VISUAL_ROOT_NAME: String = "VisualRoot"
const ATTACK_LUNGE_DISTANCE_RATIO: float = 0.35
const ATTACK_LUNGE_MIN_DISTANCE: float = 0.35
const ATTACK_LUNGE_MAX_DISTANCE: float = 0.75
const ATTACK_LUNGE_FORWARD_DURATION: float = 0.08
const ATTACK_LUNGE_RETURN_DURATION: float = 0.12
const CameraController3DScript = preload("res://systems/camera_controller_3d.gd")
const InteractionSystemScript = preload("res://systems/interaction_system.gd")
const InventoryComponentScript = preload("res://systems/inventory_component.gd")
const EquipmentSystemScript = preload("res://systems/equipment_system.gd")

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
@export_custom(PROPERTY_HINT_NONE, "gameplay_tag") var interaction_state_tag: StringName = DEFAULT_INTERACTION_STATE_TAG_NAME

var _visual_root: Node3D = null
var _head_sprite: Sprite3D = null
var _body_sprite: Sprite3D = null
var _left_leg_sprite: Sprite3D = null
var _right_leg_sprite: Sprite3D = null
var _head_outline_sprite: Sprite3D = null
var _body_outline_sprite: Sprite3D = null
var _left_leg_outline_sprite: Sprite3D = null
var _right_leg_outline_sprite: Sprite3D = null
var _interaction_system: Node = null
var _gameplay_tag_stacks: Dictionary = {}
var _cached_interacting_tag: StringName = StringName()
var _warned_missing_gameplay_tags: bool = false
var _character_id: String = ""
var _character_data: Dictionary = {}
var _resolver_result: Dictionary = {}
var _hover_outline_visible: bool = false
var _hover_outline_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var _attack_lunge_tween: Tween = null
var _camera_controller: CameraController3DScript = null
var _camera_sync_retry_scheduled: bool = false
var _actor_id: String = ""
var _inventory_component: Node = null
var _equipment_component: Node = null

func _ready() -> void:
	_setup_interaction_system()
	_ensure_placeholder_sprites()
	_refresh_placeholder_textures()
	_bind_camera_pitch_sync()

func _exit_tree() -> void:
	_disconnect_camera_pitch_sync()

func set_placeholder_colors(new_head_color: Color, new_body_color: Color) -> void:
	head_color = new_head_color
	body_color = new_body_color
	if _head_sprite and _body_sprite and _left_leg_sprite and _right_leg_sprite:
		_refresh_placeholder_textures()

func set_hover_outline_visible(hover_outline_visible: bool) -> void:
	_hover_outline_visible = hover_outline_visible
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
	initialize_actor_components(_derive_actor_id(character_id, resolver_result, context), _character_data, _resolver_result, context)

	var visual: Dictionary = _character_data.get("visual", {})
	var placeholder: Dictionary = visual.get("placeholder", {})
	var resolved_head: Color = _parse_color(str(placeholder.get("head_color", "")), head_color)
	var resolved_body: Color = _parse_color(str(placeholder.get("body_color", "")), body_color)
	var resolved_leg: Color = _parse_color(str(placeholder.get("leg_color", "")), Color(0.0, 0.0, 0.0, 0.0))
	leg_color = resolved_leg
	set_placeholder_colors(resolved_head, resolved_body)

func initialize_actor_components(
	actor_id: String,
	character_data: Dictionary = {},
	resolver_result: Dictionary = {},
	context: Dictionary = {}
) -> void:
	_actor_id = actor_id.strip_edges()
	if _actor_id.is_empty():
		return
	set_meta("actor_id", _actor_id)

	var legacy_player_storage: bool = _actor_id == "player"
	if _inventory_component == null or not is_instance_valid(_inventory_component):
		_inventory_component = get_node_or_null("InventoryComponent")
	if _inventory_component == null:
		_inventory_component = InventoryComponentScript.new()
		_inventory_component.name = "InventoryComponent"
		add_child(_inventory_component)

	var initial_inventory_state: Dictionary = _build_initial_inventory_state(character_data, context)
	_inventory_component.initialize_for_actor(_actor_id, initial_inventory_state, legacy_player_storage)
	if GameState:
		GameState.register_actor_inventory_component(_actor_id, _inventory_component)
		if legacy_player_storage:
			GameState.set_player_inventory_component(_inventory_component)

	if _equipment_component == null or not is_instance_valid(_equipment_component):
		_equipment_component = get_node_or_null("EquipmentSystem")
	if _equipment_component == null:
		_equipment_component = EquipmentSystemScript.new()
		_equipment_component.name = "EquipmentSystem"
		add_child(_equipment_component)
	if _equipment_component.has_method("initialize_for_actor"):
		_equipment_component.initialize_for_actor(_actor_id, _inventory_component)
	var initial_equipment_state: Dictionary = _build_initial_equipment_state(character_data, resolver_result, context)
	if not initial_equipment_state.is_empty() and _equipment_component.has_method("load_save_data"):
		var existing_state: Dictionary = {}
		if GameState and GameState.has_method("get_actor_equipment_state"):
			existing_state = GameState.get_actor_equipment_state(_actor_id)
		if existing_state.is_empty():
			_equipment_component.load_save_data(initial_equipment_state)

func get_actor_id() -> String:
	return _actor_id if not _actor_id.is_empty() else _character_id

func get_inventory_component() -> Node:
	return _inventory_component if _inventory_component != null and is_instance_valid(_inventory_component) else get_node_or_null("InventoryComponent")

func get_equipment_component() -> Node:
	return _equipment_component if _equipment_component != null and is_instance_valid(_equipment_component) else get_node_or_null("EquipmentSystem")

func refresh_relation_state(resolver_result: Dictionary) -> void:
	_resolver_result = resolver_result.duplicate(true)
	set_meta("relation_result", _resolver_result.duplicate(true))
	set_meta("resolved_attitude", str(_resolver_result.get("resolved_attitude", "neutral")))

func _ensure_placeholder_sprites() -> void:
	_ensure_visual_root()

	_body_outline_sprite = _visual_root.get_node_or_null("BodyOutlineSprite")
	if not _body_outline_sprite:
		_body_outline_sprite = Sprite3D.new()
		_body_outline_sprite.name = "BodyOutlineSprite"
		_visual_root.add_child(_body_outline_sprite)

	_head_outline_sprite = _visual_root.get_node_or_null("HeadOutlineSprite")
	if not _head_outline_sprite:
		_head_outline_sprite = Sprite3D.new()
		_head_outline_sprite.name = "HeadOutlineSprite"
		_visual_root.add_child(_head_outline_sprite)

	_left_leg_outline_sprite = _visual_root.get_node_or_null("LeftLegOutlineSprite")
	if not _left_leg_outline_sprite:
		_left_leg_outline_sprite = Sprite3D.new()
		_left_leg_outline_sprite.name = "LeftLegOutlineSprite"
		_visual_root.add_child(_left_leg_outline_sprite)

	_right_leg_outline_sprite = _visual_root.get_node_or_null("RightLegOutlineSprite")
	if not _right_leg_outline_sprite:
		_right_leg_outline_sprite = Sprite3D.new()
		_right_leg_outline_sprite.name = "RightLegOutlineSprite"
		_visual_root.add_child(_right_leg_outline_sprite)

	_body_sprite = _visual_root.get_node_or_null("BodySprite")
	if not _body_sprite:
		_body_sprite = Sprite3D.new()
		_body_sprite.name = "BodySprite"
		_visual_root.add_child(_body_sprite)

	_head_sprite = _visual_root.get_node_or_null("HeadSprite")
	if not _head_sprite:
		_head_sprite = Sprite3D.new()
		_head_sprite.name = "HeadSprite"
		_visual_root.add_child(_head_sprite)

	_left_leg_sprite = _visual_root.get_node_or_null("LeftLegSprite")
	if not _left_leg_sprite:
		_left_leg_sprite = Sprite3D.new()
		_left_leg_sprite.name = "LeftLegSprite"
		_visual_root.add_child(_left_leg_sprite)

	_right_leg_sprite = _visual_root.get_node_or_null("RightLegSprite")
	if not _right_leg_sprite:
		_right_leg_sprite = Sprite3D.new()
		_right_leg_sprite.name = "RightLegSprite"
		_visual_root.add_child(_right_leg_sprite)

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

func get_interaction_system() -> Node:
	return _interaction_system

func get_visual_root() -> Node3D:
	_ensure_visual_root()
	return _visual_root

func get_damage_feedback_anchor() -> Node3D:
	return get_visual_root()

func get_hit_reaction_target() -> Node3D:
	return get_visual_root()

func play_attack_lunge(target_world_pos: Vector3) -> void:
	var visual_root := get_visual_root()
	if visual_root == null or not is_instance_valid(visual_root):
		return

	var lunge_direction := target_world_pos - global_position
	lunge_direction.y = 0.0
	if lunge_direction.length_squared() <= 0.0001:
		return

	if _attack_lunge_tween and _attack_lunge_tween.is_valid():
		_attack_lunge_tween.kill()
		visual_root.position = Vector3.ZERO

	var lunge_distance := clampf(
		lunge_direction.length() * ATTACK_LUNGE_DISTANCE_RATIO,
		ATTACK_LUNGE_MIN_DISTANCE,
		ATTACK_LUNGE_MAX_DISTANCE
	)
	var lunge_offset := lunge_direction.normalized() * lunge_distance

	_attack_lunge_tween = create_tween()
	_attack_lunge_tween.tween_property(
		visual_root,
		"position",
		lunge_offset,
		ATTACK_LUNGE_FORWARD_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_lunge_tween.tween_property(
		visual_root,
		"position",
		Vector3.ZERO,
		ATTACK_LUNGE_RETURN_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _attack_lunge_tween.finished

func begin_interaction_state() -> void:
	var interacting_tag: StringName = _resolve_interacting_tag()
	if String(interacting_tag).is_empty():
		return
	var current_count: int = int(_gameplay_tag_stacks.get(interacting_tag, 0))
	_gameplay_tag_stacks[interacting_tag] = current_count + 1

func end_interaction_state() -> void:
	var interacting_tag: StringName = _resolve_interacting_tag()
	if String(interacting_tag).is_empty():
		return
	var current_count: int = int(_gameplay_tag_stacks.get(interacting_tag, 0))
	if current_count <= 0:
		return
	if current_count == 1:
		_gameplay_tag_stacks.erase(interacting_tag)
		return
	_gameplay_tag_stacks[interacting_tag] = current_count - 1

func is_interacting_state() -> bool:
	var interacting_tag: StringName = _resolve_interacting_tag()
	if String(interacting_tag).is_empty():
		return false
	return int(_gameplay_tag_stacks.get(interacting_tag, 0)) > 0

func has_gameplay_tag(tag: StringName, exact: bool = false) -> bool:
	if exact:
		return int(_gameplay_tag_stacks.get(tag, 0)) > 0

	var requested_tag_text: String = String(tag)
	for existing_tag in _gameplay_tag_stacks.keys():
		if int(_gameplay_tag_stacks.get(existing_tag, 0)) <= 0:
			continue
		var existing_tag_text: String = String(existing_tag)
		if existing_tag_text == requested_tag_text:
			return true
		if existing_tag_text.begins_with(requested_tag_text + "."):
			return true
	return false

func _setup_interaction_system() -> void:
	var existing := get_node_or_null("InteractionSystem")
	if existing and existing is InteractionSystemScript:
		_interaction_system = existing as Node
		return
	_interaction_system = InteractionSystemScript.new()
	_interaction_system.name = "InteractionSystem"
	add_child(_interaction_system)

func _ensure_visual_root() -> void:
	_visual_root = get_node_or_null(VISUAL_ROOT_NAME) as Node3D
	if _visual_root != null:
		return
	_visual_root = Node3D.new()
	_visual_root.name = VISUAL_ROOT_NAME
	add_child(_visual_root)

func _bind_camera_pitch_sync() -> void:
	_camera_sync_retry_scheduled = false
	var resolved_camera := _resolve_camera_controller()
	if resolved_camera == null:
		_schedule_camera_pitch_sync_retry()
		return
	if _camera_controller == resolved_camera:
		_apply_camera_pitch_to_visual_root(_camera_controller.get_view_rotation_degrees())
		return

	_disconnect_camera_pitch_sync()
	_camera_controller = resolved_camera
	if not _camera_controller.view_rotation_changed.is_connected(_on_camera_view_rotation_changed):
		_camera_controller.view_rotation_changed.connect(_on_camera_view_rotation_changed)
	_apply_camera_pitch_to_visual_root(_camera_controller.get_view_rotation_degrees())

func _schedule_camera_pitch_sync_retry() -> void:
	if _camera_sync_retry_scheduled:
		return
	_camera_sync_retry_scheduled = true
	call_deferred("_bind_camera_pitch_sync")

func _disconnect_camera_pitch_sync() -> void:
	if _camera_controller == null:
		return
	if is_instance_valid(_camera_controller) and _camera_controller.view_rotation_changed.is_connected(_on_camera_view_rotation_changed):
		_camera_controller.view_rotation_changed.disconnect(_on_camera_view_rotation_changed)
	_camera_controller = null

func _resolve_camera_controller() -> CameraController3DScript:
	var tree := get_tree()
	if tree == null:
		return null
	var current_scene := tree.current_scene
	if current_scene == null:
		return null
	if current_scene.has_method("get_camera"):
		var camera_from_method: Variant = current_scene.call("get_camera")
		if camera_from_method is CameraController3DScript:
			return camera_from_method as CameraController3DScript
	return current_scene.get_node_or_null("CameraController3D") as CameraController3DScript

func _on_camera_view_rotation_changed(new_rotation_degrees: Vector3) -> void:
	_apply_camera_pitch_to_visual_root(new_rotation_degrees)

func _apply_camera_pitch_to_visual_root(camera_rotation_degrees: Vector3) -> void:
	var visual_root := get_visual_root()
	if visual_root == null or not is_instance_valid(visual_root):
		return
	var visual_rotation := visual_root.rotation_degrees
	if is_equal_approx(visual_rotation.x, camera_rotation_degrees.x):
		return
	visual_rotation.x = camera_rotation_degrees.x
	visual_root.rotation_degrees = visual_rotation

func _resolve_interacting_tag() -> StringName:
	if not String(_cached_interacting_tag).is_empty():
		return _cached_interacting_tag

	var manager: Node = _get_gameplay_tags_manager()
	if manager == null or not manager.has_method("request_tag"):
		if not _warned_missing_gameplay_tags:
			_warned_missing_gameplay_tags = true
			push_warning("[CharacterActor] GameplayTags manager unavailable; interaction tag disabled.")
		return StringName()

	var configured_tag_text: String = String(interaction_state_tag).strip_edges()
	if configured_tag_text.is_empty():
		return StringName()

	var requested_tag: StringName = manager.call("request_tag", configured_tag_text, false)
	if String(requested_tag).is_empty():
		if not _warned_missing_gameplay_tags:
			_warned_missing_gameplay_tags = true
			push_warning("[CharacterActor] Tag '%s' is not registered." % configured_tag_text)
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

func _derive_actor_id(character_id: String, resolver_result: Dictionary, context: Dictionary) -> String:
	if character_id.strip_edges() == "player":
		return "player"
	var spawn_id: String = str(context.get("spawn_id", "")).strip_edges()
	if bool(resolver_result.get("allow_attack", false)):
		if not spawn_id.is_empty():
			return "enemy:%s" % spawn_id
		return "enemy:%s" % character_id.strip_edges()
	return character_id.strip_edges()

func _build_initial_inventory_state(character_data: Dictionary, _context: Dictionary) -> Dictionary:
	if GameState and GameState.has_method("get_actor_inventory_state"):
		var existing_state: Dictionary = GameState.get_actor_inventory_state(_actor_id)
		if not existing_state.is_empty():
			return existing_state

	var raw_items: Array = []
	if character_data.get("inventory", []) is Array:
		raw_items = (character_data.get("inventory", []) as Array).duplicate(true)
	var normalized_items: Array[Dictionary] = []
	for entry_variant in raw_items:
		if entry_variant is Dictionary:
			var raw_entry: Dictionary = (entry_variant as Dictionary).duplicate(true)
			normalized_items.append({
				"id": str(raw_entry.get("id", "")),
				"count": int(raw_entry.get("count", 1))
			})
	return {
		"actor_id": _actor_id,
		"inventory_items": normalized_items
	}

func _build_initial_equipment_state(character_data: Dictionary, _resolver_result: Dictionary, _context: Dictionary) -> Dictionary:
	if GameState and GameState.has_method("get_actor_equipment_state"):
		var existing_state: Dictionary = GameState.get_actor_equipment_state(_actor_id)
		if not existing_state.is_empty():
			return existing_state

	var explicit_state: Variant = character_data.get("equipment", {})
	if explicit_state is Dictionary:
		var typed_state: Dictionary = (explicit_state as Dictionary).duplicate(true)
		typed_state["actor_id"] = _actor_id
		return typed_state

	var equipped_items: Variant = character_data.get("equipped_items", {})
	if equipped_items is Dictionary:
		return {
			"actor_id": _actor_id,
			"equipped_items": (equipped_items as Dictionary).duplicate(true),
			"equipped_instance_ids": (character_data.get("equipped_instance_ids", {}) as Dictionary).duplicate(true) if character_data.get("equipped_instance_ids", {}) is Dictionary else {},
			"item_instances": (character_data.get("item_instances", {}) as Dictionary).duplicate(true) if character_data.get("item_instances", {}) is Dictionary else {},
			"current_ammo": (character_data.get("current_ammo", {}) as Dictionary).duplicate(true) if character_data.get("current_ammo", {}) is Dictionary else {}
		}
	return {}
