extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
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

	game_root.select_interaction_node(trader_node)
	var talk_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(talk_result.get("success", false)):
		errors.append("trader talk failed: %s" % talk_result.get("reason", "unknown"))
	if str(talk_result.get("dialogue_id", "")) != "trader_lao_wang_tutorial_active":
		errors.append("trader talk should resolve tutorial-active dialogue rule")
	var trade_result: Dictionary = game_root.choose_dialogue_option("trade_action")
	if not bool(trade_result.get("success", false)):
		errors.append("trade dialogue option failed: %s" % trade_result.get("reason", "unknown"))
	if trade_result.get("end_type", "") != "trade":
		errors.append("trade dialogue option should finish with trade end_type")
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
	var accept_result: Dictionary = game_root.choose_dialogue_option("accept_job")
	if not bool(accept_result.get("success", false)):
		errors.append("doctor accept option failed: %s" % accept_result.get("reason", "unknown"))
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
	var turn_in_result: Dictionary = game_root.choose_dialogue_option("turn_in_action")
	if not bool(turn_in_result.get("success", false)):
		errors.append("doctor turn-in option failed: %s" % turn_in_result.get("reason", "unknown"))
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


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


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
