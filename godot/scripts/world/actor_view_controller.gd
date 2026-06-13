extends RefCounted

const GRID_SIZE := 1.0
const DEFAULT_ACTOR_Y := 0.58
const STEP_DURATION_SEC := 0.07
const ATTACK_DURATION_SEC := 0.12

var world_container: Node3D
var active_actor_id := 0
var active_tween: Tween
var active_node_ref: WeakRef
var latest: Dictionary = {"active": false, "kind": "none"}


func attach(p_world_container: Node3D) -> void:
	world_container = p_world_container


func actor_node(actor_id: int) -> Node3D:
	if world_container == null:
		return null
	var pending: Array[Node] = [world_container]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var node_3d := node as Node3D
		if node_3d != null and int(node_3d.get_meta("actor_id", 0)) == actor_id:
			return node_3d
		for child in node.get_children():
			pending.append(child)
	return null


func active_actor_node(actor_id: int = 0) -> Node3D:
	if active_node_ref == null:
		return null
	var node := active_node_ref.get_ref() as Node3D
	if node == null or node.is_queued_for_deletion():
		return null
	if actor_id > 0 and int(node.get_meta("actor_id", 0)) != actor_id:
		return null
	if not bool(node.get_meta("action_runner_active", false)):
		return null
	return node


func move_actor_step(host: Node, actor_id: int, from_grid: Dictionary, to_grid: Dictionary, options: Dictionary = {}) -> Dictionary:
	var node := actor_node(actor_id)
	if node == null:
		latest = {
			"active": false,
			"kind": "move_step",
			"success": false,
			"reason": "actor_node_missing",
			"actor_id": actor_id,
		}
		return latest.duplicate(true)
	_finish_active_actor_presentation(actor_id, "new_step")
	var duration := float(options.get("duration_sec", STEP_DURATION_SEC))
	var y := node.position.y
	node.position = _grid_to_world(from_grid, y)
	node.rotation_degrees = Vector3(node.rotation_degrees.x, _yaw_degrees(from_grid, to_grid, node.rotation_degrees.y), node.rotation_degrees.z)
	node.set_meta("action_runner_active", true)
	node.set_meta("action_runner_step_active", true)
	node.set_meta("action_runner_kind", "move_step")
	node.set_meta("action_runner_actor_id", actor_id)
	node.set_meta("action_runner_from_grid", from_grid.duplicate(true))
	node.set_meta("action_runner_to_grid", to_grid.duplicate(true))
	node.set_meta("action_presenter_final_position", _grid_to_world(to_grid, y))
	active_actor_id = actor_id
	active_node_ref = weakref(node)
	active_tween = host.create_tween() if host != null else null
	latest = {
		"active": true,
		"kind": "move_step",
		"success": true,
		"actor_id": actor_id,
		"from_grid": from_grid.duplicate(true),
		"to_grid": to_grid.duplicate(true),
		"duration_sec": duration,
		"node_path": str(node.get_path()),
		"node_instance_id": node.get_instance_id(),
	}
	if active_tween == null:
		_finish_active_actor_presentation(actor_id, "no_tween")
		return latest.duplicate(true)
	active_tween.set_trans(Tween.TRANS_SINE)
	active_tween.set_ease(Tween.EASE_IN_OUT)
	active_tween.tween_property(node, "position", _grid_to_world(to_grid, y), duration)
	active_tween.finished.connect(Callable(self, "_on_step_tween_finished").bind(actor_id))
	return latest.duplicate(true)


func play_attack(host: Node, actor_id: int, target_actor_id: int, result: Dictionary, options: Dictionary = {}) -> Dictionary:
	var node := actor_node(actor_id)
	var target_node := actor_node(target_actor_id)
	if node == null:
		latest = {
			"active": false,
			"kind": "attack",
			"success": false,
			"reason": "actor_node_missing",
			"actor_id": actor_id,
			"target_actor_id": target_actor_id,
		}
		return latest.duplicate(true)
	_finish_active_actor_presentation(actor_id, "new_attack", true)
	var duration := float(options.get("duration_sec", ATTACK_DURATION_SEC))
	var original_position := node.position
	var target_grid: Dictionary = _dictionary_or_empty(result.get("target_grid", {}))
	if target_grid.is_empty() and target_node != null:
		target_grid = _world_to_grid(target_node.global_position)
	var actor_grid: Dictionary = _dictionary_or_empty(result.get("attacker_grid", {}))
	if actor_grid.is_empty():
		actor_grid = _world_to_grid(node.global_position)
	if not target_grid.is_empty():
		node.rotation_degrees = Vector3(node.rotation_degrees.x, _yaw_degrees(actor_grid, target_grid, node.rotation_degrees.y), node.rotation_degrees.z)
	node.set_meta("action_runner_active", true)
	node.set_meta("action_runner_step_active", true)
	node.set_meta("action_runner_kind", "attack")
	node.set_meta("action_runner_actor_id", actor_id)
	node.set_meta("action_runner_target_actor_id", target_actor_id)
	node.set_meta("action_runner_hit_kind", str(result.get("hit_kind", "")))
	node.set_meta("action_presenter_final_position", original_position)
	active_actor_id = actor_id
	active_node_ref = weakref(node)
	active_tween = host.create_tween() if host != null else null
	latest = {
		"active": true,
		"kind": "attack",
		"success": true,
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"duration_sec": duration,
		"hit_kind": str(result.get("hit_kind", "")),
		"node_path": str(node.get_path()),
		"node_instance_id": node.get_instance_id(),
	}
	if active_tween == null:
		_finish_active_actor_presentation(actor_id, "no_tween")
		return latest.duplicate(true)
	var lunge := Vector3.ZERO
	if target_node != null:
		var direction := target_node.global_position - node.global_position
		direction.y = 0.0
		if direction.length() > 0.001:
			lunge = direction.normalized() * 0.12
	active_tween.set_trans(Tween.TRANS_SINE)
	active_tween.set_ease(Tween.EASE_IN_OUT)
	active_tween.tween_property(node, "position", original_position + lunge, duration * 0.45)
	active_tween.tween_property(node, "position", original_position, duration * 0.55)
	active_tween.finished.connect(Callable(self, "_on_step_tween_finished").bind(actor_id))
	return latest.duplicate(true)


