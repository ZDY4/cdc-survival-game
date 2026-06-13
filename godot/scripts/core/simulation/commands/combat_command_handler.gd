extends RefCounted


func submit_attack(simulation: RefCounted, actor: RefCounted, command: Dictionary) -> Dictionary:
	var pipeline: Array[Dictionary] = []
	var corpse_target: Dictionary = _corpse_attack_target(simulation, command)
	if not corpse_target.is_empty():
		_append_pipeline_step(pipeline, "validate", corpse_target)
		corpse_target["attack_pipeline"] = pipeline.duplicate(true)
		return corpse_target
	var target_actor_id: int = int(command.get("target_actor_id", 0))
	var target: RefCounted = simulation.actor_registry.get_actor(target_actor_id)
	if target == null:
		var missing_target := {"success": false, "reason": "unknown_target"}
		_append_pipeline_step(pipeline, "validate", missing_target)
		missing_target["attack_pipeline"] = pipeline.duplicate(true)
		return missing_target
	var attack_options: Dictionary = simulation._attack_command_options(command, {})
	var target_check: Dictionary = simulation.validate_attack_target(actor.actor_id, target_actor_id, attack_options)
	_append_pipeline_step(pipeline, "validate", target_check)
	if not bool(target_check.get("success", false)):
		target_check["attack_pipeline"] = pipeline.duplicate(true)
		return target_check
	var profile: Dictionary = simulation._attack_profile(actor, _dictionary_or_empty(command.get("item_library", simulation.item_library)))
	var attack_range: int = int(command.get("range", int(profile.get("range", simulation.DEFAULT_ATTACK_RANGE))))
	var min_range: int = simulation._attack_min_range_from_options(command, profile)
	attack_options = simulation._attack_command_options(command, profile)
	var attack_distance: int = simulation._grid_distance(actor.grid_position, target.grid_position)
	if attack_distance > attack_range:
		_append_pipeline_step(pipeline, "approach", {
			"success": true,
			"reason": "target_out_of_range",
			"distance": attack_distance,
			"range": attack_range,
		})
		var source_target: Dictionary = _dictionary_or_empty(command.get("source_target", {
			"target_type": "actor",
			"actor_id": target_actor_id,
		}))
		var source_option_id: String = str(command.get("source_option_id", "attack"))
		var prompt: Dictionary = simulation.query_interaction_options(actor.actor_id, source_target)
		var approach_result: Dictionary = simulation._approach_then_execute_interaction(actor, source_target, source_option_id, prompt, _dictionary_or_empty(command.get("topology", {})))
		approach_result["attack_pipeline"] = pipeline.duplicate(true)
		return approach_result
	if attack_distance < min_range:
		_append_pipeline_step(pipeline, "spatial", {
			"success": false,
			"reason": "target_inside_min_range",
			"distance": attack_distance,
			"min_range": min_range,
		})
		var min_range_result: Dictionary = simulation.perform_attack(actor.actor_id, target_actor_id, _dictionary_or_empty(command.get("topology", {})), _attack_perform_options(attack_range, min_range, profile, attack_options))
		min_range_result["attack_pipeline"] = pipeline.duplicate(true)
		return min_range_result
	var topology: Dictionary = _dictionary_or_empty(command.get("topology", {}))
	var preflight: Dictionary = simulation.preview_attack(actor.actor_id, target_actor_id, topology, _attack_perform_options(attack_range, min_range, profile, attack_options))
	_append_pipeline_step(pipeline, "preflight", preflight)
	if not bool(preflight.get("can_attack", false)) and str(preflight.get("reason", "")) != "ap_insufficient":
		preflight["attack_pipeline"] = pipeline.duplicate(true)
		return preflight
	var attack_cost: float = float(command.get("ap_cost", profile.get("ap_cost", simulation.DEFAULT_ATTACK_AP)))
	if actor.ap < attack_cost:
		simulation.pending_interaction = {
			"actor_id": actor.actor_id,
			"kind": "attack",
			"target_actor_id": target_actor_id,
			"required_ap": attack_cost,
			"available_ap": actor.ap,
		}
		simulation.emit_event("interaction_queued", simulation.pending_interaction.duplicate(true))
		var ap_result := {
			"success": false,
			"reason": "ap_insufficient_attack_queued",
			"pending_interaction": simulation.pending_interaction.duplicate(true),
		}
		_append_pipeline_step(pipeline, "consume", ap_result)
		ap_result["attack_pipeline"] = pipeline.duplicate(true)
		return ap_result
	var ammo_check: Dictionary = simulation._attack_ammo_check(actor, profile)
	_append_pipeline_step(pipeline, "ammo", ammo_check)
	if not bool(ammo_check.get("success", true)):
		ammo_check["attack_pipeline"] = pipeline.duplicate(true)
		return ammo_check
	var durability_check: Dictionary = simulation._attack_weapon_durability_check(actor, profile)
	_append_pipeline_step(pipeline, "durability", durability_check)
	if not bool(durability_check.get("success", true)):
		durability_check["attack_pipeline"] = pipeline.duplicate(true)
		return durability_check
	simulation._spend_ap(actor, attack_cost, "attack")
	_append_pipeline_step(pipeline, "consume", {
		"success": true,
		"ap_cost": attack_cost,
		"ap_remaining": actor.ap,
	})
	simulation._enter_combat([actor.actor_id, target_actor_id], "player_attack")
	var result: Dictionary = simulation.perform_attack(actor.actor_id, target_actor_id, topology, _attack_perform_options(attack_range, min_range, profile, attack_options))
	_append_pipeline_step(pipeline, "apply_result", result)
	if bool(result.get("success", false)):
		var ammo_result: Dictionary = simulation._consume_attack_ammo(actor, profile)
		if bool(ammo_result.get("consumed", false)):
			result["ammo_consumed"] = ammo_result
		var durability_result: Dictionary = simulation._consume_attack_weapon_durability(actor, profile)
		if bool(durability_result.get("consumed", false)):
			result["weapon_durability_consumed"] = durability_result
		simulation.pending_interaction.clear()
	result["attack_pipeline"] = pipeline.duplicate(true)
	return result


