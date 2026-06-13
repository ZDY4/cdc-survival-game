@tool
class_name SpriteRigProfile
extends Resource

# 球面视角采样 Sprite Rig 的总配置：包含启用开关、步长、骨骼列表、部件列表。
# 一个 .tres 资源文件描述一个角色的视觉定义；角色 .tscn 用 Godot 原生节点承载骨骼和部件。

const DEFAULT_YAW_STEP_DEGREES := 45
const DEFAULT_PITCH_STEP_DEGREES := 45
const PITCH_MIN_DEGREES := -90
const PITCH_MAX_DEGREES := 90

@export var enabled: bool = true
@export_range(1, 360, 1) var yaw_step_degrees: int = DEFAULT_YAW_STEP_DEGREES
@export_range(1, 180, 1) var pitch_step_degrees: int = DEFAULT_PITCH_STEP_DEGREES
@export var bones: Array[SpriteRigBone] = []
@export var sprites: Array[SpriteRigSpritePart] = []


func yaw_angles() -> Array[int]:
	var output: Array[int] = []
	if yaw_step_degrees <= 0:
		return output
	var yaw := 0
	while yaw < 360:
		output.append(yaw)
		yaw += yaw_step_degrees
	return output


func pitch_angles() -> Array[int]:
	var output: Array[int] = []
	if pitch_step_degrees <= 0:
		return output
	var pitch := PITCH_MIN_DEGREES
	while pitch <= PITCH_MAX_DEGREES:
		output.append(pitch)
		pitch += pitch_step_degrees
	return output


func quantize(yaw_degrees: float, pitch_degrees: float) -> Vector3i:
	var yaw := _wrap_to_step(yaw_degrees, yaw_step_degrees)
	var pitch := _clamp_to_step(pitch_degrees, pitch_step_degrees, PITCH_MIN_DEGREES, PITCH_MAX_DEGREES)
	return Vector3i(yaw, pitch, 0)


func direction_key_for(yaw_degrees: int, pitch_degrees: int) -> String:
	var pitch_label := str(pitch_degrees) if pitch_degrees >= 0 else "neg%s" % abs(pitch_degrees)
	return "yaw_%03d_pitch_%s" % [wrapi(yaw_degrees, 0, 360), pitch_label]


func _wrap_to_step(value: float, step: int) -> int:
	if step <= 0:
		return 0
	var normalized := fposmod(value, 360.0)
	var rounded := int(round(normalized / float(step))) * step
	return wrapi(rounded, 0, 360)


func _clamp_to_step(value: float, step: int, min_value: int, max_value: int) -> int:
	if step <= 0:
		return 0
	var clamped := clampf(value, float(min_value), float(max_value))
	var rounded := int(round(clamped / float(step))) * step
	return clampi(rounded, min_value, max_value)
