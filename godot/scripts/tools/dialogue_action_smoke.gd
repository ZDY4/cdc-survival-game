extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const DialogueSnapshot = preload("res://scripts/ui/snapshots/dialogue_snapshot.gd")
const TradeSnapshot = preload("res://scripts/ui/snapshots/trade_snapshot.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_root: Node = GAME_ROOT_SCENE.instantiate()
	get_root().add_child(game_root)
	await process_frame

	var errors: Array[String] = _run_checks(game_root)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("dialogue_action_smoke passed:")
	print(JSON.stringify({
		"active_quests": _active_quest_ids(game_root),
		"completed_quests": game_root.simulation.snapshot().get("completed_quests", []),
		"unlocked_locations": game_root.simulation.snapshot().get("unlocked_locations", []),
		"trade_visible": game_root.trade_panel.visible,
	}, "\t"))
	quit(0)


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	var trader_node: Node = game_root.find_child("Actor_trader_lao_wang_2", true, false)
	if trader_node == null:
		return ["missing generated trader actor node"]

	_force_tutorial_active_dialogue_state(game_root.simulation)
	game_root.select_interaction_node(trader_node)
	var talk_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(talk_result.get("success", false)):
		errors.append("trader talk failed: %s" % talk_result.get("reason", "unknown"))
	var talk_dialogue_id := _dialogue_id_from_interaction_result(talk_result)
	if talk_dialogue_id != "trader_lao_wang_tutorial_active":
		errors.append("trader talk should resolve tutorial-active dialogue rule, got %s with quests %s / completed %s" % [
			talk_result,
			game_root.simulation.active_quests,
			game_root.simulation.completed_quests,
		])
	var trade_preview: Dictionary = _dialogue_option_preview(game_root, "trade_action")
	_expect_preview_action_sequence(errors, trade_preview, ["open_trade"], "trade", true, "trader trade option")
	var trade_result: Dictionary = game_root.choose_dialogue_option("trade_action")
	if not bool(trade_result.get("success", false)):
		errors.append("trade dialogue option failed: %s" % trade_result.get("reason", "unknown"))
	if trade_result.get("end_type", "") != "trade":
		errors.append("trade dialogue option should finish with trade end_type")
	_expect_actual_matches_preview(errors, trade_preview, trade_result, "trader trade option")
	if not game_root.trade_panel.visible:
		errors.append("trade panel should be visible after open_trade dialogue action")
	game_root.close_trade_panel()
	errors.append_array(_expect_explicit_shop_trade_action(game_root))

	var simulation: RefCounted = game_root.simulation
	simulation.completed_quests["tutorial_survive"] = true
	simulation.completed_quests["zombie_hunter"] = true
	simulation.active_quests.erase("tutorial_survive")
	simulation.active_quests.erase("zombie_hunter")

	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var doctor: RefCounted = _actor_by_definition(simulation, "doctor_chen")
	player.active_dialogue_id = "doctor_chen_find_medicine_offer"
	player.active_dialogue_node_id = ""
	_set_dialogue_target(player, doctor)
	game_root.refresh_dialogue_panel()
	var accept_preview: Dictionary = _dialogue_option_preview(game_root, "accept_job")
	_expect_preview_action_sequence(errors, accept_preview, ["unlock_location", "start_quest"], "", false, "doctor accept option")
	var accept_result: Dictionary = game_root.choose_dialogue_option("accept_job")
	if not bool(accept_result.get("success", false)):
		errors.append("doctor accept option failed: %s" % accept_result.get("reason", "unknown"))
	_expect_actual_matches_preview(errors, accept_preview, accept_result, "doctor accept option")
	_expect_dialogue_action_resolved(errors, game_root, "doctor_chen_find_medicine_offer", "accept_job", ["unlock_location", "start_quest"], "doctor accept option")
	if not simulation.unlocked_locations.has("hospital"):
		errors.append("doctor accept should unlock hospital")
	if not _active_quest_ids(game_root).has("find_medicine"):
		errors.append("doctor accept should start find_medicine")
	if not _dialogue_text(game_root).contains("废弃医院带回 1 份急救包"):
		errors.append("doctor accept should advance to confirmation dialog")

	var find_state: Dictionary = _dictionary_or_empty(simulation.active_quests.get("find_medicine", {})).duplicate(true)
	find_state["completed_objectives"] = {"step_1": 1}
	simulation.active_quests["find_medicine"] = find_state
	var direct_turn_in: Dictionary = simulation.turn_in_quest(1, "find_medicine")
	if bool(direct_turn_in.get("success", false)) or str(direct_turn_in.get("reason", "")) != "turn_in_requires_dialogue":
		errors.append("direct dialogue-gated quest turn-in should be rejected: %s" % direct_turn_in)
	var wrong_dialogue_turn_in: Dictionary = simulation.turn_in_quest(1, "find_medicine", {
		"source": "dialogue",
		"dialogue_id": "doctor_chen_find_medicine_active",
		"target_actor_id": doctor.actor_id if doctor != null else 0,
		"target_definition_id": "doctor_chen",
	})
	if bool(wrong_dialogue_turn_in.get("success", false)) or str(wrong_dialogue_turn_in.get("reason", "")) != "turn_in_dialogue_mismatch":
		errors.append("wrong dialogue id should reject quest turn-in: %s" % wrong_dialogue_turn_in)
	player.inventory.erase("1005")
	player.active_dialogue_id = "doctor_chen_find_medicine_turn_in"
	player.active_dialogue_node_id = ""
	_set_dialogue_target(player, doctor)
	game_root.refresh_dialogue_panel()
	var failed_turn_in_preview: Dictionary = _dialogue_option_preview(game_root, "turn_in_action")
	_expect_preview_action_sequence(errors, failed_turn_in_preview, ["turn_in_quest"], "", false, "doctor failed turn-in option")
	if not _preview_first_action_requires_runtime_validation(failed_turn_in_preview):
		errors.append("doctor failed turn-in preview should flag runtime validation")
	var failed_turn_in_requirement_preview := _turn_in_preview_from_resolution(failed_turn_in_preview)
	if bool(failed_turn_in_requirement_preview.get("ready", true)) or str(failed_turn_in_requirement_preview.get("reason", "")) != "not_enough_items":
		errors.append("doctor failed turn-in preview should expose missing item reason: %s" % failed_turn_in_requirement_preview)
	if not str(failed_turn_in_requirement_preview.get("summary", "")).contains("急救包 0/1"):
		errors.append("doctor failed turn-in preview should expose item count: %s" % failed_turn_in_requirement_preview)
	var failed_turn_in_button: Button = _dialogue_option_button(game_root, 1)
	if failed_turn_in_button == null:
		errors.append("doctor failed turn-in should expose option button")
	elif bool(failed_turn_in_button.get_meta("preview_turn_in_ready", true)) or str(failed_turn_in_button.get_meta("preview_turn_in_reason", "")) != "not_enough_items" or not str(failed_turn_in_button.tooltip_text).contains("急救包 0/1"):
		errors.append("doctor failed turn-in button should expose missing item preview")
	var failed_turn_in_result: Dictionary = game_root.choose_dialogue_option("turn_in_action")
	if bool(failed_turn_in_result.get("success", false)):
		errors.append("doctor turn-in without item should fail")
	if str(failed_turn_in_result.get("reason", "")) != "dialogue_action_failed":
		errors.append("doctor turn-in without item should report dialogue_action_failed")
	var failed_action: Dictionary = _dictionary_or_empty(failed_turn_in_result.get("action_result", {}))
	if str(failed_action.get("reason", "")) != "not_enough_items":
		errors.append("doctor turn-in without item should preserve not_enough_items action reason")
	if not _active_quest_ids(game_root).has("find_medicine"):
		errors.append("failed turn-in should keep find_medicine active")
	if simulation.completed_quests.has("find_medicine"):
		errors.append("failed turn-in should not complete find_medicine")
	if _dialogue_text(game_root).contains("这一趟救了诊所"):
		errors.append("failed turn-in should not advance to confirmation dialog")
	if _event_count(game_root, "dialogue_action_failed") <= 0:
		errors.append("failed turn-in should emit dialogue_action_failed")
	_expect_dialogue_action_resolved(errors, game_root, "doctor_chen_find_medicine_turn_in", "turn_in_action", ["turn_in_quest"], "doctor failed turn-in option", false, "not_enough_items")

	player.inventory["1005"] = 1
	var wrong_target_turn_in: Dictionary = simulation.turn_in_quest(1, "find_medicine", {
		"source": "dialogue",
		"dialogue_id": "doctor_chen_find_medicine_turn_in",
		"target_actor_id": 2,
		"target_definition_id": "trader_lao_wang",
	})
	if bool(wrong_target_turn_in.get("success", false)) or str(wrong_target_turn_in.get("reason", "")) != "turn_in_target_mismatch":
		errors.append("wrong dialogue target should reject quest turn-in: %s" % wrong_target_turn_in)
	player.active_dialogue_id = "doctor_chen_find_medicine_turn_in"
	player.active_dialogue_node_id = "choice_1"
	_set_dialogue_target(player, doctor)
	game_root.refresh_dialogue_panel()
	var turn_in_preview: Dictionary = _dialogue_option_preview(game_root, "turn_in_action")
	_expect_preview_action_sequence(errors, turn_in_preview, ["turn_in_quest"], "", false, "doctor turn-in option")
	var ready_turn_in_requirement_preview := _turn_in_preview_from_resolution(turn_in_preview)
	if not bool(ready_turn_in_requirement_preview.get("ready", false)) or not str(ready_turn_in_requirement_preview.get("reason", "")).is_empty():
		errors.append("doctor turn-in preview should be ready with medkit: %s" % ready_turn_in_requirement_preview)
	if not str(ready_turn_in_requirement_preview.get("summary", "")).contains("急救包 1/1"):
		errors.append("doctor turn-in preview should expose ready item count: %s" % ready_turn_in_requirement_preview)
	var ready_turn_in_button: Button = _dialogue_option_button(game_root, 1)
	if ready_turn_in_button == null:
		errors.append("doctor ready turn-in should expose option button")
	elif not bool(ready_turn_in_button.get_meta("preview_turn_in_ready", false)) or not str(ready_turn_in_button.get_meta("preview_turn_in_summary", "")).contains("急救包 1/1") or not str(ready_turn_in_button.tooltip_text).contains("急救包 1/1"):
		errors.append("doctor ready turn-in button should expose ready item preview")
	var turn_in_result: Dictionary = game_root.choose_dialogue_option("turn_in_action")
	if not bool(turn_in_result.get("success", false)):
		errors.append("doctor turn-in option failed: %s" % turn_in_result.get("reason", "unknown"))
	_expect_actual_matches_preview(errors, turn_in_preview, turn_in_result, "doctor turn-in option")
	_expect_dialogue_action_resolved(errors, game_root, "doctor_chen_find_medicine_turn_in", "turn_in_action", ["turn_in_quest"], "doctor turn-in option")
	if int(player.inventory.get("1005", 0)) != 0:
		errors.append("turn-in should consume medkit")
	if _active_quest_ids(game_root).has("find_medicine"):
		errors.append("find_medicine should complete after turn-in")
	if not simulation.completed_quests.has("find_medicine"):
		errors.append("find_medicine missing from completed quests")
	if not _dialogue_text(game_root).contains("这一趟救了诊所"):
		errors.append("turn-in should advance to confirmation dialog")
	errors.append_array(_expect_scripted_state_actions(game_root))
	return errors


func _force_tutorial_active_dialogue_state(simulation: RefCounted) -> void:
	for quest_id in ["factory_spare_power", "find_medicine", "zombie_hunter", "tutorial_survive"]:
		simulation.active_quests.erase(quest_id)
		simulation.completed_quests.erase(quest_id)
	simulation.active_quests["tutorial_survive"] = {
		"quest_id": "tutorial_survive",
		"current_node_id": "step_1",
		"completed_objectives": {},
	}


func _dialogue_option_preview(game_root: Node, next_node_id: String) -> Dictionary:
	var snapshot: Dictionary = DialogueSnapshot.new(game_root.registry).build(game_root.simulation.snapshot())
	for option in _array_or_empty(snapshot.get("options", [])):
		var option_data: Dictionary = _dictionary_or_empty(option)
		if str(option_data.get("next", "")) == next_node_id or str(option_data.get("id", "")) == next_node_id:
			return _dictionary_or_empty(option_data.get("resolution_preview", {}))
	return {}


func _expect_preview_action_sequence(errors: Array[String], preview: Dictionary, expected_actions: Array[String], expected_end_type: String, expected_finished: bool, context: String) -> void:
	if preview.is_empty() or not bool(preview.get("ok", false)):
		errors.append("%s preview should resolve successfully: %s" % [context, preview])
		return
	var action_types := _string_array(_array_or_empty(preview.get("action_types", [])))
	if action_types != expected_actions:
		errors.append("%s preview action types expected %s, got %s" % [context, expected_actions, action_types])
	if bool(preview.get("will_finish", false)) != expected_finished:
		errors.append("%s preview finished flag mismatch: %s" % [context, preview])
	if expected_end_type != "" and str(preview.get("end_type", "")) != expected_end_type:
		errors.append("%s preview end_type expected %s, got %s" % [context, expected_end_type, preview])


func _expect_actual_matches_preview(errors: Array[String], preview: Dictionary, result: Dictionary, context: String) -> void:
	var resolved_result := _dialogue_resolution_result(result)
	var preview_actions := _string_array(_array_or_empty(preview.get("action_types", [])))
	var result_actions: Array[String] = []
	for action_result in _array_or_empty(resolved_result.get("emitted_actions", [])):
		var action_data: Dictionary = _dictionary_or_empty(action_result)
		result_actions.append(str(action_data.get("type", "")))
	if result_actions != preview_actions:
		errors.append("%s actual action types should match preview %s, got %s" % [context, preview_actions, result_actions])
	if bool(preview.get("will_finish", false)) and str(resolved_result.get("end_type", "")) != str(preview.get("end_type", "")):
		errors.append("%s actual end_type should match preview: %s vs %s" % [context, resolved_result, preview])
	if not bool(preview.get("will_finish", false)) and str(resolved_result.get("node_id", "")) != str(preview.get("next_node_id", "")):
		errors.append("%s actual next node should match preview: %s vs %s" % [context, resolved_result, preview])


func _expect_dialogue_action_resolved(errors: Array[String], game_root: Node, dialogue_id: String, node_id: String, expected_actions: Array[String], context: String, expected_success: bool = true, expected_reason: String = "") -> void:
	var events: Array = _events_by_kind(game_root, "dialogue_action_resolved")
	var matched_actions: Array[String] = []
	for event_index in range(events.size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(events[event_index])
		var event_data: Dictionary = _dictionary_or_empty(event)
		var payload: Dictionary = _dictionary_or_empty(event_data.get("payload", {}))
		if str(payload.get("dialogue_id", "")) != dialogue_id or str(payload.get("node_id", "")) != node_id:
			continue
		var action_type := str(payload.get("action_type", ""))
		if not expected_actions.has(action_type) or matched_actions.has(action_type):
			continue
		matched_actions.append(action_type)
		if bool(payload.get("success", false)) != expected_success:
			errors.append("%s resolved event success mismatch for %s: %s" % [context, action_type, payload])
		if expected_reason != "" and str(payload.get("reason", "")) != expected_reason:
			errors.append("%s resolved event reason mismatch for %s: %s" % [context, action_type, payload])
		var summary: Dictionary = _dictionary_or_empty(payload.get("action_summary", {}))
		if str(summary.get("type", "")) != action_type:
			errors.append("%s resolved event should expose action summary type: %s" % [context, payload])
		if _dictionary_or_empty(payload.get("action_result", {})).is_empty():
			errors.append("%s resolved event should include action_result: %s" % [context, payload])
	matched_actions.sort()
	var expected_sorted := expected_actions.duplicate()
	expected_sorted.sort()
	if matched_actions != expected_sorted:
		errors.append("%s should emit dialogue_action_resolved for %s, got %s" % [context, expected_sorted, matched_actions])


func _preview_first_action_requires_runtime_validation(preview: Dictionary) -> bool:
	var actions: Array = _array_or_empty(preview.get("action_previews", []))
	if actions.is_empty():
		return false
	return bool(_dictionary_or_empty(actions[0]).get("requires_runtime_validation", false))


func _turn_in_preview_from_resolution(preview: Dictionary) -> Dictionary:
	for action in _array_or_empty(preview.get("action_previews", [])):
		var action_data := _dictionary_or_empty(action)
		var turn_in_preview := _dictionary_or_empty(action_data.get("turn_in_preview", {}))
		if not turn_in_preview.is_empty():
			return turn_in_preview
	return {}


func _execute_primary_and_complete(game_root: Node, max_waits: int = 16) -> Dictionary:
	var result: Dictionary = game_root.execute_primary_interaction()
	var waits := 0
	while waits < max_waits and _has_pending(game_root) and not _final_interaction_result(result):
		waits += 1
		var wait_result: Dictionary = game_root.simulation.submit_player_command({
			"kind": "wait",
			"topology": game_root.world_result.get("map", {}),
		})
		var pending_result: Dictionary = wait_result.get("pending_result", {})
		result = pending_result if not pending_result.is_empty() else wait_result
		_refresh_runtime_world(game_root, result)
	return result


func _refresh_runtime_world(game_root: Node, result: Dictionary) -> void:
	var rebuilt: Dictionary = WorldSnapshotBuilder.new(game_root.registry).build_from_runtime_snapshot(game_root.simulation.snapshot())
	if bool(rebuilt.get("ok", false)):
		game_root.world_result = rebuilt
		game_root.interaction_controller.world_result = rebuilt
		game_root.simulation.configure_map_interactions(rebuilt.get("map", {}).get("interaction_targets", {}))
	game_root._setup_world_container()
	WorldSceneRenderer.new().render_world(game_root.world_container, game_root.world_result)
	game_root._setup_runtime_input_controller()
	game_root._refresh_fog_overlay()
	game_root._setup_panels()
	game_root.refresh_all_panels(result.get("prompt", {}))


func _has_pending(game_root: Node) -> bool:
	var snapshot: Dictionary = game_root.simulation.snapshot()
	return not snapshot.get("pending_movement", {}).is_empty() or not snapshot.get("pending_interaction", {}).is_empty()


func _final_interaction_result(result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		return true
	return bool(result.get("consumed_target", false)) \
		or not _dialogue_id_from_interaction_result(result).is_empty() \
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


func _dialogue_id_from_interaction_result(result: Dictionary) -> String:
	var dialogue_id := str(result.get("dialogue_id", ""))
	if not dialogue_id.is_empty():
		return dialogue_id
	for key in ["result", "pending_result", "auto_turn_final_result"]:
		var nested := _dictionary_or_empty(result.get(key, {}))
		if nested.is_empty():
			continue
		var nested_dialogue_id := _dialogue_id_from_interaction_result(nested)
		if not nested_dialogue_id.is_empty():
			return nested_dialogue_id
	return ""


func _dialogue_resolution_result(result: Dictionary) -> Dictionary:
	if result.has("emitted_actions") or result.has("end_type") or result.has("node_id") or result.has("action_result"):
		return result
	for key in ["result", "pending_result", "auto_turn_final_result"]:
		var nested := _dictionary_or_empty(result.get(key, {}))
		if nested.is_empty():
			continue
		var resolved := _dialogue_resolution_result(nested)
		if not resolved.is_empty():
			return resolved
	return result


func _active_quest_ids(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	for quest in game_root.simulation.snapshot().get("active_quests", []):
		var quest_data: Dictionary = quest
		output.append(str(quest_data.get("quest_id", "")))
	return output


func _dialogue_text(game_root: Node) -> String:
	var label: Label = game_root.dialogue_panel.find_child("TextLine", true, false) as Label
	if label == null:
		return ""
	return label.text


func _dialogue_option_button(game_root: Node, index: int) -> Button:
	return game_root.dialogue_panel.find_child("DialogueOption_%d" % index, true, false) as Button


func _expect_scripted_state_actions(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	_install_scripted_dialogue(game_root)
	var simulation: RefCounted = game_root.simulation
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.active_dialogue_id = "dialogue_action_smoke_scripted"
	player.active_dialogue_node_id = ""
	var score_before := float(simulation.relationship_score(1, 2))
	var bandage_before: int = int(player.inventory.get("1006", 0))
	var ammo_before: int = int(player.inventory.get("1007", 0))
	var money_before: int = player.money
	var progression_before: Dictionary = _dictionary_or_empty(player.progression).duplicate(true)
	game_root.refresh_dialogue_panel()
	var result: Dictionary = game_root.choose_dialogue_option("apply_scripted")
	if not bool(result.get("success", false)):
		errors.append("scripted dialogue action option failed: %s" % result.get("reason", "unknown"))
	if not simulation.world_flags.has("dialogue_action_smoke_flag"):
		errors.append("set_world_flag dialogue action should set runtime world flag")
	if absf(float(simulation.relationship_score(1, 2)) - (score_before + 12.0)) > 0.001:
		errors.append("change_relationship dialogue action should adjust player/trader relationship")
	if int(player.inventory.get("1006", 0)) != bandage_before + 1:
		errors.append("give_item dialogue action should add one bandage")
	if int(player.inventory.get("1007", 0)) != ammo_before + 2:
		errors.append("give_reward dialogue action should add reward items")
	if player.money != money_before + 7:
		errors.append("give_reward dialogue action should add reward money")
	if int(_dictionary_or_empty(player.progression).get("total_xp_earned", 0)) < int(progression_before.get("total_xp_earned", 0)) + 10:
		errors.append("give_reward dialogue action should grant experience")
	if int(_dictionary_or_empty(player.progression).get("available_skill_points", 0)) < int(progression_before.get("available_skill_points", 0)) + 1:
		errors.append("give_reward dialogue action should grant skill points")
	if _event_count(game_root, "world_flag_changed") <= 0:
		errors.append("set_world_flag dialogue action should emit world_flag_changed")
	if _event_count(game_root, "relationship_changed") <= 0:
		errors.append("change_relationship dialogue action should emit relationship_changed")
	if _event_count(game_root, "dialogue_item_granted") <= 0:
		errors.append("give_item dialogue action should emit dialogue_item_granted")
	if _event_count(game_root, "dialogue_reward_granted") <= 0:
		errors.append("give_reward dialogue action should emit dialogue_reward_granted")
	if _array_or_empty(result.get("emitted_actions", [])).size() != 4:
		errors.append("scripted dialogue action result should expose emitted action results")
	_expect_dialogue_action_resolved(errors, game_root, "dialogue_action_smoke_scripted", "scripted_actions", ["set_world_flag", "change_relationship", "give_item", "give_reward"], "scripted dialogue actions")
	if not _dialogue_text(game_root).contains("状态已经记录"):
		errors.append("scripted dialogue actions should advance to confirmation dialog")
	return errors


func _expect_explicit_shop_trade_action(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	_install_explicit_shop_trade_dialogue(game_root)
	game_root.active_trade_target = {}
	game_root.close_trade_panel()
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	player.active_dialogue_id = "dialogue_action_smoke_explicit_shop_trade"
	player.active_dialogue_node_id = ""
	game_root.refresh_dialogue_panel()
	var result: Dictionary = game_root.choose_dialogue_option("open_explicit_shop")
	if not bool(result.get("success", false)):
		errors.append("explicit shop trade dialogue action failed: %s" % result.get("reason", "unknown"))
	if str(result.get("end_type", "")) != "trade":
		errors.append("explicit shop trade action should finish as trade")
	if str(game_root.active_trade_target.get("target_type", "")) != "shop":
		errors.append("explicit shop trade should use shop target")
	if str(game_root.active_trade_target.get("shop_id", "")) != "trader_lao_wang_shop":
		errors.append("explicit shop trade should preserve shop id target")
	var session: Dictionary = TradeSnapshot.new(game_root.registry).resolve_trade_session(game_root.simulation.snapshot(), game_root.active_trade_target)
	if str(session.get("shop_id", "")) != "trader_lao_wang_shop":
		errors.append("trade snapshot should resolve explicit shop id")
	if not game_root.trade_panel.visible:
		errors.append("explicit shop trade should open trade panel")
	game_root.close_trade_panel()
	return errors


func _install_scripted_dialogue(game_root: Node) -> void:
	var dialogue_library: Dictionary = game_root.registry.libraries.get("dialogues", {})
	dialogue_library["dialogue_action_smoke_scripted"] = {
		"path": "res://scripts/tools/dialogue_action_smoke.gd",
		"data": {
			"dialog_id": "dialogue_action_smoke_scripted",
			"nodes": [
				{
					"id": "start",
					"type": "dialog",
					"speaker": "Smoke",
					"text": "准备执行脚本化动作。",
					"is_start": true,
					"next": "choice_1",
				},
				{
					"id": "choice_1",
					"type": "choice",
					"options": [
						{
							"id": "apply_scripted",
							"text": "记录状态",
							"next": "scripted_actions",
						},
					],
				},
				{
					"id": "scripted_actions",
					"type": "action",
					"actions": [
						{
							"type": "set_world_flag",
							"flag_id": "dialogue_action_smoke_flag",
						},
						{
							"type": "change_relationship",
							"target_definition_id": "trader_lao_wang",
							"delta": 12,
						},
						{
							"type": "give_item",
							"item_id": "1006",
							"count": 1,
						},
						{
							"type": "give_reward",
							"rewards": {
								"items": [
									{
										"id": "1007",
										"count": 2,
									},
								],
								"money": 7,
								"experience": 10,
								"skill_points": 1,
							},
						},
					],
					"next": "confirm",
				},
				{
					"id": "confirm",
					"type": "dialog",
					"speaker": "Smoke",
					"text": "状态已经记录。",
					"next": "done",
				},
				{
					"id": "done",
					"type": "end",
					"end_type": "leave",
				},
			],
		},
	}
	game_root.registry.libraries["dialogues"] = dialogue_library


func _install_explicit_shop_trade_dialogue(game_root: Node) -> void:
	var dialogue_library: Dictionary = game_root.registry.libraries.get("dialogues", {})
	dialogue_library["dialogue_action_smoke_explicit_shop_trade"] = {
		"path": "res://scripts/tools/dialogue_action_smoke.gd",
		"data": {
			"dialog_id": "dialogue_action_smoke_explicit_shop_trade",
			"nodes": [
				{
					"id": "start",
					"type": "dialog",
					"speaker": "Smoke",
					"text": "准备打开指定商店。",
					"is_start": true,
					"next": "choice_1",
				},
				{
					"id": "choice_1",
					"type": "choice",
					"options": [
						{
							"id": "open_explicit_shop",
							"text": "打开老王商店",
							"next": "trade_action",
						},
					],
				},
				{
					"id": "trade_action",
					"type": "action",
					"actions": [
						{
							"type": "open_trade",
							"shop_id": "trader_lao_wang_shop",
						},
					],
					"next": "trade_end",
				},
				{
					"id": "trade_end",
					"type": "end",
					"end_type": "trade",
				},
			],
		},
	}
	game_root.registry.libraries["dialogues"] = dialogue_library


func _event_count(game_root: Node, kind: String) -> int:
	var count := 0
	for event in game_root.simulation.snapshot().get("events", []):
		var event_data: Dictionary = event
		if str(event_data.get("kind", "")) == kind:
			count += 1
	return count


func _events_by_kind(game_root: Node, kind: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for event in game_root.simulation.snapshot().get("events", []):
		var event_data: Dictionary = _dictionary_or_empty(event)
		if str(event_data.get("kind", "")) == kind:
			output.append(event_data)
	return output


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _string_array(values: Array) -> Array[String]:
	var output: Array[String] = []
	for value in values:
		output.append(str(value))
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _actor_by_definition(simulation: RefCounted, definition_id: String) -> RefCounted:
	for actor in simulation.actor_registry.actors():
		if actor.definition_id == definition_id:
			return actor
	return null


func _set_dialogue_target(player: RefCounted, target: RefCounted) -> void:
	if player == null:
		return
	player.active_dialogue_target_actor_id = target.actor_id if target != null else 0
	player.active_dialogue_target_definition_id = target.definition_id if target != null else ""
