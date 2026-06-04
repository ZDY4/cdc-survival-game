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
	if not _player_item_text(game_root).contains("绷带 x1"):
		errors.append("trade player column missing player inventory")
	if not _player_item_text(game_root).contains("主手 小刀 x1"):
		errors.append("trade player column missing equipped main hand item")
	if not _detail_line(game_root).contains("店铺：") or not _detail_line(game_root).contains("单价"):
		errors.append("trade detail should default to selected shop item")
	if not _press_trade_item_with_text(game_root, "player", "绷带"):
		errors.append("should select player bandage in trade panel")
	if _trade_button_text(game_root) != "出售":
		errors.append("selecting player item should set trade action to sell")
	_set_item_sellable(game_root, "1006", false)
	game_root.refresh_trade_panel()
	if not _player_item_text(game_root).contains("绷带 x1") or not _player_item_text(game_root).contains("不可出售"):
		errors.append("non-sellable player item should show disabled reason")
	if not _press_trade_item_with_text(game_root, "player", "绷带"):
		errors.append("should select non-sellable player bandage in trade panel")
	if not _trade_button_disabled(game_root):
		errors.append("non-sellable player item should disable direct sell")
	if not _queue_button_disabled(game_root):
		errors.append("non-sellable player item should disable trade cart queue")
	_press_queue_button(game_root)
	if not _cart_line(game_root).contains("购物车为空"):
		errors.append("non-sellable player item should not enter trade cart")
	if not _drop_trade_item_with_text(game_root, "player", "绷带"):
		errors.append("should attempt dragging non-sellable player bandage")
	if not _cart_line(game_root).contains("购物车为空"):
		errors.append("dragged non-sellable player item should not enter trade cart")
	var not_sellable_result: Dictionary = game_root.sell_active_trade_item("1006", 1)
	if str(not_sellable_result.get("reason", "")) != "item_not_sellable":
		errors.append("non-sellable direct sell should report item_not_sellable")
	if not _trade_feedback(game_root).contains("不可出售"):
		errors.append("non-sellable direct sell should show feedback")
	var not_sellable_cart_result: Dictionary = game_root.confirm_active_trade_cart([{
		"source": "player",
		"item_id": "1006",
		"count": 1,
	}])
	if str(not_sellable_cart_result.get("reason", "")) != "item_not_sellable":
		errors.append("non-sellable cart sell should report item_not_sellable")
	if not _trade_feedback(game_root).contains("不可出售"):
		errors.append("non-sellable cart sell should show feedback")
	_clear_item_sellable_override(game_root, "1006")
	game_root.refresh_trade_panel()

	if not _press_trade_item_with_text(game_root, "shop", "绷带"):
		errors.append("should select shop bandage in trade panel")
	if _trade_button_text(game_root) != "购买":
		errors.append("selecting shop item should set trade action to buy")
	_set_trade_quantity(game_root, 1)
	var money_before_cart := _player_money(game_root)
	var bandage_before_cart := _player_inventory_count(game_root, "1006")
	_press_queue_button(game_root)
	if not _cart_line(game_root).contains("购买 绷带 x1"):
		errors.append("trade cart should show queued bandage buy")
	if not _cart_line(game_root).contains("确认后玩家资金 76") or not _cart_line(game_root).contains("店铺资金 524"):
		errors.append("trade cart should preview post-confirm player and shop money")
	_press_cart_entry_button(game_root, 0, "IncreaseButton")
	if not _cart_line(game_root).contains("购买 绷带 x2"):
		errors.append("trade cart increase should update queued count")
	if not _cart_line(game_root).contains("确认后玩家资金 52") or not _cart_line(game_root).contains("店铺资金 548"):
		errors.append("trade cart adjusted quantity should update money preview")
	_press_cart_entry_button(game_root, 0, "DecreaseButton")
	if not _cart_line(game_root).contains("购买 绷带 x1"):
		errors.append("trade cart decrease should update queued count")
	_press_cart_entry_button(game_root, 0, "RemoveButton")
	if not _cart_line(game_root).contains("购物车为空"):
		errors.append("trade cart remove should empty queued item")
	_press_queue_button(game_root)
	_press_clear_cart_button(game_root)
	if not _cart_line(game_root).contains("购物车为空"):
		errors.append("trade cart clear should empty queued items")
	if not _drop_trade_item_with_text(game_root, "shop", "绷带"):
		errors.append("should drag shop bandage to trade cart")
	if not _cart_line(game_root).contains("购买 绷带 x1"):
		errors.append("dragged shop item should queue cart buy")
	if not _drop_trade_item_with_text_on_cart_entry(game_root, "shop", "绷带", 0):
		errors.append("should drag shop bandage onto existing cart entry")
	if not _cart_line(game_root).contains("购买 绷带 x2"):
		errors.append("dragging same shop item onto queued item should increase count")
	if not _cart_line(game_root).contains("应付 48") or not _cart_line(game_root).contains("确认后玩家资金 52"):
		errors.append("dragging onto queued item should update money preview")
	_press_cart_entry_button(game_root, 0, "DecreaseButton")
	_press_cart_entry_button(game_root, 0, "RemoveButton")
	if not _drop_trade_item_with_text(game_root, "player", "绷带"):
		errors.append("should drag player bandage to trade cart")
	if not _cart_line(game_root).contains("出售 绷带 x1"):
		errors.append("dragged player item should queue cart sell")
	_press_cart_entry_button(game_root, 0, "RemoveButton")
	if not _drop_trade_item_with_text(game_root, "shop", "急救包"):
		errors.append("should drag shop medkit to trade cart for reorder")
	if not _drop_trade_item_with_text(game_root, "shop", "绷带"):
		errors.append("should drag shop bandage to trade cart for reorder")
	if not _text_ordered(_cart_line(game_root), "购买 急救包 x1", "购买 绷带 x1"):
		errors.append("cart reorder setup should place medkit before bandage")
	_reorder_cart_entry(game_root, 1, 0)
	if not _text_ordered(_cart_line(game_root), "购买 绷带 x1", "购买 急救包 x1"):
		errors.append("cart entry drag should reorder queued items")
	if not _cart_line(game_root).contains("应付 144") or not _cart_line(game_root).contains("确认后玩家资金 -44"):
		errors.append("cart entry reorder should keep money preview")
	_press_clear_cart_button(game_root)
	_press_queue_button(game_root)
	if _player_money(game_root) != money_before_cart:
		errors.append("queueing trade cart should not spend player money")
	if _player_inventory_count(game_root, "1006") != bandage_before_cart:
		errors.append("queueing trade cart should not add player item")
	_set_player_money(game_root, 30)
	game_root.refresh_trade_panel()
	if not _press_trade_item_with_text(game_root, "shop", "急救包"):
		errors.append("should select shop medkit for atomic cart failure")
	_press_queue_button(game_root)
	if not _cart_line(game_root).contains("净付"):
		errors.append("trade cart should show net payment preview")
	_press_confirm_cart_button(game_root)
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()
	if not _trade_feedback(game_root).contains("玩家资金不足"):
		errors.append("failed trade cart should show player money feedback")
	if _player_inventory_count(game_root, "1006") != bandage_before_cart:
		errors.append("failed trade cart should not partially buy bandage")
	if _player_money(game_root) != 30:
		errors.append("failed trade cart should not spend any player money")
	if not "\n".join(_item_lines(game_root)).contains("绷带 x8"):
		errors.append("failed trade cart should not reduce shop bandage stock")
	_set_player_money(game_root, money_before_cart)
	game_root.refresh_trade_panel()
	if not _press_trade_item_with_text(game_root, "shop", "绷带"):
		errors.append("should select shop bandage again after failed cart")
	_press_queue_button(game_root)
	_press_confirm_cart_button(game_root)
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()
	if not _event_seen(game_root, "trade_confirmed"):
		errors.append("successful trade cart buy should emit trade_confirmed")
	if _player_inventory_count(game_root, "1006") != 2:
		errors.append("trade buy did not add bandage to player")
	if _player_money(game_root) != 76:
		errors.append("trade buy did not spend player money")
	if not _summary_line(game_root).contains("资金 524"):
		errors.append("trade summary did not update shop money after buy")
	if not "\n".join(_item_lines(game_root)).contains("绷带 x7"):
		errors.append("trade items did not reduce shop bandage stock")

	if not _press_trade_item_with_text(game_root, "player", "绷带"):
		errors.append("should select player bandage for trade sell")
	if _trade_button_text(game_root) != "出售":
		errors.append("selecting player item after buy should set trade action to sell")
	_set_trade_quantity(game_root, 1)
	var trade_confirmed_before_sell: int = _event_count(game_root, "trade_confirmed")
	_press_trade_button(game_root)
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()
	if _event_count(game_root, "trade_confirmed") <= trade_confirmed_before_sell:
		errors.append("successful direct trade sell should emit trade_confirmed")
	if _player_inventory_count(game_root, "1006") != 1:
		errors.append("trade sell did not remove bandage from player")
	if _player_money(game_root) != 92:
		errors.append("trade sell did not pay player money")
	if not _summary_line(game_root).contains("资金 508"):
		errors.append("trade summary did not update shop money after sell")
	if not _press_trade_item_with_text(game_root, "player", "主手 小刀"):
		errors.append("should select equipped dagger for trade sell")
	if _trade_button_text(game_root) != "出售":
		errors.append("selecting equipped item should set trade action to sell")
	if not _drop_trade_item_with_text(game_root, "player", "主手 小刀"):
		errors.append("should drag equipped dagger to trade cart")
	if not _cart_line(game_root).contains("出售 主手 小刀 x1"):
		errors.append("dragged equipped item should queue cart sell")
	_press_cart_entry_button(game_root, 0, "RemoveButton")
	var dagger_stock_before := _shop_stock_count(game_root, "1002")
	var money_before_equipped_sell := _player_money(game_root)
	_press_trade_button(game_root)
	if not _equipment_sell_dialog_visible(game_root):
		errors.append("equipped item sell should open confirmation dialog")
	if _player_equipped_item(game_root, "main_hand").is_empty():
		errors.append("equipped item should not be sold before confirmation")
	if _player_money(game_root) != money_before_equipped_sell:
		errors.append("equipped item sell should not pay before confirmation")
	if _shop_stock_count(game_root, "1002") != dagger_stock_before:
		errors.append("equipped item sell should not update shop stock before confirmation")
	_cancel_equipment_sell_dialog(game_root)
	if _equipment_sell_dialog_visible(game_root):
		errors.append("equipment sell cancel should close confirmation dialog")
	if _player_equipped_item(game_root, "main_hand").is_empty():
		errors.append("equipment sell cancel should keep main hand equipment")
	if _player_money(game_root) != money_before_equipped_sell:
		errors.append("equipment sell cancel should keep player money")
	_press_trade_button(game_root)
	if not _equipment_sell_dialog_visible(game_root):
		errors.append("equipped item sell should reopen confirmation dialog")
	var trade_confirmed_before_equipment_sell: int = _event_count(game_root, "trade_confirmed")
	_confirm_equipment_sell_dialog(game_root)
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()
	if _event_count(game_root, "trade_confirmed") <= trade_confirmed_before_equipment_sell:
		errors.append("successful equipped trade sell should emit trade_confirmed")
	if not _player_equipped_item(game_root, "main_hand").is_empty():
		errors.append("trade equipped sell did not clear main hand equipment")
	if _player_money(game_root) != 132:
		errors.append("trade equipped sell did not pay player money")
	if _shop_stock_count(game_root, "1002") != dagger_stock_before + 1:
		errors.append("trade equipped sell did not add dagger to shop stock")
	if _player_item_text(game_root).contains("主手 小刀"):
		errors.append("trade player column should remove sold equipped dagger")
	var stock_result: Dictionary = game_root.buy_active_trade_item("1006", 999)
	if stock_result.get("reason", "") != "shop_stock_insufficient":
		errors.append("oversized trade buy should report shop_stock_insufficient")
	if not _trade_feedback(game_root).contains("店铺库存不足"):
		errors.append("oversized trade buy should show shop stock feedback")
	_set_player_money(game_root, 0)
	if not _press_trade_item_with_text(game_root, "shop", "绷带"):
		errors.append("should select shop bandage for insufficient money check")
	_press_trade_button(game_root)
	if not _trade_feedback(game_root).contains("玩家资金不足"):
		errors.append("trade buy failure should show player money feedback")
	var player_stock_result: Dictionary = game_root.sell_active_trade_item("1006", 999)
	if player_stock_result.get("reason", "") != "player_stock_insufficient":
		errors.append("oversized trade sell should report player_stock_insufficient")
	if not _trade_feedback(game_root).contains("背包库存不足"):
		errors.append("oversized trade sell should show player stock feedback")
	_set_active_shop_money(game_root, 0)
	if not _press_trade_item_with_text(game_root, "player", "绷带"):
		errors.append("should select player bandage for insufficient shop money check")
	_press_trade_button(game_root)
	if not _trade_feedback(game_root).contains("店铺资金不足"):
		errors.append("trade sell failure should show shop money feedback")
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
	_close_trade_via_dialogue_leave(game_root, errors)
	_reopen_trade(game_root, errors)
	game_root.active_trade_target = {"target_type": "actor", "actor_id": 9999}
	game_root.refresh_trade_panel()
	if game_root.trade_panel.visible:
		errors.append("missing trade target should close trade panel")
	if not game_root.active_trade_target.is_empty():
		errors.append("missing trade target should clear active trade target")
	_reopen_trade(game_root, errors)
	game_root.simulation.unlock_location("forest")
	var enter_result: Dictionary = game_root.simulation.enter_location(1, "forest", game_root.registry.get_library("overworld"))
	if not bool(enter_result.get("success", false)):
		errors.append("forest enter for trade close check failed: %s" % enter_result.get("reason", "unknown"))
	game_root.refresh_trade_panel()
	if game_root.trade_panel.visible:
		errors.append("map switch should close trade panel")
	if not game_root.active_trade_target.is_empty():
		errors.append("map switch should clear active trade target")
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


