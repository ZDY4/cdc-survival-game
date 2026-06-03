extends Control

signal close_requested
signal trade_requested(source: String, item_id: String, count: int)

var _panel: PanelContainer
var _title_label: Label
var _close_button: Button
var _summary_label: Label
var _detail_label: Label
var _quantity_spin: SpinBox
var _trade_button: Button
var _items_box: VBoxContainer
var _player_items_box: VBoxContainer
var _selected_source: String = ""
var _selected_item_id: String = ""


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()
	visible = false


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	var active: bool = bool(snapshot.get("active", false))
	visible = active
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if _panel != null:
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if not active:
		return

	if snapshot.has("error"):
		_title_label.text = "Trade %s" % snapshot.get("shop_id", "")
		_summary_label.text = "交易资源不可用: %s" % snapshot.get("error", "unknown")
		_clear_items()
		return

	var target_name: String = str(snapshot.get("target_name", ""))
	_title_label.text = "%s 的交易" % target_name if not target_name.is_empty() else "交易"
	_summary_label.text = "玩家资金 %d | 店铺资金 %d | 买价 x%.1f | 卖价 x%.1f" % [
		int(snapshot.get("player_money", 0)),
		int(snapshot.get("money", 0)),
		float(snapshot.get("buy_price_modifier", 1.0)),
		float(snapshot.get("sell_price_modifier", 1.0)),
	]
	_clear_box(_items_box)
	_clear_box(_player_items_box)
	var shop_items: Array = snapshot.get("items", [])
	for item in shop_items:
		var item_data: Dictionary = item
		_items_box.add_child(_item_line(item_data, "shop"))
	if shop_items.is_empty():
		_items_box.add_child(_empty_line("店铺库存为空"))
	var player_items: Array = snapshot.get("player_items", [])
	for item in player_items:
		var item_data: Dictionary = item
		_player_items_box.add_child(_item_line(item_data, "player"))
	if player_items.is_empty():
		_player_items_box.add_child(_empty_line("背包为空"))
	_apply_detail(_default_detail_item(shop_items, player_items), "shop" if not shop_items.is_empty() else "player")


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "TradePanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.offset_left = -620
	_panel.offset_right = -16
	_panel.offset_top = -210
	_panel.offset_bottom = 210
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "TradeLines"
	box.add_theme_constant_override("separation", 7)
	_panel.add_child(box)

	_title_label = _label("TitleLine")
	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "X"
	_close_button.tooltip_text = "关闭交易"
	_close_button.custom_minimum_size = Vector2(28, 24)
	_close_button.pressed.connect(func() -> void:
		close_requested.emit()
	)
	_summary_label = _label("SummaryLine")
	_detail_label = _label("DetailLine")
	var trade_controls := HBoxContainer.new()
	trade_controls.name = "TradeControls"
	trade_controls.add_theme_constant_override("separation", 8)
	_quantity_spin = SpinBox.new()
	_quantity_spin.name = "QuantitySpin"
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = 1
	_quantity_spin.step = 1
	_quantity_spin.value = 1
	_quantity_spin.custom_minimum_size = Vector2(84, 0)
	_trade_button = Button.new()
	_trade_button.name = "TradeButton"
	_trade_button.text = "交易"
	_trade_button.disabled = true
	_trade_button.pressed.connect(func() -> void:
		if _selected_source.is_empty() or _selected_item_id.is_empty():
			return
		trade_requested.emit(_selected_source, _selected_item_id, int(_quantity_spin.value))
	)
	trade_controls.add_child(_quantity_spin)
	trade_controls.add_child(_trade_button)
	var columns := HBoxContainer.new()
	columns.name = "TradeColumns"
	columns.add_theme_constant_override("separation", 12)
	var shop_column := VBoxContainer.new()
	shop_column.name = "ShopColumn"
	shop_column.custom_minimum_size = Vector2(280, 0)
	var shop_title := _label("ShopColumnTitle")
	shop_title.text = "店铺"
	var shop_scroll := ScrollContainer.new()
	shop_scroll.name = "ShopScroll"
	shop_scroll.custom_minimum_size = Vector2(280, 220)
	shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_box = VBoxContainer.new()
	_items_box.name = "ItemLines"
	_items_box.add_theme_constant_override("separation", 4)
	var player_column := VBoxContainer.new()
	player_column.name = "PlayerColumn"
	player_column.custom_minimum_size = Vector2(280, 0)
	var player_title := _label("PlayerColumnTitle")
	player_title.text = "背包"
	var player_scroll := ScrollContainer.new()
	player_scroll.name = "PlayerScroll"
	player_scroll.custom_minimum_size = Vector2(280, 220)
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_player_items_box = VBoxContainer.new()
	_player_items_box.name = "PlayerItemLines"
	_player_items_box.add_theme_constant_override("separation", 4)
	shop_column.add_child(shop_title)
	shop_scroll.add_child(_items_box)
	shop_column.add_child(shop_scroll)
	player_column.add_child(player_title)
	player_scroll.add_child(_player_items_box)
	player_column.add_child(player_scroll)
	columns.add_child(shop_column)
	columns.add_child(player_column)
	box.add_child(_title_label)
	box.add_child(_close_button)
	box.add_child(_summary_label)
	box.add_child(_detail_label)
	box.add_child(trade_controls)
	box.add_child(columns)


