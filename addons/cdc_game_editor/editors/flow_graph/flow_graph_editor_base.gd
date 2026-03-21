@tool
extends Control

signal selection_changed(selected_nodes: Array)
signal dirty_state_changed(is_dirty: bool)

const FLOW_GRAPH_CANVAS_SCRIPT := preload("res://addons/cdc_game_editor/editors/flow_graph/flow_graph_canvas.gd")
const FLOW_GRAPH_NODE_SCRIPT := preload("res://addons/cdc_game_editor/editors/flow_graph/flow_graph_node.gd")
const CLIPBOARD_SCRIPT := preload("res://addons/cdc_game_editor/utils/editor_clipboard.gd")
const UNDO_REDO_HELPER_SCRIPT := preload("res://addons/cdc_game_editor/utils/undo_redo_helper.gd")
const PROPERTY_PANEL_SCRIPT := preload("res://addons/cdc_game_editor/utils/property_panel.gd")
const MIN_RECORD_LIST_WIDTH := 180
const MIN_SIDE_PANEL_WIDTH := 280

@onready var _graph_edit
@onready var _property_panel
@onready var _main_split: HSplitContainer
@onready var _content_split: HSplitContainer
@onready var _record_list_container: VBoxContainer
@onready var _record_list_title: Label
@onready var _record_list: ItemList
@onready var _right_container: VBoxContainer
@onready var _toolbar: HBoxContainer
@onready var _search_box: LineEdit
@onready var _status_bar: Label
@onready var _close_confirmation_dialog: ConfirmationDialog

var nodes: Dictionary = {}
var connections: Array[Dictionary] = []
var selected_node_id: String = ""
var _inspected_node_id: String = ""
var _property_panel_refresh_pending: bool = false
var _pending_property_panel_data: Dictionary = {}

var _undo_redo_helper: RefCounted
var _clipboard: RefCounted
var editor_plugin = null
var _record_list_refreshing: bool = false
var _dirty: bool = false
var _dirty_tracking_suspension: int = 0
var _pending_close_callback: Callable = Callable()

func _ready() -> void:
	_clipboard = CLIPBOARD_SCRIPT.get_instance()
	if editor_plugin:
		_undo_redo_helper = UNDO_REDO_HELPER_SCRIPT.new(editor_plugin)
	_setup_ui()
	call_deferred("_update_main_split_layout")
	_after_base_ready()