func _event_seen(game_root: Node, kind: String) -> bool:
	return _event_count(game_root, kind) > 0


func _event_count(game_root: Node, kind: String) -> int:
	var count := 0
	for event in game_root.simulation.snapshot().get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


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


func _close_trade_via_dialogue_leave(game_root: Node, errors: Array[String]) -> void:
	var talk_result: Dictionary = game_root.simulation.execute_interaction(1, {
		"target_type": "actor",
		"actor_id": 2,
	})
	game_root.refresh_dialogue_panel()
	if not bool(talk_result.get("success", false)):
		errors.append("trade dialogue close setup failed: %s" % talk_result.get("reason", "unknown"))
		return
	var leave_result: Dictionary = game_root.choose_dialogue_option(2)
	if not bool(leave_result.get("success", false)) or str(leave_result.get("end_type", "")) != "leave":
		errors.append("dialogue leave option should finish with leave end_type")
	if game_root.trade_panel.visible:
		errors.append("dialogue leave should close trade panel")
	if not game_root.active_trade_target.is_empty():
		errors.append("dialogue leave should clear active trade target")


func _title_line(game_root: Node) -> String:
	return game_root.trade_panel.get_node("TradePanel/TradeLines/TitleLine").text


func _summary_line(game_root: Node) -> String:
	return game_root.trade_panel.get_node("TradePanel/TradeLines/SummaryLine").text


