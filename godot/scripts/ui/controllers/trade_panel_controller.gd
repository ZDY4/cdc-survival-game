extends Control

const MediaTextureLoader = preload("res://scripts/ui/media_texture_loader.gd")
const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")

signal close_requested
signal trade_requested(source: String, item_id: String, count: int, stack_index: int)
signal trade_cart_confirmed(entries: Array)

const CONTEXT_TRADE := 1
const CONTEXT_QUEUE := 2
const CONTEXT_INSPECT := 3

var _panel: PanelContainer
var _title_label: Label
var _close_button: Button
var _summary_label: Label
var _feedback_label: Label
var _detail_label: Label
var _quantity_spin: SpinBox
var _trade_button: Button
var _queue_button: Button
var _clear_cart_button: Button
var _confirm_cart_button: Button
var _cart_label: Label
var _cart_items_box: VBoxContainer
var _equipment_sell_dialog: ConfirmationDialog
var _context_menu: PopupMenu
var _items_box: VBoxContainer
var _player_items_box: VBoxContainer
var _context_item: Dictionary = {}
var _context_source := ""
var _selected_source: String = ""
var _selected_item_id: String = ""
var _selected_item_snapshot: Dictionary = {}
var _cart_entries: Array[Dictionary] = []
var _player_money: int = 0
var _shop_money: int = 0
var _trade_allowed: bool = true
var _trade_block_reason: String = ""
var _reason_catalog := ReasonCatalog.new()


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
		if _equipment_sell_dialog != null:
			_equipment_sell_dialog.hide()
		if _context_menu != null:
			_context_menu.hide()
		_context_item = {}
		_context_source = ""
		_trade_allowed = true
		_trade_block_reason = ""
		_clear_cart()
		return

	if snapshot.has("error"):
		_title_label.text = "Trade %s" % snapshot.get("shop_id", "")
		_summary_label.text = "交易资源不可用: %s" % snapshot.get("error", "unknown")
		_apply_feedback({})
		if _context_menu != null:
			_context_menu.hide()
		_context_item = {}
		_context_source = ""
		_clear_cart()
		_clear_items()
		return

	var target_name: String = str(snapshot.get("target_name", ""))
	_player_money = int(snapshot.get("player_money", 0))
	_shop_money = int(snapshot.get("money", 0))
	var permission: Dictionary = _dictionary_or_empty(snapshot.get("permission", {}))
	_trade_allowed = bool(permission.get("allowed", true))
	_trade_block_reason = str(permission.get("text", ""))
	_title_label.text = "%s 的交易" % target_name if not target_name.is_empty() else "交易"
	_summary_label.text = "玩家资金 %d | 店铺资金 %d | 买价 x%.1f | 卖价 x%.1f" % [
		_player_money,
		_shop_money,
		float(snapshot.get("buy_price_modifier", 1.0)),
		float(snapshot.get("sell_price_modifier", 1.0)),
	]
	_apply_feedback(_dictionary_or_empty(snapshot.get("feedback", {})))
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
		_player_items_box.add_child(_item_line(item_data, str(item_data.get("source", "player"))))
	if player_items.is_empty():
		_player_items_box.add_child(_empty_line("背包为空"))
	var default_item: Dictionary = _default_detail_item(shop_items, player_items)
	var default_source: String = "shop" if not shop_items.is_empty() else str(default_item.get("source", "player"))
	_apply_detail(default_item, default_source)
	_update_cart_line()


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
	_feedback_label = _label("FeedbackLine")
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
		if not _item_can_trade(_selected_item_snapshot, _selected_source):
			return
		if _requires_equipment_sell_confirmation(_selected_source):
			_open_equipment_sell_dialog()
			return
		_emit_selected_trade()
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
	box.add_child(_feedback_label)
	box.add_child(_detail_label)
	box.add_child(trade_controls)
	_cart_label = _label("CartLine")
	_cart_label.text = "购物车为空"
	var cart_controls := HBoxContainer.new()
	cart_controls.name = "CartControls"
	cart_controls.add_theme_constant_override("separation", 8)
	_queue_button = Button.new()
	_queue_button.name = "QueueButton"
	_queue_button.text = "加入购物车"
	_queue_button.disabled = true
	_queue_button.pressed.connect(func() -> void:
		_queue_selected_item()
	)
	_clear_cart_button = Button.new()
	_clear_cart_button.name = "ClearCartButton"
	_clear_cart_button.text = "清空"
	_clear_cart_button.disabled = true
	_clear_cart_button.pressed.connect(func() -> void:
		_clear_cart()
	)
	_confirm_cart_button = Button.new()
	_confirm_cart_button.name = "ConfirmCartButton"
	_confirm_cart_button.text = "确认购物车"
	_confirm_cart_button.disabled = true
	_confirm_cart_button.pressed.connect(func() -> void:
		if _cart_entries.is_empty():
			return
		trade_cart_confirmed.emit(_cart_entries.duplicate(true))
		_clear_cart()
	)
	cart_controls.add_child(_queue_button)
	cart_controls.add_child(_clear_cart_button)
	cart_controls.add_child(_confirm_cart_button)
	var cart_drop_zones := HBoxContainer.new()
	cart_drop_zones.name = "CartDropZones"
	cart_drop_zones.add_theme_constant_override("separation", 8)
	cart_drop_zones.add_child(_cart_drop_zone(
		"BuyDropZone",
		"购买区",
		"buy",
		"接受店铺栏物品",
		"拒绝背包/装备出售源",
		"buy_zone_requires_shop_source"
	))
	cart_drop_zones.add_child(_cart_drop_zone(
		"SellDropZone",
		"出售区",
		"sell",
		"接受背包或装备栏物品",
		"拒绝店铺购买源",
		"sell_zone_requires_player_or_equipment_source"
	))
	var cart_scroll := ScrollContainer.new()
	cart_scroll.name = "CartScroll"
	cart_scroll.custom_minimum_size = Vector2(580, 72)
	cart_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cart_scroll.set_drag_forwarding(
		Callable(self, "_empty_trade_drag_data"),
		Callable(self, "_can_drop_cart_data"),
		Callable(self, "_drop_cart_data")
	)
	_cart_items_box = VBoxContainer.new()
	_cart_items_box.name = "CartItemLines"
	_cart_items_box.add_theme_constant_override("separation", 4)
	_cart_items_box.set_drag_forwarding(
		Callable(self, "_empty_trade_drag_data"),
		Callable(self, "_can_drop_cart_data"),
		Callable(self, "_drop_cart_data")
	)
	cart_scroll.add_child(_cart_items_box)
	_equipment_sell_dialog = ConfirmationDialog.new()
	_equipment_sell_dialog.name = "EquipmentSellConfirmDialog"
	_equipment_sell_dialog.title = "确认出售装备"
	_equipment_sell_dialog.dialog_text = "确定要出售已装备物品吗？"
	_equipment_sell_dialog.confirmed.connect(func() -> void:
		_equipment_sell_dialog.hide()
		_emit_selected_trade()
	)
	_equipment_sell_dialog.get_ok_button().text = "出售"
	_equipment_sell_dialog.get_cancel_button().text = "取消"
	add_child(_equipment_sell_dialog)
	_context_menu = PopupMenu.new()
	_context_menu.name = "TradeContextMenu"
	_context_menu.id_pressed.connect(_execute_context_action)
	add_child(_context_menu)
	box.add_child(_cart_label)
	box.add_child(cart_controls)
	box.add_child(cart_drop_zones)
	box.add_child(cart_scroll)
	box.add_child(columns)


