@tool
extends "res://addons/cdc_game_editor/editors/flow_graph/flow_graph_editor_base.gd"
## 对话编辑器
## 基于共享 Flow Graph 编辑器，只定义对话节点类型和对话数据读写。

signal dialog_saved(dialog_id: String)
signal dialog_loaded(dialog_id: String)

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
const DIALOG_DATA_DIR := "res://data/dialogues"
const START_NODE_ID := "start"

@onready var _dialog_id_input: LineEdit
@onready var _file_dialog: FileDialog
@onready var _open_dialog_popup: ConfirmationDialog
@onready var _open_dialog_list: ItemList

var current_dialog_id: String = ""
var current_file_path: String = ""
var _open_dialog_paths: Array[String] = []

func _get_editor_name() -> String:
	return "对话编辑器"

func _get_search_placeholder() -> String:
	return "搜索节点..."

func _get_property_panel_title() -> String:
	return "Node Properties"

func _get_initial_status_text() -> String:
	return "就绪"

func _get_node_type_definitions() -> Array[Dictionary]:
	return [
		{"type": "dialog", "name": NODE_TYPE_NAMES.dialog, "color": NODE_COLORS.dialog},
		{"type": "choice", "name": NODE_TYPE_NAMES.choice, "color": NODE_COLORS.choice},
		{"type": "condition", "name": NODE_TYPE_NAMES.condition, "color": NODE_COLORS.condition},
		{"type": "action", "name": NODE_TYPE_NAMES.action, "color": NODE_COLORS.action},
		{"type": "end", "name": NODE_TYPE_NAMES.end, "color": NODE_COLORS.end}
	]

func _create_toolbar() -> void:
	_add_toolbar_button("新建", _on_new_dialog, "新建对话")
	_add_toolbar_button("打开", _on_open_dialog, "打开对话文件")
	_add_toolbar_button("保存", _on_save_dialog, "保存对话文件")

	var id_label := Label.new()
	id_label.text = "dialog_id:"
	_toolbar.add_child(id_label)

	_dialog_id_input = LineEdit.new()
	_dialog_id_input.placeholder_text = "npc_guard_intro"
	_dialog_id_input.custom_minimum_size = Vector2(220, 0)
	_dialog_id_input.tooltip_text = "仅允许 a-z 0-9 和下划线(_)"
	_dialog_id_input.text_changed.connect(_on_dialog_id_text_changed)
	_toolbar.add_child(_dialog_id_input)

	_add_toolbar_separator()
	_add_toolbar_button("撤销", _on_undo, "撤销上一步操作 (Ctrl+Z)")
	_add_toolbar_button("重做", _on_redo, "重做操作 (Ctrl+Y)")
	_add_toolbar_separator()
	_add_toolbar_button("复制", _on_copy_nodes, "复制选中节点 (Ctrl+C)")
	_add_toolbar_button("粘贴", _on_paste_nodes, "粘贴节点 (Ctrl+V)")
	_add_toolbar_button("删除", _on_delete_selected, "删除选中节点 (Delete)")
	_add_toolbar_separator()
	_add_toolbar_button("导出JSON", _on_export_json, "导出为 JSON 格式")
	_add_toolbar_button("导出GD", _on_export_gdscript, "导出为 GDScript 格式")
	_add_toolbar_separator()
	_add_toolbar_button("居中", _on_center_view, "居中视图")

func _after_base_ready() -> void:
	_setup_file_dialog()
	_setup_open_dialog_popup()
	if nodes.is_empty():
		_reset_dialog_graph(true)
		_update_status("已创建默认 Start 节点")

func _setup_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.json; JSON 文件")
	_file_dialog.add_filter("*.dlg; 对话文件")
	add_child(_file_dialog)

func _setup_open_dialog_popup() -> void:
	_open_dialog_popup = ConfirmationDialog.new()
	_open_dialog_popup.title = "打开对话"
	_open_dialog_popup.dialog_text = "请选择 data/dialogues 中的对话文件，每个对话会单独保存为一个 JSON"
	_open_dialog_popup.get_ok_button().text = "打开"
	_open_dialog_popup.confirmed.connect(_on_open_dialog_confirmed)
	add_child(_open_dialog_popup)

	var container := VBoxContainer.new()
	container.custom_minimum_size = Vector2(700, 420)
	_open_dialog_popup.add_child(container)

	_open_dialog_list = ItemList.new()
	_open_dialog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_dialog_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_open_dialog_list.item_activated.connect(_on_open_dialog_item_activated)
	container.add_child(_open_dialog_list)

