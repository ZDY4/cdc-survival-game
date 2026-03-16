@tool
extends "res://addons/cdc_game_editor/editors/flow_graph/flow_graph_editor_base.gd"
## 任务编辑器
## 基于共享 Flow Graph 编辑器，使用任务节点和依赖连线来编辑任务链。

signal quest_saved(quest_id: String)
signal quest_loaded(quest_id: String)
signal validation_errors_found(errors: Array[String])

const OBJECTIVE_TYPES = {
	"collect": "收集物品",
	"kill": "击败敌人",
	"location": "到达地点",
	"talk": "与NPC对话",
	"custom": "Custom"
}

const QUEST_NODE_COLOR := Color(0.3, 0.55, 0.85)
const QUEST_STATUS_COLORS = {
	"valid": Color(0.2, 0.8, 0.2),
	"warning": Color(0.9, 0.6, 0.2),
	"error": Color(0.9, 0.2, 0.2)
}

const JSON_VALIDATOR = preload("res://addons/cdc_game_editor/utils/json_validator.gd")
const QUEST_DATA_DIR := "res://data/quests"

@onready var _file_dialog: FileDialog
@onready var _validation_panel: VBoxContainer

var current_file_path: String = ""
var _validation_errors: Dictionary = {}

func _get_editor_name() -> String:
	return "任务编辑器"

func _get_search_placeholder() -> String:
	return "搜索任务..."

func _get_property_panel_title() -> String:
	return "Quest Properties"

func _get_initial_status_text() -> String:
	return "Ready - 0 quests"

func _get_node_type_definitions() -> Array[Dictionary]:
	return [
		{"type": "quest", "name": "任务节点", "color": QUEST_NODE_COLOR}
	]

func _create_toolbar() -> void:
	_add_toolbar_button("新建", _on_new_quest, "新建任务 (Ctrl+N)")
	_add_toolbar_button("删除", _on_delete_selected, "删除选中任务 (Delete)")
	_add_toolbar_separator()
	_add_toolbar_button("撤销", _on_undo, "撤销 (Ctrl+Z)")
	_add_toolbar_button("重做", _on_redo, "重做 (Ctrl+Y)")
	_add_toolbar_separator()
	_add_toolbar_button("保存", _on_save_quests, "将每个任务分别保存到 data/quests 目录 (Ctrl+S)")
	_add_toolbar_button("加载", _on_load_quests, "从 data/quests 目录加载任务，必要时兼容旧版 quests.json")
	_add_toolbar_separator()
	_add_toolbar_button("验证", _on_validate_all, "验证所有任务")
	_add_toolbar_button("导出GD", _on_export_gdscript, "导出为 GDScript")
	_add_toolbar_separator()
	_add_toolbar_button("居中", _on_center_view, "居中视图")

func _after_base_ready() -> void:
	_setup_file_dialog()
	_setup_validation_panel()
	_load_quests_from_project_data()

func _setup_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.json; JSON 文件")
	_file_dialog.add_filter("*.quest; 任务文件")
	add_child(_file_dialog)

func _setup_validation_panel() -> void:
	_validation_panel = VBoxContainer.new()
	_validation_panel.visible = false
	_right_container.add_child(_validation_panel)

	var validation_title := Label.new()
	validation_title.text = "⚠️ 验证问题"
	validation_title.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
	_validation_panel.add_child(validation_title)
	_validation_panel.add_child(HSeparator.new())

func _load_quests_from_project_data() -> void:
	if not _load_from_directory(QUEST_DATA_DIR):
		_update_status("未找到任务目录或目录为空: %s" % QUEST_DATA_DIR)

func _ensure_quest_data_dir() -> bool:
	var absolute_dir_path := ProjectSettings.globalize_path(QUEST_DATA_DIR)
	if DirAccess.dir_exists_absolute(absolute_dir_path):
		return true
	var create_error := DirAccess.make_dir_recursive_absolute(absolute_dir_path)
	if create_error != OK:
		_update_status("无法创建目录: %s" % QUEST_DATA_DIR)
		return false
	return true

func _is_valid_quest_file_id(quest_id: String) -> bool:
	if quest_id.is_empty():
		return false

	var invalid_chars := ['/', '\\', ':', '*', '?', '"', '<', '>', '|']
	for invalid_char in invalid_chars:
		if quest_id.contains(str(invalid_char)):
			return false
	return true

