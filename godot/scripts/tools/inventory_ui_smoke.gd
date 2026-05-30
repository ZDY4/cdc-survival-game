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
	var pickup_result: Dictionary = game_root.execute_primary_interaction()
	if not bool(pickup_result.get("success", false)):
		errors.append("pickup execution failed: %s" % pickup_result.get("reason", "unknown"))

	var item_text: String = "\n".join(_item_lines(game_root))
	if not item_text.contains("绷带 x3"):
		errors.append("inventory panel missing picked bandage line")
	if not _summary_line(game_root).contains("4 类物品"):
		errors.append("inventory summary did not update item count")
	if not _summary_line(game_root).contains("2.1 kg"):
		errors.append("inventory summary did not update total weight")
	return errors


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


func _summary_line(game_root: Node) -> String:
	return game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/SummaryLine").text


func _item_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemLines")
	for child in item_box.get_children():
		if child is Label:
			output.append((child as Label).text)
	return output