func _on_dialog_id_text_changed(text: String) -> void:
	current_dialog_id = text.strip_edges()

func _set_dialog_id(dialog_id: String) -> void:
	current_dialog_id = dialog_id.strip_edges()
	if _dialog_id_input and _dialog_id_input.text != current_dialog_id:
		_dialog_id_input.text = current_dialog_id

func _is_valid_dialog_id(dialog_id: String) -> bool:
	if dialog_id.is_empty():
		return false
	for i in range(dialog_id.length()):
		var code := dialog_id.unicode_at(i)
		var is_digit := code >= 48 and code <= 57
		var is_lower := code >= 97 and code <= 122
		if not (is_digit or is_lower or code == 95):
			return false
	return true

func _ensure_dialog_data_dir() -> bool:
	var absolute_dir_path := ProjectSettings.globalize_path(DIALOG_DATA_DIR)
	if DirAccess.dir_exists_absolute(absolute_dir_path):
		return true
	var create_error := DirAccess.make_dir_recursive_absolute(absolute_dir_path)
	if create_error != OK:
		_update_status("无法创建目录: %s" % DIALOG_DATA_DIR)
		return false
	return true

func _build_dialog_file_path(dialog_id: String) -> String:
	return "%s/%s.json" % [DIALOG_DATA_DIR, dialog_id]

func _is_managed_dialog_file(path: String) -> bool:
	return path.begins_with("%s/" % DIALOG_DATA_DIR)

func _remove_replaced_dialog_file(previous_path: String, target_path: String) -> void:
	if previous_path.is_empty() or previous_path == target_path:
		return
	if not _is_managed_dialog_file(previous_path):
		return
	if not FileAccess.file_exists(previous_path):
		return

	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(previous_path))
	if remove_error != OK:
		push_warning("无法删除旧对话文件: %s" % previous_path)

func _refresh_open_dialog_list() -> bool:
	_open_dialog_paths.clear()
	_open_dialog_list.clear()

	var absolute_dir_path := ProjectSettings.globalize_path(DIALOG_DATA_DIR)
	if not DirAccess.dir_exists_absolute(absolute_dir_path):
		_update_status("目录不存在: %s" % DIALOG_DATA_DIR)
		return false

	var dir := DirAccess.open(DIALOG_DATA_DIR)
	if dir == null:
		_update_status("无法读取目录: %s" % DIALOG_DATA_DIR)
		return false

	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	file_names.sort()
	if file_names.is_empty():
		_update_status("未找到对话文件: %s" % DIALOG_DATA_DIR)
		return false

	for dialog_file in file_names:
		_open_dialog_paths.append("%s/%s" % [DIALOG_DATA_DIR, dialog_file])
		_open_dialog_list.add_item(dialog_file.get_basename())

	_open_dialog_list.select(0)
	return true

func _on_open_dialog_item_activated(index: int) -> void:
	_open_dialog_list.select(index)
	_on_open_dialog_confirmed()

func _on_open_dialog_confirmed() -> void:
	var selected_items := _open_dialog_list.get_selected_items()
	if selected_items.is_empty():
		_update_status("请选择要打开的对话")
		return

	var selected_index := int(selected_items[0])
	if selected_index < 0 or selected_index >= _open_dialog_paths.size():
		_update_status("无效的对话选择")
		return

	var target_path := _open_dialog_paths[selected_index]
	_open_dialog_popup.hide()
	_load_dialog(target_path)

func _generate_node_id(_node_type: String = "dlg") -> String:
	return "dlg_%d" % Time.get_ticks_msec()

func _apply_type_defaults(data: Dictionary, node_type: String) -> void:
	match node_type:
		"dialog":
			if not data.has("text"):
				data.text = "请输入对话文本..."
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

	if str(data.get("id", "")) == START_NODE_ID or bool(data.get("is_start", false)):
		data["is_start"] = true
		if not data.has("title"):
			data["title"] = "Start"

