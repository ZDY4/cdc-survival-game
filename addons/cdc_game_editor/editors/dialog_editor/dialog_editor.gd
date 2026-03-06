@tool
extends Control
## 对话编辑器
## 集成撤销/重做、属性面板、搜索、复制粘贴等功能

signal dialog_saved(dialog_id: String)
signal dialog_loaded(dialog_id: String)
signal selection_changed(selected_nodes: Array[GraphNode])

# 常量
const NODE_COLORS = {
	"dialog": Color(0.2, 0.6, 0.9),
	"choice": Color(0.9, 0.6, 0.2),
	"condition": Color(0.9, 0.2, 0.6),
	"action": Color(0.2, 0.9, 0.4),
	"end": Color(0.9, 0.2, 0.2)
}

const NODE_TYPE_NAMES = {
	"dialog": "对话节点",
	"choice": "选择节点",
	"condition": "条件节点",
	"action": "动作节点",
	"end": "结束节点"
}

const JSON_VALIDATOR = preload("res://addons/cdc_game_editor/utils/json_validator.gd")

# 节点引用
@onready var _graph_edit: Control
@onready var _property_panel: Control
@onready var _toolbar: HBoxContainer
@onready var _search_box: LineEdit
@onready var _file_dialog: FileDialog
@onready var _status_bar: Label

# 数据
var current_dialog_id: String = ""
var current_file_path: String = ""
var nodes: Dictionary = {}  # id -> node_data
var connections: Array[Dictionary] = []
var selected_node_id: String = ""

# 工具
var _undo_redo_helper: RefCounted
var _clipboard: RefCounted

# 编辑器插件引用于获取undo_redo
var editor_plugin: EditorPlugin = null:
	set(plugin):
		editor_plugin = plugin
		if plugin:
			_undo_redo_helper = load("res://addons/cdc_game_editor/utils/undo_redo_helper.gd").new(plugin)

func _ready():
	_clipboard = load("res://addons/cdc_game_editor/utils/editor_clipboard.gd").get_instance()
	_setup_ui()
	_setup_file_dialog()
	_setup_shortcuts()

func _setup_ui():
	anchors_preset = Control.PRESET_FULL_RECT
	
	# 创建工具栏
	_toolbar = HBoxContainer.new()
	_toolbar.custom_minimum_size = Vector2(0, 45)
	_toolbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toolbar.offset_top = 0
	_toolbar.offset_bottom = 45
	add_child(_toolbar)
	_create_toolbar()
	
	# 创建主分割容器
	var main_split = HSplitContainer.new()
	main_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_split.offset_top = 50
	main_split.offset_bottom = -20
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main_split)
	
	# 左侧：GraphEdit画布
	var left_container = VBoxContainer.new()
	left_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_child(left_container)
	
	# 搜索
	var search_container = HBoxContainer.new()
	search_container.custom_minimum_size = Vector2(0, 30)
	left_container.add_child(search_container)
	
	var search_label = Label.new()
	search_label.text = "🔍"
	search_container.add_child(search_label)
	
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "搜索节点..."
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.text_changed.connect(_on_search_text_changed)
	search_container.add_child(_search_box)
	
	var clear_btn = Button.new()
	clear_btn.text = "清除"
	clear_btn.pressed.connect(func(): _search_box.clear(); _on_search_text_changed(""))
	search_container.add_child(clear_btn)
	
	# GraphEdit
	_graph_edit = preload("dialog_graph_editor.gd").new()
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_edit.connection_request.connect(_on_connection_request)
	_graph_edit.disconnection_request.connect(_on_disconnection_request)
	_graph_edit.node_selected.connect(_on_node_selected)
	_graph_edit.node_deselected.connect(_on_node_deselected)
	_graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
	_graph_edit.gui_input.connect(_on_graph_gui_input)
	left_container.add_child(_graph_edit)
	
	# 右侧：属性面板
	_property_panel = preload("res://addons/cdc_game_editor/utils/property_panel.gd").new()
	_property_panel.custom_minimum_size = Vector2(320, 0)
	_property_panel.panel_title = "Node Properties"
	_property_panel.property_changed.connect(_on_property_changed)
	main_split.add_child(_property_panel)
	
	main_split.split_offset = -320
	
	# 状态栏
	_status_bar = Label.new()
	_status_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status_bar.offset_top = -20
	_status_bar.offset_bottom = 0
	_status_bar.offset_left = 0
	_status_bar.offset_right = 0
	_status_bar.text = "就绪"
	add_child(_status_bar)

