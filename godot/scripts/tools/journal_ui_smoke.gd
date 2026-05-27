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
	return errors


func _summary_line(game_root: Node) -> String:
	return game_root.journal_panel.get_node("JournalPanel/JournalLines/SummaryLine").text


func _quest_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var quest_box: Node = game_root.journal_panel.get_node("JournalPanel/JournalLines/QuestLines")
	for child in quest_box.get_children():
		if child is Label:
			output.append((child as Label).text)
	return output


func _quest_text(game_root: Node) -> String:
	return "\n".join(_quest_lines(game_root))
