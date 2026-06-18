extends RefCounted

## 激活效果运行时层：处理持续效果 tick、DOT 伤害、击杀归因与 stun 跳过回合。
## 无状态规则计算；actor / combat / turn 状态仍由 simulation 持有。


func tick_actor_active_effects(simulation: RefCounted) -> void:
	for actor in simulation.actor_registry.actors():
		if actor.hp <= 0.0:
			continue
		var remaining: Array[Dictionary] = []
		var defeated_by_effect := false
		for effect in actor.active_effects:
			var effect_data: Dictionary = effect.duplicate(true)
			if bool(effect_data.get("is_infinite", false)):
				remaining.append(effect_data)
				continue
			var before: float = float(effect_data.get("duration_remaining", 0.0))
			var after: float = max(0.0, before - 1.0)
			effect_data["duration_remaining"] = after
			var damage_tick: Dictionary = simulation._apply_active_effect_damage_tick(actor, effect_data, before, after)
			if bool(damage_tick.get("defeated", false)):
				defeated_by_effect = true
				break
			if after > 0.0:
				remaining.append(effect_data)
				simulation._emit("skill_effect_ticked", {
					"actor_id": actor.actor_id,
					"effect_id": str(effect_data.get("effect_id", "")),
					"skill_id": str(effect_data.get("skill_id", "")),
					"before": before,
					"after": after,
				})
			else:
				simulation._emit("skill_effect_expired", {
					"actor_id": actor.actor_id,
					"effect_id": str(effect_data.get("effect_id", "")),
					"skill_id": str(effect_data.get("skill_id", "")),
				})
		if not defeated_by_effect and simulation.actor_registry.get_actor(actor.actor_id) != null:
			actor.active_effects = remaining


func apply_active_effect_damage_tick(simulation: RefCounted, actor: RefCounted, effect_data: Dictionary, before_duration: float, after_duration: float) -> Dictionary:
	var damage: float = simulation._active_effect_tick_damage(effect_data)
	if damage <= 0.0:
		return {"success": false, "reason": "no_damage"}
	var hp_before: float = actor.hp
	actor.hp = max(0.0, actor.hp - damage)
	actor.resources["hp"] = {"current": actor.hp, "max": actor.max_hp}
	var source_actor_id: int = int(effect_data.get("source_actor_id", 0))
	simulation._emit("active_effect_damage_tick", {
		"actor_id": actor.actor_id,
		"source_actor_id": source_actor_id,
		"effect_id": str(effect_data.get("effect_id", "")),
		"base_effect_id": str(effect_data.get("base_effect_id", "")),
		"special_effects": simulation._string_array(effect_data.get("special_effects", [])),
		"stack_count": int(effect_data.get("stack_count", 1)),
		"damage": damage,
		"hp_before": hp_before,
		"hp_after": actor.hp,
		"duration_before": before_duration,
		"duration_after": after_duration,
		"defeated": actor.hp <= 0.0,
	})
	if actor.hp > 0.0:
		return {"success": true, "damage": damage, "defeated": false}
	simulation._defeat_actor_from_active_effect(source_actor_id, actor, effect_data)
	return {"success": true, "damage": damage, "defeated": true}


func active_effect_tick_damage(simulation: RefCounted, effect_data: Dictionary) -> float:
	var special_effects: Array[String] = simulation._string_array(effect_data.get("special_effects", []))
	var base_effect_id := str(effect_data.get("base_effect_id", effect_data.get("effect_id", ""))).trim_prefix("effect:")
	var library_effect: Dictionary = simulation._effect_data(base_effect_id)
	var damage: float = simulation._effect_tick_damage_value(effect_data)
	if damage <= 0.0:
		damage = simulation._effect_tick_damage_value(library_effect)
	if damage <= 0.0:
		if special_effects.has("bleeding") or base_effect_id == "bleeding":
			damage = 5.0
		elif special_effects.has("poison") or base_effect_id == "poison":
			damage = 3.0
	var interval: float = max(1.0, float(effect_data.get("tick_interval", library_effect.get("tick_interval", 1.0))))
	if interval > 1.0:
		damage = damage / interval
	return max(0.0, damage * max(1, int(effect_data.get("stack_count", 1))))


func effect_tick_damage_value(simulation: RefCounted, effect_data: Dictionary) -> float:
	if effect_data.is_empty():
		return 0.0
	for key in ["damage_per_tick", "tick_damage", "dot_damage", "damage_over_time", "bleeding_damage", "poison_damage"]:
		if effect_data.has(key):
			return max(0.0, float(effect_data.get(key, 0.0)))
	var gameplay: Dictionary = simulation._dictionary_or_empty(effect_data.get("gameplay_effect", {}))
	var resource_deltas: Dictionary = simulation._dictionary_or_empty(gameplay.get("resource_deltas", {}))
	for key in ["hp", "health"]:
		if resource_deltas.has(key):
			return max(0.0, -float(resource_deltas.get(key, 0.0)))
	return 0.0


