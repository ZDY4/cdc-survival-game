@tool
class_name SpriteRigSpritePart
extends Resource

# 部件描述。每个部件绑定到一根骨骼，运行时 Sprite3D 跟随该骨骼空间，
# 贴图按 yaw/pitch key 在 profile 步长网格中查表。

@export var id: StringName = &""
@export var bone: StringName = &""
@export var pixel_size: float = 0.0025
@export var local_offset: Vector3 = Vector3.ZERO
@export var local_rotation_degrees: Vector3 = Vector3.ZERO
@export var draw_order: int = 0
@export var billboard_mode: BaseMaterial3D.BillboardMode = BaseMaterial3D.BILLBOARD_ENABLED
@export var unshaded: bool = true
# yaw/pitch key 到贴图的映射。key 形如 yaw_045_pitch_neg45，value 为 Texture2D。
@export var angle_to_texture: Dictionary = {}


func is_valid() -> bool:
	return String(id).strip_edges() != ""


func has_texture_for_key(direction_key: String) -> bool:
	return angle_to_texture.has(direction_key) and angle_to_texture.get(direction_key) != null
