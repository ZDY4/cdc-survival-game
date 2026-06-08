extends Control

const MediaTextureLoader = preload("res://scripts/ui/media_texture_loader.gd")

signal close_requested
signal transfer_requested(source: String, item_id: String, count: int, stack_index: int)
signal transfer_all_requested(source: String)

const CONTEXT_TRANSFER := 1
const CONTEXT_TRANSFER_ALL := 2

var _panel: PanelContainer
var _title_label: Label
var _close_button: Button
var _summary_label: Label
var _permission_label: Label
var _feedback_label: Label
var _detail_label: Label
var _quantity_label: Label
var _quantity_spin: SpinBox
var _quantity_minus_button: Button
var _quantity_plus_button: Button
var _quantity_all_button: Button
var _transfer_button: Button
var _take_all_button: Button
var _store_all_button: Button
var _items_box: VBoxContainer
var _player_items_box: VBoxContainer
var _context_menu: PopupMenu
var _quantity_confirm_dialog: ConfirmationDialog
var _context_item: Dictionary = {}
var _context_source := ""
var _selected_source: String = ""
var _selected_item_id: String = ""
var _selected_item_snapshot: Dictionary = {}
var _pending_quantity_transfer: Dictionary = {}
var _container_transferable_count := 0
var _player_transferable_count := 0


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
		if _context_menu != null:
			_context_menu.hide()
		if _quantity_confirm_dialog != null:
			_quantity_confirm_dialog.hide()
		_context_item = {}
		_context_source = ""
		_pending_quantity_transfer = {}
		return

	if snapshot.has("error"):
		_title_label.text = "Container %s" % snapshot.get("container_id", "")
		_summary_label.text = "容器资源不可用: %s" % snapshot.get("error", "unknown")
		_container_transferable_count = 0
		_player_transferable_count = 0
		_apply_permission_preview({})
		_apply_feedback({})
		_apply_detail({}, "")
		_clear_items()
		return

	_title_label.text = str(snapshot.get("display_name", snapshot.get("container_id", "")))
	_panel.set_meta("container_type", str(snapshot.get("container_type", "")))
	_panel.set_meta("container_origin", str(snapshot.get("container_origin", "")))
	_panel.set_meta("container_map_id", str(snapshot.get("map_id", "")))
	_panel.set_meta("container_source_actor_id", int(snapshot.get("source_actor_id", 0)))
	_summary_label.text = "容器 %d 类物品 | 背包 %d 类物品" % [
		snapshot.get("items", []).size(),
		snapshot.get("player_items", []).size(),
	]
	_apply_permission_preview(_dictionary_or_empty(snapshot.get("permission_preview", {})))
	_apply_feedback(_dictionary_or_empty(snapshot.get("feedback", {})))
	_clear_box(_items_box)
	_clear_box(_player_items_box)
	var items: Array = snapshot.get("items", [])
	_container_transferable_count = items.size()
	if items.is_empty():
		_items_box.add_child(_empty_line())
	else:
		for item in items:
			var item_data: Dictionary = item
			_items_box.add_child(_item_line(item_data, "container"))
	var player_items: Array = snapshot.get("player_items", [])
	_player_transferable_count = player_items.size()
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
	_permission_label = _label("PermissionsLine")
	_feedback_label = _label("FeedbackLine")
	_detail_label = _label("DetailLine")
	var transfer_controls := HBoxContainer.new()
	transfer_controls.name = "TransferControls"
	transfer_controls.add_theme_constant_override("separation", 8)
	_quantity_label = _label("QuantityLabel")
	_quantity_label.text = "数量：-"
	_quantity_spin = SpinBox.new()
	_quantity_spin.name = "QuantitySpin"
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = 1
	_quantity_spin.step = 1
	_quantity_spin.value = 1
	_quantity_spin.custom_minimum_size = Vector2(84, 0)
	_quantity_spin.tooltip_text = "选择要转移的数量"
	_quantity_spin.value_changed.connect(func(_value: float) -> void:
		_sync_quantity_controls()
	)
	_quantity_minus_button = _quantity_button("QuantityMinusButton", "-", "减少 1")
	_quantity_minus_button.pressed.connect(func() -> void:
		_adjust_transfer_quantity(-1)
	)
	_quantity_plus_button = _quantity_button("QuantityPlusButton", "+", "增加 1")
	_quantity_plus_button.pressed.connect(func() -> void:
		_adjust_transfer_quantity(1)
	)
	_quantity_all_button = _quantity_button("QuantityAllButton", "全部", "选择当前堆叠的全部数量")
	_quantity_all_button.custom_minimum_size = Vector2(48, 0)
	_quantity_all_button.pressed.connect(func() -> void:
		_set_transfer_quantity(_selected_available_count())
	)
	_transfer_button = Button.new()
	_transfer_button.name = "TransferButton"
	_transfer_button.text = "转移"
	_transfer_button.tooltip_text = "转移选中的物品数量"
	_transfer_button.disabled = true
	_transfer_button.pressed.connect(func() -> void:
		if _selected_item_id.is_empty() or _selected_source.is_empty():
			return
		_request_transfer(_selected_source, _selected_item_id, int(_quantity_spin.value), false, _selected_item_snapshot)
	)
	_take_all_button = Button.new()
	_take_all_button.name = "TakeAllButton"
	_take_all_button.text = "全部拿取"
	_take_all_button.tooltip_text = "拿取容器中的全部物品和金钱"
	_take_all_button.focus_mode = Control.FOCUS_NONE
	_take_all_button.disabled = true
	_take_all_button.pressed.connect(func() -> void:
		transfer_all_requested.emit("container")
	)
	_store_all_button = Button.new()
	_store_all_button.name = "StoreAllButton"
	_store_all_button.text = "全部存放"
	_store_all_button.tooltip_text = "存放背包中的全部物品"
	_store_all_button.focus_mode = Control.FOCUS_NONE
	_store_all_button.disabled = true
	_store_all_button.pressed.connect(func() -> void:
		transfer_all_requested.emit("player")
	)
	transfer_controls.add_child(_quantity_spin)
	transfer_controls.add_child(_quantity_minus_button)
	transfer_controls.add_child(_quantity_plus_button)
	transfer_controls.add_child(_quantity_all_button)
	transfer_controls.add_child(_quantity_label)
	transfer_controls.add_child(_transfer_button)
	transfer_controls.add_child(_take_all_button)
	transfer_controls.add_child(_store_all_button)
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
	_items_box.set_meta("container_source", "container")
	_prepare_container_drop_target(_items_box)
	_items_box.set_drag_forwarding(
		Callable(self, "_empty_container_drag_data"),
		Callable(self, "_can_drop_container_data"),
		Callable(self, "_drop_container_data")
	)
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
	_player_items_box.set_meta("container_source", "player")
	_prepare_container_drop_target(_player_items_box)
	_player_items_box.set_drag_forwarding(
		Callable(self, "_empty_container_drag_data"),
		Callable(self, "_can_drop_container_data"),
		Callable(self, "_drop_container_data")
	)
	_context_menu = PopupMenu.new()
	_context_menu.name = "ContainerContextMenu"
	_context_menu.id_pressed.connect(_execute_context_action)
	add_child(_context_menu)
	_quantity_confirm_dialog = ConfirmationDialog.new()
	_quantity_confirm_dialog.name = "ContainerQuantityConfirmDialog"
	_quantity_confirm_dialog.title = "确认数量转移"
	_quantity_confirm_dialog.dialog_text = "确定要转移选中的数量吗？"
	_quantity_confirm_dialog.confirmed.connect(_confirm_pending_quantity_transfer)
	_quantity_confirm_dialog.get_ok_button().text = "转移"
	_quantity_confirm_dialog.get_cancel_button().text = "取消"
	add_child(_quantity_confirm_dialog)
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
	box.add_child(_permission_label)
	box.add_child(_feedback_label)
	box.add_child(_detail_label)
	box.add_child(transfer_controls)
	box.add_child(columns)


