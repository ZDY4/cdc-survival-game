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
	if _search_box(game_root) == null:
		errors.append("crafting panel should expose recipe search")
	if _category_button(game_root, "medical") == null:
		errors.append("crafting panel should expose medical category filter")
	if _sort_button(game_root, "SortCraftableButton") == null:
		errors.append("crafting panel should expose craftable sort")
	if _recipe_lines(game_root).size() <= 8:
		errors.append("crafting panel should show full scrollable recipe list")
	if not _recipe_text(game_root).contains("基础绷带"):
		errors.append("crafting panel missing basic bandage recipe")
	if not _recipe_text(game_root).contains("材料不足"):
		errors.append("basic bandage should initially show missing materials")
	_press_category_button(game_root, "weapon")
	await process_frame
	if _recipe_text(game_root).contains("基础绷带"):
		errors.append("weapon category filter should hide medical recipes")
	if not _recipe_text(game_root).contains("小刀"):
		errors.append("weapon category filter should show weapon recipes")
	_press_category_button(game_root, "medical")
	await process_frame
	if not _summary_line(game_root).contains("医疗"):
		errors.append("crafting summary should show active category")
	if not _recipe_text(game_root).contains("基础绷带"):
		errors.append("medical category filter should show bandage recipe")
	var search := _search_box(game_root)
	if search != null:
		search.text = "血清"
		search.text_changed.emit(search.text)
		await process_frame
		if not _recipe_text(game_root).contains("抗体血清"):
			errors.append("crafting search should match recipe names")
		if _recipe_text(game_root).contains("基础绷带"):
			errors.append("crafting search should hide non-matching recipes")
		search.text = ""
		search.text_changed.emit(search.text)
		await process_frame
	_press_category_button(game_root, "all")
	await process_frame
	if _craft_button(game_root, "recipe_bandage_basic") == null or not _craft_button(game_root, "recipe_bandage_basic").disabled:
		errors.append("basic bandage craft button should be disabled before cloth is available")
	var locked_result: Dictionary = game_root.craft_player_recipe("recipe_antibody_serum")
	game_root.crafting_panel.call("_set_feedback_from_result", locked_result, _recipe_snapshot(game_root, "recipe_antibody_serum"))
	if not _feedback_text(game_root).contains("制作失败: 抗体血清 | 配方未解锁"):
		errors.append("crafting panel should show failed craft feedback")
	if not _press_recipe_line(game_root, "recipe_bandage_basic"):
		errors.append("should select basic bandage recipe for detail")
	await process_frame
	if not _detail_text(game_root).contains("详情: 基础绷带"):
		errors.append("crafting detail should show selected recipe title")
	if not _detail_text(game_root).contains("材料: 布料 0/2"):
		errors.append("crafting detail should show missing material detail")
	if not _detail_text(game_root).contains("最大 0"):
		errors.append("crafting detail should show zero max craft count when unavailable")

	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	player.inventory["1011"] = 4
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	_press_sort_button(game_root, "SortCraftableButton")
	await process_frame
	if not _summary_line(game_root).contains("可制作优先"):
		errors.append("crafting summary should show active sort mode")
	if _recipe_lines(game_root).is_empty() or not _recipe_lines(game_root)[0].contains("基础绷带"):
		errors.append("craftable sort should move craftable recipes to the top")
	if _craft_button(game_root, "recipe_bandage_basic") == null or _craft_button(game_root, "recipe_bandage_basic").disabled:
		errors.append("basic bandage craft button should become enabled after cloth is available")
	if not _press_recipe_line(game_root, "recipe_bandage_basic"):
		errors.append("should select basic bandage recipe")
	await process_frame
	var quantity_spin: SpinBox = _quantity_spin(game_root)
	if quantity_spin == null:
		errors.append("crafting panel should expose quantity spin")
	else:
		if int(quantity_spin.max_value) != 2:
			errors.append("crafting quantity max should reflect available materials")
		quantity_spin.value = 2
		await process_frame
	if not _detail_text(game_root).contains("输出: 绷带 x2"):
		errors.append("crafting detail should preview multiplied output")
	if not _detail_text(game_root).contains("材料: 布料 4/4"):
		errors.append("crafting detail should preview multiplied materials")
	if not _detail_text(game_root).contains("最大 2"):
		errors.append("crafting detail should show max craft count")

	_craft_button(game_root, "recipe_bandage_basic").pressed.emit()
	await process_frame
	if not _feedback_text(game_root).contains("已制作: 基础绷带 -> 绷带 x1"):
		errors.append("crafting panel should show successful craft feedback")
	if _player_inventory_count(game_root, "1011") != 2:
		errors.append("crafting from panel should consume cloth")
	if _player_inventory_count(game_root, "1006") != 2:
		errors.append("crafting from panel should add crafted bandage")
	if not _event_seen(game_root, "recipe_crafted"):
		errors.append("crafting from panel should emit recipe_crafted")
	if not _detail_text(game_root).contains("最大 1"):
		errors.append("crafting panel should refresh max craft count after crafting")
	return errors


