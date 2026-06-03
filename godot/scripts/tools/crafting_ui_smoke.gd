extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")


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

	print("crafting_ui_smoke passed:")
	print(JSON.stringify({
		"summary": _summary_line(game_root),
		"recipes": _recipe_lines(game_root).slice(0, 5),
	}, "\t"))
	quit(0)


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	if game_root.crafting_panel == null:
		return ["crafting panel was not created"]
	if not _summary_line(game_root).contains("配方"):
		errors.append("crafting summary should show recipe count")
	if not _recipe_text(game_root).contains("基础绷带"):
		errors.append("crafting panel missing basic bandage recipe")
	if not _recipe_text(game_root).contains("材料不足"):
		errors.append("basic bandage should initially show missing materials")
	if _craft_button(game_root, "recipe_bandage_basic") == null or not _craft_button(game_root, "recipe_bandage_basic").disabled:
		errors.append("basic bandage craft button should be disabled before cloth is available")

	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	player.inventory["1011"] = 2
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	if _craft_button(game_root, "recipe_bandage_basic") == null or _craft_button(game_root, "recipe_bandage_basic").disabled:
		errors.append("basic bandage craft button should become enabled after cloth is available")

	_craft_button(game_root, "recipe_bandage_basic").pressed.emit()
	await process_frame
	if _player_inventory_count(game_root, "1011") != 0:
		errors.append("crafting from panel should consume cloth")
	if _player_inventory_count(game_root, "1006") != 2:
		errors.append("crafting from panel should add crafted bandage")
	if not _event_seen(game_root, "recipe_crafted"):
		errors.append("crafting from panel should emit recipe_crafted")
	if not _recipe_text(game_root).contains("材料不足"):
		errors.append("crafting panel should refresh missing materials after crafting")
	return errors


func _summary_line(game_root: Node) -> String:
	return game_root.crafting_panel.get_node("CraftingPanel/CraftingLines/SummaryLine").text


func _recipe_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var recipe_box: Node = game_root.crafting_panel.get_node("CraftingPanel/CraftingLines/RecipeLines")
	for child in recipe_box.get_children():
		if child is HBoxContainer:
			var line: Label = child.get_node("Line")
			output.append(line.text)
	return output


func _recipe_text(game_root: Node) -> String:
	return "\n".join(_recipe_lines(game_root))


func _craft_button(game_root: Node, recipe_id: String) -> Button:
	var row: Node = game_root.crafting_panel.find_child("Recipe_%s" % recipe_id, true, false)
	if row == null:
		return null
	return row.get_node("CraftButton") as Button


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
