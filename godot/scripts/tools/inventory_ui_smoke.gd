extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
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
	if not _summary_line(game_root).contains("/60.0 kg"):
		errors.append("initial inventory summary should include carry capacity")
	var player_ref: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	var initial_capacity_snapshot: Dictionary = _inventory_snapshot(game_root)
	var initial_attributes: Dictionary = player_ref.combat_attributes.duplicate(true)
	var item_limit: int = int(initial_capacity_snapshot.get("current_item_count", initial_capacity_snapshot.get("item_count", 0)))
	var stack_limit: int = int(initial_capacity_snapshot.get("current_stack_count", 0))
	player_ref.combat_attributes["max_inventory_items"] = item_limit
	player_ref.combat_attributes["max_inventory_stacks"] = stack_limit
	game_root.refresh_inventory_panel()
	if not _summary_line(game_root).contains("种类 %d/%d" % [item_limit, item_limit]):
		errors.append("inventory summary should expose item capacity preview: %s" % _summary_line(game_root))
	if not _summary_line(game_root).contains("槽位 %d/%d" % [stack_limit, stack_limit]):
		errors.append("inventory summary should expose stack capacity preview: %s" % _summary_line(game_root))
	player_ref.combat_attributes = initial_attributes.duplicate(true)
	game_root.refresh_inventory_panel()
	_install_deconstruct_requirement_smoke_item(game_root)
	var initial_text: String = "\n".join(_item_lines(game_root))
	if not initial_text.contains("手枪弹药 x10"):
		errors.append("initial inventory missing bootstrap ammo")
	var ammo_snapshot := _inventory_snapshot_item(game_root, "1009")
	var ammo_icon := _dictionary_or_empty(ammo_snapshot.get("icon_asset", {}))
	if not bool(ammo_icon.get("ok", false)) or not bool(ammo_icon.get("exists", false)):
		errors.append("inventory item snapshot should expose existing Godot icon asset: %s" % ammo_icon)
	if str(ammo_icon.get("resource_path", "")) != "res://assets/icons/ammo/ammo_pistol.svg":
		errors.append("inventory item snapshot should expose migrated ammo icon resource path: %s" % ammo_icon)
	if str(ammo_icon.get("fallback_key", "")) != "ammo":
		errors.append("inventory item snapshot should expose ammo icon fallback key: %s" % ammo_icon)
	var ammo_thumbnail := _dictionary_or_empty(ammo_snapshot.get("thumbnail_asset", {}))
	if str(ammo_thumbnail.get("resource_path", "")) != "res://assets/icons/ammo/ammo_pistol.svg" or str(ammo_thumbnail.get("thumbnail_domain", "")) != "item":
		errors.append("inventory item snapshot should expose thumbnail asset from migrated icon: %s" % ammo_thumbnail)
	var ammo_button: Button = game_root.inventory_panel.find_child("Item_1009", true, false) as Button
	if ammo_button == null:
		errors.append("inventory panel should render ammo item row")
	elif ammo_button.icon == null or str(ammo_button.get_meta("icon_resource_path", "")) != "res://assets/icons/ammo/ammo_pistol.svg":
		errors.append("inventory item row should render migrated ammo icon: %s" % str(ammo_button.get_meta("icon_resource_path", "")))
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
	player_ref.hp = 50.0
	player_ref.ap = 6.0
	player_ref.inventory["1006"] = 2
	game_root.refresh_inventory_panel()
	if not _press_inventory_item_with_text(game_root, "绷带"):
		errors.append("should select bandage row before using item")
	await process_frame
	_assert_inventory_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "Item_1006", "item_row", "select_item", {"item_id": "1006", "count": "2"}, "bandage row select audio")
	var use_button: Button = _use_button(game_root)
	if use_button == null or use_button.disabled:
		errors.append("selected consumable should enable use button")
	if not _open_inventory_context_menu(game_root, "绷带"):
		errors.append("should open context menu for bandage")
	else:
		_assert_inventory_context_menu(errors, game_root, "1006", "bandage context menu")
	if not _open_inventory_context_menu(game_root, "绷带"):
		errors.append("should reopen context menu for bandage")
	elif _context_action_disabled(game_root, 1):
		errors.append("context menu should enable use for consumable")
	else:
		var hp_before_inspect: float = player_ref.hp
		var ap_before_inspect: float = player_ref.ap
		var count_before_inspect: int = _player_inventory_count(game_root, "1006")
		if _context_action_disabled(game_root, 4):
			errors.append("context menu should enable inspect for inventory item")
		else:
			_execute_inventory_context_action(game_root, 4)
			await process_frame
			if not _detail_line(game_root).begins_with("检查：绷带"):
				errors.append("inspect context action should update item detail")
			if absf(player_ref.hp - hp_before_inspect) > 0.01:
				errors.append("inspect context action should not change hp")
			if absf(player_ref.ap - ap_before_inspect) > 0.01:
				errors.append("inspect context action should not spend AP")
			if _player_inventory_count(game_root, "1006") != count_before_inspect:
				errors.append("inspect context action should not mutate inventory")
			if not _open_inventory_context_menu(game_root, "绷带"):
				errors.append("should reopen context menu for bandage after inspect")
		if _context_action_disabled(game_root, 5):
			errors.append("usable item context menu should enable add-to-hotbar")
		else:
			var hotbar_hp_before: float = player_ref.hp
			var hotbar_ap_before: float = player_ref.ap
			var hotbar_count_before: int = _player_inventory_count(game_root, "1006")
			_execute_inventory_context_action(game_root, 5)
			await process_frame
			if not _hud_hotbar_slot_text(game_root, "slot_1").contains("绷带"):
				errors.append("adding bandage to hotbar should show item in HUD slot 1")
			if not _hud_hotbar_slot_text(game_root, "slot_1").contains("x2"):
				errors.append("item hotbar slot should show available item count")
			if not _hud_hotbar_slot_tooltip(game_root, "slot_1").contains("物品"):
				errors.append("item hotbar slot should expose item tooltip")
			if not _hud_hotbar_slot_tooltip(game_root, "slot_1").contains("AP 2"):
				errors.append("item hotbar slot tooltip should show item AP cost")
			if not _hud_hotbar_slot_tooltip(game_root, "slot_1").contains("HP +25"):
				errors.append("item hotbar slot tooltip should show item resource effect")
			player_ref.ap = 1.0
			game_root.refresh_hud()
			if not _hud_hotbar_slot_disabled(game_root, "slot_1"):
				errors.append("item hotbar slot should disable when AP is insufficient")
			if not _hud_hotbar_slot_tooltip(game_root, "slot_1").contains("AP不足"):
				errors.append("item hotbar slot tooltip should show AP-insufficient state")
			player_ref.ap = hotbar_ap_before
			game_root.refresh_hud()
			var hotbar_use: Dictionary = game_root.use_hotbar_slot("slot_1")
			await process_frame
			if not bool(hotbar_use.get("success", false)):
				errors.append("using bandage hotbar item should succeed: %s" % hotbar_use.get("reason", "unknown"))
			if absf(player_ref.hp - minf(player_ref.max_hp, hotbar_hp_before + 25.0)) > 0.01:
				errors.append("using bandage hotbar item should restore hp")
			if absf(player_ref.ap - (hotbar_ap_before - 2.0)) > 0.01:
				errors.append("using bandage hotbar item should spend item AP cost")
			if _player_inventory_count(game_root, "1006") != hotbar_count_before - 1:
				errors.append("using bandage hotbar item should consume one item")
			player_ref.inventory["1006"] = 0
			game_root.refresh_hud()
			if not _hud_hotbar_slot_disabled(game_root, "slot_1"):
				errors.append("item hotbar slot should disable when no items remain")
			if not _hud_hotbar_slot_tooltip(game_root, "slot_1").contains("数量不足"):
				errors.append("item hotbar slot tooltip should show not-enough-items state")
			player_ref.hp = 50.0
			player_ref.ap = 6.0
			player_ref.inventory["1006"] = 2
			game_root.refresh_inventory_panel()
			game_root.refresh_hud()
			if not _open_inventory_context_menu(game_root, "绷带"):
				errors.append("should reopen context menu for bandage after hotbar use")
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
		if not _inventory_feedback_line(game_root).contains("已使用 绷带") or not _inventory_feedback_line(game_root).contains("HP +25") or not _inventory_feedback_line(game_root).contains("AP 剩余 4"):
			errors.append("using bandage should show inventory feedback with effect and AP")
	var ap_before_invalid_use: float = player_ref.ap
	var invalid_use: Dictionary = game_root.use_player_item("1003")
	if str(invalid_use.get("reason", "")) != "item_not_usable":
		errors.append("using a non-usable weapon should report item_not_usable")
	if absf(player_ref.ap - ap_before_invalid_use) > 0.01:
		errors.append("failed item use should not spend AP")
	if not _inventory_feedback_line(game_root).contains("不能使用"):
		errors.append("failed item use should show inventory feedback")
	game_root.active_inventory_feedback = {
		"type": "error",
		"reason": "item_not_droppable",
		"item_id": "1003",
		"count": 1,
	}
	game_root.refresh_inventory_panel()
	if not _inventory_feedback_line(game_root).contains("物品不可丢弃"):
		errors.append("inventory feedback should use reason catalog fallback for unhandled reasons")
	game_root.active_inventory_feedback = {}
	game_root.refresh_inventory_panel()
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
	_assert_inventory_action_drag_hover_target(errors, game_root, _inventory_drag_data(game_root, "罐头食品"), quest_drop_button, false, "item_not_droppable", "quest food drop button reject hover target")
	_assert_inventory_action_hover_render(errors, game_root, _inventory_drag_data(game_root, "罐头食品"), _drop_zone(game_root), false, "item_not_droppable", "quest food drop zone reject hover render")
	_assert_inventory_action_drag_hover_target(errors, game_root, _inventory_drag_data(game_root, "罐头食品"), _equip_button(game_root), false, "item_not_equippable", "quest food equip button reject hover target")
	if not _open_inventory_context_menu(game_root, "罐头食品"):
		errors.append("should open context menu for quest food item")
	else:
		if not _context_action_disabled(game_root, 1):
			errors.append("quest item context menu should disable use")
		if not _context_action_disabled(game_root, 3):
			errors.append("quest item context menu should disable drop")
		if not _context_action_disabled(game_root, 5):
			errors.append("quest item context menu should disable add-to-hotbar")
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
	player_ref.inventory["1010"] = 3
	if not player_ref.inventory_order.has("1010"):
		player_ref.inventory_order.append("1010")
	game_root.refresh_inventory_panel()
	if not _open_inventory_context_menu(game_root, "废金属"):
		errors.append("should open context menu for temporary scrap metal")
	elif _context_action_disabled(game_root, 7):
		errors.append("droppable item context menu should enable drop all")
	else:
		if _context_action_disabled(game_root, 8):
			errors.append("split context action should be enabled for stackable multi-count items")
		if not _context_action_tooltip(game_root, 8).contains("当前堆叠"):
			errors.append("split context action should explain current stack groups")
		var scrap_before_split: int = _player_inventory_count(game_root, "1010")
		var split_result: Dictionary = game_root.split_player_inventory_stack("1010", 1)
		if not bool(split_result.get("success", false)) or str(split_result.get("kind", "")) != "inventory_stack_split":
			errors.append("split stack should create a secondary inventory stack: %s" % split_result)
		if _player_inventory_count(game_root, "1010") != scrap_before_split:
			errors.append("split stack should preserve merged inventory count")
		game_root.refresh_inventory_panel()
		var split_snapshot: Dictionary = _inventory_snapshot_item(game_root, "1010")
		if int(split_snapshot.get("stack_count", 0)) != 2:
			errors.append("split stack snapshot should expose two stacks: %s" % split_snapshot)
		var split_stacks: Array = _array_or_empty(split_snapshot.get("stack_counts", []))
		if split_stacks.size() != 2 or int(split_stacks[0]) != 2 or int(split_stacks[1]) != 1:
			errors.append("split stack snapshot should expose 2/1 stack counts: %s" % split_snapshot)
		var stack_drop_result: Dictionary = game_root.drop_player_item("1010", 1)
		await process_frame
		if not bool(stack_drop_result.get("success", false)):
			errors.append("dropping from split stack should succeed: %s" % stack_drop_result)
		game_root.refresh_inventory_panel()
		var after_stack_drop: Dictionary = _inventory_snapshot_item(game_root, "1010")
		var after_drop_stacks: Array = _array_or_empty(after_stack_drop.get("stack_counts", []))
		if after_drop_stacks.size() != 1 or int(after_drop_stacks[0]) != 2:
			errors.append("stack-aware removal should consume the newest split stack first: %s" % after_stack_drop)
		InventoryEntries.new().add_actor_item(player_ref, "1010", 2)
		game_root.refresh_inventory_panel()
		var after_stack_add: Dictionary = _inventory_snapshot_item(game_root, "1010")
		var after_add_stacks: Array = _array_or_empty(after_stack_add.get("stack_counts", []))
		if after_add_stacks.size() != 2 or int(after_add_stacks[0]) != 2 or int(after_add_stacks[1]) != 2:
			errors.append("stack-aware add should append a new stack instead of collapsing existing stacks: %s" % after_stack_add)
		player_ref.inventory.erase("1005")
		player_ref.inventory_order.erase("1005")
		player_ref.inventory_stacks.erase("1005")
		InventoryEntries.new().add_actor_item(player_ref, "1005", 25, game_root.registry.get_library("items"))
		game_root.refresh_inventory_panel()
		var max_stack_snapshot: Dictionary = _inventory_snapshot_item(game_root, "1005")
		var max_stack_counts: Array = _array_or_empty(max_stack_snapshot.get("stack_counts", []))
		if _player_inventory_count(game_root, "1005") != 25:
			errors.append("max-stack add should preserve total item count")
		if int(max_stack_snapshot.get("max_stack", 0)) != 10:
			errors.append("max-stack snapshot should expose item stack limit: %s" % max_stack_snapshot)
		if max_stack_counts.size() != 3 or int(max_stack_counts[0]) != 10 or int(max_stack_counts[1]) != 10 or int(max_stack_counts[2]) != 5:
			errors.append("max-stack add should split gained items by item max_stack: %s" % max_stack_snapshot)
		player_ref.inventory["1005"] = 9
		player_ref.inventory_stacks["1005"] = [9]
		InventoryEntries.new().add_actor_item(player_ref, "1005", 3, game_root.registry.get_library("items"))
		game_root.refresh_inventory_panel()
		var after_fill_snapshot: Dictionary = _inventory_snapshot_item(game_root, "1005")
		var after_fill_stacks: Array = _array_or_empty(after_fill_snapshot.get("stack_counts", []))
		if after_fill_stacks.size() != 2 or int(after_fill_stacks[0]) != 10 or int(after_fill_stacks[1]) != 2:
			errors.append("max-stack add should fill existing partial stack before appending: %s" % after_fill_snapshot)
		player_ref.inventory.erase("1005")
		player_ref.inventory_order.erase("1005")
		player_ref.inventory_stacks.erase("1005")
		game_root.refresh_inventory_panel()
		player_ref.inventory["1010"] = 5
		player_ref.inventory_stacks["1010"] = [2, 3]
		game_root.refresh_inventory_panel()
		if not _open_inventory_context_menu(game_root, "废金属"):
			errors.append("should reopen context menu for stack-source split")
			return errors
		if _context_action_disabled(game_root, 100):
			errors.append("specific stack split should enable first split source")
		if _context_action_disabled(game_root, 101):
			errors.append("specific stack split should enable second split source")
		if not _context_action_label(game_root, 101).contains("拆分第 2 堆"):
			errors.append("specific stack split should expose second source label")
		if not _context_action_tooltip(game_root, 101).contains("该堆当前 3 个"):
			errors.append("specific stack split should explain selected source stack")
		_execute_inventory_context_action(game_root, 101)
		await process_frame
		game_root.refresh_inventory_panel()
		var after_source_split: Dictionary = _inventory_snapshot_item(game_root, "1010")
		var source_split_stacks: Array = _array_or_empty(after_source_split.get("stack_counts", []))
		if source_split_stacks.size() != 3 or int(source_split_stacks[0]) != 2 or int(source_split_stacks[1]) != 2 or int(source_split_stacks[2]) != 1:
			errors.append("specific stack split should consume selected source stack: %s" % after_source_split)
		if not _open_inventory_context_menu(game_root, "废金属"):
			errors.append("should reopen context menu for temporary scrap metal after stack mutations")
			return errors
		_execute_inventory_context_action(game_root, 7)
		await process_frame
		if not _discard_dialog_visible(game_root):
			errors.append("drop all context action should open discard confirmation dialog")
		var drop_all_quantity_input: LineEdit = _discard_quantity_input(game_root)
		if drop_all_quantity_input == null:
			errors.append("drop all discard modal should expose quantity input")
		elif drop_all_quantity_input.text != "5":
			errors.append("drop all discard modal should start from full stack count")
		_confirm_discard_dialog(game_root)
		await process_frame
		if _player_inventory_count(game_root, "1010") != 0:
			errors.append("drop all context action should remove the whole stack")
		if not _event_seen(game_root, "inventory_item_dropped"):
			errors.append("drop all context action should emit inventory_item_dropped")
	if _filter_button(game_root, "FilterEquipmentButton") == null:
		errors.append("inventory panel should expose equipment filter")
	else:
		_filter_button(game_root, "FilterEquipmentButton").pressed.emit()
		await process_frame
		_assert_inventory_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "FilterEquipmentButton", "filter_button", "filter_category", {"filter_id": "equipment"}, "equipment filter audio")
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
		_assert_inventory_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "FilterAmmoButton", "filter_button", "filter_category", {"filter_id": "ammo"}, "ammo filter audio")
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
		_assert_inventory_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "FilterAllButton", "filter_button", "filter_category", {"filter_id": "all"}, "all filter audio")
		if not "\n".join(_item_lines(game_root)).contains("棒球棒 x1"):
			errors.append("all filter should restore inventory rows")
	if _sort_button(game_root, "SortValueButton") == null:
		errors.append("inventory panel should expose value sort")
	else:
		_sort_button(game_root, "SortValueButton").pressed.emit()
		await process_frame
		_assert_inventory_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "SortValueButton", "sort_button", "sort_mode", {"sort_id": "value"}, "value sort audio")
		if not _text_ordered("\n".join(_item_lines(game_root)), "棒球棒 x1", "手枪弹药 x10"):
			errors.append("value sort should place higher value item before ammo")
	if not _press_inventory_item_with_text(game_root, "手枪弹药"):
		errors.append("should select ammo row for detail")
	await process_frame
	_assert_inventory_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "Item_1009", "item_row", "select_item", {"item_id": "1009", "count": "10"}, "ammo row select audio")
	if not _detail_line(game_root).contains("弹药") or not _detail_line(game_root).contains("总价 50"):
		errors.append("inventory detail should show selected item category and value")
	player_ref.inventory["smoke_non_deconstructable_ui_item"] = 1
	game_root.refresh_inventory_panel()
	if not _press_inventory_item_with_text(game_root, "不可拆解UI测试物品"):
		errors.append("should select non-deconstructable UI smoke item")
	if not _detail_line(game_root).contains("拆解不可用 没有拆解产物"):
		errors.append("inventory detail should explain why item cannot be deconstructed")
	if not _open_inventory_context_menu(game_root, "不可拆解UI测试物品"):
		errors.append("should open context menu for non-deconstructable smoke item")
	elif not _context_action_disabled(game_root, 6):
		errors.append("context menu should disable deconstruct for non-deconstructable smoke item")
	elif not _context_action_tooltip(game_root, 6).contains("没有拆解产物"):
		errors.append("disabled deconstruct context action should explain missing yield")
	player_ref.inventory.erase("smoke_non_deconstructable_ui_item")
	game_root.refresh_inventory_panel()
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
	if not _open_inventory_context_menu(game_root, "水瓶"):
		errors.append("should open context menu for deconstructable water bottle")
	elif _context_action_disabled(game_root, 6):
		errors.append("context menu should enable deconstruct for water bottle")
	else:
		var bottle_count_before: int = _player_inventory_count(game_root, "1008")
		var scrap_count_before: int = _player_inventory_count(game_root, "1104")
		_execute_inventory_context_action(game_root, 6)
		await process_frame
		if _player_inventory_count(game_root, "1008") != bottle_count_before - 1:
			errors.append("deconstructing water bottle from context should consume one bottle")
		if _player_inventory_count(game_root, "1104") != scrap_count_before + 1:
			errors.append("deconstructing water bottle from context should add plastic scrap")
		if not _event_seen(game_root, "item_deconstructed"):
			errors.append("deconstructing from inventory context should emit item_deconstructed")
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
	else:
		_assert_drag_state_snapshot(errors, game_root, _inventory_drag_data(game_root, "棒球棒"), equip_button, "inventory_item", "inventory", "inventory_action", "drop baseball bat on equip button")
		_assert_inventory_action_drag_hover_target(errors, game_root, _inventory_drag_data(game_root, "棒球棒"), equip_button, true, "", "baseball bat equip action hover target")
		_assert_inventory_action_hover_render(errors, game_root, _inventory_drag_data(game_root, "棒球棒"), equip_button, true, "", "baseball bat equip action hover render")
	if equip_button == null or equip_button.disabled:
		pass
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
	if not _summary_line(game_root).contains("kg"):
		errors.append("inventory summary did not update total weight after deconstructing water bottle")
	if not _summary_line(game_root).contains("/60.0 kg"):
		errors.append("inventory summary should keep carry capacity after inventory changes")
	player_ref.inventory["smoke_deconstruct_tool_item"] = 1
	player_ref.inventory["1151"] = 1
	game_root.refresh_inventory_panel()
	if not _press_inventory_item_with_text(game_root, "拆解要求测试物品"):
		errors.append("should select deconstruct requirement smoke item")
	if not _detail_line(game_root).contains("拆解要求 工具 螺丝刀(消耗 1) / 工作台 smoke_station"):
		errors.append("inventory detail should show deconstruct tool consumption and station requirements")
	if not _detail_line(game_root).contains("拆解产物 塑料 x1"):
		errors.append("inventory detail should show deconstruct yield preview")
	if not _detail_line(game_root).contains("拆解不可用 需要工作台 smoke_station"):
		errors.append("inventory detail should explain missing deconstruct station")
	if not _open_inventory_context_menu(game_root, "拆解要求测试物品"):
		errors.append("should open context menu for station-gated deconstruct item")
	elif not _context_action_tooltip(game_root, 6).contains("需要工作台 smoke_station"):
		errors.append("deconstruct context tooltip should preview missing station requirement")
	var gated_item_snapshot: Dictionary = _inventory_snapshot_item(game_root, "smoke_deconstruct_tool_item")
	var gated_requirements: Dictionary = _dictionary_or_empty(gated_item_snapshot.get("deconstruct_requirements", {}))
	var gated_tools: Array = _array_or_empty(gated_requirements.get("required_tools", []))
	if gated_tools.is_empty() or not bool(_dictionary_or_empty(gated_tools[0]).get("consume_on_deconstruct", false)):
		errors.append("inventory snapshot should expose deconstruct consumable tool requirement")
	var gated_preview: Dictionary = _dictionary_or_empty(gated_item_snapshot.get("deconstruct_preview", {}))
	var gated_preview_entries: Array = _array_or_empty(gated_preview.get("entries", []))
	if gated_preview_entries.is_empty():
		errors.append("inventory snapshot should expose deconstruct preview entries")
	else:
		var first_preview: Dictionary = _dictionary_or_empty(gated_preview_entries[0])
		if str(first_preview.get("name", "")) != "塑料" or int(first_preview.get("total_count", 0)) != 1:
			errors.append("deconstruct preview should include localized yield name and total count")
	_assert_deconstruct_preview_snapshot(errors, game_root, "smoke_deconstruct_tool_item", "塑料", 1, "gated deconstruct preview")
	if game_root.has_method("finish_world_action_presentations"):
		game_root.finish_world_action_presentations()
		await process_frame
	var gated_deconstruct_result: Dictionary = game_root.deconstruct_player_item("smoke_deconstruct_tool_item", 1)
	await process_frame
	if str(gated_deconstruct_result.get("reason", "")) != "missing_station":
		errors.append("deconstructing requirement-gated item away from station should report missing_station")
	if not _inventory_feedback_line(game_root).contains("缺少拆解工作台 smoke_station"):
		errors.append("inventory feedback should localize missing deconstruct station")
	if _player_inventory_count(game_root, "smoke_deconstruct_tool_item") != 1:
		errors.append("failed station-gated deconstruct should not consume source item")
	player_ref.inventory.erase("1151")
	player_ref.equipment["tool"] = "1151"
	game_root.refresh_inventory_panel()
	if game_root.has_method("finish_world_action_presentations"):
		game_root.finish_world_action_presentations()
		await process_frame
	var missing_consumable_tool_result: Dictionary = game_root.deconstruct_player_item("smoke_deconstruct_tool_item", 1)
	await process_frame
	if str(missing_consumable_tool_result.get("reason", "")) != "missing_station":
		errors.append("station-gated deconstruct with equipped consumable tool should still report missing_station")
	if not player_ref.equipment.has("tool"):
		errors.append("failed station-gated deconstruct should not consume equipped tool")
	player_ref.inventory.clear()
	player_ref.inventory_order.clear()
	player_ref.equipment.clear()
	player_ref.inventory["smoke_deconstruct_consumable_tool_ui_item"] = 1
	player_ref.equipment["tool"] = "1151"
	game_root.refresh_inventory_panel()
	if not _press_inventory_item_with_text(game_root, "消耗拆解工具UI测试物品"):
		errors.append("should select consumable deconstruct UI smoke item with equipped tool")
	if not _detail_line(game_root).contains("拆解工具来源 装备:tool x1"):
		errors.append("inventory detail should preview equipped deconstruct tool source")
	if not _open_inventory_context_menu(game_root, "消耗拆解工具UI测试物品"):
		errors.append("should open context menu for equipped consumable deconstruct")
	elif _context_action_disabled(game_root, 6):
		errors.append("context menu should enable equipped consumable deconstruct")
	else:
		_execute_inventory_context_action(game_root, 6)
		await process_frame
		if not _deconstruct_equipment_dialog_visible(game_root):
			errors.append("equipped consumable deconstruct should open equipment consumption confirmation")
		_assert_modal_stack(errors, game_root, "inventory_deconstruct_equipment_confirm", "inventory", "equipped deconstruct confirmation")
		_assert_deconstruct_equipment_modal_details(errors, game_root, "smoke_deconstruct_consumable_tool_ui_item", 1, "1151", "tool", "equipped deconstruct confirmation")
		var esc_deconstruct_result: Dictionary = game_root.close_active_ui("keyboard_escape")
		if str(esc_deconstruct_result.get("closed", "")) != "modal:inventory_deconstruct_equipment_confirm":
			errors.append("Esc should close equipped deconstruct confirmation before consuming equipment, got %s" % esc_deconstruct_result)
		if not player_ref.equipment.has("tool"):
			errors.append("Esc closing equipped deconstruct confirmation should keep equipped tool")
		if _player_inventory_count(game_root, "smoke_deconstruct_consumable_tool_ui_item") != 1:
			errors.append("Esc closing equipped deconstruct confirmation should keep source item")
	if not _open_inventory_context_menu(game_root, "消耗拆解工具UI测试物品"):
		errors.append("should reopen context menu for equipped consumable deconstruct")
	else:
		_execute_inventory_context_action(game_root, 6)
		await process_frame
		_confirm_deconstruct_equipment_dialog(game_root)
	await process_frame
	if player_ref.equipment.has("tool"):
		errors.append("successful equipped consumable deconstruct should remove equipment slot")
	if _player_inventory_count(game_root, "smoke_deconstruct_consumable_tool_ui_item") != 0:
		errors.append("confirmed equipped consumable deconstruct should consume source item")
	var equipped_event_payload: Dictionary = _last_event_payload(game_root, "item_deconstructed")
	var equipped_consumed_tools: Array = _array_or_empty(equipped_event_payload.get("consumed_tools", []))
	if equipped_consumed_tools.is_empty() or str(_dictionary_or_empty(equipped_consumed_tools[0]).get("source", "")) != "equipment":
		errors.append("equipped consumable deconstruct event should report equipment source: %s" % equipped_consumed_tools)
	player_ref.inventory.clear()
	player_ref.inventory_order.clear()
	player_ref.equipment.clear()
	player_ref.inventory["smoke_deconstruct_consumable_tool_ui_item"] = 1
	var nearby_tool_grid: Dictionary = player_ref.grid_position.to_dictionary()
	game_root.simulation.map_interaction_targets["smoke_deconstruct_tool_crate_ui"] = {
		"target_id": "smoke_deconstruct_tool_crate_ui",
		"target_type": "map_object",
		"display_name": "拆解工具箱",
		"kind": "container",
		"anchor": nearby_tool_grid,
		"cells": [nearby_tool_grid],
		"container_inventory": [{"item_id": "1151", "count": 1}],
	}
	game_root.refresh_inventory_panel()
	if not _press_inventory_item_with_text(game_root, "消耗拆解工具UI测试物品"):
		errors.append("should select consumable deconstruct UI smoke item with nearby container tool")
	if not _detail_line(game_root).contains("拆解工具来源 附近容器:拆解工具箱 x1"):
		errors.append("inventory detail should preview nearby container deconstruct tool source")
	var nearby_consumable_tool_result: Dictionary = game_root.deconstruct_player_item("smoke_deconstruct_consumable_tool_ui_item", 1)
	await process_frame
	if not bool(nearby_consumable_tool_result.get("success", false)):
		errors.append("deconstruct should consume nearby container tool: %s" % nearby_consumable_tool_result.get("reason", "unknown"))
	var nearby_tool_target: Dictionary = _dictionary_or_empty(game_root.simulation.map_interaction_targets.get("smoke_deconstruct_tool_crate_ui", {}))
	if _inventory_entry_count(_array_or_empty(nearby_tool_target.get("container_inventory", [])), "1151") != 0:
		errors.append("nearby consumable deconstruct should consume map target container tool")
	var nearby_consumed_tools: Array = _array_or_empty(nearby_consumable_tool_result.get("consumed_tools", []))
	var nearby_source_seen := false
	for consumed_tool in nearby_consumed_tools:
		var consumed_tool_data: Dictionary = _dictionary_or_empty(consumed_tool)
		if str(consumed_tool_data.get("source", "")) == "nearby_container" and str(consumed_tool_data.get("container_id", "")) == "smoke_deconstruct_tool_crate_ui":
			nearby_source_seen = true
	if not nearby_source_seen:
		errors.append("nearby consumable deconstruct should report container source: %s" % nearby_consumed_tools)
	game_root.simulation.map_interaction_targets.erase("smoke_deconstruct_tool_crate_ui")
	player_ref.equipment.clear()
	player_ref.inventory.clear()
	player_ref.inventory_order.clear()
	player_ref.tool_durability.clear()
	player_ref.inventory["smoke_deconstruct_durable_tool_item"] = 2
	player_ref.inventory["1151"] = 1
	player_ref.tool_durability["1151"] = 5.0
	game_root.refresh_inventory_panel()
	if not _press_inventory_item_with_text(game_root, "耐久拆解测试物品"):
		errors.append("should select durable deconstruct smoke item")
	if not _detail_line(game_root).contains("螺丝刀(耐久 5.0/-3.0)"):
		errors.append("inventory detail should show deconstruct tool durability requirement")
	var durable_deconstruct_result: Dictionary = game_root.deconstruct_player_item("smoke_deconstruct_durable_tool_item", 1)
	await process_frame
	if not bool(durable_deconstruct_result.get("success", false)):
		errors.append("durable deconstruct from inventory should succeed: %s" % durable_deconstruct_result.get("reason", "unknown"))
	if _player_inventory_count(game_root, "1151") != 1:
		errors.append("durable deconstruct should not consume whole tool item")
	if not is_equal_approx(float(player_ref.tool_durability.get("1151", 0.0)), 2.0):
		errors.append("durable deconstruct should reduce tool durability to 2.0")
	var low_durability_deconstruct: Dictionary = game_root.deconstruct_player_item("smoke_deconstruct_durable_tool_item", 1)
	await process_frame
	if str(low_durability_deconstruct.get("reason", "")) != "tool_durability_insufficient":
		errors.append("low durability deconstruct should report tool_durability_insufficient")
	if not _inventory_feedback_line(game_root).contains("拆解工具耐久不足"):
		errors.append("inventory feedback should localize deconstruct tool durability failure")
	if _player_inventory_count(game_root, "smoke_deconstruct_durable_tool_item") != 1:
		errors.append("failed low-durability deconstruct should keep source item")
	player_ref.inventory.clear()
	player_ref.inventory_order.clear()
	player_ref.inventory["1006"] = 3
	player_ref.tool_durability.clear()
	player_ref.equipment.clear()
	game_root.refresh_inventory_panel()
	if not _press_inventory_item_with_text(game_root, "绷带"):
		errors.append("should select bandages before dropping through inventory panel")
	await process_frame
	_assert_inventory_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "Item_1006", "item_row", "select_item", {"item_id": "1006", "count": "3"}, "drop bandage row select audio")
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
		_assert_inventory_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "DropSelectedButton", "button", "open_discard_confirm", {"item_id": "1006", "count": "2"}, "drop selected button audio")
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
		var blocker_name := str(game_root.gameplay_input_blocker_name())
		if blocker_name != "modal:inventory_discard_confirm":
			errors.append("discard confirmation blocker should be modal:inventory_discard_confirm, got %s" % blocker_name)
		_assert_modal_stack(errors, game_root, "inventory_discard_confirm", "inventory", "discard confirmation")
		_assert_discard_quantity_modal_details(errors, game_root, 2, 3, true, "", "discard confirmation")
		_assert_modal_menu_event(errors, game_root, "inventory_discard_confirm", "inventory", "discard confirmation menu event")
		if discard_quantity_input != null:
			discard_quantity_input.text = "0"
			_emit_discard_confirm(game_root)
			await process_frame
			if not _discard_dialog_visible(game_root):
				errors.append("invalid discard quantity should keep modal open")
			if not _discard_error_text(game_root).contains("大于 0"):
				errors.append("invalid discard quantity should show reason")
			_assert_discard_quantity_modal_details(errors, game_root, 0, 3, false, "大于 0", "invalid discard confirmation")
			if _player_inventory_count(game_root, "1006") != 3:
				errors.append("invalid discard quantity should not mutate inventory")
			_press_discard_quantity_button(game_root, "DiscardQuantityMaxButton")
			await process_frame
			_assert_inventory_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "DiscardQuantityMaxButton", "button", "max_discard_quantity", {"item_id": "1006", "count": "3"}, "discard max quantity audio")
			if discard_quantity_input.text != "3":
				errors.append("discard max button should use available inventory count")
			_assert_discard_quantity_modal_details(errors, game_root, 3, 3, true, "", "discard max quantity")
			_press_discard_quantity_button(game_root, "DiscardQuantityMinusButton")
			await process_frame
			_assert_inventory_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "DiscardQuantityMinusButton", "button", "decrease_discard_quantity", {"item_id": "1006", "count": "2"}, "discard minus quantity audio")
			if discard_quantity_input.text != "2":
				errors.append("discard minus button should decrease quantity")
			_press_discard_quantity_button(game_root, "DiscardQuantityPlusButton")
			await process_frame
			_assert_inventory_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "DiscardQuantityPlusButton", "button", "increase_discard_quantity", {"item_id": "1006", "count": "3"}, "discard plus quantity audio")
			if discard_quantity_input.text != "3":
				errors.append("discard plus button should increase quantity")
		var esc_discard_result: Dictionary = game_root.close_active_ui("keyboard_escape")
		if str(esc_discard_result.get("closed", "")) != "modal:inventory_discard_confirm":
			errors.append("Esc should close inventory discard modal before other UI, got %s" % esc_discard_result)
		if _discard_dialog_visible(game_root):
			errors.append("Esc should hide inventory discard modal")
		_assert_no_modal_menu_event(errors, game_root, "discard confirmation Esc close menu event clear")
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
	else:
		_assert_inventory_action_drag_hover_target(errors, game_root, _inventory_drag_data(game_root, "绷带"), _drop_zone(game_root), true, "", "bandage drop zone hover target")
		_assert_inventory_action_hover_render(errors, game_root, _inventory_drag_data(game_root, "绷带"), _drop_zone(game_root), true, "", "bandage drop zone hover render")
		if not _drag_inventory_item_to_drop_zone(game_root, "绷带"):
			errors.append("should drag bandages onto drop zone")
		else:
			await process_frame
			if not _discard_dialog_visible(game_root):
				errors.append("drop zone should open discard confirmation dialog")
			if _player_inventory_count(game_root, "1006") != 2:
				errors.append("drop zone confirmation should not mutate inventory before confirm")
			var drop_zone_close_result: Dictionary = game_root.close_active_ui("keyboard_escape")
			if str(drop_zone_close_result.get("closed", "")) != "modal:inventory_discard_confirm":
				errors.append("Esc should close drop zone discard modal")
			if _discard_dialog_visible(game_root):
				errors.append("drop zone Esc should hide discard modal")
			if _player_inventory_count(game_root, "1006") != 2:
				errors.append("drop zone Esc should keep inventory unchanged")
	if not _press_inventory_item_with_text(game_root, "绷带"):
		errors.append("should reselect bandages before drag dropping to button")
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
	var drop_container: Dictionary = _container_session(game_root.simulation.snapshot(), str(drop_payload.get("container_id", "")))
	if str(drop_container.get("container_type", "")) != "drop":
		errors.append("dropping inventory item should create container_type=drop session")
	if str(drop_container.get("container_origin", "")) != "inventory_drop":
		errors.append("dropping inventory item should create container_origin=inventory_drop session")
	var drop_node: Node = game_root.find_child("Corpse_%s" % drop_payload.get("container_id", ""), true, false)
	var drop_target: Dictionary = _dictionary_or_empty(drop_node.get_meta("interaction_target", {}) if drop_node != null else {})
	if str(drop_target.get("container_type", "")) != "drop":
		errors.append("world drop marker should expose drop container_type metadata")
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


