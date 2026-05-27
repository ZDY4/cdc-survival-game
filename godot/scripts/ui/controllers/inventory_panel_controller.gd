extends Control

var _panel: PanelContainer
var _title_label: Label
var _summary_label: Label
var _items_box: VBoxContainer


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	_title_label.text = "%s 的背包" % snapshot.get("owner_name", "")
	_summary_label.text = "%d 类物品 | %.1f kg" % [
		int(snapshot.get("item_count", 0)),
		float(snapshot.get("total_weight", 0.0)),
	]
	_clear_items()
	for item in snapshot.get("items", []):
		var item_data: Dictionary = item
		_items_box.add_child(_item_line(item_data))


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
	_items_box = VBoxContainer.new()
	_items_box.name = "ItemLines"
	_items_box.add_theme_constant_override("separation", 4)
	box.add_child(_title_label)
	box.add_child(_summary_label)
	box.add_child(_items_box)


func _item_line(item: Dictionary) -> Label:
	var label := _label("Item_%s" % item.get("item_id", "unknown"))
	label.text = "%s x%d | %.1f kg" % [
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
		float(item.get("total_weight", 0.0)),
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
