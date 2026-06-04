extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


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
	var errors := _run_interaction_checks(simulation, registry)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("interaction_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_interaction_checks(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var first_snapshot: Dictionary = simulation.snapshot()
	for key in ["turn_state", "combat_state", "pending_movement", "pending_interaction", "corpse_containers", "interaction_menu", "hotbar"]:
		if not first_snapshot.has(key):
			errors.append("runtime snapshot missing %s" % key)
	var topology: Dictionary = _topology(simulation, registry)
	var unsupported_result: Dictionary = simulation.submit_player_command({"kind": "unsupported_contract_probe"})
	_expect_command_result_contract(errors, unsupported_result, "unsupported_contract_probe")
	if bool(unsupported_result.get("success", false)):
		errors.append("unsupported command should fail")
	var pickup_result: Dictionary = _submit_and_complete(simulation, registry, {
		"kind": "interact",
		"target": {
			"target_type": "map_object",
			"target_id": "survivor_outpost_01_pickup_medkit",
		},
		"topology": topology,
	})
	if not bool(pickup_result.get("success", false)):
		errors.append("pickup failed: %s" % pickup_result.get("reason", "unknown"))
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if int(player.inventory.get("1006", 0)) <= 0:
		errors.append("pickup did not add item 1006 to player inventory")
	var second_pickup: Dictionary = _submit_and_complete(simulation, registry, {
		"kind": "interact",
		"target": {
			"target_type": "map_object",
			"target_id": "survivor_outpost_01_pickup_medkit",
		},
		"topology": topology,
	})
	if bool(second_pickup.get("success", false)):
		errors.append("pickup target was not consumed")

	var talk_result: Dictionary = _submit_and_complete(simulation, registry, {
		"kind": "interact",
		"target": {
			"target_type": "actor",
			"actor_id": 2,
		},
		"topology": topology,
	})
	if not bool(talk_result.get("success", false)):
		errors.append("talk failed: %s" % talk_result.get("reason", "unknown"))
	if talk_result.get("dialogue_id", "") != "trader_lao_wang":
		errors.append("talk did not resolve trader_lao_wang dialogue")

	var container_result: Dictionary = _submit_and_complete(simulation, registry, {
		"kind": "interact",
		"target": {
			"target_type": "map_object",
			"target_id": "survivor_outpost_01_clinic_supply_cabinet",
		},
		"topology": topology,
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

	var wait_result: Dictionary = simulation.submit_player_command({
		"kind": "interact",
		"target": {
			"target_type": "self",
			"actor_id": 1,
		},
		"topology": topology,
	})
	if not bool(wait_result.get("success", false)):
		errors.append("self wait interaction failed: %s" % wait_result.get("reason", "unknown"))
	_expect_command_result_contract(errors, wait_result, "wait")
	if _event_count(simulation.snapshot(), "turn_ended") <= 0:
		errors.append("self wait should end the current turn")

	var transition_result: Dictionary = _submit_and_complete(simulation, registry, {
		"kind": "interact",
		"target": {
			"target_type": "map_object",
			"target_id": "survivor_outpost_01_interior_door",
		},
		"topology": topology,
	})
	if not bool(transition_result.get("success", false)):
		errors.append("scene transition failed: %s" % transition_result.get("reason", "unknown"))
	if simulation.active_map_id != "survivor_outpost_01_interior":
		errors.append("scene transition did not update active map")
	var approach_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var approach_errors: Array[String] = _expect_auto_approach_interaction(approach_simulation, registry)
	errors.append_array(approach_errors)
	return errors


func _submit_and_complete(simulation: RefCounted, registry: RefCounted, command: Dictionary, max_waits: int = 8) -> Dictionary:
	var result: Dictionary = simulation.submit_player_command(command)
	var waits := 0
	while waits < max_waits and _has_pending(simulation) and not _final_interaction_result(result):
		waits += 1
		var wait_result: Dictionary = simulation.submit_player_command({
			"kind": "wait",
			"topology": _topology(simulation, registry),
		})
		var pending_result: Dictionary = wait_result.get("pending_result", {})
		result = pending_result if not pending_result.is_empty() else wait_result
	return result


func _has_pending(simulation: RefCounted) -> bool:
	var snapshot: Dictionary = simulation.snapshot()
	return not snapshot.get("pending_movement", {}).is_empty() or not snapshot.get("pending_interaction", {}).is_empty()


func _final_interaction_result(result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		return true
	return bool(result.get("consumed_target", false)) \
		or result.has("dialogue_id") \
		or result.has("container") \
		or _has_context_snapshot(result) \
		or bool(result.get("waited", false)) \
		or bool(result.get("defeated", false))


func _has_context_snapshot(result: Dictionary) -> bool:
	var context: Variant = result.get("context_snapshot", {})
	if typeof(context) != TYPE_DICTIONARY:
		return false
	var context_dictionary: Dictionary = context
	return not context_dictionary.is_empty()


func _expect_command_result_contract(errors: Array[String], result: Dictionary, expected_kind: String) -> void:
	for key in ["success", "kind", "reason", "events", "turn_state", "combat_state", "runtime_snapshot_delta", "ui_feedback", "prompt", "context_snapshot"]:
		if not result.has(key):
			errors.append("command result missing %s" % key)
	if str(result.get("kind", "")) != expected_kind:
		errors.append("command result kind expected %s got %s" % [expected_kind, result.get("kind", "")])
	if typeof(result.get("events", [])) != TYPE_ARRAY:
		errors.append("command result events should be an array")
	if typeof(result.get("turn_state", {})) != TYPE_DICTIONARY:
		errors.append("command result turn_state should be a dictionary")
	if typeof(result.get("runtime_snapshot_delta", {})) != TYPE_DICTIONARY:
		errors.append("command result runtime_snapshot_delta should be a dictionary")
	if typeof(result.get("ui_feedback", {})) != TYPE_DICTIONARY:
		errors.append("command result ui_feedback should be a dictionary")


func _expect_auto_approach_interaction(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var topology: Dictionary = _topology(simulation, registry)
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.ap = 20.0
	var trader: RefCounted = simulation.actor_registry.get_actor(2)
	trader.grid_position.x = player.grid_position.x + 4
	trader.grid_position.z = player.grid_position.z
	var result: Dictionary = simulation.submit_player_command({
		"kind": "interact",
		"target": {
			"target_type": "actor",
			"actor_id": trader.actor_id,
		},
		"topology": topology,
	})
	if not bool(result.get("success", false)):
		errors.append("far talk should auto approach then execute: %s" % result.get("reason", "unknown"))
	if not bool(result.get("auto_resumed_interaction", false)):
		errors.append("far talk should report auto_resumed_interaction")
	if player.active_dialogue_id != "trader_lao_wang":
		errors.append("far talk should start trader dialogue after approach")
	if _event_count(simulation.snapshot(), "movement_queued") <= 0:
		errors.append("far talk should emit movement_queued before auto resume")
	if _event_count(simulation.snapshot(), "interaction_queued") <= 0:
		errors.append("far talk should emit interaction_queued before auto resume")
	return errors


func _topology(simulation: RefCounted, registry: RefCounted) -> Dictionary:
	var world: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	return world.get("map", {})


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


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count