func _setup_ui() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_toolbar = HBoxContainer.new()
	_toolbar.custom_minimum_size = Vector2(0, 42)
	_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_toolbar)
	_create_toolbar()

	_main_split = HSplitContainer.new()
	_main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_main_split)

	var left_container := VBoxContainer.new()
	left_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if _has_record_list():
		_content_split = HSplitContainer.new()
		_content_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_main_split.add_child(_content_split)

		_record_list_container = VBoxContainer.new()
		_record_list_container.custom_minimum_size = Vector2(_get_record_list_width(), 0)
		_record_list_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_content_split.add_child(_record_list_container)

		_record_list_title = Label.new()
		_record_list_title.text = _get_record_list_title()
		_record_list_container.add_child(_record_list_title)

		_record_list = ItemList.new()
		_record_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_record_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_record_list.item_selected.connect(_on_record_list_index_selected)
		_record_list.item_activated.connect(_on_record_list_index_activated)
		_record_list_container.add_child(_record_list)

		_content_split.add_child(left_container)
	else:
		_main_split.add_child(left_container)

	var search_container := HBoxContainer.new()
	search_container.custom_minimum_size = Vector2(0, 30)
	left_container.add_child(search_container)

	var search_label := Label.new()
	search_label.text = "🔍"
	search_container.add_child(search_label)

	_search_box = LineEdit.new()
	_search_box.placeholder_text = _get_search_placeholder()
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.text_changed.connect(_on_search_text_changed)
	search_container.add_child(_search_box)

	var clear_btn := Button.new()
	clear_btn.text = "清除"
	clear_btn.pressed.connect(func(): _search_box.clear(); _on_search_text_changed(""))
	search_container.add_child(clear_btn)

	_graph_edit = FLOW_GRAPH_CANVAS_SCRIPT.new()
	_graph_edit.node_type_definitions = _get_node_type_definitions()
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_edit.connection_request.connect(_on_connection_request)
	_graph_edit.disconnection_request.connect(_on_disconnection_request)
	_graph_edit.node_selected.connect(_on_node_selected)
	_graph_edit.node_deselected.connect(_on_node_deselected)
	_graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
	_graph_edit.add_node_requested.connect(_on_add_node_requested)
	left_container.add_child(_graph_edit)

	_right_container = VBoxContainer.new()
	_right_container.custom_minimum_size = Vector2(_get_side_panel_width(), 0)
	_right_container.size_flags_horizontal = Control.SIZE_FILL
	_right_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_split.add_child(_right_container)

	_property_panel = PROPERTY_PANEL_SCRIPT.new()
	_property_panel.custom_minimum_size = Vector2(320, 0)
	_property_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_property_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_property_panel.panel_title = _get_property_panel_title()
	_property_panel.property_changed.connect(_on_property_changed)
	_right_container.add_child(_property_panel)

	_status_bar = Label.new()
	_status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_bar.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_bar.text = _get_initial_status_text()
	root.add_child(_status_bar)

	_close_confirmation_dialog = ConfirmationDialog.new()
	_close_confirmation_dialog.title = "未保存更改"
	_close_confirmation_dialog.dialog_text = _get_unsaved_changes_dialog_text()
	_close_confirmation_dialog.get_ok_button().text = "保存并关闭"
	_close_confirmation_dialog.get_cancel_button().text = "取消"
	_close_confirmation_dialog.add_button("不保存", true, "discard")
	_close_confirmation_dialog.confirmed.connect(_on_close_dialog_confirmed)
	_close_confirmation_dialog.canceled.connect(_on_close_dialog_canceled)
	_close_confirmation_dialog.custom_action.connect(_on_close_dialog_custom_action)
	add_child(_close_confirmation_dialog)

func _create_toolbar() -> void:
	_add_toolbar_button("复制", _on_copy_nodes, "复制选中节点 (Ctrl+C)")
	_add_toolbar_button("粘贴", _on_paste_nodes, "粘贴节点 (Ctrl+V)")
	_add_toolbar_button("删除", _on_delete_selected, "删除选中节点 (Delete)")
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("居中", _on_center_view, "居中视图")

func _after_base_ready() -> void:
	pass

func _get_node_type_definitions() -> Array[Dictionary]:
	return []

func _get_node_type_config(node_type: String) -> Dictionary:
	for def in _get_node_type_definitions():
		if str(def.get("type", "")) == node_type:
			return def
	return {}

func _get_search_placeholder() -> String:
	return "搜索节点..."

func _get_property_panel_title() -> String:
	return "Node Properties"

func _get_initial_status_text() -> String:
	return "就绪"

func _get_editor_name() -> String:
	return "FlowGraphEditor"

func _get_side_panel_width() -> int:
	return 340

func _has_record_list() -> bool:
	return false

func _get_record_list_title() -> String:
	return "记录列表"

func _get_record_list_empty_text() -> String:
	return "暂无数据"

func _get_record_list_width() -> int:
	return 240

func _get_min_graph_width() -> int:
	return 640

func _get_record_list_entries() -> Array[Dictionary]:
	return []

func _get_record_list_selected_id() -> String:
	return ""

func _is_record_list_entry_dirty(_record_id: String) -> bool:
	return false

func _on_record_list_item_selected(_record_id: String) -> void:
	pass

func _on_record_list_item_activated(record_id: String) -> void:
	_on_record_list_item_selected(record_id)

