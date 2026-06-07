extends Control

const MediaTextureLoader = preload("res://scripts/ui/media_texture_loader.gd")

const CONTEXT_USE := 1
const CONTEXT_EQUIP := 2
const CONTEXT_DROP := 3
const CONTEXT_INSPECT := 4
const CONTEXT_HOTBAR := 5
const CONTEXT_DECONSTRUCT := 6
const CONTEXT_DROP_ALL := 7
const CONTEXT_SPLIT := 8
const CONTEXT_STORE_CONTAINER := 9
const CONTEXT_SELL_TRADE := 10
const CONTEXT_SPLIT_STACK_BASE := 100

var _panel: PanelContainer
var _title_label: Label
var _summary_label: Label
var _feedback_label: Label
var _search_box: LineEdit
var _filter_box: HBoxContainer
var _sort_box: HBoxContainer
var _detail_label: Label
var _quantity_spin: SpinBox
var _use_button: Button
var _equip_button: Button
var _drop_button: Button
var _drop_zone: PanelContainer
var _context_menu: PopupMenu
var _discard_dialog: ConfirmationDialog
var _discard_quantity_input: LineEdit
var _discard_quantity_label: Label
var _discard_error_label: Label
var _discard_minus_button: Button
var _discard_plus_button: Button
var _discard_max_button: Button
var _items_box: VBoxContainer
var _category_filter: String = "all"
var _sort_mode: String = "order"
var _search_text: String = ""
var _last_snapshot: Dictionary = {}
var _selected_item: Dictionary = {}
var _context_item: Dictionary = {}
var _pending_discard_item: Dictionary = {}
var _pending_discard_count := 0
var _pending_discard_available := 0


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	_last_snapshot = snapshot.duplicate(true)
	_title_label.text = "%s 的背包" % snapshot.get("owner_name", "")
	_summary_label.text = _summary_text(snapshot)
	_apply_feedback(_dictionary_or_empty(snapshot.get("feedback", {})))
	_refresh_filter_buttons()
	_refresh_sort_buttons()
	_clear_items()
	var visible_items: Array[Dictionary] = _visible_items(snapshot.get("items", []))
	if visible_items.is_empty():
		var empty := _label("EmptyLine")
		empty.text = "没有符合筛选的物品"
		_items_box.add_child(empty)
		_apply_detail({})
		return
	for item in visible_items:
		var item_data: Dictionary = item
		_items_box.add_child(_item_line(item_data))
	_apply_detail(_selected_visible_item(visible_items))


