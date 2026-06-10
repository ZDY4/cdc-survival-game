extends RefCounted

var sequence: int = 0
var active_count: int = 0
var active_refs: Array[WeakRef] = []
var active_tweens: Array = []
var latest: Dictionary = {}


func next_sequence() -> int:
	sequence += 1
	return sequence


func current_sequence() -> int:
	return sequence


func latest_snapshot() -> Dictionary:
	return latest.duplicate(true)


func snapshot() -> Dictionary:
	prune_active_refs()
	var output := latest.duplicate(true)
	output["active"] = active_count > 0
	output["active_count"] = active_count
	output["sequence"] = sequence
	return output


func finish_active_presentations() -> Dictionary:
	for tween_value in active_tweens:
		var tween := tween_value as Tween
		if tween != null and tween.is_valid():
			tween.kill()
	active_tweens.clear()
	for node_ref in active_refs:
		var node := node_ref.get_ref() as Node
		if node == null or node.is_queued_for_deletion():
			continue
		if node is Node3D and node.has_meta("action_presenter_final_position"):
			var final_position: Variant = node.get_meta("action_presenter_final_position")
			if typeof(final_position) == TYPE_VECTOR3:
				(node as Node3D).position = final_position
		if node is Node3D and node.has_meta("action_presenter_final_rotation_degrees"):
			var final_rotation: Variant = node.get_meta("action_presenter_final_rotation_degrees")
			if typeof(final_rotation) == TYPE_VECTOR3:
				(node as Node3D).rotation_degrees = final_rotation
		node.set_meta("action_presenter_active", false)
		if str(node.name).begins_with("WorldAction"):
			node.queue_free()
	active_refs.clear()
	active_count = 0
	latest["active"] = false
	latest["active_count"] = 0
	latest["fast_forwarded"] = true
	return snapshot()


func track_active_node(node: Node) -> void:
	if node == null:
		return
	prune_active_refs()
	active_refs.append(weakref(node))
	active_count = active_refs.size()


func track_active_tween(tween: Tween) -> void:
	if tween == null:
		return
	prune_active_tweens()
	active_tweens.append(tween)


func prune_active_refs() -> void:
	var retained: Array[WeakRef] = []
	for node_ref in active_refs:
		var node := node_ref.get_ref() as Node
		if node == null:
			continue
		if node.is_queued_for_deletion():
			continue
		if not bool(node.get_meta("action_presenter_active", false)):
			continue
		retained.append(node_ref)
	active_refs = retained
	active_count = active_refs.size()
	prune_active_tweens()


func prune_active_tweens() -> void:
	var retained: Array = []
	for tween_value in active_tweens:
		var tween := tween_value as Tween
		if tween != null and tween.is_valid() and tween.is_running():
			retained.append(tween)
	active_tweens = retained


func record_latest(snapshot_data: Dictionary) -> Dictionary:
	prune_active_refs()
	latest = snapshot_data.duplicate(true)
	latest["active_count"] = active_count
	latest["sequence"] = sequence
	return latest.duplicate(true)


func set_latest_value(key: String, value: Variant) -> void:
	latest[key] = value


func latest_value(key: String, fallback: Variant = null) -> Variant:
	return latest.get(key, fallback)


func refresh_latest_active() -> void:
	prune_active_refs()
	latest["active"] = active_count > 0
	latest["active_count"] = active_count