func _item_line(item: Dictionary, source: String) -> Button:
	var button := Button.new()
	button.name = "Item_%s" % item.get("item_id", "unknown")
	button.text = _item_line_text(item)
	button.tooltip_text = _item_tooltip_text(item)
	button.set_meta("container_item", item.duplicate(true))
	button.set_meta("container_source", source)
	_apply_item_icon(button, item)
	button.set_drag_forwarding(
		Callable(self, "_get_container_item_drag_data"),
		Callable(self, "_cannot_drop_container_item_data"),
		Callable(self, "_ignore_container_item_drop")
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


func _empty_container_drag_data(_position: Vector2, _from_control: Control) -> Variant:
	return null


func _get_container_item_drag_data(_position: Vector2, from_control: Control) -> Variant:
	if from_control == null or not from_control.has_meta("container_item") or not from_control.has_meta("container_source"):
		return null
	var item: Dictionary = _dictionary_or_empty(from_control.get_meta("container_item"))
	var source: String = str(from_control.get_meta("container_source"))
	var item_id: String = str(item.get("item_id", ""))
	if item.is_empty() or source.is_empty() or item_id.is_empty():
		return null
	var preview_text := "%s x%d" % [item.get("name", item_id), int(item.get("count", 0))]
	if get_viewport() != null and get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = preview_text
		set_drag_preview(preview)
	return {
		"kind": "container_item",
		"source": source,
		"item": item.duplicate(true),
		"count": int(_quantity_spin.value if _quantity_spin != null else 1),
		"drag_preview_text": preview_text,
	}


func _cannot_drop_container_item_data(_position: Vector2, _data: Variant, _from_control: Control) -> bool:
	return false


func _ignore_container_item_drop(_position: Vector2, _data: Variant, _from_control: Control) -> void:
	pass


func _can_drop_container_data(_position: Vector2, data: Variant, from_control: Control) -> bool:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var target_source: String = _drop_target_source(from_control)
	var accepted := false
	var reject_reason := ""
	match str(drag_data.get("kind", "")):
		"container_item":
			var source: String = str(drag_data.get("source", ""))
			var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
			var item_id: String = str(item.get("item_id", ""))
			accepted = not item_id.is_empty() and not source.is_empty() and not target_source.is_empty() and source != target_source
			if accepted:
				reject_reason = ""
			elif target_source.is_empty():
				reject_reason = "container_drop_target_missing"
			elif source.is_empty():
				reject_reason = "container_drop_source_missing"
			elif item_id.is_empty():
				reject_reason = "container_drop_item_missing"
			else:
				reject_reason = "container_drop_same_column"
		"inventory_item":
			var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
			var item_id: String = str(drag_data.get("item_id", item.get("item_id", "")))
			accepted = target_source == "container" and not item_id.is_empty()
			if accepted:
				reject_reason = ""
			elif target_source.is_empty():
				reject_reason = "container_drop_target_missing"
			elif item_id.is_empty():
				reject_reason = "container_drop_item_missing"
			else:
				reject_reason = "container_drop_requires_container_column"
		_:
			reject_reason = "container_drop_unsupported_drag_data"
	_apply_container_drag_hover(from_control, accepted, reject_reason)
	return accepted


func _drop_container_data(position: Vector2, data: Variant, from_control: Control) -> void:
	if not _can_drop_container_data(position, data, from_control):
		return
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
	match str(drag_data.get("kind", "")):
		"container_item":
			var source: String = str(drag_data.get("source", ""))
			var item_id: String = str(item.get("item_id", ""))
			var available: int = maxi(1, int(item.get("count", 1)))
			var requested: int = int(drag_data.get("count", _quantity_spin.value if _quantity_spin != null else 1))
			var count: int = clampi(requested, 1, available)
			_request_transfer(source, item_id, count, false, item)
		"inventory_item":
			var item_id: String = str(drag_data.get("item_id", item.get("item_id", "")))
			var available: int = maxi(1, int(item.get("count", 1)))
			var count: int = clampi(int(drag_data.get("count", 1)), 1, available)
			var root := get_parent()
			if root != null and root.has_method("store_active_container_item"):
				root.store_active_container_item(item_id, count)
	_clear_container_drag_hover(from_control)


func _prepare_container_drop_target(control: Control) -> void:
	if control == null:
		return
	control.set_meta("container_drag_hovered", false)
	control.set_meta("container_drag_last_accept", false)
	control.set_meta("container_drag_reject_reason", "")
	control.set_meta("container_drag_highlight_style", "")
	control.set_meta("container_drag_highlight_color", "")
	control.mouse_exited.connect(func() -> void:
		_clear_container_drag_hover(control)
	)


func _apply_container_drag_hover(control: Control, accepted: bool, reject_reason: String) -> void:
	if control == null or not is_instance_valid(control) or not control.has_meta("container_source"):
		return
	var color_text := "#4ecb71" if accepted else "#e25c5c"
	var style := "accept" if accepted else "reject"
	control.set_meta("container_drag_hovered", true)
	control.set_meta("container_drag_last_accept", accepted)
	control.set_meta("container_drag_reject_reason", reject_reason)
	control.set_meta("container_drag_highlight_style", style)
	control.set_meta("container_drag_highlight_color", color_text)
	control.modulate = Color(0.92, 1.0, 0.94, 1.0) if accepted else Color(1.0, 0.92, 0.92, 1.0)


func _clear_container_drag_hover(control: Control) -> void:
	if control == null or not is_instance_valid(control) or not control.has_meta("container_source"):
		return
	control.set_meta("container_drag_hovered", false)
	control.set_meta("container_drag_last_accept", false)
	control.set_meta("container_drag_reject_reason", "")
	control.set_meta("container_drag_highlight_style", "")
	control.set_meta("container_drag_highlight_color", "")
	control.modulate = Color.WHITE


func has_blocking_modal() -> bool:
	return _quantity_confirm_dialog != null and _quantity_confirm_dialog.visible and not _pending_quantity_transfer.is_empty()


func blocking_modal_name() -> String:
	if has_blocking_modal():
		return "container_quantity_confirm"
	return ""


func blocking_modal_snapshot() -> Dictionary:
	if not has_blocking_modal():
		return {}
	var count := int(_pending_quantity_transfer.get("count", 0))
	var available := int(_pending_quantity_transfer.get("available", 0))
	return {
		"id": "container_quantity_confirm",
		"name": "modal:container_quantity_confirm",
		"kind": "quantity",
		"owner_panel": "container",
		"blocks_gameplay": true,
		"mouse_blocks_world": true,
		"dialog_visible": _quantity_confirm_dialog.visible,
		"source": str(_pending_quantity_transfer.get("source", "")),
		"item_id": str(_pending_quantity_transfer.get("item_id", "")),
		"item_name": str(_pending_quantity_transfer.get("item_name", _pending_quantity_transfer.get("item_id", ""))),
		"count": count,
		"available": available,
		"quantity_min": 1,
		"quantity_max": available,
		"quantity_valid": count >= 1 and (available <= 0 or count <= available),
		"quantity_text": str(count),
		"confirm_button_mouse_filter": _control_mouse_filter_name(_quantity_confirm_dialog.get_ok_button()),
		"confirm_button_mouse_blocks_world": _control_mouse_blocks_world(_quantity_confirm_dialog.get_ok_button()),
		"cancel_button_mouse_filter": _control_mouse_filter_name(_quantity_confirm_dialog.get_cancel_button()),
		"cancel_button_mouse_blocks_world": _control_mouse_blocks_world(_quantity_confirm_dialog.get_cancel_button()),
	}


func close_blocking_modal() -> Dictionary:
	if not has_blocking_modal():
		return {"success": false, "reason": "modal_inactive"}
	_quantity_confirm_dialog.hide()
	_pending_quantity_transfer = {}
	return {
		"success": true,
		"closed": "modal:container_quantity_confirm",
	}


func _request_transfer(source: String, item_id: String, count: int, force_confirm: bool = false, selected_item: Dictionary = {}) -> void:
	if source.is_empty() or item_id.is_empty() or count <= 0:
		return
	var item := selected_item.duplicate(true) if not selected_item.is_empty() else _item_snapshot_for_transfer(source, item_id)
	var available := maxi(1, int(item.get("count", count)))
	var normalized_count := clampi(count, 1, available)
	if normalized_count > 1 and not force_confirm:
		_open_quantity_confirm(source, item_id, normalized_count, available, item)
		return
	var stack_index := int(item.get("stack_index", 0)) if source == "container" or source == "player" else 0
	transfer_requested.emit(source, item_id, normalized_count, stack_index)


func _open_quantity_confirm(source: String, item_id: String, count: int, available: int, item: Dictionary) -> void:
	if _quantity_confirm_dialog == null:
		return
	_pending_quantity_transfer = {
		"source": source,
		"item_id": item_id,
		"item_name": str(item.get("name", item_id)),
		"count": count,
		"available": available,
		"item": item.duplicate(true),
	}
	var action := "拿取" if source == "container" else ("存放" if source == "player" else "转移")
	_quantity_confirm_dialog.dialog_text = "%s %s x%d（当前可用 %d）。确定继续吗？" % [
		action,
		str(_pending_quantity_transfer.get("item_name", item_id)),
		count,
		available,
	]
	_quantity_confirm_dialog.popup_centered()


func _confirm_pending_quantity_transfer() -> void:
	var pending := _pending_quantity_transfer.duplicate(true)
	_pending_quantity_transfer = {}
	if _quantity_confirm_dialog != null:
		_quantity_confirm_dialog.hide()
	_request_transfer(
		str(pending.get("source", "")),
		str(pending.get("item_id", "")),
		int(pending.get("count", 0)),
		true,
		_dictionary_or_empty(pending.get("item", {}))
	)


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


func _item_snapshot_for_transfer(source: String, item_id: String) -> Dictionary:
	var box: VBoxContainer = _items_box if source == "container" else _player_items_box
	if box == null:
		return {}
	for child in box.get_children():
		if child.has_meta("container_item"):
			var item: Dictionary = _dictionary_or_empty(child.get_meta("container_item"))
			if str(item.get("item_id", "")) == item_id:
				return item.duplicate(true)
	return {}


func _drop_target_source(from_control: Control) -> String:
	if from_control != null and from_control.has_meta("container_source"):
		return str(from_control.get_meta("container_source"))
	return ""


func _open_context_menu_for_item(item: Dictionary, source: String, screen_position: Vector2) -> void:
	if _context_menu == null:
		return
	_apply_detail(item.duplicate(true), source)
	_context_item = item.duplicate(true)
	_context_source = source
	_context_menu.clear()
	var selected_count := _selected_transfer_count(item)
	var total_count := maxi(0, int(item.get("count", 0)))
	var transfer_label := "拿取选中数量" if source == "container" else "存放选中数量"
	var transfer_all_label := "全部拿取此项" if source == "container" else "全部存放此项"
	if source != "container" and source != "player":
		transfer_label = "转移选中数量"
		transfer_all_label = "全部转移此项"
	_context_menu.add_item(transfer_label, CONTEXT_TRANSFER)
	_context_menu.add_item(transfer_all_label, CONTEXT_TRANSFER_ALL)
	var disabled := total_count <= 0 or str(item.get("item_id", "")).is_empty() or (source != "container" and source != "player")
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_TRANSFER), disabled)
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_TRANSFER_ALL), disabled)
	_context_menu.set_item_tooltip(
		_context_menu.get_item_index(CONTEXT_TRANSFER),
		"%s x%d（当前堆叠 %d）" % [transfer_label, selected_count, total_count] if not disabled else "当前物品不能转移"
	)
	_context_menu.set_item_tooltip(
		_context_menu.get_item_index(CONTEXT_TRANSFER_ALL),
		"%s x%d" % [transfer_all_label, total_count] if not disabled else "当前物品不能转移"
	)
	var popup_position := Vector2i(int(screen_position.x), int(screen_position.y))
	_context_menu.popup(Rect2i(popup_position, Vector2i(180, 1)))


