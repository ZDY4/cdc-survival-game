@tool
extends Control
## 任务编辑器
## 集成撤销/重做、数据验证、改进的属性编辑等功能

signal quest_saved(quest_id: String)
signal quest_loaded(quest_id: String)
signal validation_errors_found(errors: Array[String])

# 常量
const OBJECTIVE_TYPES = {
	"collect": "收集物品",
	"kill": "击败敌人",
	"location": "到达地点",
	"talk": "与NPC对话",
	"custom": "Custom"
}

const QUEST_STATUS_COLORS = {
	"valid": Color(0.2, 0.8, 0.2),
	"warning": Color(0.9, 0.6, 0.2),
	"error": Color(0.9, 0.2, 0.2)
}

const JSON_VALIDATOR = preload("res://addons/cdc_game_editor/utils/json_validator.gd")

# 节点引用
@onready var _quest_list: ItemList
@onready var _property_panel: Control
@onready var _toolbar: HBoxContainer
@onready var _file_dialog: FileDialog
@onready var _status_bar: Label
@onready var _search_box: LineEdit
@onready var _validation_panel: VBoxContainer

# 数据
var quests: Dictionary = {}  # quest_id -> quest_data
var current_quest_id: String = ""
var current_file_path: String = ""
var _validation_errors: Dictionary = {}  # quest_id -> Array[String]

# 工具
var _undo_redo_helper: RefCounted

# 编辑器插件引
var editor_plugin: EditorPlugin = null:
	set(plugin):
		editor_plugin = plugin
		if plugin:
			_undo_redo_helper = load("res://addons/cdc_game_editor/utils/undo_redo_helper.gd").new(plugin)

func _ready():
	_setup_ui()
	_setup_file_dialog()
	_load_quests_from_project_data()
	_update_quest_list()

func _load_quests_from_project_data() -> void:
	var preferred_paths: Array[String] = [
		"res://data/json/quests.json",
		"res://data/quests.json"
	]
	var has_candidate_file := false
	for path in preferred_paths:
		if not FileAccess.file_exists(path):
			continue
		has_candidate_file = true
		if _load_from_file(path):
			return

	if has_candidate_file:
		_update_status("[JSON] project_data | No valid quest JSON file found in project data paths")

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
	
	# 左侧：任务列
	var left_panel = _create_quest_list_panel()
	main_split.add_child(left_panel)
	
	# 右侧：属性面板和验证面板
	var right_container = VBoxContainer.new()
	right_container.custom_minimum_size = Vector2(350, 0)
	right_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_child(right_container)
	
	# 搜索
	var search_container = HBoxContainer.new()
	search_container.custom_minimum_size = Vector2(0, 30)
	right_container.add_child(search_container)
	
	var search_label = Label.new()
	search_label.text = "🔍"
	search_container.add_child(search_label)
	
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "搜索任务..."
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.text_changed.connect(_on_search_changed)
	search_container.add_child(_search_box)
	
	var clear_btn = Button.new()
	clear_btn.text = "清除"
	clear_btn.pressed.connect(func(): _search_box.clear(); _on_search_changed(""))
	search_container.add_child(clear_btn)
	
	# 属面
	_property_panel = preload("res://addons/cdc_game_editor/utils/property_panel.gd").new()
	_property_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_property_panel.panel_title = "Quest Properties"
	_property_panel.property_changed.connect(_on_property_changed)
	right_container.add_child(_property_panel)
	
	# 验证错误面板
	_validation_panel = VBoxContainer.new()
	_validation_panel.visible = false
	right_container.add_child(_validation_panel)
	
	var validation_title = Label.new()
	validation_title.text = "⚠️ 验证问题"
	validation_title.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
	_validation_panel.add_child(validation_title)
	_validation_panel.add_child(HSeparator.new())
	
	main_split.split_offset = 250
	
	# 状态栏
	_status_bar = Label.new()
	_status_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status_bar.offset_top = -20
	_status_bar.offset_bottom = 0
	_status_bar.offset_left = 0
	_status_bar.offset_right = 0
	_status_bar.text = "Ready - 0 quests"
	add_child(_status_bar)

