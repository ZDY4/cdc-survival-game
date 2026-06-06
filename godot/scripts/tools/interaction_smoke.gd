extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")
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
	for key in ["turn_state", "combat_state", "pending_movement", "pending_interaction", "runtime_command_queue", "pending_progression_step", "current_control_actor", "recent_interaction_target", "recent_failure", "recent_event_feedback", "target_preview", "target_selection_state", "ui_menu_state_refs", "door_states", "corpse_containers", "interaction_menu", "hotbar"]:
		if not first_snapshot.has(key):
			errors.append("runtime snapshot missing %s" % key)
	_expect_initial_runtime_snapshot_fields(errors, first_snapshot)
	var topology: Dictionary = _topology(simulation, registry)
	var prompt_probe: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_pickup_medkit",
	})
	_expect_prompt_snapshot(errors, prompt_probe, "pickup", "pickup", 1.0)
	_expect_prompt_range(errors, prompt_probe, 1, "pickup prompt")
	_expect_disabled_option(errors, prompt_probe, "open_container", "target_not_container", "pickup prompt")
	_expect_disabled_option(errors, prompt_probe, "talk", "target_not_actor", "pickup prompt")
	var self_prompt_probe: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "self",
		"actor_id": 1,
	})
	_expect_prompt_snapshot(errors, self_prompt_probe, "wait", "wait", 1.0)
	_expect_prompt_range(errors, self_prompt_probe, 0, "self prompt")
	_expect_disabled_option(errors, self_prompt_probe, "attack", "self_target", "self prompt")
	if str(self_prompt_probe.get("action_label", "")) != "等待":
		errors.append("self interaction prompt should expose wait action label")
	if str(self_prompt_probe.get("target_name", "")).find("幸存者") == -1:
		errors.append("self interaction prompt should expose player target name")
	var friendly_prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "actor",
		"actor_id": 2,
	})
	_expect_prompt_snapshot(errors, friendly_prompt, "talk", "talk", 1.0)
	_expect_prompt_range(errors, friendly_prompt, 2, "friendly prompt")
	_expect_disabled_option(errors, friendly_prompt, "attack", "target_not_hostile", "friendly prompt")
	var disabled_execute: Dictionary = simulation.execute_interaction(1, {
		"target_type": "actor",
		"actor_id": 2,
	}, "attack")
	if bool(disabled_execute.get("success", false)) or str(disabled_execute.get("reason", "")) != "target_not_hostile":
		errors.append("executing a disabled friendly attack option should return target_not_hostile")
	simulation.set_relationship_score(1, 2, -75.0, "interaction_smoke_relation_hostile")
	var relationship_hostile_prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "actor",
		"actor_id": 2,
	})
	_expect_prompt_snapshot(errors, relationship_hostile_prompt, "attack", "attack", 2.0)
	if str(_dictionary_or_empty(relationship_hostile_prompt.get("target", {})).get("hostility_reason", "")) != "relationship_hostile":
		errors.append("relationship-hostile prompt should expose relationship_hostile reason")
	_expect_disabled_option(errors, relationship_hostile_prompt, "talk", "target_hostile", "relationship hostile prompt")
	simulation.set_relationship_score(1, 2, 50.0, "interaction_smoke_relation_restored")
	var hostile_prompt_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var hostile_actor: RefCounted = hostile_prompt_simulation.actor_registry.get_actor(2)
	hostile_actor.side = "hostile"
	hostile_prompt_simulation.set_relationship_score(1, hostile_actor.actor_id, -75.0, "interaction_smoke_side_hostile")
	var hostile_prompt: Dictionary = hostile_prompt_simulation.query_interaction_options(1, {
		"target_type": "actor",
		"actor_id": hostile_actor.actor_id,
	})
	_expect_prompt_snapshot(errors, hostile_prompt, "attack", "attack", 2.0)
	_expect_disabled_option(errors, hostile_prompt, "talk", "target_hostile", "hostile prompt")
	var grid_prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "grid",
		"grid": {
			"x": 25,
			"y": 0,
			"z": 39,
		},
	})
	_expect_prompt_snapshot(errors, grid_prompt, "move", "move", 0.0)
	_expect_prompt_range(errors, grid_prompt, 0, "grid prompt")
	_expect_disabled_option(errors, grid_prompt, "pickup", "target_empty", "grid prompt")
	var hidden_prompt_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	hidden_prompt_simulation.set_actor_vision_radius(1, 0)
	hidden_prompt_simulation.refresh_actor_vision(1, _topology(hidden_prompt_simulation, registry))
	var hidden_prompt: Dictionary = hidden_prompt_simulation.query_interaction_options(1, {
		"target_type": "actor",
		"actor_id": 2,
	})
	if bool(hidden_prompt.get("ok", false)) or str(hidden_prompt.get("reason", "")) != "target_not_visible":
		errors.append("active vision should reject hidden interaction target")
	if _dictionary_or_empty(hidden_prompt.get("target_grid", {})).is_empty():
		errors.append("hidden interaction prompt should expose target_grid")
	var unsupported_result: Dictionary = simulation.submit_player_command({"kind": "unsupported_contract_probe"})
	_expect_command_result_contract(errors, unsupported_result, "unsupported_contract_probe")
	if bool(unsupported_result.get("success", false)):
		errors.append("unsupported command should fail")
	_expect_rejected_command(errors, unsupported_result, "unknown_player_command", "unsupported command")
	var reject_errors: Array[String] = _expect_basic_reject_semantics(registry)
	errors.append_array(reject_errors)
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
	if int(pickup_result.get("count", 0)) != 2:
		errors.append("pickup should grant deterministic max_count 2")
	if int(pickup_result.get("inventory_before", -1)) != 1 or int(pickup_result.get("inventory_after", -1)) != 3:
		errors.append("pickup result should expose merged inventory before/after")
	if int(player.inventory.get("1006", 0)) != 3:
		errors.append("pickup did not merge item 1006 into player inventory")
	_expect_pickup_granted_payload(errors, simulation.snapshot(), "survivor_outpost_01_pickup_medkit", "1006", 2, 1, 3)
	_expect_interaction_succeeded_payload(errors, simulation.snapshot(), "pickup", "pickup", "survivor_outpost_01_pickup_medkit")
	_expect_runtime_snapshot_after_pickup(errors, simulation.snapshot())
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
	_expect_rejected_command(errors, second_pickup, "interaction_target_unavailable", "consumed pickup")
	_expect_runtime_snapshot_after_reject(errors, simulation.snapshot(), "interaction_target_unavailable")

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
	if talk_result.get("dialogue_id", "") != "trader_lao_wang_tutorial_active":
		errors.append("talk did not resolve tutorial-active trader dialogue")
	if talk_result.get("requested_dialogue_id", "") != "trader_lao_wang" or talk_result.get("dialogue_rule_source", "") != "variant":
		errors.append("talk should expose dialogue rule resolution")
	var dialogue_started_payload: Dictionary = _last_event_payload(simulation.snapshot(), "dialogue_started")
	if int(dialogue_started_payload.get("actor_id", 0)) != 1 or str(dialogue_started_payload.get("dialogue_id", "")) != "trader_lao_wang_tutorial_active":
		errors.append("dialogue_started should include actor_id and dialogue_id")
	if str(dialogue_started_payload.get("dialogue_rule_key", "")) != "trader_lao_wang" or str(dialogue_started_payload.get("dialogue_rule_source", "")) != "variant":
		errors.append("dialogue_started should include rule key and source")
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
	if str(transition_result.get("target_map_id", "")) != "survivor_outpost_01_interior":
		errors.append("scene transition result should include target_map_id")
	if str(transition_result.get("target_entry_point_id", "")).is_empty():
		errors.append("scene transition result should include target_entry_point_id")
	if str(transition_result.get("entry_facing", "")) != "south":
		errors.append("scene transition result should include target entry facing")
	if str(transition_result.get("return_map_id", "")) != "survivor_outpost_01":
		errors.append("scene transition result should include return map id")
	if str(transition_result.get("return_entry_point_id", "")) != "default_entry":
		errors.append("scene transition result should include previous active entry as return point")
	if _dictionary_or_empty(transition_result.get("grid_position", {})).is_empty():
		errors.append("scene transition result should include grid_position")
	var scene_transition_payload: Dictionary = _last_event_payload(simulation.snapshot(), "scene_transition")
	if int(scene_transition_payload.get("actor_id", 0)) != 1:
		errors.append("scene_transition should include actor_id")
	if str(scene_transition_payload.get("target_id", "")) != "survivor_outpost_01_interior_door" or str(scene_transition_payload.get("target_name", "")).is_empty():
		errors.append("scene_transition should include target id and name")
	if str(scene_transition_payload.get("from_map_id", "")) != "survivor_outpost_01" or str(scene_transition_payload.get("to_map_id", "")) != "survivor_outpost_01_interior":
		errors.append("scene_transition should include from/to map ids")
	if str(scene_transition_payload.get("entry_point_id", "")).is_empty():
		errors.append("scene_transition should include entry_point_id")
	if str(scene_transition_payload.get("entry_facing", "")) != "south":
		errors.append("scene_transition should include entry_facing")
	if str(scene_transition_payload.get("return_map_id", "")) != "survivor_outpost_01" or str(scene_transition_payload.get("return_entry_point_id", "")) != "default_entry":
		errors.append("scene_transition should include return map and entry")
	if _dictionary_or_empty(scene_transition_payload.get("grid_position", {})).is_empty():
		errors.append("scene_transition should include grid_position")
	_expect_interaction_succeeded_payload(errors, simulation.snapshot(), "enter_subscene", "enter_subscene", "进入据点室内")
	var transition_combat_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	errors.append_array(_expect_scene_transition_ends_combat(transition_combat_simulation, registry))
	var approach_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var approach_errors: Array[String] = _expect_auto_approach_interaction(approach_simulation, registry)
	errors.append_array(approach_errors)
	var range_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	errors.append_array(_expect_talk_range_direct_interaction(range_simulation, registry))
	var container_replacement_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	errors.append_array(_expect_container_replacement_close(container_replacement_simulation))
	var direct_wait_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	errors.append_array(_expect_direct_self_wait_interaction(direct_wait_simulation))
	var door_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	errors.append_array(_expect_door_interaction(door_simulation))
	var transition_permission_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	errors.append_array(_expect_scene_transition_permissions(transition_permission_simulation, registry))
	var relationship_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	errors.append_array(_expect_relationship_dialogue_rules(relationship_simulation, registry))
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