func _build_quest_file_path(quest_id: String) -> String:
	return "%s/%s.json" % [QUEST_DATA_DIR, quest_id]

func _serialize_quest_for_storage(quest_id: String, quest: Dictionary) -> Dictionary:
	var serialized_quest: Dictionary = quest.duplicate(true)
	var position: Vector2 = serialized_quest.get("position", Vector2.ZERO)

	serialized_quest.erase("id")
	serialized_quest.erase("type")
	serialized_quest.erase("position")
	serialized_quest["quest_id"] = quest_id
	serialized_quest["_editor"] = {
		"position": {"x": position.x, "y": position.y},
		"node_type": "quest"
	}
	return serialized_quest

func _generate_node_id(_node_type: String = "quest") -> String:
	return "quest_%d" % Time.get_ticks_msec()

func _build_new_quest_data(quest_id: String, position: Vector2) -> Dictionary:
	return {
		"id": quest_id,
		"quest_id": quest_id,
		"type": "quest",
		"position": position,
		"title": "New Quest",
		"description": "任务描述",
		"objectives": [],
		"rewards": {
			"items": [],
			"experience": 0
		},
		"prerequisites": [],
		"time_limit": -1,
		"_status": "draft"
	}

func _apply_type_defaults(data: Dictionary, _node_type: String) -> void:
	if not data.has("quest_id"):
		data["quest_id"] = str(data.get("id", _generate_node_id()))
	if not data.has("title"):
		data["title"] = "New Quest"
	if not data.has("description"):
		data["description"] = "任务描述"
	if not data.has("objectives"):
		data["objectives"] = []
	if not data.has("rewards"):
		data["rewards"] = {"items": [], "experience": 0}
	var rewards: Dictionary = data.get("rewards", {})
	if not rewards.has("items"):
		rewards["items"] = []
	if not rewards.has("experience"):
		rewards["experience"] = 0
	data["rewards"] = rewards
	if not data.has("prerequisites"):
		data["prerequisites"] = []
	if not data.has("time_limit"):
		data["time_limit"] = -1
	if not data.has("_status"):
		data["_status"] = "draft"

func _populate_node_preview(node, data: Dictionary) -> void:
	var quest_id := str(data.get("quest_id", data.get("id", "")))
	node.add_text_row(quest_id, Color.GRAY)
	node.add_separator()
	node.add_text_row(str(data.get("title", "Unnamed Quest")))
	node.add_text_row(_truncate_text(str(data.get("description", "")), 60), Color.WHITE, Vector2(180, 40), true, HORIZONTAL_ALIGNMENT_LEFT)
	node.add_text_row("Objectives: %d" % int(data.get("objectives", []).size()), Color.LIGHT_BLUE)

	var rewards: Dictionary = data.get("rewards", {})
	var exp := int(rewards.get("experience", 0))
	var items: Array = rewards.get("items", [])
	if items.size() > 0:
		node.add_text_row("奖励: %d经验 + %d物品" % [exp, items.size()], Color.GREEN)
	else:
		node.add_text_row("奖励: %d经验" % exp, Color.GREEN)

func _configure_node_ports(node, _data: Dictionary) -> void:
	node.add_input_port()
	node.add_output_port()

func _truncate_text(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 3) + "..."

func _get_search_strings(data: Dictionary) -> Array[String]:
	var values: Array[String] = [
		str(data.get("id", "")),
		str(data.get("quest_id", "")),
		str(data.get("title", "")),
		str(data.get("description", ""))
	]

	for obj in data.get("objectives", []):
		values.append(str(obj.get("description", "")))
		values.append(str(obj.get("target", "")))

	return values

func _normalize_pasted_node_data(data: Dictionary) -> Dictionary:
	var normalized := data.duplicate(true)
	var new_quest_id := _generate_node_id("quest")
	normalized.id = new_quest_id
	normalized.quest_id = new_quest_id
	normalized.prerequisites = []
	return normalized

func _on_new_quest() -> void:
	var quest_id := _generate_node_id("quest")
	var position = _graph_edit.scroll_offset + _graph_edit.size / 2 - Vector2(100, 50)
	var quest_data := _build_new_quest_data(quest_id, position)
	_create_node("quest", position, quest_data)
	_select_quest(quest_id)
	_validate_quest(quest_id)
	_update_status("创建了新任务: %s" % quest_id)