func context_menu_snapshot() -> Dictionary:
	if _context_menu == null or not _context_menu.visible:
		return {}
	return {
		"id": "container_context_menu",
		"name": "container_context_menu",
		"kind": "container_item",
		"owner_panel": "container",
		"active": true,
		"visible": true,
		"mouse_blocks_world": true,
		"item_id": str(_context_item.get("item_id", "")),
		"item_name": str(_context_item.get("name", _context_item.get("item_id", ""))),
		"item_count": int(_context_item.get("count", 0)),
		"source": _context_source,
		"selected_count": _selected_transfer_count(_context_item),
		"option_count": _context_menu.item_count,
		"options": _container_context_option_summaries(),
	}


func _container_context_option_summaries() -> Array[Dictionary]:
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
	_context_source = ""


func _execute_context_action(action_id: int) -> void:
	if _context_item.is_empty() or _context_source.is_empty():
		return
	var item_id := str(_context_item.get("item_id", ""))
	if item_id.is_empty():
		return
	var available := maxi(0, int(_context_item.get("count", 0)))
	if available <= 0:
		return
	match action_id:
		CONTEXT_TRANSFER:
			_request_transfer(_context_source, item_id, _selected_transfer_count(_context_item), false, _context_item)
		CONTEXT_TRANSFER_ALL:
			_request_transfer(_context_source, item_id, available, false, _context_item)
	if _context_menu != null:
		_context_menu.hide()