func _item_line(item: Dictionary, source: String) -> Button:
	var button := Button.new()
	button.name = "Item_%s" % item.get("item_id", "unknown")
	var disabled_reason: String = str(item.get("disabled_reason", ""))
	var disabled_reason_text := _trade_reason_text(disabled_reason)
	button.text = "%s x%d | %d%s%s" % [
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
		int(item.get("price", 0)),
		_stack_suffix(item),
		" | %s" % disabled_reason_text if not disabled_reason_text.is_empty() else "",
	]
	button.tooltip_text = _item_tooltip_text(item)
	var trade_disabled_reason := _trade_disabled_reason(item, source)
	var trade_disabled_reason_text := _trade_reason_text(trade_disabled_reason)
	if not disabled_reason_text.is_empty():
		button.tooltip_text = "%s\n%s" % [button.tooltip_text, disabled_reason_text] if not button.tooltip_text.is_empty() else disabled_reason_text
	if not trade_disabled_reason_text.is_empty() and trade_disabled_reason_text != disabled_reason_text:
		button.tooltip_text = "%s\n%s" % [button.tooltip_text, trade_disabled_reason_text] if not button.tooltip_text.is_empty() else trade_disabled_reason_text
	button.disabled = not trade_disabled_reason.is_empty()
	button.set_meta("trade_item", item.duplicate(true))
	button.set_meta("trade_source", source)
	_apply_item_icon(button, item)
	button.set_drag_forwarding(
		Callable(self, "_get_trade_item_drag_data"),
		Callable(self, "_cannot_drop_trade_item_data"),
		Callable(self, "_ignore_trade_item_drop")
	)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_apply_detail(item.duplicate(true), source)
	)
	button.gui_input.connect(func(event: InputEvent) -> void:
		var mouse_event := event as InputEventMouseButton
		if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT:
			return
		button.accept_event()
		_open_context_menu_for_item(item.duplicate(true), source, button.get_global_mouse_position())
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
		_selected_item_snapshot = {}
		_update_trade_controls({}, "")
		return
	var description := str(item.get("description", ""))
	var disabled_reason := str(item.get("disabled_reason", ""))
	var disabled_reason_text := _trade_reason_text(disabled_reason)
	_selected_source = source
	_selected_item_id = str(item.get("item_id", ""))
	_selected_item_snapshot = item.duplicate(true)
	_update_trade_controls(item, source)
	_detail_label.text = "%s：%s x%d | 单价 %d | 小计 %d%s%s%s" % [
		_source_display(source),
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
		int(item.get("price", 0)),
		int(item.get("price", 0)) * int(_quantity_spin.value if _quantity_spin != null else 1),
		_stack_detail_suffix(item),
		"\n%s" % description if not description.is_empty() else "",
		"\n%s" % disabled_reason_text if not disabled_reason_text.is_empty() else "",
	]


func _apply_feedback(feedback: Dictionary) -> void:
	if _feedback_label == null:
		return
	var text := str(feedback.get("text", ""))
	_feedback_label.visible = not text.is_empty()
	_feedback_label.text = text


func _item_tooltip_text(item: Dictionary) -> String:
	var description := str(item.get("description", ""))
	var stack_detail := _stack_detail_suffix(item).strip_edges()
	if stack_detail.is_empty():
		return description
	return "%s\n%s" % [description, stack_detail] if not description.is_empty() else stack_detail


func _stack_suffix(item: Dictionary) -> String:
	if not bool(item.get("multi_stack", false)):
		return ""
	return " | 堆 %d/%d" % [int(item.get("stack_index", 1)), int(item.get("stack_count", 1))]


func _stack_detail_suffix(item: Dictionary) -> String:
	if not bool(item.get("multi_stack", false)):
		return ""
	return " | 堆 %d/%d，同物品合计 %d" % [
		int(item.get("stack_index", 1)),
		int(item.get("stack_count", 1)),
		int(item.get("stack_total_count", item.get("count", 0))),
	]


func _update_trade_controls(item: Dictionary, source: String) -> void:
	if _quantity_spin == null or _trade_button == null or _queue_button == null:
		return
	var available := maxi(1, int(item.get("count", 1)))
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = available
	_quantity_spin.value = clampi(int(_quantity_spin.value), 1, available)
	var item_id := str(item.get("item_id", ""))
	var disabled_reason := _selected_trade_disabled_reason(item, source)
	var disabled_reason_text := _trade_reason_text(disabled_reason)
	_trade_button.disabled = not disabled_reason.is_empty()
	_trade_button.tooltip_text = disabled_reason_text if _trade_button.disabled else "执行当前选择的交易"
	_queue_button.disabled = _trade_button.disabled
	_queue_button.tooltip_text = disabled_reason_text if _queue_button.disabled else "把当前选择加入购物车"
	_quantity_spin.tooltip_text = "交易数量：%d / %d" % [int(_quantity_spin.value), available] if disabled_reason.is_empty() else disabled_reason_text
	match source:
		"shop":
			_trade_button.text = "购买"
		"player":
			_trade_button.text = "出售"
		_:
			_trade_button.text = "出售" if _is_sell_source(source) else "交易"


func _open_context_menu_for_item(item: Dictionary, source: String, screen_position: Vector2) -> void:
	if _context_menu == null:
		return
	_apply_detail(item.duplicate(true), source)
	_context_item = item.duplicate(true)
	_context_source = source
	_context_menu.clear()
	var action_label := "购买选中数量" if source == "shop" else "出售选中数量" if _is_sell_source(source) else "交易选中数量"
	_context_menu.add_item("检查", CONTEXT_INSPECT)
	_context_menu.add_item(action_label, CONTEXT_TRADE)
	_context_menu.add_item("加入购物车", CONTEXT_QUEUE)
	var disabled_reason := _selected_trade_disabled_reason(item, source)
	var disabled_reason_text := _trade_reason_text(disabled_reason)
	var disabled := not disabled_reason.is_empty()
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_TRADE), disabled)
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_QUEUE), disabled)
	var selected_count := _selected_trade_count(item)
	var total_count := maxi(0, int(item.get("count", 0)))
	var total_price := int(item.get("price", 0)) * selected_count
	_context_menu.set_item_tooltip(_context_menu.get_item_index(CONTEXT_INSPECT), "查看价格、描述和交易限制")
	_context_menu.set_item_tooltip(
		_context_menu.get_item_index(CONTEXT_TRADE),
		"%s x%d | 小计 %d（当前堆叠 %d）" % [action_label, selected_count, total_price, total_count] if not disabled else disabled_reason_text
	)
	_context_menu.set_item_tooltip(
		_context_menu.get_item_index(CONTEXT_QUEUE),
		"加入购物车 x%d | 小计 %d（当前堆叠 %d）" % [selected_count, total_price, total_count] if not disabled else disabled_reason_text
	)
	var popup_position := Vector2i(int(screen_position.x), int(screen_position.y))
	_context_menu.popup(Rect2i(popup_position, Vector2i(180, 1)))


