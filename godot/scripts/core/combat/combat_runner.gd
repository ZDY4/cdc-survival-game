extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const EquipmentEffects = preload("res://scripts/core/economy/equipment_effects.gd")
const VisionGeometry = preload("res://scripts/core/vision/vision_geometry.gd")

var _inventory_entries := InventoryEntries.new()
var _equipment_effects := EquipmentEffects.new()
var _vision_geometry := VisionGeometry.new()


func perform_attack(simulation: RefCounted, actor_id: int, target_actor_id: int, topology: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var attacker: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var target: RefCounted = simulation.actor_registry.get_actor(target_actor_id)
	var target_check: Dictionary = validate_attack_target(simulation, actor_id, target_actor_id, options)
	if not bool(target_check.get("success", false)):
		return target_check
	var profile: Dictionary = _dictionary_or_empty(options.get("weapon_profile", {}))
	var spatial_check: Dictionary = _spatial_check(attacker, target, topology, int(options.get("range", int(profile.get("range", 1)))), _minimum_attack_range(options, profile))
	if not bool(spatial_check.get("success", false)):
		return spatial_check
	var relationship_consequence: Dictionary = _apply_non_hostile_attack_consequence(simulation, attacker, target, target_check, options)

	var hit_roll: Dictionary = _hit_check(simulation, attacker, target, profile)
	var critical_roll: Dictionary = {
		"critical": false,
		"chance": _critical_chance(simulation, attacker, profile),
		"roll": 1.0,
		"counter": int(hit_roll.get("counter", int(simulation.combat_state.get("combat_rng_counter", 0)))),
		"salt": 0,
	}
	if bool(hit_roll.get("hit", true)):
		critical_roll = _critical_hit(simulation, attacker, target, profile)
	var critical: bool = bool(critical_roll.get("critical", false))
	var damage_result: Dictionary = _resolve_damage(simulation, attacker, target, profile, critical) if bool(hit_roll.get("hit", true)) else _miss_damage_result(simulation, target, hit_roll)
	var damage: float = float(damage_result.get("damage", 0.0))
	var triggered_on_hit_effect_ids: Array[String] = _triggered_on_hit_effect_ids(profile, damage_result)
	target.hp = max(0.0, target.hp - damage)
	var applied_on_hit_effects: Array[Dictionary] = _apply_on_hit_effects(simulation, attacker, target, profile, triggered_on_hit_effect_ids)
	simulation.emit_event("attack_performed", {
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"damage": damage,
		"target_hp": target.hp,
		"weapon_item_id": profile.get("item_id", ""),
		"critical": critical,
		"crit_roll": float(critical_roll.get("roll", 1.0)),
		"crit_chance": float(critical_roll.get("chance", 0.0)),
		"combat_rng_counter": int(critical_roll.get("counter", int(simulation.combat_state.get("combat_rng_counter", 0)))),
		"hit_kind": str(damage_result.get("hit_kind", "hit")),
		"hit_roll": float(hit_roll.get("roll", 0.0)),
		"hit_chance": float(hit_roll.get("chance", 1.0)),
		"accuracy": float(hit_roll.get("accuracy", 0.0)),
		"evasion": float(hit_roll.get("evasion", 0.0)),
		"triggered_on_hit_effect_ids": triggered_on_hit_effect_ids,
		"applied_on_hit_effects": applied_on_hit_effects.duplicate(true),
		"friendly_fire": bool(target_check.get("friendly_fire", false)),
		"relationship_consequence": relationship_consequence.duplicate(true),
	})
	simulation.emit_event("attack_resolved", {
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"damage": damage,
		"target_hp": target.hp,
		"defeated": target.hp <= 0.0,
		"critical": critical,
		"range": int(options.get("range", 1)),
		"weapon_item_id": profile.get("item_id", ""),
		"base_damage": float(profile.get("damage", attacker.attack_power)),
		"crit_multiplier": float(profile.get("crit_multiplier", 1.0)),
		"crit_roll": float(critical_roll.get("roll", 1.0)),
		"crit_chance": float(critical_roll.get("chance", 0.0)),
		"defense": float(damage_result.get("defense", 0.0)),
		"damage_reduction": float(damage_result.get("damage_reduction", 0.0)),
		"damage_bonus": float(damage_result.get("damage_bonus", 0.0)),
		"hit_kind": str(damage_result.get("hit_kind", "hit")),
		"hit_roll": float(hit_roll.get("roll", 0.0)),
		"hit_chance": float(hit_roll.get("chance", 1.0)),
		"accuracy": float(hit_roll.get("accuracy", 0.0)),
		"evasion": float(hit_roll.get("evasion", 0.0)),
		"triggered_on_hit_effect_ids": triggered_on_hit_effect_ids,
		"applied_on_hit_effects": applied_on_hit_effects.duplicate(true),
		"combat_rng_seed": int(simulation.combat_state.get("combat_rng_seed", 0)),
		"combat_rng_counter": int(critical_roll.get("counter", int(simulation.combat_state.get("combat_rng_counter", 0)))),
		"combat_rng_salt": int(critical_roll.get("salt", 0)),
		"friendly_fire": bool(target_check.get("friendly_fire", false)),
		"relationship_consequence": relationship_consequence.duplicate(true),
	})

	var defeated: bool = target.hp <= 0.0
	if defeated:
		_defeat_actor(simulation, actor_id, target_actor_id, target)
		if target.side == "player" and simulation.has_method("exit_combat_if_player_defeated"):
			simulation.call("exit_combat_if_player_defeated", "player_defeated")

	return {
		"success": true,
		"actor_id": actor_id,
		"damage": damage,
		"defeated": defeated,
		"target_actor_id": target_actor_id,
		"attacker_grid": attacker.grid_position.to_dictionary(),
		"target_grid": target.grid_position.to_dictionary(),
		"distance": int(spatial_check.get("distance", 0)),
		"range": int(spatial_check.get("range", int(options.get("range", 1)))),
		"min_range": int(spatial_check.get("min_range", 0)),
		"same_level": bool(spatial_check.get("same_level", true)),
		"range_ok": bool(spatial_check.get("range_ok", true)),
		"min_range_ok": bool(spatial_check.get("min_range_ok", true)),
		"line_of_sight": bool(spatial_check.get("line_of_sight", true)),
		"line_of_sight_required": bool(spatial_check.get("line_of_sight_required", false)),
		"spatial_failure": str(spatial_check.get("spatial_failure", "")),
		"critical": critical,
		"crit_roll": float(critical_roll.get("roll", 1.0)),
		"crit_chance": float(critical_roll.get("chance", 0.0)),
		"hit_kind": str(damage_result.get("hit_kind", "hit")),
		"hit_roll": float(hit_roll.get("roll", 0.0)),
		"hit_chance": float(hit_roll.get("chance", 1.0)),
		"accuracy": float(hit_roll.get("accuracy", 0.0)),
		"evasion": float(hit_roll.get("evasion", 0.0)),
		"damage_bonus": float(damage_result.get("damage_bonus", 0.0)),
		"triggered_on_hit_effect_ids": triggered_on_hit_effect_ids,
		"applied_on_hit_effects": applied_on_hit_effects.duplicate(true),
		"weapon_profile": profile,
		"friendly_fire": bool(target_check.get("friendly_fire", false)),
		"relationship_consequence": relationship_consequence.duplicate(true),
	}


func preview_attack(simulation: RefCounted, actor_id: int, target_actor_id: int, topology: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var attacker: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var target: RefCounted = simulation.actor_registry.get_actor(target_actor_id)
	var profile: Dictionary = _dictionary_or_empty(options.get("weapon_profile", {}))
	var attack_range: int = int(options.get("range", int(profile.get("range", 1))))
	var min_range: int = _minimum_attack_range(options, profile)
	var preview: Dictionary = {
		"success": false,
		"can_attack": false,
		"preview_kind": "attack",
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"range": max(1, attack_range),
		"min_range": min_range,
		"weapon_profile": profile.duplicate(true),
	}
	var target_check: Dictionary = validate_attack_target(simulation, actor_id, target_actor_id, options)
	if not bool(target_check.get("success", false)):
		preview.merge(target_check, true)
		_add_attack_preview_actor_fields(preview, attacker, target)
		return preview
	preview.merge(_friendly_fire_preview_fields(target_check, options), true)
	var spatial_check: Dictionary = _spatial_check(attacker, target, topology, attack_range, min_range)
	if not bool(spatial_check.get("success", false)):
		preview.merge(spatial_check, true)
		_add_attack_preview_actor_fields(preview, attacker, target)
		return preview
	preview.merge(spatial_check, true)

	var hit_preview: Dictionary = _hit_preview(simulation, attacker, target, profile)
	var damage_preview: Dictionary = _damage_preview(simulation, attacker, target, profile)
	preview["success"] = true
	preview["can_attack"] = true
	preview["reason"] = "ok"
	preview["attacker_grid"] = attacker.grid_position.to_dictionary()
	preview["target_grid"] = target.grid_position.to_dictionary()
	preview["distance"] = abs(attacker.grid_position.x - target.grid_position.x) + abs(attacker.grid_position.z - target.grid_position.z)
	preview["hit_chance"] = float(hit_preview.get("hit_chance", 1.0))
	preview["accuracy"] = float(hit_preview.get("accuracy", 0.0))
	preview["evasion"] = float(hit_preview.get("evasion", 0.0))
	preview["crit_chance"] = _critical_chance(simulation, attacker, profile)
	preview["estimated_damage"] = float(damage_preview.get("estimated_damage", 0.0))
	preview["minimum_damage"] = float(damage_preview.get("minimum_damage", 0.0))
	preview["maximum_damage"] = float(damage_preview.get("maximum_damage", 0.0))
	preview["hit_kind"] = str(damage_preview.get("hit_kind", "hit"))
	preview["target_hp"] = target.hp
	preview["target_defeated_if_max_damage"] = target.hp <= float(damage_preview.get("maximum_damage", 0.0))
	return preview


func defeat_actor(simulation: RefCounted, actor_id: int, target_actor_id: int, target: RefCounted) -> void:
	_defeat_actor(simulation, actor_id, target_actor_id, target)


func validate_attack_target(simulation: RefCounted, actor_id: int, target_actor_id: int, options: Dictionary = {}) -> Dictionary:
	var attacker: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var target: RefCounted = simulation.actor_registry.get_actor(target_actor_id)
	if attacker == null:
		return {"success": false, "reason": "unknown_attacker", "actor_id": actor_id}
	if target == null:
		return {"success": false, "reason": "unknown_target", "target_actor_id": target_actor_id}
	if attacker.actor_id == target.actor_id:
		return {"success": false, "reason": "target_self", "actor_id": actor_id}
	if attacker.hp <= 0.0:
		return {"success": false, "reason": "attacker_defeated", "actor_id": actor_id}
	if target.hp <= 0.0:
		return {"success": false, "reason": "target_defeated", "target_actor_id": target_actor_id}
	var hostility: Dictionary = _actor_hostility(simulation, attacker, target)
	if not bool(hostility.get("hostile", _can_attack(attacker, target))):
		var friendly_fire: bool = attacker.actor_id != target.actor_id
		if _allows_non_hostile_attack(options):
			var allowed_non_hostile := {
				"success": true,
				"friendly_fire": friendly_fire,
				"non_hostile_attack": true,
				"confirmation_required": bool(options.get("confirmation_required", false)),
				"actor_id": actor_id,
				"attacker_side": attacker.side,
				"target_side": target.side,
				"relationship_score": float(hostility.get("score", 0.0)),
				"hostility_reason": str(hostility.get("reason", "")),
				"target_actor_id": target_actor_id,
				"relationship_consequence_preview": _non_hostile_attack_consequence_preview(float(hostility.get("score", 0.0)), options),
			}
			var visibility_check: Dictionary = _visibility_check(simulation, attacker, target)
			if not bool(visibility_check.get("success", true)):
				return visibility_check
			return allowed_non_hostile
		return {
			"success": false,
			"reason": "target_not_hostile",
			"friendly_fire": friendly_fire,
			"non_hostile_attack": true,
			"confirmation_required": true,
			"actor_id": actor_id,
			"attacker_side": attacker.side,
			"target_side": target.side,
			"relationship_score": float(hostility.get("score", 0.0)),
			"hostility_reason": str(hostility.get("reason", "")),
			"target_actor_id": target_actor_id,
		}
	var visibility_check: Dictionary = _visibility_check(simulation, attacker, target)
	if not bool(visibility_check.get("success", true)):
		return visibility_check
	return {"success": true}


func _visibility_check(simulation: RefCounted, attacker: RefCounted, target: RefCounted) -> Dictionary:
	if simulation != null and simulation.has_method("is_actor_visible_to_actor") and not bool(simulation.call("is_actor_visible_to_actor", attacker.actor_id, target.actor_id)):
		return {
			"success": false,
			"reason": "target_not_visible",
			"actor_id": attacker.actor_id,
			"target_actor_id": target.actor_id,
			"attacker_grid": attacker.grid_position.to_dictionary(),
			"target_grid": target.grid_position.to_dictionary(),
		}
	return {"success": true}


func _allows_non_hostile_attack(options: Dictionary) -> bool:
	return bool(options.get("allow_non_hostile_attack", false)) \
		or bool(options.get("allow_friendly_fire", false)) \
		or bool(options.get("allow_friendly_attack", false))


func _friendly_fire_preview_fields(target_check: Dictionary, options: Dictionary) -> Dictionary:
	if not bool(target_check.get("friendly_fire", false)):
		return {}
	return {
		"friendly_fire": true,
		"non_hostile_attack": true,
		"confirmation_required": bool(options.get("confirmation_required", false)),
		"relationship_score": float(target_check.get("relationship_score", 0.0)),
		"hostility_reason": str(target_check.get("hostility_reason", "")),
		"relationship_consequence_preview": _dictionary_or_empty(target_check.get("relationship_consequence_preview", {})).duplicate(true),
	}


func _apply_non_hostile_attack_consequence(simulation: RefCounted, attacker: RefCounted, target: RefCounted, target_check: Dictionary, options: Dictionary) -> Dictionary:
	if not bool(target_check.get("friendly_fire", false)):
		return {}
	if simulation == null or not simulation.has_method("set_relationship_score"):
		return {}
	var before: float = float(target_check.get("relationship_score", 0.0))
	if simulation.has_method("relationship_score"):
		before = float(simulation.call("relationship_score", attacker.actor_id, target.actor_id))
	var next_score: float = _non_hostile_attack_next_relationship_score(before, options)
	var result: Dictionary = _dictionary_or_empty(simulation.call("set_relationship_score", attacker.actor_id, target.actor_id, next_score, "friendly_fire_attack"))
	result["friendly_fire"] = true
	result["relationship_before"] = before
	result["relationship_after"] = next_score
	result["hostility_threshold"] = _hostility_threshold(simulation)
	return result


func _non_hostile_attack_consequence_preview(current_score: float, options: Dictionary) -> Dictionary:
	var next_score: float = _non_hostile_attack_next_relationship_score(current_score, options)
	return {
		"score_before": current_score,
		"score_after": next_score,
		"score_delta": next_score - current_score,
		"reason": "friendly_fire_attack",
	}


func _non_hostile_attack_next_relationship_score(current_score: float, options: Dictionary) -> float:
	if options.has("friendly_fire_relationship_score"):
		return clampf(float(options.get("friendly_fire_relationship_score", -75.0)), -100.0, 100.0)
	if options.has("non_hostile_attack_relationship_score"):
		return clampf(float(options.get("non_hostile_attack_relationship_score", -75.0)), -100.0, 100.0)
	var delta: float = float(options.get("friendly_fire_relationship_delta", options.get("non_hostile_attack_relationship_delta", -75.0)))
	return clampf(min(current_score + delta, -75.0), -100.0, 100.0)


func _hostility_threshold(simulation: RefCounted) -> float:
	return -50.0


func _can_attack(attacker: RefCounted, target: RefCounted) -> bool:
	if attacker.actor_id == target.actor_id:
		return false
	if attacker.side == "hostile":
		return target.side != "hostile"
	if target.side == "hostile":
		return attacker.side != "hostile"
	return false


func _actor_hostility(simulation: RefCounted, attacker: RefCounted, target: RefCounted) -> Dictionary:
	if simulation != null and simulation.has_method("actor_hostility"):
		return _dictionary_or_empty(simulation.call("actor_hostility", attacker.actor_id, target.actor_id))
	return {"hostile": _can_attack(attacker, target), "reason": "legacy_side", "score": 0.0}


func _spatial_check(attacker: RefCounted, target: RefCounted, topology: Dictionary, attack_range: int, min_range: int = 0) -> Dictionary:
	var diagnostics: Dictionary = _attack_spatial_diagnostics(attacker, target, topology, attack_range, min_range)
	var failure: String = str(diagnostics.get("spatial_failure", ""))
	if not failure.is_empty():
		diagnostics["success"] = false
		diagnostics["reason"] = failure
		return diagnostics
	diagnostics["success"] = true
	diagnostics["reason"] = "ok"
	return diagnostics


func _attack_spatial_diagnostics(attacker: RefCounted, target: RefCounted, topology: Dictionary, attack_range: int, min_range: int = 0) -> Dictionary:
	var attacker_grid: Dictionary = attacker.grid_position.to_dictionary()
	var target_grid: Dictionary = target.grid_position.to_dictionary()
	var distance: int = abs(attacker.grid_position.x - target.grid_position.x) + abs(attacker.grid_position.z - target.grid_position.z)
	var resolved_range: int = max(1, attack_range)
	var resolved_min_range: int = clampi(min_range, 0, resolved_range)
	var same_level: bool = attacker.grid_position.y == target.grid_position.y
	var range_ok: bool = distance <= resolved_range
	var min_range_ok: bool = distance >= resolved_min_range
	var los_required: bool = not topology.is_empty()
	var los_ok: bool = same_level
	if same_level and los_required:
		los_ok = _vision_geometry.has_line_of_sight(attacker_grid, target_grid, topology)
	var failure: String = ""
	if not same_level:
		failure = "target_invalid_level"
	elif not range_ok:
		failure = "target_out_of_range"
	elif not min_range_ok:
		failure = "target_too_close"
	elif los_required and not los_ok:
		failure = "target_blocked_by_los"
	return {
		"actor_id": attacker.actor_id,
		"target_actor_id": target.actor_id,
		"attacker_grid": attacker_grid,
		"target_grid": target_grid,
		"distance": distance,
		"range": resolved_range,
		"min_range": resolved_min_range,
		"same_level": same_level,
		"range_ok": range_ok,
		"min_range_ok": min_range_ok,
		"line_of_sight": los_ok,
		"line_of_sight_required": los_required,
		"spatial_failure": failure,
	}


func _minimum_attack_range(options: Dictionary, profile: Dictionary) -> int:
	if options.has("min_range"):
		return max(0, int(options.get("min_range", 0)))
	if options.has("minimum_range"):
		return max(0, int(options.get("minimum_range", 0)))
	if options.has("minRange"):
		return max(0, int(options.get("minRange", 0)))
	if profile.has("min_range"):
		return max(0, int(profile.get("min_range", 0)))
	if profile.has("minimum_range"):
		return max(0, int(profile.get("minimum_range", 0)))
	if profile.has("minRange"):
		return max(0, int(profile.get("minRange", 0)))
	return 0


func _triggered_on_hit_effect_ids(profile: Dictionary, damage_result: Dictionary) -> Array[String]:
	var hit_kind: String = str(damage_result.get("hit_kind", "hit"))
	if not ["hit", "crit"].has(hit_kind):
		return []
	return _string_array(profile.get("on_hit_effect_ids", []))


func _apply_on_hit_effects(simulation: RefCounted, attacker: RefCounted, target: RefCounted, profile: Dictionary, effect_ids: Array[String]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if target.hp <= 0.0 or effect_ids.is_empty():
		return output
	var effect_library: Dictionary = _dictionary_or_empty(simulation.effect_library if simulation != null else {})
	if effect_library.is_empty():
		return output
	for effect_id in effect_ids:
		var effect_data: Dictionary = _effect_data(effect_id, effect_library)
		if effect_data.is_empty():
			output.append({
				"success": false,
				"reason": "unknown_effect",
				"effect_id": effect_id,
			})
			continue
		var active_effect: Dictionary = _build_on_hit_active_effect(effect_id, effect_data, attacker, target, profile)
		if active_effect.is_empty():
			output.append({
				"success": true,
				"effect_id": effect_id,
				"applied": false,
				"reason": "instant_or_placeholder_effect",
			})
			continue
		var stack_result: Dictionary = _apply_actor_effect_stack(target, active_effect, effect_data)
		stack_result["effect_id"] = effect_id
		stack_result["source_actor_id"] = attacker.actor_id
		stack_result["target_actor_id"] = target.actor_id
		stack_result["weapon_item_id"] = str(profile.get("item_id", ""))
		output.append(stack_result.duplicate(true))
		if simulation != null and simulation.has_method("emit_event"):
			simulation.emit_event("on_hit_effect_applied", stack_result.duplicate(true))
	return output


func _effect_data(effect_id: String, effect_library: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(effect_library.get(effect_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _build_on_hit_active_effect(effect_id: String, effect_data: Dictionary, attacker: RefCounted, target: RefCounted, profile: Dictionary) -> Dictionary:
	var is_infinite: bool = bool(effect_data.get("is_infinite", false))
	var duration: float = 0.0 if is_infinite else max(0.0, float(effect_data.get("duration", 0.0)))
	var modifiers: Dictionary = _dictionary_or_empty(effect_data.get("stat_modifiers", effect_data.get("modifiers", {}))).duplicate(true)
	var special_effects: Array[String] = _string_array(effect_data.get("special_effects", []))
	if duration <= 0.0 and not is_infinite and modifiers.is_empty():
		return {}
	return {
		"effect_id": "effect:%s" % effect_id,
		"base_effect_id": effect_id,
		"source": "on_hit",
		"source_actor_id": attacker.actor_id,
		"target_actor_id": target.actor_id,
		"weapon_item_id": str(profile.get("item_id", "")),
		"name": str(effect_data.get("name", effect_id)),
		"icon_path": str(effect_data.get("icon_path", "")),
		"category": str(effect_data.get("category", "debuff")),
		"duration_remaining": duration,
		"is_infinite": is_infinite,
		"modifiers": modifiers,
		"special_effects": special_effects,
		"stack_count": 1,
		"max_stacks": max(1, int(effect_data.get("max_stacks", 1))),
		"stack_mode": str(effect_data.get("stack_mode", "refresh")),
	}


func _apply_actor_effect_stack(actor: RefCounted, new_effect: Dictionary, effect_data: Dictionary) -> Dictionary:
	var effect_id: String = str(new_effect.get("effect_id", ""))
	var stack_mode: String = str(effect_data.get("stack_mode", new_effect.get("stack_mode", "refresh")))
	var is_stackable: bool = bool(effect_data.get("is_stackable", false))
	var max_stacks: int = max(1, int(effect_data.get("max_stacks", new_effect.get("max_stacks", 1))))
	var remaining: Array[Dictionary] = []
	var replaced: Array[Dictionary] = []
	var applied: Dictionary = new_effect.duplicate(true)
	var found_existing := false
	for active_effect in actor.active_effects:
		var active_data: Dictionary = _dictionary_or_empty(active_effect).duplicate(true)
		if str(active_data.get("effect_id", "")) != effect_id:
			remaining.append(active_data)
			continue
		found_existing = true
		replaced.append(active_data.duplicate(true))
		applied = _merged_effect_stack(active_data, new_effect, is_stackable, max_stacks, stack_mode)
	remaining.append(applied.duplicate(true))
	actor.active_effects = remaining
	return {
		"success": true,
		"applied": true,
		"stack_mode": stack_mode,
		"stack_count": int(applied.get("stack_count", 1)),
		"max_stacks": max_stacks,
		"duration_remaining": float(applied.get("duration_remaining", 0.0)),
		"effect": applied.duplicate(true),
		"replaced_effects": replaced.duplicate(true),
		"refreshed": found_existing,
	}


func _merged_effect_stack(active_effect: Dictionary, new_effect: Dictionary, is_stackable: bool, max_stacks: int, stack_mode: String) -> Dictionary:
	var merged: Dictionary = active_effect.duplicate(true)
	var current_duration: float = float(active_effect.get("duration_remaining", 0.0))
	var incoming_duration: float = float(new_effect.get("duration_remaining", 0.0))
	merged["source_actor_id"] = int(new_effect.get("source_actor_id", merged.get("source_actor_id", 0)))
	merged["weapon_item_id"] = str(new_effect.get("weapon_item_id", merged.get("weapon_item_id", "")))
	merged["is_infinite"] = bool(active_effect.get("is_infinite", false)) or bool(new_effect.get("is_infinite", false))
	merged["max_stacks"] = max_stacks
	merged["stack_mode"] = stack_mode
	if is_stackable:
		merged["stack_count"] = min(max_stacks, max(1, int(active_effect.get("stack_count", 1))) + 1)
	else:
		merged["stack_count"] = 1
	match stack_mode:
		"extend":
			merged["duration_remaining"] = current_duration + incoming_duration
		"intensity":
			merged["duration_remaining"] = max(current_duration, incoming_duration)
			merged["modifiers"] = _scaled_modifiers(_dictionary_or_empty(new_effect.get("modifiers", {})), int(merged.get("stack_count", 1)))
		_:
			merged["duration_remaining"] = max(current_duration, incoming_duration)
	return merged


func _scaled_modifiers(modifiers: Dictionary, stack_count: int) -> Dictionary:
	var output: Dictionary = {}
	for key in modifiers.keys():
		output[str(key)] = float(modifiers.get(key, 0.0)) * max(1, stack_count)
	return output


func _hit_check(simulation: RefCounted, attacker: RefCounted, target: RefCounted, profile: Dictionary) -> Dictionary:
	var actor_accuracy: float = _combat_attribute(simulation, attacker, "accuracy", 0.0)
	var weapon_accuracy: float = float(profile.get("accuracy", 0.0)) if profile.has("accuracy") else 0.0
	var evasion: float = clampf(_combat_attribute(simulation, target, "evasion", 0.0), 0.0, 0.95)
	var has_explicit_accuracy: bool = actor_accuracy != 0.0 or profile.has("accuracy")
	var chance: float = clampf(((actor_accuracy + weapon_accuracy) / 100.0) - evasion, 0.0, 1.0) if has_explicit_accuracy else 1.0
	if not has_explicit_accuracy:
		return {
			"hit": true,
			"chance": chance,
			"roll": 0.0,
			"counter": int(simulation.combat_state.get("combat_rng_counter", 0)),
			"salt": 0,
			"accuracy": actor_accuracy + weapon_accuracy,
			"evasion": evasion,
		}
	var salt: int = int(attacker.actor_id ^ (target.actor_id << 7) ^ 2246822519)
	var roll_data: Dictionary = _next_combat_random_unit(simulation, salt)
	var roll: float = float(roll_data.get("roll", 1.0))
	roll_data["hit"] = roll <= chance
	roll_data["chance"] = chance
	roll_data["accuracy"] = actor_accuracy + weapon_accuracy
	roll_data["evasion"] = evasion
	return roll_data


func _hit_preview(simulation: RefCounted, attacker: RefCounted, target: RefCounted, profile: Dictionary) -> Dictionary:
	var actor_accuracy: float = _combat_attribute(simulation, attacker, "accuracy", 0.0)
	var weapon_accuracy: float = float(profile.get("accuracy", 0.0)) if profile.has("accuracy") else 0.0
	var evasion: float = clampf(_combat_attribute(simulation, target, "evasion", 0.0), 0.0, 0.95)
	var has_explicit_accuracy: bool = actor_accuracy != 0.0 or profile.has("accuracy")
	var chance: float = clampf(((actor_accuracy + weapon_accuracy) / 100.0) - evasion, 0.0, 1.0) if has_explicit_accuracy else 1.0
	return {
		"hit_chance": chance,
		"accuracy": actor_accuracy + weapon_accuracy,
		"evasion": evasion,
	}


func _miss_damage_result(simulation: RefCounted, target: RefCounted, hit_roll: Dictionary) -> Dictionary:
	return {
		"damage": 0.0,
		"hit_kind": "miss",
		"defense": max(0.0, _combat_attribute(simulation, target, "defense", target.defense)),
		"damage_reduction": clampf(_combat_attribute(simulation, target, "damage_reduction", 0.0), 0.0, 0.95),
		"damage_bonus": 0.0,
		"hit_chance": float(hit_roll.get("chance", 0.0)),
	}


func _damage_preview(simulation: RefCounted, attacker: RefCounted, target: RefCounted, profile: Dictionary) -> Dictionary:
	var normal: Dictionary = _resolve_damage(simulation, attacker, target, profile, false)
	var critical: Dictionary = _resolve_damage(simulation, attacker, target, profile, true)
	return {
		"estimated_damage": float(normal.get("damage", 0.0)),
		"minimum_damage": 0.0,
		"maximum_damage": max(float(normal.get("damage", 0.0)), float(critical.get("damage", 0.0))),
		"hit_kind": str(normal.get("hit_kind", "hit")),
	}


func _resolve_damage(simulation: RefCounted, attacker: RefCounted, target: RefCounted, profile: Dictionary, critical: bool) -> Dictionary:
	var attack_damage: float = float(profile.get("damage", _combat_attribute(simulation, attacker, "attack_power", attacker.attack_power)))
	var defense: float = max(0.0, _combat_attribute(simulation, target, "defense", target.defense))
	var base_damage: float = max(0.0, attack_damage - defense)
	if base_damage <= 0.0:
		return {
			"damage": 0.0,
			"hit_kind": "blocked",
			"defense": defense,
			"damage_reduction": 0.0,
			"damage_bonus": 0.0,
		}
	var damage_reduction: float = clampf(_combat_attribute(simulation, target, "damage_reduction", 0.0), 0.0, 0.95)
	var damage_bonus: float = max(0.0, _active_effect_modifier(attacker, "damage_bonus"))
	var multiplier: float = _critical_multiplier(simulation, attacker, profile) if critical else 1.0
	var damage: float = max(1.0, round(base_damage * (1.0 + damage_bonus) * (1.0 - damage_reduction) * multiplier))
	return {
		"damage": damage,
		"hit_kind": "crit" if critical else "hit",
		"defense": defense,
		"damage_reduction": damage_reduction,
		"damage_bonus": damage_bonus,
	}


func _critical_hit(simulation: RefCounted, attacker: RefCounted, target: RefCounted, profile: Dictionary) -> Dictionary:
	var chance: float = _critical_chance(simulation, attacker, profile)
	if chance <= 0.0:
		return {
			"critical": false,
			"chance": chance,
			"roll": 1.0,
			"counter": int(simulation.combat_state.get("combat_rng_counter", 0)),
			"salt": 0,
		}
	var salt: int = int(target.actor_id ^ (attacker.actor_id << 13) ^ 3282425948)
	var roll_data: Dictionary = _next_combat_random_unit(simulation, salt)
	var roll: float = float(roll_data.get("roll", 1.0))
	roll_data["critical"] = roll <= chance
	roll_data["chance"] = chance
	return roll_data


func _critical_chance(simulation: RefCounted, attacker: RefCounted, profile: Dictionary) -> float:
	return clampf(float(profile.get("crit_chance", 0.0)) + _combat_attribute(simulation, attacker, "crit_chance", 0.0), 0.0, 1.0)


func _critical_multiplier(simulation: RefCounted, attacker: RefCounted, profile: Dictionary) -> float:
	if profile.has("crit_multiplier"):
		return max(1.0, float(profile.get("crit_multiplier", 1.0)))
	return max(1.0, _combat_attribute(simulation, attacker, "crit_damage", 1.0))


func _combat_attribute(simulation: RefCounted, actor: RefCounted, key: String, fallback: float = 0.0) -> float:
	var value: float = fallback
	if key == "attack_power":
		value = actor.attack_power
	elif key == "defense":
		value = actor.defense
	else:
		value = float(_dictionary_or_empty(actor.combat_attributes).get(key, fallback))
	value += _equipment_effects.attribute_modifier(actor, simulation.item_library, key)
	return value


func _active_effect_modifier(actor: RefCounted, key: String) -> float:
	var value := 0.0
	for effect in actor.active_effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		var modifiers: Dictionary = _dictionary_or_empty(effect_data.get("modifiers", {}))
		value += float(modifiers.get(key, 0.0))
	return value


func _next_combat_random_unit(simulation: RefCounted, salt: int) -> Dictionary:
	var seed: int = max(1, abs(int(simulation.combat_state.get("combat_rng_seed", 12648430))))
	var counter_before: int = max(0, int(simulation.combat_state.get("combat_rng_counter", 0)))
	# Rust 参考工程用 seed + counter + salt 的 deterministic RNG；这里保持同样的状态边界，
	# 但把计算限制在 31-bit 正整数内，避免 GDScript signed int 溢出差异影响重放。
	var mixed: int = seed % 2147483647
	mixed = (mixed + ((counter_before + 1) * 1103515245)) % 2147483647
	mixed = (mixed + (abs(salt) % 2147483647) * 1664525) % 2147483647
	mixed = (mixed + 1013904223) % 2147483647
	var roll: float = float(mixed % 1000000) / 1000000.0
	simulation.combat_state["combat_rng_seed"] = seed
	simulation.combat_state["combat_rng_counter"] = counter_before + 1
	return {
		"roll": roll,
		"counter": counter_before,
		"salt": salt,
	}


func _add_attack_preview_actor_fields(preview: Dictionary, attacker: RefCounted, target: RefCounted) -> void:
	if attacker != null:
		preview["actor_id"] = attacker.actor_id
		preview["attacker_grid"] = attacker.grid_position.to_dictionary()
		preview["attacker_side"] = attacker.side
	if target != null:
		preview["target_actor_id"] = target.actor_id
		preview["target_grid"] = target.grid_position.to_dictionary()
		preview["target_side"] = target.side
	if attacker != null and target != null:
		preview["distance"] = abs(attacker.grid_position.x - target.grid_position.x) + abs(attacker.grid_position.z - target.grid_position.z)


func _defeat_actor(simulation: RefCounted, actor_id: int, target_actor_id: int, target: RefCounted) -> void:
	var defeated_definition_id: String = target.definition_id
	var defeated_kind: String = target.kind
	var defeated_xp_reward: int = target.xp_reward
	var corpse: Dictionary = _create_corpse_container(simulation, target, actor_id)
	simulation.actor_registry.unregister_actor(target_actor_id)
	simulation.emit_event("actor_defeated", {
		"actor_id": target_actor_id,
		"definition_id": defeated_definition_id,
		"kind": defeated_kind,
		"defeated_by": actor_id,
	})
	simulation.emit_event("corpse_created", corpse.duplicate(true))
	simulation.grant_experience(actor_id, defeated_xp_reward, "kill:%s" % defeated_definition_id)
	simulation.record_enemy_defeated(actor_id, defeated_definition_id, defeated_kind)
	simulation.exit_combat_if_clear()


func _create_corpse_container(simulation: RefCounted, target: RefCounted, defeated_by_actor_id: int) -> Dictionary:
	var corpse_id: String = "corpse_%s_%d" % [target.definition_id, target.actor_id]
	var equipped_slots: Dictionary = _equipped_slots_snapshot(target)
	var inventory: Array[Dictionary] = _actor_inventory_entries(simulation, target, simulation.item_library)
	var corpse := {
		"container_id": corpse_id,
		"container_type": "corpse",
		"container_origin": "combat_defeat",
		"map_id": target.map_id,
		"grid_position": target.grid_position.to_dictionary(),
		"display_name": "%s的尸体" % target.display_name,
		"source_actor_id": target.actor_id,
		"source_actor_definition_id": target.definition_id,
		"source_actor_kind": target.kind,
		"defeated_by_actor_id": defeated_by_actor_id,
		"appearance_profile_id": target.appearance_profile_id,
		"model_asset": target.model_asset,
		"equipped_slots": equipped_slots,
		"money": max(0, int(target.money)),
		"inventory": inventory,
	}
	simulation.corpse_containers[corpse_id] = corpse
	simulation.container_sessions[corpse_id] = {
		"container_id": corpse_id,
		"container_type": "corpse",
		"container_origin": "combat_defeat",
		"map_id": target.map_id,
		"grid_position": target.grid_position.to_dictionary(),
		"source_actor_id": target.actor_id,
		"source_actor_definition_id": target.definition_id,
		"source_actor_kind": target.kind,
		"defeated_by_actor_id": defeated_by_actor_id,
		"display_name": corpse.get("display_name", corpse_id),
		"inventory": inventory.duplicate(true),
		"money": max(0, int(corpse.get("money", 0))),
	}
	simulation.map_interaction_targets[corpse_id] = {
		"target_id": corpse_id,
		"target_type": "map_object",
		"display_name": corpse.get("display_name", corpse_id),
		"kind": "container",
		"container_type": "corpse",
		"container_origin": "combat_defeat",
		"anchor": target.grid_position.to_dictionary(),
		"cells": [target.grid_position.to_dictionary()],
		"container_inventory": inventory.duplicate(true),
		"source_actor_id": target.actor_id,
		"source_actor_definition_id": target.definition_id,
		"defeated_by_actor_id": defeated_by_actor_id,
		"equipped_slots": equipped_slots.duplicate(true),
	}
	return corpse


func _equipped_slots_snapshot(actor: RefCounted) -> Dictionary:
	var output: Dictionary = {}
	var slots: Array = actor.equipment.keys()
	slots.sort()
	for slot_id in slots:
		var equipped_item_id: String = str(actor.equipment.get(slot_id, ""))
		if not equipped_item_id.is_empty():
			output[str(slot_id)] = equipped_item_id
	return output


func _actor_inventory_entries(simulation: RefCounted, actor: RefCounted, item_library: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var ids: Array = actor.inventory.keys()
	ids.sort()
	for item_id in ids:
		var count: int = int(actor.inventory.get(item_id, 0))
		if count > 0:
			entries.append({"item_id": str(item_id), "count": count})
	for slot_id in actor.equipment.keys():
		var equipped_item_id: String = str(actor.equipment.get(slot_id, ""))
		if equipped_item_id.is_empty():
			continue
		_inventory_entries.add(entries, equipped_item_id, 1)
	for slot_id in actor.weapon_ammo.keys():
		var loaded: int = int(actor.weapon_ammo.get(slot_id, 0))
		if loaded <= 0:
			continue
		var equipped_weapon_id: String = str(actor.equipment.get(str(slot_id), ""))
		var ammo_type: String = _weapon_ammo_type(equipped_weapon_id, item_library)
		if ammo_type.is_empty():
			continue
		_inventory_entries.add(entries, ammo_type, loaded)
	for loot_index in range(actor.loot_table.size()):
		var loot_entry: Variant = actor.loot_table[loot_index]
		var loot_data: Dictionary = _dictionary_or_empty(loot_entry)
		var item_id: String = _normalize_item_id(loot_data.get("item_id", loot_data.get("itemId", "")))
		var count: int = _resolve_loot_drop_count(simulation, actor.actor_id, item_id, loot_data, loot_index)
		if count > 0:
			_inventory_entries.add(entries, item_id, count)
	return entries


func _weapon_ammo_type(item_id: String, item_library: Dictionary) -> String:
	if item_id.is_empty():
		return ""
	var weapon: Dictionary = _weapon_fragment(item_id, item_library)
	return _normalize_item_id(weapon.get("ammo_type", ""))


func _weapon_fragment(item_id: String, item_library: Dictionary) -> Dictionary:
	if item_id.is_empty():
		return {}
	var record: Dictionary = _dictionary_or_empty(item_library.get(item_id, {}))
	var item: Dictionary = _dictionary_or_empty(record.get("data", record))
	for fragment in _array_or_empty(item.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "weapon":
			return fragment_data
	return {}


func _resolve_loot_drop_count(simulation: RefCounted, actor_id: int, item_id: String, entry: Dictionary, loot_index: int) -> int:
	if item_id.is_empty():
		return 0
	var min_count: int = int(entry.get("min", 0))
	var max_count: int = int(entry.get("max", 0))
	var chance: float = clampf(float(entry.get("chance", 0.0)), 0.0, 1.0)
	if max_count < min_count or max_count <= 0 or chance <= 0.0:
		return 0
	if chance >= 1.0 and min_count == max_count:
		return max(0, min_count)
	var salt_base: int = abs(actor_id * 65537 + abs(hash(item_id)) + loot_index * 4099)
	var chance_roll: float = float(_next_combat_random_unit(simulation, salt_base).get("roll", 1.0))
	if chance_roll > chance:
		return 0
	var span: int = max_count - min_count
	var count_roll: int = 0
	if span > 0:
		var count_unit: float = float(_next_combat_random_unit(simulation, salt_base + 97).get("roll", 0.0))
		count_roll = clampi(int(floor(count_unit * float(span + 1))), 0, span)
	return max(0, min_count + count_roll)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	for entry in _array_or_empty(value):
		var text: String = str(entry).strip_edges()
		if not text.is_empty():
			output.append(text)
	return output


func _normalize_item_id(value: Variant) -> String:
	if value == null:
		return ""
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	if typeof(value) == TYPE_INT:
		return str(value)
	var text: String = str(value).strip_edges()
	return "" if text == "<null>" else text
