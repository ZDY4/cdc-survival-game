extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_root: Node = GAME_ROOT_SCENE.instantiate()
	get_root().add_child(game_root)
	await process_frame

	var errors: Array[String] = await _run_checks(game_root)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("journal_ui_smoke passed:")
	print(JSON.stringify({
		"summary": _summary_line(game_root),
		"quests": _quest_lines(game_root),
	}, "\t"))
	quit(0)


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	if game_root.journal_panel == null:
		return ["journal panel was not created"]
	if not _summary_line(game_root).contains("任务 1"):
		errors.append("journal summary should show one active quest")
	if not _quest_text(game_root).contains("补给试跑"):
		errors.append("journal missing tutorial quest title")
	if not _quest_text(game_root).contains("进度: 0/2"):
		errors.append("journal missing initial objective progress")
	if not _detail_text(game_root).contains("老王让你去据点外警戒区"):
		errors.append("journal detail should show selected quest description")
	if not _detail_text(game_root).contains("需求: 罐头食品 x2"):
		errors.append("journal detail should show objective requirement")
	var track_button: Button = _track_button(game_root)
	if track_button == null or track_button.disabled:
		errors.append("journal should expose enabled track button for selected quest")
	else:
		track_button.pressed.emit()
		await process_frame
		if not _quest_title_text(game_root, "tutorial_survive").begins_with("* "):
			errors.append("tracking quest should mark quest title")
		if _track_button(game_root) == null or str(_track_button(game_root).text) != "取消追踪":
			errors.append("tracking selected quest should switch track button text")
		if not _hud_quest_line(game_root).contains("补给试跑") or not _hud_quest_line(game_root).contains("0/2"):
			errors.append("tracking selected quest should update HUD quest line")
		_track_button(game_root).pressed.emit()
		await process_frame
		if _quest_title_text(game_root, "tutorial_survive").begins_with("* "):
			errors.append("pressing track again should clear tracked marker")
		if not _hud_quest_line(game_root).contains("Quest none"):
			errors.append("clearing tracked quest should clear HUD quest line")

	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	player.inventory["1007"] = 1
	game_root.simulation.record_item_collected(1, "1007", 1)
	game_root.refresh_journal_panel()
	if not _quest_text(game_root).contains("进度: 1/2"):
		errors.append("journal did not refresh collect progress")

	player.inventory["1007"] = 2
	game_root.simulation.record_item_collected(1, "1007", 1)
	game_root.refresh_journal_panel()
	if not _summary_line(game_root).contains("已完成 1"):
		errors.append("journal summary did not count completed quest")
	if not _quest_text(game_root).contains("警戒区清剿"):
		errors.append("journal did not show next quest after prerequisite completion")
	if not _completed_quest_text(game_root).contains("补给试跑 | 已完成"):
		errors.append("journal should list completed tutorial quest")
	if not _press_completed_quest(game_root, "tutorial_survive"):
		errors.append("should select completed tutorial quest")
	await process_frame
	if not _detail_text(game_root).contains("详情: 补给试跑（已完成）"):
		errors.append("completed quest detail should show completed title")
	if not _detail_text(game_root).contains("进度: 2/2 | 已完成"):
		errors.append("completed quest detail should show finished progress")
	if _track_button(game_root) == null or not _track_button(game_root).disabled:
		errors.append("completed quest detail should disable tracking")
	_setup_manual_turn_in_quest(game_root)
	if not _quest_text(game_root).contains("医院取药"):
		errors.append("journal missing manual turn-in quest")
	if not _press_quest_title(game_root, "find_medicine"):
		errors.append("should select manual turn-in quest title")
	await process_frame
	if not _detail_text(game_root).contains("需要完成目标后手动交付"):
		errors.append("manual quest detail should explain turn-in requirement")
	if not _quest_text(game_root).contains("技能点 1"):
		errors.append("journal missing manual quest skill point reward preview")
	if _turn_in_button(game_root, "find_medicine") == null or not _turn_in_button(game_root, "find_medicine").disabled:
		errors.append("manual turn-in button should be disabled before objective completion")

	player.inventory["1005"] = 1
	game_root.simulation.record_item_collected(1, "1005", 1)
	game_root.refresh_journal_panel()
	if not _press_quest_title(game_root, "find_medicine"):
		errors.append("should reselect manual turn-in quest after progress refresh")
	await process_frame
	if not _quest_text(game_root).contains("可交付"):
		errors.append("manual quest should show ready status after objective completion")
	if not _detail_text(game_root).contains("交付: 可交付"):
		errors.append("manual quest detail should show ready turn-in state")
	if _turn_in_button(game_root, "find_medicine") == null or _turn_in_button(game_root, "find_medicine").disabled:
		errors.append("manual turn-in button should be enabled after objective completion")
	_turn_in_button(game_root, "find_medicine").pressed.emit()
	await process_frame
	if _quest_text(game_root).contains("医院取药"):
		errors.append("manual quest should leave active journal after turn-in")
	if not _completed_quest_text(game_root).contains("医院取药 | 已完成"):
		errors.append("manual quest should appear in completed history after turn-in")
	if not game_root.simulation.snapshot().get("completed_quests", []).has("find_medicine"):
		errors.append("manual quest should be completed after journal turn-in")
	if _player_inventory_count(game_root, "1005") != 0:
		errors.append("journal turn-in should consume quest item")
	if _player_skill_points(game_root) <= 0:
		errors.append("journal turn-in should grant skill point reward")
	if not _event_seen(game_root, "quest_completed"):
		errors.append("journal turn-in should emit quest_completed")
	return errors