func is_active() -> bool:
	var node := _active_node_ref()
	return node != null and bool(node.get_meta("action_runner_step_active", false)) and active_tween != null and active_tween.is_valid() and active_tween.is_running()


func finish_active_actor_presentation(actor_id: int = 0) -> Dictionary:
	var result: Dictionary = _finish_active_actor_presentation(actor_id, "fast_forward", true)
	active_actor_id = 0
	active_node_ref = null
	result["active"] = false
	result["action_active"] = false
	latest = result.duplicate(true)
	return result


func clear_actor_action_state(actor_id: int = 0, reason: String = "finished") -> Dictionary:
	var node := active_actor_node(actor_id if actor_id > 0 else active_actor_id)
	if node == null and actor_id > 0:
		node = actor_node(actor_id)
	if node != null:
		node.set_meta("action_runner_active", false)
		node.set_meta("action_runner_step_active", false)
		node.set_meta("action_runner_clear_reason", reason)
	if active_actor_id == actor_id or actor_id <= 0:
		active_actor_id = 0
		active_node_ref = null
	var result := latest.duplicate(true)
	result["active"] = false
	result["action_active"] = false
	result["finish_reason"] = reason
	latest = result.duplicate(true)
	return result


func snapshot() -> Dictionary:
	var output := latest.duplicate(true)
	output["active"] = is_active()
	output["action_active"] = active_actor_node(active_actor_id) != null
	output["active_actor_id"] = active_actor_id
	var node := active_actor_node(active_actor_id)
	output["node_instance_id"] = node.get_instance_id() if node != null else 0
	output["node_position"] = node.global_position if node != null else Vector3.ZERO
	return output


func _on_step_tween_finished(actor_id: int) -> void:
	_finish_active_actor_presentation(actor_id, "finished", false)


func _finish_active_actor_presentation(actor_id: int = 0, reason: String = "finished", clear_action_state: bool = false) -> Dictionary:
	if active_tween != null and active_tween.is_valid() and active_tween.is_running():
		active_tween.kill()
	var node := _active_node_ref()
	if node != null and actor_id > 0 and int(node.get_meta("actor_id", 0)) != actor_id:
		node = null
	if node == null:
		node = actor_node(actor_id if actor_id > 0 else active_actor_id)
	if node != null:
		if node.has_meta("action_presenter_final_position"):
			var final_position: Variant = node.get_meta("action_presenter_final_position")
			if typeof(final_position) == TYPE_VECTOR3:
				node.position = final_position
		node.set_meta("action_runner_step_active", false)
		if clear_action_state:
			node.set_meta("action_runner_active", false)
	active_tween = null
	var result := latest.duplicate(true)
	result["active"] = false
	result["action_active"] = active_actor_node(active_actor_id) != null
	result["finish_reason"] = reason
	latest = result.duplicate(true)
	return result


func _active_node_ref() -> Node3D:
	if active_node_ref == null:
		return null
	var node := active_node_ref.get_ref() as Node3D
	if node == null or node.is_queued_for_deletion():
		return null
	return node


func _grid_to_world(grid: Dictionary, y: float = DEFAULT_ACTOR_Y) -> Vector3:
	return Vector3(float(grid.get("x", 0)) * GRID_SIZE, y, float(grid.get("z", 0)) * GRID_SIZE)


func _world_to_grid(position: Vector3) -> Dictionary:
	return {
		"x": int(round(position.x / GRID_SIZE)),
		"y": 0,
		"z": int(round(position.z / GRID_SIZE)),
	}


func _yaw_degrees(from_grid: Dictionary, to_grid: Dictionary, fallback: float) -> float:
	var dx := int(to_grid.get("x", 0)) - int(from_grid.get("x", 0))
	var dz := int(to_grid.get("z", 0)) - int(from_grid.get("z", 0))
	if dx == 0 and dz == 0:
		return fallback
	if abs(dx) >= abs(dz):
		return 90.0 if dx > 0 else 270.0
	return 180.0 if dz > 0 else 0.0


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
