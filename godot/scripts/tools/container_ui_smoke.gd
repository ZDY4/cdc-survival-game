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
	var open_result: Dictionary = game_root.execute_primary_interaction()
	if not bool(open_result.get("success", false)):
		errors.append("container open failed: %s" % open_result.get("reason", "unknown"))
	if not game_root.container_panel.visible:
		errors.append("container panel should be visible after opening container")
	if not _container_summary(game_root).contains("2 类物品"):
		errors.append("container summary should expose initial entries")

	var take_result: Dictionary = game_root.take_active_container_item("1031", 1)
	if not bool(take_result.get("success", false)):
		errors.append("taking container item failed: %s" % take_result.get("reason", "unknown"))
	if not _inventory_text(game_root).contains("抗生素 x1"):
		errors.append("inventory panel missing taken antibiotics")
	if _container_text(game_root).contains("抗生素"):
		errors.append("container panel should remove taken antibiotics")

	var exhausted_take: Dictionary = game_root.take_active_container_item("1031", 1)
	if exhausted_take.get("reason", "") != "container_inventory_insufficient":
		errors.append("taking missing container item should report container_inventory_insufficient")

	var store_result: Dictionary = game_root.store_active_container_item("1008", 1)
	if not bool(store_result.get("success", false)):
		errors.append("storing item failed: %s" % store_result.get("reason", "unknown"))
	if not _container_text(game_root).contains("水瓶 x1"):
		errors.append("container panel missing stored water bottle")
	if _inventory_text(game_root).contains("水瓶 x1"):
		errors.append("inventory panel should remove stored water bottle")

	var missing_store: Dictionary = game_root.store_active_container_item("1008", 1)
	if missing_store.get("reason", "") != "not_enough_items":
		errors.append("storing unavailable item should report not_enough_items")
	return errors


func _container_summary(game_root: Node) -> String:
	return game_root.container_panel.get_node("ContainerPanel/ContainerLines/SummaryLine").text


func _inventory_summary(game_root: Node) -> String:
	return game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/SummaryLine").text


func _container_text(game_root: Node) -> String:
	return "\n".join(_container_item_lines(game_root))


func _inventory_text(game_root: Node) -> String:
	var output: Array[String] = []
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemLines")
	for child in item_box.get_children():
		if child is Label:
			output.append((child as Label).text)
	return "\n".join(output)


func _container_item_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var item_box: Node = game_root.container_panel.get_node("ContainerPanel/ContainerLines/ItemLines")
	for child in item_box.get_children():
		if child is Label:
			output.append((child as Label).text)
	return output