func _refresh_record_list() -> void:
	if _record_list == null:
		return

	_record_list_refreshing = true
	_record_list.clear()

	var entries: Array[Dictionary] = _get_record_list_entries()
	var selected_id: String = _get_record_list_selected_id()
	var selected_index := -1

	for entry in entries:
		var record_id := str(entry.get("id", "")).strip_edges()
		var label := str(entry.get("label", record_id)).strip_edges()
		if _is_record_list_entry_dirty(record_id):
			label += " *"
		if record_id.is_empty() or label.is_empty():
			continue
		_record_list.add_item(label)
		var item_index := _record_list.get_item_count() - 1
		_record_list.set_item_metadata(item_index, record_id)
		if record_id == selected_id:
			selected_index = item_index

	if _record_list.get_item_count() == 0:
		_record_list.add_item(_get_record_list_empty_text())
		_record_list.set_item_metadata(0, "")

	if selected_index >= 0:
		_record_list.select(selected_index)

	if _record_list_title:
		_record_list_title.text = "%s (%d)" % [_get_record_list_title(), entries.size()]

	_record_list_refreshing = false

func _on_record_list_index_selected(index: int) -> void:
	if _record_list_refreshing:
		return
	var record_id := _get_record_list_id(index)
	if record_id.is_empty():
		return
	_on_record_list_item_selected(record_id)

func _on_record_list_index_activated(index: int) -> void:
	if _record_list_refreshing:
		return
	var record_id := _get_record_list_id(index)
	if record_id.is_empty():
		return
	_on_record_list_item_activated(record_id)

func _get_record_list_id(index: int) -> String:
	if _record_list == null or index < 0 or index >= _record_list.get_item_count():
		return ""
	var metadata: Variant = _record_list.get_item_metadata(index)
	return str(metadata).strip_edges()

func _add_toolbar_button(text: String, callback: Callable, tooltip: String = "") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(callback)
	_toolbar.add_child(btn)
	return btn

func _add_toolbar_separator() -> void:
	_toolbar.add_child(VSeparator.new())

func _set_node_type_menu(definitions: Array[Dictionary]) -> void:
	if _graph_edit:
		_graph_edit.node_type_definitions = definitions

func _generate_node_id(_node_type: String = "node") -> String:
	return "node_%d" % Time.get_ticks_msec()

func _add_node_requested_data(node_type: String, position: Vector2, data: Dictionary = {}) -> void:
	_create_node(node_type, position, data)

func _create_node(node_type: String, position: Vector2 = Vector2.ZERO, data: Dictionary = {}) -> String:
	var node_id := str(data.get("id", ""))
	if node_id.is_empty():
		node_id = _generate_node_id(node_type)

	var node_data: Dictionary = {
		"id": node_id,
		"type": node_type,
		"position": position,
		"title": str(_get_node_type_config(node_type).get("name", node_type))
	}

	node_data.merge(data, true)

	if node_data.get("position", Vector2.ZERO) == Vector2.ZERO:
		node_data.position = _graph_edit.scroll_offset + _graph_edit.size / 2 - Vector2(100, 50)

	if not node_data.has("id"):
		node_data.id = node_id

	_apply_type_defaults(node_data, node_type)

	if _undo_redo_helper:
		_undo_redo_helper.create_action("创建节点")
		_undo_redo_helper.add_undo_method(self, "_remove_node", node_id)
		_undo_redo_helper.add_redo_method(self, "_create_node_internal", node_data)
		_undo_redo_helper.commit_action()

	_create_node_internal(node_data)
	_mark_dirty()
	_update_status("创建%s" % str(_get_node_type_config(node_type).get("name", "节点")))
	return node_id

func _create_node_internal(data: Dictionary) -> void:
	var node = FLOW_GRAPH_NODE_SCRIPT.new()
	node.name = str(data.get("id", ""))
	node.position_offset = data.get("position", Vector2.ZERO)
	node.data_changed.connect(_on_node_data_changed)
	_graph_edit.add_child(node)
	nodes[str(data.get("id", ""))] = data
	_refresh_graph_node(node, data)

func _refresh_graph_node(node, data: Dictionary) -> void:
	var config := _get_node_type_config(str(data.get("type", "")))
	node.title = str(data.get("title", config.get("name", "节点")))
	node.update_data(data)
	node.set_visual_style(config.get("color", Color.GRAY))
	node.reset_content()
	_populate_node_preview(node, data)
	_configure_node_ports(node, data)
	if node.has_method("finalize_ports"):
		node.finalize_ports()