func _attack_perform_options(attack_range: int, min_range: int, profile: Dictionary, attack_options: Dictionary) -> Dictionary:
	return {
		"range": attack_range,
		"min_range": min_range,
		"weapon_profile": profile,
		"allow_non_hostile_attack": bool(attack_options.get("allow_non_hostile_attack", false)),
		"confirmation_required": bool(attack_options.get("confirmation_required", false)),
		"friendly_fire_relationship_delta": float(attack_options.get("friendly_fire_relationship_delta", -75.0)),
	}


func _corpse_attack_target(simulation: RefCounted, command: Dictionary) -> Dictionary:
	var target: Dictionary = _dictionary_or_empty(command.get("target", {}))
	var target_type := str(command.get("target_type", target.get("target_type", ""))).strip_edges()
	var corpse_id := str(command.get("container_id", command.get("corpse_id", command.get("target_id", target.get("container_id", target.get("target_id", "")))))).strip_edges()
	if target_type == "corpse" or target_type == "corpse_container":
		return _corpse_attack_rejection(simulation, corpse_id, target)
	if corpse_id.is_empty():
		return {}
	if simulation.corpse_containers.has(corpse_id):
		return _corpse_attack_rejection(simulation, corpse_id, _dictionary_or_empty(simulation.corpse_containers.get(corpse_id, target)))
	var target_data: Dictionary = _dictionary_or_empty(simulation.map_interaction_targets.get(corpse_id, {}))
	if str(target_data.get("container_type", target.get("container_type", ""))) == "corpse":
		return _corpse_attack_rejection(simulation, corpse_id, target_data)
	return {}


func _corpse_attack_rejection(simulation: RefCounted, corpse_id: String, target_data: Dictionary = {}) -> Dictionary:
	var corpse: Dictionary = _dictionary_or_empty(simulation.corpse_containers.get(corpse_id, target_data))
	return {
		"success": false,
		"reason": "target_is_corpse",
		"target_type": "corpse",
		"corpse_id": corpse_id,
		"container_id": str(corpse.get("container_id", corpse_id)),
		"display_name": str(corpse.get("display_name", target_data.get("display_name", corpse_id))),
		"source_actor_id": int(corpse.get("source_actor_id", target_data.get("source_actor_id", 0))),
		"grid_position": _dictionary_or_empty(corpse.get("grid_position", target_data.get("grid_position", target_data.get("anchor", {})))).duplicate(true),
	}


func _append_pipeline_step(pipeline: Array[Dictionary], step_id: String, result: Dictionary) -> void:
	var success_value: Variant = result.get("success", result.get("can_attack", false))
	pipeline.append({
		"id": step_id,
		"success": bool(success_value),
		"reason": str(result.get("reason", "")),
	})


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