func _summary_text(snapshot: Dictionary) -> String:
	var max_weight := float(snapshot.get("max_weight", 0.0))
	var weight_text := "%.1f/%.1f kg" % [float(snapshot.get("total_weight", 0.0)), max_weight] if max_weight > 0.0 else "%.1f kg" % float(snapshot.get("total_weight", 0.0))
	var parts: Array[String] = [
		"%d 类物品" % int(snapshot.get("item_count", 0)),
		weight_text,
	]
	var max_items := int(snapshot.get("max_items", -1))
	if max_items >= 0:
		parts.append("种类 %d/%d" % [int(snapshot.get("current_item_count", snapshot.get("item_count", 0))), max_items])
	var max_stacks := int(snapshot.get("max_stacks", -1))
	if max_stacks >= 0:
		parts.append("槽位 %d/%d" % [int(snapshot.get("current_stack_count", 0)), max_stacks])
	if bool(snapshot.get("over_capacity", false)):
		if bool(snapshot.get("over_item_capacity", false)):
			parts.append("种类超限")
		elif bool(snapshot.get("over_stack_capacity", false)):
			parts.append("槽位超限")
		else:
			parts.append("超重")
	return " | ".join(parts)


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "InventoryPanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -360
	_panel.offset_right = -16
	_panel.offset_top = 16
	_panel.offset_bottom = 260
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "InventoryLines"
	box.add_theme_constant_override("separation", 7)
	_panel.add_child(box)

	_title_label = _label("TitleLine")
	_summary_label = _label("SummaryLine")
	_feedback_label = _label("InventoryFeedbackLine")
	_search_box = LineEdit.new()
	_search_box.name = "SearchBox"
	_search_box.placeholder_text = "搜索物品"
	_search_box.clear_button_enabled = true
	_search_box.custom_minimum_size = Vector2(0, 28)
	_search_box.text_changed.connect(func(text: String) -> void:
		_search_text = text.strip_edges().to_lower()
		if not _last_snapshot.is_empty():
			apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	_filter_box = HBoxContainer.new()
	_filter_box.name = "FilterBar"
	_filter_box.add_theme_constant_override("separation", 4)
	_sort_box = HBoxContainer.new()
	_sort_box.name = "SortBar"
	_sort_box.add_theme_constant_override("separation", 4)
	_detail_label = _label("DetailLine")
	_quantity_spin = SpinBox.new()
	_quantity_spin.name = "QuantitySpin"
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = 1
	_quantity_spin.step = 1
	_quantity_spin.value = 1
	_quantity_spin.custom_minimum_size = Vector2(72, 28)
	_quantity_spin.focus_mode = Control.FOCUS_NONE
	_use_button = _action_button("UseSelectedButton", "使用", "使用选中的物品")
	_use_button.disabled = true
	_use_button.pressed.connect(func() -> void:
		if _selected_item.is_empty():
			return
		var root := get_parent()
		if root != null and root.has_method("use_player_item"):
			root.use_player_item(str(_selected_item.get("item_id", "")))
	, CONNECT_DEFERRED)
	_equip_button = _action_button("EquipSelectedButton", "装备", "装备选中的物品")
	_equip_button.set_meta("inventory_action_target", "equip")
	_equip_button.set_drag_forwarding(
		Callable(self, "_empty_inventory_drag_data"),
		Callable(self, "_can_drop_inventory_action_data"),
		Callable(self, "_drop_inventory_action_data")
	)
	_equip_button.disabled = true
	_equip_button.pressed.connect(func() -> void:
		if _selected_item.is_empty():
			return
		var slots: Array = _array_or_empty(_selected_item.get("equip_slots", []))
		if slots.is_empty():
			return
		var root := get_parent()
		if root != null and root.has_method("equip_player_item"):
			root.equip_player_item(str(_selected_item.get("item_id", "")), str(slots[0]))
	, CONNECT_DEFERRED)
	_drop_button = _action_button("DropSelectedButton", "丢弃", "丢弃选中的数量")
	_drop_button.set_meta("inventory_action_target", "drop")
	_drop_button.set_drag_forwarding(
		Callable(self, "_empty_inventory_drag_data"),
		Callable(self, "_can_drop_inventory_action_data"),
		Callable(self, "_drop_inventory_action_data")
	)
	_drop_button.disabled = true
	_drop_button.pressed.connect(func() -> void:
		if _selected_item.is_empty():
			return
		_open_discard_dialog_for_item(_selected_item, int(_quantity_spin.value if _quantity_spin != null else 1))
	, CONNECT_DEFERRED)
	_drop_zone = PanelContainer.new()
	_drop_zone.name = "DropZone"
	_drop_zone.tooltip_text = "将物品拖到这里打开丢弃确认"
	_drop_zone.custom_minimum_size = Vector2(0, 34)
	_drop_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	_drop_zone.set_meta("inventory_action_target", "drop")
	_drop_zone.set_drag_forwarding(
		Callable(self, "_empty_inventory_drag_data"),
		Callable(self, "_can_drop_inventory_action_data"),
		Callable(self, "_drop_inventory_action_data")
	)
	var drop_zone_label := _label("DropZoneLabel")
	drop_zone_label.text = "拖到这里丢弃"
	drop_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_zone_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drop_zone_label.tooltip_text = _drop_zone.tooltip_text
	_drop_zone.add_child(drop_zone_label)
	_context_menu = PopupMenu.new()
	_context_menu.name = "InventoryContextMenu"
	_context_menu.id_pressed.connect(_execute_context_action)
	add_child(_context_menu)
	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.name = "DiscardConfirmDialog"
	_discard_dialog.title = "确认丢弃"
	_discard_dialog.dialog_text = "确定要丢弃选中的物品吗？"
	_discard_dialog.confirmed.connect(_confirm_pending_discard)
	_discard_dialog.get_ok_button().text = "丢弃"
	_discard_dialog.get_cancel_button().text = "取消"
	_build_discard_quantity_controls()
	add_child(_discard_dialog)
	var action_row := HBoxContainer.new()
	action_row.name = "ActionBar"
	action_row.add_theme_constant_override("separation", 4)
	action_row.add_child(_quantity_spin)
	action_row.add_child(_use_button)
	action_row.add_child(_equip_button)
	action_row.add_child(_drop_button)
	var item_scroll := ScrollContainer.new()
	item_scroll.name = "ItemScroll"
	item_scroll.custom_minimum_size = Vector2(320, 96)
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_box = VBoxContainer.new()
	_items_box.name = "ItemLines"
	_items_box.add_theme_constant_override("separation", 4)
	_items_box.set_drag_forwarding(
		Callable(self, "_empty_inventory_drag_data"),
		Callable(self, "_can_drop_inventory_data"),
		Callable(self, "_drop_inventory_data")
	)
	box.add_child(_title_label)
	box.add_child(_summary_label)
	box.add_child(_feedback_label)
	box.add_child(_search_box)
	box.add_child(_filter_box)
	box.add_child(_sort_box)
	box.add_child(_detail_label)
	box.add_child(action_row)
	box.add_child(_drop_zone)
	item_scroll.add_child(_items_box)
	box.add_child(item_scroll)
	_add_filter_button("FilterAllButton", "全部", "all")
	_add_filter_button("FilterEquipmentButton", "装备", "equipment")
	_add_filter_button("FilterConsumableButton", "消耗", "consumable")
	_add_filter_button("FilterAmmoButton", "弹药", "ammo")
	_add_filter_button("FilterMaterialButton", "材料", "material")
	_add_sort_button("SortOrderButton", "顺序", "order")
	_add_sort_button("SortNameButton", "名称", "name")
	_add_sort_button("SortWeightButton", "重量", "weight")
	_add_sort_button("SortValueButton", "价值", "value")


func _item_line(item: Dictionary) -> Button:
	var button := Button.new()
	button.name = "Item_%s" % item.get("item_id", "unknown")
	button.text = "%s x%d | %.1f kg | %s" % [
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
		float(item.get("total_weight", 0.0)),
		item.get("category_label", "杂项"),
	]
	button.tooltip_text = str(item.get("description", ""))
	button.set_meta("inventory_item", item.duplicate(true))
	button.set_meta("inventory_index", int(item.get("order_index", 0)))
	_apply_item_icon(button, item)
	button.set_drag_forwarding(
		Callable(self, "_get_inventory_item_drag_data"),
		Callable(self, "_can_drop_inventory_data"),
		Callable(self, "_drop_inventory_data")
	)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_apply_detail(item.duplicate(true))
	)
	button.gui_input.connect(func(event: InputEvent) -> void:
		var mouse_event := event as InputEventMouseButton
		if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT:
			return
		button.accept_event()
		_open_context_menu_for_item(item.duplicate(true), button.get_global_mouse_position())
	)
	return button


