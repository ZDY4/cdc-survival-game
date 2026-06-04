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
	var target_check: Dictionary = validate_attack_target(simulation, actor_id, target_actor_id)
	if not bool(target_check.get("success", false)):
		return target_check
	var spatial_check: Dictionary = _spatial_check(attacker, target, topology, int(options.get("range", 1)))
	if not bool(spatial_check.get("success", false)):
		return spatial_check

	var profile: Dictionary = _dictionary_or_empty(options.get("weapon_profile", {}))
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
		"combat_rng_seed": int(simulation.combat_state.get("combat_rng_seed", 0)),
		"combat_rng_counter": int(critical_roll.get("counter", int(simulation.combat_state.get("combat_rng_counter", 0)))),
		"combat_rng_salt": int(critical_roll.get("salt", 0)),
	})

	var defeated: bool = target.hp <= 0.0
	if defeated:
		_defeat_actor(simulation, actor_id, target_actor_id, target)

	return {
		"success": true,
		"actor_id": actor_id,
		"damage": damage,
		"defeated": defeated,
		"target_actor_id": target_actor_id,
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
		"weapon_profile": profile,
	}


func validate_attack_target(simulation: RefCounted, actor_id: int, target_actor_id: int) -> Dictionary:
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
	if not _can_attack(attacker, target):
		return {
			"success": false,
			"reason": "target_not_hostile",
			"actor_id": actor_id,
			"attacker_side": attacker.side,
			"target_side": target.side,
			"target_actor_id": target_actor_id,
		}
	if simulation.has_method("is_actor_visible_to_actor") and not bool(simulation.call("is_actor_visible_to_actor", actor_id, target_actor_id)):
		return {
			"success": false,
			"reason": "target_not_visible",
			"actor_id": actor_id,
			"target_actor_id": target_actor_id,
			"attacker_grid": attacker.grid_position.to_dictionary(),
			"target_grid": target.grid_position.to_dictionary(),
		}
	return {"success": true}


func _can_attack(attacker: RefCounted, target: RefCounted) -> bool:
	if attacker.actor_id == target.actor_id:
		return false
	if attacker.side == "hostile":
		return target.side != "hostile"
	if target.side == "hostile":
		return attacker.side != "hostile"
	return false


func _spatial_check(attacker: RefCounted, target: RefCounted, topology: Dictionary, attack_range: int) -> Dictionary:
	var distance: int = abs(attacker.grid_position.x - target.grid_position.x) + abs(attacker.grid_position.z - target.grid_position.z)
	var resolved_range: int = max(1, attack_range)
	if attacker.grid_position.y != target.grid_position.y:
		return {
			"success": false,
			"reason": "target_invalid_level",
			"actor_id": attacker.actor_id,
			"target_actor_id": target.actor_id,
			"attacker_grid": attacker.grid_position.to_dictionary(),
			"target_grid": target.grid_position.to_dictionary(),
			"distance": distance,
			"range": resolved_range,
		}
	if distance > resolved_range:
		return {
			"success": false,
			"reason": "target_out_of_range",
			"actor_id": attacker.actor_id,
			"target_actor_id": target.actor_id,
			"attacker_grid": attacker.grid_position.to_dictionary(),
			"target_grid": target.grid_position.to_dictionary(),
			"distance": distance,
			"range": resolved_range,
		}
	if not topology.is_empty() and not _vision_geometry.has_line_of_sight(attacker.grid_position.to_dictionary(), target.grid_position.to_dictionary(), topology):
		return {
			"success": false,
			"reason": "target_blocked_by_los",
			"actor_id": attacker.actor_id,
			"target_actor_id": target.actor_id,
			"attacker_grid": attacker.grid_position.to_dictionary(),
			"target_grid": target.grid_position.to_dictionary(),
			"distance": distance,
			"range": resolved_range,
		}
	return {"success": true}


func _triggered_on_hit_effect_ids(profile: Dictionary, damage_result: Dictionary) -> Array[String]:
	var hit_kind: String = str(damage_result.get("hit_kind", "hit"))
	if not ["hit", "crit"].has(hit_kind):
		return []
	return _string_array(profile.get("on_hit_effect_ids", []))


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


func _miss_damage_result(simulation: RefCounted, target: RefCounted, hit_roll: Dictionary) -> Dictionary:
	return {
		"damage": 0.0,
		"hit_kind": "miss",
		"defense": max(0.0, _combat_attribute(simulation, target, "defense", target.defense)),
		"damage_reduction": clampf(_combat_attribute(simulation, target, "damage_reduction", 0.0), 0.0, 0.95),
		"damage_bonus": 0.0,
		"hit_chance": float(hit_roll.get("chance", 0.0)),
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
	var inventory: Array[Dictionary] = _actor_inventory_entries(target, simulation.item_library)
	var corpse := {
		"container_id": corpse_id,
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
		"display_name": corpse.get("display_name", corpse_id),
		"inventory": inventory.duplicate(true),
	}
	simulation.map_interaction_targets[corpse_id] = {
		"target_id": corpse_id,
		"target_type": "map_object",
		"display_name": corpse.get("display_name", corpse_id),
		"kind": "container",
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


func _actor_inventory_entries(actor: RefCounted, item_library: Dictionary) -> Array[Dictionary]:
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
	for loot_entry in actor.loot_table:
		var loot_data: Dictionary = _dictionary_or_empty(loot_entry)
		var item_id: String = _normalize_item_id(loot_data.get("item_id", loot_data.get("itemId", "")))
		var count: int = _resolve_loot_drop_count(actor.actor_id, item_id, loot_data)
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


func _resolve_loot_drop_count(actor_id: int, item_id: String, entry: Dictionary) -> int:
	if item_id.is_empty():
		return 0
	var min_count: int = int(entry.get("min", 0))
	var max_count: int = int(entry.get("max", 0))
	var chance: float = clampf(float(entry.get("chance", 0.0)), 0.0, 1.0)
	if max_count < min_count or max_count <= 0 or chance <= 0.0:
		return 0
	var item_number: int = abs(hash(item_id))
	var roll_seed: int = abs(actor_id ^ (item_number * 1103515245))
	var chance_roll: float = float(roll_seed % 10000) / 10000.0
	if chance_roll > chance:
		return 0
	var span: int = max_count - min_count
	var count_roll: int = int((roll_seed / 97) % (span + 1)) if span > 0 else 0
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