func _container_session(snapshot: Dictionary, container_id: String) -> Dictionary:
	for entry in _array_or_empty(snapshot.get("container_sessions", [])):
		var session: Dictionary = _dictionary_or_empty(entry)
		if str(session.get("container_id", "")) == container_id:
			return session
	return {}


func _inventory_snapshot_item(game_root: Node, item_id: String) -> Dictionary:
	var snapshot: Dictionary = _inventory_snapshot(game_root)
	for item in _array_or_empty(snapshot.get("items", [])):
		var item_data: Dictionary = _dictionary_or_empty(item)
		if str(item_data.get("item_id", "")) == item_id:
			return item_data
	return {}


func _inventory_snapshot(game_root: Node) -> Dictionary:
	return _dictionary_or_empty(game_root.inventory_panel.get("_last_snapshot"))


func _assert_deconstruct_preview_snapshot(errors: Array[String], game_root: Node, expected_item_id: String, expected_output_name: String, expected_output_count: int, context: String) -> void:
	if not game_root.inventory_panel.has_method("deconstruct_preview_snapshot"):
		errors.append("%s: inventory panel should expose deconstruct_preview_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.inventory_panel.deconstruct_preview_snapshot())
	if not bool(snapshot.get("active", false)):
		errors.append("%s: deconstruct preview should be active: %s" % [context, snapshot])
		return
	if str(snapshot.get("item_id", "")) != expected_item_id:
		errors.append("%s: deconstruct preview item expected %s got %s" % [context, expected_item_id, snapshot])
	var entries: Array = _array_or_empty(snapshot.get("entries", []))
	if entries.is_empty():
		errors.append("%s: deconstruct preview should expose entries: %s" % [context, snapshot])
		return
	var first: Dictionary = _dictionary_or_empty(entries[0])
	if str(first.get("name", "")) != expected_output_name or int(first.get("total_count", 0)) != expected_output_count:
		errors.append("%s: deconstruct preview first entry expected %s x%d got %s" % [context, expected_output_name, expected_output_count, first])
	if not str(snapshot.get("summary", "")).contains("%s x%d" % [expected_output_name, expected_output_count]):
		errors.append("%s: deconstruct preview summary should include output: %s" % [context, snapshot])
	if not str(snapshot.get("detail_line_text", "")).contains("拆解产物 %s x%d" % [expected_output_name, expected_output_count]):
		errors.append("%s: deconstruct preview should mirror detail line: %s" % [context, snapshot])


func _install_deconstruct_requirement_smoke_item(game_root: Node) -> void:
	var items: Dictionary = game_root.registry.get_library("items")
	items["smoke_deconstruct_tool_item"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_deconstruct_tool_item",
			"name": "拆解要求测试物品",
			"description": "用于验证拆解工具和工作台要求",
			"value": 1,
			"weight": 0.1,
			"fragments": [{
				"kind": "crafting",
				"deconstruct_required_tools": [{"item_id": "1151", "consume_on_deconstruct": true, "consume_count": 1}],
				"deconstruct_required_station": "smoke_station",
				"deconstruct_yield": [{"item_id": "1104", "count": 1}],
			}],
		},
	}
	items["smoke_deconstruct_durable_tool_item"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_deconstruct_durable_tool_item",
			"name": "耐久拆解测试物品",
			"description": "用于验证拆解工具耐久消耗",
			"value": 1,
			"weight": 0.1,
			"fragments": [{
				"kind": "crafting",
				"deconstruct_required_tools": [{"item_id": "1151", "durability_cost": 3.0}],
				"deconstruct_yield": [{"item_id": "1104", "count": 1}],
			}],
		},
	}
	items["smoke_deconstruct_consumable_tool_ui_item"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_deconstruct_consumable_tool_ui_item",
			"name": "消耗拆解工具UI测试物品",
			"description": "用于验证拆解工具消耗来源",
			"value": 1,
			"weight": 0.1,
			"fragments": [{
				"kind": "crafting",
				"deconstruct_required_tools": [{"item_id": "1151", "consume_on_deconstruct": true, "consume_count": 1}],
				"deconstruct_yield": [{"item_id": "1104", "count": 1}],
			}],
		},
	}
	items["smoke_non_deconstructable_ui_item"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_non_deconstructable_ui_item",
			"name": "不可拆解UI测试物品",
			"description": "用于验证不可拆解原因展示",
			"value": 1,
			"weight": 0.1,
			"fragments": [{
				"kind": "crafting",
				"deconstruct_yield": [],
			}],
		},
	}


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


