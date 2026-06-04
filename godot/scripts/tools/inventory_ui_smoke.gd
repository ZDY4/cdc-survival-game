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

	var errors: Array[String] = await _run_checks(game_root)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("inventory_ui_smoke passed:")
	print(JSON.stringify({
		"summary": _summary_line(game_root),
		"items": _item_lines(game_root),
	}, "\t"))
	quit(0)


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	if game_root.inventory_panel == null:
		return ["inventory panel was not created"]
	if not _summary_line(game_root).contains("4 类物品"):
		errors.append("initial inventory summary should include bootstrap inventory")
	var initial_text: String = "\n".join(_item_lines(game_root))
	if not initial_text.contains("手枪弹药 x10"):
		errors.append("initial inventory missing bootstrap ammo")
	if _sort_button(game_root, "SortOrderButton") == null:
		errors.append("inventory panel should expose inventory order sort")
	if not _text_ordered(initial_text, "水瓶 x1", "绷带 x1") \
		or not _text_ordered(initial_text, "绷带 x1", "棒球棒 x1") \
		or not _text_ordered(initial_text, "棒球棒 x1", "手枪弹药 x10"):
		errors.append("initial inventory should follow persisted inventory order")
	if not _reorder_inventory_item_before(game_root, "手枪弹药", "水瓶"):
		errors.append("should drag ammo before water in inventory order view")
	await process_frame
	var reordered_text: String = "\n".join(_item_lines(game_root))
	if not _text_ordered(reordered_text, "手枪弹药 x10", "水瓶 x1"):
		errors.append("inventory drag reorder should move ammo before water")
	if not _append_inventory_item_by_drag(game_root, "手枪弹药"):
		errors.append("should drag ammo to the end of inventory order view")
	await process_frame
	var restored_order_text: String = "\n".join(_item_lines(game_root))
	if not _text_ordered(restored_order_text, "棒球棒 x1", "手枪弹药 x10"):
		errors.append("inventory drag append should restore ammo after baseball bat")
	if not _event_seen(game_root, "inventory_reordered"):
		errors.append("inventory drag reorder should emit inventory_reordered")
	var player_ref: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	player_ref.hp = 50.0
	player_ref.ap = 6.0
	player_ref.inventory["1006"] = 2
	game_root.refresh_inventory_panel()
	if not _press_inventory_item_with_text(game_root, "绷带"):
		errors.append("should select bandage row before using item")
	var use_button: Button = _use_button(game_root)
	if use_button == null or use_button.disabled:
		errors.append("selected consumable should enable use button")
	if not _open_inventory_context_menu(game_root, "绷带"):
		errors.append("should open context menu for bandage")
	elif _context_action_disabled(game_root, 1):
		errors.append("context menu should enable use for consumable")
	else:
		_execute_inventory_context_action(game_root, 1)
		await process_frame
		if absf(player_ref.hp - 75.0) > 0.01:
			errors.append("using bandage should restore 25 hp")
		if absf(player_ref.ap - 4.0) > 0.01:
			errors.append("using bandage should spend ceil(use_time) AP")
		player_ref.ap = 6.0
		if _player_inventory_count(game_root, "1006") != 1:
			errors.append("using bandage should consume one inventory item")
		if not _event_seen(game_root, "item_used"):
			errors.append("using bandage should emit item_used")
	var ap_before_invalid_use: float = player_ref.ap
	var invalid_use: Dictionary = game_root.use_player_item("1003")
	if str(invalid_use.get("reason", "")) != "item_not_usable":
		errors.append("using a non-usable weapon should report item_not_usable")
	if absf(player_ref.ap - ap_before_invalid_use) > 0.01:
		errors.append("failed item use should not spend AP")
	_mark_item_as_quest(game_root, "1007")
	player_ref.inventory["1007"] = 1
	if not player_ref.inventory_order.has("1007"):
		player_ref.inventory_order.append("1007")
	game_root.refresh_inventory_panel()
	if not _press_inventory_item_with_text(game_root, "罐头食品"):
		errors.append("should select temporary quest food item")
	var quest_use_button: Button = _use_button(game_root)
	if quest_use_button == null or not quest_use_button.disabled:
		errors.append("quest consumable should disable use button")
	var quest_drop_button: Button = _drop_button(game_root)
	if quest_drop_button == null or not quest_drop_button.disabled:
		errors.append("quest item should disable drop button")
	if not _open_inventory_context_menu(game_root, "罐头食品"):
		errors.append("should open context menu for quest food item")
	else:
		if not _context_action_disabled(game_root, 1):
			errors.append("quest item context menu should disable use")
		if not _context_action_disabled(game_root, 3):
			errors.append("quest item context menu should disable drop")
	var quest_ap_before: float = player_ref.ap
	var quest_use: Dictionary = game_root.use_player_item("1007")
	if str(quest_use.get("reason", "")) != "item_use_forbidden":
		errors.append("using quest item should report item_use_forbidden")
	if absf(player_ref.ap - quest_ap_before) > 0.01:
		errors.append("forbidden quest item use should not spend AP")
	var quest_drop: Dictionary = game_root.drop_player_item("1007", 1)
	if str(quest_drop.get("reason", "")) != "item_not_droppable":
		errors.append("dropping quest item should report item_not_droppable")
	if _player_inventory_count(game_root, "1007") != 1:
		errors.append("forbidden quest item drop should keep inventory")
	_unmark_item_as_quest(game_root, "1007")
	player_ref.inventory.erase("1007")
	player_ref.inventory_order.erase("1007")
	game_root.refresh_inventory_panel()
	if _filter_button(game_root, "FilterEquipmentButton") == null:
		errors.append("inventory panel should expose equipment filter")
	else:
		_filter_button(game_root, "FilterEquipmentButton").pressed.emit()
		await process_frame
		var equipment_text: String = "\n".join(_item_lines(game_root))
		if not equipment_text.contains("棒球棒 x1"):
			errors.append("equipment filter should keep weapon rows")
		if equipment_text.contains("手枪弹药 x10"):
			errors.append("equipment filter should hide ammo rows")
	if _filter_button(game_root, "FilterAmmoButton") == null:
		errors.append("inventory panel should expose ammo filter")
	else:
		_filter_button(game_root, "FilterAmmoButton").pressed.emit()
		await process_frame
		var ammo_text: String = "\n".join(_item_lines(game_root))
		if not ammo_text.contains("手枪弹药 x10"):
			errors.append("ammo filter should keep ammo rows")
		if ammo_text.contains("棒球棒 x1"):
			errors.append("ammo filter should hide equipment rows")
	if _filter_button(game_root, "FilterAllButton") == null:
		errors.append("inventory panel should expose all filter")
	else:
		_filter_button(game_root, "FilterAllButton").pressed.emit()
		await process_frame
		if not "\n".join(_item_lines(game_root)).contains("棒球棒 x1"):
			errors.append("all filter should restore inventory rows")
	if _sort_button(game_root, "SortValueButton") == null:
		errors.append("inventory panel should expose value sort")
	else:
		_sort_button(game_root, "SortValueButton").pressed.emit()
		await process_frame
		if not _text_ordered("\n".join(_item_lines(game_root)), "棒球棒 x1", "手枪弹药 x10"):
			errors.append("value sort should place higher value item before ammo")
	if not _press_inventory_item_with_text(game_root, "手枪弹药"):
		errors.append("should select ammo row for detail")
	if not _detail_line(game_root).contains("弹药") or not _detail_line(game_root).contains("总价 50"):
		errors.append("inventory detail should show selected item category and value")
	var item_scroll: Node = game_root.inventory_panel.get_node_or_null("InventoryPanel/InventoryLines/ItemScroll")
	if item_scroll == null:
		errors.append("inventory panel should wrap item rows in a scroll container")
	var search_box: LineEdit = _search_box(game_root)
	if search_box == null:
		errors.append("inventory panel should expose search box")
	else:
		search_box.text = "水瓶"
		search_box.text_changed.emit(search_box.text)
		await process_frame
		var search_text: String = "\n".join(_item_lines(game_root))
		if not search_text.contains("水瓶 x1"):
			errors.append("inventory search should keep matching item rows")
		if search_text.contains("棒球棒 x1") or search_text.contains("手枪弹药 x10"):
			errors.append("inventory search should hide non-matching rows")
		search_box.text = ""
		search_box.text_changed.emit(search_box.text)
		await process_frame
	_expect_main_hand_model(errors, game_root, "preview_placeholders/placeholders/weapon_dagger.gltf")

	if not _press_inventory_item_with_text(game_root, "棒球棒"):
		errors.append("should select baseball bat before equipping through inventory panel")
	var equip_button: Button = _equip_button(game_root)
	if equip_button == null or equip_button.disabled:
		errors.append("selected equippable item should enable equip button")
	elif not _open_inventory_context_menu(game_root, "棒球棒"):
		errors.append("should open context menu for baseball bat")
	elif _context_action_disabled(game_root, 2):
		errors.append("context menu should enable equip for baseball bat")
	else:
		_execute_inventory_context_action(game_root, 2)
		await process_frame
	_expect_main_hand_model(errors, game_root, "preview_placeholders/placeholders/weapon_blunt.gltf")
	var context_unequip_result: Dictionary = game_root.unequip_player_slot("main_hand")
	if not bool(context_unequip_result.get("success", false)):
		errors.append("unequipping context-equipped baseball bat failed: %s" % context_unequip_result.get("reason", "unknown"))
	if not _press_inventory_item_with_text(game_root, "棒球棒"):
		errors.append("should reselect baseball bat before drag equipping")
	equip_button = _equip_button(game_root)
	if equip_button == null or equip_button.disabled:
		errors.append("selected equippable item should enable equip button after context unequip")
	elif not _drag_inventory_item_to_action(game_root, "棒球棒", "EquipSelectedButton"):
		errors.append("should drag baseball bat onto equip button")
	else:
		await process_frame
	_expect_main_hand_model(errors, game_root, "preview_placeholders/placeholders/weapon_blunt.gltf")
	if "\n".join(_item_lines(game_root)).contains("棒球棒"):
		errors.append("equipped baseball bat should leave inventory panel")

	var unequip_result: Dictionary = game_root.unequip_player_slot("main_hand")
	if not bool(unequip_result.get("success", false)):
		errors.append("unequipping main hand through game app failed: %s" % unequip_result.get("reason", "unknown"))
	if _player_node(game_root).find_child("EquipmentModel_main_hand", true, false) != null:
		errors.append("main hand equipment model should be removed after unequip redraw")
	if not "\n".join(_item_lines(game_root)).contains("棒球棒 x1"):
		errors.append("unequipped baseball bat should return to inventory panel")
	var restore_result: Dictionary = game_root.equip_player_item("1002", "main_hand")
	if not bool(restore_result.get("success", false)):
		errors.append("restoring bootstrap knife through game app failed: %s" % restore_result.get("reason", "unknown"))
	_expect_main_hand_model(errors, game_root, "preview_placeholders/placeholders/weapon_dagger.gltf")

	var pickup_node: Node = game_root.find_child("MapObject_survivor_outpost_01_pickup_medkit", true, false)
	if pickup_node == null:
		return ["missing generated pickup node"]
	game_root.select_interaction_node(pickup_node)
	var pickup_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(pickup_result.get("success", false)):
		errors.append("pickup execution failed: %s" % pickup_result.get("reason", "unknown"))

	var item_text: String = "\n".join(_item_lines(game_root))
	if not item_text.contains("绷带 x3"):
		errors.append("inventory panel missing picked bandage line")
	if not _summary_line(game_root).contains("4 类物品"):
		errors.append("inventory summary did not update item count")
	if not _summary_line(game_root).contains("2.1 kg"):
		errors.append("inventory summary did not update total weight")
	if not _press_inventory_item_with_text(game_root, "绷带"):
		errors.append("should select bandages before dropping through inventory panel")
	var quantity_spin: SpinBox = _quantity_spin(game_root)
	var drop_button: Button = _drop_button(game_root)
	var discard_quantity_input: LineEdit = null
	if quantity_spin == null:
		errors.append("inventory panel should expose quantity spin")
	else:
		quantity_spin.value = 2
	if drop_button == null or drop_button.disabled:
		errors.append("selected droppable item should enable drop button")
	else:
		drop_button.pressed.emit()
		await process_frame
		if not _discard_dialog_visible(game_root):
			errors.append("drop button should open discard confirmation dialog")
		discard_quantity_input = _discard_quantity_input(game_root)
		if discard_quantity_input == null:
			errors.append("discard modal should expose quantity input")
		elif discard_quantity_input.text != "2":
			errors.append("discard modal quantity should start from selected action quantity")
		if _player_inventory_count(game_root, "1006") != 3:
			errors.append("opening discard confirmation should not mutate inventory")
		if not bool(game_root.gameplay_input_blocked_by_ui()):
			errors.append("discard confirmation should block gameplay input")
		if str(game_root.gameplay_input_blocker_name()) != "modal:inventory_discard_confirm":
			errors.append("discard confirmation blocker should be modal:inventory_discard_confirm")
		if discard_quantity_input != null:
			discard_quantity_input.text = "0"
			_emit_discard_confirm(game_root)
			await process_frame
			if not _discard_dialog_visible(game_root):
				errors.append("invalid discard quantity should keep modal open")
			if not _discard_error_text(game_root).contains("大于 0"):
				errors.append("invalid discard quantity should show reason")
			if _player_inventory_count(game_root, "1006") != 3:
				errors.append("invalid discard quantity should not mutate inventory")
			_press_discard_quantity_button(game_root, "DiscardQuantityMaxButton")
			await process_frame
			if discard_quantity_input.text != "3":
				errors.append("discard max button should use available inventory count")
			_press_discard_quantity_button(game_root, "DiscardQuantityMinusButton")
			await process_frame
			if discard_quantity_input.text != "2":
				errors.append("discard minus button should decrease quantity")
			_press_discard_quantity_button(game_root, "DiscardQuantityPlusButton")
			await process_frame
			if discard_quantity_input.text != "3":
				errors.append("discard plus button should increase quantity")
		var esc_discard_result: Dictionary = game_root.close_active_ui("keyboard_escape")
		if str(esc_discard_result.get("closed", "")) != "modal:inventory_discard_confirm":
			errors.append("Esc should close inventory discard modal before other UI")
		if _discard_dialog_visible(game_root):
			errors.append("Esc should hide inventory discard modal")
		if _player_inventory_count(game_root, "1006") != 3:
			errors.append("Esc closing discard confirmation should keep inventory")
	if not _open_inventory_context_menu(game_root, "绷带"):
		errors.append("should open context menu for picked bandages")
	elif _context_action_disabled(game_root, 3):
		errors.append("context menu should enable drop for picked bandages")
	else:
		quantity_spin.value = 1
		_execute_inventory_context_action(game_root, 3)
		await process_frame
		if not _discard_dialog_visible(game_root):
			errors.append("context drop should open discard confirmation dialog")
		discard_quantity_input = _discard_quantity_input(game_root)
		if discard_quantity_input == null:
			errors.append("context drop should expose discard modal quantity input")
		else:
			discard_quantity_input.text = "1"
		if _player_inventory_count(game_root, "1006") != 3:
			errors.append("context drop confirmation should not mutate inventory before confirm")
		_confirm_discard_dialog(game_root)
		await process_frame
	if _player_inventory_count(game_root, "1006") != 2:
		errors.append("context dropping one bandage should leave two bandages")
	if not _press_inventory_item_with_text(game_root, "绷带"):
		errors.append("should reselect bandages before drag dropping")
	quantity_spin = _quantity_spin(game_root)
	drop_button = _drop_button(game_root)
	if quantity_spin != null:
		quantity_spin.value = 1
	if drop_button == null or drop_button.disabled:
		errors.append("selected droppable item should enable drop button after context drop")
	elif not _drag_inventory_item_to_action(game_root, "绷带", "DropSelectedButton"):
		errors.append("should drag bandages onto drop button")
	else:
		await process_frame
		if not _discard_dialog_visible(game_root):
			errors.append("drag drop should open discard confirmation dialog")
		if _player_inventory_count(game_root, "1006") != 2:
			errors.append("drag drop confirmation should not mutate inventory before confirm")
		_confirm_discard_dialog(game_root)
		await process_frame
	if _player_inventory_count(game_root, "1006") != 1:
		errors.append("dropping bandages should remove the requested count from inventory")
	var drop_payload: Dictionary = _last_event_payload(game_root, "inventory_item_dropped")
	if game_root.find_child("Corpse_%s" % drop_payload.get("container_id", ""), true, false) == null:
		errors.append("dropping inventory item should create a world drop container marker")
	if not _event_seen(game_root, "inventory_item_dropped"):
		errors.append("dropping inventory item should emit inventory_item_dropped")
	return errors