func context_menu_snapshot() -> Dictionary:
	if _context_menu == null or not _context_menu.visible:
		return {}
	return {
		"id": "trade_context_menu",
		"name": "trade_context_menu",
		"kind": "trade_item",
		"owner_panel": "trade",
		"active": true,
		"visible": true,
		"mouse_blocks_world": true,
		"item_id": str(_context_item.get("item_id", "")),
		"item_name": str(_context_item.get("name", _context_item.get("item_id", ""))),
		"item_count": int(_context_item.get("count", 0)),
		"source": _context_source,
		"selected_count": _selected_trade_count(_context_item),
		"unit_price": int(_context_item.get("price", 0)),
		"total_price": int(_context_item.get("price", 0)) * _selected_trade_count(_context_item),
		"option_count": _context_menu.item_count,
		"options": _trade_context_option_summaries(),
	}


func close_context_menu() -> void:
	if _context_menu != null:
		_context_menu.hide()
	_context_item = {}
	_context_source = ""


func _trade_context_option_summaries() -> Array[Dictionary]:
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


func _execute_context_action(action_id: int) -> void:
	if _context_item.is_empty() or _context_source.is_empty():
		return
	match action_id:
		CONTEXT_INSPECT:
			_apply_detail(_context_item.duplicate(true), _context_source)
		CONTEXT_TRADE:
			if _item_can_trade(_context_item, _context_source):
				if _requires_equipment_sell_confirmation(_context_source):
					_open_equipment_sell_dialog()
				else:
					trade_requested.emit(_context_source, str(_context_item.get("item_id", "")), _selected_trade_count(_context_item), _stack_index_for_trade(_context_source, _context_item))
		CONTEXT_QUEUE:
			_queue_trade_entry(_context_item, _context_source, _selected_trade_count(_context_item))
	if _context_menu != null:
		_context_menu.hide()