func _apply_item_icon(button: Button, item: Dictionary) -> void:
	var icon_asset := _dictionary_or_empty(item.get("icon_asset", {}))
	var texture := MediaTextureLoader.texture_from_asset(icon_asset)
	if texture == null:
		button.icon = null
		return
	button.icon = texture
	button.expand_icon = true
	button.set_meta("icon_resource_path", MediaTextureLoader.resource_path_from_asset(icon_asset))
	button.set_meta("icon_fallback_key", str(icon_asset.get("fallback_key", "")))


func _empty_inventory_drag_data(_position: Vector2, _from_control: Control) -> Variant:
	return null


func _get_inventory_item_drag_data(_position: Vector2, from_control: Control) -> Variant:
	if from_control == null or not from_control.has_meta("inventory_item"):
		return null
	var item: Dictionary = _dictionary_or_empty(from_control.get_meta("inventory_item"))
	var item_id: String = str(item.get("item_id", ""))
	if item.is_empty() or item_id.is_empty():
		return null
	_apply_detail(item.duplicate(true))
	var preview_text := "%s x%d" % [item.get("name", item_id), int(item.get("count", 0))]
	if get_viewport() != null and get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = preview_text
		set_drag_preview(preview)
	return {
		"kind": "inventory_item",
		"item": item.duplicate(true),
		"item_id": item_id,
		"count": _drag_drop_count(item),
		"from_index": int(from_control.get_meta("inventory_index", item.get("order_index", 0))),
		"drag_preview_text": preview_text,
	}


func _can_drop_inventory_data(_position: Vector2, data: Variant, from_control: Control) -> bool:
	if not _can_reorder_inventory():
		return false
	var drag_data: Dictionary = _dictionary_or_empty(data)
	if str(drag_data.get("kind", "")) != "inventory_item":
		return false
	var item_id: String = str(drag_data.get("item_id", ""))
	return not item_id.is_empty() and _drop_target_index(from_control) >= 0


func _drop_inventory_data(position: Vector2, data: Variant, from_control: Control) -> void:
	if not _can_drop_inventory_data(position, data, from_control):
		return
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var root := get_parent()
	if root != null and root.has_method("reorder_player_inventory_item"):
		root.reorder_player_inventory_item(str(drag_data.get("item_id", "")), _drop_target_index(from_control))


func _can_drop_inventory_action_data(_position: Vector2, data: Variant, from_control: Control) -> bool:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	if str(drag_data.get("kind", "")) != "inventory_item":
		return false
	var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
	var item_id: String = str(drag_data.get("item_id", item.get("item_id", "")))
	if item_id.is_empty():
		return false
	match _inventory_action_target(from_control):
		"equip":
			return not _array_or_empty(item.get("equip_slots", [])).is_empty()
		"drop":
			return bool(item.get("droppable", true)) and int(item.get("count", 0)) > 0
		_:
			return false


func _drop_inventory_action_data(position: Vector2, data: Variant, from_control: Control) -> void:
	if not _can_drop_inventory_action_data(position, data, from_control):
		return
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
	var item_id: String = str(drag_data.get("item_id", item.get("item_id", "")))
	var root := get_parent()
	if root == null:
		return
	match _inventory_action_target(from_control):
		"equip":
			var slots: Array = _array_or_empty(item.get("equip_slots", []))
			if not slots.is_empty() and root.has_method("equip_player_item"):
				root.equip_player_item(item_id, str(slots[0]))
		"drop":
			_open_discard_dialog_for_item(item, _drag_drop_count(item))


func _open_context_menu_for_item(item: Dictionary, screen_position: Vector2) -> void:
	if _context_menu == null:
		return
	_apply_detail(item.duplicate(true))
	_context_item = item.duplicate(true)
	_context_menu.clear()
	_context_menu.add_item("检查", CONTEXT_INSPECT)
	_context_menu.add_item("使用", CONTEXT_USE)
	_context_menu.add_item("装备", CONTEXT_EQUIP)
	_context_menu.add_item("丢弃", CONTEXT_DROP)
	_context_menu.add_item("全部丢弃", CONTEXT_DROP_ALL)
	_context_menu.add_item("拆分", CONTEXT_SPLIT)
	_add_stack_split_context_items(item)
	_context_menu.add_item("存入容器", CONTEXT_STORE_CONTAINER)
	_context_menu.add_item("出售", CONTEXT_SELL_TRADE)
	_context_menu.add_item("拆解", CONTEXT_DECONSTRUCT)
	_context_menu.add_item("加入热栏", CONTEXT_HOTBAR)
	var root := get_parent()
	var has_container := root != null and root.has_method("has_active_container_session") and bool(root.has_active_container_session())
	var has_trade := root != null and root.has_method("has_active_trade_session") and bool(root.has_active_trade_session())
	var can_transfer := int(item.get("count", 0)) > 0
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_USE), not bool(item.get("usable", false)))
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_EQUIP), _array_or_empty(item.get("equip_slots", [])).is_empty())
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_DROP), not bool(item.get("droppable", true)) or int(item.get("count", 0)) <= 0)
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_DROP_ALL), not bool(item.get("droppable", true)) or int(item.get("count", 0)) <= 0)
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_SPLIT), not bool(item.get("can_split_stack", false)))
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_STORE_CONTAINER), not has_container or not can_transfer)
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_SELL_TRADE), not has_trade or not can_transfer)
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_DECONSTRUCT), not bool(item.get("deconstructable", false)) or int(item.get("count", 0)) <= 0)
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_HOTBAR), not bool(item.get("usable", false)))
	_context_menu.set_item_tooltip(_context_menu.get_item_index(CONTEXT_SPLIT), _split_context_tooltip(item))
	_context_menu.set_item_tooltip(_context_menu.get_item_index(CONTEXT_STORE_CONTAINER), "存入当前打开的容器" if has_container else "需要先打开一个容器")
	_context_menu.set_item_tooltip(_context_menu.get_item_index(CONTEXT_SELL_TRADE), "出售给当前交易对象" if has_trade else "需要先打开交易")
	_context_menu.set_item_tooltip(_context_menu.get_item_index(CONTEXT_DECONSTRUCT), _deconstruct_context_tooltip(item))
	var popup_position := Vector2i(int(screen_position.x), int(screen_position.y))
	_context_menu.popup(Rect2i(popup_position, Vector2i(180, 1)))


