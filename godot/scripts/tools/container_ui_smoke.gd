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

	print("container_ui_smoke passed:")
	print(JSON.stringify({
		"container_summary": _container_summary(game_root),
		"container_items": _container_item_lines(game_root),
		"inventory_summary": _inventory_summary(game_root),
	}, "\t"))
	quit(0)


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	if game_root.container_panel == null:
		return ["container panel was not created"]

	var container_node: Node = game_root.find_child("MapObject_survivor_outpost_01_clinic_supply_cabinet", true, false)
	if container_node == null:
		return ["missing generated container node"]
	game_root.select_interaction_node(container_node)
	var open_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(open_result.get("success", false)):
		errors.append("container open failed: %s" % open_result.get("reason", "unknown"))
	_finish_presentations(game_root)
	if not game_root.container_panel.visible:
		errors.append("container panel should be visible after opening container")
	_assert_panel_blocker(errors, game_root, "container", "ContainerPanel", "container open")
	var opened_session: Dictionary = _container_session(game_root.simulation.snapshot(), "survivor_outpost_01_clinic_supply_cabinet")
	if str(opened_session.get("container_type", "")) != "map":
		errors.append("opened map container session should expose container_type=map")
	if str(opened_session.get("container_origin", "")) != "map_scene":
		errors.append("opened map container session should expose container_origin=map_scene")
	var panel: Node = game_root.container_panel.get_node_or_null("ContainerPanel")
	if panel == null or str(panel.get_meta("container_type", "")) != "map":
		errors.append("container panel should preserve active container type metadata")
	if not _container_summary(game_root).contains("2 类物品"):
		errors.append("container summary should expose initial entries")
	if not _container_text(game_root).contains("抗生素"):
		errors.append("container column should expose container items")
	if not _container_player_text(game_root).contains("水瓶"):
		errors.append("player column should expose inventory items")
	if _container_item_icon_path(game_root, "container", "绷带") != "res://assets/icons/items/bandage.svg":
		errors.append("container item row should expose and render item icon")
	if _container_item_icon_path(game_root, "player", "水瓶") != "res://assets/icons/items/water_bottle.svg":
		errors.append("container player item row should expose and render item icon")
	if not _container_text(game_root).contains("kg") or not _container_player_text(game_root).contains("kg"):
		errors.append("container columns should expose basic item detail text")
	if not _container_has_scroll_columns(game_root):
		errors.append("container panel should wrap both item columns in scroll containers")
	if not _container_detail(game_root).contains("容器：") or not _container_detail(game_root).contains("单重"):
		errors.append("container detail line should default to selected container item details")
	game_root.active_container_feedback = {
		"type": "error",
		"reason": "unknown_container_transfer_source",
		"container_id": _active_container_id(game_root),
	}
	game_root.refresh_container_panel()
	if not _container_feedback(game_root).contains("未知容器转移来源"):
		errors.append("container feedback should use reason catalog fallback for unhandled reasons")
	game_root.active_container_feedback = {}
	game_root.refresh_container_panel()
	_press_first_player_container_item(game_root)
	if not _container_detail(game_root).contains("背包：") or not _container_detail(game_root).contains("总重"):
		errors.append("container detail line should switch to selected player item details")
	if _container_transfer_button_text(game_root) != "存放":
		errors.append("selecting player item should set transfer action to store")
	if not _open_container_context_menu(game_root, "container", "抗生素"):
		errors.append("should open container item context menu for antibiotics")
	else:
		_assert_container_context_menu(errors, game_root, "1031", "container", "拿取选中数量", "container antibiotics context")
		_execute_container_context_action(game_root, 1)
		if not _event_seen(game_root, "container_item_taken"):
			errors.append("container context selected transfer should emit container_item_taken")
		if not _container_player_text(game_root).contains("抗生素 x1"):
			errors.append("container context selected transfer should move item to player column")
		if not _drop_container_item_with_text(game_root, "player", "抗生素", "container"):
			errors.append("container context setup should restore antibiotics to container")
	if not _open_container_context_menu(game_root, "player", "水瓶"):
		errors.append("should open container player item context menu for water bottle")
	else:
		_assert_container_context_menu(errors, game_root, "1008", "player", "存放选中数量", "container player water context")
		_execute_container_context_action(game_root, 2)
		if not _event_seen(game_root, "container_item_stored"):
			errors.append("container context all transfer should emit container_item_stored")
		if not _container_text(game_root).contains("水瓶 x1"):
			errors.append("container context all transfer should store player water bottle")
		if not _drop_container_item_with_text(game_root, "container", "水瓶", "player"):
			errors.append("container context setup should restore water bottle to player")
	if not _press_container_item_with_text(game_root, "player", "手枪弹药"):
		errors.append("should select stacked ammo in player column for quantity controls")
	else:
		if not _container_quantity_label(game_root).contains("1/10"):
			errors.append("quantity label should show selected stacked item range")
		_press_container_quantity_all(game_root)
		if _container_quantity_spin_value(game_root) != 10 or not _container_quantity_label(game_root).contains("10/10"):
			errors.append("quantity all button should select full stacked count")
		if not _container_quantity_button_disabled(game_root, "QuantityPlusButton"):
			errors.append("quantity plus should be disabled at max count")
		if not _container_quantity_button_disabled(game_root, "QuantityAllButton"):
			errors.append("quantity all should be disabled at max count")
		if _container_quantity_button_disabled(game_root, "QuantityMinusButton"):
			errors.append("quantity minus should be enabled above one")
		_press_container_quantity_minus(game_root)
		if _container_quantity_spin_value(game_root) != 9 or not _container_quantity_label(game_root).contains("9/10"):
			errors.append("quantity minus should decrement selected count")
		_set_container_transfer_quantity(game_root, 1)
		if not _container_transfer_tooltip(game_root).contains("x1"):
			errors.append("transfer tooltip should include current selected quantity")
		_set_container_transfer_quantity(game_root, 3)
		var stored_ammo_before: int = _event_count(game_root, "container_item_stored")
		_press_container_transfer(game_root)
		_assert_container_quantity_modal(errors, game_root, "player", "1009", 3, "container quantity transfer open")
		if _event_count(game_root, "container_item_stored") != stored_ammo_before:
			errors.append("quantity modal should not transfer before confirmation")
		var modal_close_result: Dictionary = _dictionary_or_empty(game_root.close_active_ui())
		if str(modal_close_result.get("closed", "")) != "modal:container_quantity_confirm":
			errors.append("Esc close should dismiss container quantity modal first, got %s" % modal_close_result)
		if not game_root.container_panel.visible:
			errors.append("closing quantity modal should keep container panel open")
		_assert_no_container_quantity_modal(errors, game_root, "container quantity transfer Esc close")
		_press_container_transfer(game_root)
		_assert_container_quantity_modal(errors, game_root, "player", "1009", 3, "container quantity transfer reopen")
		_confirm_container_quantity_modal(game_root)
		if _event_count(game_root, "container_item_stored") <= stored_ammo_before:
			errors.append("confirming quantity modal should store selected ammo")
		if not _container_text(game_root).contains("手枪弹药 x3"):
			errors.append("confirmed quantity modal should move selected ammo into container")
		if not _drop_container_item_with_text(game_root, "container", "手枪弹药", "player"):
			errors.append("quantity modal smoke should restore ammo to player column")
		_set_container_transfer_quantity(game_root, 1)

	if not _drop_container_item_with_text(game_root, "container", "抗生素", "player"):
		errors.append("should drag antibiotics from container to player column")
	if not _event_seen(game_root, "container_item_taken"):
		errors.append("dragging container item to player column should emit container_item_taken")
	if not _event_seen(game_root, "container_transferred"):
		errors.append("dragging container item to player column should emit container_transferred")
	if not _inventory_text(game_root).contains("抗生素 x1"):
		errors.append("dragged antibiotics should appear in inventory panel")
	if not _container_player_text(game_root).contains("抗生素 x1"):
		errors.append("dragged antibiotics should appear in container player column")
	if _container_text(game_root).contains("抗生素"):
		errors.append("dragging antibiotics out should remove them from container column")
	if not _drop_container_item_with_text(game_root, "player", "抗生素", "container"):
		errors.append("should drag antibiotics from player column back to container")
	if not _event_seen(game_root, "container_item_stored"):
		errors.append("dragging player item to container column should emit container_item_stored")
	if not _event_seen(game_root, "container_transferred"):
		errors.append("dragging player item to container column should emit container_transferred")
	if not _container_text(game_root).contains("抗生素 x1"):
		errors.append("dragged antibiotics should return to container column")
	if _container_player_text(game_root).contains("抗生素 x1"):
		errors.append("dragged antibiotics should leave player column after storing")
	var capacity_player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	var capacity_session_before: Dictionary = game_root.simulation.container_sessions.get("survivor_outpost_01_clinic_supply_cabinet", {}).duplicate(true)
	var capacity_session: Dictionary = capacity_session_before.duplicate(true)
	var capacity_inventory_before: Dictionary = capacity_player.inventory.duplicate(true)
	var capacity_order_before: Array = capacity_player.inventory_order.duplicate()
	var capacity_equipment_before: Dictionary = capacity_player.equipment.duplicate(true)
	capacity_player.inventory.clear()
	capacity_player.inventory_order.clear()
	capacity_player.equipment.clear()
	capacity_player.inventory["1003"] = 50
	capacity_session["inventory"] = [{"item_id": "1003", "count": 1}]
	game_root.simulation.container_sessions["survivor_outpost_01_clinic_supply_cabinet"] = capacity_session
	game_root.refresh_container_panel()
	var overweight_take: Dictionary = game_root.take_active_container_item("1003", 1)
	if str(overweight_take.get("reason", "")) != "inventory_over_capacity":
		errors.append("overweight container take should report inventory_over_capacity")
	if not _container_feedback(game_root).contains("负重不足"):
		errors.append("overweight container take should show capacity feedback")
	if int(capacity_player.inventory.get("1003", 0)) != 50:
		errors.append("failed overweight container take should not add item")
	game_root.simulation.container_sessions["survivor_outpost_01_clinic_supply_cabinet"] = capacity_session_before.duplicate(true)
	capacity_player.inventory = capacity_inventory_before
	_restore_inventory_order(capacity_player, capacity_order_before)
	capacity_player.equipment = capacity_equipment_before
	game_root.refresh_container_panel()

	var invalid_take: Dictionary = game_root.take_active_container_item("1031", 0)
	if invalid_take.get("reason", "") != "invalid_quantity":
		errors.append("taking zero items should report invalid_quantity")
	if not _container_feedback(game_root).contains("数量无效"):
		errors.append("taking zero items should show invalid quantity feedback")
	if not _container_text(game_root).contains("抗生素 x1"):
		errors.append("invalid take quantity should not mutate container inventory")
	var invalid_store: Dictionary = game_root.store_active_container_item("1008", 0)
	if invalid_store.get("reason", "") != "invalid_quantity":
		errors.append("storing zero items should report invalid_quantity")
	if not _container_feedback(game_root).contains("数量无效"):
		errors.append("storing zero items should show invalid quantity feedback")
	if not _container_player_text(game_root).contains("水瓶 x1"):
		errors.append("invalid store quantity should not mutate player inventory")

	var bulk_player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	var bulk_sessions_before: Dictionary = game_root.simulation.container_sessions.duplicate(true)
	var bulk_active_before: String = _active_container_id(game_root)
	var bulk_inventory_before: Dictionary = bulk_player.inventory.duplicate(true)
	var bulk_order_before: Array = bulk_player.inventory_order.duplicate()
	var bulk_money_before: int = int(bulk_player.money)
	game_root.simulation.container_sessions["bulk_take_container"] = {
		"container_id": "bulk_take_container",
		"display_name": "批量拿取测试容器",
		"inventory": [
			{"item_id": "1006", "count": 2},
			{"item_id": "1031", "count": 1},
		],
		"money": 7,
	}
	bulk_player.inventory = {}
	bulk_player.inventory_order.clear()
	bulk_player.money = 0
	_set_active_container_id(game_root, "bulk_take_container")
	game_root.refresh_inventory_panel()
	game_root.refresh_container_panel()
	if _container_bulk_button_disabled(game_root, "TakeAllButton"):
		errors.append("take all button should be enabled for non-empty container")
	_press_container_bulk_button(game_root, "TakeAllButton")
	var bulk_take_session: Dictionary = _dictionary_or_empty(game_root.simulation.container_sessions.get("bulk_take_container", {}))
	if _container_entry_count(_array_or_empty(bulk_take_session.get("inventory", [])), "1006") != 0 or _container_entry_count(_array_or_empty(bulk_take_session.get("inventory", [])), "1031") != 0:
		errors.append("take all should clear container item inventory")
	if int(bulk_take_session.get("money", -1)) != 0:
		errors.append("take all should clear container money")
	if int(bulk_player.inventory.get("1006", 0)) != 2 or int(bulk_player.inventory.get("1031", 0)) != 1 or int(bulk_player.money) != 7:
		errors.append("take all should move all container items and money to player")
	if not _event_seen(game_root, "container_bulk_transferred"):
		errors.append("take all should emit container_bulk_transferred")

	game_root.simulation.container_sessions["bulk_store_container"] = {
		"container_id": "bulk_store_container",
		"display_name": "批量存放测试容器",
		"inventory": [],
		"money": 0,
	}
	bulk_player.inventory = {"1008": 2, "1006": 1}
	_restore_inventory_order(bulk_player, ["1008", "1006"])
	_set_active_container_id(game_root, "bulk_store_container")
	game_root.refresh_inventory_panel()
	game_root.refresh_container_panel()
	if _container_bulk_button_disabled(game_root, "StoreAllButton"):
		errors.append("store all button should be enabled for non-empty player inventory")
	_press_container_bulk_button(game_root, "StoreAllButton")
	var bulk_store_session: Dictionary = _dictionary_or_empty(game_root.simulation.container_sessions.get("bulk_store_container", {}))
	if _container_entry_count(_array_or_empty(bulk_store_session.get("inventory", [])), "1008") != 2 or _container_entry_count(_array_or_empty(bulk_store_session.get("inventory", [])), "1006") != 1:
		errors.append("store all should move all player items to container")
	if int(bulk_player.inventory.get("1008", 0)) != 0 or int(bulk_player.inventory.get("1006", 0)) != 0:
		errors.append("store all should remove moved items from player inventory")
	game_root.simulation.container_sessions = bulk_sessions_before.duplicate(true)
	bulk_player.inventory = bulk_inventory_before
	_restore_inventory_order(bulk_player, bulk_order_before)
	bulk_player.money = bulk_money_before
	_set_active_container_id(game_root, bulk_active_before)
	game_root.refresh_inventory_panel()
	game_root.refresh_container_panel()

	if not _press_container_item_with_text(game_root, "container", "抗生素"):
		errors.append("should select antibiotics in container column")
	if _container_transfer_button_text(game_root) != "拿取":
		errors.append("selecting container item should set transfer action to take")
	_set_container_transfer_quantity(game_root, 1)
	_press_container_transfer(game_root)
	if not _event_seen(game_root, "container_item_taken"):
		errors.append("taking container item should emit container_item_taken")
	if not _event_seen(game_root, "container_transferred"):
		errors.append("taking container item should emit container_transferred")
	if not _inventory_text(game_root).contains("抗生素 x1"):
		errors.append("inventory panel missing taken antibiotics")
	if not _container_player_text(game_root).contains("抗生素 x1"):
		errors.append("container player column missing taken antibiotics")
	if _container_text(game_root).contains("抗生素"):
		errors.append("container panel should remove taken antibiotics")

	var exhausted_take: Dictionary = game_root.take_active_container_item("1031", 1)
	if exhausted_take.get("reason", "") != "container_inventory_insufficient":
		errors.append("taking missing container item should report container_inventory_insufficient")
	if not _container_feedback(game_root).contains("容器中没有足够的抗生素"):
		errors.append("taking missing container item should show container failure feedback")

	if not _press_container_item_with_text(game_root, "player", "水瓶"):
		errors.append("should select water bottle in player column")
	if _container_transfer_button_text(game_root) != "存放":
		errors.append("selecting player item should keep transfer action as store")
	_set_container_transfer_quantity(game_root, 1)
	_press_container_transfer(game_root)
	if not _container_feedback(game_root).is_empty():
		errors.append("successful container store should clear previous failure feedback")
	if not _event_seen(game_root, "container_item_stored"):
		errors.append("storing container item should emit container_item_stored")
	if not _event_seen(game_root, "container_transferred"):
		errors.append("storing container item should emit container_transferred")
	if not _container_text(game_root).contains("水瓶 x1"):
		errors.append("container panel missing stored water bottle")
	if _container_player_text(game_root).contains("水瓶 x1"):
		errors.append("container player column should remove stored water bottle")
	if _inventory_text(game_root).contains("水瓶 x1"):
		errors.append("inventory panel should remove stored water bottle")
	player_refill_water(game_root)
	if not _drop_inventory_item_to_container(game_root, "水瓶"):
		errors.append("should drag inventory water bottle into active container")
	if not _event_seen(game_root, "container_item_stored"):
		errors.append("dragging from inventory panel to container should emit container_item_stored")
	if not _container_text(game_root).contains("水瓶 x2"):
		errors.append("inventory drag should store water bottle into container column")
	if _inventory_text(game_root).contains("水瓶 x1"):
		errors.append("inventory drag should remove stored water bottle from inventory panel")
	var money_player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if money_player == null:
		errors.append("missing player for container money check")
		return errors
	game_root.simulation.container_sessions["temporary_money_container"] = {
		"container_id": "temporary_money_container",
		"display_name": "临时金钱容器",
		"inventory": [],
		"money": 23,
	}
	money_player.active_container_id = "temporary_money_container"
	game_root.refresh_container_panel()
	if not _container_text(game_root).contains("金钱 x23"):
		errors.append("container money should appear as a takeable row")
	if not _press_container_item_with_text(game_root, "container", "金钱"):
		errors.append("should select container money row")
	else:
		if not _container_detail(game_root).contains("容器：金钱 x23"):
			errors.append("money detail should not use item weight copy")
		if _container_transfer_button_text(game_root) != "拿取":
			errors.append("selecting container money should use take action")
		_press_container_quantity_all(game_root)
		_press_container_transfer(game_root)
		_assert_container_quantity_modal(errors, game_root, "container", "money", 23, "container money quantity transfer")
		_confirm_container_quantity_modal(game_root)
		if not _event_seen(game_root, "container_money_taken"):
			errors.append("taking container money should emit container_money_taken")
		if not _event_seen(game_root, "container_transferred"):
			errors.append("taking container money should emit container_transferred")
		if _container_text(game_root).contains("金钱 x23"):
			errors.append("taken container money should disappear from container column")
		var money_session: Dictionary = _dictionary_or_empty(game_root.simulation.container_sessions.get("temporary_money_container", {}))
		if int(money_session.get("money", -1)) != 0:
			errors.append("taking container money should clear session money")
	money_player.active_container_id = str(open_result.get("container", {}).get("container_id", "survivor_outpost_01_clinic_supply_cabinet"))
	game_root.refresh_container_panel()
	player_refill_water(game_root)
	if not _open_inventory_context_menu(game_root, "水瓶"):
		errors.append("should open inventory context menu for water bottle while container is active")
	elif _context_action_disabled(game_root, 9):
		errors.append("inventory context menu should enable store-in-container when a container is active")
	else:
		_execute_inventory_context_action(game_root, 9)
		if bool(_dictionary_or_empty(game_root.context_menu_snapshot()).get("active", false)):
			errors.append("inventory context store should close context menu after execution")
		if not _event_seen(game_root, "container_item_stored"):
			errors.append("inventory context store should emit container_item_stored")
		if not _container_text(game_root).contains("水瓶 x3"):
			errors.append("inventory context store should move water bottle into container")
		if _inventory_text(game_root).contains("水瓶 x1"):
			errors.append("inventory context store should remove water bottle from inventory panel")

	var missing_store: Dictionary = game_root.store_active_container_item("1008", 1)
	if missing_store.get("reason", "") != "not_enough_items":
		errors.append("storing unavailable item should report not_enough_items")
	if not _container_feedback(game_root).contains("背包中没有足够的水瓶"):
		errors.append("storing unavailable item should show inventory failure feedback")
	var capacity_store_snapshot: Dictionary = game_root.simulation.container_sessions.duplicate(true)
	var active_container_before_capacity: String = _active_container_id(game_root)
	var capacity_store_player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	var capacity_store_inventory_before: Dictionary = capacity_store_player.inventory.duplicate(true)
	var capacity_store_order_before: Array = capacity_store_player.inventory_order.duplicate()
	game_root.simulation.container_sessions["limited_capacity_container"] = {
		"container_id": "limited_capacity_container",
		"display_name": "容量测试容器",
		"inventory": [{"item_id": "1031", "count": 1}],
		"money": 0,
		"max_weight": 0.3,
	}
	_set_active_container_id(game_root, "limited_capacity_container")
	capacity_store_player.inventory["1008"] = 1
	if not capacity_store_player.inventory_order.has("1008"):
		capacity_store_player.inventory_order.append("1008")
	game_root.refresh_container_panel()
	var container_over_capacity: Dictionary = game_root.store_active_container_item("1008", 1)
	if str(container_over_capacity.get("reason", "")) != "container_over_capacity" or str(container_over_capacity.get("limit_kind", "")) != "weight":
		errors.append("storing into overweight container should report container_over_capacity/weight")
	if not _container_feedback(game_root).contains("容器容量不足"):
		errors.append("overweight container store should show container capacity feedback")
	if int(capacity_store_player.inventory.get("1008", 0)) != 1:
		errors.append("failed container capacity store should keep player item")
	var limited_session: Dictionary = _dictionary_or_empty(game_root.simulation.container_sessions.get("limited_capacity_container", {}))
	if _container_entry_count(_array_or_empty(limited_session.get("inventory", [])), "1008") != 0:
		errors.append("failed container capacity store should not add item to container")
	game_root.simulation.container_sessions = capacity_store_snapshot.duplicate(true)
	capacity_store_player.inventory = capacity_store_inventory_before
	_restore_inventory_order(capacity_store_player, capacity_store_order_before)
	_set_active_container_id(game_root, active_container_before_capacity)
	game_root.refresh_container_panel()
	var permission_snapshot: Dictionary = game_root.simulation.container_sessions.duplicate(true)
	var active_container_before_permission: String = _active_container_id(game_root)
	game_root.simulation.container_sessions["locked_permission_container"] = {
		"container_id": "locked_permission_container",
		"display_name": "锁定权限容器",
		"inventory": [{"item_id": "1006", "count": 2}],
		"money": 11,
		"locked": true,
	}
	_set_active_container_id(game_root, "locked_permission_container")
	game_root.refresh_container_panel()
	var locked_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if str(locked_take.get("reason", "")) != "container_locked":
		errors.append("locked container take should report container_locked")
	if not _container_feedback(game_root).contains("已锁定"):
		errors.append("locked container take should show locked feedback")
	var locked_money: Dictionary = game_root.take_active_container_money(1)
	if str(locked_money.get("reason", "")) != "container_locked":
		errors.append("locked container money take should report container_locked")
	game_root.simulation.container_sessions["key_required_container"] = {
		"container_id": "key_required_container",
		"display_name": "钥匙权限容器",
		"inventory": [{"item_id": "1006", "count": 1}],
		"money": 0,
		"locked": true,
		"required_item_ids": ["1138"],
	}
	_set_active_container_id(game_root, "key_required_container")
	game_root.refresh_container_panel()
	var key_permission_text := _container_permission_text(game_root)
	if not key_permission_text.contains("锁定") or not key_permission_text.contains("钥匙"):
		errors.append("key-required container should preview locked key permission")
	var missing_key_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if str(missing_key_take.get("reason", "")) != "container_key_missing":
		errors.append("key-required container should report container_key_missing")
	if not _container_feedback(game_root).contains("钥匙"):
		errors.append("key-required container should show missing key feedback")
	var permission_player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	permission_player.inventory["1138"] = 1
	var key_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if not bool(key_take.get("success", false)):
		errors.append("key-required locked container should allow take with key: %s" % key_take.get("reason", "unknown"))
	game_root.simulation.container_sessions["consuming_key_container"] = {
		"container_id": "consuming_key_container",
		"display_name": "消耗钥匙容器",
		"inventory": [{"item_id": "1006", "count": 1}],
		"money": 0,
		"locked": true,
		"required_item_ids": ["1138"],
		"consume_required_items_on_unlock": true,
	}
	_set_active_container_id(game_root, "consuming_key_container")
	permission_player.inventory["1138"] = 1
	game_root.refresh_container_panel()
	var consuming_key_permission_text := _container_permission_text(game_root)
	if not consuming_key_permission_text.contains("解锁消耗钥匙"):
		errors.append("consuming key container should preview key consumption")
	var consuming_key_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if not bool(consuming_key_take.get("success", false)):
		errors.append("consuming key container should allow take with key: %s" % consuming_key_take.get("reason", "unknown"))
	if int(permission_player.inventory.get("1138", 0)) != 0:
		errors.append("consuming key container should consume one key")
	if not bool(consuming_key_take.get("unlock_requirements_consumed", false)):
		errors.append("consuming key container should report consumed unlock requirements")
	var consuming_key_session: Dictionary = _dictionary_or_empty(game_root.simulation.container_sessions.get("consuming_key_container", {}))
	if bool(consuming_key_session.get("locked", true)) or not bool(consuming_key_session.get("unlock_requirements_consumed", false)):
		errors.append("consuming key container should persist unlocked state")
	if not _event_seen(game_root, "container_unlocked") or not _event_seen(game_root, "unlock_requirement_consumed"):
		errors.append("consuming key container should emit unlock consumption events")
	game_root.simulation.container_sessions["tool_required_container"] = {
		"container_id": "tool_required_container",
		"display_name": "工具权限容器",
		"inventory": [],
		"money": 0,
		"required_tool_ids": ["1150"],
	}
	_set_active_container_id(game_root, "tool_required_container")
	game_root.refresh_container_panel()
	if not _container_permission_text(game_root).contains("工具"):
		errors.append("tool-required container should preview required tool")
	player_refill_water(game_root)
	var missing_tool_store: Dictionary = game_root.store_active_container_item("1008", 1)
	if str(missing_tool_store.get("reason", "")) != "container_tool_missing":
		errors.append("tool-required container should report container_tool_missing")
	if not _container_feedback(game_root).contains("撬锁器"):
		errors.append("tool-required container should show missing tool feedback")
	permission_player.inventory["1150"] = 1
	var tool_store: Dictionary = game_root.store_active_container_item("1008", 1)
	if not bool(tool_store.get("success", false)):
		errors.append("tool-required container should allow store with tool: %s" % tool_store.get("reason", "unknown"))
	game_root.simulation.container_sessions["consuming_tool_container"] = {
		"container_id": "consuming_tool_container",
		"display_name": "消耗工具容器",
		"inventory": [],
		"money": 0,
		"locked": true,
		"required_tool_ids": ["1150"],
		"consume_required_tools_on_unlock": true,
	}
	_set_active_container_id(game_root, "consuming_tool_container")
	player_refill_water(game_root)
	permission_player.inventory["1150"] = 1
	game_root.refresh_container_panel()
	if not _container_permission_text(game_root).contains("解锁消耗工具"):
		errors.append("consuming tool container should preview tool consumption")
	var consuming_tool_store: Dictionary = game_root.store_active_container_item("1008", 1)
	if not bool(consuming_tool_store.get("success", false)):
		errors.append("consuming tool container should allow store with tool: %s" % consuming_tool_store.get("reason", "unknown"))
	if int(permission_player.inventory.get("1150", 0)) != 0:
		errors.append("consuming tool container should consume one tool")
	if not bool(consuming_tool_store.get("unlock_requirements_consumed", false)):
		errors.append("consuming tool container should report consumed unlock requirements")
	var consuming_tool_session: Dictionary = _dictionary_or_empty(game_root.simulation.container_sessions.get("consuming_tool_container", {}))
	if bool(consuming_tool_session.get("locked", true)) or not bool(consuming_tool_session.get("unlock_requirements_consumed", false)):
		errors.append("consuming tool container should persist unlocked state")
	game_root.simulation.container_sessions["store_forbidden_container"] = {
		"container_id": "store_forbidden_container",
		"display_name": "禁止存放容器",
		"inventory": [],
		"money": 0,
		"allow_store": false,
	}
	_set_active_container_id(game_root, "store_forbidden_container")
	game_root.refresh_container_panel()
	player_refill_water(game_root)
	var forbidden_store: Dictionary = game_root.store_active_container_item("1008", 1)
	if str(forbidden_store.get("reason", "")) != "container_store_forbidden":
		errors.append("store-forbidden container should report container_store_forbidden")
	if not _container_feedback(game_root).contains("没有权限"):
		errors.append("store-forbidden container should show permission feedback")
	game_root.simulation.container_sessions["flagged_permission_container"] = {
		"container_id": "flagged_permission_container",
		"display_name": "旗标权限容器",
		"inventory": [{"item_id": "1006", "count": 1}],
		"money": 0,
		"required_world_flags": ["container_permission_smoke_flag"],
	}
	_set_active_container_id(game_root, "flagged_permission_container")
	game_root.refresh_container_panel()
	var flagged_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if str(flagged_take.get("reason", "")) != "container_world_flag_missing":
		errors.append("flag-gated container should report container_world_flag_missing")
	game_root.simulation.world_flags["container_permission_smoke_flag"] = true
	var allowed_flagged_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if not bool(allowed_flagged_take.get("success", false)):
		errors.append("flag-gated container should allow take after flag: %s" % allowed_flagged_take.get("reason", "unknown"))
	game_root.simulation.world_flags.erase("container_permission_smoke_flag")
	var active_quests_before: Dictionary = game_root.simulation.active_quests.duplicate(true)
	var completed_quests_before: Dictionary = game_root.simulation.completed_quests.duplicate(true)
	game_root.simulation.container_sessions["active_quest_container"] = {
		"container_id": "active_quest_container",
		"display_name": "进行中任务容器",
		"inventory": [{"item_id": "1006", "count": 1}],
		"required_active_quest_ids": ["container_permission_active_quest"],
	}
	_set_active_container_id(game_root, "active_quest_container")
	game_root.refresh_container_panel()
	var active_missing_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if str(active_missing_take.get("reason", "")) != "container_active_quest_missing":
		errors.append("active quest gated container should report container_active_quest_missing")
	if not _container_feedback(game_root).contains("任务"):
		errors.append("active quest gated container should show quest feedback")
	game_root.simulation.active_quests["container_permission_active_quest"] = {
		"quest_id": "container_permission_active_quest",
		"current_node_id": "smoke",
		"completed_objectives": {},
	}
	var active_allowed_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if not bool(active_allowed_take.get("success", false)):
		errors.append("active quest gated container should allow take when quest is active: %s" % active_allowed_take.get("reason", "unknown"))
	game_root.simulation.container_sessions["completed_quest_container"] = {
		"container_id": "completed_quest_container",
		"display_name": "完成任务容器",
		"inventory": [{"item_id": "1006", "count": 1}],
		"required_completed_quest_ids": ["container_permission_completed_quest"],
	}
	_set_active_container_id(game_root, "completed_quest_container")
	game_root.refresh_container_panel()
	var completed_missing_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if str(completed_missing_take.get("reason", "")) != "container_completed_quest_missing":
		errors.append("completed quest gated container should report container_completed_quest_missing")
	game_root.simulation.completed_quests["container_permission_completed_quest"] = true
	var completed_allowed_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if not bool(completed_allowed_take.get("success", false)):
		errors.append("completed quest gated container should allow take when quest is completed: %s" % completed_allowed_take.get("reason", "unknown"))
	game_root.simulation.container_sessions["blocked_quest_container"] = {
		"container_id": "blocked_quest_container",
		"display_name": "阻止任务容器",
		"inventory": [{"item_id": "1006", "count": 1}],
		"blocked_active_quest_ids": ["container_permission_active_quest"],
		"blocked_completed_quest_ids": ["container_permission_completed_quest"],
	}
	_set_active_container_id(game_root, "blocked_quest_container")
	game_root.refresh_container_panel()
	var active_blocked_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if str(active_blocked_take.get("reason", "")) != "container_active_quest_blocked":
		errors.append("blocked active quest container should report container_active_quest_blocked")
	game_root.simulation.active_quests.erase("container_permission_active_quest")
	var completed_blocked_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if str(completed_blocked_take.get("reason", "")) != "container_completed_quest_blocked":
		errors.append("blocked completed quest container should report container_completed_quest_blocked")
	game_root.simulation.active_quests = active_quests_before.duplicate(true)
	game_root.simulation.completed_quests = completed_quests_before.duplicate(true)
	var owner_relationship_before: float = float(game_root.simulation.relationship_score(1, 2))
	game_root.simulation.container_sessions["owned_forbidden_container"] = {
		"container_id": "owned_forbidden_container",
		"display_name": "私人储物箱",
		"inventory": [{"item_id": "1006", "count": 1}],
		"owned": true,
		"owner_actor_id": 2,
	}
	_set_active_container_id(game_root, "owned_forbidden_container")
	game_root.refresh_container_panel()
	if not _container_permission_text(game_root).contains("归属"):
		errors.append("owned container should preview owner permission")
	var owned_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if str(owned_take.get("reason", "")) != "container_owner_forbidden":
		errors.append("owned container should reject take without steal or relationship permission")
	if not _container_feedback(game_root).contains("属于其他角色"):
		errors.append("owned container should show owner feedback")
	game_root.simulation.container_sessions["owned_relationship_container"] = {
		"container_id": "owned_relationship_container",
		"display_name": "信任储物箱",
		"inventory": [{"item_id": "1006", "count": 1}],
		"owned": true,
		"owner_actor_id": 2,
		"owner_relationship_min": 60.0,
	}
	_set_active_container_id(game_root, "owned_relationship_container")
	game_root.simulation.set_relationship_score(1, 2, 20.0, "container_owner_smoke_low")
	game_root.refresh_container_panel()
	var low_relationship_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if str(low_relationship_take.get("reason", "")) != "container_owner_relationship_too_low":
		errors.append("owned relationship container should reject low relationship")
	if not _container_feedback(game_root).contains("关系不足"):
		errors.append("owned relationship container should show relationship feedback")
	game_root.simulation.set_relationship_score(1, 2, 80.0, "container_owner_smoke_trusted")
	var trusted_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if not bool(trusted_take.get("success", false)):
		errors.append("owned relationship container should allow trusted take: %s" % trusted_take.get("reason", "unknown"))
	game_root.simulation.container_sessions["stealable_container"] = {
		"container_id": "stealable_container",
		"display_name": "可偷取储物箱",
		"inventory": [{"item_id": "1006", "count": 1}],
		"owned": true,
		"owner_actor_id": 2,
		"allow_steal": true,
		"steal_relationship_delta": -15.0,
	}
	_set_active_container_id(game_root, "stealable_container")
	game_root.simulation.set_relationship_score(1, 2, 10.0, "container_owner_smoke_steal")
	game_root.refresh_container_panel()
	var steal_take: Dictionary = game_root.take_active_container_item("1006", 1)
	if not bool(steal_take.get("success", false)) or not bool(steal_take.get("stealing", false)):
		errors.append("stealable owned container should allow take and mark stealing")
	if int(steal_take.get("owner_actor_id", 0)) != 2:
		errors.append("stealable owned container should expose owner_actor_id")
	if not _event_seen(game_root, "container_stolen"):
		errors.append("stealable owned container should emit container_stolen")
	var stolen_payload: Dictionary = _last_event_payload(game_root, "container_stolen")
	if str(stolen_payload.get("container_id", "")) != "stealable_container":
		errors.append("container_stolen should include container id")
	if not is_equal_approx(float(stolen_payload.get("relationship_before", 0.0)), 10.0):
		errors.append("container_stolen should include relationship_before")
	if not is_equal_approx(float(stolen_payload.get("relationship_after", 0.0)), -5.0):
		errors.append("container_stolen should include relationship_after")
	if not is_equal_approx(game_root.simulation.relationship_score(1, 2), -5.0):
		errors.append("stealable owned container should apply relationship penalty")
	game_root.simulation.set_relationship_score(1, 2, owner_relationship_before, "container_owner_smoke_restore")
	game_root.simulation.container_sessions = permission_snapshot.duplicate(true)
	_set_active_container_id(game_root, active_container_before_permission)
	game_root.refresh_container_panel()
	_press_close_button(game_root)
	if game_root.container_panel.visible:
		errors.append("close button should close container panel")
	if not _active_container_id(game_root).is_empty():
		errors.append("close button should clear active container runtime state")
	var reopened_container_node: Node = game_root.find_child("MapObject_survivor_outpost_01_clinic_supply_cabinet", true, false)
	if reopened_container_node == null:
		errors.append("missing generated container node for reopen")
		return errors
	game_root.select_interaction_node(reopened_container_node)
	var reopen_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(reopen_result.get("success", false)):
		errors.append("container reopen failed: %s" % reopen_result.get("reason", "unknown"))
	if not game_root.container_panel.visible:
		errors.append("container panel should reopen for Esc close check")
	_finish_presentations(game_root)
	var esc_container_result: Dictionary = _dictionary_or_empty(game_root.close_active_ui("keyboard_escape"))
	if str(esc_container_result.get("closed", "")) != "container":
		errors.append("Esc close should target container panel, got %s" % esc_container_result)
	if game_root.container_panel.visible:
		errors.append("Esc should close container panel; blocker=%s close=%s stack=%s" % [
			str(game_root.gameplay_input_blocker_name()),
			JSON.stringify(game_root.menu_state_snapshot().get("close_priority", [])) if game_root.has_method("menu_state_snapshot") else "[]",
			JSON.stringify(game_root.modal_stack_snapshot()) if game_root.has_method("modal_stack_snapshot") else "{}",
		])
	if not _active_container_id(game_root).is_empty():
		errors.append("Esc should clear active container runtime state")
	var range_container_node: Node = game_root.find_child("MapObject_survivor_outpost_01_clinic_supply_cabinet", true, false)
	if range_container_node == null:
		errors.append("missing generated container node for range close check")
		return errors
	game_root.select_interaction_node(range_container_node)
	var range_open_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(range_open_result.get("success", false)):
		errors.append("container reopen for range close check failed: %s" % range_open_result.get("reason", "unknown"))
	var range_player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if range_player == null:
		errors.append("missing player for range close check")
		return errors
	range_player.grid_position.x = 0
	range_player.grid_position.z = 0
	game_root.refresh_container_panel()
	if game_root.container_panel.visible:
		errors.append("out-of-range container should close container panel")
	if not _active_container_id(game_root).is_empty():
		errors.append("out-of-range container should clear active container runtime state")
	var vanished_container_node: Node = game_root.find_child("MapObject_survivor_outpost_01_clinic_supply_cabinet", true, false)
	if vanished_container_node == null:
		errors.append("missing generated container node for vanished target check")
		return errors
	game_root.select_interaction_node(vanished_container_node)
	var vanished_open_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(vanished_open_result.get("success", false)):
		errors.append("container reopen for vanished target check failed: %s" % vanished_open_result.get("reason", "unknown"))
	var vanished_container_id := _active_container_id(game_root)
	game_root.simulation.container_sessions.erase(vanished_container_id)
	game_root.refresh_container_panel()
	if game_root.container_panel.visible:
		errors.append("missing container target should close container panel")
	if not _active_container_id(game_root).is_empty():
		errors.append("missing container target should clear active container runtime state")
	_validate_empty_container_world_state(game_root, errors)
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("missing player for map switch container close check")
		return errors
	game_root.simulation.container_sessions["temporary_container"] = {
		"container_id": "temporary_container",
		"display_name": "临时容器",
		"inventory": [],
	}
	player.active_container_id = "temporary_container"
	game_root.refresh_container_panel()
	if not game_root.container_panel.visible:
		errors.append("temporary container should be visible before map switch")
	if not _container_text(game_root).contains("容器为空"):
		errors.append("empty container should show empty prompt")
	game_root.simulation.unlock_location("forest")
	var enter_result: Dictionary = game_root.simulation.enter_location(1, "forest", game_root.registry.get_library("overworld"))
	if not bool(enter_result.get("success", false)):
		errors.append("forest enter for container close check failed: %s" % enter_result.get("reason", "unknown"))
	game_root.refresh_container_panel()
	if game_root.container_panel.visible:
		errors.append("map switch should close container panel")
	if not _active_container_id(game_root).is_empty():
		errors.append("map switch should clear active container runtime state")
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
	var button: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/CloseButton")
	if button is Button:
		(button as Button).pressed.emit()