func _selected_trade_count(item: Dictionary) -> int:
	var available := maxi(1, int(item.get("count", 1)))
	var selected_count := int(_quantity_spin.value if _quantity_spin != null else 1)
	return clampi(selected_count, 1, available)


func has_blocking_modal() -> bool:
	return _equipment_sell_dialog != null and _equipment_sell_dialog.visible


func blocking_modal_name() -> String:
	if has_blocking_modal():
		return "equipment_sell_confirm"
	return ""


func blocking_modal_snapshot() -> Dictionary:
	if not has_blocking_modal():
		return {}
	return {
		"id": "equipment_sell_confirm",
		"name": "modal:equipment_sell_confirm",
		"kind": "confirm",
		"owner_panel": "trade",
		"blocks_gameplay": true,
		"mouse_blocks_world": true,
		"source": _selected_source,
		"item_id": _selected_item_id,
		"count": int(_quantity_spin.value if _quantity_spin != null else 1),
	}


func close_blocking_modal() -> Dictionary:
	if not has_blocking_modal():
		return {"success": false, "reason": "modal_inactive"}
	_equipment_sell_dialog.hide()
	return {
		"success": true,
		"closed": "modal:equipment_sell_confirm",
	}


func handle_shortcut_key(event: InputEventKey) -> bool:
	if not visible or event == null or not event.pressed or event.echo or has_blocking_modal():
		return false
	var key := event.keycode
	if key == 0:
		key = event.physical_keycode
	match key:
		KEY_ENTER, KEY_KP_ENTER:
			if event.shift_pressed:
				_confirm_cart_from_shortcut()
			else:
				_trade_selected_from_shortcut()
			return true
		KEY_Q:
			_queue_selected_from_shortcut()
			return true
		KEY_DELETE, KEY_BACKSPACE:
			_clear_cart_from_shortcut()
			return true
		_:
			return false


func _queue_selected_item() -> void:
	if _selected_source.is_empty() or _selected_item_id.is_empty() or _selected_item_snapshot.is_empty():
		return
	if not _item_can_trade(_selected_item_snapshot, _selected_source):
		return
	var count := int(_quantity_spin.value if _quantity_spin != null else 1)
	if count <= 0:
		return
	_queue_trade_entry(_selected_item_snapshot, _selected_source, count)


func _queue_selected_from_shortcut() -> void:
	set_meta("trade_last_shortcut", "queue")
	_queue_selected_item()


func _trade_selected_from_shortcut() -> void:
	set_meta("trade_last_shortcut", "trade")
	if _trade_button == null or _trade_button.disabled:
		return
	if _requires_equipment_sell_confirmation(_selected_source):
		_open_equipment_sell_dialog()
		return
	_emit_selected_trade()


func _confirm_cart_from_shortcut() -> void:
	set_meta("trade_last_shortcut", "confirm_cart")
	if _confirm_cart_button == null or _confirm_cart_button.disabled or _cart_entries.is_empty():
		return
	trade_cart_confirmed.emit(_cart_entries.duplicate(true))
	_clear_cart()


