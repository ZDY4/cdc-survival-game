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
	_finish_presentations(game_root)

	if not game_root.trade_panel.visible:
		errors.append("trade panel did not open after trader talk")
	_assert_panel_blocker(errors, game_root, "trade", "TradePanel", "trade open")
	if not _title_line(game_root).contains("废土商人·老王"):
		errors.append("trade title did not use trader display name")
	if not _summary_line(game_root).contains("资金 500"):
		errors.append("trade summary missing shop money")
	if not _trade_zone_tooltip(game_root, "BuyDropZone").contains("接受店铺栏物品") or not _trade_zone_tooltip(game_root, "BuyDropZone").contains("拒绝背包/装备"):
		errors.append("buy drop zone tooltip should explain accepted and rejected sources")
	if not _trade_zone_tooltip(game_root, "SellDropZone").contains("接受背包或装备栏物品") or not _trade_zone_tooltip(game_root, "SellDropZone").contains("拒绝店铺"):
		errors.append("sell drop zone tooltip should explain accepted and rejected sources")
	if not _trade_zone_label_text(game_root, "BuyDropZone").contains("接受店铺栏物品"):
		errors.append("buy drop zone should show accepted source in visible label")
	if not _trade_zone_label_text(game_root, "SellDropZone").contains("接受背包或装备栏物品"):
		errors.append("sell drop zone should show accepted source in visible label")
	if _trade_zone_meta_text(game_root, "BuyDropZone", "trade_drop_accept_text") != "接受店铺栏物品":
		errors.append("buy drop zone should expose stable accept text metadata")
	if _trade_zone_meta_text(game_root, "SellDropZone", "trade_drop_reject_text") != "拒绝店铺购买源":
		errors.append("sell drop zone should expose stable reject text metadata")
	if _trade_zone_reject_reason(game_root, "BuyDropZone") != "buy_zone_requires_shop_source":
		errors.append("buy drop zone should expose stable reject reason metadata")
	if _trade_zone_reject_reason(game_root, "SellDropZone") != "sell_zone_requires_player_or_equipment_source":
		errors.append("sell drop zone should expose stable reject reason metadata")
	game_root.trade_panel.call("_update_drop_zone_drag_state", _trade_zone_control(game_root, "BuyDropZone"), "player", false, "buy_zone_requires_shop_source")
	if _trade_zone_meta_text(game_root, "BuyDropZone", "trade_drop_last_reject_reason") != "buy_zone_requires_shop_source":
		errors.append("buy drop zone should preserve stable reject reason code")
	if not _trade_zone_meta_text(game_root, "BuyDropZone", "trade_drop_last_preview_text").contains("购买区只接受店铺物品"):
		errors.append("buy drop zone preview should use reason catalog text")
	game_root.trade_panel.call("_update_drop_zone_drag_state", _trade_zone_control(game_root, "SellDropZone"), "shop", false, "sell_zone_requires_player_or_equipment_source")
	if _trade_zone_meta_text(game_root, "SellDropZone", "trade_drop_last_reject_reason") != "sell_zone_requires_player_or_equipment_source":
		errors.append("sell drop zone should preserve stable reject reason code")
	if not _trade_zone_meta_text(game_root, "SellDropZone", "trade_drop_last_preview_text").contains("出售区只接受背包或装备物品"):
		errors.append("sell drop zone preview should use reason catalog text")

	var item_text: String = "\n".join(_item_lines(game_root))
	if not item_text.contains("急救包 x1"):
		errors.append("trade items missing medkit")
	if not item_text.contains("绷带 x8"):
		errors.append("trade items missing bandage")
	if not _player_item_text(game_root).contains("绷带 x1"):
		errors.append("trade player column missing player inventory")
	if not _player_item_text(game_root).contains("主手 小刀 x1"):
		errors.append("trade player column missing equipped main hand item")
	if _trade_item_icon_path(game_root, "shop", "急救包") != "res://assets/icons/items/medkit.svg":
		errors.append("trade shop item row should expose and render item icon")
	if _trade_item_icon_path(game_root, "player", "绷带") != "res://assets/icons/items/bandage.svg":
		errors.append("trade player item row should expose and render item icon")
	if _trade_item_icon_path(game_root, "player", "主手 小刀") != "res://assets/icons/weapons/knife.svg":
		errors.append("trade equipment item row should expose and render item icon")
	if not _detail_line(game_root).contains("店铺：") or not _detail_line(game_root).contains("单价"):
		errors.append("trade detail should default to selected shop item")
	if not _open_trade_context_menu(game_root, "shop", "绷带"):
		errors.append("should open trade context menu for shop bandage")
	else:
		_assert_trade_context_menu(errors, game_root, "1006", "shop", "购买选中数量", "shop bandage context")
		_execute_trade_context_action(game_root, 2)
		if not _cart_line(game_root).contains("购买 绷带 x1"):
			errors.append("trade context queue should add shop bandage to cart")
		_press_cart_entry_button(game_root, 0, "RemoveButton")
		if not _cart_line(game_root).contains("购物车为空"):
			_press_clear_cart_button(game_root)
	_close_trade_context_menu(game_root)
	if not _open_trade_context_menu(game_root, "player", "绷带"):
		errors.append("should open trade context menu for player bandage")
	else:
		_assert_trade_context_menu(errors, game_root, "1006", "player", "出售选中数量", "player bandage context")
		_execute_trade_context_action(game_root, 2)
		if not _cart_line(game_root).contains("出售 绷带 x1"):
			errors.append("trade context queue should add player bandage sell to cart")
		_press_cart_entry_button(game_root, 0, "RemoveButton")
		if not _cart_line(game_root).contains("购物车为空"):
			_press_clear_cart_button(game_root)
	_close_trade_context_menu(game_root)
	if not _press_trade_item_with_text(game_root, "player", "绷带"):
		errors.append("should select player bandage in trade panel")
	if _trade_button_text(game_root) != "出售":
		errors.append("selecting player item should set trade action to sell")
	var player_money_before_context_sell: int = _player_money(game_root)
	var shop_sessions_before_context_sell: Dictionary = game_root.simulation.shop_sessions.duplicate(true)
	_add_player_inventory_item(game_root, "1010", 1)
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()
	if not _open_inventory_context_menu(game_root, "废金属"):
		errors.append("should open inventory context menu for scrap while trade is active")
	elif _context_action_disabled(game_root, 10):
		errors.append("inventory context menu should enable sell when trade is active")
	else:
		var trade_confirmed_before_context_sell: int = _event_count(game_root, "trade_confirmed")
		var money_before_context_sell: int = _player_money(game_root)
		_execute_inventory_context_action(game_root, 10)
		if _event_count(game_root, "trade_confirmed") <= trade_confirmed_before_context_sell:
			errors.append("inventory context sell should emit trade_confirmed")
		if _player_inventory_count(game_root, "1010") != 0:
			errors.append("inventory context sell should remove sold scrap")
		if _player_money(game_root) <= money_before_context_sell:
			errors.append("inventory context sell should pay player money")
	_set_player_money(game_root, player_money_before_context_sell)
	_remove_player_inventory_item(game_root, "1010")
	game_root.simulation.shop_sessions = shop_sessions_before_context_sell.duplicate(true)
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()
	_set_item_sellable(game_root, "1006", false)
	game_root.refresh_trade_panel()
	if not _player_item_text(game_root).contains("绷带 x1") or not _player_item_text(game_root).contains("不可出售"):
		errors.append("non-sellable player item should show disabled reason")
	if not _press_trade_item_with_text(game_root, "player", "绷带"):
		errors.append("should select non-sellable player bandage in trade panel")
	if not _trade_button_disabled(game_root):
		errors.append("non-sellable player item should disable direct sell")
	if not _trade_button_tooltip(game_root).contains("不可出售"):
		errors.append("non-sellable direct sell button should explain disabled reason")
	if not _queue_button_disabled(game_root):
		errors.append("non-sellable player item should disable trade cart queue")
	if not _queue_button_tooltip(game_root).contains("不可出售"):
		errors.append("non-sellable queue button should explain disabled reason")
	_press_queue_button(game_root)
	if not _cart_line(game_root).contains("购物车为空"):
		errors.append("non-sellable player item should not enter trade cart")
	if not _drop_trade_item_with_text(game_root, "player", "绷带"):
		errors.append("should attempt dragging non-sellable player bandage")
	if not _cart_line(game_root).contains("购物车为空"):
		errors.append("dragged non-sellable player item should not enter trade cart")
	if _can_drop_trade_item_to_zone(game_root, "player", "绷带", "SellDropZone"):
		errors.append("sell drop zone can_drop should reject non-sellable player item")
	if _trade_zone_last_accept(game_root, "SellDropZone"):
		errors.append("sell drop zone should record rejected non-sellable drag")
	if not _trade_zone_meta_text(game_root, "SellDropZone", "trade_drop_last_reject_reason").contains("不可出售"):
		errors.append("sell drop zone should expose non-sellable reject reason")
	if not _trade_zone_meta_text(game_root, "SellDropZone", "trade_drop_last_preview_text").contains("不可出售"):
		errors.append("sell drop zone preview should explain non-sellable drag")
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
	_press_trade_shortcut(game_root, KEY_Q)
	if _trade_last_shortcut(game_root) != "queue":
		errors.append("Q should route to trade queue shortcut")
	if not _cart_line(game_root).contains("购买 绷带 x1"):
		errors.append("trade cart should show shortcut queued bandage buy")
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
	_press_trade_shortcut(game_root, KEY_DELETE)
	if _trade_last_shortcut(game_root) != "clear_cart":
		errors.append("Delete should route to trade clear cart shortcut")
	if not _cart_line(game_root).contains("购物车为空"):
		errors.append("trade cart clear shortcut should empty queued items")
	if not _drop_trade_item_with_text(game_root, "shop", "绷带"):
		errors.append("should drag shop bandage to trade cart")
	if not _cart_line(game_root).contains("购买 绷带 x1"):
		errors.append("dragged shop item should queue cart buy")
	_assert_trade_cart_hover_target(errors, game_root, _trade_drag_data(game_root, "shop", "绷带"), _trade_cart_target(game_root), "trade_cart", true, "", "shop bandage to trade cart hover target")
	_assert_trade_cart_hover_render(errors, game_root, _trade_drag_data(game_root, "shop", "绷带"), _trade_cart_target(game_root), true, "", "shop bandage to trade cart hover render")
	_press_cart_entry_button(game_root, 0, "RemoveButton")
	if not _drop_trade_item_to_zone(game_root, "shop", "绷带", "BuyDropZone"):
		errors.append("should drag shop bandage to buy drop zone")
	else:
		_assert_drag_state_snapshot(errors, game_root, _trade_drag_data(game_root, "shop", "绷带"), _trade_zone_control(game_root, "BuyDropZone"), "trade_item", "trade", "trade_drop_zone", "shop bandage to buy drop zone")
	if not _cart_line(game_root).contains("购买 绷带 x1"):
		errors.append("buy drop zone should queue cart buy")
	_press_cart_entry_button(game_root, 0, "RemoveButton")
	if not _drop_trade_item_to_zone(game_root, "shop", "绷带", "SellDropZone"):
		errors.append("should attempt dragging shop bandage to sell drop zone")
	if not _cart_line(game_root).contains("购物车为空"):
		errors.append("sell drop zone should reject shop buy item")
	if _can_drop_trade_item_to_zone(game_root, "shop", "绷带", "SellDropZone"):
		errors.append("sell drop zone can_drop should reject shop buy item")
	if _trade_zone_last_accept(game_root, "SellDropZone"):
		errors.append("sell drop zone should record rejected shop drag")
	if _trade_zone_meta_text(game_root, "SellDropZone", "trade_drop_last_source") != "shop":
		errors.append("sell drop zone should remember rejected drag source")
	if _trade_zone_meta_text(game_root, "SellDropZone", "trade_drop_last_reject_reason") != "sell_zone_requires_player_or_equipment_source":
		errors.append("sell drop zone should preserve stable last reject reason code")
	if not _trade_zone_meta_text(game_root, "SellDropZone", "trade_drop_last_preview_text").contains("出售区只接受背包或装备物品"):
		errors.append("sell drop zone should expose catalog reject preview text")
	if not _drop_trade_item_with_text(game_root, "shop", "绷带"):
		errors.append("should drag shop bandage back to cart after zone rejection")
	_assert_trade_cart_hover_target(errors, game_root, _trade_drag_data(game_root, "shop", "绷带"), _trade_cart_entry_control(game_root, 0), "trade_cart_entry", true, "", "shop bandage to cart entry hover target")
	_assert_trade_cart_hover_render(errors, game_root, _trade_drag_data(game_root, "shop", "绷带"), _trade_cart_entry_control(game_root, 0), true, "", "shop bandage to cart entry hover render")
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
	if not _drop_trade_item_to_zone(game_root, "player", "绷带", "SellDropZone"):
		errors.append("should drag player bandage to sell drop zone")
	else:
		_assert_drag_state_snapshot(errors, game_root, _trade_drag_data(game_root, "player", "绷带"), _trade_zone_control(game_root, "SellDropZone"), "trade_item", "trade", "trade_drop_zone", "player bandage to sell drop zone")
	if not _cart_line(game_root).contains("出售 绷带 x1"):
		errors.append("sell drop zone should queue cart sell")
	if not _can_drop_trade_item_to_zone(game_root, "player", "绷带", "SellDropZone"):
		errors.append("sell drop zone can_drop should accept player sell item")
	if not _trade_zone_last_accept(game_root, "SellDropZone"):
		errors.append("sell drop zone should record accepted player drag")
	if not _trade_zone_meta_text(game_root, "SellDropZone", "trade_drop_last_preview_text").contains("可放入：背包"):
		errors.append("sell drop zone should expose accepted player preview text")
	_press_cart_entry_button(game_root, 0, "RemoveButton")
	if not _drop_trade_item_to_zone(game_root, "player", "绷带", "BuyDropZone"):
		errors.append("should attempt dragging player bandage to buy drop zone")
	if not _cart_line(game_root).contains("购物车为空"):
		errors.append("buy drop zone should reject player sell item")
	if _can_drop_trade_item_to_zone(game_root, "player", "绷带", "BuyDropZone"):
		errors.append("buy drop zone can_drop should reject player sell item")
	if _trade_zone_last_accept(game_root, "BuyDropZone"):
		errors.append("buy drop zone should record rejected player drag")
	if _trade_zone_meta_text(game_root, "BuyDropZone", "trade_drop_last_reject_reason") != "buy_zone_requires_shop_source":
		errors.append("buy drop zone should preserve stable last reject reason code")
	if not _trade_zone_meta_text(game_root, "BuyDropZone", "trade_drop_last_preview_text").contains("购买区只接受店铺物品"):
		errors.append("buy drop zone should expose catalog reject preview text")
	if not _drop_inventory_item_to_trade_cart(game_root, "绷带"):
		errors.append("should drag inventory bandage to trade cart")
	if not _cart_line(game_root).contains("出售 绷带 x1"):
		errors.append("dragged inventory item should queue cart sell")
	_press_cart_entry_button(game_root, 0, "RemoveButton")
	if not _drop_inventory_item_to_trade_zone(game_root, "绷带", "SellDropZone"):
		errors.append("should drag inventory bandage to sell drop zone")
	if not _cart_line(game_root).contains("出售 绷带 x1"):
		errors.append("sell drop zone should queue inventory sell")
	_press_cart_entry_button(game_root, 0, "RemoveButton")
	if not _drop_trade_item_with_text(game_root, "shop", "急救包"):
		errors.append("should drag shop medkit to trade cart for reorder")
	if not _drop_trade_item_with_text(game_root, "shop", "绷带"):
		errors.append("should drag shop bandage to trade cart for reorder")
	if not _text_ordered(_cart_line(game_root), "购买 急救包 x1", "购买 绷带 x1"):
		errors.append("cart reorder setup should place medkit before bandage")
	_assert_trade_cart_hover_target(errors, game_root, {"kind": "trade_cart_entry", "index": 1, "drag_preview_text": "购买 绷带 x1"}, _trade_cart_entry_control(game_root, 0), "trade_cart_entry", true, "", "cart entry reorder hover target")
	_assert_trade_cart_hover_render(errors, game_root, {"kind": "trade_cart_entry", "index": 1, "drag_preview_text": "购买 绷带 x1"}, _trade_cart_entry_control(game_root, 0), true, "", "cart entry reorder hover render")
	_assert_trade_cart_hover_target(errors, game_root, {"kind": "trade_cart_entry", "index": -1, "drag_preview_text": "失效条目"}, _trade_cart_target(game_root), "trade_cart", false, "cart_entry_missing_index", "invalid cart entry reject hover target")
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
	var capacity_player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	var capacity_inventory_before: Dictionary = capacity_player.inventory.duplicate(true)
	var capacity_order_before: Array = capacity_player.inventory_order.duplicate()
	var capacity_equipment_before: Dictionary = capacity_player.equipment.duplicate(true)
	var capacity_money_before: int = _player_money(game_root)
	var capacity_shop_sessions_before: Dictionary = game_root.simulation.shop_sessions.duplicate(true)
	capacity_player.inventory.clear()
	capacity_player.inventory_order.clear()
	capacity_player.equipment.clear()
	capacity_player.inventory["1003"] = 50
	_set_player_money(game_root, 1000)
	game_root.refresh_trade_panel()
	var overweight_buy: Dictionary = game_root.buy_active_trade_item("1006", 1)
	if str(overweight_buy.get("reason", "")) != "inventory_over_capacity":
		errors.append("overweight direct trade buy should report inventory_over_capacity")
	if not _trade_feedback(game_root).contains("负重不足"):
		errors.append("overweight direct trade buy should show capacity feedback")
	if int(capacity_player.inventory.get("1003", 0)) != 50:
		errors.append("failed overweight direct trade buy should not add item")
	if _player_money(game_root) != 1000:
		errors.append("failed overweight direct trade buy should not spend money")
	var overweight_cart: Dictionary = game_root.confirm_active_trade_cart([{
		"source": "shop",
		"item_id": "1006",
		"count": 1,
	}])
	if str(overweight_cart.get("reason", "")) != "inventory_over_capacity":
		errors.append("overweight trade cart should report inventory_over_capacity")
	if _player_money(game_root) != 1000:
		errors.append("failed overweight trade cart should not spend money")
	game_root.simulation.shop_sessions = capacity_shop_sessions_before.duplicate(true)
	capacity_player.inventory = capacity_inventory_before
	capacity_player.inventory_order = capacity_order_before
	capacity_player.equipment = capacity_equipment_before
	_set_player_money(game_root, capacity_money_before)
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()
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
	_press_trade_shortcut(game_root, KEY_ENTER, true)
	if _trade_last_shortcut(game_root) != "confirm_cart":
		errors.append("Shift+Enter should route to trade cart confirm shortcut")
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
	_press_trade_shortcut(game_root, KEY_ENTER)
	if _trade_last_shortcut(game_root) != "trade":
		errors.append("Enter should route to direct trade shortcut")
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

	var stack_player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	var stack_shop_sessions_before: Dictionary = game_root.simulation.shop_sessions.duplicate(true)
	var stack_inventory_before: Dictionary = stack_player.inventory.duplicate(true)
	var stack_order_before: Array = stack_player.inventory_order.duplicate()
	var stack_inventory_stacks_before: Dictionary = stack_player.inventory_stacks.duplicate(true)
	var stack_money_before: int = int(stack_player.money)
	var stack_shop: Dictionary = _dictionary_or_empty(game_root.simulation.shop_sessions.get("trader_lao_wang_shop", {})).duplicate(true)
	stack_shop["money"] = 1000
	stack_shop["inventory"] = [
		{"item_id": "1006", "count": 2, "price": 10},
		{"item_id": "1006", "count": 3, "price": 10},
	]
	game_root.simulation.shop_sessions["trader_lao_wang_shop"] = stack_shop
	stack_player.inventory["1006"] = 1
	if not stack_player.inventory_order.has("1006"):
		stack_player.inventory_order.append("1006")
	stack_player.money = 200
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()
	var stacked_shop_text := "\n".join(_item_lines(game_root))
	if not stacked_shop_text.contains("绷带 x2") or not stacked_shop_text.contains("堆 1/2"):
		errors.append("multi-stack shop should label first stack in item list: %s" % stacked_shop_text)
	if not stacked_shop_text.contains("绷带 x3") or not stacked_shop_text.contains("堆 2/2"):
		errors.append("multi-stack shop should label second stack in item list: %s" % stacked_shop_text)
	var stacked_shop_button: Button = _trade_item_button_with_text(game_root, "shop", "堆 1/2")
	if stacked_shop_button == null:
		errors.append("multi-stack shop should expose first stack button")
	else:
		var stacked_shop_item: Dictionary = _dictionary_or_empty(stacked_shop_button.get_meta("trade_item", {}))
		if not bool(stacked_shop_item.get("multi_stack", false)):
			errors.append("multi-stack shop button metadata should mark multi_stack: %s" % stacked_shop_item)
		if int(stacked_shop_item.get("stack_index", 0)) != 1 or int(stacked_shop_item.get("stack_count", 0)) != 2 or int(stacked_shop_item.get("stack_total_count", 0)) != 5:
			errors.append("multi-stack shop button metadata should expose stack position and total: %s" % stacked_shop_item)
		stacked_shop_button.pressed.emit()
		if not _detail_line(game_root).contains("同物品合计 5"):
			errors.append("multi-stack shop detail should expose total count: %s" % _detail_line(game_root))
		_set_trade_quantity(game_root, 1)
		_press_trade_button(game_root)
		var selected_shop_stacks: Array = _shop_stack_counts(game_root, "1006")
		if selected_shop_stacks.size() != 2 or int(selected_shop_stacks[0]) != 1 or int(selected_shop_stacks[1]) != 3:
			errors.append("trade UI direct buy should consume selected first shop stack: %s" % selected_shop_stacks)
		stack_shop["money"] = 1000
		stack_shop["inventory"] = [
			{"item_id": "1006", "count": 2, "price": 10},
			{"item_id": "1006", "count": 3, "price": 10},
		]
		game_root.simulation.shop_sessions["trader_lao_wang_shop"] = stack_shop
		stack_player.inventory["1006"] = 1
		stack_player.inventory_stacks = stack_inventory_stacks_before.duplicate(true)
		stack_player.money = 200
		game_root.refresh_inventory_panel()
		game_root.refresh_trade_panel()
		var stacked_shop_cart_button: Button = _trade_item_button_with_text(game_root, "shop", "堆 1/2")
		if stacked_shop_cart_button == null:
			errors.append("multi-stack shop should expose first stack button after direct-buy reset")
		else:
			stacked_shop_cart_button.pressed.emit()
			_set_trade_quantity(game_root, 1)
			_press_queue_button(game_root)
			_press_confirm_cart_button(game_root)
			var selected_cart_stacks: Array = _shop_stack_counts(game_root, "1006")
			if selected_cart_stacks.size() != 2 or int(selected_cart_stacks[0]) != 1 or int(selected_cart_stacks[1]) != 3:
				errors.append("trade cart buy should consume selected first shop stack: %s" % selected_cart_stacks)
			stack_shop["money"] = 1000
			stack_shop["inventory"] = [
				{"item_id": "1006", "count": 2, "price": 10},
				{"item_id": "1006", "count": 3, "price": 10},
			]
			game_root.simulation.shop_sessions["trader_lao_wang_shop"] = stack_shop
			stack_player.inventory["1006"] = 1
			stack_player.inventory_stacks = stack_inventory_stacks_before.duplicate(true)
			stack_player.money = 200
			game_root.refresh_inventory_panel()
			game_root.refresh_trade_panel()
		stack_player.inventory["1006"] = 5
		if not stack_player.inventory_order.has("1006"):
			stack_player.inventory_order.append("1006")
		stack_player.inventory_stacks = {"1006": [2, 3]}
		stack_player.money = 200
		stack_shop["money"] = 1000
		stack_shop["inventory"] = [
			{"item_id": "1006", "count": 2, "price": 10},
			{"item_id": "1006", "count": 3, "price": 10},
		]
		game_root.simulation.shop_sessions["trader_lao_wang_shop"] = stack_shop
		game_root.refresh_inventory_panel()
		game_root.refresh_trade_panel()
		var stacked_player_text := _player_item_text(game_root)
		if not stacked_player_text.contains("绷带 x2") or not stacked_player_text.contains("堆 1/2"):
			errors.append("multi-stack player trade column should label first stack: %s" % stacked_player_text)
		if not stacked_player_text.contains("绷带 x3") or not stacked_player_text.contains("堆 2/2"):
			errors.append("multi-stack player trade column should label second stack: %s" % stacked_player_text)
		var stacked_player_sell_button: Button = _trade_item_button_with_text(game_root, "player", "堆 1/2")
		if stacked_player_sell_button == null:
			errors.append("multi-stack player trade column should expose first stack button")
		else:
			var stacked_player_trade_item: Dictionary = _dictionary_or_empty(stacked_player_sell_button.get_meta("trade_item", {}))
			if int(stacked_player_trade_item.get("stack_index", 0)) != 1 or int(stacked_player_trade_item.get("stack_count", 0)) != 2 or int(stacked_player_trade_item.get("stack_total_count", 0)) != 5:
				errors.append("multi-stack player trade metadata should expose stack position and total: %s" % stacked_player_trade_item)
			stacked_player_sell_button.pressed.emit()
			_set_trade_quantity(game_root, 1)
			_press_trade_button(game_root)
			var direct_sell_player_stacks: Array = _array_or_empty(stack_player.inventory_stacks.get("1006", []))
			if direct_sell_player_stacks.size() != 2 or int(direct_sell_player_stacks[0]) != 1 or int(direct_sell_player_stacks[1]) != 3:
				errors.append("trade UI direct sell should consume selected first player stack: %s" % direct_sell_player_stacks)
		stack_player.inventory["1006"] = 5
		stack_player.inventory_stacks = {"1006": [2, 3]}
		stack_player.money = 200
		stack_shop["money"] = 1000
		stack_shop["inventory"] = [
			{"item_id": "1006", "count": 2, "price": 10},
			{"item_id": "1006", "count": 3, "price": 10},
		]
		game_root.simulation.shop_sessions["trader_lao_wang_shop"] = stack_shop
		game_root.refresh_inventory_panel()
		game_root.refresh_trade_panel()
		var stacked_player_cart_button: Button = _trade_item_button_with_text(game_root, "player", "堆 1/2")
		if stacked_player_cart_button == null:
			errors.append("multi-stack player trade column should expose first stack button after direct-sell reset")
		else:
			stacked_player_cart_button.pressed.emit()
			_set_trade_quantity(game_root, 1)
			_press_queue_button(game_root)
			_press_confirm_cart_button(game_root)
			var cart_sell_player_stacks: Array = _array_or_empty(stack_player.inventory_stacks.get("1006", []))
			if cart_sell_player_stacks.size() != 2 or int(cart_sell_player_stacks[0]) != 1 or int(cart_sell_player_stacks[1]) != 3:
				errors.append("trade cart sell should consume selected first player stack: %s" % cart_sell_player_stacks)
		stack_player.inventory["1006"] = 1
		stack_player.inventory_stacks = stack_inventory_stacks_before.duplicate(true)
		stack_player.money = 200
		stack_shop["money"] = 1000
		stack_shop["inventory"] = [
			{"item_id": "1006", "count": 2, "price": 10},
			{"item_id": "1006", "count": 3, "price": 10},
		]
		game_root.simulation.shop_sessions["trader_lao_wang_shop"] = stack_shop
		game_root.refresh_inventory_panel()
		game_root.refresh_trade_panel()
	var stacked_buy: Dictionary = game_root.buy_active_trade_item("1006", 4)
	if not bool(stacked_buy.get("success", false)):
		errors.append("buying across shop stacks should succeed: %s" % stacked_buy)
	var after_buy_stacks: Array = _shop_stack_counts(game_root, "1006")
	if after_buy_stacks.size() != 1 or int(after_buy_stacks[0]) != 1:
		errors.append("buying across shop stacks should consume newest stacks first: %s" % after_buy_stacks)
	if _player_inventory_count(game_root, "1006") != 5:
		errors.append("buying across shop stacks should add combined count to player")
	var stacked_sell: Dictionary = game_root.sell_active_trade_item("1006", 2)
	if not bool(stacked_sell.get("success", false)):
		errors.append("selling to shop should append a new shop stack: %s" % stacked_sell)
	var after_sell_stacks: Array = _shop_stack_counts(game_root, "1006")
	if after_sell_stacks.size() != 2 or int(after_sell_stacks[0]) != 1 or int(after_sell_stacks[1]) != 2:
		errors.append("selling to shop should preserve old stack and append new stack: %s" % after_sell_stacks)
	game_root.simulation.shop_sessions = stack_shop_sessions_before.duplicate(true)
	stack_player.inventory = stack_inventory_before
	stack_player.inventory_order = stack_order_before
	stack_player.inventory_stacks = stack_inventory_stacks_before
	stack_player.money = stack_money_before
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()

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
	if not bool(game_root.gameplay_input_blocked_by_ui()):
		errors.append("equipment sell confirm should block gameplay input")
	if str(game_root.gameplay_input_blocker_name()) != "modal:equipment_sell_confirm":
		errors.append("equipment sell confirm blocker should be modal:equipment_sell_confirm")
	_assert_modal_stack(errors, game_root, "equipment_sell_confirm", "trade", "equipment sell confirmation")
	_assert_modal_menu_event(errors, game_root, "equipment_sell_confirm", "trade", "equipment sell confirmation menu event")
	var esc_equipment_sell_result: Dictionary = game_root.close_active_ui("keyboard_escape")
	if str(esc_equipment_sell_result.get("closed", "")) != "modal:equipment_sell_confirm":
		errors.append("Esc should close equipment sell modal before trade panel")
	if _equipment_sell_dialog_visible(game_root):
		errors.append("Esc should hide equipment sell modal")
	_assert_no_modal_menu_event(errors, game_root, "equipment sell confirmation Esc close menu event clear")
	if bool(_dictionary_or_empty(game_root.context_menu_snapshot()).get("active", false)):
		var context_close_result: Dictionary = game_root.close_active_context_menu()
		if not bool(context_close_result.get("success", false)):
			errors.append("closing leftover context menu after equipment sell modal should succeed: %s" % context_close_result)
	if not game_root.trade_panel.visible:
		errors.append("Esc closing equipment sell modal should keep trade panel open")
	if game_root.active_trade_target.is_empty():
		errors.append("Esc closing equipment sell modal should keep active trade target")
	if _player_equipped_item(game_root, "main_hand").is_empty():
		errors.append("Esc equipment sell close should keep main hand equipment")
	if _player_money(game_root) != money_before_equipped_sell:
		errors.append("Esc equipment sell close should keep player money")
	_press_trade_button(game_root)
	if not _equipment_sell_dialog_visible(game_root):
		errors.append("equipped item sell should reopen confirmation dialog")
	var trade_confirmed_before_equipment_sell: int = _event_count(game_root, "trade_confirmed")
	_confirm_equipment_sell_dialog(game_root)
	_finish_presentations(game_root)
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
	var permission_shop_snapshot: Dictionary = game_root.simulation.shop_sessions.duplicate(true)
	var relationship_before_permission: float = float(game_root.simulation.relationship_score(1, 2))
	var permission_shop: Dictionary = game_root.simulation.shop_sessions.get("trader_lao_wang_shop", {}).duplicate(true)
	permission_shop["required_relationship_min"] = 25.0
	permission_shop["target_actor_definition_id"] = "trader_lao_wang"
	game_root.simulation.shop_sessions["trader_lao_wang_shop"] = permission_shop
	game_root.simulation.set_relationship_score(1, 2, -25.0, "trade_ui_permission_low")
	game_root.refresh_trade_panel()
	if not _trade_feedback(game_root).contains("关系不足"):
		errors.append("low relationship trade panel should preview relationship feedback")
	if not _trade_item_disabled(game_root, "shop", "绷带"):
		errors.append("low relationship should disable shop item buttons")
	if _press_trade_item_with_text(game_root, "shop", "绷带") and not _trade_button_disabled(game_root):
		errors.append("low relationship should disable direct trade button")
	if not _queue_button_disabled(game_root):
		errors.append("low relationship should disable queue button")
	_drop_trade_item_with_text(game_root, "shop", "绷带")
	if not _cart_line(game_root).contains("购物车为空"):
		errors.append("low relationship should block dragging items into trade cart")
	var denied_buy_result: Dictionary = game_root.buy_active_trade_item("1006", 1)
	if str(denied_buy_result.get("reason", "")) != "trade_relationship_too_low":
		errors.append("low relationship trade buy should report trade_relationship_too_low")
	if not _trade_feedback(game_root).contains("关系不足"):
		errors.append("low relationship trade buy should show relationship feedback")
	var denied_sell_result: Dictionary = game_root.sell_active_trade_item("1006", 1)
	if str(denied_sell_result.get("reason", "")) != "trade_relationship_too_low":
		errors.append("low relationship trade sell should report trade_relationship_too_low")
	var denied_cart_result: Dictionary = game_root.confirm_active_trade_cart([{
		"source": "shop",
		"item_id": "1006",
		"count": 1,
	}])
	if str(denied_cart_result.get("reason", "")) != "trade_relationship_too_low":
		errors.append("low relationship trade cart should report trade_relationship_too_low")
	game_root.simulation.set_relationship_score(1, 2, 50.0, "trade_ui_permission_restored")
	var allowed_buy_before_money: int = _player_money(game_root)
	var allowed_buy_before_count: int = _player_inventory_count(game_root, "1006")
	var allowed_buy_result: Dictionary = game_root.buy_active_trade_item("1006", 1)
	if not bool(allowed_buy_result.get("success", false)):
		errors.append("restored relationship trade buy should succeed: %s" % allowed_buy_result.get("reason", "unknown"))
	elif _player_money(game_root) >= allowed_buy_before_money or _player_inventory_count(game_root, "1006") <= allowed_buy_before_count:
		errors.append("restored relationship trade buy should update money and inventory")
	game_root.simulation.shop_sessions = permission_shop_snapshot.duplicate(true)
	game_root.simulation.set_relationship_score(1, 2, relationship_before_permission, "trade_ui_permission_snapshot_restore")
	_set_player_money(game_root, 132)
	game_root.refresh_inventory_panel()
	game_root.refresh_trade_panel()
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
	var trade_closed_before_button: int = _event_count(game_root, "trade_closed")
	_press_close_button(game_root)
	if game_root.trade_panel.visible:
		errors.append("close button should close trade panel")
	if not game_root.active_trade_target.is_empty():
		errors.append("close button should clear active trade target")
	if _event_count(game_root, "trade_closed") <= trade_closed_before_button:
		errors.append("close button should emit trade_closed")
	_assert_trade_closed_payload(errors, game_root, "button", "close button")
	_reopen_trade(game_root, errors)
	var trade_closed_before_escape: int = _event_count(game_root, "trade_closed")
	_press_key(game_root, KEY_ESCAPE)
	if game_root.trade_panel.visible:
		errors.append("Esc should close trade panel")
	if not game_root.active_trade_target.is_empty():
		errors.append("Esc should clear active trade target")
	if _event_count(game_root, "trade_closed") <= trade_closed_before_escape:
		errors.append("Esc should emit trade_closed")
	_assert_trade_closed_payload(errors, game_root, "dialogue_closed:keyboard_escape", "Esc close")
	_reopen_trade(game_root, errors)
	var trade_closed_before_dialogue_leave: int = _event_count(game_root, "trade_closed")
	_close_trade_via_dialogue_leave(game_root, errors)
	if _event_count(game_root, "trade_closed") <= trade_closed_before_dialogue_leave:
		errors.append("dialogue leave should emit trade_closed")
	_assert_trade_closed_payload(errors, game_root, "dialogue_finished:leave", "dialogue leave")
	_reopen_trade(game_root, errors)
	game_root.active_trade_target = {"target_type": "actor", "actor_id": 9999}
	game_root.refresh_trade_panel()
	if game_root.trade_panel.visible:
		errors.append("missing trade target should close trade panel")
	if not game_root.active_trade_target.is_empty():
		errors.append("missing trade target should clear active trade target")
	_reopen_trade(game_root, errors)
	game_root.simulation.unlock_location("forest")
	var trade_closed_before_map_switch: int = _event_count(game_root, "trade_closed")
	var enter_result: Dictionary = game_root.simulation.enter_location(1, "forest", game_root.registry.get_library("overworld"))
	if not bool(enter_result.get("success", false)):
		errors.append("forest enter for trade close check failed: %s" % enter_result.get("reason", "unknown"))
	game_root.refresh_trade_panel()
	if game_root.trade_panel.visible:
		errors.append("map switch should close trade panel")
	if not game_root.active_trade_target.is_empty():
		errors.append("map switch should clear active trade target")
	if _event_count(game_root, "trade_closed") <= trade_closed_before_map_switch:
		errors.append("map switch should emit trade_closed")
	_assert_trade_closed_payload(errors, game_root, "target_unavailable", "map switch")
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