func _execute_primary_and_complete(game_root: Node, max_waits: int = 8) -> Dictionary:
	_finish_presentations(game_root)
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
	_finish_presentations(game_root)
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


func _validate_empty_container_world_state(game_root: Node, errors: Array[String]) -> void:
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("missing player for empty container world state check")
		return
	var container_id := "survivor_outpost_01_clinic_supply_cabinet"
	var target: Dictionary = _dictionary_or_empty(_dictionary_or_empty(_dictionary_or_empty(game_root.world_result.get("map", {})).get("interaction_targets", {})).get(container_id, {}))
	var anchor: Dictionary = _dictionary_or_empty(target.get("anchor", {}))
	player.grid_position.x = int(anchor.get("x", player.grid_position.x))
	player.grid_position.z = int(anchor.get("z", player.grid_position.z))
	game_root.simulation.container_sessions[container_id] = {
		"container_id": container_id,
		"display_name": "诊所补给柜",
		"inventory": [{"item_id": "1031", "count": 1}],
		"money": 0,
	}
	player.active_container_id = container_id
	_finish_presentations(game_root)
	var take_all: Dictionary = game_root.take_all_active_container_items()
	if not bool(take_all.get("success", false)):
		errors.append("empty state setup take all failed: %s" % take_all.get("reason", "unknown"))
	var session: Dictionary = _dictionary_or_empty(game_root.simulation.container_sessions.get(container_id, {}))
	if not _array_or_empty(session.get("inventory", [])).is_empty() or int(session.get("money", 0)) != 0:
		errors.append("empty state setup should clear container session")
	_refresh_runtime_world(game_root, {"prompt": {}})
	var container_node: Node = game_root.find_child("MapObject_%s" % container_id, true, false)
	if container_node == null:
		errors.append("empty container should remain as a map object")
		return
	var badge: Node = container_node.find_child("ContainerStateBadge", true, false)
	if badge == null:
		errors.append("empty container should expose ContainerStateBadge")
	else:
		if not bool(badge.get_meta("container_empty", false)):
			errors.append("empty container badge should expose container_empty")
		if str(badge.get_meta("container_visual_state", "")) != "empty":
			errors.append("empty container badge should expose empty visual state")
	var node_target: Dictionary = _dictionary_or_empty(container_node.get_meta("interaction_target", {}))
	if str(node_target.get("container_type", "")) != "map":
		errors.append("empty container interaction metadata should expose container_type")
	if not bool(node_target.get("container_empty", false)):
		errors.append("empty container interaction metadata should expose container_empty")
	if int(node_target.get("container_item_count", -1)) != 0:
		errors.append("empty container interaction metadata should expose zero item count")
	var pickable_body: Node = container_node.find_child("PickableBody", true, false)
	var pickable_target: Dictionary = _dictionary_or_empty(pickable_body.get_meta("interaction_target", {}) if pickable_body != null else {})
	if pickable_body == null or not bool(pickable_target.get("container_empty", false)):
		errors.append("empty container pickable body should mirror container_empty metadata")
	if pickable_body == null or str(pickable_target.get("container_type", "")) != "map":
		errors.append("empty container pickable body should mirror container_type metadata")
	game_root.select_interaction_node(container_node)
	var open_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(open_result.get("success", false)):
		errors.append("empty container should still open: %s" % open_result.get("reason", "unknown"))
	if not _container_text(game_root).contains("容器为空"):
		errors.append("empty container panel should show empty prompt after world rebuild")


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