func _remove_node(node_id: String) -> void:
	var node = _graph_edit.get_node_or_null(node_id)
	if not node:
		return

	var removed_data: Dictionary = nodes.get(node_id, {}).duplicate(true)
	for conn in connections.duplicate():
		if conn.from == node_id or conn.to == node_id:
			_graph_edit.disconnect_node(StringName(conn.from), int(conn.from_port), StringName(conn.to), int(conn.to_port))
			connections.erase(conn)
			_update_node_disconnection(str(conn.from), int(conn.from_port), str(conn.to), int(conn.to_port))
			_on_connection_removed(conn)

	node.queue_free()
	nodes.erase(node_id)
	_on_node_removed(node_id, removed_data)

func _on_node_removed(_node_id: String, _removed_data: Dictionary) -> void:
	pass

func _populate_node_preview(node, data: Dictionary) -> void:
	node.add_text_row(str(data.get("title", data.get("id", "节点"))))

func _configure_node_ports(node, _data: Dictionary) -> void:
	node.add_input_port()
	node.add_output_port()

func _apply_type_defaults(_data: Dictionary, _node_type: String) -> void:
	pass

func _on_add_node_requested(node_type: String, graph_position: Vector2, pending_connection: Dictionary = {}) -> void:
	var new_node_id := _create_node(node_type, graph_position)
	if not pending_connection.is_empty():
		_connect_new_node_from_pending_connection(new_node_id, pending_connection)

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var from := String(from_node)
	var to := String(to_node)

	if _would_create_cycle(from, to):
		_update_status("无法创建循环连接")
		return

	for conn in connections.duplicate():
		if conn.from == from and int(conn.from_port) == from_port:
			_graph_edit.disconnect_node(StringName(conn.from), int(conn.from_port), StringName(conn.to), int(conn.to_port))
			connections.erase(conn)
			_on_connection_removed(conn)
			break

	_graph_edit.connect_node(from_node, from_port, to_node, to_port)

	var conn_data := {
		"from": from,
		"from_port": from_port,
		"to": to,
		"to_port": to_port
	}
	connections.append(conn_data)
	_on_connection_added(conn_data)
	_update_node_connection(from, from_port, to, to_port)
	_mark_dirty()

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	_graph_edit.disconnect_node(from_node, from_port, to_node, to_port)

	var from := String(from_node)
	var to := String(to_node)
	for i in range(connections.size() - 1, -1, -1):
		var conn: Dictionary = connections[i]
		if conn.from == from and int(conn.from_port) == from_port and conn.to == to and int(conn.to_port) == to_port:
			connections.remove_at(i)
			_on_connection_removed(conn)
			_update_node_disconnection(from, from_port, to, to_port)
			_mark_dirty()
			break

func _on_connection_added(_conn: Dictionary) -> void:
	pass

func _on_connection_removed(_conn: Dictionary) -> void:
	pass

func _would_create_cycle(from: String, to: String) -> bool:
	var visited := {}
	var queue := [to]

	while queue.size() > 0:
		var current: String = str(queue.pop_front())
		if current == from:
			return true
		if visited.has(current):
			continue
		visited[current] = true

		for conn in connections:
			if conn.from == current:
				queue.append(conn.to)

	return false

func _connect_new_node_from_pending_connection(new_node_id: String, pending_connection: Dictionary) -> void:
	if new_node_id.is_empty() or pending_connection.is_empty():
		return

	var direction := str(pending_connection.get("direction", ""))
	var existing_node_id := str(pending_connection.get("node_id", ""))
	var existing_port := int(pending_connection.get("port", 0))
	var new_node = _graph_edit.get_node_or_null(new_node_id)
	if not (new_node and new_node is GraphNode):
		return

	match direction:
		"from_output":
			var input_port := _find_first_enabled_port(new_node, true)
			if input_port >= 0:
				_on_connection_request(StringName(existing_node_id), existing_port, StringName(new_node_id), input_port)
		"to_input":
			var output_port := _find_first_enabled_port(new_node, false)
			if output_port >= 0:
				_on_connection_request(StringName(new_node_id), output_port, StringName(existing_node_id), existing_port)