func _populate_node_preview(node, data: Dictionary) -> void:
	if _is_start_node(data):
		node.add_text_row("START", Color(1.0, 0.95, 0.45))
		node.add_separator()

	match str(data.get("type", "")):
		"dialog":
			node.add_text_row("🎭 %s" % str(data.get("speaker", "")))
			node.add_text_row(_truncate_text(str(data.get("text", "")), 50), Color.WHITE, Vector2(200, 40), true, HORIZONTAL_ALIGNMENT_LEFT)
			if not str(data.get("portrait", "")).is_empty():
				node.add_text_row("🖼 %s" % str(data.get("portrait", "")).get_file(), Color.GRAY)
		"choice":
			var options: Array = data.get("options", [])
			node.add_text_row("选项列表 (%d)" % options.size())
			for i in range(options.size()):
				var option: Dictionary = options[i]
				node.add_text_row("%d. %s" % [i + 1, _truncate_text(str(option.get("text", "")), 25)], Color.LIGHT_GRAY)
		"condition":
			node.add_text_row("🔀 条件判断")
			node.add_text_row(_truncate_text(str(data.get("condition", "")), 40), Color.YELLOW, Vector2(200, 40), true, HORIZONTAL_ALIGNMENT_LEFT)
		"action":
			node.add_text_row("动作节点")
			node.add_text_row("包含 %d 个动作" % int(data.get("actions", []).size()), Color.GREEN)
		"end":
			node.add_text_row("🏁 对话结束", Color.RED)
			node.add_text_row("类型: %s" % str(data.get("end_type", "normal")), Color.GRAY)
		_:
			node.add_text_row("节点数据缺失")

func _configure_node_ports(node, data: Dictionary) -> void:
	match str(data.get("type", "")):
		"dialog", "action":
			node.add_input_port()
			node.add_output_port()
		"choice":
			node.add_input_port()
			var options: Array = data.get("options", [])
			for _i in range(options.size()):
				node.add_output_port()
		"condition":
			node.add_input_port()
			node.add_output_port()
			node.add_output_port()
		"end":
			node.add_input_port()

func _truncate_text(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 3) + "..."

func _update_property_panel(data: Dictionary) -> void:
	_property_panel.clear()
	if data.is_empty():
		return

	_property_panel.add_readonly_label("id", "节点ID:", str(data.get("id", "")))
	_property_panel.add_readonly_label("type", "类型:", NODE_TYPE_NAMES.get(str(data.get("type", "")), str(data.get("type", ""))))
	if _is_start_node(data):
		_property_panel.add_readonly_label("is_start", "入口节点:", "是")
	_property_panel.add_separator()

	match str(data.get("type", "")):
		"dialog":
			_property_panel.add_string_property("speaker", "说话人:", str(data.get("speaker", "")))
			_property_panel.add_string_property("text", "对话内容:", str(data.get("text", "")), true, "输入对话文本...")
			_property_panel.add_string_property("portrait", "头像路径:", str(data.get("portrait", "")), false, "res://assets/portraits/...")
		"choice":
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_choice_editor(data))
		"condition":
			_property_panel.add_string_property("condition", "条件表达式:", str(data.get("condition", "")), true, "输入条件代码...")
		"action":
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_action_editor(data))
		"end":
			var end_types = {"normal": "Normal End", "success": "Success End", "fail": "Fail End"}
			_property_panel.add_enum_property("end_type", "结束类型:", end_types, str(data.get("end_type", "normal")))

func _create_choice_editor(data: Dictionary) -> Control:
	var container := VBoxContainer.new()

	var label := Label.new()
	label.text = "选项列表:"
	container.add_child(label)

	var options: Array = data.get("options", [])
	for i in range(options.size()):
		var option: Dictionary = options[i]
		var hbox := HBoxContainer.new()

		var idx_label := Label.new()
		idx_label.text = "%d." % (i + 1)
		idx_label.custom_minimum_size = Vector2(25, 0)
		hbox.add_child(idx_label)

		var edit := LineEdit.new()
		edit.text = str(option.get("text", ""))
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_changed.connect(func(v: String): option.text = v; _on_node_data_changed(str(data.get("id", "")), data))
		hbox.add_child(edit)

		var del_btn := Button.new()
		del_btn.text = "×"
		del_btn.tooltip_text = "删除选项"
		del_btn.pressed.connect(func(): _remove_choice_option(data, i))
		hbox.add_child(del_btn)

		container.add_child(hbox)

	var add_btn := Button.new()
	add_btn.text = "+ 添加选项"
	add_btn.pressed.connect(func(): _add_choice_option(data))
	container.add_child(add_btn)

	return container