func _create_toolbar():
	# 文件操作
	_add_toolbar_button("新建", _on_new_dialog, "新建对话")
	_add_toolbar_button("打开", _on_open_dialog, "打开对话文件")
	_add_toolbar_button("保存", _on_save_dialog, "保存对话文件")
	_toolbar.add_child(VSeparator.new())
	
	# 编辑操作
	_add_toolbar_button("撤销", _on_undo, "撤销上一步操(Ctrl+Z)")
	_add_toolbar_button("重做", _on_redo, "重做操作 (Ctrl+Y)")
	_toolbar.add_child(VSeparator.new())
	
	# 节点操作
	_add_toolbar_button("复制", _on_copy_nodes, "复制选中节点 (Ctrl+C)")
	_add_toolbar_button("粘贴", _on_paste_nodes, "粘贴节点 (Ctrl+V)")
	_add_toolbar_button("删除", _on_delete_selected, "删除选中节点 (Delete)")
	_toolbar.add_child(VSeparator.new())
	
	# 导出
	_add_toolbar_button("导出JSON", _on_export_json, "导出为JSON格式")
	_add_toolbar_button("导出GD", _on_export_gdscript, "导出为GDScript格式")
	_toolbar.add_child(VSeparator.new())
	
	# 视图操作
	_add_toolbar_button("居中", _on_center_view, "居中视图")

func _add_toolbar_button(text: String, callback: Callable, tooltip: String = ""):
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.pressed.connect(callback)
	_toolbar.add_child(btn)

func _setup_file_dialog():
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.json; JSON 文件")
	_file_dialog.add_filter("*.dlg; 对话文件")
	add_child(_file_dialog)

func _setup_shortcuts():
	#  _input _gui_input 
	pass

func _input(event: InputEvent):
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

# 节点创建
func _create_node(type: String, position: Vector2 = Vector2.ZERO, data: Dictionary = {}):
	var node_id = _generate_node_id()
	
	if position == Vector2.ZERO:
		position = _graph_edit.scroll_offset + _graph_edit.size / 2 - Vector2(100, 50)
	
	var node_data = {
		"id": node_id,
		"type": type,
		"position": position,
		"title": NODE_TYPE_NAMES.get(type, "未知节点")
	}
	
	# 合并传入的数
	node_data.merge(data, true)
	
	# 设置类型默认数据
	_apply_type_defaults(node_data, type)
	
	# 创建撤销动作
	if _undo_redo_helper:
		_undo_redo_helper.create_action("创建节点")
		_undo_redo_helper.add_undo_method(self, "_remove_node", node_id)
		_undo_redo_helper.add_redo_method(self, "_create_node_internal", node_data)
		_undo_redo_helper.commit_action()
	
	_create_node_internal(node_data)
	_update_status("创建%s" % NODE_TYPE_NAMES.get(type, "节点"))

func _create_node_internal(data: Dictionary):
	var node = preload("dialog_node.gd").new()
	node.name = data.id
	node.title = data.get("title", NODE_TYPE_NAMES.get(data.type, "节点"))
	node.position_offset = data.position
	node.set_color(NODE_COLORS.get(data.type, Color.GRAY))
	node.node_data = data
	node.data_changed.connect(_on_node_data_changed)
	
	# 添加端口
	_add_node_ports(node, data)
	
	_graph_edit.add_child(node)
	nodes[data.id] = data

func _add_node_ports(node: GraphNode, data: Dictionary):
	match data.type:
		"dialog", "action":
			node.add_input_port("输入")
			node.add_output_port("输出")
		"choice":
			node.add_input_port("输入")
			var options = data.get("options", [])
			for i in range(options.size()):
				node.add_output_port("选项%d" % (i + 1))
		"condition":
			node.add_input_port("输入")
			node.add_output_port("True")
			node.add_output_port("False")
		"end":
			node.add_input_port("输入")

