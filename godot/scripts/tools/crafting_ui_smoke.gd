extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")


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
	if not _recipe_line_has_icon(game_root, "recipe_bandage_basic", "res://assets/icons/items/bandage.svg"):
		errors.append("basic bandage recipe row should render migrated output item icon")
	var bandage_thumbnail := _dictionary_or_empty(_recipe_snapshot(game_root, "recipe_bandage_basic").get("thumbnail_asset", {}))
	if str(bandage_thumbnail.get("resource_path", "")) != "res://assets/icons/items/bandage.svg" or str(bandage_thumbnail.get("thumbnail_domain", "")) != "recipe":
		errors.append("basic bandage recipe snapshot should expose output thumbnail asset: %s" % bandage_thumbnail)
	_press_category_button(game_root, "weapon")
	await process_frame
	_assert_crafting_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "FilterCategory_weapon", "filter_button", "filter_category", {"category_id": "weapon"}, "weapon category filter audio")
	if _recipe_text(game_root).contains("基础绷带"):
		errors.append("weapon category filter should hide medical recipes")
	if not _recipe_text(game_root).contains("小刀"):
		errors.append("weapon category filter should show weapon recipes")
	_install_unlock_source_smoke_recipes(game_root)
	game_root.refresh_crafting_panel()
	await process_frame
	if not _press_recipe_line(game_root, "smoke_skill_unlock_recipe"):
		errors.append("should select skill unlock smoke recipe")
	await process_frame
	if not _recipe_line(game_root, "smoke_skill_unlock_recipe").contains("未解锁 生存本能 0/2"):
		errors.append("skill unlock recipe row should show missing skill level")
	if not _detail_text(game_root).contains("解锁 技能 生存本能 Lv2"):
		errors.append("skill unlock recipe detail should show skill unlock requirement")
	var skill_unlock_locator: Button = _missing_reason_button(game_root, "MissingReasonUnlock_survival")
	if skill_unlock_locator == null:
		errors.append("crafting detail should expose missing skill unlock locator")
	else:
		skill_unlock_locator.pressed.emit()
		await process_frame
		_assert_crafting_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "MissingReasonUnlock_survival", "missing_reason_button", "locate_missing_reason", {"recipe_id": "smoke_skill_unlock_recipe", "value": "生存本能"}, "skill unlock locator audio")
		if _search_box(game_root) == null or _search_box(game_root).text != "生存本能":
			errors.append("missing skill unlock locator should search by skill name")
		_search_box(game_root).text = ""
		_search_box(game_root).text_changed.emit("")
		await process_frame
	var player_for_unlock_sources: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	player_for_unlock_sources.progression["learned_skills"]["survival"] = 2
	game_root.refresh_crafting_panel()
	await process_frame
	if _recipe_line(game_root, "smoke_skill_unlock_recipe").contains("未解锁 生存本能"):
		errors.append("skill unlock recipe row should stop showing lock after required skill")
	if not _press_recipe_line(game_root, "smoke_quest_unlock_recipe"):
		errors.append("should select quest unlock smoke recipe")
	await process_frame
	if not _recipe_line(game_root, "smoke_quest_unlock_recipe").contains("未解锁 补给试跑"):
		errors.append("quest unlock recipe row should show missing quest title")
	if not _detail_text(game_root).contains("解锁 任务 补给试跑"):
		errors.append("quest unlock recipe detail should show quest unlock requirement")
	var quest_unlock_locator: Button = _missing_reason_button(game_root, "MissingReasonUnlock_tutorial_survive")
	if quest_unlock_locator == null:
		errors.append("crafting detail should expose missing quest unlock locator")
	else:
		quest_unlock_locator.pressed.emit()
		await process_frame
		if _search_box(game_root) == null or _search_box(game_root).text != "补给试跑":
			errors.append("missing quest unlock locator should search by quest title")
		_search_box(game_root).text = ""
		_search_box(game_root).text_changed.emit("")
		await process_frame
	game_root.simulation.completed_quests["tutorial_survive"] = true
	game_root.refresh_crafting_panel()
	await process_frame
	if _recipe_line(game_root, "smoke_quest_unlock_recipe").contains("未解锁 补给试跑"):
		errors.append("quest unlock recipe row should stop showing lock after required quest")
	if not _press_recipe_line(game_root, "smoke_item_unlock_recipe"):
		errors.append("should select item unlock smoke recipe")
	await process_frame
	if not _recipe_line(game_root, "smoke_item_unlock_recipe").contains("未解锁 塑料"):
		errors.append("item unlock recipe row should show missing item name")
	if not _detail_text(game_root).contains("解锁 物品 塑料 x1"):
		errors.append("item unlock recipe detail should show item unlock requirement")
	player_for_unlock_sources.inventory["1104"] = 1
	game_root.refresh_crafting_panel()
	await process_frame
	if _recipe_line(game_root, "smoke_item_unlock_recipe").contains("未解锁 塑料"):
		errors.append("item unlock recipe row should stop showing lock after required item")
	player_for_unlock_sources.inventory.erase("1104")
	if not _press_recipe_line(game_root, "smoke_book_unlock_recipe"):
		errors.append("should select book unlock smoke recipe")
	await process_frame
	if not _recipe_line(game_root, "smoke_book_unlock_recipe").contains("未解锁 抗生素"):
		errors.append("book unlock recipe row should show missing book item name")
	if not _detail_text(game_root).contains("解锁 书籍 抗生素"):
		errors.append("book unlock recipe detail should show book unlock requirement")
	player_for_unlock_sources.inventory["1031"] = 1
	game_root.refresh_crafting_panel()
	await process_frame
	if _recipe_line(game_root, "smoke_book_unlock_recipe").contains("未解锁 抗生素"):
		errors.append("book unlock recipe row should stop showing lock after required book item")
	player_for_unlock_sources.inventory.erase("1031")
	if not _press_recipe_line(game_root, "smoke_world_flag_unlock_recipe"):
		errors.append("should select world flag unlock smoke recipe")
	await process_frame
	if not _recipe_line(game_root, "smoke_world_flag_unlock_recipe").contains("未解锁 outpost_workshop_restored"):
		errors.append("world flag unlock recipe row should show missing flag id")
	if not _detail_text(game_root).contains("解锁 世界状态 outpost_workshop_restored"):
		errors.append("world flag unlock recipe detail should show world flag requirement")
	game_root.simulation.world_flags["outpost_workshop_restored"] = true
	game_root.refresh_crafting_panel()
	await process_frame
	if _recipe_line(game_root, "smoke_world_flag_unlock_recipe").contains("未解锁 outpost_workshop_restored"):
		errors.append("world flag unlock recipe row should stop showing lock after required flag")
	game_root.simulation.world_flags.erase("outpost_workshop_restored")
	var player_for_consumable_tool: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	player_for_consumable_tool.inventory["1011"] = 1
	player_for_consumable_tool.inventory["1151"] = 1
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	if not _press_recipe_line(game_root, "smoke_consumes_tool_recipe"):
		errors.append("should select consumable tool smoke recipe")
	await process_frame
	if not _detail_text(game_root).contains("工具 螺丝刀 1/1 消耗x1"):
		errors.append("crafting detail should preview consumed required tool")
	var consumable_tool_snapshot: Dictionary = _recipe_snapshot(game_root, "smoke_consumes_tool_recipe")
	var required_tools: Array = _array_or_empty(consumable_tool_snapshot.get("required_tools", []))
	if required_tools.is_empty() or not bool(_dictionary_or_empty(required_tools[0]).get("consume_on_craft", false)):
		errors.append("crafting snapshot should expose consume_on_craft for required tool")
	var consumable_tool_result: Dictionary = game_root.craft_player_recipe("smoke_consumes_tool_recipe")
	if not bool(consumable_tool_result.get("success", false)):
		errors.append("consumable tool UI craft should succeed: %s" % consumable_tool_result.get("reason", "unknown"))
	if _player_inventory_count(game_root, "1151") != 0:
		errors.append("consumable tool UI craft should consume player inventory tool")
	if _array_or_empty(consumable_tool_result.get("consumed_tools", [])).is_empty():
		errors.append("consumable tool UI craft result should expose consumed_tools")
	player_for_consumable_tool.inventory["1011"] = 1
	player_for_consumable_tool.inventory.erase("1151")
	player_for_consumable_tool.equipment["utility"] = "1151"
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	if not _press_recipe_line(game_root, "smoke_consumes_tool_recipe"):
		errors.append("should select consumable tool smoke recipe for equipped tool")
	await process_frame
	var equipped_tool_snapshot: Dictionary = _recipe_snapshot(game_root, "smoke_consumes_tool_recipe")
	var equipped_required_tools: Array = _array_or_empty(equipped_tool_snapshot.get("required_tools", []))
	if equipped_required_tools.is_empty() or int(_dictionary_or_empty(equipped_required_tools[0]).get("equipment_available", 0)) != 1:
		errors.append("crafting snapshot should expose equipped consumable tool availability: %s" % equipped_required_tools)
	var craft_button: Button = _craft_button(game_root, "smoke_consumes_tool_recipe")
	if craft_button == null:
		errors.append("equipped consumable tool recipe should expose craft button")
	else:
		craft_button.pressed.emit()
		await process_frame
		if not _craft_equipment_dialog_visible(game_root):
			errors.append("equipped consumable tool craft should open equipment consumption confirmation")
		_assert_craft_equipment_modal_details(errors, game_root, "smoke_consumes_tool_recipe", 1, "1151", "utility", "equipped craft confirmation")
		var esc_craft_result: Dictionary = game_root.close_active_ui("keyboard_escape")
		if str(esc_craft_result.get("closed", "")) != "modal:craft_equipment_tool_confirm":
			errors.append("Esc should close equipped craft confirmation before consuming equipment, got %s" % esc_craft_result)
		if not player_for_consumable_tool.equipment.has("utility"):
			errors.append("Esc closing equipped craft confirmation should keep equipped tool")
		if _player_inventory_count(game_root, "1011") != 1:
			errors.append("Esc closing equipped craft confirmation should keep craft material")
		craft_button = _craft_button(game_root, "smoke_consumes_tool_recipe")
		if craft_button == null:
			errors.append("equipped consumable tool recipe should still expose craft button after Esc")
		else:
			craft_button.pressed.emit()
			await process_frame
			_confirm_craft_equipment_dialog(game_root)
			await process_frame
			_assert_crafting_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "CraftEquipmentToolConfirmDialog", "dialog", "confirm_equipment_tool_craft", {"recipe_id": "smoke_consumes_tool_recipe", "count": "1"}, "equipped craft confirmation audio")
	if player_for_consumable_tool.equipment.has("utility"):
		errors.append("confirmed equipped consumable craft should remove equipment slot")
	if _player_inventory_count(game_root, "1011") != 0:
		errors.append("confirmed equipped consumable craft should consume material")
	var equipped_craft_event: Dictionary = _last_event_payload(game_root, "recipe_crafted")
	var equipped_consumed_tools: Array = _array_or_empty(equipped_craft_event.get("consumed_tools", []))
	if equipped_consumed_tools.is_empty() or str(_dictionary_or_empty(equipped_consumed_tools[0]).get("source", "")) != "equipment":
		errors.append("equipped consumable tool craft event should report equipment source: %s" % equipped_consumed_tools)
	player_for_consumable_tool.inventory["1011"] = 1
	player_for_consumable_tool.equipment.clear()
	var nearby_tool_grid: Dictionary = player_for_consumable_tool.grid_position.to_dictionary()
	game_root.simulation.map_interaction_targets["smoke_consumable_tool_crate_ui"] = {
		"target_id": "smoke_consumable_tool_crate_ui",
		"target_type": "map_object",
		"display_name": "消耗工具箱",
		"kind": "container",
		"anchor": nearby_tool_grid,
		"cells": [nearby_tool_grid],
		"container_inventory": [{"item_id": "1151", "count": 1}],
	}
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	var nearby_consumable_tool_result: Dictionary = game_root.craft_player_recipe("smoke_consumes_tool_recipe")
	if not bool(nearby_consumable_tool_result.get("success", false)):
		errors.append("nearby container consumable tool UI craft should succeed: %s" % nearby_consumable_tool_result.get("reason", "unknown"))
	var nearby_tool_target: Dictionary = _dictionary_or_empty(game_root.simulation.map_interaction_targets.get("smoke_consumable_tool_crate_ui", {}))
	if _inventory_entry_count(_array_or_empty(nearby_tool_target.get("container_inventory", [])), "1151") != 0:
		errors.append("nearby container consumable tool UI craft should consume target container tool")
	var nearby_consumed_tools: Array = _array_or_empty(nearby_consumable_tool_result.get("consumed_tools", []))
	var nearby_source_seen := false
	for consumed_tool in nearby_consumed_tools:
		var consumed_tool_data: Dictionary = _dictionary_or_empty(consumed_tool)
		if str(consumed_tool_data.get("source", "")) == "nearby_container" and str(consumed_tool_data.get("container_id", "")) == "smoke_consumable_tool_crate_ui":
			nearby_source_seen = true
	if not nearby_source_seen:
		errors.append("nearby container consumable tool UI craft should report container source: %s" % nearby_consumed_tools)
	game_root.simulation.map_interaction_targets.erase("smoke_consumable_tool_crate_ui")
	player_for_consumable_tool.inventory["1011"] = 2
	player_for_consumable_tool.inventory["1151"] = 1
	player_for_consumable_tool.tool_durability["1151"] = 5.0
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	if not _press_recipe_line(game_root, "smoke_durable_tool_recipe"):
		errors.append("should select durable tool smoke recipe")
	await process_frame
	if not _detail_text(game_root).contains("工具 螺丝刀 1/1 耐久5.0/-3.0"):
		errors.append("crafting detail should preview required tool durability")
	var durable_tool_snapshot: Dictionary = _recipe_snapshot(game_root, "smoke_durable_tool_recipe")
	var durable_required_tools: Array = _array_or_empty(durable_tool_snapshot.get("required_tools", []))
	if durable_required_tools.is_empty() or not is_equal_approx(float(_dictionary_or_empty(durable_required_tools[0]).get("available_durability", 0.0)), 5.0):
		errors.append("crafting snapshot should expose available tool durability")
	var durable_tool_result: Dictionary = game_root.craft_player_recipe("smoke_durable_tool_recipe")
	if not bool(durable_tool_result.get("success", false)):
		errors.append("durable tool UI craft should succeed: %s" % durable_tool_result.get("reason", "unknown"))
	if _player_inventory_count(game_root, "1151") != 1:
		errors.append("durable tool UI craft should not consume the tool item")
	if not is_equal_approx(float(player_for_consumable_tool.tool_durability.get("1151", 0.0)), 2.0):
		errors.append("durable tool UI craft should reduce tool durability")
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	if not _press_recipe_line(game_root, "smoke_durable_tool_recipe"):
		errors.append("should reselect durable tool smoke recipe after durability loss")
	await process_frame
	if not _recipe_line(game_root, "smoke_durable_tool_recipe").contains("工具耐久不足"):
		errors.append("durable tool recipe row should show durability shortage after durability loss")
	if str(_recipe_snapshot(game_root, "smoke_durable_tool_recipe").get("craft_reason", "")) != "tool_durability_insufficient":
		errors.append("durable tool recipe snapshot should expose tool_durability_insufficient")
	player_for_consumable_tool.inventory.erase("1151")
	player_for_consumable_tool.tool_durability.erase("1151")
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	if not _recipe_line(game_root, "recipe_advanced_knife").contains("未解锁 基础小刀"):
		errors.append("recipe-chain gated recipe row should show missing source recipe")
	if not _press_recipe_line(game_root, "recipe_advanced_knife"):
		errors.append("should select advanced knife recipe for unlock locator smoke")
	await process_frame
	if not _detail_text(game_root).contains("解锁 配方 基础小刀"):
		errors.append("crafting detail should show recipe unlock requirement")
	var unlock_locator: Button = _missing_reason_button(game_root, "MissingReasonUnlock_recipe_knife_basic")
	if unlock_locator == null:
		errors.append("crafting detail should expose missing recipe unlock locator")
	else:
		unlock_locator.pressed.emit()
		await process_frame
		if _search_box(game_root) == null or _search_box(game_root).text != "基础小刀":
			errors.append("missing unlock locator should populate crafting search with source recipe name")
		if not _recipe_text(game_root).contains("基础小刀"):
			errors.append("missing unlock locator should keep source recipe visible")
		_search_box(game_root).text = ""
		_search_box(game_root).text_changed.emit("")
		await process_frame
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
		_assert_crafting_control_audio(errors, game_root, "ui_slider_changed", "ui_slider", "SearchBox", "line_edit", "search_recipe", {"value": "血清"}, "crafting search audio")
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
	if str(game_root.crafting_panel.call("_craft_failure_text", "inventory_over_capacity")) != "背包容量不足":
		errors.append("crafting failure text should use reason catalog fallback for inventory reasons")
	if str(game_root.crafting_panel.call("_craft_failure_text", "smoke_unknown_reason")) != "smoke_unknown_reason":
		errors.append("crafting failure text should preserve unknown reason fallback")
	var fallback_recipe := {"craft_reason": "inventory_over_capacity"}
	if str(game_root.crafting_panel.call("_reason_text", fallback_recipe)) != "背包容量不足":
		errors.append("crafting recipe reason text should use reason catalog fallback")
	if not _press_recipe_line(game_root, "recipe_bandage_basic"):
		errors.append("should select basic bandage recipe for detail")
	await process_frame
	if not _detail_text(game_root).contains("详情: 基础绷带"):
		errors.append("crafting detail should show selected recipe title")
	if not _detail_text(game_root).contains("材料: 布料 0/2"):
		errors.append("crafting detail should show missing material detail")
	if not _detail_text(game_root).contains("最大 0"):
		errors.append("crafting detail should show zero max craft count when unavailable")
	var material_locator: Button = _missing_reason_button(game_root, "MissingReasonMaterial_1011")
	if material_locator == null:
		errors.append("crafting detail should expose missing material locator")
	else:
		material_locator.pressed.emit()
		await process_frame
		if _search_box(game_root) == null or _search_box(game_root).text != "布料":
			errors.append("missing material locator should populate crafting search")
		if not _summary_line(game_root).contains("全部"):
			errors.append("missing material locator should reset category filter to all")
		if not _recipe_text(game_root).contains("基础绷带"):
			errors.append("missing material locator should keep recipes that use the material")
		_search_box(game_root).text = ""
		_search_box(game_root).text_changed.emit("")
		await process_frame
	if not _press_recipe_line(game_root, "recipe_antibody_serum"):
		errors.append("should select locked antibody serum for locator smoke")
	await process_frame
	var skill_locator: Button = _missing_reason_button(game_root, "MissingReasonSkill_medical")
	if skill_locator == null:
		errors.append("crafting detail should expose missing skill locator")
	else:
		skill_locator.pressed.emit()
		await process_frame
		if _search_box(game_root) == null or _search_box(game_root).text != "medical":
			errors.append("missing skill locator should populate crafting search")
		if not _recipe_text(game_root).contains("抗体血清"):
			errors.append("missing skill locator should keep recipes that require the skill")
		_search_box(game_root).text = ""
		_search_box(game_root).text_changed.emit("")
		await process_frame
	if not _press_recipe_line(game_root, "recipe_knife_basic"):
		errors.append("should select basic knife recipe for tool locator smoke")
	await process_frame
	if not _detail_text(game_root).contains("工具 螺丝刀 0/1"):
		errors.append("crafting detail should show missing required tool")
	if not _recipe_line(game_root, "recipe_knife_basic").contains("缺工具 螺丝刀 0/1"):
		errors.append("tool-gated recipe row should show missing tool reason")
	var tool_locator: Button = _missing_reason_button(game_root, "MissingReasonTool_1151")
	if tool_locator == null:
		errors.append("crafting detail should expose missing tool locator")
	else:
		tool_locator.pressed.emit()
		await process_frame
		if _search_box(game_root) == null or _search_box(game_root).text != "螺丝刀":
			errors.append("missing tool locator should populate crafting search with tool name")
		if not _recipe_text(game_root).contains("基础小刀"):
			errors.append("missing tool locator should keep recipes that require the tool")
		_search_box(game_root).text = ""
		_search_box(game_root).text_changed.emit("")
		await process_frame
	var player_for_tool: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	var tool_container_grid: Dictionary = player_for_tool.grid_position.to_dictionary()
	game_root.simulation.map_interaction_targets["smoke_nearby_tool_crate"] = {
		"target_id": "smoke_nearby_tool_crate",
		"target_type": "map_object",
		"display_name": "临时工具箱",
		"kind": "container",
		"anchor": tool_container_grid,
		"cells": [tool_container_grid],
		"container_inventory": [{"item_id": "1151", "count": 1}],
	}
	game_root.refresh_crafting_panel()
	if not _press_recipe_line(game_root, "recipe_knife_basic"):
		errors.append("should reselect basic knife recipe near tool container")
	await process_frame
	if not _detail_text(game_root).contains("工具 螺丝刀 1/1"):
		errors.append("crafting detail should count nearby container tool as available")
	if not _recipe_line(game_root, "recipe_knife_basic").contains("需工作台 workbench"):
		errors.append("tool-gated recipe should advance to station reason when nearby container has tool")
	game_root.simulation.map_interaction_targets.erase("smoke_nearby_tool_crate")
	player_for_tool.inventory["1151"] = 1
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	if not _press_recipe_line(game_root, "recipe_knife_basic"):
		errors.append("should reselect basic knife recipe after adding tool")
	await process_frame
	if not _detail_text(game_root).contains("工具 螺丝刀 1/1"):
		errors.append("crafting detail should show available required tool")
	if not _recipe_line(game_root, "recipe_knife_basic").contains("需工作台 workbench"):
		errors.append("tool-gated recipe should advance to station reason when tool exists")
	if _crafting_station_count(game_root) <= 0:
		errors.append("crafting UI snapshot should expose map crafting station annotations")
	for station_id in ["workbench", "medical_station", "forge"]:
		if not _has_crafting_station(game_root, station_id):
			errors.append("crafting UI snapshot should expose %s station" % station_id)
	var station_snapshot: Dictionary = _dictionary_or_empty(_crafting_snapshot(game_root).get("station_snapshot", {}))
	var workbench_station: Dictionary = _dictionary_or_empty(_dictionary_or_empty(station_snapshot.get("by_id", {})).get("workbench", {}))
	if str(workbench_station.get("display_name", "")) != "工作坊工作台" or int(workbench_station.get("range", 0)) <= 0:
		errors.append("crafting station annotation should expose display name and range from map scene")
	if not workbench_station.has("distance") or not workbench_station.has("in_range"):
		errors.append("crafting station annotation should expose distance and in_range state")
	if not _summary_line(game_root).contains("工作台"):
		errors.append("crafting summary should show station annotation summary")
	var station_locator: Button = _missing_reason_button(game_root, "MissingReasonStation_workbench")
	if station_locator == null:
		errors.append("crafting detail should expose missing station locator")
	else:
		station_locator.pressed.emit()
		await process_frame
		if _search_box(game_root) == null or _search_box(game_root).text != "workbench":
			errors.append("missing station locator should populate crafting search")
		if not _recipe_text(game_root).contains("基础小刀"):
			errors.append("missing station locator should keep recipes that require the station")
		_search_box(game_root).text = ""
		_search_box(game_root).text_changed.emit("")
		await process_frame
	player_for_tool.grid_position = GridCoord.new(33, 0, 31)
	game_root.refresh_crafting_panel()
	if not _press_recipe_line(game_root, "recipe_knife_basic"):
		errors.append("should reselect basic knife recipe near workbench")
	await process_frame
	if not _detail_text(game_root).contains("工作坊工作台 距离"):
		errors.append("crafting detail should show nearby workbench availability")
	var map_data: Dictionary = _dictionary_or_empty(game_root.world_result.get("map", {}))
	var original_stations: Array = _array_or_empty(map_data.get("crafting_stations", [])).duplicate(true)
	map_data["crafting_stations"] = _station_context_with_requirement(_array_or_empty(map_data.get("crafting_stations", [])), "workbench", {
		"required_world_flags": ["crafting_ui_station_permission_smoke"],
	})
	game_root.world_result["map"] = map_data
	game_root.interaction_controller.world_result = game_root.world_result
	if game_root.panel_controller != null:
		game_root.panel_controller.update_world_result(game_root.world_result)
	game_root.refresh_crafting_panel()
	await process_frame
	if not _press_recipe_line(game_root, "recipe_knife_basic"):
		errors.append("should reselect basic knife recipe after station permission gate")
	await process_frame
	if not _recipe_line(game_root, "recipe_knife_basic").contains("工作台未启用 crafting_ui_station_permission_smoke"):
		errors.append("crafting UI should show station permission missing world flag")
	if not _detail_text(game_root).contains("未启用 crafting_ui_station_permission_smoke"):
		errors.append("crafting detail should preview station permission missing world flag")
	_assert_station_permission_preview(errors, game_root, "recipe_knife_basic", false, "station_world_flag_missing", "crafting_ui_station_permission_smoke", "station permission blocked")
	game_root.simulation.world_flags["crafting_ui_station_permission_smoke"] = true
	game_root.refresh_crafting_panel()
	await process_frame
	if _recipe_line(game_root, "recipe_knife_basic").contains("工作台未启用"):
		errors.append("crafting UI should clear station permission reason after world flag")
	if _detail_text(game_root).contains("未启用 crafting_ui_station_permission_smoke"):
		errors.append("crafting detail should clear station permission reason after world flag")
	_assert_station_permission_preview(errors, game_root, "recipe_knife_basic", true, "", "", "station permission restored")
	game_root.simulation.world_flags.erase("crafting_ui_station_permission_smoke")
	map_data["crafting_stations"] = original_stations
	game_root.world_result["map"] = map_data
	game_root.interaction_controller.world_result = game_root.world_result
	if game_root.panel_controller != null:
		game_root.panel_controller.update_world_result(game_root.world_result)
	game_root.refresh_crafting_panel()
	player_for_tool.grid_position = GridCoord.new(32, 0, 10)
	player_for_tool.inventory["1006"] = 2
	player_for_tool.inventory["1031"] = 1
	player_for_tool.progression["learned_skills"]["medical"] = 1
	game_root.refresh_crafting_panel()
	if not _press_recipe_line(game_root, "recipe_antibody_serum"):
		errors.append("should select antibody serum recipe near medical station")
	await process_frame
	if not _detail_text(game_root).contains("诊所医疗台 距离"):
		errors.append("crafting detail should show nearby medical station availability")
	player_for_tool.inventory.erase("1031")
	player_for_tool.inventory["1006"] = 1
	player_for_tool.grid_position = GridCoord.new(34, 0, 31)
	game_root.simulation.crafted_recipes["recipe_knife_basic"] = true
	player_for_tool.inventory["1166"] = 1
	player_for_tool.progression["learned_skills"]["crafting"] = 3
	player_for_tool.progression["learned_skills"]["engineering"] = 2
	game_root.refresh_crafting_panel()
	if not _press_recipe_line(game_root, "recipe_advanced_knife"):
		errors.append("should select advanced knife recipe near forge")
	await process_frame
	if not _detail_text(game_root).contains("工坊熔炉 距离"):
		errors.append("crafting detail should show nearby forge availability")
	player_for_tool.inventory["1010"] = 3
	player_for_tool.inventory["1012"] = 1
	player_for_tool.progression["learned_skills"]["crafting"] = 1
	var unlock_craft_result: Dictionary = game_root.simulation.craft_recipe(1, "recipe_knife_basic", game_root.registry.get_library("recipes"), game_root.call("_crafting_context"))
	if not bool(unlock_craft_result.get("success", false)):
		errors.append("crafting source recipe for unlock should succeed: %s" % unlock_craft_result.get("reason", "unknown"))
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	if not _press_recipe_line(game_root, "recipe_advanced_knife"):
		errors.append("should select advanced knife after source recipe craft")
	await process_frame
	if _recipe_line(game_root, "recipe_advanced_knife").contains("未解锁 基础小刀"):
		errors.append("advanced knife row should stop showing recipe-chain lock after source recipe is crafted")
	if _missing_reason_button(game_root, "MissingReasonUnlock_recipe_knife_basic") != null:
		errors.append("advanced knife detail should stop exposing recipe unlock locator after source recipe is crafted")

	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	player.inventory["1011"] = 4
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	_press_sort_button(game_root, "SortCraftableButton")
	await process_frame
	_assert_crafting_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "SortCraftableButton", "sort_button", "sort_mode", {"sort_id": "craftable"}, "craftable sort audio")
	if not _summary_line(game_root).contains("可制作优先"):
		errors.append("crafting summary should show active sort mode")
	if _recipe_lines(game_root).is_empty() or not _recipe_lines(game_root)[0].contains("基础绷带"):
		errors.append("craftable sort should move craftable recipes to the top")
	if _craft_button(game_root, "recipe_bandage_basic") == null or _craft_button(game_root, "recipe_bandage_basic").disabled:
		errors.append("basic bandage craft button should become enabled after cloth is available")
	if not _press_recipe_line(game_root, "recipe_bandage_basic"):
		errors.append("should select basic bandage recipe")
	await process_frame
	_assert_crafting_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "Recipe_recipe_bandage_basic", "recipe_row", "select_recipe", {"recipe_id": "recipe_bandage_basic", "count": "1"}, "bandage recipe row select audio")
	var quantity_spin: SpinBox = _quantity_spin(game_root)
	if quantity_spin == null:
		errors.append("crafting panel should expose quantity spin")
	else:
		if int(quantity_spin.max_value) != 2:
			errors.append("crafting quantity max should reflect available materials")
		quantity_spin.value = 2
		await process_frame
		_assert_crafting_control_audio(errors, game_root, "ui_slider_changed", "ui_slider", "CraftQuantitySpin", "spin_box", "set_craft_quantity", {"recipe_id": "recipe_bandage_basic", "count": "2", "value": "2"}, "craft quantity spin audio")
	if not _detail_text(game_root).contains("输出: 绷带 x2"):
		errors.append("crafting detail should preview multiplied output")
	if not _detail_text(game_root).contains("材料: 布料 4/4"):
		errors.append("crafting detail should preview multiplied materials")
	if not _detail_text(game_root).contains("最大 2"):
		errors.append("crafting detail should show max craft count")

	var crafted_events_before := _event_count(game_root, "recipe_crafted")
	if _queue_button(game_root, "recipe_bandage_basic") == null or _queue_button(game_root, "recipe_bandage_basic").disabled:
		errors.append("basic bandage queue button should be enabled after cloth is available")
	else:
		_queue_button(game_root, "recipe_bandage_basic").pressed.emit()
		await process_frame
		_assert_crafting_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "QueueButton_recipe_bandage_basic", "button", "queue_recipe", {"recipe_id": "recipe_bandage_basic", "count": "2"}, "queue bandage audio")
		if not _queue_line(game_root).contains("制作队列 1项/2次") or not _queue_line(game_root).contains("基础绷带 x2"):
			errors.append("crafting queue should show queued batch bandage")
		_assert_craft_queue_snapshot(errors, game_root, 1, 2, 2, true, "queued batch bandage")
		_assert_app_craft_queue_snapshot(errors, game_root, 1, 2, "queued batch bandage app state")
		game_root.refresh_crafting_panel()
		await process_frame
		if not _queue_line(game_root).contains("制作队列 1项/2次") or not _queue_line(game_root).contains("基础绷带 x2"):
			errors.append("crafting queue should survive panel refresh")
		_assert_craft_queue_snapshot(errors, game_root, 1, 2, 2, true, "queued batch bandage after refresh")
		if _player_inventory_count(game_root, "1011") != 4:
			errors.append("queueing craft should not consume materials")
		var cancel_button := _cancel_queue_entry_button(game_root, 0)
		if cancel_button == null:
			errors.append("crafting queue entry should expose cancel button")
		else:
			cancel_button.pressed.emit()
			await process_frame
			_assert_crafting_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "CancelCraftQueueEntry_0", "queue_entry_button", "cancel_queue_entry", {"recipe_id": "recipe_bandage_basic", "count": "2", "queue_count": "1", "value": "0"}, "cancel queue entry audio")
			if not _queue_line(game_root).contains("制作队列 空"):
				errors.append("cancelling queued craft should empty queue")
			_assert_craft_queue_snapshot(errors, game_root, 0, 0, 0, false, "cancelled queue item")
			if _player_inventory_count(game_root, "1011") != 4:
				errors.append("cancelling queued craft should not consume materials")
		_queue_button(game_root, "recipe_bandage_basic").pressed.emit()
		await process_frame
		if _confirm_queue_button(game_root) == null or _confirm_queue_button(game_root).disabled:
			errors.append("crafting queue confirm button should enable with queued entries")
		else:
			_confirm_queue_button(game_root).pressed.emit()
	await process_frame
	var confirm_runner: Dictionary = await _wait_for_turn_action_runner_idle(game_root)
	if bool(confirm_runner.get("active", false)):
		errors.append("confirmed queue runner should become idle before next crafting command: %s" % JSON.stringify(confirm_runner))
	_assert_crafting_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "ConfirmCraftQueueButton", "button", "confirm_craft_queue", {"queue_count": "1", "count": "2"}, "confirm craft queue audio")
	if not _feedback_text(game_root).contains("已执行制作队列: 2次"):
		errors.append("crafting panel should show queue execution feedback")
	if not _queue_line(game_root).contains("制作队列 空"):
		errors.append("crafting queue should clear after successful execution")
	_assert_craft_queue_snapshot(errors, game_root, 0, 0, 0, false, "executed queue cleared")
	if _player_inventory_count(game_root, "1011") != 0:
		errors.append("queue crafting from panel should consume selected cloth quantity")
	if _player_inventory_count(game_root, "1006") != 3:
		errors.append("queue crafting from panel should add crafted bandages")
	if not _event_seen(game_root, "recipe_crafted"):
		errors.append("crafting queue from panel should emit recipe_crafted")
	if _event_count(game_root, "recipe_crafted") < crafted_events_before + 2:
		errors.append("queue batch crafting should emit recipe_crafted for each crafted item")
	if not _detail_text(game_root).contains("最大 0"):
		errors.append("crafting panel should refresh max craft count after batch crafting")
	player.inventory["1011"] = 104
	player.ap = 0.5
	game_root.refresh_inventory_panel()
	game_root.refresh_crafting_panel()
	if not _press_recipe_line(game_root, "recipe_bandage_basic"):
		errors.append("should reselect basic bandage for multi-entry queue")
	await process_frame
	var cross_turn_bandages_before := _player_inventory_count(game_root, "1006")
	var cross_turn_crafted_events_before := _event_count(game_root, "recipe_crafted")
	var queue_start: Dictionary = game_root.confirm_crafting_queue([
		{"recipe_id": "recipe_bandage_basic", "count": 50},
		{"recipe_id": "recipe_bandage_basic", "count": 1},
	])
	await process_frame
	if not bool(queue_start.get("success", false)) or not bool(queue_start.get("pending", false)):
		errors.append("multi-entry cross-turn queue should start with pending first entry: %s" % queue_start)
	if int(queue_start.get("advanced_entry_count", 0)) != 1:
		errors.append("multi-entry cross-turn queue should advance only one queue entry per runner action: %s" % queue_start)
	_assert_runner_craft_phase(errors, game_root, "recipe_bandage_basic", 50, true, "confirm_queue", "multi-entry queue pending first")
	if not _pending_crafting_line(game_root).contains("正在制作 基础绷带 x50"):
		errors.append("first multi-entry queue craft should remain pending after AP auto turns: %s" % _pending_crafting_line(game_root))
	if not _queue_line(game_root).contains("制作队列 1项/1次") or not _queue_line(game_root).contains("基础绷带 x1"):
		errors.append("multi-entry queue should retain remaining entry while first craft is pending: %s" % _queue_line(game_root))
	_assert_craft_queue_snapshot(errors, game_root, 1, 1, 1, true, "multi-entry cross-turn queue pending first")
	_assert_queue_feedback(errors, game_root, "confirm", true, 0, 1, "multi-entry cross-turn queue pending first")
	var queue_wait: Dictionary = game_root.submit_wait_action()
	if not bool(queue_wait.get("success", false)):
		errors.append("multi-entry queue wait should complete through GameApp facade: %s" % queue_wait)
	var wait_runner: Dictionary = await _wait_for_turn_action_runner_idle(game_root)
	if bool(wait_runner.get("active", false)):
		errors.append("multi-entry queue wait runner should become idle before assertions: %s" % JSON.stringify(wait_runner))
	var action_chain: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("latest_action_chain", {}))
	var chained_wait_runner: Dictionary = _dictionary_or_empty(action_chain.get("wait_runner", {}))
	if str(action_chain.get("kind", "")) != "craft_to_crafting_queue":
		errors.append("multi-entry queue continuation should expose craft_to_crafting_queue action chain, got %s" % JSON.stringify(action_chain))
	var chained_queue_result: Dictionary = _dictionary_or_empty(action_chain.get("queue_result", {}))
	if int(chained_queue_result.get("advanced_entry_count", 0)) != 1:
		errors.append("multi-entry queue continuation should advance only one queue entry: %s" % JSON.stringify(chained_queue_result))
	if str(chained_wait_runner.get("action_kind", "")) != "craft":
		errors.append("multi-entry queue continuation should be driven by active craft runner, got %s" % JSON.stringify(chained_wait_runner))
	_assert_runner_craft_phase_from_snapshot(errors, chained_wait_runner, "recipe_bandage_basic", 50, false, "confirm_queue", "multi-entry queue craft resume")
	_assert_runner_craft_phase_from_snapshot(errors, wait_runner, "recipe_bandage_basic", 1, false, "confirm_queue", "remaining queue craft runner")
	if not _pending_crafting_line(game_root).contains("正在制作 无"):
		errors.append("multi-entry queue should clear pending after wait continuation: %s" % _pending_crafting_line(game_root))
	if not _queue_line(game_root).contains("制作队列 空"):
		errors.append("multi-entry queue should consume remaining entry after pending completion: %s" % _queue_line(game_root))
	_assert_craft_queue_snapshot(errors, game_root, 0, 0, 0, false, "multi-entry cross-turn queue completed")
	_assert_queue_feedback(errors, game_root, "pending_completed", false, 1, 0, "multi-entry cross-turn queue completed")
	if _player_inventory_count(game_root, "1011") != 2:
		errors.append("multi-entry cross-turn queue should consume first and resumed second craft materials")
	if _player_inventory_count(game_root, "1006") != cross_turn_bandages_before + 51:
		errors.append("multi-entry cross-turn queue should add outputs from both queue entries")
	if _event_count(game_root, "recipe_crafted") < cross_turn_crafted_events_before + 51:
		errors.append("multi-entry cross-turn queue should emit recipe_crafted for all completed crafts")
	player.inventory["1011"] = 100
	player.ap = 0.5
	game_root.refresh_crafting_panel()
	var pending_result: Dictionary = game_root.craft_player_recipe("recipe_bandage_basic", 50)
	await process_frame
	if not bool(pending_result.get("success", false)) or str(pending_result.get("kind", "")) != "pending_crafting":
		errors.append("AP-short craft from UI should create pending crafting: %s" % pending_result)
	_assert_runner_craft_phase(errors, game_root, "recipe_bandage_basic", 50, true, "craft", "single pending craft")
	if not _pending_crafting_line(game_root).contains("正在制作 基础绷带 x50"):
		errors.append("crafting panel should show active pending craft: %s" % _pending_crafting_line(game_root))
	if not _pending_crafting_line(game_root).contains("%"):
		errors.append("crafting pending line should show progress percent")
	var pending_progress_bar := _pending_crafting_progress_bar(game_root)
	if pending_progress_bar == null:
		errors.append("crafting panel should expose pending crafting progress bar")
	elif not pending_progress_bar.visible or float(pending_progress_bar.value) <= 0.0 or float(pending_progress_bar.max_value) <= 0.0:
		errors.append("pending crafting progress bar should be visible with progress: value=%s max=%s visible=%s" % [
			str(pending_progress_bar.value),
			str(pending_progress_bar.max_value),
			str(pending_progress_bar.visible),
		])
	_assert_pending_crafting_snapshot(errors, game_root, "recipe_bandage_basic", 50, true, "active pending craft")
	var cancel_pending_button := _cancel_pending_crafting_button(game_root)
	if cancel_pending_button == null or cancel_pending_button.disabled:
		errors.append("crafting panel should expose enabled cancel pending crafting button")
	else:
		cancel_pending_button.pressed.emit()
		await process_frame
		_assert_crafting_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "CancelPendingCraftingButton", "button", "cancel_pending_crafting", {"recipe_id": "recipe_bandage_basic", "count": "50"}, "cancel pending crafting audio")
		if not _pending_crafting_line(game_root).contains("正在制作 无"):
			errors.append("cancelled pending crafting should clear pending line")
		var cancelled_progress_bar := _pending_crafting_progress_bar(game_root)
		if cancelled_progress_bar != null and cancelled_progress_bar.visible:
			errors.append("cancelled pending crafting should hide progress bar")
		_assert_pending_crafting_snapshot(errors, game_root, "", 0, false, "cancelled pending craft")
		_assert_pending_crafting_cancel_result(errors, game_root, "recipe_bandage_basic", 50, "crafting_ui", "cancelled pending craft")
		if _player_inventory_count(game_root, "1011") != 100:
			errors.append("cancelling pending crafting should not consume queued materials")
		if not _event_seen(game_root, "crafting_cancelled"):
			errors.append("cancelling pending crafting should emit crafting_cancelled")
		if not _feedback_text(game_root).contains("已取消正在制作"):
			errors.append("crafting panel should show pending cancellation feedback")
		if not _feedback_text(game_root).contains("基础绷带 x50") or not _feedback_text(game_root).contains("AP"):
			errors.append("crafting panel should show cancelled recipe and AP feedback: %s" % _feedback_text(game_root))
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