func _clear_cart_from_shortcut() -> void:
	set_meta("trade_last_shortcut", "clear_cart")
	if _cart_entries.is_empty():
		return
	_clear_cart()


func _queue_trade_entry(item: Dictionary, source: String, count: int) -> bool:
	var item_id: String = str(item.get("item_id", ""))
	if source.is_empty() or item_id.is_empty() or not _item_can_trade(item, source):
		return false
	var max_count: int = maxi(1, int(item.get("count", count)))
	var normalized_count: int = clampi(count, 1, max_count)
	var entry := {
		"source": source,
		"item_id": item_id,
		"name": str(item.get("name", item_id)),
		"count": normalized_count,
		"max_count": max_count,
		"unit_price": int(item.get("price", 0)),
	}
	var stack_index := _stack_index_for_trade(source, item)
	if stack_index > 0:
		entry["stack_index"] = stack_index
	_cart_entries.append(entry)
	_update_cart_line()
	return true


func _empty_trade_drag_data(_position: Vector2, _from_control: Control) -> Variant:
	return null


func _get_trade_item_drag_data(_position: Vector2, from_control: Control) -> Variant:
	if from_control == null or not from_control.has_meta("trade_item") or not from_control.has_meta("trade_source"):
		return null
	var item: Dictionary = _dictionary_or_empty(from_control.get_meta("trade_item"))
	var source: String = str(from_control.get_meta("trade_source"))
	if item.is_empty() or source.is_empty() or not _item_can_trade(item, source):
		return null
	var preview_text := "%s x%d" % [item.get("name", item.get("item_id", "")), int(item.get("count", 0))]
	if get_viewport() != null and get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = preview_text
		preview.name = "TradeDragPreview"
		preview.set_meta("trade_drag_preview_text", preview_text)
		set_drag_preview(preview)
	return {
		"kind": "trade_item",
		"source": source,
		"item": item.duplicate(true),
		"count": int(_quantity_spin.value if _quantity_spin != null else 1),
		"drag_preview_text": preview_text,
	}


func _cannot_drop_trade_item_data(_position: Vector2, _data: Variant, _from_control: Control) -> bool:
	return false


func _ignore_trade_item_drop(_position: Vector2, _data: Variant, _from_control: Control) -> void:
	pass


func _can_drop_cart_data(_position: Vector2, data: Variant, _from_control: Control) -> bool:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	match str(drag_data.get("kind", "")):
		"trade_item":
			var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
			var source: String = str(drag_data.get("source", ""))
			var accepted := not item.is_empty() and _item_can_trade(item, source) and _drag_source_matches_drop_zone(source, _from_control)
			_update_drop_zone_drag_state(_from_control, source, accepted, _drop_reject_reason(item, source, _from_control))
			return accepted
		"inventory_item":
			var item: Dictionary = _trade_item_from_inventory_drag(drag_data)
			var accepted := not item.is_empty() and _item_can_trade(item, "player") and _drag_source_matches_drop_zone("player", _from_control)
			_update_drop_zone_drag_state(_from_control, "player", accepted, _drop_reject_reason(item, "player", _from_control))
			return accepted
		"trade_cart_entry":
			var from_index: int = int(drag_data.get("index", -1))
			var accepted := from_index >= 0 and from_index < _cart_entries.size() and not _is_trade_drop_zone(_from_control)
			_update_drop_zone_drag_state(_from_control, "cart", accepted, str(_from_control.get_meta("trade_drop_reject_reason", "cart_entry_requires_cart_target")) if _is_trade_drop_zone(_from_control) else "")
			return accepted
		_:
			_update_drop_zone_drag_state(_from_control, "", false, "unsupported_drag_data")
			return false


func _drop_cart_data(position: Vector2, data: Variant, from_control: Control) -> void:
	if not _can_drop_cart_data(position, data, from_control):
		return
	var drag_data: Dictionary = _dictionary_or_empty(data)
	match str(drag_data.get("kind", "")):
		"trade_item":
			var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
			var source: String = str(drag_data.get("source", ""))
			var count: int = int(drag_data.get("count", 1))
			if _merge_trade_item_into_cart_entry(item, source, count, _cart_drop_index(from_control)):
				return
			_queue_trade_entry(item, source, count)
		"inventory_item":
			var item: Dictionary = _trade_item_from_inventory_drag(drag_data)
			var count: int = int(drag_data.get("count", 1))
			if _merge_trade_item_into_cart_entry(item, "player", count, _cart_drop_index(from_control)):
				return
			_queue_trade_entry(item, "player", count)
		"trade_cart_entry":
			_reorder_cart_entry(int(drag_data.get("index", -1)), _cart_drop_index(from_control))


func _emit_selected_trade() -> void:
	if _selected_source.is_empty() or _selected_item_id.is_empty():
		return
	trade_requested.emit(_selected_source, _selected_item_id, int(_quantity_spin.value), _stack_index_for_trade(_selected_source, _selected_item_snapshot))