func _select_quest(quest_id: String) -> void:
	selected_node_id = quest_id
	_inspected_node_id = quest_id
	var quest = nodes.get(quest_id, {})
	if not quest.is_empty():
		_queue_property_panel_update(quest)
		_update_validation_panel()

	var graph_node = _graph_edit.get_node_or_null(quest_id)
	if graph_node and graph_node is GraphNode:
		graph_node.selected = true

func _update_property_panel(quest: Dictionary) -> void:
	_property_panel.clear()
	if quest.is_empty():
		return

	_property_panel.add_string_property("quest_id", "任务ID:", str(quest.get("quest_id", "")), false, "Unique identifier")
	_property_panel.add_string_property("title", "任务标题:", str(quest.get("title", "")), false, "显示名称")
	_property_panel.add_string_property("description", "任务描述:", str(quest.get("description", "")), true, "详细描述...")
	_property_panel.add_separator()

	var rewards: Dictionary = quest.get("rewards", {})
	_property_panel.add_number_property("experience", "经验值:", int(rewards.get("experience", 0)), 0, 999999, 10, false)
	_property_panel.add_number_property("time_limit", "时间限制(秒):", int(quest.get("time_limit", -1)), -1, 999999, 1, false)
	_property_panel.add_separator()
	_property_panel.add_custom_control(_create_objectives_editor(quest))
	_property_panel.add_separator()
	_property_panel.add_custom_control(_create_rewards_editor(quest))
	_property_panel.add_separator()
	_property_panel.add_custom_control(_create_prerequisites_editor(quest))

func _create_objectives_editor(quest: Dictionary) -> Control:
	var container := VBoxContainer.new()

	var label := Label.new()
	label.text = "📋 任务目标 (%d)" % quest.get("objectives", []).size()
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	container.add_child(label)

	var list_container := VBoxContainer.new()
	container.add_child(list_container)
	_refresh_objectives_list(list_container, quest)

	var add_btn := Button.new()
	add_btn.text = "+ 添加目标"
	add_btn.pressed.connect(func(): _add_objective(quest, list_container))
	container.add_child(add_btn)

	return container

func _refresh_objectives_list(container: VBoxContainer, quest: Dictionary) -> void:
	for child in container.get_children():
		child.queue_free()

	var objectives: Array = quest.get("objectives", [])
	for i in range(objectives.size()):
		container.add_child(_create_objective_row(quest, i, objectives[i], container))

func _create_objective_row(quest: Dictionary, index: int, obj: Dictionary, list_container: VBoxContainer) -> Control:
	var panel := PanelContainer.new()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var top_row := HBoxContainer.new()
	vbox.add_child(top_row)

	var type_option := OptionButton.new()
	for key in OBJECTIVE_TYPES:
		type_option.add_item(OBJECTIVE_TYPES[key], type_option.item_count)
		type_option.set_item_metadata(type_option.item_count - 1, key)
		if key == obj.get("type", "collect"):
			type_option.selected = type_option.item_count - 1
	type_option.item_selected.connect(func(i: int):
		var type_key = type_option.get_item_metadata(i)
		_on_objective_field_changed(quest, index, "type", type_key)
	)
	top_row.add_child(type_option)

	var target_edit := LineEdit.new()
	target_edit.text = str(obj.get("target", ""))
	target_edit.placeholder_text = "目标ID"
	target_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_edit.text_changed.connect(func(v: String): _on_objective_field_changed(quest, index, "target", v))
	top_row.add_child(target_edit)

	var count_spin := SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 999
	count_spin.value = float(obj.get("count", 1))
	count_spin.value_changed.connect(func(v: float): _on_objective_field_changed(quest, index, "count", int(v)))
	top_row.add_child(count_spin)

	var desc_row := HBoxContainer.new()
	vbox.add_child(desc_row)

	var desc_edit := LineEdit.new()
	desc_edit.text = str(obj.get("description", ""))
	desc_edit.placeholder_text = "目标描述"
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_edit.text_changed.connect(func(v: String): _on_objective_field_changed(quest, index, "description", v))
	desc_row.add_child(desc_edit)

	var del_btn := Button.new()
	del_btn.text = "×"
	del_btn.tooltip_text = "删除目标"
	del_btn.pressed.connect(func(): _remove_objective(quest, index, list_container))
	desc_row.add_child(del_btn)

	return panel

