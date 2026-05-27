extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")


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
	var talk_result: Dictionary = game_root.execute_primary_interaction()
	if not bool(talk_result.get("success", false)):
		errors.append("trader talk failed: %s" % talk_result.get("reason", "unknown"))
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


func _active_quest_ids(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	for quest in game_root.simulation.snapshot().get("active_quests", []):
		var quest_data: Dictionary = quest
		output.append(str(quest_data.get("quest_id", "")))
	return output


func _dialogue_text(game_root: Node) -> String:
	return game_root.dialogue_panel.get_node("DialoguePanel/DialogueLines/TextLine").text
