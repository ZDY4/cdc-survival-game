extends Control

signal close_requested
signal transfer_requested(source: String, item_id: String, count: int)

var _panel: PanelContainer
var _title_label: Label
var _close_button: Button
var _summary_label: Label
var _feedback_label: Label
var _detail_label: Label
var _quantity_spin: SpinBox
var _transfer_button: Button
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
		_title_label.text = "Container %s" % snapshot.get("container_id", "")
		_summary_label.text = "容器资源不可用: %s" % snapshot.get("error", "unknown")
		_apply_feedback({})
		_apply_detail({}, "")
		_clear_items()
		return

	_title_label.text = str(snapshot.get("display_name", snapshot.get("container_id", "")))
	_summary_label.text = "容器 %d 类物品 | 背包 %d 类物品" % [
		snapshot.get("items", []).size(),
		snapshot.get("player_items", []).size(),
	]
	_apply_feedback(_dictionary_or_empty(snapshot.get("feedback", {})))
	_clear_box(_items_box)
	_clear_box(_player_items_box)
	var items: Array = snapshot.get("items", [])
	if items.is_empty():
		_items_box.add_child(_empty_line())
	else:
		for item in items:
			var item_data: Dictionary = item
			_items_box.add_child(_item_line(item_data, "container"))
	var player_items: Array = snapshot.get("player_items", [])
	if player_items.is_empty():
		_player_items_box.add_child(_empty_inventory_line())
	else:
		for item in player_items:
			var item_data: Dictionary = item
			_player_items_box.add_child(_item_line(item_data, "player"))
	_apply_detail(_default_detail_item(items, player_items), "container" if not items.is_empty() else "player")


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "ContainerPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -560
	_panel.offset_right = -16
	_panel.offset_top = -285
	_panel.offset_bottom = -16
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "ContainerLines"
	box.add_theme_constant_override("separation", 7)
	_panel.add_child(box)

	_title_label = _label("TitleLine")
	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "X"
	_close_button.tooltip_text = "关闭容器"
	_close_button.custom_minimum_size = Vector2(28, 24)
	_close_button.pressed.connect(func() -> void:
		close_requested.emit()
	)
	_summary_label = _label("SummaryLine")
	_feedback_label = _label("FeedbackLine")
	_detail_label = _label("DetailLine")
	var transfer_controls := HBoxContainer.new()
	transfer_controls.name = "TransferControls"
	transfer_controls.add_theme_constant_override("separation", 8)
	_quantity_spin = SpinBox.new()
	_quantity_spin.name = "QuantitySpin"
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = 1
	_quantity_spin.step = 1
	_quantity_spin.value = 1
	_quantity_spin.custom_minimum_size = Vector2(84, 0)
	_transfer_button = Button.new()
	_transfer_button.name = "TransferButton"
	_transfer_button.text = "转移"
	_transfer_button.tooltip_text = "转移选中的物品数量"
	_transfer_button.disabled = true
	_transfer_button.pressed.connect(func() -> void:
		if _selected_item_id.is_empty() or _selected_source.is_empty():
			return
		transfer_requested.emit(_selected_source, _selected_item_id, int(_quantity_spin.value))
	)
	transfer_controls.add_child(_quantity_spin)
	transfer_controls.add_child(_transfer_button)
	var columns := HBoxContainer.new()
	columns.name = "ItemColumns"
	columns.add_theme_constant_override("separation", 12)
	var container_column := VBoxContainer.new()
	container_column.name = "ContainerColumn"
	container_column.custom_minimum_size = Vector2(250, 0)
	var container_title := _label("ContainerColumnTitle")
	container_title.text = "容器"
	var container_scroll := ScrollContainer.new()
	container_scroll.name = "ContainerScroll"
	container_scroll.custom_minimum_size = Vector2(250, 150)
	container_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_box = VBoxContainer.new()
	_items_box.name = "ItemLines"
	_items_box.add_theme_constant_override("separation", 4)
	var player_column := VBoxContainer.new()
	player_column.name = "PlayerColumn"
	player_column.custom_minimum_size = Vector2(250, 0)
	var player_title := _label("PlayerColumnTitle")
	player_title.text = "背包"
	var player_scroll := ScrollContainer.new()
	player_scroll.name = "PlayerScroll"
	player_scroll.custom_minimum_size = Vector2(250, 150)
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_player_items_box = VBoxContainer.new()
	_player_items_box.name = "PlayerItemLines"
	_player_items_box.add_theme_constant_override("separation", 4)
	container_column.add_child(container_title)
	container_scroll.add_child(_items_box)
	container_column.add_child(container_scroll)
	player_column.add_child(player_title)
	player_scroll.add_child(_player_items_box)
	player_column.add_child(player_scroll)
	columns.add_child(container_column)
	columns.add_child(player_column)
	box.add_child(_title_label)
	box.add_child(_close_button)
	box.add_child(_summary_label)
	box.add_child(_feedback_label)
	box.add_child(_detail_label)
	box.add_child(transfer_controls)
	box.add_child(columns)