func _stack_index_for_trade(source: String, item: Dictionary) -> int:
	return int(item.get("stack_index", 0)) if source == "shop" or source == "player" else 0


func _open_equipment_sell_dialog() -> void:
	if _equipment_sell_dialog == null:
		return
	var item_name: String = str(_selected_item_snapshot.get("name", _selected_item_id))
	var price: int = int(_selected_item_snapshot.get("price", 0))
	_equipment_sell_dialog.dialog_text = "出售已装备的 %s 将会自动卸下该装备，并获得 %d。确定出售吗？" % [
		item_name,
		price,
	]
	_equipment_sell_dialog.popup_centered()


func _clear_cart() -> void:
	_cart_entries.clear()
	_update_cart_line()


func _update_cart_line() -> void:
	if _cart_label == null:
		return
	_clear_box(_cart_items_box)
	if _cart_entries.is_empty():
		_cart_label.text = "购物车为空"
		if _clear_cart_button != null:
			_clear_cart_button.disabled = true
		if _confirm_cart_button != null:
			_confirm_cart_button.disabled = true
		return
	var parts: Array[String] = []
	var buy_total := 0
	var sell_total := 0
	for index in range(_cart_entries.size()):
		var entry: Dictionary = _cart_entries[index]
		_cart_items_box.add_child(_cart_entry_row(entry, index))
		var source := str(entry.get("source", ""))
		var count := int(entry.get("count", 0))
		var unit_price := int(entry.get("unit_price", 0))
		var verb := "购买" if source == "shop" else "出售" if _is_sell_source(source) else "交易"
		parts.append("%s %s x%d" % [verb, entry.get("name", entry.get("item_id", "")), count])
		if source == "shop":
			buy_total += unit_price * count
		elif _is_sell_source(source):
			sell_total += unit_price * count
	var net_payment := buy_total - sell_total
	var net_text := "净付 %d" % net_payment if net_payment >= 0 else "净收 %d" % -net_payment
	_cart_label.text = "购物车：%s | 应付 %d | 应收 %d | %s | 确认后玩家资金 %d | 店铺资金 %d%s" % [
		"；".join(parts),
		buy_total,
		sell_total,
		net_text,
		_player_money - net_payment,
		_shop_money + net_payment,
		" | %s" % _trade_block_reason if not _trade_allowed and not _trade_block_reason.is_empty() else "",
	]
	if _clear_cart_button != null:
		_clear_cart_button.disabled = false
	if _confirm_cart_button != null:
		_confirm_cart_button.disabled = not _trade_allowed


