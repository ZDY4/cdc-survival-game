extends RefCounted

## 战斗运行时层：发起/预览/校验攻击、击杀记录、进入战斗与先攻排序、战斗退出（清场/强制/玩家阵亡/视野衰减）、敌我可见性配对、武器攻击档案与弹药/耐久校验。
## 无状态规则计算；权威 combat_state / actor 状态由 simulation 持有，所有读写经 simulation 转发。

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")


func perform_attack(simulation: RefCounted, actor_id: int, target_actor_id: int, topology: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	return simulation._combat_runner.perform_attack(simulation, actor_id, target_actor_id, simulation._topology_with_runtime_door_states(topology), options)


func preview_attack(simulation: RefCounted, actor_id: int, target_actor_id: int, topology: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var combat_topology: Dictionary = simulation._topology_with_runtime_door_states(topology)
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return simulation._combat_runner.preview_attack(simulation, actor_id, target_actor_id, combat_topology, options)
	var profile: Dictionary = simulation._dictionary_or_empty(options.get("weapon_profile", {}))
	if profile.is_empty():
		profile = simulation._attack_profile(actor, simulation._dictionary_or_empty(options.get("item_library", simulation.item_library)))
	var attack_range: int = int(options.get("range", int(profile.get("range", simulation.DEFAULT_ATTACK_RANGE))))
	var preview: Dictionary = simulation._combat_runner.preview_attack(simulation, actor_id, target_actor_id, combat_topology, {
		"range": attack_range,
		"min_range": simulation._attack_min_range_from_options(options, profile),
		"weapon_profile": profile,
		"allow_non_hostile_attack": simulation._allows_non_hostile_attack_option(options),
		"confirmation_required": bool(options.get("confirmation_required", simulation._allows_non_hostile_attack_option(options))),
		"friendly_fire_relationship_delta": float(options.get("friendly_fire_relationship_delta", options.get("non_hostile_attack_relationship_delta", -75.0))),
	})
	var attack_cost: float = float(options.get("ap_cost", profile.get("ap_cost", simulation.DEFAULT_ATTACK_AP)))
	preview["ap_cost"] = attack_cost
	preview["ap_available"] = actor.ap
	preview["ap_affordable"] = actor.ap >= attack_cost
	var ammo_check: Dictionary = simulation._attack_ammo_check(actor, profile)
	preview["ammo_check"] = ammo_check.duplicate(true)
	preview["ammo_available"] = bool(ammo_check.get("success", true))
	if bool(preview.get("can_attack", false)) and (not bool(preview.get("ap_affordable", false)) or not bool(preview.get("ammo_available", true))):
		preview["success"] = false
		preview["can_attack"] = false
		if not bool(preview.get("ap_affordable", false)):
			preview["reason"] = "ap_insufficient"
		else:
			preview["reason"] = str(ammo_check.get("reason", "ammo_unavailable"))
	return preview


func validate_attack_target(simulation: RefCounted, actor_id: int, target_actor_id: int, options: Dictionary = {}) -> Dictionary:
	return simulation._combat_runner.validate_attack_target(simulation, actor_id, target_actor_id, options)


func record_enemy_defeated(simulation: RefCounted, actor_id: int, enemy_definition_id: String, enemy_kind: String = "enemy") -> void:
	simulation._quest_runner.record_enemy_defeated(simulation, actor_id, enemy_definition_id, enemy_kind)


func enter_combat(simulation: RefCounted, actor_ids: Array, reason: String) -> void:
	var seed_participants: Array[int] = []
	for actor_id in actor_ids:
		var normalized_id: int = int(actor_id)
		if normalized_id > 0 and not seed_participants.has(normalized_id):
			seed_participants.append(normalized_id)
	var participants: Array[int] = simulation._collect_combat_participants(seed_participants)
	for actor in simulation.actor_registry.actors():
		if participants.has(actor.actor_id):
			actor.in_combat = true
	if not bool(simulation.combat_state.get("active", false)):
		simulation.combat_state["active"] = true
		simulation.combat_state["round"] = int(simulation.turn_state.get("round", 1))
		simulation.combat_state["participants"] = participants
		simulation._refresh_combat_turn_order("combat_started")
		simulation.combat_state["turns_without_hostile_player_sight"] = 0
		simulation.combat_state["last_hostile_seen_turn"] = int(simulation.turn_state.get("round", 1)) if simulation._participants_include_hostile_player_pair(participants) else 0
		simulation._emit("combat_started", {
			"participants": participants,
			"turn_order": simulation._array_or_empty(simulation.combat_state.get("turn_order", [])).duplicate(true),
			"initiative": simulation._array_or_empty(simulation.combat_state.get("initiative", [])).duplicate(true),
			"current_combat_actor_id": int(simulation.combat_state.get("current_combat_actor_id", 0)),
			"next_combat_actor_id": int(simulation.combat_state.get("next_combat_actor_id", 0)),
			"seed_participants": seed_participants,
			"added_participants": participants.duplicate(),
			"round": int(simulation.combat_state.get("round", 0)),
			"last_hostile_seen_turn": int(simulation.combat_state.get("last_hostile_seen_turn", 0)),
			"reason": reason,
		})
	else:
		var existing: Array = simulation._array_or_empty(simulation.combat_state.get("participants", []))
		var added: Array[int] = []
		for actor_id in participants:
			if not existing.has(actor_id):
				existing.append(actor_id)
				added.append(actor_id)
		simulation.combat_state["participants"] = existing
		if not added.is_empty():
			for actor in simulation.actor_registry.actors():
				if added.has(actor.actor_id):
					actor.in_combat = true
			simulation._refresh_combat_turn_order("combat_participants_updated")
			if simulation._participants_include_hostile_player_pair(existing):
				simulation.combat_state["last_hostile_seen_turn"] = int(simulation.turn_state.get("round", 1))
			simulation._emit("combat_participants_updated", {
				"participants": existing.duplicate(),
				"turn_order": simulation._array_or_empty(simulation.combat_state.get("turn_order", [])).duplicate(true),
				"initiative": simulation._array_or_empty(simulation.combat_state.get("initiative", [])).duplicate(true),
				"current_combat_actor_id": int(simulation.combat_state.get("current_combat_actor_id", 0)),
				"next_combat_actor_id": int(simulation.combat_state.get("next_combat_actor_id", 0)),
				"seed_participants": seed_participants,
				"added_participants": added,
				"round": int(simulation.combat_state.get("round", 0)),
				"last_hostile_seen_turn": int(simulation.combat_state.get("last_hostile_seen_turn", 0)),
				"reason": reason,
			})


func _combat_initiative_sort_key(simulation: RefCounted, actor_id: int) -> Array:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return [9999, 9999, actor_id]
	var side_rank := 0 if actor.side == "player" else 1
	return [-simulation._combat_initiative_score(actor), side_rank, actor_id]


func _combat_initiative_score(simulation: RefCounted, actor: RefCounted) -> float:
	return simulation._combat_initiative_speed(actor)


func _combat_initiative_speed(simulation: RefCounted, actor: RefCounted) -> float:
	var attributes: Dictionary = simulation._dictionary_or_empty(actor.combat_attributes)
	return float(attributes.get("initiative", attributes.get("speed", 0.0)))


func exit_combat_if_clear(simulation: RefCounted, reason: String = "hostiles_cleared") -> bool:
	if not bool(simulation.combat_state.get("active", false)):
		return false
	var has_hostile := false
	for actor in simulation.actor_registry.actors():
		if actor.side == "hostile" and actor.hp > 0.0 and (actor.map_id.is_empty() or actor.map_id == simulation.active_map_id):
			has_hostile = true
			break
	if has_hostile:
		return false
	simulation._finish_combat_state(reason, {}, false)
	return true


func force_end_combat(simulation: RefCounted, reason: String = "forced", metadata: Dictionary = {}) -> Dictionary:
	if not bool(simulation.combat_state.get("active", false)):
		return {
			"success": false,
			"reason": "combat_inactive",
			"end_reason": reason,
		}
	simulation._finish_combat_state(reason, metadata, true)
	return {
		"success": true,
		"reason": reason,
		"metadata": metadata.duplicate(true),
	}


func exit_combat_if_player_defeated(simulation: RefCounted, reason: String = "player_defeated") -> bool:
	if not bool(simulation.combat_state.get("active", false)):
		return false
	var has_living_player := false
	for actor in simulation.actor_registry.actors():
		if actor.side == "player" and actor.hp > 0.0 and (actor.map_id.is_empty() or actor.map_id == simulation.active_map_id):
			has_living_player = true
			break
	if has_living_player:
		return false
	simulation.force_end_combat(reason)
	return true


func update_combat_visibility_decay(simulation: RefCounted, topology: Dictionary = {}) -> Dictionary:
	if not bool(simulation.combat_state.get("active", false)):
		return {"success": false, "reason": "combat_inactive"}
	var visibility_pair: Dictionary = simulation.hostile_player_visibility_pair(simulation._topology_with_runtime_door_states(topology))
	if not visibility_pair.is_empty():
		var previous: int = int(simulation.combat_state.get("turns_without_hostile_player_sight", 0))
		simulation.combat_state["turns_without_hostile_player_sight"] = 0
		simulation.combat_state["last_hostile_seen_turn"] = int(simulation.turn_state.get("round", 1))
		if previous > 0:
			simulation._emit("combat_visibility_restored", {
				"previous_no_sight_turns": previous,
				"hostile_actor_id": int(visibility_pair.get("hostile_actor_id", 0)),
				"player_actor_id": int(visibility_pair.get("player_actor_id", 0)),
			})
		return {
			"success": true,
			"visible": true,
			"combat_exited": false,
			"turns_without_hostile_player_sight": 0,
			"visibility_pair": visibility_pair,
		}

	var no_sight_turns: int = int(simulation.combat_state.get("turns_without_hostile_player_sight", 0)) + 1
	simulation.combat_state["turns_without_hostile_player_sight"] = no_sight_turns
	simulation._emit("combat_visibility_decay", {
		"turns_without_hostile_player_sight": no_sight_turns,
		"threshold": simulation.COMBAT_EXIT_NO_SIGHT_TURNS,
	})
	if no_sight_turns < simulation.COMBAT_EXIT_NO_SIGHT_TURNS:
		return {
			"success": true,
			"visible": false,
			"combat_exited": false,
			"turns_without_hostile_player_sight": no_sight_turns,
		}

	simulation._finish_combat_state("visibility_decay", {}, true)
	return {
		"success": true,
		"visible": false,
		"combat_exited": true,
		"reason": "visibility_decay",
		"turns_without_hostile_player_sight": 0,
	}


func hostile_player_visibility_pair(simulation: RefCounted, topology: Dictionary = {}) -> Dictionary:
	var visibility_topology: Dictionary = simulation._topology_with_runtime_door_states(topology)
	for hostile in simulation.actor_registry.actors():
		if hostile.side != "hostile" or hostile.hp <= 0.0:
			continue
		if not hostile.map_id.is_empty() and hostile.map_id != simulation.active_map_id:
			continue
		for player in simulation.actor_registry.actors():
			if player.side != "player" or player.hp <= 0.0:
				continue
			if not player.map_id.is_empty() and player.map_id != simulation.active_map_id:
				continue
			if simulation._hostile_can_see_player(hostile, player, visibility_topology):
				return {
					"hostile_actor_id": hostile.actor_id,
					"player_actor_id": player.actor_id,
				}
	return {}


func _attack_profile(simulation: RefCounted, actor: RefCounted, items: Dictionary) -> Dictionary:
	var equipped_item_id: String = str(actor.equipment.get("main_hand", ""))
	var item_data: Dictionary = simulation._item_data_from_library(equipped_item_id, items)
	var weapon: Dictionary = simulation._weapon_fragment(equipped_item_id, items)
	if weapon.is_empty():
		return {
			"item_id": equipped_item_id,
			"damage": actor.attack_power,
			"range": simulation.DEFAULT_ATTACK_RANGE,
			"min_range": 0,
			"ap_cost": simulation.DEFAULT_ATTACK_AP,
			"crit_chance": 0.0,
			"crit_multiplier": 1.0,
			"ammo_type": "",
			"on_hit_effect_ids": [],
			"equipment_slot": "main_hand",
			"max_ammo": 0,
			"effect_data": simulation._dictionary_or_empty(item_data.get("effect_data", {})).duplicate(true),
		}
	var attack_speed: float = max(0.1, float(weapon.get("attack_speed", 1.0)))
	var weapon_range: int = max(1, simulation._optional_int(weapon.get("range", simulation.DEFAULT_ATTACK_RANGE), simulation.DEFAULT_ATTACK_RANGE))
	var weapon_min_range: int = clampi(simulation._weapon_min_range(weapon), 0, weapon_range)
	var max_ammo: int = simulation._equipment_effects.weapon_magazine_capacity(actor, weapon, items)
	var effect_data: Dictionary = simulation._dictionary_or_empty(item_data.get("effect_data", {}))
	var durability: Dictionary = simulation._item_durability_fragment(item_data)
	var on_hit_effect_ids: Array[String] = simulation._string_array(weapon.get("on_hit_effect_ids", []))
	if on_hit_effect_ids.is_empty():
		on_hit_effect_ids = simulation._string_array(weapon.get("special_effects", []))
	var profile: Dictionary = {
		"item_id": equipped_item_id,
		"damage": float(weapon.get("damage", actor.attack_power)),
		"range": weapon_range,
		"min_range": weapon_min_range,
		"ap_cost": max(1.0, ceil(simulation.DEFAULT_ATTACK_AP / attack_speed)),
		"attack_speed": attack_speed,
		"crit_chance": clampf(float(weapon.get("crit_chance", 0.0)), 0.0, 1.0),
		"crit_multiplier": max(1.0, float(weapon.get("crit_multiplier", 1.0))),
		"ammo_type": simulation._normalize_item_id(weapon.get("ammo_type", "")),
		"ammo_per_attack": 1,
		"on_hit_effect_ids": on_hit_effect_ids,
		"equipment_slot": "main_hand",
		"max_ammo": max_ammo,
		"effect_data": effect_data.duplicate(true),
	}
	if not durability.is_empty():
		profile["durability_cost"] = max(0.0, simulation._optional_float(weapon.get("durability_cost", effect_data.get("durability_cost", 1.0)), 1.0))
		profile["durability_default"] = max(0.0, simulation._optional_float(durability.get("durability", durability.get("max_durability", 100.0)), 100.0))
		profile["max_durability"] = max(1.0, simulation._optional_float(durability.get("max_durability", profile.get("durability_default", 100.0)), 100.0))
	if weapon.get("accuracy", null) != null:
		profile["accuracy"] = simulation._optional_float(weapon.get("accuracy", 0.0), 0.0)
	for key in ["armor_pierce", "armor_break_chance", "armor_break_defense_multiplier"]:
		if weapon.has(key):
			profile[key] = simulation._optional_float(weapon.get(key, 0.0), 0.0)
		elif effect_data.has(key):
			profile[key] = simulation._optional_float(effect_data.get(key, 0.0), 0.0)
	simulation._apply_attack_ammo_profile(actor, profile, items)
	return profile


func _attack_ammo_available(simulation: RefCounted, actor: RefCounted, profile: Dictionary, ammo_type: String) -> int:
	var slot_id := str(profile.get("equipment_slot", "main_hand"))
	if actor.weapon_ammo.has(slot_id):
		return max(0, int(actor.weapon_ammo.get(slot_id, 0)))
	return max(0, int(actor.inventory.get(ammo_type, 0)))


func _attack_min_range_from_options(simulation: RefCounted, options: Dictionary, profile: Dictionary) -> int:
	if options.has("min_range"):
		return max(0, int(options.get("min_range", 0)))
	if options.has("minimum_range"):
		return max(0, int(options.get("minimum_range", 0)))
	if options.has("minRange"):
		return max(0, int(options.get("minRange", 0)))
	return max(0, int(profile.get("min_range", 0)))


func _attack_command_options(simulation: RefCounted, command: Dictionary, profile: Dictionary) -> Dictionary:
	return {
		"weapon_profile": profile.duplicate(true),
		"allow_non_hostile_attack": simulation._allows_non_hostile_attack_option(command),
		"confirmation_required": bool(command.get("confirmation_required", simulation._allows_non_hostile_attack_option(command))),
		"friendly_fire_relationship_delta": float(command.get("friendly_fire_relationship_delta", command.get("non_hostile_attack_relationship_delta", -75.0))),
	}


func _weapon_min_range(simulation: RefCounted, weapon: Dictionary) -> int:
	if weapon.has("min_range"):
		return max(0, simulation._optional_int(weapon.get("min_range", 0), 0))
	if weapon.has("minimum_range"):
		return max(0, simulation._optional_int(weapon.get("minimum_range", 0), 0))
	if weapon.has("minRange"):
		return max(0, simulation._optional_int(weapon.get("minRange", 0), 0))
	return 0


func _weapon_fragment(simulation: RefCounted, item_id: String, items: Dictionary) -> Dictionary:
	var item: Dictionary = simulation._item_data_from_library(item_id, items)
	if item.is_empty():
		return {}
	for fragment in simulation._array_or_empty(item.get("fragments", [])):
		var fragment_data: Dictionary = simulation._dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "weapon":
			return fragment_data
	return {}


func _attack_ammo_check(simulation: RefCounted, actor: RefCounted, profile: Dictionary) -> Dictionary:
	var ammo_type: String = str(profile.get("ammo_type", ""))
	if ammo_type.is_empty() or ammo_type == "<null>":
		return {"success": true}
	var required: int = max(1, int(profile.get("ammo_per_attack", 1)))
	var slot_id := str(profile.get("equipment_slot", "main_hand"))
	if actor.weapon_ammo.has(slot_id):
		var loaded: int = int(actor.weapon_ammo.get(slot_id, 0))
		if loaded < required:
			return {
				"success": false,
				"reason": "magazine_empty",
				"slot_id": slot_id,
				"ammo_type": ammo_type,
				"required": required,
				"loaded": loaded,
				"capacity": int(profile.get("max_ammo", 0)),
				"inventory": int(actor.inventory.get(ammo_type, 0)),
			}
		return {"success": true}
	var current: int = int(actor.inventory.get(ammo_type, 0))
	if current < required:
		return {
			"success": false,
			"reason": "ammo_insufficient",
			"ammo_type": ammo_type,
			"required": required,
			"current": current,
		}
	return {"success": true}


func _attack_weapon_durability_check(simulation: RefCounted, actor: RefCounted, profile: Dictionary) -> Dictionary:
	var item_id := str(profile.get("item_id", "")).strip_edges()
	var cost: float = max(0.0, float(profile.get("durability_cost", 0.0)))
	if actor == null or item_id.is_empty() or cost <= 0.0:
		return {"success": true}
	var current: float = simulation._weapon_durability(actor, profile)
	if current >= cost:
		return {"success": true}
	return {
		"success": false,
		"reason": "weapon_durability_insufficient",
		"actor_id": actor.actor_id,
		"weapon_item_id": item_id,
		"slot_id": str(profile.get("equipment_slot", "main_hand")),
		"durability_before": current,
		"durability_cost": cost,
		"max_durability": float(profile.get("max_durability", max(1.0, current))),
	}


func _weapon_durability(simulation: RefCounted, actor: RefCounted, profile: Dictionary) -> float:
	if actor == null:
		return 0.0
	var item_id := str(profile.get("item_id", "")).strip_edges()
	if item_id.is_empty():
		return 0.0
	if actor.tool_durability.has(item_id):
		return max(0.0, float(actor.tool_durability.get(item_id, 0.0)))
	return max(0.0, float(profile.get("durability_default", profile.get("max_durability", 100.0))))


func _apply_attack_ammo_profile(simulation: RefCounted, actor: RefCounted, profile: Dictionary, items: Dictionary) -> void:
	var ammo_type: String = _normalize_item_id(simulation, profile.get("ammo_type", ""))
	if actor == null or ammo_type.is_empty() or ammo_type == "<null>":
		return
	var ammo_item: Dictionary = _item_data_from_library(simulation, ammo_type, items)
	if ammo_item.is_empty():
		return
	var ammo_data: Dictionary = simulation._dictionary_or_empty(ammo_item.get("ammo_data", {})).duplicate(true)
	var effect_data: Dictionary = _merged_ammo_effect_data(simulation, ammo_item, ammo_data)
	var available: int = _attack_ammo_available(simulation, actor, profile, ammo_type)
	var ammo_profile := {
		"item_id": ammo_type,
		"ammo_type": ammo_type,
		"display_name": str(ammo_item.get("name", ammo_type)),
		"available": available,
		"source": "magazine" if actor.weapon_ammo.has(str(profile.get("equipment_slot", "main_hand"))) else "inventory",
		"slot_id": str(profile.get("equipment_slot", "main_hand")),
		"ammo_data": ammo_data.duplicate(true),
		"effect_data": effect_data.duplicate(true),
	}
	var flat_bonus: float = _ammo_float(simulation, ammo_item, ammo_data, effect_data, ["damage_flat_bonus", "flat_damage_bonus", "damage_bonus_flat"], 0.0)
	var percent_bonus: float = _ammo_float(simulation, ammo_item, ammo_data, effect_data, ["damage_bonus_percent", "damage_percent_bonus", "damage_bonus"], 0.0)
	var accuracy_bonus: float = _ammo_float(simulation, ammo_item, ammo_data, effect_data, ["accuracy_bonus", "accuracy"], 0.0)
	var crit_chance_bonus: float = _ammo_float(simulation, ammo_item, ammo_data, effect_data, ["crit_chance_bonus", "crit_bonus"], 0.0)
	var crit_multiplier_bonus: float = _ammo_float(simulation, ammo_item, ammo_data, effect_data, ["crit_multiplier_bonus", "crit_damage_bonus"], 0.0)
	var armor_pierce_bonus: float = _ammo_float(simulation, ammo_item, ammo_data, effect_data, ["armor_pierce_bonus", "armor_pierce"], 0.0)
	var armor_break_chance_bonus: float = _ammo_float(simulation, ammo_item, ammo_data, effect_data, ["armor_break_chance_bonus", "armor_break_chance"], 0.0)
	var armor_break_multiplier_bonus: float = _ammo_float(simulation, ammo_item, ammo_data, effect_data, ["armor_break_defense_multiplier_bonus", "armor_break_defense_multiplier"], 0.0)
	if absf(flat_bonus) > 0.0001:
		profile["damage"] = max(0.0, float(profile.get("damage", 0.0)) + flat_bonus)
		profile["ammo_damage_flat_bonus"] = flat_bonus
		ammo_profile["damage_flat_bonus"] = flat_bonus
	if absf(percent_bonus) > 0.0001:
		profile["ammo_damage_bonus"] = percent_bonus
		ammo_profile["damage_bonus"] = percent_bonus
	if absf(accuracy_bonus) > 0.0001:
		profile["accuracy"] = float(profile.get("accuracy", 0.0)) + accuracy_bonus
		ammo_profile["accuracy_bonus"] = accuracy_bonus
	if absf(crit_chance_bonus) > 0.0001:
		profile["crit_chance"] = clampf(float(profile.get("crit_chance", 0.0)) + crit_chance_bonus, 0.0, 1.0)
		ammo_profile["crit_chance_bonus"] = crit_chance_bonus
	if absf(crit_multiplier_bonus) > 0.0001:
		profile["crit_multiplier_bonus"] = float(profile.get("crit_multiplier_bonus", 0.0)) + crit_multiplier_bonus
		ammo_profile["crit_multiplier_bonus"] = crit_multiplier_bonus
	if absf(armor_pierce_bonus) > 0.0001:
		profile["armor_pierce"] = clampf(float(profile.get("armor_pierce", 0.0)) + armor_pierce_bonus, 0.0, 1.0)
		ammo_profile["armor_pierce"] = armor_pierce_bonus
	if absf(armor_break_chance_bonus) > 0.0001:
		profile["armor_break_chance"] = clampf(float(profile.get("armor_break_chance", 0.0)) + armor_break_chance_bonus, 0.0, 1.0)
		ammo_profile["armor_break_chance"] = armor_break_chance_bonus
	if absf(armor_break_multiplier_bonus) > 0.0001:
		profile["armor_break_defense_multiplier"] = clampf(float(profile.get("armor_break_defense_multiplier", 0.0)) + armor_break_multiplier_bonus, 0.0, 1.0)
		ammo_profile["armor_break_defense_multiplier"] = armor_break_multiplier_bonus
	var ammo_effect_ids: Array[String] = _ammo_on_hit_effect_ids(simulation, ammo_item, ammo_data, effect_data)
	if not ammo_effect_ids.is_empty():
		var merged_effects: Array[String] = simulation._string_array(profile.get("on_hit_effect_ids", []))
		for effect_id in ammo_effect_ids:
			if not merged_effects.has(effect_id):
				merged_effects.append(effect_id)
		profile["on_hit_effect_ids"] = merged_effects
		ammo_profile["on_hit_effect_ids"] = ammo_effect_ids
	profile["ammo_profile"] = ammo_profile


func _merged_ammo_effect_data(simulation: RefCounted, ammo_item: Dictionary, ammo_data: Dictionary) -> Dictionary:
	var output: Dictionary = simulation._dictionary_or_empty(ammo_data.get("effect_data", {})).duplicate(true)
	for key in simulation._dictionary_or_empty(ammo_item.get("effect_data", {})).keys():
		output[str(key)] = simulation._dictionary_or_empty(ammo_item.get("effect_data", {})).get(key)
	return output


func _ammo_float(simulation: RefCounted, ammo_item: Dictionary, ammo_data: Dictionary, effect_data: Dictionary, keys: Array[String], fallback: float) -> float:
	for key in keys:
		if effect_data.has(key):
			return simulation._optional_float(effect_data.get(key), fallback)
		if ammo_data.has(key):
			return simulation._optional_float(ammo_data.get(key), fallback)
		if ammo_item.has(key):
			return simulation._optional_float(ammo_item.get(key), fallback)
	return fallback


func _ammo_on_hit_effect_ids(simulation: RefCounted, ammo_item: Dictionary, ammo_data: Dictionary, effect_data: Dictionary) -> Array[String]:
	var ids: Array[String] = simulation._string_array(effect_data.get("on_hit_effect_ids", []))
	if ids.is_empty():
		ids = simulation._string_array(ammo_data.get("on_hit_effect_ids", []))
	if ids.is_empty():
		ids = simulation._string_array(ammo_item.get("on_hit_effect_ids", []))
	if ids.is_empty():
		ids = simulation._string_array(ammo_data.get("special_effects", effect_data.get("special_effects", [])))
	return ids


func _item_durability_fragment(simulation: RefCounted, item_data: Dictionary) -> Dictionary:
	for fragment in simulation._array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = simulation._dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "durability":
			return fragment_data
	return {}


func _item_data_from_library(simulation: RefCounted, item_id: String, items: Dictionary) -> Dictionary:
	if item_id.is_empty():
		return {}
	var record: Dictionary = simulation._dictionary_or_empty(items.get(item_id, {}))
	if record.is_empty():
		return {}
	return simulation._dictionary_or_empty(record.get("data", record))


func _consume_attack_ammo(simulation: RefCounted, actor: RefCounted, profile: Dictionary) -> Dictionary:
	var ammo_type: String = str(profile.get("ammo_type", ""))
	if ammo_type.is_empty() or ammo_type == "<null>":
		return {"consumed": false}
	var count: int = max(1, int(profile.get("ammo_per_attack", 1)))
	var slot_id := str(profile.get("equipment_slot", "main_hand"))
	if actor.weapon_ammo.has(slot_id):
		actor.weapon_ammo[slot_id] = max(0, int(actor.weapon_ammo.get(slot_id, 0)) - count)
		simulation._emit("ammo_consumed", {
			"actor_id": actor.actor_id,
			"ammo_type": ammo_type,
			"count": count,
			"source": "magazine",
			"slot_id": slot_id,
			"loaded_remaining": int(actor.weapon_ammo.get(slot_id, 0)),
			"remaining": int(actor.inventory.get(ammo_type, 0)),
			"weapon_item_id": profile.get("item_id", ""),
		})
		return {
			"consumed": true,
			"source": "magazine",
			"slot_id": slot_id,
			"ammo_type": ammo_type,
			"count": count,
			"loaded_remaining": int(actor.weapon_ammo.get(slot_id, 0)),
			"remaining": int(actor.inventory.get(ammo_type, 0)),
		}
	simulation._inventory_entries.add_actor_item(actor, ammo_type, -count)
	simulation._emit("ammo_consumed", {
		"actor_id": actor.actor_id,
		"ammo_type": ammo_type,
		"count": count,
		"remaining": int(actor.inventory.get(ammo_type, 0)),
		"weapon_item_id": profile.get("item_id", ""),
	})
	return {
		"consumed": true,
		"ammo_type": ammo_type,
		"count": count,
		"remaining": int(actor.inventory.get(ammo_type, 0)),
	}


func _consume_attack_weapon_durability(simulation: RefCounted, actor: RefCounted, profile: Dictionary) -> Dictionary:
	var item_id := str(profile.get("item_id", "")).strip_edges()
	var cost: float = max(0.0, float(profile.get("durability_cost", 0.0)))
	if actor == null or item_id.is_empty() or cost <= 0.0:
		return {"consumed": false}
	var before: float = simulation._weapon_durability(actor, profile)
	if before < cost:
		return {
			"consumed": false,
			"reason": "weapon_durability_insufficient",
			"weapon_item_id": item_id,
			"durability_before": before,
			"durability_cost": cost,
		}
	var after: float = max(0.0, before - cost)
	actor.tool_durability[item_id] = after
	var payload := {
		"actor_id": actor.actor_id,
		"weapon_item_id": item_id,
		"slot_id": str(profile.get("equipment_slot", "main_hand")),
		"durability_cost": cost,
		"durability_before": before,
		"durability_after": after,
		"max_durability": float(profile.get("max_durability", max(1.0, before))),
	}
	simulation._emit("weapon_durability_consumed", payload.duplicate(true))
	var result: Dictionary = payload.duplicate(true)
	result["consumed"] = true
	return result


func _normalize_item_id(_simulation: RefCounted, value: Variant) -> String:
	if value == null:
		return ""
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	if typeof(value) == TYPE_INT:
		return str(value)
	var text := str(value).strip_edges()
	return "" if text == "<null>" else text
