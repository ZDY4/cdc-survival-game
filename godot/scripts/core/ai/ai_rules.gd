extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const SettlementLifeRules = preload("res://scripts/core/ai/settlement_life_rules.gd")
const VisionGeometry = preload("res://scripts/core/vision/vision_geometry.gd")

var _settlement_life_rules := SettlementLifeRules.new()
var _vision_geometry := VisionGeometry.new()


func decide_actor_intent(actor: RefCounted, actors: Array, context: Dictionary = {}) -> Dictionary:
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	if actor.kind == "enemy" or actor.side == "hostile":
		return _hostile_intent(actor, actors, context)
	if not _dictionary_or_empty(actor.life).is_empty():
		return _settlement_life_rules.decide_intent(actor, context)
	return _idle_intent(actor, "no_ai_profile")


func _hostile_intent(actor: RefCounted, actors: Array, context: Dictionary) -> Dictionary:
	var ai: Dictionary = _dictionary_or_empty(actor.ai)
	var aggro_range: float = max(0.0, float(ai.get("aggro_range", 8.0)))
	var weapon: Dictionary = _dictionary_or_empty(context.get("weapon_profile", {}))
	var attack_range: float = _hostile_attack_range(ai, weapon)
	var target_result: Dictionary = _nearest_target(actor, actors, aggro_range, context)
	var target: RefCounted = target_result.get("actor")
	if target == null:
		var idle: Dictionary = _idle_intent(actor, str(target_result.get("reason", "no_target_in_aggro_range")))
		idle["aggro_range"] = aggro_range
		idle["attack_range"] = attack_range
		idle["ap"] = float(actor.ap)
		idle.merge(_weapon_debug_payload(weapon), true)
		idle["candidate_count"] = int(target_result.get("candidate_count", 0))
		idle["blocked_by_los_count"] = int(target_result.get("blocked_by_los_count", 0))
		return idle

	var distance: float = _grid_distance(actor.grid_position, target.grid_position)
	if distance <= attack_range:
		if bool(weapon.get("can_reload", false)):
			return _reload_intent(actor, target, distance, aggro_range, attack_range, weapon)
		if not bool(weapon.get("ammo_ready", true)):
			var no_ammo: Dictionary = _idle_intent(actor, "weapon_ammo_unavailable")
			no_ammo["target_actor_id"] = target.actor_id
			no_ammo["target_grid"] = target.grid_position.to_dictionary()
			no_ammo["distance"] = distance
			no_ammo["aggro_range"] = aggro_range
			no_ammo["attack_range"] = attack_range
			no_ammo["ap"] = float(actor.ap)
			no_ammo.merge(_weapon_debug_payload(weapon), true)
			return no_ammo
		return {
			"success": true,
			"actor_id": actor.actor_id,
			"intent": "attack",
			"target_actor_id": target.actor_id,
			"target_grid": target.grid_position.to_dictionary(),
			"distance": distance,
			"aggro_range": aggro_range,
			"attack_range": attack_range,
			"ap": float(actor.ap),
			"reason": "target_in_attack_range",
		}.merged(_weapon_debug_payload(weapon), true)
	if _weapon_needs_ammo(weapon) and not bool(weapon.get("ammo_ready", true)) and not bool(weapon.get("can_reload", false)):
		var blocked: Dictionary = _idle_intent(actor, "weapon_ammo_unavailable")
		blocked["target_actor_id"] = target.actor_id
		blocked["target_grid"] = target.grid_position.to_dictionary()
		blocked["distance"] = distance
		blocked["aggro_range"] = aggro_range
		blocked["attack_range"] = attack_range
		blocked["ap"] = float(actor.ap)
		blocked.merge(_weapon_debug_payload(weapon), true)
		return blocked
	return {
		"success": true,
		"actor_id": actor.actor_id,
		"intent": "approach",
		"target_actor_id": target.actor_id,
		"target_grid": target.grid_position.to_dictionary(),
		"distance": distance,
		"aggro_range": aggro_range,
		"attack_range": attack_range,
		"ap": float(actor.ap),
		"reason": "target_in_aggro_range",
	}.merged(_weapon_debug_payload(weapon), true)