func _find_first_enabled_port(graph_node: GraphNode, is_input: bool) -> int:
	var slot_index := 0
	while true:
		var enabled := false
		if is_input:
			if not graph_node.has_method("is_slot_enabled_left"):
				return -1
			enabled = bool(graph_node.call("is_slot_enabled_left", slot_index))
		else:
			if not graph_node.has_method("is_slot_enabled_right"):
				return -1
			enabled = bool(graph_node.call("is_slot_enabled_right", slot_index))

		if enabled:
			return slot_index

		slot_index += 1
		if slot_index > 31:
			break

	return -1

func _update_node_connection(_from_id: String, _from_port: int, _to_id: String, _to_port: int) -> void:
	pass

func _update_node_disconnection(_from_id: String, _from_port: int, _to_id: String, _to_port: int) -> void:
	pass

func _on_node_selected(node: Node) -> void:
	if node is GraphNode:
		var node_id := String(node.name)
		if selected_node_id == node_id and _inspected_node_id == node_id:
			return
		selected_node_id = node_id
		_inspected_node_id = node_id
		_queue_property_panel_update(node.node_data)
		selection_changed.emit([node])

func _on_node_deselected(node: Node) -> void:
	if node is GraphNode and node.selected:
		return
	if selected_node_id == String(node.name):
		_clear_selection_state()
		selection_changed.emit([])

func _on_delete_nodes_request(nodes_to_delete: Array) -> void:
	if nodes_to_delete.is_empty():
		return

	var ids_to_delete: Array[String] = []
	for node_name in nodes_to_delete:
		var node_id := String(node_name)
		if nodes.has(node_id):
			ids_to_delete.append(node_id)

	if ids_to_delete.is_empty():
		return

	if _undo_redo_helper:
		_undo_redo_helper.create_action("删除节点")
		for node_id in ids_to_delete:
			var data = nodes[node_id].duplicate(true)
			_undo_redo_helper.add_undo_method(self, "_create_node_internal", data)
			_undo_redo_helper.add_redo_method(self, "_remove_node", node_id)
		_undo_redo_helper.commit_action()

	for node_id in ids_to_delete:
		_remove_node(node_id)

	_clear_selection_state()
	_mark_dirty()
	_update_status("已删除 %d 个节点" % ids_to_delete.size())

func _on_delete_selected() -> void:
	var selected = _graph_edit.get_selected_nodes()
	if selected.is_empty():
		return

	var ids: Array[StringName] = []
	for node in selected:
		ids.append(node.name)
	_on_delete_nodes_request(ids)

func _on_node_data_changed(node_id: String, new_data: Dictionary) -> void:
	var previous_data: Dictionary = nodes.get(node_id, {}).duplicate(true)
	nodes[node_id] = new_data
	var node = _graph_edit.get_node_or_null(node_id)
	var is_position_only_update := _is_position_only_update(previous_data, new_data)
	if node and node is GraphNode and not is_position_only_update:
		_refresh_graph_node(node, new_data)
	if node_id == selected_node_id and _inspected_node_id == node_id and not is_position_only_update:
		_queue_property_panel_update(new_data)
	_after_node_data_changed(node_id, previous_data, new_data, is_position_only_update)

func _update_property_panel(data: Dictionary) -> void:
	_property_panel.clear()
	if not data.is_empty():
		_property_panel.add_readonly_label("id", "节点ID:", str(data.get("id", "")))
		_property_panel.add_readonly_label("type", "类型:", str(data.get("type", "")))

func _on_property_changed(property_name: String, new_value: Variant, old_value: Variant) -> void:
	if selected_node_id.is_empty():
		return

	var data = nodes.get(selected_node_id)
	if not data:
		return

	if _undo_redo_helper:
		_undo_redo_helper.create_action("修改 %s" % property_name)
		_undo_redo_helper.add_undo_method(self, "_set_property", selected_node_id, property_name, old_value)
		_undo_redo_helper.add_redo_method(self, "_set_property", selected_node_id, property_name, new_value)
		_undo_redo_helper.commit_action()

	_set_property(selected_node_id, property_name, new_value)

func _set_property(node_id: String, property_name: String, value: Variant) -> void:
	var data = nodes.get(node_id)
	if not data:
		return

	data[property_name] = value
	nodes[node_id] = data
	_on_node_data_changed(node_id, data)

