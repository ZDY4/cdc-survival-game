extends RefCounted

const GRID_SIZE := 1.0
const DEFAULT_ACTOR_Y := 0.58
const STEP_DURATION_SEC := 0.07
const ATTACK_DURATION_SEC := 0.12

var world_container: Node3D
var active_actor_id := 0
var active_tween: Tween
var active_node_ref: WeakRef
var background_tweens: Dictionary = {}
var latest: Dictionary = {"active": false, "kind": "none"}
var _active_token := 0
var _foreground_completed: Dictionary = {}
var _background_tokens: Dictionary = {}
var _background_completed: Dictionary = {}
# Per-frame cache of actor_id -> Node3D. actor_node() 和 _actor_nodes_snapshot()
# 原本各自遍历整棵 world_container（成千上万节点），且一帧会被调用数十次。
# 缓存让每帧最多遍历一次世界树，其余调用走字典查询。
var _actor_node_map: Dictionary = {}
var _actor_node_map_frame := -1


func attach(p_world_container: Node3D) -> void:
	world_container = p_world_container


func _actor_node_map_for_frame() -> Dictionary:
	var frame := Engine.get_process_frames()
	if frame == _actor_node_map_frame:
		return _actor_node_map
	_actor_node_map = {}
	_actor_node_map_frame = frame
	if world_container == null:
		return _actor_node_map
	var pending: Array[Node] = [world_container]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var node_3d := node as Node3D
		if node_3d != null and node_3d.has_meta("actor_id"):
			var aid := int(node_3d.get_meta("actor_id", 0))
			if aid > 0 and not _actor_node_map.has(aid):
				_actor_node_map[aid] = node_3d
		for child in node.get_children():
			pending.append(child)
	return _actor_node_map


func actor_node(actor_id: int) -> Node3D:
	if world_container == null:
		return null
	if actor_id > 0:
		var cached := _actor_node_map_for_frame().get(actor_id, null) as Node3D
		if cached != null and is_instance_valid(cached) and not cached.is_queued_for_deletion():
			return cached
	# Fallback: 保留原始全树遍历语义（处理 actor_id<=0、缓存未命中或本帧新增节点）。
	var pending: Array[Node] = [world_container]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var node_3d := node as Node3D
		if node_3d != null and int(node_3d.get_meta("actor_id", 0)) == actor_id:
			if actor_id > 0:
				_actor_node_map[actor_id] = node_3d
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
	var presentation_token := int(options.get("presentation_token", 0))
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
	node.set_meta("action_runner_presentation_token", presentation_token)
	node.set_meta("action_presenter_final_position", _grid_to_world(to_grid, y))
	active_actor_id = actor_id
	_active_token = presentation_token
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
		"node_path": _node_path(node),
		"node_instance_id": node.get_instance_id(),
		"presentation_token": presentation_token,
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
	var presentation_token := int(options.get("presentation_token", 0))
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
	node.set_meta("action_runner_presentation_token", presentation_token)
	node.set_meta("action_presenter_final_position", original_position)
	active_actor_id = actor_id
	_active_token = presentation_token
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
		"node_path": _node_path(node),
		"node_instance_id": node.get_instance_id(),
		"presentation_token": presentation_token,
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


func move_actor_background_step(host: Node, actor_id: int, from_grid: Dictionary, to_grid: Dictionary, options: Dictionary = {}) -> Dictionary:
	var node := actor_node(actor_id)
	var presentation_token := int(options.get("presentation_token", 0))
	if node == null:
		return {
			"success": false,
			"active": false,
			"kind": "background_move_step",
			"reason": "actor_node_missing",
			"actor_id": actor_id,
		}
	_finish_background_actor_presentation(actor_id, "new_background_step", false)
	var duration := float(options.get("duration_sec", STEP_DURATION_SEC))
	var y := node.position.y
	var final_position := _grid_to_world(to_grid, y)
	node.position = _grid_to_world(from_grid, y)
	node.rotation_degrees = Vector3(node.rotation_degrees.x, _yaw_degrees(from_grid, to_grid, node.rotation_degrees.y), node.rotation_degrees.z)
	node.set_meta("background_action_active", true)
	node.set_meta("background_action_kind", "move_step")
	node.set_meta("background_action_actor_id", actor_id)
	node.set_meta("background_action_from_grid", from_grid.duplicate(true))
	node.set_meta("background_action_to_grid", to_grid.duplicate(true))
	node.set_meta("background_action_presentation_token", presentation_token)
	node.set_meta("background_action_final_position", final_position)
	var tween: Tween = host.create_tween() if host != null else null
	var output := {
		"success": true,
		"active": tween != null,
		"kind": "background_move_step",
		"actor_id": actor_id,
		"from_grid": from_grid.duplicate(true),
		"to_grid": to_grid.duplicate(true),
		"duration_sec": duration,
		"node_path": _node_path(node),
		"node_instance_id": node.get_instance_id(),
		"presentation_token": presentation_token,
	}
	if tween == null:
		node.position = final_position
		node.set_meta("background_action_active", false)
		if presentation_token > 0:
			_background_completed[actor_id] = _completion_record(presentation_token, actor_id, "background_move_step", "no_tween")
		output["active"] = false
		output["reason"] = "no_tween"
		return output
	background_tweens[actor_id] = tween
	_background_tokens[actor_id] = presentation_token
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "position", final_position, duration)
	tween.finished.connect(Callable(self, "_on_background_tween_finished").bind(actor_id))
	return output


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
	_prune_background_completions()
	var output := latest.duplicate(true)
	output["active"] = is_active()
	output["action_active"] = active_actor_node(active_actor_id) != null
	output["active_actor_id"] = active_actor_id
	var node := active_actor_node(active_actor_id)
	output["node_instance_id"] = node.get_instance_id() if node != null else 0
	output["node_position"] = _node_global_position(node) if node != null else Vector3.ZERO
	output["actor_nodes"] = _actor_nodes_snapshot()
	output["actor_node_count"] = _dictionary_or_empty(output.get("actor_nodes", {})).size()
	output["foreground_completed"] = _foreground_completed.duplicate(true)
	output["background_completed"] = _background_completed.duplicate(true)
	return output


