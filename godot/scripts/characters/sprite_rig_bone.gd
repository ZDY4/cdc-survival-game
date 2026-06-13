@tool
class_name SpriteRigBone
extends Resource

# 单根骨骼描述，骨骼层级在 SpriteRigProfile 中通过 parent 字段扁平表达。
# 局部位置/旋转以 Skeleton3D 根骨骼坐标系为基准。

@export var name: StringName = &""
@export var parent: StringName = &""
@export var position: Vector3 = Vector3.ZERO
@export var rotation_degrees: Vector3 = Vector3.ZERO


func is_valid() -> bool:
	return String(name).strip_edges() != ""