func _inventory_entry_count(entries: Array, item_id: String) -> int:
	var total := 0
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if str(entry_data.get("item_id", "")) == item_id:
			total += max(0, int(entry_data.get("count", 0)))
	return total


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


func _inventory_feedback_line(game_root: Node) -> String:
	var label: Label = game_root.inventory_panel.find_child("InventoryFeedbackLine", true, false) as Label
	return "" if label == null else str(label.text)


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


func _drop_zone(game_root: Node) -> Control:
	return game_root.inventory_panel.find_child("DropZone", true, false) as Control


func _quantity_spin(game_root: Node) -> SpinBox:
	return game_root.inventory_panel.find_child("QuantitySpin", true, false) as SpinBox


func _discard_dialog_visible(game_root: Node) -> bool:
	var dialog: Node = game_root.inventory_panel.get_node_or_null("DiscardConfirmDialog")
	if dialog is ConfirmationDialog:
		return bool((dialog as ConfirmationDialog).visible)
	return false


func _deconstruct_equipment_dialog_visible(game_root: Node) -> bool:
	var dialog: Node = game_root.inventory_panel.get_node_or_null("DeconstructEquipmentToolConfirmDialog")
	if dialog is ConfirmationDialog:
		return bool((dialog as ConfirmationDialog).visible)
	return false


