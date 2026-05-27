extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")


func _init() -> void:
	var registry := ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		for error in load_result.errors:
			printerr(error)
		quit(1)
		return

	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var simulation: RefCounted = runtime_result.get("simulation")
	var errors := _run_interaction_checks(simulation)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("interaction_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_interaction_checks(simulation: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var pickup_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_pickup_medkit",
	})
	if not bool(pickup_result.get("success", false)):
		errors.append("pickup failed: %s" % pickup_result.get("reason", "unknown"))
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if int(player.inventory.get("1006", 0)) <= 0:
		errors.append("pickup did not add item 1006 to player inventory")
	var second_pickup: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_pickup_medkit",
	})
	if bool(second_pickup.get("success", false)):
		errors.append("pickup target was not consumed")

	var talk_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "actor",
		"actor_id": 2,
	})
	if not bool(talk_result.get("success", false)):
		errors.append("talk failed: %s" % talk_result.get("reason", "unknown"))
	if talk_result.get("dialogue_id", "") != "trader_lao_wang":
		errors.append("talk did not resolve trader_lao_wang dialogue")

	var container_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_clinic_supply_cabinet",
	})
	if not bool(container_result.get("success", false)):
		errors.append("container open failed: %s" % container_result.get("reason", "unknown"))
	var container: Dictionary = container_result.get("container", {})
	if container.get("container_id", "") != "survivor_outpost_01_clinic_supply_cabinet":
		errors.append("container result used wrong id")
	if container.get("inventory", []).size() != 2:
		errors.append("container inventory did not expose initial entries")
	if player.active_container_id != "survivor_outpost_01_clinic_supply_cabinet":
		errors.append("player active container was not updated")

	var transition_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_interior_door",
	})
	if not bool(transition_result.get("success", false)):
		errors.append("scene transition failed: %s" % transition_result.get("reason", "unknown"))
	if simulation.active_map_id != "survivor_outpost_01_interior":
		errors.append("scene transition did not update active map")
	return errors


func _digest(snapshot: Dictionary) -> Dictionary:
	var actors: Array = snapshot.get("actors", [])
	var player_inventory: Dictionary = {}
	var player_dialogue := ""
	for actor in actors:
		if int(actor.get("actor_id", 0)) == 1:
			player_inventory = actor.get("inventory", {})
			player_dialogue = str(actor.get("active_dialogue_id", ""))
	return {
		"active_map_id": snapshot.get("active_map_id", ""),
		"consumed_interaction_targets": snapshot.get("consumed_interaction_targets", []),
		"event_count": snapshot.get("events", []).size(),
		"player_inventory": player_inventory,
		"player_dialogue": player_dialogue,
		"container_sessions": snapshot.get("container_sessions", []),
	}