func _recipe_line(game_root: Node, recipe_id: String) -> String:
	var row: Node = game_root.crafting_panel.find_child("Recipe_%s" % recipe_id, true, false)
	if row == null:
		return ""
	var line: Node = row.get_node("Line")
	return str((line as Button).text) if line is Button else ""


func _recipe_line_has_icon(game_root: Node, recipe_id: String, expected_resource_path: String) -> bool:
	var row: Node = game_root.crafting_panel.find_child("Recipe_%s" % recipe_id, true, false)
	if row == null:
		return false
	var line: Button = row.get_node_or_null("Line") as Button
	return line != null and line.icon != null and str(line.get_meta("icon_resource_path", "")) == expected_resource_path


func _craft_button(game_root: Node, recipe_id: String) -> Button:
	var row: Node = game_root.crafting_panel.find_child("Recipe_%s" % recipe_id, true, false)
	if row == null:
		return null
	return row.get_node("CraftButton") as Button


func _craft_equipment_dialog_visible(game_root: Node) -> bool:
	var dialog: Node = game_root.crafting_panel.get_node_or_null("CraftEquipmentToolConfirmDialog")
	if dialog is ConfirmationDialog:
		return bool((dialog as ConfirmationDialog).visible)
	return false


func _confirm_craft_equipment_dialog(game_root: Node) -> void:
	var dialog: Node = game_root.crafting_panel.get_node_or_null("CraftEquipmentToolConfirmDialog")
	if dialog is ConfirmationDialog:
		(dialog as ConfirmationDialog).confirmed.emit()
		(dialog as ConfirmationDialog).hide()


