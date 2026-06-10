extends RefCounted

var _last_hover_state: Dictionary = _default_hover_state()


func replace_hover_state(next_state: Dictionary) -> bool:
	if _last_hover_state == next_state:
		return false
	_last_hover_state = next_state
	return true


func current_state() -> Dictionary:
	return _last_hover_state.duplicate(true)


func hover_state_snapshot(ui_blocker: String) -> Dictionary:
	var snapshot: Dictionary = _last_hover_state.duplicate(true)
	snapshot["ui_blocker"] = ui_blocker
	return snapshot


func can_reuse_ground_hover(grid: Dictionary, skill_targeting_active: bool) -> bool:
	if skill_targeting_active:
		return false
	if str(_last_hover_state.get("kind", "")) != "ground":
		return false
	var previous_grid: Dictionary = _dictionary_or_empty(_last_hover_state.get("grid", {}))
	return int(previous_grid.get("x", -999999)) == int(grid.get("x", 999999)) \
		and int(previous_grid.get("y", -999999)) == int(grid.get("y", 999999)) \
		and int(previous_grid.get("z", -999999)) == int(grid.get("z", 999999))


func selection_debug_snapshot(hover: Dictionary) -> Dictionary:
	var prompt: Dictionary = _dictionary_or_empty(hover.get("prompt", {}))
	var move_preview: Dictionary = _dictionary_or_empty(hover.get("move_preview", {}))
	var attack_preview: Dictionary = _dictionary_or_empty(hover.get("attack_preview", {}))
	var target_id := str(hover.get("target_id", ""))
	var actor_id := int(hover.get("actor_id", 0))
	return {
		"active": bool(hover.get("active", false)),
		"kind": str(hover.get("kind", "")),
		"hovered_grid": _dictionary_or_empty(hover.get("grid", {})).duplicate(true),
		"hovered_actor_id": actor_id,
		"hovered_object_id": target_id if actor_id <= 0 else "",
		"target_type": str(hover.get("target_type", "")),
		"target_category": str(hover.get("target_category", "")),
		"target_id": target_id,
		"target_name": str(hover.get("target_name", "")),
		"blocker_name": str(hover.get("ui_blocker", "")),
		"reason": str(hover.get("reason", "")),
		"prompt": _selection_debug_prompt(prompt),
		"move_preview": _selection_debug_move_preview(move_preview),
		"attack_preview": _selection_debug_attack_preview(attack_preview),
		"picking": _dictionary_or_empty(hover.get("picking", {})).duplicate(true),
	}


func hover_prompt_for_target(target: Dictionary, simulation: Variant, player_id: int) -> Dictionary:
	if simulation == null or not simulation.has_method("query_interaction_options"):
		return {}
	if player_id <= 0:
		return {}
	var prompt: Dictionary = simulation.query_interaction_options(player_id, target)
	return {
		"ok": bool(prompt.get("ok", false)),
		"reason": str(prompt.get("reason", "")),
		"target_name": str(prompt.get("target_name", "")),
		"primary_option_id": str(prompt.get("primary_option_id", "")),
		"primary_option_kind": str(prompt.get("primary_option_kind", "")),
		"action_label": str(prompt.get("action_label", "")),
		"ap_cost": float(prompt.get("ap_cost", 0.0)),
		"target_distance": int(prompt.get("target_distance", -1)),
		"interaction_range": int(prompt.get("interaction_range", -1)),
		"requires_approach": bool(prompt.get("requires_approach", false)),
		"option_count": _array_or_empty(prompt.get("options", [])).size(),
		"disabled_option_count": _array_or_empty(prompt.get("disabled_options", [])).size(),
	}


func hover_target_category(target: Dictionary, prompt: Dictionary, runtime_snapshot: Dictionary) -> String:
	var target_type := str(target.get("target_type", ""))
	if target_type == "actor":
		var actor_id := int(target.get("actor_id", 0))
		for actor in _array_or_empty(runtime_snapshot.get("actors", [])):
			var actor_data: Dictionary = _dictionary_or_empty(actor)
			if int(actor_data.get("actor_id", 0)) == actor_id:
				var side := str(actor_data.get("side", ""))
				if not side.is_empty():
					return "actor:%s" % side
				return "actor"
		return "actor"
	if target_type == "map_object":
		var target_kind := str(target.get("target_kind", target.get("kind", "")))
		if target_kind == "door":
			return "door"
		var prompt_kind := str(prompt.get("primary_option_kind", ""))
		if prompt_kind == "door_toggle":
			return "door"
		if prompt_kind == "open_container":
			return "container"
		if prompt_kind in ["enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor"]:
			return "trigger"
		if not prompt_kind.is_empty():
			return prompt_kind
		return "map_object"
	return target_type if not target_type.is_empty() else "interaction"