func _summary_line(game_root: Node) -> String:
	return game_root.crafting_panel.get_node("CraftingPanel/CraftingLines/SummaryLine").text


func _recipe_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var recipe_box: Node = game_root.crafting_panel.find_child("RecipeLines", true, false)
	if recipe_box == null:
		return output
	for child in recipe_box.get_children():
		if child is HBoxContainer:
			var line: Node = child.get_node("Line")
			if line is Button:
				output.append((line as Button).text)
			elif line is Label:
				output.append((line as Label).text)
	return output


func _recipe_text(game_root: Node) -> String:
	return "\n".join(_recipe_lines(game_root))


func _craft_button(game_root: Node, recipe_id: String) -> Button:
	var row: Node = game_root.crafting_panel.find_child("Recipe_%s" % recipe_id, true, false)
	if row == null:
		return null
	return row.get_node("CraftButton") as Button


func _search_box(game_root: Node) -> LineEdit:
	return game_root.crafting_panel.find_child("SearchBox", true, false) as LineEdit


func _category_button(game_root: Node, category: String) -> Button:
	var node_name := "FilterCategoryAllButton" if category == "all" else "FilterCategory_%s" % category
	return game_root.crafting_panel.find_child(node_name, true, false) as Button


func _sort_button(game_root: Node, node_name: String) -> Button:
	return game_root.crafting_panel.find_child(node_name, true, false) as Button


func _press_category_button(game_root: Node, category: String) -> bool:
	var button := _category_button(game_root, category)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _press_sort_button(game_root: Node, node_name: String) -> bool:
	var button := _sort_button(game_root, node_name)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _press_recipe_line(game_root: Node, recipe_id: String) -> bool:
	var row: Node = game_root.crafting_panel.find_child("Recipe_%s" % recipe_id, true, false)
	if row == null:
		return false
	var line: Button = row.get_node("Line") as Button
	if line == null:
		return false
	line.pressed.emit()
	return true


func _quantity_spin(game_root: Node) -> SpinBox:
	return game_root.crafting_panel.find_child("CraftQuantitySpin", true, false) as SpinBox


func _detail_text(game_root: Node) -> String:
	var title: Node = game_root.crafting_panel.find_child("DetailTitleLine", true, false)
	var body: Node = game_root.crafting_panel.find_child("DetailBodyLine", true, false)
	var parts: Array[String] = []
	if title is Label:
		parts.append((title as Label).text)
	if body is Label:
		parts.append((body as Label).text)
	return "\n".join(parts)


func _feedback_text(game_root: Node) -> String:
	var label: Node = game_root.crafting_panel.find_child("FeedbackLine", true, false)
	if label is Label:
		return (label as Label).text
	return ""


func _recipe_snapshot(game_root: Node, recipe_id: String) -> Dictionary:
	var snapshot: Dictionary = game_root.crafting_panel.get("_last_snapshot")
	for recipe in snapshot.get("recipes", []):
		var recipe_data: Dictionary = recipe
		if str(recipe_data.get("recipe_id", "")) == recipe_id:
			return recipe_data
	return {"recipe_id": recipe_id, "name": recipe_id}


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