func _apply_type_defaults(data: Dictionary, type: String):
	match type:
		"dialog":
			if not data.has("text"):
				data.text = "请输入话文.."
			if not data.has("speaker"):
				data.speaker = "NPC"
			if not data.has("portrait"):
				data.portrait = ""
		"choice":
			if not data.has("options"):
				data.options = [
					{"text": "选项1", "next": ""},
					{"text": "选项2", "next": ""}
				]
		"condition":
			if not data.has("condition"):
				data.condition = "GameState.player_hp > 50"
			if not data.has("true_next"):
				data.true_next = ""
			if not data.has("false_next"):
				data.false_next = ""
		"action":
			if not data.has("actions"):
				data.actions = [{"type": "give_item", "params": {}}]
		"end":
			if not data.has("end_type"):
				data.end_type = "normal"

func _remove_node(node_id: String):
	var node = _graph_edit.get_node_or_null(node_id)
	if node:
		# 移除相关连接
		for conn in connections.duplicate():
			if conn.from == node_id or conn.to == node_id:
				_graph_edit.disconnect_node(
					StringName(conn.from), conn.from_port,
					StringName(conn.to), conn.to_port
				)
				connections.erase(conn)
		
		node.queue_free()
		nodes.erase(node_id)

func _generate_node_id() -> String:
	return "dlg_%d" % Time.get_ticks_msec()

# 属面
func _update_property_panel(data: Dictionary):
	_property_panel.clear()
	
	if data.is_empty():
		return
	
	# ID（只读）
	_property_panel.add_readonly_label("id", "节点ID:", data.id)
	
	# 类型（只读）
	_property_panel.add_readonly_label("type", "类型:", NODE_TYPE_NAMES.get(data.type, data.type))
	
	_property_panel.add_separator()
	
	# 根据类型显示不同属
	match data.type:
		"dialog":
			_property_panel.add_string_property("speaker", "说话", data.get("speaker", ""))
			_property_panel.add_string_property("text", "对话内容:", data.get("text", ""), true, "输入对话文本...")
			_property_panel.add_string_property("portrait", "头像路径:", data.get("portrait", ""), false, "res://assets/portraits/...")
		
		"choice":
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_choice_editor(data))
		
		"condition":
			_property_panel.add_string_property("condition", "条件表达", data.get("condition", ""), true, "杈撳叆鏉′欢浠ｇ爜...")
		
		"action":
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_action_editor(data))
		
		"end":
			var end_types = {"normal": "Normal End", "success": "Success End", "fail": "Fail End"}
			_property_panel.add_enum_property("end_type", "结束类型:", end_types, data.get("end_type", "normal"))