func _confirm_discard_dialog(game_root: Node) -> void:
	var dialog: Node = game_root.inventory_panel.get_node_or_null("DiscardConfirmDialog")
	if dialog is ConfirmationDialog:
		(dialog as ConfirmationDialog).confirmed.emit()
		(dialog as ConfirmationDialog).hide()


func _confirm_deconstruct_equipment_dialog(game_root: Node) -> void:
	var dialog: Node = game_root.inventory_panel.get_node_or_null("DeconstructEquipmentToolConfirmDialog")
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


func _context_action_tooltip(game_root: Node, action_id: int) -> String:
	var menu: PopupMenu = game_root.inventory_panel.find_child("InventoryContextMenu", true, false) as PopupMenu
	if menu == null:
		return ""
	var index: int = menu.get_item_index(action_id)
	if index < 0:
		return ""
	return str(menu.get_item_tooltip(index))


func _context_action_label(game_root: Node, action_id: int) -> String:
	var menu: PopupMenu = game_root.inventory_panel.find_child("InventoryContextMenu", true, false) as PopupMenu
	if menu == null:
		return ""
	var index: int = menu.get_item_index(action_id)
	if index < 0:
		return ""
	return str(menu.get_item_text(index))


func _execute_inventory_context_action(game_root: Node, action_id: int) -> void:
	game_root.inventory_panel.call("_execute_context_action", action_id)