func _detail_line(game_root: Node) -> String:
	var label: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/DetailLine")
	if label is Label:
		return str((label as Label).text)
	return ""


func _trade_feedback(game_root: Node) -> String:
	var label: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/FeedbackLine")
	if label is Label and (label as Label).visible:
		return str((label as Label).text)
	return ""


func _item_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var item_box: Node = _trade_item_box(game_root, "shop")
	for child in item_box.get_children():
		var text := _item_control_text(child)
		if not text.is_empty():
			output.append(text)
	return output


func _player_item_text(game_root: Node) -> String:
	var output: Array[String] = []
	var item_box: Node = _trade_item_box(game_root, "player")
	for child in item_box.get_children():
		var text := _item_control_text(child)
		if not text.is_empty():
			output.append(text)
	return "\n".join(output)


func _press_trade_item_with_text(game_root: Node, source: String, text: String) -> bool:
	var button: Button = _trade_item_button_with_text(game_root, source, text)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _drop_trade_item_with_text(game_root: Node, source: String, text: String, count: int = 1) -> bool:
	return _drop_trade_item_with_text_on_target(game_root, source, text, null, count)


func _drop_trade_item_with_text_on_cart_entry(game_root: Node, source: String, text: String, target_index: int, count: int = 1) -> bool:
	var target: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartScroll/CartItemLines/CartEntry_%d" % target_index)
	if not target is Control:
		return false
	return _drop_trade_item_with_text_on_target(game_root, source, text, target, count)


