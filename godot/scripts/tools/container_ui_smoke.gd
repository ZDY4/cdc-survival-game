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
	if not game_root.container_panel.visible:
		errors.append("container panel should be visible after opening container")
	if not _container_summary(game_root).contains("2 类物品"):
		errors.append("container summary should expose initial entries")
	if not _container_text(game_root).contains("抗生素"):
		errors.append("container column should expose container items")
	if not _container_player_text(game_root).contains("水瓶"):
		errors.append("player column should expose inventory items")
	if not _container_text(game_root).contains("kg") or not _container_player_text(game_root).contains("kg"):
		errors.append("container columns should expose basic item detail text")
	if not _container_has_scroll_columns(game_root):
		errors.append("container panel should wrap both item columns in scroll containers")
	if not _container_detail(game_root).contains("容器：") or not _container_detail(game_root).contains("单重"):
		errors.append("container detail line should default to selected container item details")
	_press_first_player_container_item(game_root)
	if not _container_detail(game_root).contains("背包：") or not _container_detail(game_root).contains("总重"):
		errors.append("container detail line should switch to selected player item details")
	if _container_transfer_button_text(game_root) != "存放":
		errors.append("selecting player item should set transfer action to store")
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
	if not _open_inventory_context_menu(game_root, "水瓶"):
		errors.append("should open inventory context menu for water bottle while container is active")
	elif _context_action_disabled(game_root, 9):
		errors.append("inventory context menu should enable store-in-container when a container is active")
	else:
		_execute_inventory_context_action(game_root, 9)
		if not _event_seen(game_root, "container_item_stored"):
			errors.append("inventory context store should emit container_item_stored")
		if not _container_text(game_root).contains("水瓶 x2"):
			errors.append("inventory context store should move water bottle into container")
		if _inventory_text(game_root).contains("水瓶 x1"):
			errors.append("inventory context store should remove water bottle from inventory panel")

	var missing_store: Dictionary = game_root.store_active_container_item("1008", 1)
	if missing_store.get("reason", "") != "not_enough_items":
		errors.append("storing unavailable item should report not_enough_items")
	if not _container_feedback(game_root).contains("背包中没有足够的水瓶"):
		errors.append("storing unavailable item should show inventory failure feedback")
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
	_press_key(game_root, KEY_ESCAPE)
	if game_root.container_panel.visible:
		errors.append("Esc should close container panel")
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


func _event_seen(game_root: Node, kind: String) -> bool:
	for event in game_root.simulation.snapshot().get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			return true
	return false


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


func _container_item_button_with_text(game_root: Node, source: String, text: String) -> Button:
	var item_box: Node = _container_item_box(game_root, source)
	if item_box == null:
		return null
	for child in item_box.get_children():
		if child is Button and str((child as Button).text).contains(text):
			return child as Button
	return null


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