func _assert_craft_equipment_modal_details(errors: Array[String], game_root: Node, expected_recipe_id: String, expected_count: int, expected_tool_id: String, expected_slot_id: String, context: String) -> void:
	var stack_snapshot: Dictionary = _dictionary_or_empty(game_root.modal_stack_snapshot()) if game_root.has_method("modal_stack_snapshot") else {}
	var top: Dictionary = _dictionary_or_empty(stack_snapshot.get("top", {}))
	if str(top.get("id", "")) != "craft_equipment_tool_confirm":
		errors.append("%s: craft equipment modal details require confirm top: %s" % [context, stack_snapshot])
		return
	if str(top.get("recipe_id", "")) != expected_recipe_id or int(top.get("count", 0)) != expected_count:
		errors.append("%s: craft equipment modal should expose recipe/count: %s" % [context, top])
	if str(top.get("owner_panel", "")) != "crafting":
		errors.append("%s: craft equipment modal should be owned by crafting panel: %s" % [context, top])
	var sources: Array = _array_or_empty(top.get("equipment_sources", []))
	if sources.is_empty():
		errors.append("%s: craft equipment modal should expose equipment source: %s" % [context, top])
		return
	var source: Dictionary = _dictionary_or_empty(sources[0])
	if str(source.get("item_id", "")) != expected_tool_id or str(source.get("slot_id", "")) != expected_slot_id:
		errors.append("%s: craft equipment source expected %s/%s, got %s" % [context, expected_tool_id, expected_slot_id, source])
	if not bool(top.get("confirm_button_mouse_blocks_world", false)) or not bool(top.get("cancel_button_mouse_blocks_world", false)):
		errors.append("%s: craft equipment modal buttons should stop world mouse input: %s" % [context, top])