func _create_toolbar():
	_add_toolbar_button("新建", _on_new_quest, "新建任务 (Ctrl+N)")
	_add_toolbar_button("删除", _on_delete_quest, "删除选中任务 (Delete)")
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("撤销", _on_undo, "撤销 (Ctrl+Z)")
	_add_toolbar_button("重做", _on_redo, "重做 (Ctrl+Y)")
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("保存", _on_save_quests, "保存到文(Ctrl+S)")
	_add_toolbar_button("Load", _on_load_quests, "Load from file")
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("Validate", _on_validate_all, "Validate all quests")
	_add_toolbar_button("导出GD", _on_export_gdscript, "导出为GDScript")

func _add_toolbar_button(text: String, callback: Callable, tooltip: String = ""):
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.pressed.connect(callback)
	_toolbar.add_child(btn)

func _create_quest_list_panel() -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)
	
	# 标题
	var title = Label.new()
	title.text = "任务列表"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	
	vbox.add_child(HSeparator.new())
	
	# 任务列表
	_quest_list = ItemList.new()
	_quest_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_quest_list.item_selected.connect(_on_quest_selected)
	vbox.add_child(_quest_list)
	
	return panel

func _setup_file_dialog():
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.json; JSON 文件")
	_file_dialog.add_filter("*.quest; 任务文件")
	add_child(_file_dialog)

func _input(event: InputEvent):
	if not visible:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_DELETE:
				_on_delete_quest()
			KEY_N when event.ctrl_pressed:
				_on_new_quest()
			KEY_S when event.ctrl_pressed:
				_on_save_quests()
			KEY_Z when event.ctrl_pressed and not event.shift_pressed:
				_on_undo()
			KEY_Y when event.ctrl_pressed:
				_on_redo()