func _item_line(item: Dictionary, source: String) -> Button:
	var button := Button.new()
	button.name = "Item_%s" % item.get("item_id", "unknown")
	button.text = "%s x%d | %d" % [
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
		int(item.get("price", 0)),
	]
	button.tooltip_text = str(item.get("description", ""))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_apply_detail(item.duplicate(true), source)
	)
	return button


func _empty_line(text: String) -> Label:
	var label := _label("EmptyLine")
	label.text = text
	return label


func _apply_detail(item: Dictionary, source: String) -> void:
	if _detail_label == null:
		return
	if item.is_empty():
		_detail_label.text = "选择物品查看价格"
		_selected_source = ""
		_selected_item_id = ""
		_update_trade_controls({}, "")
		return
	var description := str(item.get("description", ""))
	_selected_source = source
	_selected_item_id = str(item.get("item_id", ""))
	_update_trade_controls(item, source)
	_detail_label.text = "%s：%s x%d | 单价 %d | 小计 %d%s" % [
		_source_display(source),
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
		int(item.get("price", 0)),
		int(item.get("price", 0)) * int(_quantity_spin.value if _quantity_spin != null else 1),
		"\n%s" % description if not description.is_empty() else "",
	]


func _update_trade_controls(item: Dictionary, source: String) -> void:
	if _quantity_spin == null or _trade_button == null:
		return
	var available := maxi(1, int(item.get("count", 1)))
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = available
	_quantity_spin.value = clampi(int(_quantity_spin.value), 1, available)
	var item_id := str(item.get("item_id", ""))
	_trade_button.disabled = item.is_empty() or item_id.is_empty() or source.is_empty()
	match source:
		"shop":
			_trade_button.text = "购买"
		"player":
			_trade_button.text = "出售"
		_:
			_trade_button.text = "交易"


func _default_detail_item(shop_items: Array, player_items: Array) -> Dictionary:
	if not shop_items.is_empty():
		return _dictionary_or_empty(shop_items[0])
	if not player_items.is_empty():
		return _dictionary_or_empty(player_items[0])
	return {}


func _source_display(source: String) -> String:
	match source:
		"shop":
			return "店铺"
		"player":
			return "背包"
		_:
			return source


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear_items() -> void:
	_clear_box(_items_box)
	_clear_box(_player_items_box)


func _clear_box(box: VBoxContainer) -> void:
	if box == null:
		return
	for child in box.get_children():
		box.remove_child(child)
		child.free()


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