func _drop_trade_item_with_text_on_target(game_root: Node, source: String, text: String, target: Control, count: int = 1) -> bool:
	var button: Button = _trade_item_button_with_text(game_root, source, text)
	if button == null:
		return false
	var item: Dictionary = button.get_meta("trade_item", {})
	var trade_source: String = str(button.get_meta("trade_source", ""))
	if item.is_empty() or trade_source.is_empty():
		return false
	game_root.trade_panel.call("_drop_cart_data", Vector2.ZERO, {
		"kind": "trade_item",
		"source": trade_source,
		"item": item.duplicate(true),
		"count": count,
	}, target)
	return true


func _trade_item_button_with_text(game_root: Node, source: String, text: String) -> Button:
	var item_box: Node = _trade_item_box(game_root, source)
	if item_box == null:
		return null
	for child in item_box.get_children():
		if child is Button and str((child as Button).text).contains(text):
			return child as Button
	return null


func _set_trade_quantity(game_root: Node, count: int) -> void:
	var spin: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/TradeControls/QuantitySpin")
	if spin is SpinBox:
		(spin as SpinBox).value = count


func _press_trade_button(game_root: Node) -> void:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/TradeControls/TradeButton")
	if button is Button:
		(button as Button).pressed.emit()


func _equipment_sell_dialog_visible(game_root: Node) -> bool:
	var dialog: Node = game_root.trade_panel.get_node_or_null("EquipmentSellConfirmDialog")
	if dialog is ConfirmationDialog:
		return bool((dialog as ConfirmationDialog).visible)
	return false