# 任务管理
func _on_new_quest():
	var quest_id = "quest_%d" % Time.get_ticks_msec()
	var quest_data = {
		"quest_id": quest_id,
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
	var quest_snapshot = quest_data.duplicate(true)
	
	# 撤销/重做
	if _undo_redo_helper:
		_undo_redo_helper.create_action("创建任务")
		_undo_redo_helper.add_undo_method(self, "_remove_quest", quest_id)
		_undo_redo_helper.add_redo_method(self, "_add_quest", quest_id, quest_snapshot)
		_undo_redo_helper.commit_action()
	
	_add_quest(quest_id, quest_data)
	_select_quest(quest_id)
	_update_status("创建了新任务: %s" % quest_id)

func _add_quest(quest_id: String, quest_data: Dictionary):
	quests[quest_id] = quest_data.duplicate(true)
	_update_quest_list()
	_validate_quest(quest_id)

func _remove_quest(quest_id: String):
	if quests.has(quest_id):
		var old_data = quests[quest_id].duplicate(true)
		quests.erase(quest_id)
		_validation_errors.erase(quest_id)
		
		if current_quest_id == quest_id:
			current_quest_id = ""
			_property_panel.clear()
		
		_update_quest_list()
		_update_validation_panel()
		return old_data
	return null

func _on_delete_quest():
	if current_quest_id.is_empty():
		return
	
	var quest_id = current_quest_id
	var old_data = quests[quest_id].duplicate(true)
	
	# 撤销/重做
	if _undo_redo_helper:
		_undo_redo_helper.create_action("删除任务")
		_undo_redo_helper.add_undo_method(self, "_add_quest", quest_id, old_data)
		_undo_redo_helper.add_redo_method(self, "_remove_quest", quest_id)
		_undo_redo_helper.commit_action()
	
	_remove_quest(quest_id)
	_update_status("删除了任 %s" % quest_id)

func _on_quest_selected(index: int):
	var quest_id = _quest_list.get_item_metadata(index)
	_select_quest(quest_id)

func _select_quest(quest_id: String):
	current_quest_id = quest_id
	var quest = quests.get(quest_id)
	if quest:
		_update_property_panel(quest)
		_update_validation_panel()

func _update_quest_list(filter: String = ""):
	_quest_list.clear()
	
	var sorted_quests = quests.keys()
	sorted_quests.sort()
	
	for quest_id in sorted_quests:
		var quest = quests[quest_id]
		var display_text = "%s - %s" % [quest_id, quest.get("title", "Unnamed")]
		
		if filter.is_empty() or display_text.to_lower().contains(filter.to_lower()):
			var idx = _quest_list.add_item(display_text)
			_quest_list.set_item_metadata(idx, quest_id)
			
			# 根据验证状
			if _validation_errors.has(quest_id) and not _validation_errors[quest_id].is_empty():
				_quest_list.set_item_custom_fg_color(idx, QUEST_STATUS_COLORS.error)
	
	_update_status("Total quests: %d" % quests.size())

func _on_search_changed(text: String):
	_update_quest_list(text)

# 属面
func _update_property_panel(quest: Dictionary):
	_property_panel.clear()
	
	if quest.is_empty():
		return
	
	# ID（可编辑，但需要特殊处理）
	_property_panel.add_string_property("quest_id", "任务ID:", quest.get("quest_id", ""), false, "Unique identifier")
	
	# 标和描
	_property_panel.add_string_property("title", "任务标题:", quest.get("title", ""), false, "显示名称")
	_property_panel.add_string_property("description", "任务描述:", quest.get("description", ""), true, "详细描述...")
	
	_property_panel.add_separator()
	
	# 经验值
	var rewards = quest.get("rewards", {})
	_property_panel.add_number_property("experience", "经验值", 
		rewards.get("experience", 0), 0, 999999, 10, false)
	
	# 时间限制
	_property_panel.add_number_property("time_limit", "时间限制(:", 
		quest.get("time_limit", -1), -1, 999999, 1, false)
	
	_property_panel.add_separator()
	
	# 自定义控件：目标列表
	_property_panel.add_custom_control(_create_objectives_editor(quest))
	
	_property_panel.add_separator()
	
	# 自定义控件：奖励物品列表
	_property_panel.add_custom_control(_create_rewards_editor(quest))
	
	_property_panel.add_separator()
	
	# 自定义控件：前置任务
	_property_panel.add_custom_control(_create_prerequisites_editor(quest))

func _create_objectives_editor(quest: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "📋 任务 (%d" % quest.objectives.size()
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	container.add_child(label)
	
	var list_container = VBoxContainer.new()
	list_container.name = "ObjectivesList"
	container.add_child(list_container)
	
	_refresh_objectives_list(list_container, quest)
	
	var add_btn = Button.new()
	add_btn.text = "+ 添加目标"
	add_btn.pressed.connect(func(): _add_objective(quest, list_container))
	container.add_child(add_btn)
	
	return container

func _refresh_objectives_list(container: VBoxContainer, quest: Dictionary):
	for child in container.get_children():
		child.queue_free()
	
	var objectives = quest.get("objectives", [])
	for i in range(objectives.size()):
		var obj = objectives[i]
		var row = _create_objective_row(quest, i, obj, container)
		container.add_child(row)

func _create_objective_row(quest: Dictionary, index: int, obj: Dictionary, list_container: VBoxContainer) -> Control:
	var panel = PanelContainer.new()
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	# 类型和目
	var top_row = HBoxContainer.new()
	vbox.add_child(top_row)
	
	var type_option = OptionButton.new()
	for key in OBJECTIVE_TYPES:
		type_option.add_item(OBJECTIVE_TYPES[key], type_option.item_count)
		type_option.set_item_metadata(type_option.item_count - 1, key)
		if key == obj.get("type", "collect"):
			type_option.selected = type_option.item_count - 1
	
	type_option.item_selected.connect(func(i):
		var type_key = type_option.get_item_metadata(i)
		_on_objective_field_changed(quest, index, "type", type_key)
	)
	top_row.add_child(type_option)
	
	var target_edit = LineEdit.new()
	target_edit.text = obj.get("target", "")
	target_edit.placeholder_text = "目标ID"
	target_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_edit.text_changed.connect(func(v): _on_objective_field_changed(quest, index, "target", v))
	top_row.add_child(target_edit)
	
	var count_spin = SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 999
	count_spin.value = obj.get("count", 1)
	count_spin.value_changed.connect(func(v): _on_objective_field_changed(quest, index, "count", int(v)))
	top_row.add_child(count_spin)
	
	# 描述
	var desc_row = HBoxContainer.new()
	vbox.add_child(desc_row)
	
	var desc_edit = LineEdit.new()
	desc_edit.text = obj.get("description", "")
	desc_edit.placeholder_text = "目标描述"
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_edit.text_changed.connect(func(v): _on_objective_field_changed(quest, index, "description", v))
	desc_row.add_child(desc_edit)
	
	var del_btn = Button.new()
	del_btn.text = "×"
	del_btn.tooltip_text = "删除目标"
	del_btn.pressed.connect(func(): _remove_objective(quest, index, list_container))
	desc_row.add_child(del_btn)
	
	return panel

func _on_objective_field_changed(quest: Dictionary, index: int, field: String, value: Variant):
	if index < quest.objectives.size():
		quest.objectives[index][field] = value
		_validate_quest(quest.quest_id)

func _add_objective(quest: Dictionary, list_container: VBoxContainer):
	var new_objective = {
		"type": "collect",
		"target": "",
		"count": 1,
		"description": "New objective"
	}
	var quest_id = str(quest.get("quest_id", ""))
	var insert_index = quest.objectives.size()
	
	# 撤销/重做
	if _undo_redo_helper and not quest_id.is_empty():
		_undo_redo_helper.create_action("添加目标")
		_undo_redo_helper.add_undo_method(self, "_remove_objective_at", quest_id, insert_index)
		_undo_redo_helper.add_redo_method(self, "_insert_objective_at", quest_id, insert_index, new_objective)
		_undo_redo_helper.commit_action()
	
	quest.objectives.append(new_objective)
	_refresh_objectives_list(list_container, quest)
	_validate_quest(quest.quest_id)

func _remove_objective(quest: Dictionary, index: int, list_container: VBoxContainer):
	if index < quest.objectives.size():
		var old_obj = quest.objectives[index].duplicate(true)
		var quest_id = str(quest.get("quest_id", ""))
		
		# 撤销/重做
		if _undo_redo_helper and not quest_id.is_empty():
			_undo_redo_helper.create_action("删除目标")
			_undo_redo_helper.add_undo_method(self, "_insert_objective_at", quest_id, index, old_obj)
			_undo_redo_helper.add_redo_method(self, "_remove_objective_at", quest_id, index)
			_undo_redo_helper.commit_action()
		
		quest.objectives.remove_at(index)
		_refresh_objectives_list(list_container, quest)
		_validate_quest(quest.quest_id)

func _remove_objective_at(quest_id: String, index: int):
	var quest = quests.get(quest_id, {})
	if quest and index >= 0 and index < quest.objectives.size():
		quest.objectives.remove_at(index)
		_validate_quest(quest_id)
		if current_quest_id == quest_id:
			_update_property_panel(quest)
		_update_quest_list(_search_box.text)
		_update_validation_panel()

func _insert_objective_at(quest_id: String, index: int, obj: Dictionary):
	var quest = quests.get(quest_id, {})
	if not quest:
		return
	var target_index: int = clampi(index, 0, quest.objectives.size())
	quest.objectives.insert(target_index, obj.duplicate(true))
	_validate_quest(quest_id)
	if current_quest_id == quest_id:
		_update_property_panel(quest)
	_update_quest_list(_search_box.text)
	_update_validation_panel()

func _create_rewards_editor(quest: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "🎁 物品奖励"
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	container.add_child(label)
	
	var rewards = quest.get("rewards", {})
	var items = rewards.get("items", [])
	
	var list = VBoxContainer.new()
	list.name = "RewardsList"
	container.add_child(list)
	
	for i in range(items.size()):
		var row = _create_reward_row(quest, i, items[i], list)
		list.add_child(row)
	
	var add_btn = Button.new()
	add_btn.text = "+ 添加物品"
	add_btn.pressed.connect(func(): _add_reward_item(quest, list))
	container.add_child(add_btn)
	
	return container

func _create_reward_row(quest: Dictionary, index: int, item: Dictionary, list: VBoxContainer) -> Control:
	var row = HBoxContainer.new()
	
	var id_edit = LineEdit.new()
	id_edit.text = item.get("id", "")
	id_edit.placeholder_text = "物品ID"
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_edit.text_changed.connect(func(v):
		quest.rewards.items[index].id = v
	)
	row.add_child(id_edit)
	
	var count_spin = SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 999
	count_spin.value = item.get("count", 1)
	count_spin.value_changed.connect(func(v):
		quest.rewards.items[index].count = int(v)
	)
	row.add_child(count_spin)
	
	var del_btn = Button.new()
	del_btn.text = "×"
	del_btn.pressed.connect(func(): _remove_reward_item(quest, index, list))
	row.add_child(del_btn)
	
	return row

func _add_reward_item(quest: Dictionary, list: VBoxContainer):
	quest.rewards.items.append({"id": "", "count": 1})
	_refresh_rewards_list(list, quest)

func _remove_reward_item(quest: Dictionary, index: int, list: VBoxContainer):
	if index < quest.rewards.items.size():
		quest.rewards.items.remove_at(index)
		_refresh_rewards_list(list, quest)

func _refresh_rewards_list(list: VBoxContainer, quest: Dictionary):
	for child in list.get_children():
		child.queue_free()
	
	var items = quest.get("rewards", {}).get("items", [])
	for i in range(items.size()):
		var row = _create_reward_row(quest, i, items[i], list)
		list.add_child(row)

func _create_prerequisites_editor(quest: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "🔗 前置任务"
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	container.add_child(label)
	
	var prereq_list = VBoxContainer.new()
	prereq_list.name = "PrereqList"
	container.add_child(prereq_list)
	
	_refresh_prereq_list(prereq_list, quest)
	
	var add_btn = Button.new()
	add_btn.text = "+ 添加前置任务"
	add_btn.pressed.connect(func(): _show_prereq_selector(quest, prereq_list))
	container.add_child(add_btn)
	
	return container

func _refresh_prereq_list(list: VBoxContainer, quest: Dictionary):
	for child in list.get_children():
		child.queue_free()
	
	for prereq_id in quest.get("prerequisites", []):
		var row = HBoxContainer.new()
		
		var id_label = Label.new()
		id_label.text = prereq_id
		id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(id_label)
		
		var del_btn = Button.new()
		del_btn.text = "×"
		del_btn.pressed.connect(func(): _remove_prereq(quest, prereq_id, list))
		row.add_child(del_btn)
		
		list.add_child(row)

func _show_prereq_selector(quest: Dictionary, list: VBoxContainer):
	var popup = PopupPanel.new()
	popup.size = Vector2(400, 300)
	
	var vbox = VBoxContainer.new()
	popup.add_child(vbox)
	
	var title = Label.new()
	title.text = "选择前置任务"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var item_list = ItemList.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(item_list)
	
	for quest_id in quests:
		if quest_id != quest.quest_id and not quest.prerequisites.has(quest_id):
			var q = quests[quest_id]
			var idx = item_list.add_item("%s - %s" % [quest_id, q.get("title", "")])
			item_list.set_item_metadata(idx, quest_id)
	
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_box)
	
	var confirm_btn = Button.new()
	confirm_btn.text = "确认"
	confirm_btn.pressed.connect(func():
		var selected = item_list.get_selected_items()
		if selected.size() > 0:
			var prereq_id = item_list.get_item_metadata(selected[0])
			_add_prereq(quest, prereq_id, list)
		popup.queue_free()
	)
	btn_box.add_child(confirm_btn)
	
	add_child(popup)
	popup.popup_centered()

func _add_prereq(quest: Dictionary, prereq_id: String, list: VBoxContainer):
	if not quest.prerequisites.has(prereq_id):
		quest.prerequisites.append(prereq_id)
		_refresh_prereq_list(list, quest)
		_validate_quest(quest.quest_id)

func _remove_prereq(quest: Dictionary, prereq_id: String, list: VBoxContainer):
	quest.prerequisites.erase(prereq_id)
	_refresh_prereq_list(list, quest)
	_validate_quest(quest.quest_id)

# 属变
func _on_property_changed(property_name: String, new_value: Variant, old_value: Variant):
	if current_quest_id.is_empty():
		return
	
	var quest = quests[current_quest_id]
	
	# 特殊处理嵌属
	if property_name == "experience":
		quest.rewards.experience = int(new_value)
	elif property_name == "time_limit":
		quest.time_limit = int(new_value)
	elif property_name == "quest_id":
		# ID变更要特殊
		if new_value != current_quest_id and not new_value.is_empty():
			if _undo_redo_helper:
				_undo_redo_helper.create_action("修改任务ID")
				_undo_redo_helper.add_undo_method(self, "_change_quest_id", new_value, current_quest_id)
				_undo_redo_helper.add_redo_method(self, "_change_quest_id", current_quest_id, new_value)
				_undo_redo_helper.commit_action()
			_change_quest_id(current_quest_id, new_value)
			return
	else:
		quest[property_name] = new_value
	
	_validate_quest(current_quest_id)
	_update_quest_list()

func _change_quest_id(old_id: String, new_id: String):
	if quests.has(old_id) and not quests.has(new_id):
		var data = quests[old_id]
		data.quest_id = new_id
		quests.erase(old_id)
		quests[new_id] = data
		
		if _validation_errors.has(old_id):
			_validation_errors[new_id] = _validation_errors[old_id]
			_validation_errors.erase(old_id)
		
		current_quest_id = new_id
		_update_quest_list()
		_select_quest(new_id)

# 验证
func _validate_quest(quest_id: String) -> bool:
	var quest = quests.get(quest_id)
	if not quest:
		return false
	
	var errors: Array[String] = []
	
	# 检查ID
	if quest_id.is_empty():
		errors.append("任务ID不能为空")
	
	# 查标
	if quest.get("title", "").is_empty():
		errors.append("任务标题不能为空")
	
	# 查目
	var objectives = quest.get("objectives", [])
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
	
	# 查前
	for prereq in quest.get("prerequisites", []):
		if not quests.has(prereq):
			errors.append("Prerequisite quest '%s' does not exist" % prereq)
	
	_validation_errors[quest_id] = errors
	return errors.is_empty()

func _validate_all():
	var all_errors: Array[String] = []
	
	for quest_id in quests:
		if not _validate_quest(quest_id):
			for error in _validation_errors[quest_id]:
				all_errors.append("%s: %s" % [quest_id, error])
	
	validation_errors_found.emit(all_errors)
	return all_errors

func _on_validate_all():
	var errors = _validate_all()
	_update_validation_panel()
	
	if errors.is_empty():
		_update_status("有任务验证过")
	else:
		_update_status("Found %d validation issues" % errors.size())

func _update_validation_panel():
	if current_quest_id.is_empty():
		_validation_panel.visible = false
		return
	
	var errors = _validation_errors.get(current_quest_id, [])
	
	if errors.is_empty():
		_validation_panel.visible = false
		return
	
	_validation_panel.visible = true
	
	# 清除旧的错误显示（保留标题和分隔符）
	while _validation_panel.get_child_count() > 2:
		_validation_panel.remove_child(_validation_panel.get_child(2))
	
	for error in errors:
		var label = Label.new()
		label.text = "%s" % error
		label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_validation_panel.add_child(label)

# 文件操作
func _on_save_quests():
	if current_file_path.is_empty():
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.current_file = "quests.json"
		_file_dialog.file_selected.connect(_save_to_file, CONNECT_ONE_SHOT)
		_file_dialog.popup_centered(Vector2(800, 600))
	else:
		_save_to_file(current_file_path)

func _save_to_file(path: String):
	current_file_path = path
	var json = JSON.stringify(quests, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		quest_saved.emit(current_quest_id)
		_update_status("已保 %s" % path)
	else:
		_update_status("无法保存文件")

func _on_load_quests():
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.file_selected.connect(_load_from_file, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _load_from_file(path: String) -> bool:
	var validation := JSON_VALIDATOR.validate_file(path, {
		"root_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"wrapper_key": "quests",
		"wrapper_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"entry_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"entry_label": "quest"
	})
	if not bool(validation.get("ok", false)):
		_update_status(str(validation.get("message", "[JSON] Unknown validation error")))
		return false

	var loaded_quests: Variant = validation.get("data", {})
	if not (loaded_quests is Dictionary):
		_update_status("[JSON] %s | Invalid validator result: data must be Dictionary" % path)
		return false
	quests = loaded_quests

	current_file_path = path
	current_quest_id = ""
	_validation_errors.clear()
	
	# Validate all quests after load.
	for quest_id in quests:
		_validate_quest(quest_id)
	
	_update_quest_list()
	_property_panel.clear()
	quest_loaded.emit(current_quest_id)
	_update_status("Loaded: %s" % path)
	return true

func _on_export_gdscript():
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "quest_data.gd"
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
	lines.append("# Auto-generated quest data")
	lines.append("# 生成时间: %s" % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("const QUESTS = {")
	
	var quest_keys = quests.keys()
	for i in range(quest_keys.size()):
		var quest_id = quest_keys[i]
		var quest = quests[quest_id]
		
		lines.append('\t"%s": {' % quest_id)
		lines.append('\t\t"quest_id": "%s",' % quest_id)
		lines.append('\t\t"title": "%s",' % quest.get("title", ""))
		lines.append('\t\t"description": "%s",' % quest.get("description", ""))
		
		# 目标
		lines.append('\t\t"objectives": [')
		for obj in quest.get("objectives", []):
			lines.append('\t\t\t{')
			lines.append('\t\t\t\t"type": "%s",' % obj.get("type", ""))
			lines.append('\t\t\t\t"target": "%s",' % obj.get("target", ""))
			lines.append('\t\t\t\t"count": %d,' % obj.get("count", 1))
			lines.append('\t\t\t\t"description": "%s"' % obj.get("description", ""))
			lines.append('\t\t\t},')
		lines.append('\t\t],')
		
		# 奖励
		lines.append('\t\t"rewards": {')
		lines.append('\t\t\t"items": [')
		for item in quest.get("rewards", {}).get("items", []):
			lines.append('\t\t\t\t{"id": "%s", "count": %d},' % [item.get("id", ""), item.get("count", 1)])
		lines.append('\t\t\t],')
		lines.append('\t\t\t"experience": %d' % quest.get("rewards", {}).get("experience", 0))
		lines.append('\t\t},')
		
		# 前置任务
		lines.append('\t\t"prerequisites": %s,' % str(quest.get("prerequisites", [])))
		lines.append('\t\t"time_limit": %d' % quest.get("time_limit", -1))
		lines.append('\t},')
	
	lines.append('}')
	lines.append("")
	lines.append("static func get_quest(quest_id: String):")
	lines.append("\treturn QUESTS.get(quest_id, null)")
	
	return "\n".join(lines)

# 撤销/重做
func _on_undo():
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().undo()
		_update_status("撤销")
		_update_quest_list()
		_update_validation_panel()

func _on_redo():
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().redo()
		_update_status("重做")
		_update_quest_list()
		_update_validation_panel()

func _update_status(message: String):
	_status_bar.text = "%s - Total %d quests" % [message, quests.size()]
	print("任务编辑器 %s" % message)

# 公共方法
func get_current_quest_id() -> String:
	return current_quest_id

func get_quests_count() -> int:
	return quests.size()

func get_validation_errors() -> Dictionary:
	return _validation_errors

