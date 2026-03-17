extends Node

const NODE_NAME: String = "HitReaction3D"
const SHAKE_OFFSETS: Array[Vector3] = [
	Vector3(-0.10, 0.0, 0.06),
	Vector3(0.09, 0.0, -0.05),
	Vector3(-0.05, 0.0, -0.04),
	Vector3(0.04, 0.0, 0.03)
]
const SHAKE_STEP_DURATION: float = 0.03
const RETURN_DURATION: float = 0.05

var _shake_tween: Tween = null
var _current_target: Node3D = null
var _base_position: Vector3 = Vector3.ZERO

static func get_or_create(target: Node3D):
	if target == null or not is_instance_valid(target):
		return null

	var existing := target.get_node_or_null(NODE_NAME)
	if existing != null and existing.has_method("play_hit_shake"):
		return existing

	var reaction := new()
	reaction.name = NODE_NAME
	target.add_child(reaction)
	return reaction

func play_hit_shake() -> void:
	var host := get_parent() as Node3D
	if host == null or not is_instance_valid(host):
		return

	var reaction_target := _resolve_reaction_target(host)
	if reaction_target == null or not is_instance_valid(reaction_target):
		return

	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
		if _current_target != null and is_instance_valid(_current_target):
			_current_target.position = _base_position

	_current_target = reaction_target
	_base_position = reaction_target.position

	_shake_tween = create_tween()
	for shake_offset in SHAKE_OFFSETS:
		_shake_tween.tween_property(
			reaction_target,
			"position",
			_base_position + shake_offset,
			SHAKE_STEP_DURATION
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_shake_tween.tween_property(
		reaction_target,
		"position",
		_base_position,
		RETURN_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_shake_tween.finished.connect(_on_shake_finished, CONNECT_ONE_SHOT)

func _resolve_reaction_target(target: Node3D) -> Node3D:
	if target.has_method("get_hit_reaction_target"):
		var explicit_target: Variant = target.call("get_hit_reaction_target")
		if explicit_target is Node3D and is_instance_valid(explicit_target):
			return explicit_target as Node3D

	var visual_root := target.get_node_or_null("VisualRoot")
	if visual_root is Node3D and is_instance_valid(visual_root):
		return visual_root as Node3D

	if target.has_method("get_hover_outline_target"):
		var hover_target: Variant = target.call("get_hover_outline_target")
		if hover_target is Node3D and is_instance_valid(hover_target):
			return hover_target as Node3D

	return target

func _on_shake_finished() -> void:
	if _current_target != null and is_instance_valid(_current_target):
		_current_target.position = _base_position