func _on_objective_field_changed(quest: Dictionary, index: int, field: String, value: Variant) -> void:
	var objectives: Array = quest.get("objectives", [])
	if index < objectives.size():
		objectives[index][field] = value
		quest["objectives"] = objectives
		_on_node_data_changed(str(quest.get("id", "")), quest)
		_validate_quest(str(quest.get("id", "")))
		_update_validation_panel()

func _add_objective(quest: Dictionary, list_container: VBoxContainer) -> void:
	var objectives: Array = quest.get("objectives", [])
	objectives.append({
		"type": "collect",
		"target": "",
		"count": 1,
		"description": "New objective"
	})
	quest["objectives"] = objectives
	_refresh_objectives_list(list_container, quest)
	_on_node_data_changed(str(quest.get("id", "")), quest)
	_validate_quest(str(quest.get("id", "")))
	_update_validation_panel()

func _remove_objective(quest: Dictionary, index: int, list_container: VBoxContainer) -> void:
	var objectives: Array = quest.get("objectives", [])
	if index < objectives.size():
		objectives.remove_at(index)
		quest["objectives"] = objectives
		_refresh_objectives_list(list_container, quest)
		_on_node_data_changed(str(quest.get("id", "")), quest)
		_validate_quest(str(quest.get("id", "")))
		_update_validation_panel()

func _create_rewards_editor(quest: Dictionary) -> Control:
	var container := VBoxContainer.new()

	var label := Label.new()
	label.text = "🎁 物品奖励"
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	container.add_child(label)

	var list := VBoxContainer.new()
	container.add_child(list)
	_refresh_rewards_list(list, quest)

	var add_btn := Button.new()
	add_btn.text = "+ 添加物品"
	add_btn.pressed.connect(func(): _add_reward_item(quest, list))
	container.add_child(add_btn)

	return container

func _create_reward_row(quest: Dictionary, index: int, item: Dictionary, list: VBoxContainer) -> Control:
	var row := HBoxContainer.new()

	var id_edit := LineEdit.new()
	id_edit.text = str(item.get("id", ""))
	id_edit.placeholder_text = "物品ID"
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_edit.text_changed.connect(func(v: String):
		_update_reward_item_field(quest, index, "id", v)
	)
	row.add_child(id_edit)

	var count_spin := SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 999
	count_spin.value = float(item.get("count", 1))
	count_spin.value_changed.connect(func(v: float):
		_update_reward_item_field(quest, index, "count", int(v))
	)
	row.add_child(count_spin)

	var del_btn := Button.new()
	del_btn.text = "×"
	del_btn.pressed.connect(func(): _remove_reward_item(quest, index, list))
	row.add_child(del_btn)

	return row

func _add_reward_item(quest: Dictionary, list: VBoxContainer) -> void:
	var rewards: Dictionary = quest.get("rewards", {})
	var items: Array = rewards.get("items", [])
	items.append({"id": "", "count": 1})
	rewards["items"] = items
	quest["rewards"] = rewards
	_refresh_rewards_list(list, quest)
	_on_node_data_changed(str(quest.get("id", "")), quest)

func _remove_reward_item(quest: Dictionary, index: int, list: VBoxContainer) -> void:
	var rewards: Dictionary = quest.get("rewards", {})
	var items: Array = rewards.get("items", [])
	if index < items.size():
		items.remove_at(index)
		rewards["items"] = items
		quest["rewards"] = rewards
		_refresh_rewards_list(list, quest)
		_on_node_data_changed(str(quest.get("id", "")), quest)

func _refresh_rewards_list(list: VBoxContainer, quest: Dictionary) -> void:
	for child in list.get_children():
		child.queue_free()

	var items: Array = quest.get("rewards", {}).get("items", [])
	for i in range(items.size()):
		list.add_child(_create_reward_row(quest, i, items[i], list))

func _create_prerequisites_editor(quest: Dictionary) -> Control:
	var container := VBoxContainer.new()

	var label := Label.new()
	label.text = "🔗 前置任务"
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	container.add_child(label)

	var prereq_list := VBoxContainer.new()
	container.add_child(prereq_list)
	_refresh_prereq_list(prereq_list, quest)

	var add_btn := Button.new()
	add_btn.text = "+ 添加前置任务"
	add_btn.pressed.connect(func(): _show_prereq_selector(quest, prereq_list))
	container.add_child(add_btn)

	return container

