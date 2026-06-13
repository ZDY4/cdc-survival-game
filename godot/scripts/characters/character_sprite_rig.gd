@tool
class_name CharacterSpriteRig
extends Node3D

# 绑定 Godot scene 中已经声明好的 Skeleton3D + BoneAttachment3D + Sprite3D 子树，
# 并在 _process 中按相机相对角色的 3D 方向量化到 yaw/pitch 网格，切换每个部件的 texture。
# 该节点作为 .tscn 场景根使用，不在运行时生成 rig 结构，也不负责装备等其它角色视觉。

@export var profile: SpriteRigProfile = null
@export var enable_runtime_update: bool = true
# 默认按固定间隔检查一次，并在相机/角色未移动时跳过贴图查表。
@export_range(0.0, 0.5, 0.01) var update_interval_seconds: float = 0.05
@export var update_on_camera_change_only: bool = true
@export_range(0.0, 0.1, 0.001) var refresh_position_epsilon: float = 0.001

const SKELETON_NODE_NAME := "SpriteRigSkeleton"
const ATTACHMENT_PREFIX := "SpriteRigAttachment_"
const SPRITE_PREFIX := "SpriteRigSprite_"

var _skeleton: Skeleton3D
var _parts: Array[Dictionary] = []
var _accumulator: float = 0.0
var _last_direction_key: StringName = &""
var _cached_camera: Camera3D
var _last_camera_position := Vector3(INF, INF, INF)
var _last_rig_position := Vector3(INF, INF, INF)
var _last_rig_rotation := Vector3(INF, INF, INF)
var _direction_camera_override: Camera3D


func _ready() -> void:
	_skeleton = _find_skeleton()
	if profile == null or not bool(profile.get("enabled")):
		return
	_bind_part_nodes()
	set_process(enable_runtime_update and not Engine.is_editor_hint())


func _process(delta: float) -> void:
	if not enable_runtime_update or profile == null or _parts.is_empty():
		return
	if update_interval_seconds > 0.0:
		_accumulator += delta
		if _accumulator < update_interval_seconds:
			return
		_accumulator = 0.0
	_update_directions()


func _find_skeleton() -> Skeleton3D:
	var named_skeleton := get_node_or_null(SKELETON_NODE_NAME) as Skeleton3D
	if named_skeleton != null:
		return named_skeleton
	for child in get_children():
		if child is Skeleton3D:
			return child
	push_warning("CharacterSpriteRig 缺少 Skeleton3D: %s" % name)
	return null


func _bind_part_nodes() -> void:
	_parts.clear()
	if profile == null or _skeleton == null:
		return
	for part_value in _profile_array("sprites"):
		var part: SpriteRigSpritePart = part_value as SpriteRigSpritePart
		if part == null:
			continue
		var part_id := String(part.get("id"))
		if part_id.strip_edges().is_empty():
			continue
		var attachment := _skeleton.get_node_or_null(ATTACHMENT_PREFIX + part_id) as BoneAttachment3D
		if attachment == null:
			push_warning("SpriteRigProfile 部件 %s 缺少 BoneAttachment3D" % part_id)
			continue
		var bone_name := String(part.get("bone"))
		if bone_name != "" and _skeleton.find_bone(bone_name) >= 0:
			attachment.bone_name = bone_name
		var sprite := attachment.get_node_or_null(SPRITE_PREFIX + part_id) as Sprite3D
		if sprite == null:
			push_warning("SpriteRigProfile 部件 %s 缺少 Sprite3D" % part_id)
			continue
		sprite.pixel_size = float(part.get("pixel_size"))
		sprite.billboard = int(part.get("billboard_mode"))
		sprite.position = part.get("local_offset") if typeof(part.get("local_offset")) == TYPE_VECTOR3 else Vector3.ZERO
		sprite.rotation_degrees = part.get("local_rotation_degrees") if typeof(part.get("local_rotation_degrees")) == TYPE_VECTOR3 else Vector3.ZERO
		sprite.centered = true
		sprite.shaded = not bool(part.get("unshaded"))
		_apply_sprite_order(sprite, int(part.get("draw_order")))

		_parts.append({
			"part": part,
			"attachment": attachment,
			"sprite": sprite,
			"part_id": part_id,
		})
	_update_directions()


func _update_directions(force: bool = false) -> void:
	var camera := _get_viewport_camera()
	if camera == null:
		return
	if force:
		_remember_refresh_inputs(camera)
	elif not _should_refresh_for_camera(camera):
		return
	_apply_direction_from_world_position(_node_position(camera))


func apply_direction_from_world_position(viewer_position: Vector3) -> void:
	_ensure_part_nodes()
	_apply_direction_from_world_position(viewer_position)


func _apply_direction_from_world_position(viewer_position: Vector3) -> void:
	if profile == null:
		return
	var rig_position := _node_position(self)
	var direction_global := viewer_position - rig_position
	if direction_global.length_squared() <= 0.000001:
		return
	var direction_local := _node_basis(self).inverse() * direction_global
	var horizontal := Vector2(direction_local.x, direction_local.z)
	var yaw := rad_to_deg(atan2(horizontal.x, horizontal.y))
	var pitch := rad_to_deg(atan2(direction_local.y, horizontal.length()))
	var quantized: Vector3i = profile.call("quantize", yaw, pitch)
	var yaw_q: int = quantized.x
	var pitch_q: int = quantized.y
	var key: String = str(profile.call("direction_key_for", yaw_q, pitch_q))
	set_meta("direction_refresh_count", int(get_meta("direction_refresh_count", 0)) + 1)
	if key == _last_direction_key:
		return
	_apply_direction_key(key, yaw_q, pitch_q)