func context_menu_snapshot() -> Dictionary:
	if _context_menu == null or not _context_menu.visible:
		return {}
	return {
		"id": "inventory_context_menu",
		"name": "inventory_context_menu",
		"kind": "inventory_item",
		"owner_panel": "inventory",
		"active": true,
		"visible": true,
		"mouse_blocks_world": true,
		"item_id": str(_context_item.get("item_id", "")),
		"item_name": str(_context_item.get("name", _context_item.get("item_id", ""))),
		"item_count": int(_context_item.get("count", 0)),
		"option_count": _context_menu.item_count,
		"options": _inventory_context_option_summaries(),
	}


func _inventory_context_option_summaries() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if _context_menu == null:
		return output
	for index in range(_context_menu.item_count):
		output.append({
			"id": _context_menu.get_item_id(index),
			"label": _context_menu.get_item_text(index),
			"disabled": _context_menu.is_item_disabled(index),
			"tooltip": _context_menu.get_item_tooltip(index),
		})
	return output


func close_context_menu() -> void:
	if _context_menu != null:
		_context_menu.hide()
	_context_item = {}


func _execute_context_action(action_id: int) -> void:
	if _context_item.is_empty():
		return
	var action_item := _context_item.duplicate(true)
	var item_id: String = str(_context_item.get("item_id", ""))
	if item_id.is_empty():
		return
	close_context_menu()
	if action_id == CONTEXT_INSPECT:
		_apply_inspect_detail(action_item)
		return
	var root := get_parent()
	if root == null:
		return
	if action_id >= CONTEXT_SPLIT_STACK_BASE:
		if root.has_method("split_player_inventory_stack"):
			var source_stack_index := action_id - CONTEXT_SPLIT_STACK_BASE + 1
			root.split_player_inventory_stack(item_id, _drag_drop_count(action_item), source_stack_index)
		return
	match action_id:
		CONTEXT_USE:
			if bool(action_item.get("usable", false)) and root.has_method("use_player_item"):
				root.use_player_item(item_id)
		CONTEXT_EQUIP:
			var slots: Array = _array_or_empty(action_item.get("equip_slots", []))
			if not slots.is_empty() and root.has_method("equip_player_item"):
				root.equip_player_item(item_id, str(slots[0]))
		CONTEXT_DROP:
			if bool(action_item.get("droppable", true)):
				_open_discard_dialog_for_item(action_item, _drag_drop_count(action_item))
		CONTEXT_DROP_ALL:
			if bool(action_item.get("droppable", true)):
				_open_discard_dialog_for_item(action_item, int(action_item.get("count", 1)))
		CONTEXT_SPLIT:
			if root.has_method("split_player_inventory_stack"):
				root.split_player_inventory_stack(item_id, _drag_drop_count(action_item))
		CONTEXT_STORE_CONTAINER:
			if root.has_method("store_active_container_item"):
				root.store_active_container_item(item_id, _drag_drop_count(action_item))
		CONTEXT_SELL_TRADE:
			if root.has_method("sell_active_trade_item"):
				root.sell_active_trade_item(item_id, _drag_drop_count(action_item))
		CONTEXT_DECONSTRUCT:
			if bool(action_item.get("deconstructable", false)) and root.has_method("deconstruct_player_item"):
				root.deconstruct_player_item(item_id, _drag_drop_count(action_item))
		CONTEXT_HOTBAR:
			if bool(action_item.get("usable", false)) and root.has_method("bind_player_item_to_hotbar"):
				root.bind_player_item_to_hotbar("", item_id)


func _apply_inspect_detail(item: Dictionary) -> void:
	_apply_detail(item.duplicate(true))
	if _detail_label == null or item.is_empty():
		return
	var item_name := str(item.get("name", item.get("item_id", "")))
	_detail_label.text = "检查：%s\n%s" % [item_name, _detail_label.text]


func _split_context_tooltip(item: Dictionary) -> String:
	if not bool(item.get("stackable", false)) or int(item.get("count", 0)) <= 1:
		return "只有数量大于 1 的堆叠物品才能拆分"
	if not bool(item.get("can_split_stack", false)):
		return "当前最大堆叠数量不足，无法继续拆分"
	var stacks: Array = _array_or_empty(item.get("stack_counts", []))
	return "拆分当前最大堆叠；当前堆叠 %s" % ", ".join(_string_array(stacks))