func _add_choice_option(data: Dictionary) -> void:
	if not data.has("options"):
		data.options = []
	data.options.append({"text": "新选项", "next": ""})
	_update_property_panel(data)
	_on_node_data_changed(str(data.get("id", "")), data)

func _remove_choice_option(data: Dictionary, index: int) -> void:
	if data.has("options") and index < data.options.size():
		data.options.remove_at(index)
		_update_property_panel(data)
		_on_node_data_changed(str(data.get("id", "")), data)

func _create_action_editor(_data: Dictionary) -> Control:
	var label := Label.new()
	label.text = "Action editor (WIP)\nPlease edit actions in code."
	label.modulate = Color.GRAY
	return label

func _update_node_connection(from_id: String, from_port: int, to_id: String, _to_port: int) -> void:
	var from_data = nodes.get(from_id)
	if not from_data:
		return

	match str(from_data.get("type", "")):
		"dialog", "action":
			from_data["next"] = to_id
		"choice":
			var options: Array = from_data.get("options", [])
			if from_port < options.size():
				options[from_port].next = to_id
		"condition":
			if from_port == 0:
				from_data["true_next"] = to_id
			else:
				from_data["false_next"] = to_id

func _update_node_disconnection(from_id: String, from_port: int, _to_id: String, _to_port: int) -> void:
	var from_data = nodes.get(from_id)
	if not from_data:
		return

	match str(from_data.get("type", "")):
		"dialog", "action":
			from_data["next"] = ""
		"choice":
			var options: Array = from_data.get("options", [])
			if from_port < options.size():
				options[from_port].next = ""
		"condition":
			if from_port == 0:
				from_data["true_next"] = ""
			else:
				from_data["false_next"] = ""

func _get_search_strings(data: Dictionary) -> Array[String]:
	var values: Array[String] = [
		str(data.get("id", "")),
		str(data.get("title", "")),
		str(data.get("speaker", "")),
		str(data.get("text", ""))
	]

	var options: Array = data.get("options", [])
	for option in options:
		values.append(str(option.get("text", "")))

	return values

func _on_new_dialog() -> void:
	_reset_dialog_graph(true)
	_update_status("新建对话")

func _reset_dialog_graph(create_default_start: bool) -> void:
	_set_dialog_id("")
	current_file_path = ""
	nodes.clear()
	connections.clear()
	_graph_edit.clear_graph()
	_clear_selection_state()
	if create_default_start:
		_create_start_node()

func _on_open_dialog() -> void:
	if not _refresh_open_dialog_list():
		return
	_open_dialog_popup.popup_centered(Vector2(760, 520))

func _on_save_dialog() -> void:
	var dialog_id := current_dialog_id.strip_edges()
	_set_dialog_id(dialog_id)

	if not _is_valid_dialog_id(dialog_id):
		_update_status("dialog_id 无效: 仅允许 a-z0-9_")
		return

	if not _ensure_dialog_data_dir():
		return

	var target_path := _build_dialog_file_path(dialog_id)
	_save_dialog_to_path(target_path)

func _load_dialog(path: String) -> void:
	_reset_dialog_graph(false)

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
	var loaded_dialog_id := str(data.get("dialog_id", "")).strip_edges()
	if loaded_dialog_id.is_empty():
		loaded_dialog_id = path.get_file().get_basename()

	_set_dialog_id(loaded_dialog_id)
	current_file_path = path

	for node_data in loaded_nodes:
		_create_node_internal(node_data)

	connections = loaded_connections
	for conn_data in connections:
		_graph_edit.connect_node(
			StringName(str(conn_data.get("from", ""))),
			int(conn_data.get("from_port", 0)),
			StringName(str(conn_data.get("to", ""))),
			int(conn_data.get("to_port", 0))
		)

	_ensure_start_node()

	dialog_loaded.emit(current_dialog_id)
	_update_status("Loaded: %s" % current_dialog_id)

