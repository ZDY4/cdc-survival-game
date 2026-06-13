extends RefCounted


static func create(actor_id: int, target_grid: Dictionary, topology: Dictionary, begin_result: Dictionary) -> Dictionary:
	return {
		"kind": "move",
		"actor_id": actor_id,
		"target_grid": target_grid.duplicate(true),
		"topology": topology.duplicate(true),
		"path": _array_or_empty(begin_result.get("path", [])).duplicate(true),
		"step_index": 0,
		"phase": "move_step",
		"ap_before": float(begin_result.get("ap", 0.0)),
		"completed_after_presentation": false,
		"turn_cycles": 0,
	}


static func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