func _press_trade_shortcut(game_root: Node, key: int, shift_pressed: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.shift_pressed = shift_pressed
	event.pressed = true
	game_root.runtime_input_controller.input(event)
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.shift_pressed = shift_pressed
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


func _last_event_payload(game_root: Node, kind: String) -> Dictionary:
	var events: Array = game_root.simulation.snapshot().get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = events[index]
		if event_data.get("kind", "") == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


func _assert_trade_closed_payload(errors: Array[String], game_root: Node, expected_reason: String, context: String) -> void:
	var payload: Dictionary = _last_event_payload(game_root, "trade_closed")
	if int(payload.get("actor_id", 0)) != 1:
		errors.append("%s trade_closed should include actor_id" % context)
	if str(payload.get("reason", "")) != expected_reason:
		errors.append("%s trade_closed reason expected %s, got %s" % [context, expected_reason, payload.get("reason", "")])
	if str(payload.get("target_type", "")) != "actor":
		errors.append("%s trade_closed should include target_type" % context)
	if int(payload.get("target_actor_id", 0)) != 2:
		errors.append("%s trade_closed should include target_actor_id" % context)
	if str(payload.get("shop_id", "")) != "trader_lao_wang_shop":
		errors.append("%s trade_closed should include shop_id" % context)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _assert_modal_stack(errors: Array[String], game_root: Node, expected_id: String, expected_owner: String, context: String) -> void:
	if not game_root.has_method("modal_stack_snapshot"):
		errors.append("%s: game root should expose modal_stack_snapshot" % context)
		return
	var stack_snapshot: Dictionary = _dictionary_or_empty(game_root.modal_stack_snapshot())
	if not bool(stack_snapshot.get("active", false)) or int(stack_snapshot.get("count", 0)) <= 0:
		errors.append("%s: modal stack should be active: %s" % [context, stack_snapshot])
		return
	var top: Dictionary = _dictionary_or_empty(stack_snapshot.get("top", {}))
	if str(top.get("id", "")) != expected_id:
		errors.append("%s: modal stack top expected %s, got %s" % [context, expected_id, top])
	if str(top.get("owner_panel", "")) != expected_owner:
		errors.append("%s: modal stack owner expected %s, got %s" % [context, expected_owner, top])
	if not bool(top.get("blocks_gameplay", false)) or not bool(top.get("mouse_blocks_world", false)):
		errors.append("%s: modal stack top should block gameplay and mouse world input: %s" % [context, top])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_stack: Dictionary = _dictionary_or_empty(runtime.get("modal_stack", {}))
	if str(_dictionary_or_empty(runtime_stack.get("top", {})).get("id", "")) != expected_id:
		errors.append("%s: runtime modal stack should expose top %s: %s" % [context, expected_id, runtime_stack])


func _assert_modal_menu_event(errors: Array[String], game_root: Node, expected_id: String, expected_owner: String, context: String) -> void:
	if not game_root.has_method("menu_state_snapshot"):
		errors.append("%s: game root should expose menu_state_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot())
	var event: Dictionary = _dictionary_or_empty(snapshot.get("modal_event", {}))
	if event.is_empty():
		errors.append("%s: menu state should expose modal_event: %s" % [context, snapshot])
		return
	if str(event.get("event", "")) != "modal_opened" or str(event.get("panel_id", "")) != expected_id:
		errors.append("%s: modal event expected opened:%s, got %s" % [context, expected_id, event])
	if str(event.get("owner_panel", "")) != expected_owner:
		errors.append("%s: modal event owner expected %s, got %s" % [context, expected_owner, event])
	if not bool(event.get("blocks_gameplay", false)) or not bool(event.get("mouse_blocks_world", false)):
		errors.append("%s: modal event should expose gameplay and mouse blockers: %s" % [context, event])
	if not _recent_menu_events_contain(snapshot, "modal_opened", expected_id):
		errors.append("%s: recent events should include modal event %s: %s" % [context, expected_id, snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_menu: Dictionary = _dictionary_or_empty(runtime.get("menu_state", {}))
	var runtime_event: Dictionary = _dictionary_or_empty(runtime_menu.get("modal_event", {}))
	if str(runtime_event.get("event", "")) != "modal_opened" or str(runtime_event.get("panel_id", "")) != expected_id:
		errors.append("%s: runtime menu should expose modal event %s: %s" % [context, expected_id, runtime_menu])
	if not _recent_menu_events_contain(runtime_menu, "modal_opened", expected_id):
		errors.append("%s: runtime recent events should include modal event %s: %s" % [context, expected_id, runtime_menu])


func _assert_no_modal_menu_event(errors: Array[String], game_root: Node, context: String) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot() if game_root.has_method("menu_state_snapshot") else {})
	if not _dictionary_or_empty(snapshot.get("modal_event", {})).is_empty():
		errors.append("%s: modal_event should clear when no modal is active: %s" % [context, snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_menu: Dictionary = _dictionary_or_empty(runtime.get("menu_state", {}))
	if not _dictionary_or_empty(runtime_menu.get("modal_event", {})).is_empty():
		errors.append("%s: runtime modal_event should clear when no modal is active: %s" % [context, runtime_menu])


func _recent_menu_events_contain(menu_state: Dictionary, expected_event: String, expected_id: String) -> bool:
	for value in _array_or_empty(menu_state.get("recent_events", [])):
		var event: Dictionary = _dictionary_or_empty(value)
		if str(event.get("event", "")) == expected_event and str(event.get("panel_id", "")) == expected_id:
			return true
	return false


func _assert_panel_blocker(errors: Array[String], game_root: Node, panel_id: String, content_name: String, context: String) -> void:
	if str(game_root.gameplay_input_blocker_name()) != panel_id:
		errors.append("%s: blocker expected %s, got %s" % [context, panel_id, str(game_root.gameplay_input_blocker_name())])
	var snapshot: Dictionary = _dictionary_or_empty(game_root.gameplay_input_blocker_snapshot())
	if str(snapshot.get("panel_id", "")) != panel_id:
		errors.append("%s: blocker snapshot panel expected %s, got %s" % [context, panel_id, snapshot])
	if not bool(snapshot.get("mouse_blocks_world", false)) or not bool(snapshot.get("content_mouse_blocks_world", false)):
		errors.append("%s: panel blocker should stop mouse on root and content: %s" % [context, snapshot])
	var content := game_root.find_child(content_name, true, false) as Control
	if content == null or content.mouse_filter != Control.MOUSE_FILTER_STOP:
		errors.append("%s: %s should stop mouse input" % [context, content_name])


func _assert_trade_context_menu(errors: Array[String], game_root: Node, expected_item_id: String, expected_source: String, expected_label: String, context: String) -> void:
	if not game_root.has_method("context_menu_snapshot"):
		errors.append("%s: game root should expose context_menu_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.context_menu_snapshot())
	if not bool(snapshot.get("active", false)):
		errors.append("%s: context menu snapshot should be active: %s" % [context, snapshot])
		return
	var top: Dictionary = _dictionary_or_empty(snapshot.get("top", {}))
	if str(top.get("id", "")) != "trade_context_menu" or str(top.get("kind", "")) != "trade_item":
		errors.append("%s: expected trade context top, got %s" % [context, top])
	if str(top.get("owner_panel", "")) != "trade":
		errors.append("%s: trade context owner should be trade: %s" % [context, top])
	if str(top.get("item_id", "")) != expected_item_id:
		errors.append("%s: trade context item expected %s, got %s" % [context, expected_item_id, top])
	if str(top.get("source", "")) != expected_source:
		errors.append("%s: trade context source expected %s, got %s" % [context, expected_source, top])
	if int(top.get("selected_count", 0)) <= 0 or int(top.get("unit_price", 0)) <= 0 or int(top.get("total_price", 0)) <= 0:
		errors.append("%s: trade context should expose counts and prices: %s" % [context, top])
	if int(top.get("option_count", 0)) != 3:
		errors.append("%s: trade context menu should expose inspect/trade/queue options: %s" % [context, top])
	var expected_action_seen := false
	var queue_seen := false
	for option in _array_or_empty(top.get("options", [])):
		var option_data: Dictionary = _dictionary_or_empty(option)
		if str(option_data.get("label", "")) == expected_label:
			expected_action_seen = true
			if bool(option_data.get("disabled", true)):
				errors.append("%s: trade action should be enabled: %s" % [context, option_data])
			if not str(option_data.get("tooltip", "")).contains("小计"):
				errors.append("%s: trade action tooltip should expose subtotal: %s" % [context, option_data])
		if int(option_data.get("id", -1)) == 2:
			queue_seen = true
			if bool(option_data.get("disabled", true)):
				errors.append("%s: queue action should be enabled: %s" % [context, option_data])
	if not expected_action_seen:
		errors.append("%s: context menu should include %s: %s" % [context, expected_label, top])
	if not queue_seen:
		errors.append("%s: context menu should include queue option: %s" % [context, top])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_context: Dictionary = _dictionary_or_empty(runtime.get("context_menu", {}))
	var runtime_top: Dictionary = _dictionary_or_empty(runtime_context.get("top", {}))
	if str(runtime_top.get("id", "")) != "trade_context_menu" or str(runtime_top.get("item_id", "")) != expected_item_id:
		errors.append("%s: runtime context menu should expose trade item %s: %s" % [context, expected_item_id, runtime_context])


func _finish_presentations(game_root: Node) -> void:
	if game_root.has_method("finish_world_action_presentations"):
		game_root.finish_world_action_presentations()


func _press_close_button(game_root: Node) -> void:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CloseButton")
	if button is Button:
		(button as Button).pressed.emit()


func _reopen_trade(game_root: Node, errors: Array[String]) -> void:
	_finish_presentations(game_root)
	var trader_node: Node = game_root.find_child("Actor_trader_lao_wang_2", true, false)
	if trader_node == null:
		errors.append("missing trader actor node for trade reopen")
		return
	game_root.select_interaction_node(trader_node)
	var result: Dictionary = game_root.execute_primary_interaction()
	_finish_presentations(game_root)
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
	var leave_option_index := _dialogue_option_index(game_root, "leave_end")
	var leave_result: Dictionary = game_root.choose_dialogue_option(leave_option_index)
	if not bool(leave_result.get("success", false)) or str(leave_result.get("end_type", "")) != "leave":
		errors.append("dialogue leave option should finish with leave end_type")
	if game_root.trade_panel.visible:
		errors.append("dialogue leave should close trade panel")
	if not game_root.active_trade_target.is_empty():
		errors.append("dialogue leave should clear active trade target")


func _dialogue_option_index(game_root: Node, next_id: String) -> int:
	var snapshot: Dictionary = game_root._current_dialogue_snapshot()
	var options: Array = snapshot.get("options", [])
	for index in range(options.size()):
		var option: Dictionary = _dictionary_or_empty(options[index])
		if str(option.get("next", "")) == next_id:
			return index
	return 0


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
	return _drop_trade_item_with_text_on_target(game_root, source, text, _trade_cart_target(game_root), count)


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


func _drop_trade_item_to_zone(game_root: Node, source: String, text: String, zone_name: String, count: int = 1) -> bool:
	var target: Node = game_root.trade_panel.find_child(zone_name, true, false)
	if not target is Control:
		return false
	return _drop_trade_item_with_text_on_target(game_root, source, text, target, count)


func _can_drop_trade_item_to_zone(game_root: Node, source: String, text: String, zone_name: String, count: int = 1) -> bool:
	var button: Button = _trade_item_button_with_text(game_root, source, text)
	var target: Node = game_root.trade_panel.find_child(zone_name, true, false)
	if button == null or not button.has_meta("trade_item") or not button.has_meta("trade_source") or not target is Control:
		return false
	var item: Dictionary = button.get_meta("trade_item", {})
	return bool(game_root.trade_panel.call("_can_drop_cart_data", Vector2.ZERO, {
		"kind": "trade_item",
		"source": str(button.get_meta("trade_source", "")),
		"item": item.duplicate(true),
		"count": count,
	}, target))


func _drop_inventory_item_to_trade_cart(game_root: Node, text: String, count: int = 1) -> bool:
	var button: Button = _inventory_item_button(game_root, text)
	if button == null or not button.has_meta("inventory_item"):
		return false
	var item: Dictionary = button.get_meta("inventory_item", {})
	if item.is_empty():
		return false
	game_root.trade_panel.call("_drop_cart_data", Vector2.ZERO, {
		"kind": "inventory_item",
		"item": item.duplicate(true),
		"item_id": str(item.get("item_id", "")),
		"count": count,
	}, null)
	return true


func _drop_inventory_item_to_trade_zone(game_root: Node, text: String, zone_name: String, count: int = 1) -> bool:
	var button: Button = _inventory_item_button(game_root, text)
	var target: Node = game_root.trade_panel.find_child(zone_name, true, false)
	if button == null or not button.has_meta("inventory_item") or not target is Control:
		return false
	var item: Dictionary = button.get_meta("inventory_item", {})
	if item.is_empty():
		return false
	game_root.trade_panel.call("_drop_cart_data", Vector2.ZERO, {
		"kind": "inventory_item",
		"item": item.duplicate(true),
		"item_id": str(item.get("item_id", "")),
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


func _trade_item_icon_path(game_root: Node, source: String, text: String) -> String:
	var button: Button = _trade_item_button_with_text(game_root, source, text)
	if button == null or button.icon == null or not button.has_meta("icon_resource_path"):
		return ""
	return str(button.get_meta("icon_resource_path"))


func _trade_item_disabled(game_root: Node, source: String, text: String) -> bool:
	var button: Button = _trade_item_button_with_text(game_root, source, text)
	if button == null:
		return true
	return bool(button.disabled)


func _trade_zone_tooltip(game_root: Node, zone_name: String) -> String:
	var target: Node = game_root.trade_panel.find_child(zone_name, true, false)
	return "" if not target is Control else str((target as Control).tooltip_text)


func _trade_zone_control(game_root: Node, zone_name: String) -> Control:
	return game_root.trade_panel.find_child(zone_name, true, false) as Control


func _trade_cart_target(game_root: Node) -> Control:
	return game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartScroll/CartItemLines") as Control


func _trade_cart_entry_control(game_root: Node, index: int) -> Control:
	return game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartScroll/CartItemLines/CartEntry_%d" % index) as Control


func _trade_drag_data(game_root: Node, source: String, text: String) -> Dictionary:
	var button: Button = _trade_item_button_with_text(game_root, source, text)
	if button == null:
		return {}
	return _dictionary_or_empty(game_root.trade_panel.call("_get_trade_item_drag_data", Vector2.ZERO, button))


func _assert_drag_state_snapshot(errors: Array[String], game_root: Node, drag_data: Dictionary, target: Control, expected_kind: String, expected_source_owner: String, expected_target_kind: String, context: String) -> void:
	if drag_data.is_empty():
		errors.append("%s: drag data should be available" % context)
		return
	if not game_root.has_method("drag_state_snapshot"):
		errors.append("%s: game root should expose drag_state_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.drag_state_snapshot(drag_data, target))
	if not bool(snapshot.get("active", false)):
		errors.append("%s: drag snapshot should be active: %s" % [context, snapshot])
	if str(snapshot.get("kind", "")) != expected_kind:
		errors.append("%s: drag kind expected %s, got %s" % [context, expected_kind, snapshot])
	var source: Dictionary = _dictionary_or_empty(snapshot.get("source", {}))
	if str(source.get("owner_panel", "")) != expected_source_owner:
		errors.append("%s: source owner expected %s, got %s" % [context, expected_source_owner, snapshot])
	var target_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("target", {}))
	if str(target_snapshot.get("target_kind", "")) != expected_target_kind:
		errors.append("%s: target kind expected %s, got %s" % [context, expected_target_kind, snapshot])
	var preview: Dictionary = _dictionary_or_empty(snapshot.get("preview", {}))
	if not bool(preview.get("has_preview", false)) or str(preview.get("text", "")).is_empty():
		errors.append("%s: drag snapshot should expose preview text: %s" % [context, snapshot])
	_assert_drag_preview_diagnostics(errors, preview, context)
	var runtime_drag: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("drag", {}))
	if not runtime_drag.has("active") or not runtime_drag.has("target"):
		errors.append("%s: runtime control should expose drag state shape: %s" % [context, runtime_drag])


func _assert_trade_cart_hover_target(errors: Array[String], game_root: Node, drag_data: Dictionary, target: Control, expected_target_kind: String, expected_accept: bool, expected_reject_reason: String, context: String) -> void:
	if target == null:
		errors.append("%s: trade cart target should exist" % context)
		return
	if drag_data.is_empty():
		errors.append("%s: drag data should be available" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.drag_state_snapshot(drag_data, target))
	var target_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("target", {}))
	if str(target_snapshot.get("target_kind", "")) != expected_target_kind:
		errors.append("%s: target kind expected %s, got %s" % [context, expected_target_kind, snapshot])
	if not str(target_snapshot.get("accepts", "")).contains("trade_item") or not str(target_snapshot.get("accepts", "")).contains("trade_cart_entry"):
		errors.append("%s: trade cart target should declare accepted drag kinds: %s" % [context, target_snapshot])
	if bool(target_snapshot.get("last_accept", false)) != expected_accept:
		errors.append("%s: trade cart accept expected %s, got %s" % [context, expected_accept, target_snapshot])
	if str(target_snapshot.get("reject_reason", "")) != expected_reject_reason:
		errors.append("%s: trade cart reject reason expected %s, got %s" % [context, expected_reject_reason, target_snapshot])
	var highlight: Dictionary = _dictionary_or_empty(target_snapshot.get("hover_highlight", {}))
	_assert_drag_reject_reason_text(errors, target_snapshot, highlight, expected_reject_reason, context)
	var expected_style := "accept" if expected_accept else "reject"
	if not bool(highlight.get("active", false)) or str(highlight.get("style", "")) != expected_style:
		errors.append("%s: trade cart hover highlight should expose %s: %s" % [context, expected_style, highlight])


func _assert_trade_cart_hover_render(errors: Array[String], game_root: Node, drag_data: Dictionary, target: Control, expected_accept: bool, expected_reject_reason: String, context: String) -> void:
	if target == null:
		errors.append("%s: trade cart target should exist" % context)
		return
	if drag_data.is_empty():
		errors.append("%s: drag data should be available" % context)
		return
	var can_drop: bool = bool(game_root.trade_panel.call("_can_drop_cart_data", Vector2.ZERO, drag_data, target))
	if can_drop != expected_accept:
		errors.append("%s: trade cart can_drop expected %s, got %s" % [context, expected_accept, can_drop])
	if not bool(target.get_meta("trade_cart_drag_hovered", false)):
		errors.append("%s: trade cart target should record active hover render state" % context)
	if bool(target.get_meta("trade_cart_drag_last_accept", false)) != expected_accept:
		errors.append("%s: trade cart hover accept expected %s, got %s" % [context, expected_accept, target.get_meta("trade_cart_drag_last_accept", false)])
	if str(target.get_meta("trade_cart_drag_reject_reason", "")) != expected_reject_reason:
		errors.append("%s: trade cart hover reject reason expected %s, got %s" % [context, expected_reject_reason, target.get_meta("trade_cart_drag_reject_reason", "")])
	var expected_style := "accept" if expected_accept else "reject"
	var expected_color := "#4ecb71" if expected_accept else "#e25c5c"
	if str(target.get_meta("trade_cart_drag_highlight_style", "")) != expected_style:
		errors.append("%s: trade cart hover style expected %s, got %s" % [context, expected_style, target.get_meta("trade_cart_drag_highlight_style", "")])
	if str(target.get_meta("trade_cart_drag_highlight_color", "")) != expected_color:
		errors.append("%s: trade cart hover color expected %s, got %s" % [context, expected_color, target.get_meta("trade_cart_drag_highlight_color", "")])


func _assert_drag_reject_reason_text(errors: Array[String], target_snapshot: Dictionary, highlight: Dictionary, expected_reject_reason: String, context: String) -> void:
	var reason_text := str(target_snapshot.get("reject_reason_text", ""))
	var highlight_text := str(highlight.get("reject_reason_text", ""))
	if expected_reject_reason.is_empty():
		if not reason_text.is_empty() or not highlight_text.is_empty():
			errors.append("%s: accepted drag target should not expose reject reason text: %s / %s" % [context, target_snapshot, highlight])
		return
	if reason_text.is_empty():
		errors.append("%s: rejected drag target should expose reject reason text: %s" % [context, target_snapshot])
	if highlight_text != reason_text:
		errors.append("%s: hover highlight should mirror reject reason text: %s / %s" % [context, target_snapshot, highlight])


func _assert_drag_preview_diagnostics(errors: Array[String], preview: Dictionary, context: String) -> void:
	var position: Dictionary = _dictionary_or_empty(preview.get("screen_position", {}))
	var viewport: Dictionary = _dictionary_or_empty(preview.get("viewport_size", {}))
	var estimated_size: Dictionary = _dictionary_or_empty(preview.get("estimated_size", {}))
	var anchor: Dictionary = _dictionary_or_empty(preview.get("anchor", {}))
	if position.is_empty() or not position.has("x") or not position.has("y"):
		errors.append("%s: drag preview should expose screen position: %s" % [context, preview])
	if viewport.is_empty() or float(viewport.get("x", 0.0)) <= 0.0 or float(viewport.get("y", 0.0)) <= 0.0:
		errors.append("%s: drag preview should expose viewport size: %s" % [context, preview])
	if estimated_size.is_empty() or float(estimated_size.get("x", 0.0)) <= 0.0 or float(estimated_size.get("y", 0.0)) <= 0.0:
		errors.append("%s: drag preview should expose estimated size: %s" % [context, preview])
	if anchor.is_empty() or not anchor.has("x") or not anchor.has("y"):
		errors.append("%s: drag preview should expose anchor: %s" % [context, preview])
	if str(preview.get("lifecycle_state", "")) != "dragging":
		errors.append("%s: drag preview should expose dragging lifecycle: %s" % [context, preview])
	if str(preview.get("threshold_policy", "")) != "godot_default":
		errors.append("%s: drag preview should expose threshold policy: %s" % [context, preview])


func _trade_last_shortcut(game_root: Node) -> String:
	return str(game_root.trade_panel.get_meta("trade_last_shortcut", ""))


func _trade_zone_label_text(game_root: Node, zone_name: String) -> String:
	var target: Node = game_root.trade_panel.find_child(zone_name, true, false)
	if target == null:
		return ""
	var label: Node = target.get_child(0) if target.get_child_count() > 0 else null
	if label is Label:
		return str((label as Label).text)
	return ""


func _trade_zone_meta_text(game_root: Node, zone_name: String, key: String) -> String:
	var target: Node = game_root.trade_panel.find_child(zone_name, true, false)
	if target == null or not target.has_meta(key):
		return ""
	return str(target.get_meta(key))


func _trade_zone_last_accept(game_root: Node, zone_name: String) -> bool:
	var target: Node = game_root.trade_panel.find_child(zone_name, true, false)
	if target == null or not target.has_meta("trade_drop_last_accept"):
		return false
	return bool(target.get_meta("trade_drop_last_accept"))


func _trade_zone_reject_reason(game_root: Node, zone_name: String) -> String:
	var target: Node = game_root.trade_panel.find_child(zone_name, true, false)
	if target == null or not target.has_meta("trade_drop_reject_reason"):
		return ""
	return str(target.get_meta("trade_drop_reject_reason"))


func _open_inventory_context_menu(game_root: Node, item_needle: String) -> bool:
	var source: Button = _inventory_item_button(game_root, item_needle)
	if source == null or not source.has_meta("inventory_item"):
		return false
	game_root.inventory_panel.call("_open_context_menu_for_item", source.get_meta("inventory_item"), Vector2.ZERO)
	return true


func _open_trade_context_menu(game_root: Node, source: String, item_needle: String) -> bool:
	var button: Button = _trade_item_button_with_text(game_root, source, item_needle)
	if button == null or not button.has_meta("trade_item"):
		return false
	game_root.trade_panel.call("_open_context_menu_for_item", button.get_meta("trade_item"), str(button.get_meta("trade_source", source)), Vector2.ZERO)
	return true


func _inventory_item_button(game_root: Node, text: String) -> Button:
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemScroll/ItemLines")
	for child in item_box.get_children():
		if child is Button and str((child as Button).text).contains(text):
			return child as Button
	return null


func _context_action_disabled(game_root: Node, action_id: int) -> bool:
	var menu: PopupMenu = game_root.inventory_panel.find_child("InventoryContextMenu", true, false) as PopupMenu
	if menu == null:
		return true
	var index: int = menu.get_item_index(action_id)
	if index < 0:
		return true
	return menu.is_item_disabled(index)


func _execute_inventory_context_action(game_root: Node, action_id: int) -> void:
	game_root.inventory_panel.call("_execute_context_action", action_id)


func _execute_trade_context_action(game_root: Node, action_id: int) -> void:
	game_root.trade_panel.call("_execute_context_action", action_id)


func _close_trade_context_menu(game_root: Node) -> void:
	if game_root.trade_panel != null and game_root.trade_panel.has_method("close_context_menu"):
		game_root.trade_panel.call("close_context_menu")


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


func _trade_button_tooltip(game_root: Node) -> String:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/TradeControls/TradeButton")
	if button is Button:
		return str((button as Button).tooltip_text)
	return ""


func _queue_button_disabled(game_root: Node) -> bool:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartControls/QueueButton")
	if button is Button:
		return bool((button as Button).disabled)
	return true


func _queue_button_tooltip(game_root: Node) -> String:
	var button: Node = game_root.trade_panel.get_node_or_null("TradePanel/TradeLines/CartControls/QueueButton")
	if button is Button:
		return str((button as Button).tooltip_text)
	return ""


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
	var total := 0
	for shop_id in game_root.simulation.shop_sessions.keys():
		var shop: Dictionary = game_root.simulation.shop_sessions[shop_id]
		for entry in shop.get("inventory", []):
			var entry_data: Dictionary = entry
			if str(entry_data.get("item_id", "")) == item_id:
				total += max(0, int(entry_data.get("count", 0)))
	return total


func _shop_stack_counts(game_root: Node, item_id: String) -> Array[int]:
	var stacks: Array[int] = []
	var shop: Dictionary = _dictionary_or_empty(game_root.simulation.shop_sessions.get("trader_lao_wang_shop", {}))
	for entry in _array_or_empty(shop.get("inventory", [])):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if str(entry_data.get("item_id", "")) != item_id:
			continue
		var count: int = max(0, int(entry_data.get("count", 0)))
		if count > 0:
			stacks.append(count)
	return stacks


func _set_player_money(game_root: Node, money: int) -> void:
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor != null:
		actor.money = money


func _add_player_inventory_item(game_root: Node, item_id: String, count: int) -> void:
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor == null:
		return
	actor.inventory[item_id] = int(actor.inventory.get(item_id, 0)) + count
	if not actor.inventory_order.has(item_id):
		actor.inventory_order.append(item_id)


func _remove_player_inventory_item(game_root: Node, item_id: String) -> void:
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor == null:
		return
	actor.inventory.erase(item_id)
	actor.inventory_order.erase(item_id)


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