func _setup_manual_turn_in_quest(game_root: Node) -> void:
	var simulation: RefCounted = game_root.simulation
	simulation.active_quests.clear()
	simulation.completed_quests.clear()
	simulation.completed_quests["tutorial_survive"] = true
	simulation.completed_quests["zombie_hunter"] = true
	simulation.start_quest(1, "find_medicine")
	game_root.refresh_journal_panel()


func _summary_line(game_root: Node) -> String:
	return game_root.journal_panel.get_node("JournalPanel/JournalLines/SummaryLine").text


func _quest_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var quest_box: Node = game_root.journal_panel.get_node("JournalPanel/JournalLines/QuestLines")
	for child in quest_box.get_children():
		if child is Button:
			output.append((child as Button).text)
		elif child is Label:
			output.append((child as Label).text)
		elif child is HBoxContainer:
			var line: Label = child.get_node("Line")
			output.append(line.text)
	return output


func _quest_text(game_root: Node) -> String:
	return "\n".join(_quest_lines(game_root))


func _completed_quest_text(game_root: Node) -> String:
	return "\n".join(_completed_quest_lines(game_root))


func _turn_in_button(game_root: Node, quest_id: String) -> Button:
	var row: Node = game_root.journal_panel.find_child("Reward_%s" % quest_id, true, false)
	if row == null:
		return null
	return row.get_node("TurnInButton") as Button


func _track_button(game_root: Node) -> Button:
	return game_root.journal_panel.find_child("TrackQuestButton", true, false) as Button


func _detail_text(game_root: Node) -> String:
	var title: Node = game_root.journal_panel.find_child("DetailTitleLine", true, false)
	var body: Node = game_root.journal_panel.find_child("DetailBodyLine", true, false)
	var parts: Array[String] = []
	if title is Label:
		parts.append((title as Label).text)
	if body is Label:
		parts.append((body as Label).text)
	return "\n".join(parts)


func _hud_quest_line(game_root: Node) -> String:
	var label: Label = game_root.hud.get_node("HudPanel/HudLines/QuestLine") as Label
	return "" if label == null else label.text


func _quest_title_text(game_root: Node, quest_id: String) -> String:
	var button: Button = _quest_title_button(game_root, quest_id)
	return "" if button == null else str(button.text)


func _press_quest_title(game_root: Node, quest_id: String) -> bool:
	var button: Button = _quest_title_button(game_root, quest_id)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _quest_title_button(game_root: Node, quest_id: String) -> Button:
	return game_root.journal_panel.find_child("Quest_%s" % quest_id, true, false) as Button


func _completed_quest_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var quest_box: Node = game_root.journal_panel.get_node("JournalPanel/JournalLines/CompletedQuestLines")
	for child in quest_box.get_children():
		if child is Button:
			output.append((child as Button).text)
		elif child is Label:
			output.append((child as Label).text)
	return output


func _press_completed_quest(game_root: Node, quest_id: String) -> bool:
	var button: Button = game_root.journal_panel.find_child("CompletedQuest_%s" % quest_id, true, false) as Button
	if button == null:
		return false
	button.pressed.emit()
	return true


func _player_inventory_count(game_root: Node, item_id: String) -> int:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return int(actor_data.get("inventory", {}).get(item_id, 0))
	return 0


func _player_skill_points(game_root: Node) -> int:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return int(actor_data.get("progression", {}).get("available_skill_points", 0))
	return 0


func _event_seen(game_root: Node, kind: String) -> bool:
	for event in game_root.simulation.snapshot().get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			return true
	return false
