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

	print("trade_ui_smoke passed:")
	print(JSON.stringify({
		"title": _title_line(game_root),
		"summary": _summary_line(game_root),
		"items": _item_lines(game_root).slice(0, 3),
	}, "\t"))
	quit(0)


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	if game_root.trade_panel == null:
		return ["trade panel was not created"]
	if game_root.trade_panel.visible:
		errors.append("trade panel should be hidden before talking to trader")

	var trader_node: Node = game_root.find_child("Actor_trader_lao_wang_2", true, false)
	if trader_node == null:
		return ["missing generated trader actor node"]
	game_root.select_interaction_node(trader_node)
	var result: Dictionary = game_root.execute_primary_interaction()
	if not bool(result.get("success", false)):
		errors.append("talk execution failed: %s" % result.get("reason", "unknown"))

	if not game_root.trade_panel.visible:
		errors.append("trade panel did not open after trader talk")
	if not _title_line(game_root).contains("废土商人·老王"):
		errors.append("trade title did not use trader display name")
	if not _summary_line(game_root).contains("资金 500"):
		errors.append("trade summary missing shop money")

	var item_text: String = "\n".join(_item_lines(game_root))
	if not item_text.contains("急救包 x1"):
		errors.append("trade items missing medkit")
	if not item_text.contains("绷带 x8"):
		errors.append("trade items missing bandage")
	return errors


func _title_line(game_root: Node) -> String:
	return game_root.trade_panel.get_node("TradePanel/TradeLines/TitleLine").text


func _summary_line(game_root: Node) -> String:
	return game_root.trade_panel.get_node("TradePanel/TradeLines/SummaryLine").text


func _item_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var item_box: Node = game_root.trade_panel.get_node("TradePanel/TradeLines/ItemLines")
	for child in item_box.get_children():
		if child is Label:
			output.append((child as Label).text)
	return output