func _container_summary(game_root: Node) -> String:
	return game_root.container_panel.get_node("ContainerPanel/ContainerLines/SummaryLine").text


func _container_feedback(game_root: Node) -> String:
	var label: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/FeedbackLine")
	if label is Label and (label as Label).visible:
		return str((label as Label).text)
	return ""


func _container_detail(game_root: Node) -> String:
	var label: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/DetailLine")
	if label is Label:
		return str((label as Label).text)
	return ""


func _container_permission_text(game_root: Node) -> String:
	var label: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/PermissionsLine")
	if label is Label:
		return str((label as Label).text)
	return ""


func _container_session(snapshot: Dictionary, container_id: String) -> Dictionary:
	for entry in _array_or_empty(snapshot.get("container_sessions", [])):
		var session: Dictionary = _dictionary_or_empty(entry)
		if str(session.get("container_id", "")) == container_id:
			return session
	return {}


func _event_seen(game_root: Node, kind: String) -> bool:
	for event in game_root.simulation.snapshot().get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			return true
	return false


func _event_count(game_root: Node, kind: String) -> int:
	var count := 0
	for event in game_root.simulation.snapshot().get("events", []):
		var event_data: Dictionary = _dictionary_or_empty(event)
		if str(event_data.get("kind", "")) == kind:
			count += 1
	return count