func _selected_transfer_count(item: Dictionary) -> int:
	var available := maxi(1, int(item.get("count", 1)))
	var selected_count := int(_quantity_spin.value if _quantity_spin != null else 1)
	return clampi(selected_count, 1, available)


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
		_selected_item_snapshot = {}
		_update_transfer_controls({}, "")
		return
	_detail_label.text = _detail_text(item, source)
	_selected_source = source
	_selected_item_id = str(item.get("item_id", ""))
	_selected_item_snapshot = item.duplicate(true)
	_update_transfer_controls(item, source)


func _apply_permission_preview(preview: Dictionary) -> void:
	if _permission_label == null:
		return
	var text := str(preview.get("text", "权限：无特殊限制"))
	_permission_label.text = text
	var lines: Array = preview.get("lines", [])
	_permission_label.tooltip_text = "\n".join(lines) if not lines.is_empty() else text


func _update_transfer_controls(item: Dictionary, source: String) -> void:
	if _quantity_spin == null or _transfer_button == null:
		return
	var available := maxi(0, int(item.get("count", 0)))
	var has_selection := not item.is_empty() and not str(item.get("item_id", "")).is_empty() and not source.is_empty()
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = maxi(1, available)
	_quantity_spin.value = clampi(int(_quantity_spin.value), 1, maxi(1, available))
	_quantity_spin.editable = has_selection and available > 1
	var item_id := str(item.get("item_id", ""))
	_transfer_button.disabled = not has_selection or available <= 0
	match source:
		"container":
			_transfer_button.text = "拿取"
		"player":
			_transfer_button.text = "存放"
		_:
			_transfer_button.text = "转移"
	_sync_quantity_controls()