func move_preview_for_grid(grid: Dictionary, simulation: Variant, player_id: int, world_result: Dictionary) -> Dictionary:
	if simulation == null or not simulation.has_method("preview_move"):
		return {}
	if player_id <= 0:
		return {}
	var preview: Dictionary = simulation.preview_move(player_id, grid, _dictionary_or_empty(world_result.get("map", {})))
	return {
		"reachable": bool(preview.get("reachable", preview.get("success", false))),
		"reason": str(preview.get("reason", "")),
		"steps": int(preview.get("steps", 0)),
		"path": _array_or_empty(preview.get("path", [])).duplicate(true),
		"ap_cost": float(preview.get("ap_cost", 0.0)),
		"ap_available": float(preview.get("ap_available", 0.0)),
		"ap_affordable": bool(preview.get("ap_affordable", true)),
		"affordable_steps": int(preview.get("affordable_steps", 0)),
		"requires_pending": bool(preview.get("requires_pending", false)),
		"pending_steps": int(preview.get("pending_steps", 0)),
		"target_position": _dictionary_or_empty(preview.get("target_position", grid)).duplicate(true),
		"blocker": _dictionary_or_empty(preview.get("blocker", {})).duplicate(true),
		"visited_cell_count": int(preview.get("visited_cell_count", 0)),
		"pathfinding_time_ms": float(preview.get("pathfinding_time_ms", 0.0)),
	}


func attack_preview_for_target(target: Dictionary, simulation: Variant, player_id: int, world_result: Dictionary) -> Dictionary:
	if str(target.get("target_type", "")) != "actor":
		return {}
	if simulation == null or not simulation.has_method("preview_attack"):
		return {}
	var target_actor_id := int(target.get("actor_id", 0))
	if player_id <= 0 or target_actor_id <= 0 or player_id == target_actor_id:
		return {}
	var preview: Dictionary = simulation.preview_attack(player_id, target_actor_id, _dictionary_or_empty(world_result.get("map", {})))
	return {
		"can_attack": bool(preview.get("can_attack", preview.get("success", false))),
		"success": bool(preview.get("success", false)),
		"reason": str(preview.get("reason", "")),
		"actor_id": int(preview.get("actor_id", player_id)),
		"target_actor_id": int(preview.get("target_actor_id", target_actor_id)),
		"target_grid": _dictionary_or_empty(preview.get("target_grid", {})).duplicate(true),
		"distance": int(preview.get("distance", -1)),
		"range": int(preview.get("range", -1)),
		"ap_cost": float(preview.get("ap_cost", 0.0)),
		"ap_available": float(preview.get("ap_available", 0.0)),
		"ap_affordable": bool(preview.get("ap_affordable", true)),
		"ammo_available": bool(preview.get("ammo_available", true)),
		"hit_chance": float(preview.get("hit_chance", -1.0)),
		"crit_chance": float(preview.get("crit_chance", 0.0)),
		"estimated_damage": float(preview.get("estimated_damage", 0.0)),
	}


func _default_hover_state() -> Dictionary:
	return {
		"active": false,
		"kind": "",
		"grid": {},
		"target_name": "",
		"target_type": "",
		"target_id": "",
		"actor_id": 0,
		"ui_blocker": "",
		"reason": "",
		"prompt": {},
		"move_preview": {},
		"attack_preview": {},
		"picking": {},
	}


func _selection_debug_prompt(prompt: Dictionary) -> Dictionary:
	if prompt.is_empty():
		return {
			"has_prompt": false,
			"ok": false,
			"primary_option_id": "",
			"action_label": "",
			"option_count": 0,
			"disabled_option_count": 0,
			"disabled_reason": "",
			"target_distance": -1,
			"interaction_range": -1,
			"requires_approach": false,
		}
	return {
		"has_prompt": true,
		"ok": bool(prompt.get("ok", false)),
		"primary_option_id": str(prompt.get("primary_option_id", "")),
		"action_label": str(prompt.get("action_label", "")),
		"option_count": _array_or_empty(prompt.get("options", [])).size(),
		"disabled_option_count": _array_or_empty(prompt.get("disabled_options", [])).size(),
		"disabled_reason": str(prompt.get("reason", "")),
		"target_distance": int(prompt.get("target_distance", -1)),
		"interaction_range": int(prompt.get("interaction_range", -1)),
		"requires_approach": bool(prompt.get("requires_approach", false)),
	}


func _selection_debug_move_preview(move_preview: Dictionary) -> Dictionary:
	if move_preview.is_empty():
		return {"has_preview": false}
	return {
		"has_preview": true,
		"reachable": bool(move_preview.get("reachable", false)),
		"reason": str(move_preview.get("reason", "")),
		"steps": int(move_preview.get("steps", 0)),
		"ap_cost": float(move_preview.get("ap_cost", 0.0)),
		"ap_available": float(move_preview.get("ap_available", 0.0)),
		"ap_affordable": bool(move_preview.get("ap_affordable", true)),
		"requires_pending": bool(move_preview.get("requires_pending", false)),
		"pathfinding_time_ms": float(move_preview.get("pathfinding_time_ms", 0.0)),
		"visited_cell_count": int(move_preview.get("visited_cell_count", 0)),
	}


func _selection_debug_attack_preview(attack_preview: Dictionary) -> Dictionary:
	if attack_preview.is_empty():
		return {"has_preview": false}
	return {
		"has_preview": true,
		"can_attack": bool(attack_preview.get("can_attack", false)),
		"reason": str(attack_preview.get("reason", "")),
		"target_actor_id": int(attack_preview.get("target_actor_id", 0)),
		"distance": int(attack_preview.get("distance", -1)),
		"range": int(attack_preview.get("range", -1)),
		"ap_cost": float(attack_preview.get("ap_cost", 0.0)),
		"ap_available": float(attack_preview.get("ap_available", 0.0)),
		"hit_chance": float(attack_preview.get("hit_chance", -1.0)),
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