func _add_stack_split_context_items(item: Dictionary) -> void:
	if _context_menu == null:
		return
	var stacks: Array = _array_or_empty(item.get("stack_counts", []))
	if stacks.size() <= 1:
		return
	var split_count := _drag_drop_count(item)
	for index in range(stacks.size()):
		var stack_count := int(stacks[index])
		var item_id := CONTEXT_SPLIT_STACK_BASE + index
		_context_menu.add_item("拆分第 %d 堆" % (index + 1), item_id)
		var menu_index := _context_menu.get_item_index(item_id)
		var can_split := bool(item.get("stackable", false)) and stack_count > split_count
		_context_menu.set_item_disabled(menu_index, not can_split)
		_context_menu.set_item_tooltip(menu_index, "从第 %d 堆拆出 %d 个；该堆当前 %d 个" % [index + 1, split_count, stack_count])


func _apply_feedback(feedback: Dictionary) -> void:
	if _feedback_label == null:
		return
	var text := str(feedback.get("text", ""))
	_feedback_label.visible = not text.is_empty()
	_feedback_label.text = text
	_feedback_label.tooltip_text = str(feedback.get("reason", ""))


func has_blocking_modal() -> bool:
	return _discard_dialog != null and _discard_dialog.visible


func blocking_modal_name() -> String:
	if has_blocking_modal():
		return "inventory_discard_confirm"
	return ""


func blocking_modal_snapshot() -> Dictionary:
	if not has_blocking_modal():
		return {}
	var quantity_value := _discard_quantity_value()
	var quantity_valid := quantity_value >= 1 and (_pending_discard_available <= 0 or quantity_value <= _pending_discard_available)
	return {
		"id": "inventory_discard_confirm",
		"name": "modal:inventory_discard_confirm",
		"kind": "confirm",
		"owner_panel": "inventory",
		"blocks_gameplay": true,
		"mouse_blocks_world": true,
		"dialog_visible": _discard_dialog.visible,
		"item_id": str(_pending_discard_item.get("item_id", "")),
		"item_name": str(_pending_discard_item.get("name", _pending_discard_item.get("item_id", ""))),
		"count": quantity_value,
		"available": _pending_discard_available,
		"quantity_min": 1,
		"quantity_max": _pending_discard_available,
		"quantity_text": _discard_quantity_input.text if _discard_quantity_input != null else str(quantity_value),
		"quantity_valid": quantity_valid,
		"quantity_error": _discard_error_label.text if _discard_error_label != null else "",
		"quantity_input_mouse_filter": _control_mouse_filter_name(_discard_quantity_input),
		"quantity_input_mouse_blocks_world": _control_mouse_blocks_world(_discard_quantity_input),
		"minus_button_disabled": _discard_minus_button.disabled if _discard_minus_button != null else true,
		"plus_button_disabled": _discard_plus_button.disabled if _discard_plus_button != null else true,
		"max_button_disabled": _discard_max_button.disabled if _discard_max_button != null else true,
		"confirm_button_mouse_filter": _control_mouse_filter_name(_discard_dialog.get_ok_button()),
		"confirm_button_mouse_blocks_world": _control_mouse_blocks_world(_discard_dialog.get_ok_button()),
		"cancel_button_mouse_filter": _control_mouse_filter_name(_discard_dialog.get_cancel_button()),
		"cancel_button_mouse_blocks_world": _control_mouse_blocks_world(_discard_dialog.get_cancel_button()),
	}


func close_blocking_modal() -> Dictionary:
	if not has_blocking_modal():
		return {"success": false, "reason": "modal_inactive"}
	_discard_dialog.hide()
	_pending_discard_item = {}
	_pending_discard_count = 0
	_pending_discard_available = 0
	_clear_discard_quantity_error()
	return {
		"success": true,
		"closed": "modal:inventory_discard_confirm",
	}


func _open_discard_dialog_for_item(item: Dictionary, count: int) -> void:
	if _discard_dialog == null or item.is_empty():
		return
	var item_id := str(item.get("item_id", ""))
	if item_id.is_empty() or not bool(item.get("droppable", true)):
		return
	var available := maxi(1, int(item.get("count", 1)))
	var normalized_count := clampi(count, 1, available)
	_pending_discard_item = item.duplicate(true)
	_pending_discard_count = normalized_count
	_pending_discard_available = available
	var root := get_parent()
	if root != null and root.has_method("finish_world_action_presentations"):
		root.finish_world_action_presentations()
	_discard_dialog.dialog_text = "丢弃 %s x%d 会在当前位置生成掉落容器。确定丢弃吗？" % [
		item.get("name", item_id),
		normalized_count,
	]
	_refresh_discard_quantity_controls(normalized_count, available)
	_discard_dialog.popup_centered()


func _confirm_pending_discard() -> void:
	if _pending_discard_item.is_empty():
		return
	var item_id := str(_pending_discard_item.get("item_id", ""))
	var count := _discard_quantity_value()
	var available := _current_inventory_count(item_id)
	if available <= 0:
		available = _pending_discard_available
	if count <= 0:
		_set_discard_quantity_error("请输入大于 0 的数量")
		return
	if count > available:
		_set_discard_quantity_error("数量不能超过当前持有的 %d" % available)
		return
	_pending_discard_item = {}
	_pending_discard_count = 0
	_pending_discard_available = 0
	if _discard_dialog != null:
		_discard_dialog.hide()
	_clear_discard_quantity_error()
	var root := get_parent()
	if root != null and root.has_method("drop_player_item"):
		root.drop_player_item(item_id, count)


