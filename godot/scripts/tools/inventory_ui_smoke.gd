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
	_expect_main_hand_model(errors, game_root, "preview_placeholders/placeholders/weapon_dagger.gltf")

	var equip_result: Dictionary = game_root.equip_player_item("1003", "main_hand")
	if not bool(equip_result.get("success", false)):
		errors.append("equipping baseball bat through game app failed: %s" % equip_result.get("reason", "unknown"))
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
	var drop_result: Dictionary = game_root.drop_player_item("1006", 2)
	if not bool(drop_result.get("success", false)):
		errors.append("dropping picked bandages failed: %s" % drop_result.get("reason", "unknown"))
	if _player_inventory_count(game_root, "1006") != 1:
		errors.append("dropping bandages should remove the requested count from inventory")
	if game_root.find_child("Corpse_%s" % drop_result.get("container_id", ""), true, false) == null:
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
		or result.has("context_snapshot") \
		or bool(result.get("waited", false)) \
		or bool(result.get("defeated", false))


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


func _summary_line(game_root: Node) -> String:
	return game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/SummaryLine").text


func _item_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemLines")
	for child in item_box.get_children():
		var text := _control_text(child)
		if not text.is_empty():
			output.append(text)
	return output


func _filter_button(game_root: Node, node_name: String) -> Button:
	return game_root.inventory_panel.find_child(node_name, true, false) as Button


func _sort_button(game_root: Node, node_name: String) -> Button:
	return game_root.inventory_panel.find_child(node_name, true, false) as Button


func _press_inventory_item_with_text(game_root: Node, needle: String) -> bool:
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemLines")
	for child in item_box.get_children():
		if child is Button and str((child as Button).text).contains(needle):
			(child as Button).pressed.emit()
			return true
	return false


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