func _refresh_prereq_list(list: VBoxContainer, quest: Dictionary) -> void:
	for child in list.get_children():
		child.queue_free()

	for prereq_id in quest.get("prerequisites", []):
		var row := HBoxContainer.new()

		var id_label := Label.new()
		id_label.text = str(prereq_id)
		id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(id_label)

		var del_btn := Button.new()
		del_btn.text = "×"
		del_btn.pressed.connect(func(): _remove_prereq(quest, str(prereq_id), list))
		row.add_child(del_btn)

		list.add_child(row)

func _show_prereq_selector(quest: Dictionary, list: VBoxContainer) -> void:
	var popup := PopupPanel.new()
	popup.size = Vector2(400, 300)

	var vbox := VBoxContainer.new()
	popup.add_child(vbox)

	var title := Label.new()
	title.text = "选择前置任务"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var item_list := ItemList.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(item_list)

	for quest_id in nodes.keys():
		var prerequisites: Array = quest.get("prerequisites", [])
		if quest_id != str(quest.get("quest_id", "")) and not prerequisites.has(quest_id):
			var q: Dictionary = nodes[quest_id]
			var idx := item_list.add_item("%s - %s" % [quest_id, str(q.get("title", ""))])
			item_list.set_item_metadata(idx, quest_id)

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_box)

	var confirm_btn := Button.new()
	confirm_btn.text = "确认"
	confirm_btn.pressed.connect(func():
		var selected := item_list.get_selected_items()
		if selected.size() > 0:
			var prereq_id = str(item_list.get_item_metadata(selected[0]))
			_add_prereq(quest, prereq_id, list)
		popup.queue_free()
	)
	btn_box.add_child(confirm_btn)

	add_child(popup)
	popup.popup_centered()

func _add_prereq(quest: Dictionary, prereq_id: String, list: VBoxContainer) -> void:
	var prerequisites: Array = quest.get("prerequisites", [])
	if not prerequisites.has(prereq_id):
		prerequisites.append(prereq_id)
		quest["prerequisites"] = prerequisites
		_refresh_prereq_list(list, quest)
		_rebuild_connections_from_prerequisites()
		_on_node_data_changed(str(quest.get("id", "")), quest)
		_validate_quest(str(quest.get("id", "")))
		_update_validation_panel()

func _remove_prereq(quest: Dictionary, prereq_id: String, list: VBoxContainer) -> void:
	var prerequisites: Array = quest.get("prerequisites", [])
	prerequisites.erase(prereq_id)
	quest["prerequisites"] = prerequisites
	_refresh_prereq_list(list, quest)
	_rebuild_connections_from_prerequisites()
	_on_node_data_changed(str(quest.get("id", "")), quest)
	_validate_quest(str(quest.get("id", "")))
	_update_validation_panel()

func _on_property_changed(property_name: String, new_value: Variant, _old_value: Variant) -> void:
	if selected_node_id.is_empty():
		return

	var quest: Dictionary = nodes.get(selected_node_id, {})
	if quest.is_empty():
		return

	if property_name == "experience":
		var rewards: Dictionary = quest.get("rewards", {})
		rewards["experience"] = int(new_value)
		quest["rewards"] = rewards
	elif property_name == "time_limit":
		quest["time_limit"] = int(new_value)
	elif property_name == "quest_id":
		var new_id := str(new_value).strip_edges()
		if new_id.is_empty() or new_id == selected_node_id:
			return
		if nodes.has(new_id):
			_update_status("任务ID已存在: %s" % new_id)
			return
		_change_quest_id(selected_node_id, new_id)
		return
	else:
		quest[property_name] = new_value

	_on_node_data_changed(str(quest.get("id", "")), quest)
	_validate_quest(str(quest.get("id", "")))
	_update_validation_panel()

func _change_quest_id(old_id: String, new_id: String) -> void:
	if not nodes.has(old_id) or nodes.has(new_id):
		return

	var quest: Dictionary = nodes[old_id]
	quest["id"] = new_id
	quest["quest_id"] = new_id

	nodes.erase(old_id)
	nodes[new_id] = quest

	if _validation_errors.has(old_id):
		_validation_errors[new_id] = _validation_errors[old_id]
		_validation_errors.erase(old_id)

	for quest_id in nodes.keys():
		var other: Dictionary = nodes[quest_id]
		var prerequisites: Array = other.get("prerequisites", [])
		for i in range(prerequisites.size()):
			if str(prerequisites[i]) == old_id:
				prerequisites[i] = new_id
				other["prerequisites"] = prerequisites
				_on_node_data_changed(str(other.get("id", "")), other)

	var graph_node = _graph_edit.get_node_or_null(old_id)
	if graph_node:
		graph_node.name = new_id
		graph_node.title = str(quest.get("title", ""))

	selected_node_id = new_id
	_inspected_node_id = new_id
	_rebuild_connections_from_prerequisites()
	_on_node_data_changed(new_id, quest)
	_validate_quest(new_id)
	_update_validation_panel()
	_update_status("已修改任务ID: %s" % new_id)