func _build_discard_quantity_controls() -> void:
	if _discard_dialog == null:
		return
	var box := VBoxContainer.new()
	box.name = "DiscardQuantityBox"
	box.add_theme_constant_override("separation", 6)
	_discard_quantity_label = _label("DiscardQuantityLabel")
	_discard_quantity_label.text = "数量"
	_discard_quantity_input = LineEdit.new()
	_discard_quantity_input.name = "DiscardQuantityInput"
	_discard_quantity_input.custom_minimum_size = Vector2(88, 28)
	_discard_quantity_input.placeholder_text = "数量"
	_discard_quantity_input.text_changed.connect(func(_text: String) -> void:
		_refresh_discard_dialog_text(_discard_quantity_value())
		_clear_discard_quantity_error()
	, CONNECT_DEFERRED)
	_discard_quantity_input.text_submitted.connect(func(_text: String) -> void:
		_confirm_pending_discard()
	, CONNECT_DEFERRED)
	_discard_minus_button = _action_button("DiscardQuantityMinusButton", "-", "减少 1")
	_discard_minus_button.pressed.connect(func() -> void:
		_adjust_discard_quantity(-1)
	, CONNECT_DEFERRED)
	_discard_plus_button = _action_button("DiscardQuantityPlusButton", "+", "增加 1")
	_discard_plus_button.pressed.connect(func() -> void:
		_adjust_discard_quantity(1)
	, CONNECT_DEFERRED)
	_discard_max_button = _action_button("DiscardQuantityMaxButton", "最大", "设为最大数量")
	_discard_max_button.pressed.connect(func() -> void:
		_set_discard_quantity(_pending_discard_available)
	, CONNECT_DEFERRED)
	var row := HBoxContainer.new()
	row.name = "DiscardQuantityControls"
	row.add_theme_constant_override("separation", 4)
	row.add_child(_discard_minus_button)
	row.add_child(_discard_quantity_input)
	row.add_child(_discard_plus_button)
	row.add_child(_discard_max_button)
	_discard_error_label = _label("DiscardQuantityError")
	_discard_error_label.text = ""
	_discard_error_label.modulate = Color(1.0, 0.32, 0.26)
	box.add_child(_discard_quantity_label)
	box.add_child(row)
	box.add_child(_discard_error_label)
	_discard_dialog.add_child(box)


func _refresh_discard_quantity_controls(count: int, available: int) -> void:
	if _discard_quantity_input == null:
		return
	_discard_quantity_input.text = str(clampi(count, 1, maxi(1, available)))
	_refresh_discard_dialog_text(int(_discard_quantity_input.text))
	if _discard_quantity_label != null:
		_discard_quantity_label.text = "数量：1-%d" % maxi(1, available)
	if _discard_minus_button != null:
		_discard_minus_button.disabled = available <= 1
	if _discard_plus_button != null:
		_discard_plus_button.disabled = available <= 1
	if _discard_max_button != null:
		_discard_max_button.disabled = available <= 1
	_clear_discard_quantity_error()


func _discard_quantity_value() -> int:
	if _discard_quantity_input == null:
		return _pending_discard_count
	var text := _discard_quantity_input.text.strip_edges()
	if not text.is_valid_int():
		return 0
	return int(text)


func _set_discard_quantity(count: int) -> void:
	if _discard_quantity_input == null:
		return
	_discard_quantity_input.text = str(clampi(count, 1, maxi(1, _pending_discard_available)))
	_refresh_discard_dialog_text(int(_discard_quantity_input.text))
	_clear_discard_quantity_error()


func _adjust_discard_quantity(delta: int) -> void:
	_set_discard_quantity(_discard_quantity_value() + delta)


func _set_discard_quantity_error(message: String) -> void:
	if _discard_error_label != null:
		_discard_error_label.text = message


func _clear_discard_quantity_error() -> void:
	if _discard_error_label != null:
		_discard_error_label.text = ""


func _refresh_discard_dialog_text(count: int) -> void:
	if _discard_dialog == null or _pending_discard_item.is_empty():
		return
	var item_id := str(_pending_discard_item.get("item_id", ""))
	if item_id.is_empty():
		return
	_discard_dialog.dialog_text = "丢弃 %s x%d 会在当前位置生成掉落容器。确定丢弃吗？" % [
		_pending_discard_item.get("name", item_id),
		maxi(0, count),
	]


func _control_mouse_blocks_world(control: Control) -> bool:
	return control != null and control.mouse_filter == Control.MOUSE_FILTER_STOP


func _control_mouse_filter_name(control: Control) -> String:
	if control == null:
		return ""
	match control.mouse_filter:
		Control.MOUSE_FILTER_STOP:
			return "stop"
		Control.MOUSE_FILTER_PASS:
			return "pass"
		Control.MOUSE_FILTER_IGNORE:
			return "ignore"
		_:
			return str(control.mouse_filter)


func _current_inventory_count(item_id: String) -> int:
	for item in _array_or_empty(_last_snapshot.get("items", [])):
		var item_data: Dictionary = item
		if str(item_data.get("item_id", "")) == item_id:
			return int(item_data.get("count", 0))
	return 0


func _inventory_action_target(from_control: Control) -> String:
	if from_control != null and from_control.has_meta("inventory_action_target"):
		return str(from_control.get_meta("inventory_action_target"))
	return ""


func _drag_drop_count(item: Dictionary) -> int:
	var item_id: String = str(item.get("item_id", ""))
	var available: int = max(1, int(item.get("count", 1)))
	if _quantity_spin != null and str(_selected_item.get("item_id", "")) == item_id:
		return clampi(int(_quantity_spin.value), 1, available)
	return 1


func _can_reorder_inventory() -> bool:
	return _sort_mode == "order" and _category_filter == "all" and _search_text.is_empty()