func _item_line(item: Dictionary, source: String) -> Button:
	var button := Button.new()
	button.name = "Item_%s" % item.get("item_id", "unknown")
	var rarity := str(item.get("rarity", ""))
	var rarity_suffix := " | %s" % rarity if not rarity.is_empty() else ""
	button.text = "%s x%d | %.1f kg%s" % [
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
		float(item.get("total_weight", 0.0)),
		rarity_suffix,
	]
	button.tooltip_text = str(item.get("description", ""))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_apply_detail(item.duplicate(true), source)
	)
	return button


func _empty_line() -> Label:
	var label := _label("EmptyLine")
	label.text = "容器为空"
	return label


func _empty_inventory_line() -> Label:
	var label := _label("EmptyInventoryLine")
	label.text = "背包为空"
	return label


func _apply_feedback(feedback: Dictionary) -> void:
	if _feedback_label == null:
		return
	var text := str(feedback.get("text", ""))
	_feedback_label.visible = not text.is_empty()
	_feedback_label.text = text


func _apply_detail(item: Dictionary, source: String) -> void:
	if _detail_label == null:
		return
	if item.is_empty():
		_detail_label.text = "选择物品查看详情"
		_selected_source = ""
		_selected_item_id = ""
		_update_transfer_controls({}, "")
		return
	var rarity := str(item.get("rarity", ""))
	var rarity_suffix := " | %s" % rarity if not rarity.is_empty() else ""
	var description := str(item.get("description", ""))
	_detail_label.text = "%s：%s x%d | 单重 %.1f kg | 总重 %.1f kg%s%s" % [
		_source_display(source),
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
		float(item.get("unit_weight", 0.0)),
		float(item.get("total_weight", 0.0)),
		rarity_suffix,
		"\n%s" % description if not description.is_empty() else "",
	]
	_selected_source = source
	_selected_item_id = str(item.get("item_id", ""))
	_update_transfer_controls(item, source)


func _update_transfer_controls(item: Dictionary, source: String) -> void:
	if _quantity_spin == null or _transfer_button == null:
		return
	var available := maxi(1, int(item.get("count", 1)))
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = available
	_quantity_spin.value = clampi(int(_quantity_spin.value), 1, available)
	var item_id := str(item.get("item_id", ""))
	_transfer_button.disabled = item.is_empty() or item_id.is_empty() or source.is_empty()
	match source:
		"container":
			_transfer_button.text = "拿取"
		"player":
			_transfer_button.text = "存放"
		_:
			_transfer_button.text = "转移"


func _default_detail_item(items: Array, player_items: Array) -> Dictionary:
	if not items.is_empty():
		return _dictionary_or_empty(items[0])
	if not player_items.is_empty():
		return _dictionary_or_empty(player_items[0])
	return {}


func _source_display(source: String) -> String:
	match source:
		"container":
			return "容器"
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
