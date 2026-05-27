extends RefCounted


func perform_attack(simulation: RefCounted, actor_id: int, target_actor_id: int) -> Dictionary:
	var attacker: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var target: RefCounted = simulation.actor_registry.get_actor(target_actor_id)
	if attacker == null:
		return {"success": false, "reason": "unknown_attacker"}
	if target == null:
		return {"success": false, "reason": "unknown_target"}
	if not _can_attack(attacker, target):
		return {"success": false, "reason": "target_not_hostile"}

	var damage: float = _resolve_damage(attacker, target)
	target.hp = max(0.0, target.hp - damage)
	simulation.emit_event("attack_performed", {
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"damage": damage,
		"target_hp": target.hp,
	})

	var defeated: bool = target.hp <= 0.0
	if defeated:
		_defeat_actor(simulation, actor_id, target_actor_id, target)

	return {
		"success": true,
		"damage": damage,
		"defeated": defeated,
		"target_actor_id": target_actor_id,
	}


func _can_attack(attacker: RefCounted, target: RefCounted) -> bool:
	return target.side == "hostile" or attacker.side == "hostile"


func _resolve_damage(attacker: RefCounted, target: RefCounted) -> float:
	return max(1.0, attacker.attack_power - target.defense)


func _defeat_actor(simulation: RefCounted, actor_id: int, target_actor_id: int, target: RefCounted) -> void:
	var defeated_definition_id: String = target.definition_id
	var defeated_kind: String = target.kind
	var defeated_xp_reward: int = target.xp_reward
	simulation.actor_registry.unregister_actor(target_actor_id)
	simulation.emit_event("actor_defeated", {
		"actor_id": target_actor_id,
		"definition_id": defeated_definition_id,
		"kind": defeated_kind,
		"defeated_by": actor_id,
	})
	simulation.grant_experience(actor_id, defeated_xp_reward, "kill:%s" % defeated_definition_id)
	simulation.record_enemy_defeated(actor_id, defeated_definition_id, defeated_kind)