func _drop_target_index(from_control: Control) -> int:
	if from_control != null and from_control.has_meta("inventory_index"):
		return int(from_control.get_meta("inventory_index"))
	if not _last_snapshot.is_empty():
		return _array_or_empty(_last_snapshot.get("inventory_order", [])).size()
	return 0


func _visible_items(items: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for item in items:
		var item_data: Dictionary = item
		if _category_filter != "all" and str(item_data.get("category", "")) != _category_filter:
			continue
		if not _search_matches(item_data):
			continue
		output.append(item_data)
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match _sort_mode:
			"order":
				var order_a: int = int(a.get("order_index", 0))
				var order_b: int = int(b.get("order_index", 0))
				if order_a == order_b:
					return str(a.get("item_id", "")) < str(b.get("item_id", ""))
				return order_a < order_b
			"weight":
				var weight_a: float = float(a.get("total_weight", 0.0))
				var weight_b: float = float(b.get("total_weight", 0.0))
				if is_equal_approx(weight_a, weight_b):
					return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
				return weight_a > weight_b
			"value":
				var value_a: int = int(a.get("total_value", 0))
				var value_b: int = int(b.get("total_value", 0))
				if value_a == value_b:
					return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
				return value_a > value_b
			_:
				return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
	)
	return output


func _search_matches(item: Dictionary) -> bool:
	if _search_text.is_empty():
		return true
	var haystack := "%s %s %s %s %s" % [
		item.get("item_id", ""),
		item.get("name", ""),
		item.get("description", ""),
		item.get("category", ""),
		item.get("category_label", ""),
	]
	return haystack.to_lower().contains(_search_text)


func _apply_detail(item: Dictionary) -> void:
	if _detail_label == null:
		return
	_selected_item = item.duplicate(true)
	if item.is_empty():
		_detail_label.text = "选择物品查看详情"
		_update_action_buttons({})
		return
	var rarity := str(item.get("rarity", ""))
	var rarity_suffix := " | %s" % rarity if not rarity.is_empty() else ""
	var slots: Array = item.get("equip_slots", [])
	var slot_suffix := " | 槽位 %s" % ", ".join(slots) if not slots.is_empty() else ""
	var stack_suffix := " | 堆叠 %d" % int(item.get("max_stack", 1)) if bool(item.get("stackable", false)) else ""
	var deconstruct_suffix := _deconstruct_requirements_text(item)
	var deconstruct_preview_suffix := _deconstruct_preview_text(item)
	var deconstruct_unavailable_suffix := _deconstruct_unavailable_text(item)
	var description := str(item.get("description", ""))
	_detail_label.text = "%s | %s | 单重 %.2f kg | 总重 %.2f kg | 单价 %d | 总价 %d%s%s%s%s%s%s%s" % [
		item.get("name", item.get("item_id", "")),
		item.get("category_label", "杂项"),
		float(item.get("unit_weight", 0.0)),
		float(item.get("total_weight", 0.0)),
		int(item.get("value", 0)),
		int(item.get("total_value", 0)),
		rarity_suffix,
		slot_suffix,
		stack_suffix,
		deconstruct_suffix,
		deconstruct_preview_suffix,
		deconstruct_unavailable_suffix,
		"\n%s" % description if not description.is_empty() else "",
	]
	_update_action_buttons(item)


func _deconstruct_requirements_text(item: Dictionary) -> String:
	if not bool(item.get("deconstructable", false)):
		return ""
	var requirements: Dictionary = _dictionary_or_empty(item.get("deconstruct_requirements", {}))
	var parts: Array[String] = []
	var required_tools: Array = _array_or_empty(requirements.get("required_tools", []))
	if not required_tools.is_empty():
		parts.append("工具 %s" % ", ".join(_deconstruct_tool_requirement_texts(required_tools)))
	var station := str(requirements.get("required_station", "none"))
	if station not in ["", "none"]:
		parts.append("工作台 %s" % station)
	if parts.is_empty():
		return ""
	var source_suffix := _deconstruct_tool_sources_text(required_tools)
	return " | 拆解要求 %s%s" % [" / ".join(parts), source_suffix]


func _deconstruct_tool_requirement_texts(required_tools: Array) -> Array[String]:
	var output: Array[String] = []
	for entry in required_tools:
		if typeof(entry) != TYPE_DICTIONARY:
			output.append(str(entry))
			continue
		var tool: Dictionary = _dictionary_or_empty(entry)
		var label := str(tool.get("name", tool.get("item_id", "")))
		if label.is_empty():
			continue
		var required: int = max(1, int(tool.get("required", 1)))
		if required > 1:
			label = "%s x%d" % [label, required]
		if bool(tool.get("consume_on_deconstruct", false)):
			label = "%s(消耗 %d)" % [label, max(1, int(tool.get("consume_count", 1)))]
		var durability_cost: float = max(0.0, float(tool.get("durability_cost", 0.0)))
		if durability_cost > 0.0:
			label = "%s(耐久 %.1f/-%.1f)" % [label, float(tool.get("available_durability", 0.0)), durability_cost]
		output.append(label)
	return output


func _deconstruct_tool_sources_text(required_tools: Array) -> String:
	var parts: Array[String] = []
	var missing_count := 0
	for entry in required_tools:
		var tool: Dictionary = _dictionary_or_empty(entry)
		if not bool(tool.get("consume_on_deconstruct", false)):
			continue
		missing_count += max(0, int(tool.get("missing_count", 0)))
		for source in _array_or_empty(tool.get("consumption_sources", [])):
			var source_data: Dictionary = _dictionary_or_empty(source)
			var label := str(source_data.get("label", source_data.get("source", ""))).strip_edges()
			var count := int(source_data.get("count", 0))
			if label.is_empty() or count <= 0:
				continue
			parts.append("%s x%d" % [label, count])
	if missing_count > 0:
		parts.append("缺 %d" % missing_count)
	if parts.is_empty():
		return ""
	return " | 拆解工具来源 %s" % ", ".join(parts)