func _prune_background_completions() -> void:
	for actor_id in _background_completed.keys():
		if actor_node(int(actor_id)) == null:
			_background_completed.erase(actor_id)


func clear_presentation_completion(token: int, actor_id: int = 0, channel: String = "foreground_actor") -> void:
	if channel == "foreground_actor":
		if int(_foreground_completed.get("token", 0)) == token and (actor_id <= 0 or int(_foreground_completed.get("actor_id", 0)) == actor_id):
			_foreground_completed.clear()
		return
	if channel == "background_actor" and actor_id > 0:
		var completed: Dictionary = _dictionary_or_empty(_background_completed.get(actor_id, {}))
		if int(completed.get("token", 0)) == token:
			_background_completed.erase(actor_id)


func _on_step_tween_finished(actor_id: int) -> void:
	_finish_active_actor_presentation(actor_id, "finished", false)


func _on_background_tween_finished(actor_id: int) -> void:
	_finish_background_actor_presentation(actor_id, "finished", false)


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
	if _active_token > 0 and reason != "new_step":
		_foreground_completed = _completion_record(_active_token, actor_id if actor_id > 0 else active_actor_id, str(latest.get("kind", "move_step")), reason)
	var result := latest.duplicate(true)
	result["active"] = false
	result["action_active"] = active_actor_node(active_actor_id) != null
	result["finish_reason"] = reason
	result["presentation_token"] = _active_token
	latest = result.duplicate(true)
	if reason != "new_step":
		_active_token = 0
	return result


func _finish_background_actor_presentation(actor_id: int, reason: String = "finished", clear_action_state: bool = true) -> Dictionary:
	var tween: Tween = background_tweens.get(actor_id, null)
	if tween != null and tween.is_valid() and tween.is_running():
		tween.kill()
	background_tweens.erase(actor_id)
	var token := int(_background_tokens.get(actor_id, 0))
	_background_tokens.erase(actor_id)
	var node := actor_node(actor_id)
	if node != null:
		if node.has_meta("background_action_final_position"):
			var final_position: Variant = node.get_meta("background_action_final_position")
			if typeof(final_position) == TYPE_VECTOR3:
				node.position = final_position
		if clear_action_state or reason == "finished":
			node.set_meta("background_action_active", false)
			node.set_meta("background_action_clear_reason", reason)
	if token > 0 and reason != "new_background_step":
		_background_completed[actor_id] = _completion_record(token, actor_id, "background_move_step", reason)
	return {
		"success": true,
		"active": false,
		"kind": "background_move_step",
		"actor_id": actor_id,
		"finish_reason": reason,
		"presentation_token": token,
	}


func _completion_record(token: int, actor_id: int, kind: String, reason: String) -> Dictionary:
	return {
		"token": token,
		"actor_id": actor_id,
		"kind": kind,
		"finish_reason": reason,
		"finished_at_process_frame": Engine.get_process_frames(),
	}


func _active_node_ref() -> Node3D:
	if active_node_ref == null:
		return null
	var node := active_node_ref.get_ref() as Node3D
	if node == null or node.is_queued_for_deletion():
		return null
	return node


func _actor_nodes_snapshot() -> Dictionary:
	var output: Dictionary = {}
	# 复用按帧缓存的节点表，避免每次调用都全树遍历。
	for actor_id in _actor_node_map_for_frame():
		var node_3d := _actor_node_map[actor_id] as Node3D
		if node_3d == null or not is_instance_valid(node_3d) or node_3d.is_queued_for_deletion():
			continue
		output[str(actor_id)] = {
			"actor_id": actor_id,
			"node_path": _node_path(node_3d),
			"node_instance_id": node_3d.get_instance_id(),
			"node_position": _node_global_position(node_3d),
			"node_present": true,
			"action_runner_active": bool(node_3d.get_meta("action_runner_active", false)),
			"action_runner_step_active": bool(node_3d.get_meta("action_runner_step_active", false)),
			"action_runner_kind": str(node_3d.get_meta("action_runner_kind", "")),
			"background_action_active": bool(node_3d.get_meta("background_action_active", false)),
			"background_action_kind": str(node_3d.get_meta("background_action_kind", "")),
		}
	return output


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


func _node_path(node: Node) -> String:
	if node == null:
		return ""
	return str(node.get_path()) if node.is_inside_tree() else node.name


func _node_global_position(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	return node.global_position if node.is_inside_tree() else node.position


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