func _cancel_equipment_sell_dialog(game_root: Node) -> void:
	var dialog: Node = game_root.trade_panel.get_node_or_null("EquipmentSellConfirmDialog")
	if dialog is ConfirmationDialog:
		(dialog as ConfirmationDialog).hide()


func _confirm_equipment_sell_dialog(game_root: Node) -> void:
	var dialog: Node = game_root.trade_panel.get_node_or_null("EquipmentSellConfirmDialog")
	if dialog is ConfirmationDialog:
		(dialog as ConfirmationDialog).confirmed.emit()
		(dialog as ConfirmationDialog).hide()


func _press_queue_button(game_root: Node) -> void:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartControls/QueueButton")
	if button is Button:
		(button as Button).pressed.emit()


func _press_confirm_cart_button(game_root: Node) -> void:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartControls/ConfirmCartButton")
	if button is Button:
		(button as Button).pressed.emit()


func _press_clear_cart_button(game_root: Node) -> void:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartControls/ClearCartButton")
	if button is Button:
		(button as Button).pressed.emit()


func _press_cart_entry_button(game_root: Node, index: int, button_name: String) -> void:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartScroll/CartItemLines/CartEntry_%d/%s" % [index, button_name])
	if button is Button:
		(button as Button).pressed.emit()


func _reorder_cart_entry(game_root: Node, from_index: int, target_index: int) -> void:
	var target: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartScroll/CartItemLines/CartEntry_%d" % target_index)
	if target is Control:
		game_root.trade_panel.call("_drop_cart_data", Vector2.ZERO, {
			"kind": "trade_cart_entry",
			"index": from_index,
		}, target)