func _hud_hotbar_slot_text(game_root: Node, slot_id: String) -> String:
	var button: Button = game_root.hud.find_child("HotbarSlot_%s" % slot_id, true, false) as Button
	return "" if button == null else str(button.text)


func _hud_hotbar_slot_tooltip(game_root: Node, slot_id: String) -> String:
	var button: Button = game_root.hud.find_child("HotbarSlot_%s" % slot_id, true, false) as Button
	return "" if button == null else str(button.tooltip_text)


func _hud_hotbar_slot_disabled(game_root: Node, slot_id: String) -> bool:
	var button: Button = game_root.hud.find_child("HotbarSlot_%s" % slot_id, true, false) as Button
	return button == null or button.disabled


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


func _drag_inventory_item_to_drop_zone(game_root: Node, item_needle: String) -> bool:
	var source: Button = _inventory_item_button(game_root, item_needle)
	var target: Control = game_root.inventory_panel.find_child("DropZone", true, false) as Control
	if source == null or target == null or not source.has_meta("inventory_item"):
		return false
	game_root.inventory_panel.call("_drop_inventory_action_data", Vector2.ZERO, {
		"kind": "inventory_item",
		"item": source.get_meta("inventory_item"),
		"item_id": str(source.get_meta("inventory_item").get("item_id", "")),
		"from_index": int(source.get_meta("inventory_index", 0)),
	}, target)
	return true