func _reload_intent(actor: RefCounted, target: RefCounted, distance: float, aggro_range: float, attack_range: float, weapon: Dictionary) -> Dictionary:
	var intent := {
		"success": true,
		"actor_id": actor.actor_id,
		"intent": "reload",
		"target_actor_id": target.actor_id,
		"target_grid": target.grid_position.to_dictionary(),
		"distance": distance,
		"aggro_range": aggro_range,
		"attack_range": attack_range,
		"ap": float(actor.ap),
		"reason": "weapon_magazine_empty",
	}
	intent.merge(_weapon_debug_payload(weapon), true)
	return intent


func _hostile_attack_range(ai: Dictionary, weapon: Dictionary) -> float:
	if weapon.has("attack_range"):
		return max(0.0, float(weapon.get("attack_range", 1.0)))
	if weapon.has("range"):
		return max(0.0, float(weapon.get("range", 1.0)))
	return max(0.0, float(ai.get("attack_range", 1.0)))


func _weapon_debug_payload(weapon: Dictionary) -> Dictionary:
	if weapon.is_empty():
		return {}
	return {
		"weapon_item_id": str(weapon.get("item_id", "")),
		"weapon_slot_id": str(weapon.get("slot_id", "")),
		"ammo_type": str(weapon.get("ammo_type", "")),
		"ammo_ready": bool(weapon.get("ammo_ready", true)),
		"can_reload": bool(weapon.get("can_reload", false)),
		"loaded": int(weapon.get("loaded", 0)),
		"capacity": int(weapon.get("capacity", 0)),
		"inventory_ammo": int(weapon.get("inventory", 0)),
		"ap_cost": float(weapon.get("ap_cost", 0.0)),
	}


func _weapon_needs_ammo(weapon: Dictionary) -> bool:
	var ammo_type: String = str(weapon.get("ammo_type", ""))
	return not ammo_type.is_empty() and ammo_type != "<null>"


func _nearest_target(actor: RefCounted, actors: Array, aggro_range: float, context: Dictionary) -> Dictionary:
	var best_target: RefCounted = null
	var best_distance: float = INF
	var candidate_count: int = 0
	var blocked_by_los_count: int = 0
	for candidate in actors:
		if candidate == null or candidate.actor_id == actor.actor_id:
			continue
		if candidate.hp <= 0.0:
			continue
		if not _same_active_map(actor, candidate, str(context.get("active_map_id", ""))):
			continue
		if _same_side(actor, candidate):
			continue
		if actor.side != "hostile" and candidate.side != "hostile":
			continue
		var distance: float = _grid_distance(actor.grid_position, candidate.grid_position)
		if distance > aggro_range:
			continue
		candidate_count += 1
		if not _has_line_of_sight(actor, candidate, _dictionary_or_empty(context.get("topology", {}))):
			blocked_by_los_count += 1
			continue
		if distance < best_distance:
			best_distance = distance
			best_target = candidate
	if best_target == null:
		return {
			"actor": null,
			"candidate_count": candidate_count,
			"blocked_by_los_count": blocked_by_los_count,
			"reason": "target_blocked_by_los" if candidate_count > 0 and blocked_by_los_count >= candidate_count else "no_target_in_aggro_range",
		}
	return {
		"actor": best_target,
		"candidate_count": candidate_count,
		"blocked_by_los_count": blocked_by_los_count,
		"reason": "target_visible",
	}


func _same_active_map(actor: RefCounted, candidate: RefCounted, active_map_id: String) -> bool:
	if actor.map_id.is_empty() or candidate.map_id.is_empty():
		return true
	if not active_map_id.is_empty() and actor.map_id != active_map_id:
		return false
	return actor.map_id == candidate.map_id


func _has_line_of_sight(actor: RefCounted, target: RefCounted, topology: Dictionary) -> bool:
	if actor.grid_position.y != target.grid_position.y:
		return false
	if topology.is_empty():
		return true
	return _vision_geometry.has_line_of_sight(actor.grid_position.to_dictionary(), target.grid_position.to_dictionary(), topology)


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