func _update_node_connection(from_id: String, _from_port: int, to_id: String, _to_port: int) -> void:
	var target: Dictionary = nodes.get(to_id, {})
	if target.is_empty():
		return

	var prerequisites: Array = target.get("prerequisites", [])
	if not prerequisites.has(from_id):
		prerequisites.append(from_id)
		target["prerequisites"] = prerequisites
		_on_node_data_changed(to_id, target)
		_validate_quest(to_id)
		_update_validation_panel()

func _update_node_disconnection(from_id: String, _from_port: int, to_id: String, _to_port: int) -> void:
	var target: Dictionary = nodes.get(to_id, {})
	if target.is_empty():
		return

	var prerequisites: Array = target.get("prerequisites", [])
	prerequisites.erase(from_id)
	target["prerequisites"] = prerequisites
	_on_node_data_changed(to_id, target)
	_validate_quest(to_id)
	_update_validation_panel()

func _on_node_removed(node_id: String, _removed_data: Dictionary) -> void:
	_validation_errors.erase(node_id)

	for quest_id in nodes.keys():
		var other: Dictionary = nodes[quest_id]
		var prerequisites: Array = other.get("prerequisites", [])
		if prerequisites.has(node_id):
			prerequisites.erase(node_id)
			other["prerequisites"] = prerequisites
			_on_node_data_changed(str(other.get("id", "")), other)
			_validate_quest(str(other.get("id", "")))

	if selected_node_id == node_id:
		_clear_selection_state()
	_update_validation_panel()

func _rebuild_connections_from_prerequisites() -> void:
	for conn in _graph_edit.get_connection_list():
		_graph_edit.disconnect_node(StringName(conn.from), int(conn.from_port), StringName(conn.to), int(conn.to_port))

	connections.clear()

	for quest_id in nodes.keys():
		var quest: Dictionary = nodes[quest_id]
		for prereq_id in quest.get("prerequisites", []):
			var prerequisite := str(prereq_id)
			if not nodes.has(prerequisite):
				continue

			var conn := {
				"from": prerequisite,
				"from_port": 0,
				"to": quest_id,
				"to_port": 0
			}
			connections.append(conn)
			_graph_edit.connect_node(StringName(prerequisite), 0, StringName(quest_id), 0)

func _validate_quest(quest_id: String) -> bool:
	var quest: Dictionary = nodes.get(quest_id, {})
	if quest.is_empty():
		return false

	var errors: Array[String] = []
	if quest_id.is_empty():
		errors.append("任务ID不能为空")
	if str(quest.get("title", "")).is_empty():
		errors.append("任务标题不能为空")

	var objectives: Array = quest.get("objectives", [])
	if objectives.is_empty():
		errors.append("At least one objective is required")

	for i in range(objectives.size()):
		var obj: Variant = objectives[i]
		if not (obj is Dictionary):
			errors.append("目标 #%d 数据格式无效" % (i + 1))
			continue
		if not obj.has("target"):
			errors.append("目标 #%d 缺少目标ID" % (i + 1))
			continue
		var target: Variant = obj.get("target")
		if target == null:
			errors.append("目标 #%d 缺少目标ID" % (i + 1))
		elif target is String and target.strip_edges().is_empty():
			errors.append("目标 #%d 缺少目标ID" % (i + 1))

	for prereq in quest.get("prerequisites", []):
		if not nodes.has(str(prereq)):
			errors.append("Prerequisite quest '%s' does not exist" % str(prereq))

	_validation_errors[quest_id] = errors
	return errors.is_empty()

func _validate_all() -> Array[String]:
	var all_errors: Array[String] = []
	for quest_id in nodes.keys():
		if not _validate_quest(quest_id):
			for error in _validation_errors[quest_id]:
				all_errors.append("%s: %s" % [quest_id, error])
	validation_errors_found.emit(all_errors)
	return all_errors

