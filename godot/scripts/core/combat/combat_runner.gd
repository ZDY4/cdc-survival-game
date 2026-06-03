extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const VisionGeometry = preload("res://scripts/core/vision/vision_geometry.gd")

var _inventory_entries := InventoryEntries.new()
var _vision_geometry := VisionGeometry.new()


func perform_attack(simulation: RefCounted, actor_id: int, target_actor_id: int, topology: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var attacker: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var target: RefCounted = simulation.actor_registry.get_actor(target_actor_id)
	if attacker == null:
		return {"success": false, "reason": "unknown_attacker"}
	if target == null:
		return {"success": false, "reason": "unknown_target"}
	if not _can_attack(attacker, target):
		return {"success": false, "reason": "target_not_hostile"}
	var spatial_check: Dictionary = _spatial_check(attacker, target, topology, int(options.get("range", 1)))
	if not bool(spatial_check.get("success", false)):
		return spatial_check

	var profile: Dictionary = _dictionary_or_empty(options.get("weapon_profile", {}))
	var critical: bool = _critical_hit(attacker, target, profile)
	var damage: float = _resolve_damage(attacker, target, profile, critical)
	target.hp = max(0.0, target.hp - damage)
	simulation.emit_event("attack_performed", {
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"damage": damage,
		"target_hp": target.hp,
		"weapon_item_id": profile.get("item_id", ""),
		"critical": critical,
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
		"weapon_profile": profile,
	}


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


func _critical_hit(attacker: RefCounted, target: RefCounted, profile: Dictionary) -> bool:
	var chance: float = clampf(float(profile.get("crit_chance", 0.0)), 0.0, 1.0)
	if chance <= 0.0:
		return false
	var seed_value: int = int(attacker.actor_id * 1103515245 + target.actor_id * 12345 + int(attacker.ap * 100.0))
	var roll: float = float(abs(seed_value) % 10000) / 10000.0
	return roll < chance


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