func _sync_quantity_controls() -> void:
	if _quantity_spin == null or _transfer_button == null:
		return
	var available := _selected_available_count()
	var has_selection := not _selected_item_id.is_empty() and not _selected_source.is_empty() and available > 0
	var count := clampi(int(_quantity_spin.value), 1, maxi(1, available))
	if int(_quantity_spin.value) != count:
		_quantity_spin.value = count
	if _quantity_label != null:
		_quantity_label.text = "数量：%d/%d" % [count, available] if has_selection else "数量：-"
		_quantity_label.tooltip_text = "当前选择数量 / 可用数量" if has_selection else "先选择容器或背包中的物品"
	if _quantity_minus_button != null:
		_quantity_minus_button.disabled = not has_selection or count <= 1
	if _quantity_plus_button != null:
		_quantity_plus_button.disabled = not has_selection or count >= available
	if _quantity_all_button != null:
		_quantity_all_button.disabled = not has_selection or count >= available
	if _quantity_spin != null:
		_quantity_spin.tooltip_text = "转移数量：%d / %d" % [count, available] if has_selection else "先选择容器或背包中的物品"
	var action := _transfer_button.text
	_transfer_button.tooltip_text = "%s %s x%d" % [action, _selected_item_id, count] if has_selection else "先选择要转移的物品"
	if _take_all_button != null:
		_take_all_button.disabled = _container_transferable_count <= 0
		_take_all_button.tooltip_text = "拿取容器中的全部物品和金钱" if _container_transferable_count > 0 else "容器中没有可拿取的物品"
	if _store_all_button != null:
		_store_all_button.disabled = _player_transferable_count <= 0
		_store_all_button.tooltip_text = "存放背包中的全部物品" if _player_transferable_count > 0 else "背包中没有可存放的物品"