func _expect_scene_transition_ends_combat(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null:
		return ["scene transition combat smoke missing player"]
	var player_grid: Dictionary = player.grid_position.to_dictionary()
	var hostile_id: int = simulation.register_actor({
		"definition_id": "transition_combat_hostile",
		"kind": "enemy",
		"side": "hostile",
		"display_name": "Transition Combat Hostile",
		"grid_position": GridCoord.from_dictionary({
			"x": int(player_grid.get("x", 0)) + 1,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		}),
		"hp": 10.0,
		"max_hp": 10.0,
		"ap": 0.0,
		"map_id": simulation.active_map_id,
	})
	simulation._enter_combat([1, hostile_id], "scene_transition_combat_smoke")
	var result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_interior_door",
	}, "enter_subscene")
	if not bool(result.get("success", false)):
		errors.append("scene transition during combat should succeed: %s" % result.get("reason", "unknown"))
	if not bool(result.get("combat_ended", false)):
		errors.append("scene transition should report combat_ended when changing maps")
	var combat_state: Dictionary = _dictionary_or_empty(simulation.snapshot().get("combat_state", {}))
	if bool(combat_state.get("active", false)):
		errors.append("scene transition should clear active combat state")
	var combat_end: Dictionary = _last_event_payload(simulation.snapshot(), "combat_ended")
	if str(combat_end.get("reason", "")) != "map_changed" or str(combat_end.get("source", "")) != "scene_transition":
		errors.append("scene transition should force end combat with map_changed reason")
	if str(combat_end.get("from_map_id", "")) != "survivor_outpost_01" or str(combat_end.get("to_map_id", "")) != "survivor_outpost_01_interior":
		errors.append("scene transition combat_ended should include from/to map ids")
	return errors