func _last_event_payload(game_root: Node, kind: String) -> Dictionary:
	var events: Array = game_root.simulation.snapshot().get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if str(event_data.get("kind", "")) == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


func _inventory_summary(game_root: Node) -> String:
	return game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/SummaryLine").text


func _container_text(game_root: Node) -> String:
	return "\n".join(_container_item_lines(game_root))


func _container_player_text(game_root: Node) -> String:
	var output: Array[String] = []
	var item_box: Node = game_root.container_panel.get_node("ContainerPanel/ContainerLines/ItemColumns/PlayerColumn/PlayerScroll/PlayerItemLines")
	for child in item_box.get_children():
		var text := _item_control_text(child)
		if not text.is_empty():
			output.append(text)
	return "\n".join(output)


func _inventory_text(game_root: Node) -> String:
	var output: Array[String] = []
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemScroll/ItemLines")
	for child in item_box.get_children():
		var text := _item_control_text(child)
		if not text.is_empty():
			output.append(text)
	return "\n".join(output)


func player_refill_water(game_root: Node) -> void:
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor == null:
		return
	actor.inventory["1008"] = 1
	if not actor.inventory_order.has("1008"):
		actor.inventory_order.append("1008")
	game_root.refresh_inventory_panel()
	game_root.refresh_container_panel()