func _deconstruct_unavailable_text(item: Dictionary) -> String:
	var unavailable: Dictionary = _dictionary_or_empty(item.get("deconstruct_unavailable", {}))
	var text := str(unavailable.get("text", "")).strip_edges()
	if text.is_empty():
		return ""
	return " | 拆解不可用 %s" % text


func _deconstruct_context_tooltip(item: Dictionary) -> String:
	if bool(item.get("deconstructable", false)) and int(item.get("count", 0)) > 0:
		var unavailable: Dictionary = _dictionary_or_empty(item.get("deconstruct_unavailable", {}))
		var warning := str(unavailable.get("text", "")).strip_edges()
		return "拆解选中的数量" if warning.is_empty() else "拆解选中的数量；%s" % warning
	var unavailable_text := str(_dictionary_or_empty(item.get("deconstruct_unavailable", {})).get("text", "")).strip_edges()
	return unavailable_text if not unavailable_text.is_empty() else "选中的物品不能拆解"


func _deconstruct_preview_text(item: Dictionary) -> String:
	if not bool(item.get("deconstructable", false)):
		return ""
	var preview: Dictionary = _dictionary_or_empty(item.get("deconstruct_preview", {}))
	var entries: Array = _array_or_empty(preview.get("entries", []))
	if entries.is_empty():
		return ""
	var parts: Array[String] = []
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var name := str(entry_data.get("name", entry_data.get("item_id", "")))
		var total_count := int(entry_data.get("total_count", 0))
		if name.is_empty() or total_count <= 0:
			continue
		parts.append("%s x%d" % [name, total_count])
	if parts.is_empty():
		return ""
	return " | 拆解产物 %s" % ", ".join(parts)


func _update_action_buttons(item: Dictionary) -> void:
	if _use_button == null or _equip_button == null or _drop_button == null or _quantity_spin == null:
		return
	var usable: bool = bool(item.get("usable", false))
	var equippable: bool = not _array_or_empty(item.get("equip_slots", [])).is_empty()
	var droppable: bool = bool(item.get("droppable", true)) and int(item.get("count", 0)) > 0
	var item_name: String = str(item.get("name", item.get("item_id", "")))
	var ap_cost: float = float(item.get("use_ap_cost", 0.0))
	var count: int = max(1, int(item.get("count", 1)))
	_quantity_spin.max_value = count
	_quantity_spin.value = clampi(int(_quantity_spin.value), 1, count)
	_quantity_spin.editable = count > 1
	_use_button.disabled = not usable
	_use_button.tooltip_text = "使用 %s | AP %.0f" % [item_name, ap_cost] if usable else "选中的物品不能使用"
	_equip_button.disabled = not equippable
	_equip_button.tooltip_text = "装备 %s" % item_name if equippable else "选中的物品不能装备"
	_drop_button.disabled = not droppable
	_drop_button.tooltip_text = "丢弃 %s x%d" % [item_name, int(_quantity_spin.value)] if droppable else "选中的物品不能丢弃"


func _selected_visible_item(items: Array[Dictionary]) -> Dictionary:
	var selected_id: String = str(_selected_item.get("item_id", ""))
	if not selected_id.is_empty():
		for item in items:
			var item_data: Dictionary = item
			if str(item_data.get("item_id", "")) == selected_id:
				return item_data
	return items[0]


func _add_filter_button(node_name: String, text: String, category: String) -> void:
	var button := _toolbar_button(node_name, text, "显示%s物品" % text)
	button.pressed.connect(func() -> void:
		_category_filter = category
		if not _last_snapshot.is_empty():
			apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	_filter_box.add_child(button)


func _add_sort_button(node_name: String, text: String, mode: String) -> void:
	var button := _toolbar_button(node_name, text, "按%s排序" % text)
	button.pressed.connect(func() -> void:
		_sort_mode = mode
		if not _last_snapshot.is_empty():
			apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	_sort_box.add_child(button)


func _toolbar_button(node_name: String, text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tooltip
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(54, 28)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _action_button(node_name: String, text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(54, 28)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _refresh_filter_buttons() -> void:
	if _filter_box == null:
		return
	for child in _filter_box.get_children():
		if child is Button:
			var button := child as Button
			match button.name:
				"FilterAllButton":
					button.button_pressed = _category_filter == "all"
				"FilterEquipmentButton":
					button.button_pressed = _category_filter == "equipment"
				"FilterConsumableButton":
					button.button_pressed = _category_filter == "consumable"
				"FilterAmmoButton":
					button.button_pressed = _category_filter == "ammo"
				"FilterMaterialButton":
					button.button_pressed = _category_filter == "material"


func _refresh_sort_buttons() -> void:
	if _sort_box == null:
		return
	for child in _sort_box.get_children():
		if child is Button:
			var button := child as Button
			match button.name:
				"SortOrderButton":
					button.button_pressed = _sort_mode == "order"
				"SortNameButton":
					button.button_pressed = _sort_mode == "name"
				"SortWeightButton":
					button.button_pressed = _sort_mode == "weight"
				"SortValueButton":
					button.button_pressed = _sort_mode == "value"


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear_items() -> void:
	for child in _items_box.get_children():
		_items_box.remove_child(child)
		child.free()


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	for entry in _array_or_empty(value):
		output.append(str(entry))
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