func _cart_line(game_root: Node) -> String:
	var label: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartLine")
	if label is Label:
		return str((label as Label).text)
	return ""


func _trade_button_text(game_root: Node) -> String:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/TradeControls/TradeButton")
	if button is Button:
		return str((button as Button).text)
	return ""


func _trade_button_disabled(game_root: Node) -> bool:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/TradeControls/TradeButton")
	if button is Button:
		return bool((button as Button).disabled)
	return true


func _queue_button_disabled(game_root: Node) -> bool:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartControls/QueueButton")
	if button is Button:
		return bool((button as Button).disabled)
	return true


func _trade_item_box(game_root: Node, source: String) -> Node:
	match source:
		"shop":
			return game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/TradeColumns/ShopColumn/ShopScroll/ItemLines")
		"player":
			return game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/TradeColumns/PlayerColumn/PlayerScroll/PlayerItemLines")
		_:
			return null


func _item_control_text(node: Node) -> String:
	if node is Label:
		return str((node as Label).text)
	if node is Button:
		return str((node as Button).text)
	return ""


func _text_ordered(text: String, first: String, second: String) -> bool:
	var first_index: int = text.find(first)
	var second_index: int = text.find(second)
	return first_index >= 0 and second_index >= 0 and first_index < second_index


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


func _player_equipped_item(game_root: Node, slot_id: String) -> String:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			var equipment: Dictionary = actor_data.get("equipment", {})
			return str(equipment.get(slot_id, ""))
	return ""


func _shop_stock_count(game_root: Node, item_id: String) -> int:
	for shop_id in game_root.simulation.shop_sessions.keys():
		var shop: Dictionary = game_root.simulation.shop_sessions[shop_id]
		for entry in shop.get("inventory", []):
			var entry_data: Dictionary = entry
			if str(entry_data.get("item_id", "")) == item_id:
				return int(entry_data.get("count", 0))
	return 0


func _set_player_money(game_root: Node, money: int) -> void:
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor != null:
		actor.money = money


func _set_active_shop_money(game_root: Node, money: int) -> void:
	for shop_id in game_root.simulation.shop_sessions.keys():
		var shop: Dictionary = game_root.simulation.shop_sessions[shop_id]
		shop["money"] = money
		game_root.simulation.shop_sessions[shop_id] = shop
		return


func _set_item_sellable(game_root: Node, item_id: String, sellable: bool) -> void:
	var items: Dictionary = game_root.registry.get_library("items")
	var record: Dictionary = items.get(item_id, {})
	var data: Dictionary = record.get("data", {})
	data["sellable"] = sellable
	record["data"] = data
	items[item_id] = record


func _clear_item_sellable_override(game_root: Node, item_id: String) -> void:
	var items: Dictionary = game_root.registry.get_library("items")
	var record: Dictionary = items.get(item_id, {})
	var data: Dictionary = record.get("data", {})
	data.erase("sellable")
	record["data"] = data
	items[item_id] = record