func _open_inventory_context_menu(game_root: Node, item_needle: String) -> bool:
	var source: Button = _inventory_item_button(game_root, item_needle)
	if source == null or not source.has_meta("inventory_item"):
		return false
	game_root.inventory_panel.call("_open_context_menu_for_item", source.get_meta("inventory_item"), Vector2.ZERO)
	return true


func _open_container_context_menu(game_root: Node, source: String, item_needle: String) -> bool:
	var button: Button = _container_item_button_with_text(game_root, source, item_needle)
	if button == null or not button.has_meta("container_item"):
		return false
	game_root.container_panel.call("_open_context_menu_for_item", button.get_meta("container_item"), source, Vector2.ZERO)
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


func _execute_container_context_action(game_root: Node, action_id: int) -> void:
	game_root.container_panel.call("_execute_context_action", action_id)


func _container_item_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var item_box: Node = game_root.container_panel.get_node("ContainerPanel/ContainerLines/ItemColumns/ContainerColumn/ContainerScroll/ItemLines")
	for child in item_box.get_children():
		var text := _item_control_text(child)
		if not text.is_empty():
			output.append(text)
	return output


func _press_first_player_container_item(game_root: Node) -> void:
	var item_box: Node = _container_item_box(game_root, "player")
	for child in item_box.get_children():
		if child is Button:
			(child as Button).pressed.emit()
			return