func _get_search_strings(data: Dictionary) -> Array[String]:
	var values: Array[String] = []
	for key in ["id", "title", "text", "speaker"]:
		if data.has(key):
			values.append(str(data.get(key, "")))
	return values

func _on_search_text_changed(text: String) -> void:
	if text.is_empty():
		for node in _graph_edit.get_all_nodes():
			node.modulate = Color.WHITE
		return

	var search_lower := text.to_lower()
	var match_count := 0
	for node in _graph_edit.get_all_nodes():
		var data: Dictionary = node.node_data
		var match_found := false
		for candidate in _get_search_strings(data):
			if candidate.to_lower().contains(search_lower):
				match_found = true
				break

		if match_found:
			node.modulate = Color.WHITE
			match_count += 1
		else:
			node.modulate = Color(0.5, 0.5, 0.5, 0.5)

	_update_status("找到 %d 个匹配节点" % match_count)

func _on_copy_nodes() -> void:
	var selected = _graph_edit.get_selected_nodes()
	if selected.is_empty():
		return
	_sync_node_positions_from_graph()

	if selected.size() == 1:
		_clipboard.copy_node(selected[0].node_data, str(selected[0].node_data.get("type", "")))
	else:
		var datas: Array[Dictionary] = []
		for node in selected:
			datas.append(node.node_data)
		_clipboard.copy_nodes(datas, "batch")

	_update_status("已复制 %d 个节点" % selected.size())

func _normalize_pasted_node_data(data: Dictionary) -> Dictionary:
	return data

func _on_paste_nodes() -> void:
	if not _clipboard.has_data():
		return

	if _clipboard.get_clipboard_type() == "batch":
		var pasted: Array[Dictionary] = _clipboard.paste_nodes()
		for data in pasted:
			var normalized := _normalize_pasted_node_data(data)
			if not normalized.is_empty():
				_create_node_internal(normalized)
		if not pasted.is_empty():
			_mark_dirty()
		_update_status("已粘贴 %d 个节点" % pasted.size())
	else:
		var pasted = _clipboard.paste_node()
		if pasted.is_empty():
			return
		var normalized := _normalize_pasted_node_data(pasted)
		if normalized.is_empty():
			return
		_create_node_internal(normalized)
		_mark_dirty()
		_update_status("已粘贴节点")

func _on_undo() -> void:
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().undo()
		_update_status("撤销")

func _on_redo() -> void:
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().redo()
		_update_status("重做")

func _on_center_view() -> void:
	_graph_edit.center_view()
	_update_status("已居中视图")

func _update_status(message: String) -> void:
	_status_bar.text = message
	print("%s %s" % [_get_editor_name(), message])

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_main_split_layout()

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_DELETE:
				_on_delete_selected()
			KEY_Z when event.ctrl_pressed and not event.shift_pressed:
				_on_undo()
			KEY_Y when event.ctrl_pressed:
				_on_redo()
			KEY_C when event.ctrl_pressed:
				_on_copy_nodes()
			KEY_V when event.ctrl_pressed:
				_on_paste_nodes()

func get_nodes_count() -> int:
	return nodes.size()

func get_connections_count() -> int:
	return connections.size()

func has_unsaved_changes() -> bool:
	return _dirty

func _set_dirty_state(is_dirty: bool) -> void:
	if _dirty == is_dirty:
		return
	_dirty = is_dirty
	dirty_state_changed.emit(_dirty)
	_refresh_record_list()

func _mark_dirty() -> void:
	if _dirty_tracking_suspension > 0:
		return
	_set_dirty_state(true)

func _clear_dirty_state() -> void:
	_set_dirty_state(false)

func _begin_dirty_tracking_suspension() -> void:
	_dirty_tracking_suspension += 1

func _end_dirty_tracking_suspension() -> void:
	_dirty_tracking_suspension = maxi(_dirty_tracking_suspension - 1, 0)

func request_window_close(on_close: Callable) -> void:
	if not has_unsaved_changes():
		if on_close.is_valid():
			on_close.call()
		return

	_pending_close_callback = on_close
	_close_confirmation_dialog.dialog_text = _get_unsaved_changes_dialog_text()
	_close_confirmation_dialog.popup_centered(Vector2i(420, 180))