func _on_validate_all() -> void:
	var errors := _validate_all()
	_update_validation_panel()
	if errors.is_empty():
		_update_status("所有任务验证通过")
	else:
		_update_status("Found %d validation issues" % errors.size())

func _update_validation_panel() -> void:
	if selected_node_id.is_empty():
		_validation_panel.visible = false
		return

	var errors: Array = _validation_errors.get(selected_node_id, [])
	if errors.is_empty():
		_validation_panel.visible = false
		return

	_validation_panel.visible = true
	while _validation_panel.get_child_count() > 2:
		_validation_panel.remove_child(_validation_panel.get_child(2))

	for error in errors:
		var label := Label.new()
		label.text = str(error)
		label.add_theme_color_override("font_color", QUEST_STATUS_COLORS.error)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_validation_panel.add_child(label)

func _clear_editor_state() -> void:
	current_file_path = ""
	nodes.clear()
	connections.clear()
	_validation_errors.clear()
	_graph_edit.clear_graph()
	_clear_selection_state()
	_update_validation_panel()

func _on_save_quests() -> void:
	if not _ensure_quest_data_dir():
		return

	_save_to_directory(QUEST_DATA_DIR)

func _save_to_directory(path: String) -> void:
	current_file_path = path
	_sync_node_positions_from_graph()

	var quest_ids: Array = nodes.keys()
	quest_ids.sort()
	var invalid_ids: Array[String] = []
	for quest_id in quest_ids:
		if not _is_valid_quest_file_id(str(quest_id)):
			invalid_ids.append(str(quest_id))

	if not invalid_ids.is_empty():
		_update_status("任务ID不能作为文件名: %s" % ", ".join(invalid_ids))
		return

	var save_failed := false
	for quest_id in quest_ids:
		var quest: Dictionary = nodes[quest_id]
		var json := JSON.stringify(_serialize_quest_for_storage(str(quest_id), quest), "\t")
		var quest_file_path := _build_quest_file_path(str(quest_id))
		var file := FileAccess.open(quest_file_path, FileAccess.WRITE)
		if file == null:
			save_failed = true
			push_warning("无法保存任务文件: %s" % quest_file_path)
			continue
		file.store_string(json)
		file.close()

	if save_failed:
		_update_status("部分任务文件保存失败")
		return

	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var existing_quest_id := file_name.trim_suffix(".json")
				if not nodes.has(existing_quest_id):
					dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	quest_saved.emit(selected_node_id)
	_update_status("已保存 %d 个任务到 %s" % [quest_ids.size(), path])

func _on_load_quests() -> void:
	if not _load_from_directory(QUEST_DATA_DIR):
		_update_status("未找到有效任务文件: %s" % QUEST_DATA_DIR)

func _load_from_directory(directory_path: String) -> bool:
	var absolute_dir_path := ProjectSettings.globalize_path(directory_path)
	if not DirAccess.dir_exists_absolute(absolute_dir_path):
		return false

	var dir := DirAccess.open(directory_path)
	if dir == null:
		_update_status("无法读取目录: %s" % directory_path)
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
		return false

	_clear_editor_state()

	var loaded_count := 0
	for file_index in range(file_names.size()):
		var quest_file_name := file_names[file_index]
		var quest_file_path := "%s/%s" % [directory_path, quest_file_name]
		var validation := JSON_VALIDATOR.validate_file(quest_file_path, {
			"root_type": JSON_VALIDATOR.TYPE_DICTIONARY
		})
		if not bool(validation.get("ok", false)):
			push_warning(str(validation.get("message", "[JSON] Unknown validation error")))
			continue

		var loaded_quest: Variant = validation.get("data", {})
		if not (loaded_quest is Dictionary):
			push_warning("[JSON] %s | Invalid validator result: data must be Dictionary" % quest_file_path)
			continue

		var quest_id := str((loaded_quest as Dictionary).get("quest_id", "")).strip_edges()
		if quest_id.is_empty():
			quest_id = quest_file_name.get_basename()

		var node_data := _quest_to_node_data(quest_id, loaded_quest as Dictionary, loaded_count)
		_create_node_internal(node_data)
		loaded_count += 1

	if loaded_count == 0:
		_clear_editor_state()
		_update_status("未找到有效任务文件: %s" % directory_path)
		return false

	current_file_path = directory_path
	_rebuild_connections_from_prerequisites()

	for quest_id in nodes.keys():
		_validate_quest(quest_id)

	quest_loaded.emit(selected_node_id)
	_update_status("已从 %s 加载 %d 个任务" % [directory_path, loaded_count])
	return true