func _execute_primary_and_complete(game_root: Node, max_waits: int = 8) -> Dictionary:
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


func _expect_main_hand_model(errors: Array[String], game_root: Node, expected_asset: String) -> void:
	var player: Node = _player_node(game_root)
	var model: Node = player.find_child("EquipmentModel_main_hand", true, false)
	if model == null:
		errors.append("missing main hand equipment model")
		return
	if str(model.get_meta("model_asset", "")) != expected_asset:
		errors.append("main hand equipment model should use %s" % expected_asset)


func _player_node(game_root: Node) -> Node:
	return game_root.find_child("Actor_player_1", true, false)


func _player_inventory_count(game_root: Node, item_id: String) -> int:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return int(actor_data.get("inventory", {}).get(item_id, 0))
	return 0


func _event_seen(game_root: Node, kind: String) -> bool:
	for event in game_root.simulation.snapshot().get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			return true
	return false


func _last_event_payload(game_root: Node, kind: String) -> Dictionary:
	var events: Array = game_root.simulation.snapshot().get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = events[index]
		if event_data.get("kind", "") == kind:
			return event_data.get("payload", {})
	return {}


func _mark_item_as_quest(game_root: Node, item_id: String) -> void:
	var data: Dictionary = _item_data(game_root, item_id)
	var fragments: Array = data.get("fragments", [])
	fragments.append({"kind": "quest"})
	data["fragments"] = fragments