func _press_container_item_with_text(game_root: Node, source: String, text: String) -> bool:
	var button: Button = _container_item_button_with_text(game_root, source, text)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _drop_container_item_with_text(game_root: Node, source: String, text: String, target_source: String, count: int = 1) -> bool:
	var button: Button = _container_item_button_with_text(game_root, source, text)
	var target: Node = _container_item_box(game_root, target_source)
	if button == null or not target is Control:
		return false
	var item: Dictionary = button.get_meta("container_item", {})
	var drag_source: String = str(button.get_meta("container_source", ""))
	if item.is_empty() or drag_source.is_empty():
		return false
	game_root.container_panel.call("_drop_container_data", Vector2.ZERO, {
		"kind": "container_item",
		"source": drag_source,
		"item": item.duplicate(true),
		"count": count,
	}, target)
	return true


func _drop_inventory_item_to_container(game_root: Node, text: String, count: int = 1) -> bool:
	var button: Button = _inventory_item_button(game_root, text)
	var target: Node = _container_item_box(game_root, "container")
	if button == null or not target is Control or not button.has_meta("inventory_item"):
		return false
	var item: Dictionary = button.get_meta("inventory_item", {})
	if item.is_empty():
		return false
	game_root.container_panel.call("_drop_container_data", Vector2.ZERO, {
		"kind": "inventory_item",
		"item": item.duplicate(true),
		"item_id": str(item.get("item_id", "")),
		"count": count,
	}, target)
	return true


