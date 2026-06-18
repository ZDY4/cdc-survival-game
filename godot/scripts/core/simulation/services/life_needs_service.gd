extends RefCounted

## 聚落生活「需求」层：饥饿/精力/士气的快照、衰减、定时 tick 与即时增减。
## 由 simulation 持有权威 actor.life 状态，本服务为无状态规则计算；所有状态读写经 simulation 转发。


func tick_settlement_life_needs(simulation: RefCounted, minutes: int) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var tick_minutes: int = max(0, minutes)
	if tick_minutes <= 0:
		return output
	for actor in simulation.actor_registry.actors():
		if actor.hp <= 0.0:
			continue
		var life: Dictionary = simulation._dictionary_or_empty(actor.life)
		if str(life.get("settlement_id", "")).is_empty():
			continue
		var profile: Dictionary = simulation._life_need_profile(actor)
		var before: Dictionary = simulation._life_needs_snapshot(actor)
		var runtime: Dictionary = simulation._ensure_life_runtime(actor)
		var needs: Dictionary = simulation._dictionary_or_empty(runtime.get("needs", {})).duplicate(true)
		var hours: float = float(tick_minutes) / 60.0
		simulation._apply_life_need_decay(needs, "hunger", float(profile.get("hunger_decay_per_hour", 0.0)) * hours)
		simulation._apply_life_need_decay(needs, "energy", float(profile.get("energy_decay_per_hour", 0.0)) * hours)
		simulation._apply_life_need_decay(needs, "morale", float(profile.get("morale_decay_per_hour", 0.0)) * hours)
		runtime["needs"] = needs
		runtime["last_need_tick"] = {
			"world_time": simulation.world_time.duplicate(true),
			"minutes": tick_minutes,
			"profile_id": str(life.get("need_profile_id", "")),
		}
		simulation._set_life_runtime(actor, runtime)
		var after: Dictionary = simulation._life_needs_snapshot(actor)
		var tick: Dictionary = {
			"actor_id": actor.actor_id,
			"definition_id": actor.definition_id,
			"settlement_id": str(life.get("settlement_id", "")),
			"profile_id": str(life.get("need_profile_id", "")),
			"minutes": tick_minutes,
			"needs_before": before,
			"needs_after": after,
		}
		output.append(tick)
		simulation._emit("settlement_life_needs_ticked", tick.duplicate(true))
	return output


func life_need_profile(simulation: RefCounted, actor: RefCounted) -> Dictionary:
	var life: Dictionary = simulation._dictionary_or_empty(actor.life)
	var profile_id: String = str(life.get("need_profile_id", ""))
	var output: Dictionary = {}
	for profile in simulation._ai_collection("need_profiles"):
		var profile_data: Dictionary = simulation._dictionary_or_empty(profile)
		if str(profile_data.get("id", "")) == profile_id:
			output = profile_data.duplicate(true)
			break
	var override: Dictionary = simulation._dictionary_or_empty(life.get("need_profile_override", {}))
	for key in override.keys():
		output[str(key)] = override[key]
	return output


func ai_collection(simulation: RefCounted, collection_name: String) -> Array:
	for record in simulation.ai_library.values():
		var record_data: Dictionary = simulation._dictionary_or_empty(record)
		var data: Dictionary = simulation._dictionary_or_empty(record_data.get("data", record_data))
		if data.has(collection_name):
			return simulation._array_or_empty(data.get(collection_name, []))
	return []


func life_needs_snapshot(simulation: RefCounted, actor: RefCounted) -> Dictionary:
	var runtime: Dictionary = simulation._ensure_life_runtime(actor)
	var needs: Dictionary = simulation._dictionary_or_empty(runtime.get("needs", {}))
	return {
		"hunger": life_need_value_snapshot(simulation, needs, "hunger"),
		"energy": life_need_value_snapshot(simulation, needs, "energy"),
		"morale": life_need_value_snapshot(simulation, needs, "morale"),
	}


func life_need_value_snapshot(simulation: RefCounted, needs: Dictionary, need_id: String) -> Dictionary:
	var data: Dictionary = simulation._dictionary_or_empty(needs.get(need_id, {}))
	var max_value: float = max(1.0, float(data.get("max", 100.0)))
	return {
		"current": clampf(float(data.get("current", max_value)), 0.0, max_value),
		"max": max_value,
	}


func ensure_life_runtime(simulation: RefCounted, actor: RefCounted) -> Dictionary:
	var life: Dictionary = simulation._dictionary_or_empty(actor.life).duplicate(true)
	var runtime: Dictionary = simulation._dictionary_or_empty(life.get("runtime", {})).duplicate(true)
	var needs: Dictionary = simulation._dictionary_or_empty(runtime.get("needs", {})).duplicate(true)
	for need_id in ["hunger", "energy", "morale"]:
		if not needs.has(need_id):
			needs[need_id] = {"current": 100.0, "max": 100.0}
		else:
			needs[need_id] = life_need_value_snapshot(simulation, needs, need_id)
	runtime["needs"] = needs
	life["runtime"] = runtime
	actor.life = life
	return runtime


func set_life_runtime(simulation: RefCounted, actor: RefCounted, runtime: Dictionary) -> void:
	var life: Dictionary = simulation._dictionary_or_empty(actor.life).duplicate(true)
	life["runtime"] = runtime.duplicate(true)
	actor.life = life


func apply_life_need_decay(_simulation: RefCounted, needs: Dictionary, need_id: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var data: Dictionary = life_need_value_snapshot(_simulation, needs, need_id)
	data["current"] = clampf(float(data.get("current", 100.0)) - amount, 0.0, float(data.get("max", 100.0)))
	needs[need_id] = data


func apply_life_need_delta(simulation: RefCounted, actor: RefCounted, deltas: Dictionary, source: String, source_id: String = "") -> Dictionary:
	if deltas.is_empty():
		return {}
	var before: Dictionary = simulation._life_needs_snapshot(actor)
	var runtime: Dictionary = simulation._ensure_life_runtime(actor)
	var needs: Dictionary = simulation._dictionary_or_empty(runtime.get("needs", {})).duplicate(true)
	for key in deltas.keys():
		var normalized: String = str(key).trim_suffix("_delta")
		if not ["hunger", "energy", "morale"].has(normalized):
			continue
		var data: Dictionary = life_need_value_snapshot(simulation, needs, normalized)
		data["current"] = clampf(float(data.get("current", 100.0)) + float(deltas.get(key, 0.0)), 0.0, float(data.get("max", 100.0)))
		needs[normalized] = data
	runtime["needs"] = needs
	runtime["last_need_effect"] = {
		"source": source,
		"source_id": source_id,
		"world_time": simulation.world_time.duplicate(true),
		"deltas": deltas.duplicate(true),
	}
	simulation._set_life_runtime(actor, runtime)
	var after: Dictionary = simulation._life_needs_snapshot(actor)
	var payload: Dictionary = {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"source": source,
		"source_id": source_id,
		"deltas": deltas.duplicate(true),
		"needs_before": before,
		"needs_after": after,
	}
	simulation._emit("settlement_life_needs_changed", payload.duplicate(true))
	return payload
