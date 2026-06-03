extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const VisionGeometry = preload("res://scripts/core/vision/vision_geometry.gd")

var _inventory_entries := InventoryEntries.new()
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
	var critical_roll: Dictionary = _critical_hit(simulation, attacker, target, profile)
	var critical: bool = bool(critical_roll.get("critical", false))
	var damage: float = _resolve_damage(attacker, target, profile, critical)
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
		"combat_rng_seed": int(simulation.combat_state.get("combat_rng_seed", 0)),
		"combat_rng_counter": int(critical_roll.get("counter", int(simulation.combat_state.get("combat_rng_counter", 0)))),
		"combat_rng_salt": int(critical_roll.get("salt", 0)),
	})

	var defeated: bool = target.hp <= 0.0
	if defeated:
		_defeat_actor(simulation, actor_id, target_actor_id, target)

	return {
		"success": true,
		"damage": damage,
		"defeated": defeated,
		"target_actor_id": target_actor_id,
		"critical": critical,
		"crit_roll": float(critical_roll.get("roll", 1.0)),
		"crit_chance": float(critical_roll.get("chance", 0.0)),
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
			"attacker_side": attacker.side,
			"target_side": target.side,
			"target_actor_id": target_actor_id,
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
	if attacker.grid_position.y != target.grid_position.y:
		return {
			"success": false,
			"reason": "target_invalid_level",
			"attacker_grid": attacker.grid_position.to_dictionary(),
			"target_grid": target.grid_position.to_dictionary(),
		}
	var distance: int = abs(attacker.grid_position.x - target.grid_position.x) + abs(attacker.grid_position.z - target.grid_position.z)
	var resolved_range: int = max(1, attack_range)
	if distance > resolved_range:
		return {
			"success": false,
			"reason": "target_out_of_range",
			"distance": distance,
			"range": resolved_range,
		}
	if not topology.is_empty() and not _vision_geometry.has_line_of_sight(attacker.grid_position.to_dictionary(), target.grid_position.to_dictionary(), topology):
		return {
			"success": false,
			"reason": "target_blocked_by_los",
			"attacker_grid": attacker.grid_position.to_dictionary(),
			"target_grid": target.grid_position.to_dictionary(),
		}
	return {"success": true}


func _resolve_damage(attacker: RefCounted, target: RefCounted, profile: Dictionary, critical: bool) -> float:
	var base_damage: float = float(profile.get("damage", attacker.attack_power))
	var multiplier: float = float(profile.get("crit_multiplier", 1.0)) if critical else 1.0
	return max(1.0, base_damage * multiplier - target.defense)


func _critical_hit(simulation: RefCounted, attacker: RefCounted, target: RefCounted, profile: Dictionary) -> Dictionary:
	var chance: float = clampf(float(profile.get("crit_chance", 0.0)), 0.0, 1.0)
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
	var corpse: Dictionary = _create_corpse_container(simulation, target)
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


func _create_corpse_container(simulation: RefCounted, target: RefCounted) -> Dictionary:
	var corpse_id: String = "corpse_%s_%d" % [target.definition_id, target.actor_id]
	var inventory: Array[Dictionary] = _actor_inventory_entries(target)
	var corpse := {
		"container_id": corpse_id,
		"map_id": target.map_id,
		"grid_position": target.grid_position.to_dictionary(),
		"display_name": "%s的遗留物" % target.display_name,
		"source_actor_definition_id": target.definition_id,
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
	}
	return corpse


func _actor_inventory_entries(actor: RefCounted) -> Array[Dictionary]:
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
	return entries


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