func _quest_to_node_data(quest_id: String, raw_quest: Dictionary, index: int) -> Dictionary:
	var quest := raw_quest.duplicate(true)
	var default_position := Vector2(float(index % 4) * 280.0, float(index / 4) * 180.0)
	var editor_meta: Variant = quest.get("_editor", {})
	var position := default_position
	if editor_meta is Dictionary:
		var pos_data: Variant = editor_meta.get("position", {})
		if pos_data is Dictionary:
			position = Vector2(float(pos_data.get("x", default_position.x)), float(pos_data.get("y", default_position.y)))

	quest.erase("_editor")
	quest["id"] = quest_id
	quest["quest_id"] = str(quest.get("quest_id", quest_id))
	quest["type"] = "quest"
	quest["position"] = position
	quest["title"] = str(quest.get("title", "Untitled Quest"))

	_apply_type_defaults(quest, "quest")
	return quest

func _on_export_gdscript() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "quest_data.gd"
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
	lines.append("# Auto-generated quest data")
	lines.append("# 生成时间: %s" % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("const QUESTS = {")

	var quest_ids: Array = nodes.keys()
	quest_ids.sort()
	for quest_id in quest_ids:
		var quest: Dictionary = nodes[quest_id]
		lines.append('\t"%s": {' % quest_id)
		lines.append('\t\t"quest_id": "%s",' % quest_id)
		lines.append('\t\t"title": "%s",' % str(quest.get("title", "")))
		lines.append('\t\t"description": "%s",' % str(quest.get("description", "")))
		lines.append('\t\t"objectives": [')
		for obj in quest.get("objectives", []):
			lines.append('\t\t\t{')
			lines.append('\t\t\t\t"type": "%s",' % str(obj.get("type", "")))
			lines.append('\t\t\t\t"target": "%s",' % str(obj.get("target", "")))
			lines.append('\t\t\t\t"count": %d,' % int(obj.get("count", 1)))
			lines.append('\t\t\t\t"description": "%s"' % str(obj.get("description", "")))
			lines.append('\t\t\t},')
		lines.append('\t\t],')
		lines.append('\t\t"rewards": {')
		lines.append('\t\t\t"items": [')
		for item in quest.get("rewards", {}).get("items", []):
			lines.append('\t\t\t\t{"id": "%s", "count": %d},' % [str(item.get("id", "")), int(item.get("count", 1))])
		lines.append('\t\t\t],')
		lines.append('\t\t\t"experience": %d' % int(quest.get("rewards", {}).get("experience", 0)))
		lines.append('\t\t},')
		lines.append('\t\t"prerequisites": %s,' % str(quest.get("prerequisites", [])))
		lines.append('\t\t"time_limit": %d' % int(quest.get("time_limit", -1)))
		lines.append('\t},')

	lines.append('}')
	lines.append("")
	lines.append("static func get_quest(quest_id: String):")
	lines.append("\treturn QUESTS.get(quest_id, null)")
	return "\n".join(lines)

func _input(event: InputEvent) -> void:
	super._input(event)
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_N when event.ctrl_pressed:
				_on_new_quest()
			KEY_S when event.ctrl_pressed:
				_on_save_quests()

func focus_record(record_id: String) -> bool:
	var target_id := record_id.strip_edges()
	if target_id.is_empty():
		return false
	if not nodes.has(target_id):
		_update_status("未找到任务: %s" % target_id)
		return false

	_select_quest(target_id)
	_graph_edit.center_view()
	_update_status("已定位任务: %s" % target_id)
	return true

func get_current_quest_id() -> String:
	return selected_node_id

func get_quests_count() -> int:
	return nodes.size()

func get_validation_errors() -> Dictionary:
	return _validation_errors

func _update_reward_item_field(quest: Dictionary, index: int, field: String, value: Variant) -> void:
	var rewards: Dictionary = quest.get("rewards", {})
	var items: Array = rewards.get("items", [])
	if index >= items.size():
		return
	items[index][field] = value
	rewards["items"] = items
	quest["rewards"] = rewards
	_on_node_data_changed(str(quest.get("id", "")), quest)