func effect_data(simulation: RefCounted, effect_id: String) -> Dictionary:
	if effect_id.is_empty():
		return {}
	var record: Dictionary = simulation._dictionary_or_empty(simulation.effect_library.get(effect_id, {}))
	return simulation._dictionary_or_empty(record.get("data", record))


func defeat_actor_from_active_effect(simulation: RefCounted, source_actor_id: int, target: RefCounted, effect_data: Dictionary) -> void:
	var defeated_by_actor_id: int = source_actor_id
	if simulation.actor_registry.get_actor(defeated_by_actor_id) == null:
		defeated_by_actor_id = 0
	simulation._combat_runner.defeat_actor(simulation, defeated_by_actor_id, target.actor_id, target)
	simulation._emit("active_effect_defeated_actor", {
		"actor_id": target.actor_id,
		"source_actor_id": defeated_by_actor_id,
		"effect_id": str(effect_data.get("effect_id", "")),
		"base_effect_id": str(effect_data.get("base_effect_id", "")),
	})
	if target.side == "player":
		simulation.exit_combat_if_player_defeated("player_defeated_by_active_effect")


func actor_has_special_effect(simulation: RefCounted, actor: RefCounted, special_effect_id: String) -> bool:
	return not simulation._actor_special_effects(actor, special_effect_id).is_empty()


func actor_special_effects(simulation: RefCounted, actor: RefCounted, special_effect_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if actor == null:
		return output
	for effect in actor.active_effects:
		var effect_data: Dictionary = simulation._dictionary_or_empty(effect)
		var base_effect_id := str(effect_data.get("base_effect_id", effect_data.get("effect_id", ""))).trim_prefix("effect:")
		if base_effect_id == special_effect_id or str(effect_data.get("effect_id", "")) == special_effect_id:
			output.append(effect_data.duplicate(true))
			continue
		if simulation._string_array(effect_data.get("special_effects", [])).has(special_effect_id):
			output.append(effect_data.duplicate(true))
	return output


func stunned_turn_skip_payload(simulation: RefCounted, actor: RefCounted, reason: String) -> Dictionary:
	var effects: Array[Dictionary] = simulation._actor_special_effects(actor, "stun")
	var effect_ids: Array[String] = []
	for effect in effects:
		var effect_id := str(effect.get("effect_id", ""))
		if not effect_id.is_empty():
			effect_ids.append(effect_id)
	return {
		"actor_id": actor.actor_id,
		"reason": reason,
		"special_effect": "stun",
		"effect_ids": effect_ids,
		"effects": effects.duplicate(true),
		"ap": actor.ap,
		"round": int(simulation.turn_state.get("round", 1)),
		"combat_active": bool(simulation.combat_state.get("active", false)) and actor.in_combat,
	}


func stunned_npc_turn_result(simulation: RefCounted, actor: RefCounted, reason: String = "npc_turn") -> Dictionary:
	var payload: Dictionary = simulation._stunned_turn_skip_payload(actor, reason)
	simulation._emit("actor_turn_skipped", payload.duplicate(true))
	return {
		"success": true,
		"actor_id": actor.actor_id,
		"intent": "skip",
		"reason": "actor_stunned",
		"skipped_turn": true,
		"effect_ids": simulation._array_or_empty(payload.get("effect_ids", [])).duplicate(true),
		"ap": actor.ap,
	}


func submit_stunned_player_turn(simulation: RefCounted, actor: RefCounted, command: Dictionary, command_kind: String) -> Dictionary:
	var topology: Dictionary = simulation._dictionary_or_empty(command.get("topology", {}))
	var skip_payload: Dictionary = simulation._stunned_turn_skip_payload(actor, "player_command:%s" % command_kind)
	simulation._emit("actor_turn_skipped", skip_payload.duplicate(true))
	simulation._close_turn(actor.actor_id, "stunned")
	var npc_results: Array[Dictionary] = simulation.advance_world_turn(topology)
	simulation._open_turn(actor.actor_id, "player_turn")
	return {
		"success": false,
		"kind": "stunned_turn_skip",
		"reason": "actor_stunned",
		"actor_id": actor.actor_id,
		"command_kind": command_kind,
		"effect_ids": simulation._array_or_empty(skip_payload.get("effect_ids", [])).duplicate(true),
		"skipped_turn": true,
		"npc_results": npc_results,
		"turn_state": simulation.turn_state.duplicate(true),
	}
