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

	var buy_result: Dictionary = game_root.buy_active_trade_item("1006", 1)
	if not bool(buy_result.get("success", false)):
		errors.append("trade buy failed: %s" % buy_result.get("reason", "unknown"))
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()
	if _player_inventory_count(game_root, "1006") != 2:
		errors.append("trade buy did not add bandage to player")
	if _player_money(game_root) != 76:
		errors.append("trade buy did not spend player money")
	if not _summary_line(game_root).contains("资金 524"):
		errors.append("trade summary did not update shop money after buy")
	if not "\n".join(_item_lines(game_root)).contains("绷带 x7"):
		errors.append("trade items did not reduce shop bandage stock")

	var sell_result: Dictionary = game_root.sell_active_trade_item("1006", 1)
	if not bool(sell_result.get("success", false)):
		errors.append("trade sell failed: %s" % sell_result.get("reason", "unknown"))
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()
	if _player_inventory_count(game_root, "1006") != 1:
		errors.append("trade sell did not remove bandage from player")
	if _player_money(game_root) != 92:
		errors.append("trade sell did not pay player money")
	if not _summary_line(game_root).contains("资金 508"):
		errors.append("trade summary did not update shop money after sell")
	_press_close_button(game_root)
	if game_root.trade_panel.visible:
		errors.append("close button should close trade panel")
	if not game_root.active_trade_target.is_empty():
		errors.append("close button should clear active trade target")
	_reopen_trade(game_root, errors)
	_press_key(game_root, KEY_ESCAPE)
	if game_root.trade_panel.visible:
		errors.append("Esc should close trade panel")
	if not game_root.active_trade_target.is_empty():
		errors.append("Esc should clear active trade target")
	_reopen_trade(game_root, errors)
	game_root.simulation.actor_registry.unregister_actor(2)
	game_root.refresh_trade_panel()
	if game_root.trade_panel.visible:
		errors.append("missing trade target should close trade panel")
	if not game_root.active_trade_target.is_empty():
		errors.append("missing trade target should clear active trade target")
	return errors


func _press_key(game_root: Node, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	game_root.runtime_input_controller.input(event)
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	game_root.runtime_input_controller.input(event)


func _press_close_button(game_root: Node) -> void:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CloseButton")
	if button is Button:
		(button as Button).pressed.emit()


func _reopen_trade(game_root: Node, errors: Array[String]) -> void:
	var trader_node: Node = game_root.find_child("Actor_trader_lao_wang_2", true, false)
	if trader_node == null:
		errors.append("missing trader actor node for trade reopen")
		return
	game_root.select_interaction_node(trader_node)
	var result: Dictionary = game_root.execute_primary_interaction()
	if not bool(result.get("success", false)):
		errors.append("trade reopen failed: %s" % result.get("reason", "unknown"))
	if not game_root.trade_panel.visible:
		errors.append("trade panel should reopen for Esc close check")


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


func _player_inventory_count(game_root: Node, item_id: String) -> int:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			var inventory: Dictionary = actor_data.get("inventory", {})
			return int(inventory.get(item_id, 0))
	return 0


func _player_money(game_root: Node) -> int:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return int(actor_data.get("money", 0))
	return 0