func _final_interaction_result(result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		return true
	return bool(result.get("consumed_target", false)) \
		or result.has("dialogue_id") \
		or result.has("container") \
		or _has_context_snapshot(result) \
		or bool(result.get("waited", false)) \
		or bool(result.get("door_toggled", false)) \
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


func _expect_initial_runtime_snapshot_fields(errors: Array[String], snapshot: Dictionary) -> void:
	var control_actor: Dictionary = _dictionary_or_empty(snapshot.get("current_control_actor", {}))
	if int(control_actor.get("actor_id", 0)) != 1:
		errors.append("runtime snapshot should expose current player control actor")
	if str(control_actor.get("display_name", "")).is_empty():
		errors.append("runtime snapshot current control actor should include display_name")
	if typeof(snapshot.get("runtime_command_queue", [])) != TYPE_ARRAY:
		errors.append("runtime snapshot command queue should be an array")
	if typeof(snapshot.get("pending_progression_step", {})) != TYPE_DICTIONARY:
		errors.append("runtime snapshot pending progression step should be a dictionary")
	if typeof(snapshot.get("recent_event_feedback", [])) != TYPE_ARRAY:
		errors.append("runtime snapshot recent event feedback should be an array")
	if typeof(snapshot.get("target_selection_state", {})) != TYPE_DICTIONARY:
		errors.append("runtime snapshot target selection state should be a dictionary")
	if typeof(snapshot.get("ui_menu_state_refs", {})) != TYPE_DICTIONARY:
		errors.append("runtime snapshot ui menu state refs should be a dictionary")


func _expect_runtime_snapshot_after_pickup(errors: Array[String], snapshot: Dictionary) -> void:
	var recent_target: Dictionary = _dictionary_or_empty(snapshot.get("recent_interaction_target", {}))
	if str(recent_target.get("target_name", "")).find("survivor_outpost_01_pickup_medkit") == -1:
		errors.append("runtime snapshot should expose recent pickup target")
	if str(recent_target.get("option_kind", "")) != "pickup":
		errors.append("runtime snapshot recent target should include pickup option kind")
	var target_preview: Dictionary = _dictionary_or_empty(snapshot.get("target_preview", {}))
	if str(target_preview.get("source", "")) != "interaction_menu":
		errors.append("runtime snapshot target preview should use interaction_menu after interaction prompt")
	if str(target_preview.get("primary_option_kind", "")) != "pickup":
		errors.append("runtime snapshot target preview should include primary option kind")
	var selection_state: Dictionary = _dictionary_or_empty(snapshot.get("target_selection_state", {}))
	if not bool(selection_state.get("has_selection", false)) or not bool(selection_state.get("has_prompt", false)):
		errors.append("runtime snapshot target selection state should show active prompt")
	var ui_refs: Dictionary = _dictionary_or_empty(snapshot.get("ui_menu_state_refs", {}))
	if not bool(ui_refs.get("interaction_menu_open", false)):
		errors.append("runtime snapshot ui menu refs should expose interaction menu open")
	var feedback: Array = snapshot.get("recent_event_feedback", [])
	if feedback.is_empty():
		errors.append("runtime snapshot should expose recent event feedback entries")


func _expect_runtime_snapshot_after_reject(errors: Array[String], snapshot: Dictionary, expected_reason: String) -> void:
	var recent_failure: Dictionary = _dictionary_or_empty(snapshot.get("recent_failure", {}))
	if str(recent_failure.get("reason", "")) != expected_reason:
		errors.append("runtime snapshot should expose recent failure reason")
	if int(recent_failure.get("actor_id", 0)) != 1:
		errors.append("runtime snapshot recent failure should include actor_id")
	var feedback: Array = snapshot.get("recent_event_feedback", [])
	var found_reject_feedback := false
	for entry in feedback:
		var data: Dictionary = _dictionary_or_empty(entry)
		if str(data.get("kind", "")) == "player_command_rejected":
			found_reject_feedback = true
	if not found_reject_feedback:
		errors.append("runtime snapshot feedback should include recent command rejection")


func _expect_rejected_command(errors: Array[String], result: Dictionary, expected_reason: String, context: String) -> void:
	if bool(result.get("success", false)):
		errors.append("%s should be rejected" % context)
	if str(result.get("reason", "")) != expected_reason:
		errors.append("%s reason expected %s, got %s" % [context, expected_reason, result.get("reason", "")])
	var feedback: Dictionary = _dictionary_or_empty(result.get("ui_feedback", {}))
	if bool(feedback.get("success", true)):
		errors.append("%s ui_feedback should report failure" % context)
	if str(feedback.get("reason", "")) != expected_reason:
		errors.append("%s ui_feedback reason expected %s, got %s" % [context, expected_reason, feedback.get("reason", "")])
	var rejected_payload: Dictionary = _last_result_event_payload(result, "player_command_rejected")
	if str(rejected_payload.get("reason", "")) != expected_reason:
		errors.append("%s player_command_rejected should include reason" % context)
	var ui_payload: Dictionary = _last_result_event_payload(result, "ui_feedback")
	if str(ui_payload.get("reason", "")) != expected_reason:
		errors.append("%s ui_feedback event should include reason" % context)


func _expect_basic_reject_semantics(registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var unknown_actor: Dictionary = simulation.submit_player_command({
		"kind": "wait",
		"actor_id": 99999,
	})
	_expect_command_result_contract(errors, unknown_actor, "wait")
	_expect_rejected_command(errors, unknown_actor, "unknown_actor", "unknown actor command")

	var non_player_actor: Dictionary = simulation.submit_player_command({
		"kind": "wait",
		"actor_id": 2,
	})
	_expect_command_result_contract(errors, non_player_actor, "wait")
	_expect_rejected_command(errors, non_player_actor, "command_actor_not_player", "non-player actor command")

	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.turn_open = false
	var closed_turn: Dictionary = simulation.submit_player_command({
		"kind": "wait",
		"actor_id": 1,
	})
	_expect_command_result_contract(errors, closed_turn, "wait")
	_expect_rejected_command(errors, closed_turn, "turn_closed", "closed turn command")

	player.turn_open = true
	var unknown_attack_target: Dictionary = simulation.submit_player_command({
		"kind": "attack",
		"actor_id": 1,
		"target_actor_id": 99999,
	})
	_expect_command_result_contract(errors, unknown_attack_target, "attack")
	_expect_rejected_command(errors, unknown_attack_target, "unknown_target", "unknown attack target")
	return errors


func _event_count_in_result(result: Dictionary, kind: String) -> int:
	var count := 0
	for event in result.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _last_result_event_payload(result: Dictionary, kind: String) -> Dictionary:
	var events: Array = result.get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if event_data.get("kind", "") == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


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
	if expected_option_id == "pickup":
		if str(payload.get("item_id", "")) != "1006":
			errors.append("pickup interaction_succeeded should include item_id")
		if int(payload.get("count", 0)) != 2:
			errors.append("pickup interaction_succeeded should include count")
		if int(payload.get("inventory_before", -1)) != 1 or int(payload.get("inventory_after", -1)) != 3:
			errors.append("pickup interaction_succeeded should include inventory before/after")


func _expect_pickup_granted_payload(errors: Array[String], snapshot: Dictionary, expected_target_id: String, expected_item_id: String, expected_count: int, expected_before: int, expected_after: int) -> void:
	var payload: Dictionary = _last_event_payload(snapshot, "pickup_granted")
	if str(payload.get("target_id", "")) != expected_target_id:
		errors.append("pickup_granted should include target_id")
	if str(payload.get("item_id", "")) != expected_item_id:
		errors.append("pickup_granted should include item_id")
	if int(payload.get("count", 0)) != expected_count:
		errors.append("pickup_granted should include count")
	if int(payload.get("inventory_before", -1)) != expected_before or int(payload.get("inventory_after", -1)) != expected_after:
		errors.append("pickup_granted should include inventory before/after")


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


func _expect_disabled_option(errors: Array[String], prompt: Dictionary, option_id: String, reason: String, context: String) -> void:
	for candidate in prompt.get("disabled_options", []):
		var option: Dictionary = _dictionary_or_empty(candidate)
		if str(option.get("id", "")) != option_id:
			continue
		if not bool(option.get("disabled", false)):
			errors.append("%s disabled option %s should be marked disabled" % [context, option_id])
		if str(option.get("disabled_reason", "")) != reason:
			errors.append("%s disabled option %s reason expected %s got %s" % [context, option_id, reason, option.get("disabled_reason", "")])
		if not option.has("ap_cost"):
			errors.append("%s disabled option %s should include ap_cost" % [context, option_id])
		return
	errors.append("%s should expose disabled option %s" % [context, option_id])


func _expect_prompt_range(errors: Array[String], prompt: Dictionary, expected_range: int, context: String) -> void:
	if int(prompt.get("interaction_range", -1)) != expected_range:
		errors.append("%s should expose interaction_range %d" % [context, expected_range])
	if not prompt.has("target_distance"):
		errors.append("%s should expose target_distance" % context)
	if not prompt.has("requires_approach"):
		errors.append("%s should expose requires_approach" % context)
	var options: Array = prompt.get("options", [])
	if not options.is_empty() and int(_dictionary_or_empty(options[0]).get("interaction_range", -1)) != expected_range:
		errors.append("%s primary option should expose interaction_range %d" % [context, expected_range])


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
	if player.active_dialogue_id != "trader_lao_wang_tutorial_active":
		errors.append("far talk should start trader dialogue after approach")
	if _grid_distance(player.grid_position, trader.grid_position) > 2:
		errors.append("far talk should stop within talk interaction range")
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


func _expect_talk_range_direct_interaction(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var topology: Dictionary = _topology(simulation, registry)
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var trader: RefCounted = simulation.actor_registry.get_actor(2)
	trader.grid_position.x = player.grid_position.x + 2
	trader.grid_position.z = player.grid_position.z
	player.ap = 6.0
	var movement_before: int = _event_count(simulation.snapshot(), "movement_queued")
	var result: Dictionary = simulation.submit_player_command({
		"kind": "interact",
		"target": {
			"target_type": "actor",
			"actor_id": trader.actor_id,
		},
		"topology": topology,
	})
	if not bool(result.get("success", false)):
		errors.append("range-2 talk should execute without approach: %s" % result.get("reason", "unknown"))
	if player.active_dialogue_id != "trader_lao_wang_tutorial_active":
		errors.append("range-2 talk should start trader dialogue")
	if _event_count(simulation.snapshot(), "movement_queued") != movement_before:
		errors.append("range-2 talk should not queue movement")
	var prompt: Dictionary = _dictionary_or_empty(result.get("prompt", {}))
	if int(prompt.get("interaction_range", -1)) != 2 or bool(prompt.get("requires_approach", true)):
		errors.append("range-2 talk prompt should expose no approach required")
	return errors


func _expect_container_replacement_close(simulation: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var clinic_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_clinic_supply_cabinet",
	})
	if not bool(clinic_result.get("success", false)):
		return ["container replacement setup failed: %s" % clinic_result.get("reason", "unknown")]
	var canteen_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_canteen_food_crate",
	})
	if not bool(canteen_result.get("success", false)):
		return ["container replacement open failed: %s" % canteen_result.get("reason", "unknown")]
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null or player.active_container_id != "survivor_outpost_01_canteen_food_crate":
		errors.append("opening a new container should replace active container id")
	var payload: Dictionary = _last_event_payload(simulation.snapshot(), "container_closed")
	if str(payload.get("container_id", "")) != "survivor_outpost_01_clinic_supply_cabinet":
		errors.append("container replacement should close previous container")
	if str(payload.get("reason", "")) != "replaced":
		errors.append("container replacement close reason should be replaced")
	if str(payload.get("next_container_id", "")) != "survivor_outpost_01_canteen_food_crate":
		errors.append("container replacement should include next_container_id")
	return errors


