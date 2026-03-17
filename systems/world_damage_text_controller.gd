class_name WorldDamageTextController
extends Node3D

const FLOAT_DURATION: float = 0.6
const BASE_UPWARD_OFFSET: Vector3 = Vector3(0.0, 0.9, 0.0)
const NORMAL_COLOR: Color = Color(1.0, 0.95, 0.65, 1.0)
const CRITICAL_COLOR: Color = Color(1.0, 0.45, 0.2, 1.0)

func _ready() -> void:
	top_level = true
	global_position = Vector3.ZERO

func show_damage_number(target: Node3D, amount: int, is_critical: bool = false) -> void:
	if target == null or not is_instance_valid(target):
		return

	var anchor := _resolve_feedback_anchor(target)
	if anchor == null or not is_instance_valid(anchor):
		return

	var label := Label3D.new()
	label.name = "DamageNumber"
	label.text = "!" + str(amount) if is_critical else str(amount)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 56 if is_critical else 44
	label.modulate = CRITICAL_COLOR if is_critical else NORMAL_COLOR
	label.outline_size = 6
	label.no_depth_test = false
	label.position = anchor.global_position + BASE_UPWARD_OFFSET + _build_random_offset()
	label.scale = Vector3.ONE * (1.1 if is_critical else 0.95)
	add_child(label)

	var end_position := label.position + Vector3(randf_range(-0.08, 0.08), 0.65, randf_range(-0.06, 0.06))
	var end_scale := Vector3.ONE * (1.25 if is_critical else 1.05)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", end_position, FLOAT_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", end_scale, FLOAT_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, FLOAT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(label.queue_free, CONNECT_ONE_SHOT)

func _resolve_feedback_anchor(target: Node3D) -> Node3D:
	if target.has_method("get_damage_feedback_anchor"):
		var explicit_anchor: Variant = target.call("get_damage_feedback_anchor")
		if explicit_anchor is Node3D and is_instance_valid(explicit_anchor):
			return explicit_anchor as Node3D

	var visual_root := target.get_node_or_null("VisualRoot")
	if visual_root is Node3D and is_instance_valid(visual_root):
		return visual_root as Node3D

	if target.has_method("get_hover_outline_target"):
		var hover_target: Variant = target.call("get_hover_outline_target")
		if hover_target is Node3D and is_instance_valid(hover_target):
			return hover_target as Node3D

	return target

func _build_random_offset() -> Vector3:
	return Vector3(
		randf_range(-0.12, 0.12),
		randf_range(-0.03, 0.06),
		randf_range(-0.08, 0.08)
	)
