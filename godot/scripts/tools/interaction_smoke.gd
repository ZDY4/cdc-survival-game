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
	var prompt_probe: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_pickup_medkit",
	})
	_expect_prompt_snapshot(errors, prompt_probe, "pickup", "pickup", 1.0)
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
	_expect_interaction_succeeded_payload(errors, simulation.snapshot(), "pickup", "pickup", "survivor_outpost_01_pickup_medkit")
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
	var dialogue_started_payload: Dictionary = _last_event_payload(simulation.snapshot(), "dialogue_started")
	if int(dialogue_started_payload.get("actor_id", 0)) != 1 or str(dialogue_started_payload.get("dialogue_id", "")) != "trader_lao_wang":
		errors.append("dialogue_started should include actor_id and dialogue_id")
	_expect_interaction_succeeded_payload(errors, simulation.snapshot(), "talk", "talk", "老王")

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
	var container_opened_payload: Dictionary = _last_event_payload(simulation.snapshot(), "container_opened")
	if int(container_opened_payload.get("actor_id", 0)) != 1 or str(container_opened_payload.get("target_id", "")) != "survivor_outpost_01_clinic_supply_cabinet":
		errors.append("container_opened should include actor_id and target_id")
	if int(container_opened_payload.get("item_count", -1)) != 2:
		errors.append("container_opened should include item_count")
	_expect_interaction_succeeded_payload(errors, simulation.snapshot(), "open_container", "open_container", "补给柜")

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
	_expect_interaction_succeeded_payload(errors, simulation.snapshot(), "wait", "wait", "幸存者")

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
	var scene_transition_payload: Dictionary = _last_event_payload(simulation.snapshot(), "scene_transition")
	if int(scene_transition_payload.get("actor_id", 0)) != 1:
		errors.append("scene_transition should include actor_id")
	if str(scene_transition_payload.get("from_map_id", "")) != "survivor_outpost_01" or str(scene_transition_payload.get("to_map_id", "")) != "survivor_outpost_01_interior":
		errors.append("scene_transition should include from/to map ids")
	if str(scene_transition_payload.get("entry_point_id", "")).is_empty():
		errors.append("scene_transition should include entry_point_id")
	_expect_interaction_succeeded_payload(errors, simulation.snapshot(), "enter_subscene", "enter_subscene", "进入据点室内")
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
	if _event_count_in_result(result, "player_command_submitted") <= 0:
		errors.append("command result should include player_command_submitted")
	var expected_terminal_event := "player_command_completed" if bool(result.get("success", false)) else "player_command_rejected"
	if _event_count_in_result(result, expected_terminal_event) <= 0:
		errors.append("command result should include %s" % expected_terminal_event)
	if _event_count_in_result(result, "ui_feedback") <= 0:
		errors.append("command result should include ui_feedback event")


func _event_count_in_result(result: Dictionary, kind: String) -> int:
	var count := 0
	for event in result.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _expect_interaction_succeeded_payload(errors: Array[String], snapshot: Dictionary, expected_option_id: String, expected_option_kind: String, expected_name_fragment: String) -> void:
	var payload: Dictionary = _last_event_payload(snapshot, "interaction_succeeded")
	if int(payload.get("actor_id", 0)) != 1:
		errors.append("%s interaction_succeeded should include actor_id" % expected_option_id)
	if str(payload.get("option_id", "")) != expected_option_id:
		errors.append("%s interaction_succeeded should include option_id" % expected_option_id)
	if str(payload.get("option_kind", "")) != expected_option_kind:
		errors.append("%s interaction_succeeded should include option_kind" % expected_option_id)
	if str(payload.get("target_name", "")).find(expected_name_fragment) == -1:
		errors.append("%s interaction_succeeded should include target_name" % expected_option_id)


func _expect_prompt_snapshot(errors: Array[String], prompt: Dictionary, expected_option_id: String, expected_option_kind: String, expected_ap_cost: float) -> void:
	if not bool(prompt.get("ok", false)):
		errors.append("prompt snapshot probe should succeed")
	if str(prompt.get("primary_option_id", "")) != expected_option_id:
		errors.append("prompt snapshot should include primary_option_id")
	if str(prompt.get("primary_option_kind", "")) != expected_option_kind:
		errors.append("prompt snapshot should include primary_option_kind")
	if str(prompt.get("action_label", "")).is_empty():
		errors.append("prompt snapshot should include action_label")
	if absf(float(prompt.get("ap_cost", -1.0)) - expected_ap_cost) > 0.001:
		errors.append("prompt snapshot should include ap_cost")
	if str(prompt.get("target_kind", "")).is_empty():
		errors.append("prompt snapshot should include target_kind")
	if typeof(prompt.get("disabled_options", [])) != TYPE_ARRAY:
		errors.append("prompt snapshot should include disabled_options")
	var options: Array = prompt.get("options", [])
	if options.is_empty():
		errors.append("prompt snapshot should include options")
	else:
		var option: Dictionary = _dictionary_or_empty(options[0])
		if str(option.get("kind", "")) != expected_option_kind:
			errors.append("prompt option should include kind")
		if not option.has("ap_cost") or not option.has("disabled") or not option.has("disabled_reason"):
			errors.append("prompt option should include ap_cost and disabled metadata")


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
	var interaction_queued_payload: Dictionary = _last_event_payload(simulation.snapshot(), "interaction_queued")
	if int(interaction_queued_payload.get("actor_id", 0)) != 1:
		errors.append("interaction_queued should include actor_id")
	var queued_target: Dictionary = _dictionary_or_empty(interaction_queued_payload.get("target", {}))
	if str(queued_target.get("target_type", "")) != "actor" or int(queued_target.get("actor_id", 0)) != trader.actor_id:
		errors.append("interaction_queued should include queued actor target")
	if str(interaction_queued_payload.get("option_id", "")).is_empty():
		errors.append("interaction_queued should include option_id")
	if _event_count(simulation.snapshot(), "interaction_resumed") <= 0:
		errors.append("far talk should emit interaction_resumed after auto approach")
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


func _last_event_payload(snapshot: Dictionary, kind: String) -> Dictionary:
	var events: Array = snapshot.get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = events[index]
		if event_data.get("kind", "") == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