func _unmark_item_as_quest(game_root: Node, item_id: String) -> void:
	var data: Dictionary = _item_data(game_root, item_id)
	var output: Array = []
	for fragment in data.get("fragments", []):
		var fragment_data: Dictionary = fragment
		if str(fragment_data.get("kind", "")) == "quest":
			continue
		output.append(fragment_data)
	data["fragments"] = output


func _item_data(game_root: Node, item_id: String) -> Dictionary:
	var record: Dictionary = game_root.registry.get_library("items").get(item_id, {})
	return record.get("data", {})


func _summary_line(game_root: Node) -> String:
	return game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/SummaryLine").text


func _item_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemScroll/ItemLines")
	for child in item_box.get_children():
		var text := _control_text(child)
		if not text.is_empty():
			output.append(text)
	return output


func _filter_button(game_root: Node, node_name: String) -> Button:
	return game_root.inventory_panel.find_child(node_name, true, false) as Button


func _sort_button(game_root: Node, node_name: String) -> Button:
	return game_root.inventory_panel.find_child(node_name, true, false) as Button


func _search_box(game_root: Node) -> LineEdit:
	return game_root.inventory_panel.find_child("SearchBox", true, false) as LineEdit


func _use_button(game_root: Node) -> Button:
	return game_root.inventory_panel.find_child("UseSelectedButton", true, false) as Button


