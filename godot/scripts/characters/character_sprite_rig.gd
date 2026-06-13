@tool
class_name CharacterSpriteRig
extends Node3D

# 绑定 Godot scene 中已经声明好的 Skeleton3D + BoneAttachment3D + Sprite3D 子树，
# 并在 _process 中按相机相对角色的 3D 方向量化到 yaw/pitch 网格，切换每个部件的 texture。
# 该节点作为 .tscn 场景根使用，不在运行时生成 rig 结构，也不负责装备等其它角色视觉。

@export var profile: SpriteRigProfile = null
@export var enable_runtime_update: bool = true
# 0 表示每帧更新；>0 时按间隔更新以省 CPU。
@export_range(0.0, 0.5, 0.01) var update_interval_seconds: float = 0.0

const SKELETON_NODE_NAME := "SpriteRigSkeleton"
const ATTACHMENT_PREFIX := "SpriteRigAttachment_"
const SPRITE_PREFIX := "SpriteRigSprite_"

var _skeleton: Skeleton3D
var _parts: Array[Dictionary] = []
var _accumulator: float = 0.0
var _last_direction_key: StringName = &""


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

		_parts.append({
			"part": part,
			"attachment": attachment,
			"sprite": sprite,
			"part_id": part_id,
		})
	_update_directions()


func _update_directions() -> void:
	var camera := _get_viewport_camera()
	if camera == null:
		return
	var direction_global := camera.global_position - global_position
	if direction_global.length_squared() <= 0.000001:
		return
	var direction_local := global_transform.basis.inverse() * direction_global
	var horizontal := Vector2(direction_local.x, direction_local.z)
	var yaw := rad_to_deg(atan2(horizontal.x, horizontal.y))
	var pitch := rad_to_deg(atan2(direction_local.y, horizontal.length()))
	var quantized: Vector3i = profile.call("quantize", yaw, pitch)
	var yaw_q: int = quantized.x
	var pitch_q: int = quantized.y
	var key: String = str(profile.call("direction_key_for", yaw_q, pitch_q))
	if key == _last_direction_key:
		return
	_last_direction_key = key
	set_meta("direction_key", key)
	set_meta("camera_yaw_degrees", yaw_q)
	set_meta("camera_pitch_degrees", pitch_q)
	for entry in _parts:
		var part: Resource = entry.get("part", null) as Resource
		var sprite: Sprite3D = entry.get("sprite", null)
		if part == null or sprite == null:
			continue
		var textures: Dictionary = part.get("angle_to_texture") if typeof(part.get("angle_to_texture")) == TYPE_DICTIONARY else {}
		var texture: Texture2D = textures.get(key, null) as Texture2D
		if texture != null:
			sprite.texture = texture
		sprite.set_meta("direction_key", key)
		sprite.set_meta("texture_resource_path", texture.resource_path if texture != null else "")


func _get_viewport_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_3d()


func _profile_array(key: String) -> Array:
	if profile == null:
		return []
	var value: Variant = profile.get(key)
	return value if typeof(value) == TYPE_ARRAY else []


func part_count() -> int:
	return _parts.size()


func direction_key() -> String:
	return String(_last_direction_key)