func _get_unsaved_changes_dialog_text() -> String:
	return "当前编辑器有未保存的更改，是否先保存？"

func _save_before_close() -> bool:
	return false

func _after_node_data_changed(_node_id: String, previous_data: Dictionary, new_data: Dictionary, _is_position_only_update: bool) -> void:
	if previous_data != new_data:
		_mark_dirty()

func _on_close_dialog_confirmed() -> void:
	if not _save_before_close():
		return
	_finish_pending_close()

func _on_close_dialog_custom_action(action: StringName) -> void:
	if String(action) != "discard":
		return
	_finish_pending_close()

func _on_close_dialog_canceled() -> void:
	_pending_close_callback = Callable()

func _finish_pending_close() -> void:
	var callback := _pending_close_callback
	_pending_close_callback = Callable()
	if callback.is_valid():
		callback.call()

func _sync_node_positions_from_graph() -> void:
	if not _graph_edit:
		return

	for graph_node in _graph_edit.get_all_nodes():
		var node_id := str(graph_node.name)
		if not nodes.has(node_id):
			continue
		var data: Dictionary = nodes[node_id]
		data["position"] = graph_node.position_offset
		nodes[node_id] = data

func _clear_selection_state() -> void:
	selected_node_id = ""
	_inspected_node_id = ""
	_pending_property_panel_data.clear()
	_property_panel_refresh_pending = false
	if _property_panel:
		_property_panel.clear()

func _queue_property_panel_update(data: Dictionary) -> void:
	_pending_property_panel_data = data.duplicate(true)
	if _property_panel_refresh_pending:
		return
	_property_panel_refresh_pending = true
	call_deferred("_flush_property_panel_update")

func _flush_property_panel_update() -> void:
	_property_panel_refresh_pending = false
	if not _property_panel:
		return
	if _pending_property_panel_data.is_empty():
		_property_panel.clear()
		return
	_update_property_panel(_pending_property_panel_data)

func _update_main_split_layout() -> void:
	if not _main_split or not is_instance_valid(_main_split):
		return

	var total_width := int(_main_split.size.x)
	if total_width <= 0:
		return

	var side_panel_width := _get_side_panel_width()
	var min_graph_width := _get_min_graph_width()
	if _has_record_list():
		min_graph_width += MIN_RECORD_LIST_WIDTH
	var max_side_panel_width := maxi(MIN_SIDE_PANEL_WIDTH, total_width - min_graph_width)
	side_panel_width = clampi(side_panel_width, MIN_SIDE_PANEL_WIDTH, max_side_panel_width)
	if _right_container and is_instance_valid(_right_container):
		_right_container.custom_minimum_size = Vector2(side_panel_width, 0)

	var desired_content_width := total_width - side_panel_width
	var min_content_width := mini(420, maxi(220, total_width - MIN_SIDE_PANEL_WIDTH))
	var max_content_width := maxi(min_content_width, total_width - MIN_SIDE_PANEL_WIDTH)
	var split_offset := clampi(desired_content_width, min_content_width, max_content_width)
	_main_split.split_offset = split_offset

	if _content_split and is_instance_valid(_content_split):
		var content_width := int(_content_split.size.x)
		if content_width <= 0:
			content_width = split_offset
		var record_list_width := _get_record_list_width()
		var max_record_list_width := maxi(MIN_RECORD_LIST_WIDTH, content_width - _get_min_graph_width())
		record_list_width = clampi(record_list_width, MIN_RECORD_LIST_WIDTH, max_record_list_width)
		if _record_list_container and is_instance_valid(_record_list_container):
			_record_list_container.custom_minimum_size = Vector2(record_list_width, 0)
		_content_split.split_offset = record_list_width

func _is_position_only_update(previous_data: Dictionary, new_data: Dictionary) -> bool:
	if previous_data.is_empty():
		return false
	if previous_data == new_data:
		return false

	var previous_without_position := previous_data.duplicate(true)
	var new_without_position := new_data.duplicate(true)
	previous_without_position.erase("position")
	new_without_position.erase("position")

	return previous_without_position == new_without_position