func _expect_direct_self_wait_interaction(simulation: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var round_before: int = int(simulation.snapshot().get("turn_state", {}).get("round", 0))
	var result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "self",
		"actor_id": 1,
	}, "wait")
	if not bool(result.get("success", false)):
		errors.append("direct self wait interaction should succeed: %s" % result.get("reason", "unknown"))
	if not bool(result.get("waited", false)):
		errors.append("direct self wait interaction should report waited")
	if str(result.get("kind", "")) != "wait":
		errors.append("direct self wait interaction should preserve wait result kind")
	if int(simulation.snapshot().get("turn_state", {}).get("round", 0)) <= round_before:
		errors.append("direct self wait interaction should advance the turn round")
	if _event_count(simulation.snapshot(), "turn_ended") <= 0:
		errors.append("direct self wait interaction should emit turn_ended")
	_expect_interaction_succeeded_payload(errors, simulation.snapshot(), "wait", "wait", "幸存者")
	return errors


func _expect_door_interaction(simulation: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null:
		return ["door interaction smoke missing player"]
	player.ap = 10.0
	var door_grid := {
		"x": player.grid_position.x + 1,
		"y": player.grid_position.y,
		"z": player.grid_position.z,
	}
	simulation.configure_map_interactions({
		"door_interaction_smoke": _door_target("door_interaction_smoke", false, false, door_grid),
		"locked_door_interaction_smoke": _door_target("locked_door_interaction_smoke", false, true, door_grid),
		"keyed_door_interaction_smoke": _door_target("keyed_door_interaction_smoke", false, true, door_grid, {
			"required_item_ids": ["1138"],
		}),
		"tool_door_interaction_smoke": _door_target("tool_door_interaction_smoke", false, true, door_grid, {
			"required_tool_ids": ["1150"],
		}),
		"consume_key_door_interaction_smoke": _door_target("consume_key_door_interaction_smoke", false, true, door_grid, {
			"required_item_ids": ["1138"],
			"consume_required_items_on_unlock": true,
		}),
		"consume_tool_door_interaction_smoke": _door_target("consume_tool_door_interaction_smoke", false, true, door_grid, {
			"required_tool_ids": ["1150"],
			"consume_required_tools_on_unlock": true,
		}),
	})
	var prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "map_object",
		"target_id": "door_interaction_smoke",
	})
	_expect_prompt_snapshot(errors, prompt, "door_toggle", "door_toggle", 1.0)
	_expect_prompt_range(errors, prompt, 1, "door prompt")
	var result: Dictionary = simulation.submit_player_command({
		"kind": "interact",
		"target": {
			"target_type": "map_object",
			"target_id": "door_interaction_smoke",
		},
		"topology": {},
	})
	if not bool(result.get("success", false)):
		errors.append("door toggle interaction should succeed: %s" % result.get("reason", "unknown"))
	if not bool(result.get("door_toggled", false)) or not bool(result.get("is_open", false)):
		errors.append("door toggle interaction should report open door")
	if _event_count(simulation.snapshot(), "door_toggled") <= 0:
		errors.append("door toggle should emit door_toggled")
	_expect_interaction_succeeded_payload(errors, simulation.snapshot(), "door_toggle", "door_toggle", "测试门")
	var locked_prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "map_object",
		"target_id": "locked_door_interaction_smoke",
	})
	if not bool(locked_prompt.get("ok", false)):
		errors.append("locked door prompt should still open via inspect placeholder")
	if str(locked_prompt.get("primary_option_id", "")) != "inspect":
		errors.append("locked door primary option should fall back to inspect placeholder")
	_expect_disabled_option(errors, locked_prompt, "door_toggle", "door_locked", "locked door prompt")
	var locked_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "locked_door_interaction_smoke",
	}, "door_toggle")
	if bool(locked_result.get("success", false)) or str(locked_result.get("reason", "")) != "door_locked":
		errors.append("locked door toggle should return door_locked")
	var keyed_prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "map_object",
		"target_id": "keyed_door_interaction_smoke",
	})
	_expect_disabled_option(errors, keyed_prompt, "door_toggle", "door_key_missing", "keyed door prompt without key")
	var keyed_result_missing: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "keyed_door_interaction_smoke",
	}, "door_toggle")
	if bool(keyed_result_missing.get("success", false)) or str(keyed_result_missing.get("reason", "")) != "door_key_missing":
		errors.append("keyed locked door should require key")
	player.inventory["1138"] = 1
	var keyed_prompt_with_key: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "map_object",
		"target_id": "keyed_door_interaction_smoke",
	})
	_expect_prompt_snapshot(errors, keyed_prompt_with_key, "door_toggle", "door_toggle", 1.0)
	var keyed_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "keyed_door_interaction_smoke",
	}, "door_toggle")
	if not bool(keyed_result.get("success", false)) or not bool(keyed_result.get("is_open", false)):
		errors.append("keyed locked door should open with key: %s" % keyed_result.get("reason", "unknown"))
	var tool_result_missing: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "tool_door_interaction_smoke",
	}, "door_toggle")
	if bool(tool_result_missing.get("success", false)) or str(tool_result_missing.get("reason", "")) != "door_tool_missing":
		errors.append("tool locked door should require tool")
	player.inventory["1150"] = 1
	var tool_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "tool_door_interaction_smoke",
	}, "door_toggle")
	if not bool(tool_result.get("success", false)) or not bool(tool_result.get("is_open", false)):
		errors.append("tool locked door should open with tool: %s" % tool_result.get("reason", "unknown"))
	player.inventory["1138"] = 1
	var consume_key_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "consume_key_door_interaction_smoke",
	}, "door_toggle")
	if not bool(consume_key_result.get("success", false)) or not bool(consume_key_result.get("is_open", false)):
		errors.append("consuming key locked door should open with key: %s" % consume_key_result.get("reason", "unknown"))
	if int(player.inventory.get("1138", 0)) != 0:
		errors.append("consuming key locked door should consume one key")
	if not bool(consume_key_result.get("unlock_requirements_consumed", false)):
		errors.append("consuming key locked door should report unlock requirement consumption")
	var consume_key_state: Dictionary = _dictionary_or_empty(simulation.door_states.get("consume_key_door_interaction_smoke", {}))
	if bool(consume_key_state.get("locked", true)) or not bool(consume_key_state.get("unlock_requirements_consumed", false)):
		errors.append("consuming key locked door should persist unlocked state")
	player.inventory["1150"] = 1
	var consume_tool_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "consume_tool_door_interaction_smoke",
	}, "door_toggle")
	if not bool(consume_tool_result.get("success", false)) or not bool(consume_tool_result.get("is_open", false)):
		errors.append("consuming tool locked door should open with tool: %s" % consume_tool_result.get("reason", "unknown"))
	if int(player.inventory.get("1150", 0)) != 0:
		errors.append("consuming tool locked door should consume one tool")
	if _event_count(simulation.snapshot(), "door_unlocked") <= 0 or _event_count(simulation.snapshot(), "unlock_requirement_consumed") <= 0:
		errors.append("consuming locked doors should emit unlock consumption events")
	return errors