func _create_choice_editor(data: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "选项列表:"
	container.add_child(label)
	
	var options = data.get("options", [])
	for i in range(options.size()):
		var option = options[i]
		var hbox = HBoxContainer.new()
		
		var idx_label = Label.new()
		idx_label.text = "%d." % (i + 1)
		idx_label.custom_minimum_size = Vector2(25, 0)
		hbox.add_child(idx_label)
		
		var edit = LineEdit.new()
		edit.text = option.text
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_changed.connect(func(v): option.text = v; _on_node_data_changed(data.id, data))
		hbox.add_child(edit)
		
		var del_btn = Button.new()
		del_btn.text = "×"
		del_btn.tooltip_text = "删除选项"
		del_btn.pressed.connect(func(): _remove_choice_option(data, i))
		hbox.add_child(del_btn)
		
		container.add_child(hbox)
	
	var add_btn = Button.new()
	add_btn.text = "+ 添加选项"
	add_btn.pressed.connect(func(): _add_choice_option(data))
	container.add_child(add_btn)
	
	return container

func _add_choice_option(data: Dictionary):
	if not data.has("options"):
		data.options = []
	data.options.append({"text": "新选项", "next": ""})
	_update_property_panel(data)
	_on_node_data_changed(data.id, data)

func _remove_choice_option(data: Dictionary, index: int):
	if data.has("options") and index < data.options.size():
		data.options.remove_at(index)
		_update_property_panel(data)
		_on_node_data_changed(data.id, data)

func _create_action_editor(data: Dictionary) -> Control:
	var label = Label.new()
	label.text = "Action editor (WIP)\nPlease edit actions in code."
	label.modulate = Color.GRAY
	return label

# 事件处理
func _on_graph_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_show_context_menu(event.position)

func _show_context_menu(position: Vector2):
	var menu = PopupMenu.new()
	
	var types = [
		{"id": 0, "name": "对话节点", "type": "dialog"},
		{"id": 1, "name": "选择节点", "type": "choice"},
		{"id": 2, "name": "条件节点", "type": "condition"},
		{"id": 3, "name": "动作节点", "type": "action"},
		{"id": 4, "name": "结束节点", "type": "end"}
	]
	
	for t in types:
		menu.add_item(t.name, t.id)
	
	menu.id_pressed.connect(func(id):
		for t in types:
			if t.id == id:
				var graph_pos = position + _graph_edit.scroll_offset
				_create_node(t.type, graph_pos)
				break
		menu.queue_free()
	)
	
	add_child(menu)
	menu.position = get_global_mouse_position()
	menu.popup()

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	var from = String(from_node)
	var to = String(to_node)
	
	# 查循
	if _would_create_cycle(from, to):
		_update_status("无法创建连接")
		return
	
	# 移除同一端口的旧连接
	for conn in connections.duplicate():
		if conn.from == from and conn.from_port == from_port:
			_graph_edit.disconnect_node(StringName(conn.from), conn.from_port, StringName(conn.to), conn.to_port)
			connections.erase(conn)
			break
	
	_graph_edit.connect_node(from_node, from_port, to_node, to_port)
	
	var conn_data = {
		"from": from,
		"from_port": from_port,
		"to": to,
		"to_port": to_port
	}
	connections.append(conn_data)
	
	# 更新节点数据
	_update_node_connection(from, from_port, to)

func _would_create_cycle(from: String, to: String) -> bool:
	# 化的测：查目标节点是否能到达源节
	var visited = {}
	var queue = [to]
	
	while queue.size() > 0:
		var current = queue.pop_front()
		if current == from:
			return true
		if visited.has(current):
			continue
		visited[current] = true
		
		# 找到从current出发的所有连
		for conn in connections:
			if conn.from == current:
				queue.append(conn.to)
	
	return false

func _update_node_connection(from_id: String, from_port: int, to_id: String):
	var from_data = nodes.get(from_id)
	if not from_data:
		return
	
	match from_data.type:
		"dialog", "action":
			from_data["next"] = to_id
		"choice":
			var options = from_data.get("options", [])
			if from_port < options.size():
				options[from_port].next = to_id
		"condition":
			if from_port == 0:
				from_data["true_next"] = to_id
			else:
				from_data["false_next"] = to_id

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	_graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	
	var from = String(from_node)
	var to = String(to_node)
	
	for i in range(connections.size() - 1, -1, -1):
		var conn = connections[i]
		if conn.from == from and conn.to == to:
			connections.remove_at(i)
			_update_node_disconnection(from, conn.from_port)
			break

func _update_node_disconnection(from_id: String, from_port: int):
	var from_data = nodes.get(from_id)
	if not from_data:
		return
	
	match from_data.type:
		"dialog", "action":
			from_data["next"] = ""
		"choice":
			var options = from_data.get("options", [])
			if from_port < options.size():
				options[from_port].next = ""
		"condition":
			if from_port == 0:
				from_data["true_next"] = ""
			else:
				from_data["false_next"] = ""

func _on_node_selected(node: Node):
	if node is GraphNode:
		selected_node_id = node.name
		_update_property_panel(node.node_data)
		selection_changed.emit([node])

func _on_node_deselected(node: Node):
	if selected_node_id == String(node.name):
		selected_node_id = ""
		_property_panel.clear()
		selection_changed.emit([])

func _on_delete_nodes_request(nodes_to_delete: Array):
	if nodes_to_delete.is_empty():
		return
	
	var ids_to_delete: Array[String] = []
	for node_name in nodes_to_delete:
		var id = String(node_name)
		if nodes.has(id):
			ids_to_delete.append(id)
	
	if ids_to_delete.is_empty():
		return
	
	# 创建撤销动作
	if _undo_redo_helper:
		_undo_redo_helper.create_action("删除节点")
		
		for node_id in ids_to_delete:
			var data = nodes[node_id].duplicate(true)
			_undo_redo_helper.add_undo_method(self, "_create_node_internal", data)
			_undo_redo_helper.add_redo_method(self, "_remove_node", node_id)
		
		_undo_redo_helper.commit_action()
	
	for node_id in ids_to_delete:
		_remove_node(node_id)
	
	_property_panel.clear()
	_update_status("Deleted %d nodes" % ids_to_delete.size())

func _on_delete_selected():
	var selected = _graph_edit.get_selected_nodes()
	if selected.size() > 0:
		var ids: Array[StringName] = []
		for node in selected:
			ids.append(node.name)
		_on_delete_nodes_request(ids)

func _on_node_data_changed(node_id: String, new_data: Dictionary):
	nodes[node_id] = new_data
	var node = _graph_edit.get_node_or_null(node_id)
	if node and node is GraphNode:
		node.update_data(new_data)

func _on_property_changed(property_name: String, new_value: Variant, old_value: Variant):
	if selected_node_id.is_empty():
		return
	
	var data = nodes.get(selected_node_id)
	if not data:
		return
	
	# 创建撤销动作
	if _undo_redo_helper:
		_undo_redo_helper.create_action("修改 %s" % property_name)
		_undo_redo_helper.add_undo_method(self, "_set_property", selected_node_id, property_name, old_value)
		_undo_redo_helper.add_redo_method(self, "_set_property", selected_node_id, property_name, new_value)
		_undo_redo_helper.commit_action()
	
	_set_property(selected_node_id, property_name, new_value)

func _set_property(node_id: String, property: String, value: Variant):
	var data = nodes.get(node_id)
	if data:
		data[property] = value
		nodes[node_id] = data
		_on_node_data_changed(node_id, data)
		
		# 如果当前选中节点就是的节点，更新属面
		if node_id == selected_node_id:
			# 重新加载属性面板以反映变化
			var node = _graph_edit.get_node_or_null(node_id)
			if node:
				_update_property_panel(node.node_data)

# 复制粘贴
func _on_copy_nodes():
	var selected = _graph_edit.get_selected_nodes()
	if selected.is_empty():
		return
	
	if selected.size() == 1:
		_clipboard.copy_node(selected[0].node_data, selected[0].node_data.type)
	else:
		var datas: Array[Dictionary] = []
		for node in selected:
			datas.append(node.node_data)
		_clipboard.copy_nodes(datas, "batch")
	
	_update_status("Copied %d nodes" % selected.size())

func _on_paste_nodes():
	if not _clipboard.has_data():
		return
	
	if _clipboard.get_clipboard_type() == "batch":
		var pasted = _clipboard.paste_nodes()
		for data in pasted:
			_create_node_internal(data)
		_update_status("Pasted %d nodes" % pasted.size())
	else:
		var pasted = _clipboard.paste_node()
		if not pasted.is_empty():
			_create_node_internal(pasted)
			_update_status("Pasted node")

# 搜索
func _on_search_text_changed(text: String):
	if text.is_empty():
		# 重置有节点的
		for node in _graph_edit.get_all_nodes():
			node.modulate = Color.WHITE
		return
	
	var search_lower = text.to_lower()
	var match_count = 0
	
	for node in _graph_edit.get_all_nodes():
		var data = node.node_data
		var match_found = false
		
		# 搜索ID
		if data.id.to_lower().contains(search_lower):
			match_found = true
		# 搜索文本内容
		elif data.has("text") and data.text.to_lower().contains(search_lower):
			match_found = true
		# 搜索说话
		elif data.has("speaker") and data.speaker.to_lower().contains(search_lower):
			match_found = true
		
		if match_found:
			node.modulate = Color.WHITE
			match_count += 1
		else:
			node.modulate = Color(0.5, 0.5, 0.5, 0.5)
	
	_update_status("Found %d matching nodes" % match_count)

# 工具栏功
func _on_new_dialog():
	current_dialog_id = ""
	current_file_path = ""
	nodes.clear()
	connections.clear()
	selected_node_id = ""
	_graph_edit.clear_graph()
	_property_panel.clear()
	_update_status("新建对话")

func _on_open_dialog():
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.file_selected.connect(_load_dialog, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _on_save_dialog():
	if current_file_path.is_empty():
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.current_file = "dialog.json"
		_file_dialog.file_selected.connect(_save_dialog_to_path, CONNECT_ONE_SHOT)
		_file_dialog.popup_centered(Vector2(800, 600))
	else:
		_save_dialog_to_path(current_file_path)

func _load_dialog(path: String):
	_on_new_dialog()

	var validation := JSON_VALIDATOR.validate_file(path, {
		"root_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"fields": [
			{
				"key": "nodes",
				"required": true,
				"type": JSON_VALIDATOR.TYPE_ARRAY,
				"entry_type": JSON_VALIDATOR.TYPE_DICTIONARY,
				"entry_label": "nodes"
			},
			{
				"key": "connections",
				"required": true,
				"type": JSON_VALIDATOR.TYPE_ARRAY,
				"entry_type": JSON_VALIDATOR.TYPE_DICTIONARY,
				"entry_label": "connections",
				"entry_required_keys": ["from", "to", "from_port", "to_port"]
			}
		]
	})
	if not bool(validation.get("ok", false)):
		_update_status(str(validation.get("message", "[JSON] Unknown validation error")))
		return

	var root_data: Variant = validation.get("data", {})
	if not (root_data is Dictionary):
		_update_status("[JSON] %s | Invalid validator result: data must be Dictionary" % path)
		return
	var data: Dictionary = root_data

	var loaded_nodes: Array = data.get("nodes", [])
	var loaded_connections: Array = data.get("connections", [])
	
	current_dialog_id = str(data.get("dialog_id", ""))
	current_file_path = path
	
	for node_data in loaded_nodes:
		_create_node_internal(node_data)
	
	connections = loaded_connections
	for conn_data in connections:
		var from_node: StringName = StringName(str(conn_data.get("from", "")))
		var to_node: StringName = StringName(str(conn_data.get("to", "")))
		var from_port: int = int(conn_data.get("from_port", 0))
		var to_port: int = int(conn_data.get("to_port", 0))
		_graph_edit.connect_node(from_node, from_port, to_node, to_port)
	
	dialog_loaded.emit(current_dialog_id)
	_update_status("Loaded: %s" % current_dialog_id)

func _save_dialog_to_path(path: String):
	current_file_path = path
	
	var data = {
		"dialog_id": current_dialog_id if not current_dialog_id.is_empty() else "dialog_%d" % Time.get_ticks_msec(),
		"nodes": nodes.values(),
		"connections": connections
	}
	
	var json = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		dialog_saved.emit(data.dialog_id)
		_update_status("已保 %s" % path)
	else:
		_update_status("无法保存文件")

func _on_export_json():
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "dialog_export.json"
	_file_dialog.file_selected.connect(func(path):
		_save_dialog_to_path(path)
	, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _on_export_gdscript():
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "dialog_data.gd"
	_file_dialog.file_selected.connect(func(path):
		var output = _build_gdscript()
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(output)
			file.close()
			_update_status("已出GDScript")
	, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _build_gdscript() -> String:
	var lines: Array[String] = []
	lines.append("# Auto-generated dialog data")
	lines.append("# 生成时间: %s" % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("const DIALOGS = {")
	
	var dialog_key = current_dialog_id if not current_dialog_id.is_empty() else "dialog_001"
	lines.append('\t"%s": {' % dialog_key)
	lines.append('\t\t"nodes": [')
	
	for node_id in nodes:
		var node = nodes[node_id]
		lines.append('\t\t\t{')
		for key in node:
			var value = node[key]
			if value is String:
				lines.append('\t\t\t\t"%s": "%s",' % [key, value])
			else:
				lines.append('\t\t\t\t"%s": %s,' % [key, str(value)])
		lines.append('\t\t\t},')
	
	lines.append('\t\t],')
	lines.append('\t\t"connections": [')
	for conn in connections:
		lines.append('\t\t\t{')
		lines.append('\t\t\t\t"from": "%s",' % conn.from)
		lines.append('\t\t\t\t"to": "%s",' % conn.to)
		lines.append('\t\t\t},')
	lines.append('\t\t],')
	lines.append('\t}')
	lines.append('}')
	lines.append("")
	lines.append("static func get_dialog(dialog_id: String):")
	lines.append("\treturn DIALOGS.get(dialog_id, {})")
	
	return "\n".join(lines)

func _on_undo():
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().undo()
		_update_status("撤销")

func _on_redo():
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().redo()
		_update_status("重做")

func _on_center_view():
	_graph_edit.center_view()
	_update_status("View centered")

func _update_status(message: String):
	_status_bar.text = message
	print("对话编辑器 %s" % message)

# 公共方法
func get_current_dialog_id() -> String:
	return current_dialog_id

func get_nodes_count() -> int:
	return nodes.size()

func get_connections_count() -> int:
	return connections.size()

func has_unsaved_changes() -> bool:
	# 可以在这里实现更复杂的检测逻辑
	return not nodes.is_empty()