func _container_item_button_with_text(game_root: Node, source: String, text: String) -> Button:
	var item_box: Node = _container_item_box(game_root, source)
	if item_box == null:
		return null
	for child in item_box.get_children():
		if child is Button and str((child as Button).text).contains(text):
			return child as Button
	return null


func _container_item_icon_path(game_root: Node, source: String, text: String) -> String:
	var button: Button = _container_item_button_with_text(game_root, source, text)
	if button == null or button.icon == null or not button.has_meta("icon_resource_path"):
		return ""
	return str(button.get_meta("icon_resource_path"))


func _set_container_transfer_quantity(game_root: Node, count: int) -> void:
	var spin: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/TransferControls/QuantitySpin")
	if spin is SpinBox:
		(spin as SpinBox).value = count


func _container_quantity_spin_value(game_root: Node) -> int:
	var spin: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/TransferControls/QuantitySpin")
	if spin is SpinBox:
		return int((spin as SpinBox).value)
	return 0


func _container_quantity_label(game_root: Node) -> String:
	var label: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/TransferControls/QuantityLabel")
	if label is Label:
		return str((label as Label).text)
	return ""


func _press_container_quantity_minus(game_root: Node) -> void:
	_press_container_quantity_button(game_root, "QuantityMinusButton")


func _press_container_quantity_all(game_root: Node) -> void:
	_press_container_quantity_button(game_root, "QuantityAllButton")


func _press_container_quantity_button(game_root: Node, node_name: String) -> void:
	var button: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/TransferControls/%s" % node_name)
	if button is Button:
		(button as Button).pressed.emit()


func _container_quantity_button_disabled(game_root: Node, node_name: String) -> bool:
	var button: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/TransferControls/%s" % node_name)
	if button is Button:
		return bool((button as Button).disabled)
	return true


func _press_container_transfer(game_root: Node) -> void:
	var button: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/TransferControls/TransferButton")
	if button is Button:
		(button as Button).pressed.emit()


func _assert_container_quantity_modal(errors: Array[String], game_root: Node, expected_source: String, expected_item_id: String, expected_count: int, context: String) -> void:
	var dialog: ConfirmationDialog = game_root.container_panel.find_child("ContainerQuantityConfirmDialog", true, false) as ConfirmationDialog
	if dialog == null or not dialog.visible:
		errors.append("%s: container quantity modal should be visible" % context)
	if str(game_root.gameplay_input_blocker_name()) != "modal:container_quantity_confirm":
		errors.append("%s: blocker should be modal:container_quantity_confirm, got %s" % [context, str(game_root.gameplay_input_blocker_name())])
	var stack: Dictionary = _dictionary_or_empty(game_root.modal_stack_snapshot()) if game_root.has_method("modal_stack_snapshot") else {}
	var top: Dictionary = _dictionary_or_empty(stack.get("top", {}))
	if str(top.get("id", "")) != "container_quantity_confirm":
		errors.append("%s: modal stack top should expose container_quantity_confirm: %s" % [context, stack])
	if str(top.get("owner_panel", "")) != "container" or str(top.get("kind", "")) != "quantity":
		errors.append("%s: modal stack top should expose owner/kind: %s" % [context, top])
	if str(top.get("source", "")) != expected_source or str(top.get("item_id", "")) != expected_item_id or int(top.get("count", 0)) != expected_count:
		errors.append("%s: modal stack should expose transfer payload: %s" % [context, top])
	if not bool(top.get("blocks_gameplay", false)) or not bool(top.get("mouse_blocks_world", false)):
		errors.append("%s: quantity modal should block gameplay and mouse world input: %s" % [context, top])
	if not bool(top.get("dialog_visible", false)):
		errors.append("%s: quantity modal should expose visible dialog: %s" % [context, top])
	if int(top.get("quantity_min", 0)) != 1 or int(top.get("quantity_max", 0)) < expected_count:
		errors.append("%s: quantity modal should expose valid bounds: %s" % [context, top])
	if not bool(top.get("quantity_valid", false)) or str(top.get("quantity_text", "")) != str(expected_count):
		errors.append("%s: quantity modal should expose valid selected quantity: %s" % [context, top])
	if not bool(top.get("confirm_button_mouse_blocks_world", false)) or not bool(top.get("cancel_button_mouse_blocks_world", false)):
		errors.append("%s: quantity modal buttons should stop world mouse input: %s" % [context, top])
	if str(top.get("confirm_button_mouse_filter", "")) != "stop" or str(top.get("cancel_button_mouse_filter", "")) != "stop":
		errors.append("%s: quantity modal button mouse filters should be stop: %s" % [context, top])
	var menu_state: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot()) if game_root.has_method("menu_state_snapshot") else {}
	var modal_event: Dictionary = _dictionary_or_empty(menu_state.get("modal_event", {}))
	if str(modal_event.get("panel_id", "")) != "container_quantity_confirm" or str(modal_event.get("owner_panel", "")) != "container":
		errors.append("%s: menu state should expose quantity modal event: %s" % [context, menu_state])
	var runtime_menu: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("menu_state", {}))
	var runtime_event: Dictionary = _dictionary_or_empty(runtime_menu.get("modal_event", {}))
	if str(runtime_event.get("panel_id", "")) != "container_quantity_confirm":
		errors.append("%s: runtime menu should expose quantity modal event: %s" % [context, runtime_menu])