func _expect_scene_transition_permissions(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	_configure_transition_permission_targets(simulation)
	var flagged_prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "map_object",
		"target_id": "flagged_transition_smoke",
	})
	_expect_disabled_option(errors, flagged_prompt, "enter_subscene", "scene_transition_world_flag_missing", "flag-gated transition prompt")
	var flagged_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "flagged_transition_smoke",
	}, "enter_subscene")
	if bool(flagged_result.get("success", false)) or str(flagged_result.get("reason", "")) != "scene_transition_world_flag_missing":
		errors.append("flag-gated transition should reject without world flag")
	simulation.world_flags["transition_permission_smoke_flag"] = true
	var flagged_allowed: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "flagged_transition_smoke",
	}, "enter_subscene")
	if not bool(flagged_allowed.get("success", false)):
		errors.append("flag-gated transition should allow after world flag: %s" % flagged_allowed.get("reason", "unknown"))
	_configure_transition_permission_targets(simulation)
	var location_prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "map_object",
		"target_id": "location_transition_smoke",
	})
	_expect_disabled_option(errors, location_prompt, "enter_subscene", "scene_transition_location_locked", "location-gated transition prompt")
	var location_result: Dictionary = simulation.submit_player_command({
		"kind": "interact",
		"target": {
			"target_type": "map_object",
			"target_id": "location_transition_smoke",
		},
		"option_id": "enter_subscene",
	})
	if bool(location_result.get("success", false)) or str(location_result.get("reason", "")) != "scene_transition_location_locked":
		errors.append("location-gated transition should reject without unlocked location")
	var feedback: Array = HudSnapshot.new(registry).build(simulation.snapshot(), {}, {}).get("event_feedback", [])
	var has_localized_feedback := false
	for event in feedback:
		var event_data: Dictionary = _dictionary_or_empty(event)
		if str(event_data.get("text", "")).contains("地点未解锁"):
			has_localized_feedback = true
			break
	if not has_localized_feedback:
		errors.append("HUD feedback should localize scene transition locked location")
	simulation.unlocked_locations.append("transition_permission_smoke_location")
	_configure_transition_permission_targets(simulation)
	var location_allowed: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "location_transition_smoke",
	}, "enter_subscene")
	if not bool(location_allowed.get("success", false)):
		errors.append("location-gated transition should allow after unlock: %s" % location_allowed.get("reason", "unknown"))
	return errors