func _normalize_pasted_node_data(data: Dictionary) -> Dictionary:
	var normalized := data.duplicate(true)
	normalized.erase("is_start")
	if str(normalized.get("id", "")) == START_NODE_ID:
		normalized["id"] = _generate_node_id("dlg")
	if str(normalized.get("title", "")) == "Start":
		normalized["title"] = NODE_TYPE_NAMES.dialog
	return normalized

func _on_delete_nodes_request(nodes_to_delete: Array) -> void:
	var filtered_nodes: Array = []
	var skipped_start := false

	for node_name in nodes_to_delete:
		var node_id := str(node_name)
		var node_data: Dictionary = nodes.get(node_id, {})
		if _is_start_node(node_data):
			skipped_start = true
			continue
		filtered_nodes.append(node_name)

	if skipped_start:
		_update_status("Start 节点不能删除")

	if filtered_nodes.is_empty():
		return

	super._on_delete_nodes_request(filtered_nodes)

func _save_dialog_to_path(path: String, persist_as_current: bool = true) -> void:
	_sync_node_positions_from_graph()

	var dialog_id := current_dialog_id if not current_dialog_id.is_empty() else "dialog_%d" % Time.get_ticks_msec()
	var previous_file_path := current_file_path
	var data: Dictionary = {
		"dialog_id": dialog_id,
		"nodes": nodes.values(),
		"connections": connections
	}

	var json := JSON.stringify(data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		if persist_as_current:
			_remove_replaced_dialog_file(previous_file_path, path)
			current_file_path = path
			dialog_saved.emit(dialog_id)
			_update_status("已保存 %s" % path)
		else:
			_update_status("已导出 %s" % path)
	else:
		_update_status("无法保存文件")

func _on_export_json() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "%s.json" % (current_dialog_id if not current_dialog_id.is_empty() else "dialog_export")
	_file_dialog.file_selected.connect(func(path: String): _save_dialog_to_path(path, false), CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _on_export_gdscript() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "dialog_data.gd"
	_file_dialog.file_selected.connect(func(path: String):
		var output := _build_gdscript()
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(output)
			file.close()
			_update_status("已导出 GDScript")
	, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _build_gdscript() -> String:
	_sync_node_positions_from_graph()

	var lines: Array[String] = []
	lines.append("# Auto-generated dialog data")
	lines.append("# 生成时间: %s" % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("const DIALOGS = {")

	var dialog_key := current_dialog_id if not current_dialog_id.is_empty() else "dialog_001"
	lines.append('\t"%s": {' % dialog_key)
	lines.append('\t\t"nodes": [')

	for node_id in nodes:
		var node_data: Dictionary = nodes[node_id]
		lines.append('\t\t\t{')
		for key in node_data:
			var value: Variant = node_data[key]
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

func get_current_dialog_id() -> String:
	return current_dialog_id

func _create_start_node() -> void:
	if _has_start_node():
		return

	var start_position := Vector2(120, 180)
	var start_node_data: Dictionary = {
		"id": START_NODE_ID,
		"type": "dialog",
		"title": "Start",
		"speaker": "NPC",
		"text": "请输入开场对白...",
		"portrait": "",
		"position": start_position,
		"is_start": true
	}
	_create_node("dialog", start_position, start_node_data)

func _ensure_start_node() -> void:
	if _has_start_node():
		return

	if nodes.is_empty():
		_create_start_node()
		return

	var first_node_id := str(nodes.keys()[0])
	var first_node: Dictionary = nodes.get(first_node_id, {}).duplicate(true)
	if first_node.is_empty():
		_create_start_node()
		return

	first_node["is_start"] = true
	if first_node_id == START_NODE_ID and not first_node.has("title"):
		first_node["title"] = "Start"
	_on_node_data_changed(first_node_id, first_node)

func _has_start_node() -> bool:
	for node_id in nodes.keys():
		var node_data: Dictionary = nodes[node_id]
		if _is_start_node(node_data):
			return true
	return false

func _is_start_node(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	return bool(data.get("is_start", false)) or str(data.get("id", "")) == START_NODE_ID