func apply_direction_key(direction_key: String, yaw_degrees: int = 0, pitch_degrees: int = 0) -> void:
	_ensure_part_nodes()
	_apply_direction_key(direction_key, yaw_degrees, pitch_degrees)


func _ensure_part_nodes() -> void:
	if _skeleton == null:
		_skeleton = _find_skeleton()
	if _parts.is_empty() and profile != null and _skeleton != null:
		_bind_part_nodes()


func _apply_direction_key(key: String, yaw_degrees: int, pitch_degrees: int) -> void:
	if profile == null:
		return
	_last_direction_key = StringName(key)
	set_meta("direction_key", key)
	set_meta("camera_yaw_degrees", yaw_degrees)
	set_meta("camera_pitch_degrees", pitch_degrees)
	for entry in _parts:
		var part: Resource = entry.get("part", null) as Resource
		var sprite: Sprite3D = entry.get("sprite", null)
		if part == null or sprite == null:
			continue
		var textures: Dictionary = part.get("angle_to_texture") if typeof(part.get("angle_to_texture")) == TYPE_DICTIONARY else {}
		var texture: Texture2D = textures.get(key, null) as Texture2D
		if texture != null:
			sprite.texture = texture
		var order := _draw_order_for(part, key)
		_apply_sprite_order(sprite, order)
		sprite.set_meta("direction_key", key)
		sprite.set_meta("draw_order", order)
		sprite.set_meta("texture_resource_path", texture.resource_path if texture != null else "")


func _get_viewport_camera() -> Camera3D:
	if is_instance_valid(_direction_camera_override):
		return _direction_camera_override
	if is_instance_valid(_cached_camera):
		return _cached_camera
	var viewport := get_viewport()
	if viewport == null:
		return null
	_cached_camera = viewport.get_camera_3d()
	return _cached_camera


func _should_refresh_for_camera(camera: Camera3D) -> bool:
	if not update_on_camera_change_only:
		return true
	if _last_direction_key == &"":
		_remember_refresh_inputs(camera)
		return true
	var rig_rotation := _node_basis(self).get_euler()
	var moved := _node_position(camera).distance_squared_to(_last_camera_position) > refresh_position_epsilon * refresh_position_epsilon \
			or _node_position(self).distance_squared_to(_last_rig_position) > refresh_position_epsilon * refresh_position_epsilon \
			or rig_rotation.distance_squared_to(_last_rig_rotation) > refresh_position_epsilon * refresh_position_epsilon
	if moved:
		_remember_refresh_inputs(camera)
	return moved


func _remember_refresh_inputs(camera: Camera3D) -> void:
	_last_camera_position = _node_position(camera)
	_last_rig_position = _node_position(self)
	_last_rig_rotation = _node_basis(self).get_euler()


func _node_position(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position


func _node_basis(node: Node3D) -> Basis:
	return node.global_transform.basis if node.is_inside_tree() else node.transform.basis


func _draw_order_for(part: Resource, direction_key: String) -> int:
	var order := int(part.get("draw_order"))
	var overrides: Dictionary = part.get("direction_draw_order") if typeof(part.get("direction_draw_order")) == TYPE_DICTIONARY else {}
	if overrides.has(direction_key):
		order = int(overrides.get(direction_key, order))
	return order


func _apply_sprite_order(sprite: Sprite3D, order: int) -> void:
	if sprite == null:
		return
	sprite.set_meta("draw_order", order)
	sprite.set("sorting_offset", float(order) * 0.001)
	sprite.set("render_priority", clampi(order, -128, 127))


func _profile_array(key: String) -> Array:
	if profile == null:
		return []
	var value: Variant = profile.get(key)
	return value if typeof(value) == TYPE_ARRAY else []


func part_count() -> int:
	return _parts.size()


func direction_key() -> String:
	return String(_last_direction_key)


func set_direction_camera_override(camera: Camera3D) -> void:
	_direction_camera_override = camera
	_cached_camera = null


func equipment_attachment_for(slot_id: String, attach_target: String = "") -> BoneAttachment3D:
	if _skeleton == null:
		_skeleton = _find_skeleton()
	if _skeleton == null:
		return null
	var part_id := equipment_part_id_for(slot_id, attach_target)
	if part_id.is_empty():
		return null
	return _skeleton.get_node_or_null(ATTACHMENT_PREFIX + part_id) as BoneAttachment3D


func equipment_part_id_for(slot_id: String, attach_target: String = "") -> String:
	var target := attach_target if not attach_target.strip_edges().is_empty() else slot_id
	match target:
		"main_hand":
			return "hand_r"
		"off_hand":
			return "hand_l"
		"hands":
			return "hand_r"
		"head":
			return "head"
		"body", "back", "accessory":
			return "body"
		"legs", "feet":
			return "foot_l"
		_:
			match slot_id:
				"main_hand":
					return "hand_r"
				"off_hand":
					return "hand_l"
				"head":
					return "head"
				"body", "back", "accessory":
					return "body"
				"legs", "feet":
					return "foot_l"
	return ""
