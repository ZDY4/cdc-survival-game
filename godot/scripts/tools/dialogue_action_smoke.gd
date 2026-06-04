extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
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

	var simulation: RefCounted = game_root.simulation
	simulation.completed_quests["tutorial_survive"] = true
	simulation.completed_quests["zombie_hunter"] = true
	simulation.active_quests.erase("tutorial_survive")
	simulation.active_quests.erase("zombie_hunter")

	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.active_dialogue_id = "doctor_chen_find_medicine_offer"
	player.active_dialogue_node_id = ""
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

	player.inventory["1005"] = 1
	simulation.record_item_collected(1, "1005", 1)
	player.active_dialogue_id = "doctor_chen_find_medicine_turn_in"
	player.active_dialogue_node_id = ""
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
	return game_root.dialogue_panel.get_node("DialoguePanel/DialogueLines/TextLine").text