func _configure_transition_permission_targets(simulation: RefCounted) -> void:
	simulation.configure_map_interactions({
		"flagged_transition_smoke": _transition_target("flagged_transition_smoke", {
			"required_world_flags": ["transition_permission_smoke_flag"],
		}),
		"location_transition_smoke": _transition_target("location_transition_smoke", {
			"required_unlocked_locations": ["transition_permission_smoke_location"],
		}),
	})


func _expect_relationship_dialogue_rules(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var initial_score := float(simulation.relationship_score(1, 2))
	if initial_score < 49.9:
		errors.append("player/trader relationship should initialize from friendly side")
	var trusted_result: Dictionary = simulation.set_relationship_score(1, 2, 75.0, "interaction_smoke_trusted")
	if not bool(trusted_result.get("success", false)) or absf(float(trusted_result.get("score", 0.0)) - 75.0) > 0.001:
		errors.append("relationship score should be settable for trusted dialogue")
	if _event_count(simulation.snapshot(), "relationship_changed") <= 0:
		errors.append("relationship score change should emit relationship_changed")
	simulation.active_quests.clear()
	simulation.completed_quests.clear()
	var trusted_talk: Dictionary = simulation.execute_interaction(1, {
		"target_type": "actor",
		"actor_id": 2,
	}, "talk")
	if not bool(trusted_talk.get("success", false)):
		errors.append("trusted relationship talk should succeed: %s" % trusted_talk.get("reason", "unknown"))
	if str(trusted_talk.get("dialogue_id", "")) != "trader_lao_wang_trusted":
		errors.append("trusted relationship should select trusted dialogue")
	var cold_result: Dictionary = simulation.set_relationship_score(1, 2, -25.0, "interaction_smoke_cold")
	if not bool(cold_result.get("success", false)) or absf(float(cold_result.get("score", 0.0)) + 25.0) > 0.001:
		errors.append("relationship score should be settable for cold dialogue")
	var cold_talk: Dictionary = simulation.execute_interaction(1, {
		"target_type": "actor",
		"actor_id": 2,
	}, "talk")
	if not bool(cold_talk.get("success", false)):
		errors.append("cold relationship talk should succeed: %s" % cold_talk.get("reason", "unknown"))
	if str(cold_talk.get("dialogue_id", "")) != "trader_lao_wang_cold":
		errors.append("cold relationship should select cold dialogue")
	var clamped_result: Dictionary = simulation.set_relationship_score(1, 2, -150.0, "interaction_smoke_clamped")
	if not bool(clamped_result.get("success", false)) or absf(float(clamped_result.get("score", 0.0)) + 100.0) > 0.001:
		errors.append("relationship score should clamp to -100")
	var feedback: Array = HudSnapshot.new(registry).build(simulation.snapshot(), {}, {}).get("event_feedback", [])
	var has_relationship_feedback := false
	for event in feedback:
		var event_data: Dictionary = _dictionary_or_empty(event)
		var feedback_text := str(event_data.get("text", ""))
		if str(event_data.get("kind", "")) == "relationship_changed" and feedback_text.contains("关系:") and feedback_text.contains("-25") and feedback_text.contains("-100") and feedback_text.contains("-75"):
			has_relationship_feedback = true
			break
	if not has_relationship_feedback:
		errors.append("recent event feedback should include localized relationship_changed details")
	return errors


func _door_target(target_id: String, is_open: bool, locked: bool, grid: Dictionary, extra_door: Dictionary = {}) -> Dictionary:
	var door := {
		"door_id": target_id,
		"object_id": target_id,
		"display_name": "测试门",
		"is_open": is_open,
		"locked": locked,
		"blocks_movement": not is_open,
		"blocks_sight": not is_open,
		"blocks_sight_when_closed": true,
	}
	for key in extra_door.keys():
		door[key] = extra_door[key]
	return {
		"target_id": target_id,
		"target_type": "map_object",
		"display_name": "测试门",
		"kind": "door",
		"anchor": grid.duplicate(true),
		"cells": [grid.duplicate(true)],
		"door": door,
	}


func _transition_target(target_id: String, extra: Dictionary = {}) -> Dictionary:
	var target := {
		"target_id": target_id,
		"target_type": "map_object",
		"display_name": "权限切换测试",
		"kind": "enter_subscene",
		"anchor": {"x": 0, "y": 0, "z": 0},
		"cells": [{"x": 0, "y": 0, "z": 0}],
		"target_map_id": "survivor_outpost_01_interior",
		"target_entry_point_id": "default_entry",
	}
	for key in extra.keys():
		target[key] = extra[key]
	return target


func _grid_distance(left: RefCounted, right: RefCounted) -> int:
	if left == null or right == null:
		return 999999
	if left.y != right.y:
		return 999999
	return abs(left.x - right.x) + abs(left.z - right.z)


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
