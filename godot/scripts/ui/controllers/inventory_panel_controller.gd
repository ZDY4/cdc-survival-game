extends Control

var _panel: PanelContainer
var _title_label: Label
var _summary_label: Label
var _search_box: LineEdit
var _filter_box: HBoxContainer
var _sort_box: HBoxContainer
var _detail_label: Label
var _use_button: Button
var _items_box: VBoxContainer
var _category_filter: String = "all"
var _sort_mode: String = "order"
var _search_text: String = ""
var _last_snapshot: Dictionary = {}
var _selected_item: Dictionary = {}


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	_last_snapshot = snapshot.duplicate(true)
	_title_label.text = "%s 的背包" % snapshot.get("owner_name", "")
	_summary_label.text = "%d 类物品 | %.1f kg" % [
		int(snapshot.get("item_count", 0)),
		float(snapshot.get("total_weight", 0.0)),
	]
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
	_use_button = _toolbar_button("UseSelectedButton", "使用", "使用选中的物品")
	_use_button.disabled = true
	_use_button.pressed.connect(func() -> void:
		if _selected_item.is_empty():
			return
		var root := get_parent()
		if root != null and root.has_method("use_player_item"):
			root.use_player_item(str(_selected_item.get("item_id", "")))
	, CONNECT_DEFERRED)
	var item_scroll := ScrollContainer.new()
	item_scroll.name = "ItemScroll"
	item_scroll.custom_minimum_size = Vector2(320, 96)
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_box = VBoxContainer.new()
	_items_box.name = "ItemLines"
	_items_box.add_theme_constant_override("separation", 4)
	box.add_child(_title_label)
	box.add_child(_summary_label)
	box.add_child(_search_box)
	box.add_child(_filter_box)
	box.add_child(_sort_box)
	box.add_child(_detail_label)
	box.add_child(_use_button)
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
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_apply_detail(item.duplicate(true))
	)
	return button


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
		_update_use_button({})
		return
	var rarity := str(item.get("rarity", ""))
	var rarity_suffix := " | %s" % rarity if not rarity.is_empty() else ""
	var slots: Array = item.get("equip_slots", [])
	var slot_suffix := " | 槽位 %s" % ", ".join(slots) if not slots.is_empty() else ""
	var stack_suffix := " | 堆叠 %d" % int(item.get("max_stack", 1)) if bool(item.get("stackable", false)) else ""
	var description := str(item.get("description", ""))
	_detail_label.text = "%s | %s | 单重 %.2f kg | 总重 %.2f kg | 单价 %d | 总价 %d%s%s%s%s" % [
		item.get("name", item.get("item_id", "")),
		item.get("category_label", "杂项"),
		float(item.get("unit_weight", 0.0)),
		float(item.get("total_weight", 0.0)),
		int(item.get("value", 0)),
		int(item.get("total_value", 0)),
		rarity_suffix,
		slot_suffix,
		stack_suffix,
		"\n%s" % description if not description.is_empty() else "",
	]
	_update_use_button(item)


func _update_use_button(item: Dictionary) -> void:
	if _use_button == null:
		return
	var usable: bool = bool(item.get("usable", false))
	var item_name: String = str(item.get("name", item.get("item_id", "")))
	var ap_cost: float = float(item.get("use_ap_cost", 0.0))
	_use_button.disabled = not usable
	_use_button.tooltip_text = "使用 %s | AP %.0f" % [item_name, ap_cost] if usable else "选中的物品不能使用"


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
