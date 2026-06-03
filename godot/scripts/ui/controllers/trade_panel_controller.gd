extends Control

signal close_requested

var _panel: PanelContainer
var _title_label: Label
var _close_button: Button
var _summary_label: Label
var _items_box: VBoxContainer


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
	_summary_label.text = "资金 %d | 买价 x%.1f | 卖价 x%.1f" % [
		int(snapshot.get("money", 0)),
		float(snapshot.get("buy_price_modifier", 1.0)),
		float(snapshot.get("sell_price_modifier", 1.0)),
	]
	_clear_items()
	for item in snapshot.get("items", []):
		var item_data: Dictionary = item
		_items_box.add_child(_item_line(item_data))


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "TradePanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.offset_left = -390
	_panel.offset_right = -16
	_panel.offset_top = -135
	_panel.offset_bottom = 165
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
	_items_box = VBoxContainer.new()
	_items_box.name = "ItemLines"
	_items_box.add_theme_constant_override("separation", 4)
	box.add_child(_title_label)
	box.add_child(_close_button)
	box.add_child(_summary_label)
	box.add_child(_items_box)


func _item_line(item: Dictionary) -> Label:
	var label := _label("Item_%s" % item.get("item_id", "unknown"))
	label.text = "%s x%d | %d" % [
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
		int(item.get("price", 0)),
	]
	return label


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