func _equip_button(game_root: Node) -> Button:
	return game_root.inventory_panel.find_child("EquipSelectedButton", true, false) as Button


func _drop_button(game_root: Node) -> Button:
	return game_root.inventory_panel.find_child("DropSelectedButton", true, false) as Button


func _quantity_spin(game_root: Node) -> SpinBox:
	return game_root.inventory_panel.find_child("QuantitySpin", true, false) as SpinBox


func _discard_dialog_visible(game_root: Node) -> bool:
	var dialog: Node = game_root.inventory_panel.get_node_or_null("DiscardConfirmDialog")
	if dialog is ConfirmationDialog:
		return bool((dialog as ConfirmationDialog).visible)
	return false


func _confirm_discard_dialog(game_root: Node) -> void:
	var dialog: Node = game_root.inventory_panel.get_node_or_null("DiscardConfirmDialog")
	if dialog is ConfirmationDialog:
		(dialog as ConfirmationDialog).confirmed.emit()
		(dialog as ConfirmationDialog).hide()


func _emit_discard_confirm(game_root: Node) -> void:
	var dialog: Node = game_root.inventory_panel.get_node_or_null("DiscardConfirmDialog")
	if dialog is ConfirmationDialog:
		(dialog as ConfirmationDialog).confirmed.emit()


