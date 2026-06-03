extends Control

signal close_requested

var _panel: PanelContainer
var _title_label: Label
var _close_button: Button
var _summary_label: Label
var _feedback_label: Label
var _items_box: VBoxContainer
var _player_items_box: VBoxContainer


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
			_items_box.add_child(_item_line(item_data))
	var player_items: Array = snapshot.get("player_items", [])
	if player_items.is_empty():
		_player_items_box.add_child(_empty_inventory_line())
	else:
		for item in player_items:
			var item_data: Dictionary = item
			_player_items_box.add_child(_item_line(item_data))


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
	var columns := HBoxContainer.new()
	columns.name = "ItemColumns"
	columns.add_theme_constant_override("separation", 12)
	var container_column := VBoxContainer.new()
	container_column.name = "ContainerColumn"
	container_column.custom_minimum_size = Vector2(250, 0)
	var container_title := _label("ContainerColumnTitle")
	container_title.text = "容器"
	_items_box = VBoxContainer.new()
	_items_box.name = "ItemLines"
	_items_box.add_theme_constant_override("separation", 4)
	var player_column := VBoxContainer.new()
	player_column.name = "PlayerColumn"
	player_column.custom_minimum_size = Vector2(250, 0)
	var player_title := _label("PlayerColumnTitle")
	player_title.text = "背包"
	_player_items_box = VBoxContainer.new()
	_player_items_box.name = "PlayerItemLines"
	_player_items_box.add_theme_constant_override("separation", 4)
	container_column.add_child(container_title)
	container_column.add_child(_items_box)
	player_column.add_child(player_title)
	player_column.add_child(_player_items_box)
	columns.add_child(container_column)
	columns.add_child(player_column)
	box.add_child(_title_label)
	box.add_child(_close_button)
	box.add_child(_summary_label)
	box.add_child(_feedback_label)
	box.add_child(columns)


func _item_line(item: Dictionary) -> Label:
	var label := _label("Item_%s" % item.get("item_id", "unknown"))
	label.text = "%s x%d" % [
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
	]
	return label


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