func _adjust_transfer_quantity(delta: int) -> void:
	_set_transfer_quantity(int(_quantity_spin.value if _quantity_spin != null else 1) + delta)


func _set_transfer_quantity(count: int) -> void:
	if _quantity_spin == null:
		return
	_quantity_spin.value = clampi(count, 1, maxi(1, _selected_available_count()))
	_sync_quantity_controls()


func _selected_available_count() -> int:
	if _selected_item_id.is_empty() or _selected_source.is_empty():
		return 0
	if not _selected_item_snapshot.is_empty():
		return maxi(0, int(_selected_item_snapshot.get("count", 0)))
	for item in _items_for_selected_source():
		var item_data: Dictionary = _dictionary_or_empty(item)
		if str(item_data.get("item_id", "")) == _selected_item_id:
			return maxi(0, int(item_data.get("count", 0)))
	return 0


func _items_for_selected_source() -> Array:
	var box: VBoxContainer = _items_box if _selected_source == "container" else _player_items_box
	if box == null:
		return []
	var items: Array = []
	for child in box.get_children():
		if child.has_meta("container_item"):
			items.append(_dictionary_or_empty(child.get_meta("container_item")))
	return items


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


func _item_line_text(item: Dictionary) -> String:
	if str(item.get("kind", "")) == "money" or str(item.get("item_id", "")) == "money":
		return "%s x%d" % [
			item.get("name", "金钱"),
			int(item.get("count", 0)),
		]
	var rarity := str(item.get("rarity", ""))
	var rarity_suffix := " | %s" % rarity if not rarity.is_empty() else ""
	return "%s x%d | %.1f kg%s%s" % [
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
		float(item.get("total_weight", 0.0)),
		rarity_suffix,
		_stack_suffix(item),
	]


func _detail_text(item: Dictionary, source: String) -> String:
	var description := str(item.get("description", ""))
	if str(item.get("kind", "")) == "money" or str(item.get("item_id", "")) == "money":
		return "%s：%s x%d%s" % [
			_source_display(source),
			item.get("name", "金钱"),
			int(item.get("count", 0)),
			"\n%s" % description if not description.is_empty() else "",
		]
	var rarity := str(item.get("rarity", ""))
	var rarity_suffix := " | %s" % rarity if not rarity.is_empty() else ""
	return "%s：%s x%d | 单重 %.1f kg | 总重 %.1f kg%s%s%s" % [
		_source_display(source),
		item.get("name", item.get("item_id", "")),
		int(item.get("count", 0)),
		float(item.get("unit_weight", 0.0)),
		float(item.get("total_weight", 0.0)),
		rarity_suffix,
		_stack_detail_suffix(item),
		"\n%s" % description if not description.is_empty() else "",
	]


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


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _quantity_button(node_name: String, text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(28, 0)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = true
	return button


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