func _discard_quantity_input(game_root: Node) -> LineEdit:
	return game_root.inventory_panel.find_child("DiscardQuantityInput", true, false) as LineEdit


func _discard_error_text(game_root: Node) -> String:
	var label: Node = game_root.inventory_panel.find_child("DiscardQuantityError", true, false)
	if label is Label:
		return str((label as Label).text)
	return ""


func _press_discard_quantity_button(game_root: Node, button_name: String) -> void:
	var button: Button = game_root.inventory_panel.find_child(button_name, true, false) as Button
	if button != null and not button.disabled:
		button.pressed.emit()


func _open_inventory_context_menu(game_root: Node, item_needle: String) -> bool:
	var source: Button = _inventory_item_button(game_root, item_needle)
	if source == null or not source.has_meta("inventory_item"):
		return false
	game_root.inventory_panel.call("_open_context_menu_for_item", source.get_meta("inventory_item"), Vector2.ZERO)
	return true


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


func _reorder_inventory_item_before(game_root: Node, item_needle: String, target_needle: String) -> bool:
	var source: Button = _inventory_item_button(game_root, item_needle)
	var target: Button = _inventory_item_button(game_root, target_needle)
	if source == null or target == null or not source.has_meta("inventory_item"):
		return false
	game_root.inventory_panel.call("_drop_inventory_data", Vector2.ZERO, {
		"kind": "inventory_item",
		"item": source.get_meta("inventory_item"),
		"item_id": str(source.get_meta("inventory_item").get("item_id", "")),
		"from_index": int(source.get_meta("inventory_index", 0)),
	}, target)
	return true