func _inventory_drag_data(game_root: Node, item_needle: String) -> Dictionary:
	var source: Button = _inventory_item_button(game_root, item_needle)
	if source == null or not source.has_meta("inventory_item"):
		return {}
	var data: Variant = game_root.inventory_panel.call("_get_inventory_item_drag_data", Vector2.ZERO, source)
	return _dictionary_or_empty(data)


func _assert_drag_state_snapshot(errors: Array[String], game_root: Node, drag_data: Dictionary, target: Control, expected_kind: String, expected_source_owner: String, expected_target_kind: String, context: String) -> void:
	if drag_data.is_empty():
		errors.append("%s: drag data should be available" % context)
		return
	if not game_root.has_method("drag_state_snapshot"):
		errors.append("%s: game root should expose drag_state_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.drag_state_snapshot(drag_data, target))
	if not bool(snapshot.get("active", false)):
		errors.append("%s: drag snapshot should be active: %s" % [context, snapshot])
	if str(snapshot.get("kind", "")) != expected_kind:
		errors.append("%s: drag kind expected %s, got %s" % [context, expected_kind, snapshot])
	var source: Dictionary = _dictionary_or_empty(snapshot.get("source", {}))
	if str(source.get("owner_panel", "")) != expected_source_owner:
		errors.append("%s: source owner expected %s, got %s" % [context, expected_source_owner, snapshot])
	var target_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("target", {}))
	if str(target_snapshot.get("target_kind", "")) != expected_target_kind:
		errors.append("%s: target kind expected %s, got %s" % [context, expected_target_kind, snapshot])
	var preview: Dictionary = _dictionary_or_empty(snapshot.get("preview", {}))
	if not bool(preview.get("has_preview", false)) or str(preview.get("text", "")).is_empty():
		errors.append("%s: drag snapshot should expose preview text: %s" % [context, snapshot])
	_assert_drag_preview_diagnostics(errors, preview, context)
	var runtime_drag: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("drag", {}))
	if not runtime_drag.has("active") or not runtime_drag.has("target"):
		errors.append("%s: runtime control should expose drag state shape: %s" % [context, runtime_drag])


func _assert_inventory_action_drag_hover_target(errors: Array[String], game_root: Node, drag_data: Dictionary, target: Control, expected_accept: bool, expected_reject_reason: String, context: String) -> void:
	if target == null:
		errors.append("%s: inventory action target should exist" % context)
		return
	if drag_data.is_empty():
		errors.append("%s: drag data should be available" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.drag_state_snapshot(drag_data, target))
	var target_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("target", {}))
	if str(target_snapshot.get("target_kind", "")) != "inventory_action":
		errors.append("%s: target should be inventory_action: %s" % [context, snapshot])
	if str(target_snapshot.get("target_id", "")) != str(target.get_meta("inventory_action_target", "")):
		errors.append("%s: target id should match action meta: %s" % [context, target_snapshot])
	if str(target_snapshot.get("accepts", "")) != "inventory_item":
		errors.append("%s: inventory action should declare accepted drag kind: %s" % [context, target_snapshot])
	if bool(target_snapshot.get("last_accept", false)) != expected_accept:
		errors.append("%s: inventory action accept expected %s, got %s" % [context, expected_accept, target_snapshot])
	if str(target_snapshot.get("reject_reason", "")) != expected_reject_reason:
		errors.append("%s: inventory action reject reason expected %s, got %s" % [context, expected_reject_reason, target_snapshot])
	var highlight: Dictionary = _dictionary_or_empty(target_snapshot.get("hover_highlight", {}))
	_assert_drag_reject_reason_text(errors, target_snapshot, highlight, expected_reject_reason, context)
	var expected_style := "accept" if expected_accept else "reject"
	if not bool(highlight.get("active", false)) or str(highlight.get("style", "")) != expected_style:
		errors.append("%s: inventory action hover highlight should expose %s: %s" % [context, expected_style, highlight])


