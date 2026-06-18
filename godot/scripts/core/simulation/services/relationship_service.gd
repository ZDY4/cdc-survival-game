extends RefCounted

## 关系与敌对评分服务：维护 actor 间关系分数、默认关系和敌对判定。
## 无状态规则计算；relationships 字典仍由 simulation 持有。


func actor_hostility(simulation: RefCounted, actor_id: int, target_actor_id: int) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var target: RefCounted = simulation.actor_registry.get_actor(target_actor_id)
	if actor == null or target == null:
		return {"hostile": false, "reason": "unknown_actor_pair", "score": 0.0}
	if actor.actor_id == target.actor_id:
		return {"hostile": false, "reason": "self", "score": 100.0}
	var score: float = relationship_score(simulation, actor.actor_id, target.actor_id)
	var same_group: bool = actors_share_side_or_group(simulation, actor, target)
	var side_hostile: bool = actor.side == "hostile" or target.side == "hostile"
	var hostile: bool = false
	var reason: String = "neutral"
	if score <= simulation.RELATIONSHIP_HOSTILE_THRESHOLD:
		hostile = true
		reason = "relationship_hostile"
	elif side_hostile and score < simulation.RELATIONSHIP_FRIENDLY_THRESHOLD:
		hostile = true
		reason = "side_hostile"
	elif same_group:
		hostile = false
		reason = "same_group"
	else:
		hostile = false
		reason = "relationship_non_hostile" if score >= simulation.RELATIONSHIP_FRIENDLY_THRESHOLD else "neutral"
	return {
		"hostile": hostile,
		"reason": reason,
		"score": score,
		"threshold": simulation.RELATIONSHIP_HOSTILE_THRESHOLD,
		"actor_side": actor.side,
		"target_side": target.side,
		"actor_group_id": actor.group_id,
		"target_group_id": target.group_id,
	}


func are_actors_hostile(simulation: RefCounted, actor_id: int, target_actor_id: int) -> bool:
	return bool(actor_hostility(simulation, actor_id, target_actor_id).get("hostile", false))


func relationship_score(simulation: RefCounted, actor_id: int, target_actor_id: int) -> float:
	if actor_id <= 0 or target_actor_id <= 0:
		return 0.0
	if actor_id == target_actor_id:
		return 100.0
	var key: String = relationship_key(simulation, actor_id, target_actor_id)
	if simulation.relationships.has(key):
		return float(simulation.relationships.get(key, 0.0))
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var target_actor: RefCounted = simulation.actor_registry.get_actor(target_actor_id)
	return default_relationship_score(simulation, actor, target_actor)


func set_relationship_score(simulation: RefCounted, actor_id: int, target_actor_id: int, score: float, reason: String = "manual") -> Dictionary:
	if actor_id <= 0 or target_actor_id <= 0:
		return {"success": false, "reason": "invalid_actor_pair", "actor_id": actor_id, "target_actor_id": target_actor_id}
	if actor_id == target_actor_id:
		return {"success": false, "reason": "self_relationship_locked", "actor_id": actor_id, "target_actor_id": target_actor_id}
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var target_actor: RefCounted = simulation.actor_registry.get_actor(target_actor_id)
	if actor == null or target_actor == null:
		return {"success": false, "reason": "unknown_actor_pair", "actor_id": actor_id, "target_actor_id": target_actor_id}
	var previous: float = relationship_score(simulation, actor_id, target_actor_id)
	var clamped: float = clampf(score, -100.0, 100.0)
	var key: String = relationship_key(simulation, actor_id, target_actor_id)
	simulation.relationships[key] = clamped
	var changed: bool = absf(previous - clamped) > 0.001
	var left_actor: RefCounted = actor if actor.actor_id <= target_actor.actor_id else target_actor
	var right_actor: RefCounted = target_actor if actor.actor_id <= target_actor.actor_id else actor
	if changed:
		simulation._emit("relationship_changed", {
			"actor_id": left_actor.actor_id,
			"target_actor_id": right_actor.actor_id,
			"actor_name": left_actor.display_name,
			"target_actor_name": right_actor.display_name,
			"score_before": previous,
			"score": clamped,
			"score_delta": clamped - previous,
			"reason": reason,
			"actor_side": left_actor.side,
			"target_side": right_actor.side,
		})
	return {
		"success": true,
		"actor_id": left_actor.actor_id,
		"target_actor_id": right_actor.actor_id,
		"actor_name": left_actor.display_name,
		"target_actor_name": right_actor.display_name,
		"score_before": previous,
		"score": clamped,
		"score_delta": clamped - previous,
		"previous": previous,
		"changed": changed,
		"reason": reason,
	}


func initialize_relationships_for_actor(simulation: RefCounted, actor: RefCounted) -> void:
	if actor == null:
		return
	for other in simulation.actor_registry.actors():
		if other == null or other.actor_id == actor.actor_id:
			continue
		var key: String = relationship_key(simulation, actor.actor_id, other.actor_id)
		if simulation.relationships.has(key):
			continue
		simulation.relationships[key] = default_relationship_score(simulation, actor, other)


func relationship_key(_simulation: RefCounted, actor_id: int, target_actor_id: int) -> String:
	var left: int = min(actor_id, target_actor_id)
	var right: int = max(actor_id, target_actor_id)
	return "%d:%d" % [left, right]


func actors_share_side_or_group(_simulation: RefCounted, actor: RefCounted, target_actor: RefCounted) -> bool:
	if actor == null or target_actor == null:
		return false
	if not actor.group_id.is_empty() and actor.group_id == target_actor.group_id:
		return true
	return not actor.side.is_empty() and actor.side == target_actor.side


func default_relationship_score(_simulation: RefCounted, actor: RefCounted, target_actor: RefCounted) -> float:
	if actor == null or target_actor == null:
		return 0.0
	if actor.actor_id == target_actor.actor_id:
		return 100.0
	if actor.side == "hostile" or target_actor.side == "hostile":
		if actor.side == target_actor.side:
			return 50.0
		return -100.0
	if actor.side == target_actor.side and actor.group_id == target_actor.group_id and not actor.group_id.is_empty():
		return 75.0
	if actor.side == target_actor.side and actor.side != "neutral":
		return 50.0
	if actor.side == "player" and target_actor.side == "friendly":
		return 50.0
	if actor.side == "friendly" and target_actor.side == "player":
		return 50.0
	return 0.0