func _append_inventory_item_by_drag(game_root: Node, item_needle: String) -> bool:
	var source: Button = _inventory_item_button(game_root, item_needle)
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemScroll/ItemLines")
	if source == null or item_box == null or not source.has_meta("inventory_item"):
		return false
	game_root.inventory_panel.call("_drop_inventory_data", Vector2.ZERO, {
		"kind": "inventory_item",
		"item": source.get_meta("inventory_item"),
		"item_id": str(source.get_meta("inventory_item").get("item_id", "")),
		"from_index": int(source.get_meta("inventory_index", 0)),
	}, item_box)
	return true


func _drag_inventory_item_to_action(game_root: Node, item_needle: String, target_button_name: String) -> bool:
	var source: Button = _inventory_item_button(game_root, item_needle)
	var target: Button = game_root.inventory_panel.find_child(target_button_name, true, false) as Button
	if source == null or target == null or not source.has_meta("inventory_item"):
		return false
	game_root.inventory_panel.call("_drop_inventory_action_data", Vector2.ZERO, {
		"kind": "inventory_item",
		"item": source.get_meta("inventory_item"),
		"item_id": str(source.get_meta("inventory_item").get("item_id", "")),
		"from_index": int(source.get_meta("inventory_index", 0)),
	}, target)
	return true


func _inventory_item_button(game_root: Node, needle: String) -> Button:
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemScroll/ItemLines")
	for child in item_box.get_children():
		if child is Button and str((child as Button).text).contains(needle):
			return child as Button
	return null


func _press_inventory_item_with_text(game_root: Node, needle: String) -> bool:
	var button: Button = _inventory_item_button(game_root, needle)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _detail_line(game_root: Node) -> String:
	var label: Node = game_root.inventory_panel.get_node_or_null("InventoryPanel/InventoryLines/DetailLine")
	if label is Label:
		return str((label as Label).text)
	return ""


func _text_ordered(text: String, first: String, second: String) -> bool:
	var first_index: int = text.find(first)
	var second_index: int = text.find(second)
	return first_index >= 0 and second_index >= 0 and first_index < second_index


func _control_text(control: Node) -> String:
	if control is Button:
		return str((control as Button).text)
	if control is Label:
		return str((control as Label).text)
	return ""