func _assert_inventory_action_hover_render(errors: Array[String], game_root: Node, drag_data: Dictionary, target: Control, expected_accept: bool, expected_reject_reason: String, context: String) -> void:
	if target == null:
		errors.append("%s: inventory action target should exist" % context)
		return
	if drag_data.is_empty():
		errors.append("%s: drag data should be available" % context)
		return
	var can_drop: bool = bool(game_root.inventory_panel.call("_can_drop_inventory_action_data", Vector2.ZERO, drag_data, target))
	if can_drop != expected_accept:
		errors.append("%s: inventory action can_drop expected %s, got %s" % [context, expected_accept, can_drop])
	if not bool(target.get_meta("inventory_action_drag_hovered", false)):
		errors.append("%s: inventory action target should record active hover render state" % context)
	if bool(target.get_meta("inventory_action_drag_last_accept", false)) != expected_accept:
		errors.append("%s: inventory action hover accept expected %s, got %s" % [context, expected_accept, target.get_meta("inventory_action_drag_last_accept", false)])
	if str(target.get_meta("inventory_action_drag_reject_reason", "")) != expected_reject_reason:
		errors.append("%s: inventory action hover reject reason expected %s, got %s" % [context, expected_reject_reason, target.get_meta("inventory_action_drag_reject_reason", "")])
	var expected_style := "accept" if expected_accept else "reject"
	var expected_color := "#4ecb71" if expected_accept else "#e25c5c"
	if str(target.get_meta("inventory_action_drag_highlight_style", "")) != expected_style:
		errors.append("%s: inventory action hover style expected %s, got %s" % [context, expected_style, target.get_meta("inventory_action_drag_highlight_style", "")])
	if str(target.get_meta("inventory_action_drag_highlight_color", "")) != expected_color:
		errors.append("%s: inventory action hover color expected %s, got %s" % [context, expected_color, target.get_meta("inventory_action_drag_highlight_color", "")])
	if target is PanelContainer:
		var label := target.get_node_or_null("DropZoneLabel") as Label
		if label == null or str(label.get_meta("inventory_action_drag_highlight_color", "")) != expected_color:
			errors.append("%s: inventory drop zone label should expose hover color meta: %s" % [context, label])


func _assert_drag_preview_diagnostics(errors: Array[String], preview: Dictionary, context: String) -> void:
	var position: Dictionary = _dictionary_or_empty(preview.get("screen_position", {}))
	var viewport: Dictionary = _dictionary_or_empty(preview.get("viewport_size", {}))
	var estimated_size: Dictionary = _dictionary_or_empty(preview.get("estimated_size", {}))
	var anchor: Dictionary = _dictionary_or_empty(preview.get("anchor", {}))
	if position.is_empty() or not position.has("x") or not position.has("y"):
		errors.append("%s: drag preview should expose screen position: %s" % [context, preview])
	if viewport.is_empty() or float(viewport.get("x", 0.0)) <= 0.0 or float(viewport.get("y", 0.0)) <= 0.0:
		errors.append("%s: drag preview should expose viewport size: %s" % [context, preview])
	if estimated_size.is_empty() or float(estimated_size.get("x", 0.0)) <= 0.0 or float(estimated_size.get("y", 0.0)) <= 0.0:
		errors.append("%s: drag preview should expose estimated size: %s" % [context, preview])
	if anchor.is_empty() or not anchor.has("x") or not anchor.has("y"):
		errors.append("%s: drag preview should expose anchor: %s" % [context, preview])
	if str(preview.get("lifecycle_state", "")) != "dragging":
		errors.append("%s: drag preview should expose dragging lifecycle: %s" % [context, preview])
	if str(preview.get("threshold_policy", "")) != "godot_default":
		errors.append("%s: drag preview should expose threshold policy: %s" % [context, preview])


func _assert_drag_reject_reason_text(errors: Array[String], target_snapshot: Dictionary, highlight: Dictionary, expected_reject_reason: String, context: String) -> void:
	var reason_text := str(target_snapshot.get("reject_reason_text", ""))
	var highlight_text := str(highlight.get("reject_reason_text", ""))
	if expected_reject_reason.is_empty():
		if not reason_text.is_empty() or not highlight_text.is_empty():
			errors.append("%s: accepted drag target should not expose reject reason text: %s / %s" % [context, target_snapshot, highlight])
		return
	if reason_text.is_empty():
		errors.append("%s: rejected drag target should expose reject reason text: %s" % [context, target_snapshot])
	if highlight_text != reason_text:
		errors.append("%s: hover highlight should mirror reject reason text: %s / %s" % [context, target_snapshot, highlight])