func _assert_no_container_quantity_modal(errors: Array[String], game_root: Node, context: String) -> void:
	var dialog: ConfirmationDialog = game_root.container_panel.find_child("ContainerQuantityConfirmDialog", true, false) as ConfirmationDialog
	if dialog != null and dialog.visible:
		errors.append("%s: container quantity modal should be hidden" % context)
	var stack: Dictionary = _dictionary_or_empty(game_root.modal_stack_snapshot()) if game_root.has_method("modal_stack_snapshot") else {}
	if bool(stack.get("active", false)):
		errors.append("%s: modal stack should be inactive: %s" % [context, stack])
	var menu_state: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot()) if game_root.has_method("menu_state_snapshot") else {}
	if not _dictionary_or_empty(menu_state.get("modal_event", {})).is_empty():
		errors.append("%s: modal event should clear after close: %s" % [context, menu_state])


func _confirm_container_quantity_modal(game_root: Node) -> void:
	var dialog: ConfirmationDialog = game_root.container_panel.find_child("ContainerQuantityConfirmDialog", true, false) as ConfirmationDialog
	if dialog != null:
		dialog.confirmed.emit()


func _press_container_bulk_button(game_root: Node, node_name: String) -> void:
	var button: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/TransferControls/%s" % node_name)
	if button is Button:
		(button as Button).pressed.emit()


func _container_bulk_button_disabled(game_root: Node, node_name: String) -> bool:
	var button: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/TransferControls/%s" % node_name)
	if button is Button:
		return bool((button as Button).disabled)
	return true


func _container_transfer_button_text(game_root: Node) -> String:
	var button: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/TransferControls/TransferButton")
	if button is Button:
		return str((button as Button).text)
	return ""


func _container_transfer_tooltip(game_root: Node) -> String:
	var button: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/TransferControls/TransferButton")
	if button is Button:
		return str((button as Button).tooltip_text)
	return ""


func _container_item_box(game_root: Node, source: String) -> Node:
	match source:
		"container":
			return game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/ItemColumns/ContainerColumn/ContainerScroll/ItemLines")
		"player":
			return game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/ItemColumns/PlayerColumn/PlayerScroll/PlayerItemLines")
		_:
			return null


func _item_control_text(node: Node) -> String:
	if node is Label:
		return str((node as Label).text)
	if node is Button:
		return str((node as Button).text)
	return ""


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


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


func _assert_container_context_menu(errors: Array[String], game_root: Node, expected_item_id: String, expected_source: String, expected_label: String, context: String) -> void:
	if not game_root.has_method("context_menu_snapshot"):
		errors.append("%s: game root should expose context_menu_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.context_menu_snapshot())
	if not bool(snapshot.get("active", false)):
		errors.append("%s: context menu snapshot should be active: %s" % [context, snapshot])
		return
	var top: Dictionary = _dictionary_or_empty(snapshot.get("top", {}))
	if str(top.get("id", "")) != "container_context_menu" or str(top.get("kind", "")) != "container_item":
		errors.append("%s: expected container context top, got %s" % [context, top])
	if str(top.get("owner_panel", "")) != "container":
		errors.append("%s: container context owner should be container: %s" % [context, top])
	if str(top.get("item_id", "")) != expected_item_id:
		errors.append("%s: context menu item expected %s, got %s" % [context, expected_item_id, top])
	if str(top.get("source", "")) != expected_source:
		errors.append("%s: context menu source expected %s, got %s" % [context, expected_source, top])
	if int(top.get("selected_count", 0)) <= 0 or int(top.get("item_count", 0)) <= 0:
		errors.append("%s: context menu should expose selected and total counts: %s" % [context, top])
	if int(top.get("option_count", 0)) != 2:
		errors.append("%s: container context menu should expose two transfer options: %s" % [context, top])
	var expected_action_seen := false
	var all_action_seen := false
	for option in _array_or_empty(top.get("options", [])):
		var option_data: Dictionary = _dictionary_or_empty(option)
		if str(option_data.get("label", "")) == expected_label:
			expected_action_seen = true
			if bool(option_data.get("disabled", true)):
				errors.append("%s: selected transfer option should be enabled: %s" % [context, option_data])
			if not str(option_data.get("tooltip", "")).contains("当前堆叠"):
				errors.append("%s: selected transfer tooltip should expose stack count: %s" % [context, option_data])
		if int(option_data.get("id", -1)) == 2:
			all_action_seen = true
			if bool(option_data.get("disabled", true)):
				errors.append("%s: all transfer option should be enabled: %s" % [context, option_data])
	if not expected_action_seen:
		errors.append("%s: context menu should include %s: %s" % [context, expected_label, top])
	if not all_action_seen:
		errors.append("%s: context menu should include all-item transfer option: %s" % [context, top])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_context: Dictionary = _dictionary_or_empty(runtime.get("context_menu", {}))
	var runtime_top: Dictionary = _dictionary_or_empty(runtime_context.get("top", {}))
	if str(runtime_top.get("id", "")) != "container_context_menu" or str(runtime_top.get("item_id", "")) != expected_item_id:
		errors.append("%s: runtime context menu should expose container item %s: %s" % [context, expected_item_id, runtime_context])


func _finish_presentations(game_root: Node) -> void:
	if game_root.has_method("finish_world_action_presentations"):
		game_root.finish_world_action_presentations()


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _container_entry_count(entries: Array, item_id: String) -> int:
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if str(entry_data.get("item_id", "")) == item_id:
			return int(entry_data.get("count", 0))
	return 0


func _restore_inventory_order(actor: RefCounted, order: Array) -> void:
	if actor == null:
		return
	actor.inventory_order.clear()
	for item_id in order:
		var normalized_item_id := str(item_id)
		if not normalized_item_id.is_empty():
			actor.inventory_order.append(normalized_item_id)


func _container_has_scroll_columns(game_root: Node) -> bool:
	var container_scroll: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/ItemColumns/ContainerColumn/ContainerScroll")
	var player_scroll: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/ItemColumns/PlayerColumn/PlayerScroll")
	return container_scroll is ScrollContainer and player_scroll is ScrollContainer


func _active_container_id(game_root: Node) -> String:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return str(actor_data.get("active_container_id", ""))
	return ""


func _set_active_container_id(game_root: Node, container_id: String) -> void:
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor != null:
		actor.active_container_id = container_id
