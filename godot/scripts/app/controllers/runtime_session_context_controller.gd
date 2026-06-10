extends RefCounted

const TradeSnapshot = preload("res://scripts/ui/snapshots/trade_snapshot.gd")


func dialogue_trade_target(result: Dictionary, current_target: Dictionary) -> Dictionary:
	var shop_id := dialogue_trade_shop_id(result)
	if not shop_id.is_empty():
		return {
			"target_type": "shop",
			"shop_id": shop_id,
		}
	if current_target.get("target_type", "") == "actor":
		return current_target.duplicate(true)
	return {
		"target_type": "shop",
	}


func active_trade_target_available(registry: RefCounted, simulation: RefCounted, target: Dictionary) -> bool:
	if target.is_empty() or simulation == null:
		return true
	if str(target.get("target_type", "")) == "shop" and not str(target.get("shop_id", "")).is_empty():
		return registry != null and registry.get_library("shops").has(str(target.get("shop_id", "")))
	if str(target.get("target_type", "")) != "actor":
		return true
	var actor_id := int(target.get("actor_id", 0))
	if actor_id <= 0:
		return false
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return false
	if not str(actor.map_id).is_empty() and not simulation.active_map_id.is_empty() and str(actor.map_id) != simulation.active_map_id:
		return false
	var shop_id := "%s_shop" % actor.definition_id
	return registry != null and registry.get_library("shops").has(shop_id)


func dialogue_trade_shop_id(result: Dictionary) -> String:
	for action in array_or_empty(result.get("emitted_actions", [])):
		var action_data: Dictionary = dictionary_or_empty(action)
		if str(action_data.get("type", "")) != "open_trade":
			continue
		var shop_id := str(action_data.get("shop_id", "")).strip_edges()
		if not shop_id.is_empty():
			return shop_id
	return ""


func active_shop_id(registry: RefCounted, simulation: RefCounted, target: Dictionary) -> String:
	if registry == null or simulation == null:
		return ""
	var session: Dictionary = TradeSnapshot.new(registry).resolve_trade_session(simulation.snapshot(), target)
	return str(session.get("shop_id", ""))


func trade_closed_payload(registry: RefCounted, simulation: RefCounted, target: Dictionary, reason: String) -> Dictionary:
	var payload := {
		"actor_id": 1,
		"reason": reason,
		"target_type": str(target.get("target_type", "")),
		"target_actor_id": int(target.get("actor_id", 0)),
	}
	if registry != null and simulation != null:
		var session: Dictionary = TradeSnapshot.new(registry).resolve_trade_session(simulation.snapshot(), target)
		payload["shop_id"] = str(session.get("shop_id", ""))
		payload["target_name"] = str(session.get("target_name", ""))
	return payload


func active_container_id(simulation: RefCounted) -> String:
	if simulation == null:
		return ""
	var snapshot: Dictionary = simulation.snapshot()
	for actor in array_or_empty(snapshot.get("actors", [])):
		var actor_data: Dictionary = dictionary_or_empty(actor)
		if actor_data.get("kind", "") == "player":
			return str(actor_data.get("active_container_id", ""))
	return ""


func active_container_close_reason(simulation: RefCounted) -> String:
	var container_id := active_container_id(simulation)
	if container_id.is_empty() or simulation == null:
		return ""
	if not simulation.container_sessions.has(container_id):
		return "target_unavailable"
	if not active_container_in_range(simulation, container_id):
		return "out_of_range"
	return ""


func active_container_in_range(simulation: RefCounted, container_id: String) -> bool:
	if simulation == null:
		return true
	var target: Dictionary = dictionary_or_empty(simulation.map_interaction_targets.get(container_id, {}))
	if target.is_empty():
		return true
	var actor: RefCounted = simulation.actor_registry.get_actor(1)
	if actor == null or actor.grid_position == null:
		return true
	var actor_grid: Dictionary = actor.grid_position.to_dictionary()
	for cell in array_or_empty(target.get("cells", [])):
		if grid_distance(actor_grid, dictionary_or_empty(cell)) <= 1:
			return true
	if grid_distance(actor_grid, dictionary_or_empty(target.get("anchor", {}))) <= 1:
		return true
	return false


func grid_distance(left: Dictionary, right: Dictionary) -> int:
	if left.is_empty() or right.is_empty() or int(left.get("y", 0)) != int(right.get("y", 0)):
		return 999999
	return abs(int(left.get("x", 0)) - int(right.get("x", 0))) + abs(int(left.get("z", 0)) - int(right.get("z", 0)))


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