func _assert_inventory_control_audio(errors: Array[String], game_root: Node, expected_event_kind: String, expected_sound_id: String, expected_control_name: String, expected_control_kind: String, expected_action: String, expected_payload: Dictionary, context: String) -> void:
	if not game_root.has_method("audio_feedback_snapshot"):
		errors.append("%s: game root should expose audio_feedback_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(snapshot.get("last_event_kind", "")) != expected_event_kind or str(snapshot.get("last_sound_id", "")) != expected_sound_id:
		errors.append("%s: expected %s/%s audio feedback, got %s" % [context, expected_event_kind, expected_sound_id, snapshot])
		return
	var recent: Array = _array_or_empty(snapshot.get("recent_events", []))
	if recent.is_empty():
		errors.append("%s: audio snapshot should expose recent events: %s" % [context, snapshot])
		return
	var entry: Dictionary = _dictionary_or_empty(recent[recent.size() - 1])
	if str(entry.get("audio_source", "")) != "ui" or str(entry.get("panel_id", "")) != "inventory":
		errors.append("%s: recent audio source/panel mismatch: %s" % [context, entry])
	if str(entry.get("event_kind", "")) != expected_event_kind or str(entry.get("sound_id", "")) != expected_sound_id:
		errors.append("%s: recent audio event mismatch: %s" % [context, entry])
	if str(entry.get("control_name", "")) != expected_control_name:
		errors.append("%s: recent audio control name expected %s, got %s" % [context, expected_control_name, entry.get("control_name", "")])
	if str(entry.get("control_kind", "")) != expected_control_kind:
		errors.append("%s: recent audio control kind expected %s, got %s" % [context, expected_control_kind, entry.get("control_kind", "")])
	if str(entry.get("action", "")) != expected_action:
		errors.append("%s: recent audio action expected %s, got %s" % [context, expected_action, entry.get("action", "")])
	for key in expected_payload.keys():
		if str(entry.get(key, "")) != str(expected_payload.get(key, "")):
			errors.append("%s: recent audio payload %s expected %s, got %s" % [context, key, expected_payload.get(key, ""), entry.get(key, "")])


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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _assert_inventory_context_menu(errors: Array[String], game_root: Node, expected_item_id: String, context: String) -> void:
	if not game_root.has_method("context_menu_snapshot"):
		errors.append("%s: game root should expose context_menu_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.context_menu_snapshot())
	if not bool(snapshot.get("active", false)):
		errors.append("%s: context menu snapshot should be active: %s" % [context, snapshot])
		return
	var top: Dictionary = _dictionary_or_empty(snapshot.get("top", {}))
	if str(top.get("id", "")) != "inventory_context_menu" or str(top.get("kind", "")) != "inventory_item":
		errors.append("%s: expected inventory context top, got %s" % [context, top])
	if str(top.get("item_id", "")) != expected_item_id:
		errors.append("%s: context menu item expected %s, got %s" % [context, expected_item_id, top])
	if int(top.get("option_count", 0)) < 8:
		errors.append("%s: inventory context menu should expose action options: %s" % [context, top])
	var options: Array = _array_or_empty(top.get("options", []))
	var split_seen := false
	var expected_item: Dictionary = _inventory_snapshot_item(game_root, expected_item_id)
	var expected_split_enabled := bool(expected_item.get("can_split_stack", false))
	for option in options:
		var option_data: Dictionary = _dictionary_or_empty(option)
		if int(option_data.get("id", -1)) == 8:
			split_seen = true
			if bool(option_data.get("disabled", false)) == expected_split_enabled:
				errors.append("%s: split action enabled state should follow can_split_stack=%s: %s" % [context, str(expected_split_enabled), option_data])
	if not split_seen:
		errors.append("%s: inventory context snapshot should include split action: %s" % [context, top])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_context: Dictionary = _dictionary_or_empty(runtime.get("context_menu", {}))
	if str(_dictionary_or_empty(runtime_context.get("top", {})).get("item_id", "")) != expected_item_id:
		errors.append("%s: runtime context menu should expose inventory item %s: %s" % [context, expected_item_id, runtime_context])


func _assert_modal_stack(errors: Array[String], game_root: Node, expected_id: String, expected_owner: String, context: String) -> void:
	if not game_root.has_method("modal_stack_snapshot"):
		errors.append("%s: game root should expose modal_stack_snapshot" % context)
		return
	var stack_snapshot: Dictionary = _dictionary_or_empty(game_root.modal_stack_snapshot())
	if not bool(stack_snapshot.get("active", false)) or int(stack_snapshot.get("count", 0)) <= 0:
		errors.append("%s: modal stack should be active: %s" % [context, stack_snapshot])
		return
	var top: Dictionary = _dictionary_or_empty(stack_snapshot.get("top", {}))
	if str(top.get("id", "")) != expected_id:
		errors.append("%s: modal stack top expected %s, got %s" % [context, expected_id, top])
	if str(top.get("owner_panel", "")) != expected_owner:
		errors.append("%s: modal stack owner expected %s, got %s" % [context, expected_owner, top])
	if not bool(top.get("blocks_gameplay", false)) or not bool(top.get("mouse_blocks_world", false)):
		errors.append("%s: modal stack top should block gameplay and mouse world input: %s" % [context, top])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_stack: Dictionary = _dictionary_or_empty(runtime.get("modal_stack", {}))
	if str(_dictionary_or_empty(runtime_stack.get("top", {})).get("id", "")) != expected_id:
		errors.append("%s: runtime modal stack should expose top %s: %s" % [context, expected_id, runtime_stack])


func _assert_discard_quantity_modal_details(errors: Array[String], game_root: Node, expected_count: int, expected_available: int, expected_valid: bool, expected_error_fragment: String, context: String) -> void:
	var stack_snapshot: Dictionary = _dictionary_or_empty(game_root.modal_stack_snapshot()) if game_root.has_method("modal_stack_snapshot") else {}
	var top: Dictionary = _dictionary_or_empty(stack_snapshot.get("top", {}))
	if str(top.get("id", "")) != "inventory_discard_confirm":
		errors.append("%s: discard modal details require inventory_discard_confirm top: %s" % [context, stack_snapshot])
		return
	if not bool(top.get("dialog_visible", false)):
		errors.append("%s: discard modal snapshot should expose visible dialog: %s" % [context, top])
	if int(top.get("count", -1)) != expected_count or int(top.get("available", -1)) != expected_available:
		errors.append("%s: discard modal should expose count/available %d/%d, got %s" % [context, expected_count, expected_available, top])
	if int(top.get("quantity_min", 0)) != 1 or int(top.get("quantity_max", 0)) != expected_available:
		errors.append("%s: discard modal should expose quantity bounds: %s" % [context, top])
	if bool(top.get("quantity_valid", not expected_valid)) != expected_valid:
		errors.append("%s: discard modal quantity_valid expected %s, got %s" % [context, str(expected_valid), top])
	var error_text := str(top.get("quantity_error", ""))
	if expected_error_fragment.is_empty():
		if not error_text.is_empty():
			errors.append("%s: discard modal quantity_error should be empty, got %s" % [context, top])
	elif not error_text.contains(expected_error_fragment):
		errors.append("%s: discard modal quantity_error should contain %s, got %s" % [context, expected_error_fragment, top])
	if not bool(top.get("quantity_input_mouse_blocks_world", false)) or str(top.get("quantity_input_mouse_filter", "")) != "stop":
		errors.append("%s: discard quantity input should stop world mouse input: %s" % [context, top])
	if not bool(top.get("confirm_button_mouse_blocks_world", false)) or not bool(top.get("cancel_button_mouse_blocks_world", false)):
		errors.append("%s: discard modal buttons should stop world mouse input: %s" % [context, top])


func _assert_deconstruct_equipment_modal_details(errors: Array[String], game_root: Node, expected_item_id: String, expected_count: int, expected_tool_id: String, expected_slot_id: String, context: String) -> void:
	var stack_snapshot: Dictionary = _dictionary_or_empty(game_root.modal_stack_snapshot()) if game_root.has_method("modal_stack_snapshot") else {}
	var top: Dictionary = _dictionary_or_empty(stack_snapshot.get("top", {}))
	if str(top.get("id", "")) != "inventory_deconstruct_equipment_confirm":
		errors.append("%s: deconstruct equipment modal details require confirm top: %s" % [context, stack_snapshot])
		return
	if str(top.get("item_id", "")) != expected_item_id or int(top.get("count", 0)) != expected_count:
		errors.append("%s: deconstruct equipment modal should expose item/count: %s" % [context, top])
	var sources: Array = _array_or_empty(top.get("equipment_sources", []))
	if sources.is_empty():
		errors.append("%s: deconstruct equipment modal should expose equipment source: %s" % [context, top])
		return
	var source: Dictionary = _dictionary_or_empty(sources[0])
	if str(source.get("item_id", "")) != expected_tool_id or str(source.get("slot_id", "")) != expected_slot_id:
		errors.append("%s: deconstruct equipment source expected %s/%s, got %s" % [context, expected_tool_id, expected_slot_id, source])
	if not bool(top.get("confirm_button_mouse_blocks_world", false)) or not bool(top.get("cancel_button_mouse_blocks_world", false)):
		errors.append("%s: deconstruct equipment modal buttons should stop world mouse input: %s" % [context, top])


func _assert_modal_menu_event(errors: Array[String], game_root: Node, expected_id: String, expected_owner: String, context: String) -> void:
	if not game_root.has_method("menu_state_snapshot"):
		errors.append("%s: game root should expose menu_state_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot())
	var event: Dictionary = _dictionary_or_empty(snapshot.get("modal_event", {}))
	if event.is_empty():
		errors.append("%s: menu state should expose modal_event: %s" % [context, snapshot])
		return
	if str(event.get("event", "")) != "modal_opened" or str(event.get("panel_id", "")) != expected_id:
		errors.append("%s: modal event expected opened:%s, got %s" % [context, expected_id, event])
	if str(event.get("owner_panel", "")) != expected_owner:
		errors.append("%s: modal event owner expected %s, got %s" % [context, expected_owner, event])
	if not bool(event.get("blocks_gameplay", false)) or not bool(event.get("mouse_blocks_world", false)):
		errors.append("%s: modal event should expose gameplay and mouse blockers: %s" % [context, event])
	if not _recent_menu_events_contain(snapshot, "modal_opened", expected_id):
		errors.append("%s: recent events should include modal event %s: %s" % [context, expected_id, snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_menu: Dictionary = _dictionary_or_empty(runtime.get("menu_state", {}))
	var runtime_event: Dictionary = _dictionary_or_empty(runtime_menu.get("modal_event", {}))
	if str(runtime_event.get("event", "")) != "modal_opened" or str(runtime_event.get("panel_id", "")) != expected_id:
		errors.append("%s: runtime menu should expose modal event %s: %s" % [context, expected_id, runtime_menu])
	if not _recent_menu_events_contain(runtime_menu, "modal_opened", expected_id):
		errors.append("%s: runtime recent events should include modal event %s: %s" % [context, expected_id, runtime_menu])


func _assert_no_modal_menu_event(errors: Array[String], game_root: Node, context: String) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot() if game_root.has_method("menu_state_snapshot") else {})
	if not _dictionary_or_empty(snapshot.get("modal_event", {})).is_empty():
		errors.append("%s: modal_event should clear when no modal is active: %s" % [context, snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_menu: Dictionary = _dictionary_or_empty(runtime.get("menu_state", {}))
	if not _dictionary_or_empty(runtime_menu.get("modal_event", {})).is_empty():
		errors.append("%s: runtime modal_event should clear when no modal is active: %s" % [context, runtime_menu])


func _recent_menu_events_contain(menu_state: Dictionary, expected_event: String, expected_id: String) -> bool:
	for value in _array_or_empty(menu_state.get("recent_events", [])):
		var event: Dictionary = _dictionary_or_empty(value)
		if str(event.get("event", "")) == expected_event and str(event.get("panel_id", "")) == expected_id:
			return true
	return false