func _queue_button(game_root: Node, recipe_id: String) -> Button:
	var row: Node = game_root.crafting_panel.find_child("Recipe_%s" % recipe_id, true, false)
	if row == null:
		return null
	return row.get_node("QueueButton") as Button


func _queue_line(game_root: Node) -> String:
	var label: Label = game_root.crafting_panel.find_child("CraftQueueLine", true, false) as Label
	if label == null:
		return ""
	return str(label.text)


func _queue_feedback_line(game_root: Node) -> String:
	var label: Label = game_root.crafting_panel.find_child("CraftQueueFeedbackLine", true, false) as Label
	if label == null:
		return ""
	return str(label.text)


func _assert_craft_queue_snapshot(errors: Array[String], game_root: Node, expected_entries: int, expected_total_count: int, expected_total_output: int, expected_confirm_enabled: bool, context: String) -> void:
	if not game_root.crafting_panel.has_method("craft_queue_snapshot"):
		errors.append("%s: crafting panel should expose craft_queue_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.crafting_panel.craft_queue_snapshot())
	if int(snapshot.get("entry_count", -1)) != expected_entries:
		errors.append("%s: queue entry count expected %d got %s" % [context, expected_entries, snapshot])
	if int(snapshot.get("total_count", -1)) != expected_total_count:
		errors.append("%s: queue total count expected %d got %s" % [context, expected_total_count, snapshot])
	if int(snapshot.get("total_output_count", -1)) != expected_total_output:
		errors.append("%s: queue total output expected %d got %s" % [context, expected_total_output, snapshot])
	if bool(snapshot.get("confirm_enabled", false)) != expected_confirm_enabled:
		errors.append("%s: queue confirm enabled expected %s got %s" % [context, str(expected_confirm_enabled), snapshot])
	if expected_entries > 0:
		var entries: Array = _array_or_empty(snapshot.get("entries", []))
		var first: Dictionary = _dictionary_or_empty(entries[0] if not entries.is_empty() else {})
		if str(first.get("recipe_id", "")) != "recipe_bandage_basic":
			errors.append("%s: queue first recipe should be bandage: %s" % [context, first])
		if str(first.get("cancel_button_name", "")) != "CancelCraftQueueEntry_0" or not bool(first.get("cancellable", false)):
			errors.append("%s: queue entry should expose cancel metadata: %s" % [context, first])
		var outputs: Array = _array_or_empty(snapshot.get("outputs", []))
		var output_seen := false
		for output in outputs:
			var output_data: Dictionary = _dictionary_or_empty(output)
			if str(output_data.get("item_id", "")) == "1006" and int(output_data.get("count", 0)) == expected_total_output:
				output_seen = true
		if not output_seen:
			errors.append("%s: queue should aggregate bandage output: %s" % [context, outputs])


func _assert_queue_feedback(errors: Array[String], game_root: Node, expected_trigger: String, expected_pending: bool, expected_completed: int, expected_remaining_entries: int, context: String) -> void:
	if not game_root.crafting_panel.has_method("craft_queue_snapshot"):
		errors.append("%s: crafting panel should expose craft_queue_snapshot for queue feedback" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.crafting_panel.craft_queue_snapshot())
	var latest: Dictionary = _dictionary_or_empty(snapshot.get("latest_result", {}))
	if latest.is_empty():
		errors.append("%s: queue feedback latest_result should be present: %s" % [context, snapshot])
		return
	if str(latest.get("trigger", "")) != expected_trigger:
		errors.append("%s: queue feedback trigger expected %s got %s" % [context, expected_trigger, latest])
	if bool(latest.get("pending", false)) != expected_pending:
		errors.append("%s: queue feedback pending expected %s got %s" % [context, str(expected_pending), latest])
	if int(latest.get("completed_count", -1)) != expected_completed:
		errors.append("%s: queue feedback completed expected %d got %s" % [context, expected_completed, latest])
	if int(latest.get("remaining_queue_count", -1)) != expected_remaining_entries:
		errors.append("%s: queue feedback remaining entries expected %d got %s" % [context, expected_remaining_entries, latest])
	var feedback := _queue_feedback_line(game_root)
	if expected_pending and not feedback.contains("队列进行中"):
		errors.append("%s: queue feedback line should show in-progress state: %s" % [context, feedback])
	if not expected_pending and not feedback.contains("队列完成"):
		errors.append("%s: queue feedback line should show completed state: %s" % [context, feedback])


func _assert_app_craft_queue_snapshot(errors: Array[String], game_root: Node, expected_entries: int, expected_total_count: int, context: String) -> void:
	if not game_root.has_method("crafting_queue_snapshot"):
		errors.append("%s: game root should expose crafting_queue_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.crafting_queue_snapshot())
	if int(snapshot.get("entry_count", -1)) != expected_entries:
		errors.append("%s: app queue entry count expected %d got %s" % [context, expected_entries, snapshot])
	if int(snapshot.get("total_count", -1)) != expected_total_count:
		errors.append("%s: app queue total count expected %d got %s" % [context, expected_total_count, snapshot])


func _assert_pending_crafting_snapshot(errors: Array[String], game_root: Node, expected_recipe_id: String, expected_count: int, expected_active: bool, context: String) -> void:
	if not game_root.crafting_panel.has_method("craft_queue_snapshot"):
		errors.append("%s: crafting panel should expose craft_queue_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.crafting_panel.craft_queue_snapshot())
	var pending: Dictionary = _dictionary_or_empty(snapshot.get("pending", {}))
	if bool(pending.get("active", false)) != expected_active:
		errors.append("%s: pending active expected %s got %s" % [context, str(expected_active), pending])
	if bool(pending.get("progress_bar_visible", false)) != expected_active:
		errors.append("%s: pending progress bar visibility expected %s got %s" % [context, str(expected_active), pending])
	if not expected_active:
		if str(pending.get("progress_state", "")) != "inactive":
			errors.append("%s: inactive pending should expose inactive progress state: %s" % [context, pending])
		if bool(pending.get("progress_state_visible", false)):
			errors.append("%s: inactive pending progress state line should be hidden: %s" % [context, pending])
		if bool(pending.get("cancel_enabled", false)):
			errors.append("%s: inactive pending should not expose enabled cancel: %s" % [context, pending])
		if float(pending.get("progress_bar_value", 0.0)) != 0.0:
			errors.append("%s: inactive pending progress should reset: %s" % [context, pending])
		return
	if str(pending.get("recipe_id", "")) != expected_recipe_id:
		errors.append("%s: pending recipe expected %s got %s" % [context, expected_recipe_id, pending])
	if int(pending.get("count", 0)) != expected_count:
		errors.append("%s: pending count expected %d got %s" % [context, expected_count, pending])
	if float(pending.get("required_ap", 0.0)) <= 0.0:
		errors.append("%s: pending should expose required AP: %s" % [context, pending])
	if float(pending.get("progress_ratio", -1.0)) < 0.0 or float(pending.get("progress_ratio", 2.0)) > 1.0:
		errors.append("%s: pending progress ratio should be clamped: %s" % [context, pending])
	var progress_state := str(pending.get("progress_state", ""))
	if not ["starting", "in_progress", "nearly_done"].has(progress_state):
		errors.append("%s: active pending should expose progress state: %s" % [context, pending])
	if str(pending.get("progress_state_text", "")).is_empty() or not str(pending.get("progress_state_text", "")).contains("剩余"):
		errors.append("%s: active pending should expose localized progress state text: %s" % [context, pending])
	if not bool(pending.get("progress_state_visible", false)):
		errors.append("%s: active pending should show progress state line: %s" % [context, pending])
	if str(pending.get("progress_state_line", "")).is_empty() or not str(pending.get("progress_state_line", "")).contains("%"):
		errors.append("%s: active pending progress state line should include percent: %s" % [context, pending])
	if not bool(pending.get("cancel_enabled", false)):
		errors.append("%s: active pending should expose enabled cancel: %s" % [context, pending])
	if float(pending.get("progress_bar_value", 0.0)) <= 0.0 or float(pending.get("progress_bar_max", 0.0)) <= 0.0:
		errors.append("%s: active pending should expose progress bar values: %s" % [context, pending])
	if str(pending.get("progress_bar_color", "")).is_empty():
		errors.append("%s: active pending should expose progress bar color diagnostic: %s" % [context, pending])


func _assert_runner_craft_phase(errors: Array[String], game_root: Node, expected_recipe_id: String, expected_count: int, expected_pending: bool, expected_source: String, context: String) -> void:
	var runner: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("turn_action_runner", {}))
	_assert_runner_craft_phase_from_snapshot(errors, runner, expected_recipe_id, expected_count, expected_pending, expected_source, context)


func _assert_runner_craft_phase_from_snapshot(errors: Array[String], runner: Dictionary, expected_recipe_id: String, expected_count: int, expected_pending: bool, expected_source: String, context: String) -> void:
	var phase: Dictionary = _dictionary_or_empty(runner.get("craft_phase", {}))
	if phase.is_empty():
		errors.append("%s: turn action runner should expose craft_phase, got %s" % [context, JSON.stringify(runner)])
		return
	if str(phase.get("recipe_id", "")) != expected_recipe_id:
		errors.append("%s: craft_phase should expose recipe %s, got %s" % [context, expected_recipe_id, JSON.stringify(phase)])
	if int(phase.get("count", 0)) != expected_count:
		errors.append("%s: craft_phase should expose count %d, got %s" % [context, expected_count, JSON.stringify(phase)])
	if bool(phase.get("pending", false)) != expected_pending:
		errors.append("%s: craft_phase pending should be %s, got %s" % [context, str(expected_pending), JSON.stringify(phase)])
	if not expected_source.is_empty() and str(phase.get("source", "")) != expected_source:
		errors.append("%s: craft_phase should expose source %s, got %s" % [context, expected_source, JSON.stringify(phase)])
	if float(phase.get("required_ap", 0.0)) <= 0.0:
		errors.append("%s: craft_phase should expose required AP, got %s" % [context, JSON.stringify(phase)])
	if expected_pending and float(phase.get("remaining_ap", 0.0)) <= 0.0:
		errors.append("%s: pending craft_phase should expose remaining AP, got %s" % [context, JSON.stringify(phase)])
	if not expected_pending and not bool(phase.get("completed", false)):
		errors.append("%s: completed craft_phase should expose completed=true, got %s" % [context, JSON.stringify(phase)])


func _assert_runner_wait_phase(errors: Array[String], runner: Dictionary, expected_reason: String, context: String) -> void:
	var phase: Dictionary = _dictionary_or_empty(runner.get("wait_phase", {}))
	if phase.is_empty():
		errors.append("%s: turn action runner should expose wait_phase, got %s" % [context, JSON.stringify(runner)])
		return
	if str(phase.get("reason", "")) != expected_reason:
		errors.append("%s: wait_phase should expose reason %s, got %s" % [context, expected_reason, JSON.stringify(phase)])
	if not bool(phase.get("completed", false)):
		errors.append("%s: wait_phase should expose completed wait, got %s" % [context, JSON.stringify(phase)])
	if str(phase.get("pending_kind", "")) != "crafting":
		errors.append("%s: wait_phase should expose crafting pending kind, got %s" % [context, JSON.stringify(phase)])


func _assert_pending_crafting_cancel_result(errors: Array[String], game_root: Node, expected_recipe_id: String, expected_count: int, expected_reason: String, context: String) -> void:
	if not game_root.crafting_panel.has_method("craft_queue_snapshot"):
		errors.append("%s: crafting panel should expose craft_queue_snapshot for pending cancel result" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.crafting_panel.craft_queue_snapshot())
	var result: Dictionary = _dictionary_or_empty(snapshot.get("pending_result", {}))
	if result.is_empty():
		errors.append("%s: pending cancel result should be present: %s" % [context, snapshot])
		return
	if str(result.get("reason", "")) != "pending_cancelled":
		errors.append("%s: pending cancel reason should be pending_cancelled: %s" % [context, result])
	if str(result.get("cancel_reason", "")) != expected_reason:
		errors.append("%s: pending cancel origin expected %s got %s" % [context, expected_reason, result])
	if str(result.get("recipe_id", "")) != expected_recipe_id:
		errors.append("%s: pending cancel recipe expected %s got %s" % [context, expected_recipe_id, result])
	if int(result.get("count", 0)) != expected_count:
		errors.append("%s: pending cancel count expected %d got %s" % [context, expected_count, result])
	if float(result.get("required_ap", 0.0)) <= 0.0 or float(result.get("progress_ap", 0.0)) <= 0.0:
		errors.append("%s: pending cancel should expose AP progress: %s" % [context, result])
	if float(result.get("remaining_ap", -1.0)) < 0.0:
		errors.append("%s: pending cancel remaining AP should be non-negative: %s" % [context, result])
	if int(result.get("remaining_queue_count", -1)) != 0 or int(result.get("remaining_total_count", -1)) != 0:
		errors.append("%s: pending cancel should expose empty remaining queue: %s" % [context, result])
	var policy: Dictionary = _dictionary_or_empty(result.get("turn_policy", {}))
	if str(policy.get("action_kind", "")) != "cancel_pending":
		errors.append("%s: pending cancel should expose cancel turn policy: %s" % [context, result])
	var summary := str(result.get("summary", ""))
	if not summary.contains("基础绷带 x50") or not summary.contains("AP"):
		errors.append("%s: pending cancel summary should include recipe and AP: %s" % [context, result])


func _assert_station_permission_preview(errors: Array[String], game_root: Node, recipe_id: String, expected_success: bool, expected_reason: String, expected_blocker_id: String, context: String) -> void:
	var recipe: Dictionary = _recipe_snapshot(game_root, recipe_id)
	var preview: Dictionary = _dictionary_or_empty(recipe.get("station_permission_preview", {}))
	if preview.is_empty() or not bool(preview.get("active", false)):
		errors.append("%s: recipe should expose station permission preview: %s" % [context, recipe])
		return
	if bool(preview.get("success", false)) != expected_success:
		errors.append("%s: station permission success expected %s got %s" % [context, str(expected_success), preview])
	if expected_reason.is_empty():
		if not str(preview.get("reason", "")).is_empty():
			errors.append("%s: restored station permission should clear reason: %s" % [context, preview])
	else:
		if str(preview.get("reason", "")) != expected_reason:
			errors.append("%s: station permission reason expected %s got %s" % [context, expected_reason, preview])
		if not str(preview.get("text", "")).contains(expected_blocker_id):
			errors.append("%s: station permission text should include blocker: %s" % [context, preview])
		var blockers: Array = _array_or_empty(preview.get("blockers", []))
		var blocker_seen := false
		for blocker in blockers:
			var blocker_data: Dictionary = _dictionary_or_empty(blocker)
			if str(blocker_data.get("id", "")) == expected_blocker_id:
				blocker_seen = true
		if not blocker_seen:
			errors.append("%s: station permission blockers should include %s: %s" % [context, expected_blocker_id, preview])
	if not game_root.crafting_panel.has_method("craft_queue_snapshot"):
		errors.append("%s: crafting panel should expose craft_queue_snapshot for station preview" % context)
		return
	var panel_snapshot: Dictionary = _dictionary_or_empty(game_root.crafting_panel.craft_queue_snapshot())
	var panel_preview: Dictionary = _dictionary_or_empty(panel_snapshot.get("station_permission_preview", {}))
	if str(panel_preview.get("required_station", "")) != str(preview.get("required_station", "")):
		errors.append("%s: panel station preview should mirror selected recipe: %s" % [context, panel_snapshot])
	if bool(panel_preview.get("success", false)) != expected_success:
		errors.append("%s: panel station preview success expected %s got %s" % [context, str(expected_success), panel_preview])
	var detail := _detail_text(game_root)
	if not detail.contains(str(preview.get("text", ""))):
		errors.append("%s: detail text should include station permission preview: %s / %s" % [context, preview, detail])


func _assert_crafting_control_audio(errors: Array[String], game_root: Node, expected_event_kind: String, expected_sound_id: String, expected_control_name: String, expected_control_kind: String, expected_action: String, expected_payload: Dictionary, context: String) -> void:
	if not game_root.has_method("audio_feedback_snapshot"):
		errors.append("%s: game root should expose audio_feedback_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	var recent: Array = _array_or_empty(snapshot.get("recent_events", []))
	if recent.is_empty():
		errors.append("%s: audio snapshot should expose recent events: %s" % [context, snapshot])
		return
	var entry: Dictionary = {}
	for index in range(recent.size() - 1, -1, -1):
		var candidate: Dictionary = _dictionary_or_empty(recent[index])
		if str(candidate.get("audio_source", "")) != "ui" or str(candidate.get("panel_id", "")) != "crafting":
			continue
		if str(candidate.get("event_kind", "")) != expected_event_kind or str(candidate.get("sound_id", "")) != expected_sound_id:
			continue
		if str(candidate.get("control_name", "")) != expected_control_name:
			continue
		entry = candidate
		break
	if entry.is_empty():
		errors.append("%s: expected crafting audio %s/%s/%s, got %s" % [context, expected_event_kind, expected_sound_id, expected_control_name, snapshot])
		return
	if str(entry.get("control_kind", "")) != expected_control_kind:
		errors.append("%s: recent audio control kind expected %s, got %s" % [context, expected_control_kind, entry.get("control_kind", "")])
	if str(entry.get("action", "")) != expected_action:
		errors.append("%s: recent audio action expected %s, got %s" % [context, expected_action, entry.get("action", "")])
	for key in expected_payload.keys():
		if str(entry.get(key, "")) != str(expected_payload.get(key, "")):
			errors.append("%s: recent audio payload %s expected %s, got %s" % [context, key, expected_payload.get(key, ""), entry.get(key, "")])


func _confirm_queue_button(game_root: Node) -> Button:
	return game_root.crafting_panel.find_child("ConfirmCraftQueueButton", true, false) as Button


func _clear_queue_button(game_root: Node) -> Button:
	return game_root.crafting_panel.find_child("ClearCraftQueueButton", true, false) as Button


func _cancel_queue_entry_button(game_root: Node, index: int) -> Button:
	return game_root.crafting_panel.find_child("CancelCraftQueueEntry_%d" % index, true, false) as Button


func _pending_crafting_line(game_root: Node) -> String:
	var label: Label = game_root.crafting_panel.find_child("PendingCraftingLine", true, false) as Label
	return str(label.text) if label != null else ""


func _pending_crafting_progress_bar(game_root: Node) -> ProgressBar:
	return game_root.crafting_panel.find_child("PendingCraftingProgressBar", true, false) as ProgressBar


func _cancel_pending_crafting_button(game_root: Node) -> Button:
	return game_root.crafting_panel.find_child("CancelPendingCraftingButton", true, false) as Button


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


func _missing_reason_button(game_root: Node, node_name: String) -> Button:
	return game_root.crafting_panel.find_child(node_name, true, false) as Button


func _recipe_snapshot(game_root: Node, recipe_id: String) -> Dictionary:
	var snapshot: Dictionary = _crafting_snapshot(game_root)
	for recipe in snapshot.get("recipes", []):
		var recipe_data: Dictionary = recipe
		if str(recipe_data.get("recipe_id", "")) == recipe_id:
			return recipe_data
	return {"recipe_id": recipe_id, "name": recipe_id}


func _crafting_snapshot(game_root: Node) -> Dictionary:
	if game_root == null or game_root.crafting_panel == null:
		return {}
	return _dictionary_or_empty(game_root.crafting_panel.get("_last_snapshot"))


func _player_inventory_count(game_root: Node, item_id: String) -> int:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return int(actor_data.get("inventory", {}).get(item_id, 0))
	return 0


func _inventory_entry_count(entries: Array, item_id: String) -> int:
	var total := 0
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if str(entry_data.get("item_id", "")) == item_id:
			total += max(0, int(entry_data.get("count", 0)))
	return total


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
	var events: Array = _array_or_empty(game_root.simulation.snapshot().get("events", []))
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if str(event_data.get("kind", "")) == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


func _crafting_station_count(game_root: Node) -> int:
	var station_snapshot: Dictionary = _dictionary_or_empty(_crafting_snapshot(game_root).get("station_snapshot", {}))
	return int(station_snapshot.get("count", 0))


func _has_crafting_station(game_root: Node, station_id: String) -> bool:
	var station_snapshot: Dictionary = _dictionary_or_empty(_crafting_snapshot(game_root).get("station_snapshot", {}))
	return _dictionary_or_empty(station_snapshot.get("by_id", {})).has(station_id)


func _station_context_with_requirement(stations: Array, station_id: String, requirement: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for station in stations:
		var station_data: Dictionary = _dictionary_or_empty(station).duplicate(true)
		if str(station_data.get("station_id", "")) == station_id:
			for key in requirement.keys():
				station_data[key] = requirement.get(key)
		output.append(station_data)
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _wait_for_turn_action_runner_idle(game_root: Node, max_frames: int = 240) -> Dictionary:
	if game_root.has_method("drain_turn_action_runner"):
		var drained: Dictionary = _dictionary_or_empty(game_root.call("drain_turn_action_runner", max_frames))
		await process_frame
		return drained
	var runner: Dictionary = {}
	for _index in range(max_frames):
		var snapshot: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
		runner = _dictionary_or_empty(snapshot.get("turn_action_runner", {}))
		if not bool(runner.get("active", false)):
			return runner
		await process_frame
	await process_frame
	return _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("turn_action_runner", {}))


func _install_unlock_source_smoke_recipes(game_root: Node) -> void:
	var recipes: Dictionary = game_root.registry.get_library("recipes")
	recipes["smoke_skill_unlock_recipe"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_skill_unlock_recipe",
			"name": "技能解锁测试配方",
			"description": "需要生存技能等级的测试配方",
			"category": "weapon",
			"output": {"item_id": "1006", "count": 1},
			"materials": [{"item_id": 1144, "count": 99}],
			"required_tools": [],
			"required_station": "none",
			"skill_requirements": {},
			"craft_time": 0.0,
			"experience_reward": 0,
			"unlock_conditions": [{"type": "skill", "id": "survival", "level": 2}],
			"is_default_unlocked": false,
		},
	}
	recipes["smoke_quest_unlock_recipe"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_quest_unlock_recipe",
			"name": "任务解锁测试配方",
			"description": "需要完成任务的测试配方",
			"category": "weapon",
			"output": {"item_id": "1006", "count": 1},
			"materials": [{"item_id": 1144, "count": 99}],
			"required_tools": [],
			"required_station": "none",
			"skill_requirements": {},
			"craft_time": 0.0,
			"experience_reward": 0,
			"unlock_conditions": [{"type": "quest", "id": "tutorial_survive"}],
			"is_default_unlocked": false,
		},
	}
	recipes["smoke_item_unlock_recipe"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_item_unlock_recipe",
			"name": "物品解锁测试配方",
			"description": "需要持有物品的测试配方",
			"category": "weapon",
			"output": {"item_id": "1006", "count": 1},
			"materials": [{"item_id": 1144, "count": 99}],
			"required_tools": [],
			"required_station": "none",
			"skill_requirements": {},
			"craft_time": 0.0,
			"experience_reward": 0,
			"unlock_conditions": [{"type": "item", "id": "1104", "count": 1}],
			"is_default_unlocked": false,
		},
	}
	recipes["smoke_book_unlock_recipe"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_book_unlock_recipe",
			"name": "书籍解锁测试配方",
			"description": "需要读物或蓝图物品的测试配方",
			"category": "weapon",
			"output": {"item_id": "1006", "count": 1},
			"materials": [{"item_id": 1144, "count": 99}],
			"required_tools": [],
			"required_station": "none",
			"skill_requirements": {},
			"craft_time": 0.0,
			"experience_reward": 0,
			"unlock_conditions": [{"type": "book", "id": "1031"}],
			"is_default_unlocked": false,
		},
	}
	recipes["smoke_world_flag_unlock_recipe"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_world_flag_unlock_recipe",
			"name": "世界状态解锁测试配方",
			"description": "需要世界状态 flag 的测试配方",
			"category": "weapon",
			"output": {"item_id": "1006", "count": 1},
			"materials": [{"item_id": 1144, "count": 99}],
			"required_tools": [],
			"required_station": "none",
			"skill_requirements": {},
			"craft_time": 0.0,
			"experience_reward": 0,
			"unlock_conditions": [{"type": "world_flag", "id": "outpost_workshop_restored"}],
			"is_default_unlocked": false,
		},
	}
	recipes["smoke_consumes_tool_recipe"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_consumes_tool_recipe",
			"name": "消耗工具测试配方",
			"description": "制作时会消耗背包中的工具",
			"category": "tool",
			"output": {"item_id": "1006", "count": 1},
			"materials": [{"item_id": "1011", "count": 1}],
			"required_tools": [{"item_id": "1151", "consume_on_craft": true, "consume_count": 1}],
			"required_station": "none",
			"skill_requirements": {},
			"craft_time": 0.0,
			"experience_reward": 0,
			"unlock_conditions": [],
			"is_default_unlocked": true,
		},
	}
	recipes["smoke_durable_tool_recipe"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_durable_tool_recipe",
			"name": "耐久工具测试配方",
			"description": "制作时会扣减工具耐久",
			"category": "tool",
			"output": {"item_id": "1006", "count": 1},
			"materials": [{"item_id": "1011", "count": 2}],
			"required_tools": [{"item_id": "1151", "durability_cost": 3.0}],
			"required_station": "none",
			"skill_requirements": {},
			"craft_time": 0.0,
			"experience_reward": 0,
			"unlock_conditions": [],
			"is_default_unlocked": true,
		},
	}
