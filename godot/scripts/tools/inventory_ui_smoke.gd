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


func _summary_line(game_root: Node) -> String:
	return game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/SummaryLine").text


func _item_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemLines")
	for child in item_box.get_children():
		if child is Label:
			output.append((child as Label).text)
	return output