func _cart_entry_row(entry: Dictionary, index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CartEntry_%d" % index
	row.add_theme_constant_override("separation", 6)
	row.set_meta("cart_index", index)
	row.set_drag_forwarding(
		Callable(self, "_get_cart_entry_drag_data"),
		Callable(self, "_can_drop_cart_data"),
		Callable(self, "_drop_cart_data")
	)
	var label := _label("CartEntryLabel")
	label.custom_minimum_size = Vector2(332, 0)
	var source := str(entry.get("source", ""))
	var verb := "购买" if source == "shop" else "出售" if _is_sell_source(source) else "交易"
	label.text = "%s %s x%d | 小计 %d" % [
		verb,
		entry.get("name", entry.get("item_id", "")),
		int(entry.get("count", 0)),
		int(entry.get("count", 0)) * int(entry.get("unit_price", 0)),
	]
	var decrease_button := Button.new()
	decrease_button.name = "DecreaseButton"
	decrease_button.text = "-"
	decrease_button.custom_minimum_size = Vector2(28, 24)
	decrease_button.disabled = int(entry.get("count", 0)) <= 1
	decrease_button.pressed.connect(func() -> void:
		_adjust_cart_entry(index, -1)
	)
	var increase_button := Button.new()
	increase_button.name = "IncreaseButton"
	increase_button.text = "+"
	increase_button.custom_minimum_size = Vector2(28, 24)
	increase_button.disabled = int(entry.get("count", 0)) >= int(entry.get("max_count", entry.get("count", 0)))
	increase_button.pressed.connect(func() -> void:
		_adjust_cart_entry(index, 1)
	)
	var remove_button := Button.new()
	remove_button.name = "RemoveButton"
	remove_button.text = "移除"
	remove_button.custom_minimum_size = Vector2(52, 24)
	remove_button.pressed.connect(func() -> void:
		_remove_cart_entry(index)
	)
	row.add_child(label)
	row.add_child(decrease_button)
	row.add_child(increase_button)
	row.add_child(remove_button)
	return row


func _get_cart_entry_drag_data(_position: Vector2, from_control: Control) -> Variant:
	if from_control == null or not from_control.has_meta("cart_index"):
		return null
	var index: int = int(from_control.get_meta("cart_index"))
	if index < 0 or index >= _cart_entries.size():
		return null
	var entry: Dictionary = _cart_entries[index]
	var source: String = str(entry.get("source", ""))
	var verb: String = "购买" if source == "shop" else "出售" if _is_sell_source(source) else "交易"
	var preview_text := "%s %s x%d" % [
		verb,
		entry.get("name", entry.get("item_id", "")),
		int(entry.get("count", 0)),
	]
	if get_viewport() != null and get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = preview_text
		preview.name = "TradeCartDragPreview"
		preview.set_meta("trade_drag_preview_text", preview_text)
		set_drag_preview(preview)
	return {
		"kind": "trade_cart_entry",
		"index": index,
		"drag_preview_text": preview_text,
	}


func _cart_drop_index(from_control: Control) -> int:
	if from_control != null and from_control.has_meta("cart_index"):
		return int(from_control.get_meta("cart_index"))
	return _cart_entries.size()


func _reorder_cart_entry(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= _cart_entries.size():
		return
	var clamped_to_index: int = clampi(to_index, 0, _cart_entries.size())
	if from_index == clamped_to_index or from_index + 1 == clamped_to_index:
		return
	var entry: Dictionary = _cart_entries[from_index]
	_cart_entries.remove_at(from_index)
	if clamped_to_index > from_index:
		clamped_to_index -= 1
	_cart_entries.insert(clamped_to_index, entry)
	_update_cart_line()


func _merge_trade_item_into_cart_entry(item: Dictionary, source: String, count: int, target_index: int) -> bool:
	if target_index < 0 or target_index >= _cart_entries.size():
		return false
	var item_id: String = str(item.get("item_id", ""))
	var entry: Dictionary = _cart_entries[target_index]
	if str(entry.get("source", "")) != source:
		return false
	if str(entry.get("item_id", "")) != item_id:
		return false
	if int(entry.get("unit_price", 0)) != int(item.get("price", entry.get("unit_price", 0))):
		return false
	if int(entry.get("stack_index", 0)) != _stack_index_for_trade(source, item):
		return false
	var max_count: int = maxi(1, int(entry.get("max_count", entry.get("count", 1))))
	var merged_count: int = clampi(int(entry.get("count", 1)) + maxi(1, count), 1, max_count)
	if merged_count == int(entry.get("count", 1)):
		return true
	entry["count"] = merged_count
	_cart_entries[target_index] = entry
	_update_cart_line()
	return true


func _trade_item_from_inventory_drag(drag_data: Dictionary) -> Dictionary:
	var drag_item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
	var item_id: String = str(drag_data.get("item_id", drag_item.get("item_id", "")))
	if item_id.is_empty() or _player_items_box == null:
		return {}
	for child in _player_items_box.get_children():
		if not child.has_meta("trade_item") or not child.has_meta("trade_source"):
			continue
		if str(child.get_meta("trade_source", "")) != "player":
			continue
		var trade_item: Dictionary = _dictionary_or_empty(child.get_meta("trade_item"))
		if str(trade_item.get("item_id", "")) == item_id:
			return trade_item.duplicate(true)
	return {}


func _adjust_cart_entry(index: int, delta: int) -> void:
	if index < 0 or index >= _cart_entries.size() or delta == 0:
		return
	var entry := _cart_entries[index]
	var max_count := maxi(1, int(entry.get("max_count", entry.get("count", 1))))
	entry["count"] = clampi(int(entry.get("count", 1)) + delta, 1, max_count)
	_cart_entries[index] = entry
	_update_cart_line()


func _remove_cart_entry(index: int) -> void:
	if index < 0 or index >= _cart_entries.size():
		return
	_cart_entries.remove_at(index)
	_update_cart_line()


func _cart_drop_zone(node_name: String, title: String, zone: String, accept_text: String, reject_text: String, reject_reason: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.custom_minimum_size = Vector2(286, 42)
	var tooltip := "拖到这里%s\n%s；%s" % [
		"购买" if zone == "buy" else "出售",
		accept_text,
		reject_text,
	]
	panel.tooltip_text = tooltip
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_meta("trade_drop_zone", zone)
	panel.set_meta("trade_drop_accepts", "shop" if zone == "buy" else "player,equipment")
	panel.set_meta("trade_drop_accept_text", accept_text)
	panel.set_meta("trade_drop_reject_text", reject_text)
	panel.set_meta("trade_drop_reject_reason", reject_reason)
	panel.set_meta("trade_drop_idle_text", "%s\n%s" % [title, accept_text])
	panel.set_meta("trade_drop_hover_text", "%s\n%s；%s" % [title, accept_text, reject_text])
	panel.set_meta("trade_drop_last_preview_text", "")
	panel.set_meta("trade_drop_last_accept", false)
	panel.set_meta("trade_drop_last_source", "")
	panel.set_drag_forwarding(
		Callable(self, "_empty_trade_drag_data"),
		Callable(self, "_can_drop_cart_data"),
		Callable(self, "_drop_cart_data")
	)
	panel.mouse_entered.connect(func() -> void:
		_set_drop_zone_hovered(panel, true)
	)
	panel.mouse_exited.connect(func() -> void:
		_set_drop_zone_hovered(panel, false)
	)
	panel.add_theme_stylebox_override("panel", _drop_zone_style(Color(0.12, 0.16, 0.18, 0.92), Color(0.32, 0.47, 0.43, 1.0)))
	var label := _label("%sLabel" % node_name)
	label.text = str(panel.get_meta("trade_drop_idle_text", ""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.tooltip_text = tooltip
	label.custom_minimum_size = Vector2(0, 38)
	panel.add_child(label)
	return panel


func _set_drop_zone_hovered(panel: PanelContainer, hovered: bool) -> void:
	if panel == null:
		return
	panel.set_meta("trade_drop_hovered", hovered)
	var label: Label = panel.get_child(0) as Label if panel.get_child_count() > 0 else null
	if label != null:
		label.text = str(panel.get_meta("trade_drop_hover_text" if hovered else "trade_drop_idle_text", ""))
	var background := Color(0.15, 0.20, 0.22, 0.96) if hovered else Color(0.12, 0.16, 0.18, 0.92)
	var border := Color(0.63, 0.80, 0.67, 1.0) if hovered else Color(0.32, 0.47, 0.43, 1.0)
	panel.add_theme_stylebox_override("panel", _drop_zone_style(background, border))


func _update_drop_zone_drag_state(from_control: Control, source: String, accepted: bool, reject_reason: String = "") -> void:
	if not _is_trade_drop_zone(from_control):
		return
	var reason := "" if accepted else reject_reason
	if reason.is_empty() and not accepted:
		reason = str(from_control.get_meta("trade_drop_reject_reason", ""))
	var source_text := _source_display(source) if not source.is_empty() else "未知来源"
	var preview_text := "可放入：%s" % source_text if accepted else "不可放入：%s | %s" % [source_text, _trade_reason_text(reason)]
	from_control.set_meta("trade_drop_last_source", source)
	from_control.set_meta("trade_drop_last_accept", accepted)
	from_control.set_meta("trade_drop_last_reject_reason", reason)
	from_control.set_meta("trade_drop_last_preview_text", preview_text)


func _is_trade_drop_zone(control: Control) -> bool:
	return control != null and control.has_meta("trade_drop_zone")


func _drop_zone_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _drag_source_matches_drop_zone(source: String, from_control: Control) -> bool:
	if from_control == null or not from_control.has_meta("trade_drop_zone"):
		return true
	match str(from_control.get_meta("trade_drop_zone", "")):
		"buy":
			return source == "shop"
		"sell":
			return _is_sell_source(source)
		_:
			return true


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
			return "装备" if source.begins_with("equipment:") else source


func _is_sell_source(source: String) -> bool:
	return source == "player" or source.begins_with("equipment:")


func _requires_equipment_sell_confirmation(source: String) -> bool:
	return source.begins_with("equipment:")


func _item_can_trade(item: Dictionary, source: String) -> bool:
	return _trade_disabled_reason(item, source).is_empty()


func _selected_trade_disabled_reason(item: Dictionary, source: String) -> String:
	var item_id := str(item.get("item_id", ""))
	if item.is_empty() or item_id.is_empty() or source.is_empty():
		return "先选择可交易的物品"
	return _trade_disabled_reason(item, source)


func _trade_disabled_reason(item: Dictionary, source: String) -> String:
	if not _trade_allowed:
		return _trade_block_reason if not _trade_block_reason.is_empty() else "当前交易不可用"
	var disabled_reason := str(item.get("disabled_reason", ""))
	if bool(item.get("trade_disabled", false)):
		return disabled_reason if not disabled_reason.is_empty() else "该物品当前不能交易"
	if source == "shop":
		return ""
	if _is_sell_source(source):
		if not bool(item.get("sellable", true)):
			return disabled_reason if not disabled_reason.is_empty() else "该物品不可出售"
		return ""
	return "未知交易来源：%s" % source


func _trade_reason_text(reason: String) -> String:
	var normalized := reason.strip_edges()
	if normalized.is_empty():
		return ""
	var entry: Dictionary = _reason_catalog.entry_for(normalized)
	return str(entry.get("disabled_text", normalized)) if bool(entry.get("known", false)) else normalized


func _drop_reject_reason(item: Dictionary, source: String, from_control: Control) -> String:
	if item.is_empty():
		return "unknown_trade_item"
	if _is_trade_drop_zone(from_control) and not _drag_source_matches_drop_zone(source, from_control):
		return str(from_control.get_meta("trade_drop_reject_reason", "drop_zone_source_mismatch"))
	var disabled_reason := _trade_disabled_reason(item, source)
	if not disabled_reason.is_empty():
		return disabled_reason
	return "trade_item_rejected"


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
		child.queue_free()


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
