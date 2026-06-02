extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const SettlementLifeRules = preload("res://scripts/core/ai/settlement_life_rules.gd")

var _settlement_life_rules := SettlementLifeRules.new()


func decide_actor_intent(actor: RefCounted, actors: Array, context: Dictionary = {}) -> Dictionary:
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	if actor.kind == "enemy" or actor.side == "hostile":
		return _hostile_intent(actor, actors)
	if not _dictionary_or_empty(actor.life).is_empty():
		return _settlement_life_rules.decide_intent(actor, context)
	return _idle_intent(actor, "no_ai_profile")


func _hostile_intent(actor: RefCounted, actors: Array) -> Dictionary:
	var ai: Dictionary = _dictionary_or_empty(actor.ai)
	var aggro_range: float = max(0.0, float(ai.get("aggro_range", 8.0)))
	var attack_range: float = max(0.0, float(ai.get("attack_range", 1.0)))
	var target: RefCounted = _nearest_target(actor, actors, aggro_range)
	if target == null:
		return _idle_intent(actor, "no_target_in_aggro_range")

	var distance: float = _grid_distance(actor.grid_position, target.grid_position)
	if distance <= attack_range:
		return {
			"success": true,
			"actor_id": actor.actor_id,
			"intent": "attack",
			"target_actor_id": target.actor_id,
			"distance": distance,
			"attack_range": attack_range,
		}
	return {
		"success": true,
		"actor_id": actor.actor_id,
		"intent": "approach",
		"target_actor_id": target.actor_id,
		"target_grid": target.grid_position.to_dictionary(),
		"distance": distance,
		"aggro_range": aggro_range,
	}


func _nearest_target(actor: RefCounted, actors: Array, aggro_range: float) -> RefCounted:
	var best_target: RefCounted = null
	var best_distance: float = INF
	for candidate in actors:
		if candidate == null or candidate.actor_id == actor.actor_id:
			continue
		if _same_side(actor, candidate):
			continue
		if actor.side != "hostile" and candidate.side != "hostile":
			continue
		var distance: float = _grid_distance(actor.grid_position, candidate.grid_position)
		if distance <= aggro_range and distance < best_distance:
			best_distance = distance
			best_target = candidate
	return best_target


func _same_side(left: RefCounted, right: RefCounted) -> bool:
	if left.side == right.side:
		return true
	return not left.group_id.is_empty() and left.group_id == right.group_id


func _grid_distance(left: RefCounted, right: RefCounted) -> float:
	if left == null or right == null or left.y != right.y:
		return INF
	var dx: float = float(left.x - right.x)
	var dz: float = float(left.z - right.z)
	return sqrt(dx * dx + dz * dz)


func _idle_intent(actor: RefCounted, reason: String) -> Dictionary:
	return {
		"success": true,
		"actor_id": actor.actor_id if actor != null else 0,
		"intent": "idle",
		"reason": reason,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
