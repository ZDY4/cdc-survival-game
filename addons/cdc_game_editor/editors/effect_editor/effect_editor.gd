@tool
extends Control
## EffectEditor - 效果编辑器
## 用于创建和编辑游戏中的效果（buffs/debuffs

signal effect_saved(effect_id: String)
signal effect_loaded(effect_id: String)

# 效果类别
const EFFECT_CATEGORIES = {
	"buff": "增益 (Buff)",
	"debuff": "减益 (Debuff)",
	"neutral": "(Neutral)"
}

const DEFAULT_EFFECTS_DIR := "res://data/json/effects"

# 叠加模式
const STACK_MODES = {
	"refresh": "刷新持续时间",
	"extend": "延长持续时间",
	"intensity": "增强效果",
	"separate": "独立实例"
}

# 属列
const AVAILABLE_STATS = [
	"strength",
	"agility",
	"constitution",
	"intelligence",
	"perception",
	"charisma",
	"max_hp",
	"max_stamina",
	"damage",
	"defense",
	"speed",
	"crit_chance",
	"crit_damage",
	"damage_mult",
	"defense_mult",
	"speed_mult",
	"exp_mult"
]

# 节点引用
@onready var _effect_list: ItemList
@onready var _category_filter: OptionButton
@onready var _search_box: LineEdit
@onready var _property_panel: VBoxContainer
@onready var _toolbar: HBoxContainer
@onready var _file_dialog: FileDialog
@onready var _status_bar: Label

# 数据
var effects: Dictionary = {}  # effect_id -> effect_data
var current_effect_id: String = ""
var current_dir_path: String = ""

# UI元素引用
var _ui_elements: Dictionary = {}

# 编辑器插件引
var editor_plugin: EditorPlugin = null

func _ready():
	_setup_ui()
	_setup_file_dialog()
	_update_effect_list()

func _setup_ui():
	anchors_preset = Control.PRESET_FULL_RECT
	
	# 工具栏
	_toolbar = HBoxContainer.new()
	_toolbar.custom_minimum_size = Vector2(0, 45)
	add_child(_toolbar)
	
	var new_btn = Button.new()
	new_btn.text = "新建效果"
	new_btn.pressed.connect(_on_new_effect)
	_toolbar.add_child(new_btn)
	
	var delete_btn = Button.new()
	delete_btn.text = "删除"
	delete_btn.pressed.connect(_on_delete_effect)
	_toolbar.add_child(delete_btn)
	
	_toolbar.add_child(VSeparator.new())
	
	var save_btn = Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(_on_save_effects)
	_toolbar.add_child(save_btn)
	
	var load_btn = Button.new()
	load_btn.text = "加载"
	load_btn.pressed.connect(_on_load_effects)
	_toolbar.add_child(load_btn)
	
	# 主分割
	var main_split = HSplitContainer.new()
	main_split.position = Vector2(0, 50)
	main_split.size = Vector2(size.x, size.y - 70)
	add_child(main_split)
	
	# 左侧：效果列
	var left_panel = _create_effect_list_panel()
	main_split.add_child(left_panel)
	
	# 右侧：属性面板
	var right_panel = _create_property_panel()
	main_split.add_child(right_panel)
	
	main_split.split_offset = 250
	
	# 状态栏
	_status_bar = Label.new()
	_status_bar.position = Vector2(0, size.y - 20)
	_status_bar.size = Vector2(size.x, 20)
	_status_bar.text = "就绪"
	add_child(_status_bar)

func _create_effect_list_panel() -> Control:
	var panel = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)
	
	var title = Label.new()
	title.text = "效果列表"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)
	
	panel.add_child(HSeparator.new())
	
	# 类别过滤
	_category_filter = OptionButton.new()
	_category_filter.add_item("全部类别")
	_category_filter.add_item("增益 (Buff)")
	_category_filter.add_item("减益 (Debuff)")
	_category_filter.add_item("(Neutral)")
	_category_filter.item_selected.connect(_on_category_filter_changed)
	panel.add_child(_category_filter)
	
	# 搜索
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "搜索效果..."
	_search_box.text_changed.connect(_on_search_changed)
	panel.add_child(_search_box)
	
	# 效果列表
	_effect_list = ItemList.new()
	_effect_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_effect_list.item_selected.connect(_on_effect_selected)
	panel.add_child(_effect_list)
	
	# 统计
	var stats = Label.new()
	stats.name = "StatsLabel"
	stats.text = "Total: 0 effects"
	panel.add_child(stats)
	
	return panel

func _create_property_panel() -> Control:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	_property_panel = VBoxContainer.new()
	_property_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_property_panel.add_theme_constant_override("separation", 10)
	scroll.add_child(_property_panel)
	
	return scroll

func _setup_file_dialog():
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.json; JSON文件")
	add_child(_file_dialog)
	
	var default_dir := ProjectSettings.globalize_path(DEFAULT_EFFECTS_DIR)
	if DirAccess.dir_exists_absolute(default_dir):
		_file_dialog.current_dir = default_dir
		current_dir_path = default_dir

func _update_effect_list(category_filter: String = "", search_filter: String = ""):
	_effect_list.clear()
	_ui_elements.clear()
	
	var sorted_effects = effects.keys()
	sorted_effects.sort()
	
	for effect_id in sorted_effects:
		var effect = effects[effect_id]
		var category = effect.get("category", "neutral")
		var display_text = "%s - %s (%s)" % [effect_id, effect.get("name", "Unnamed"), EFFECT_CATEGORIES.get(category, category)]
		
		# 类别过滤
		if not category_filter.is_empty() and category != category_filter:
			continue
		
		# 搜索过滤
		if not search_filter.is_empty() and not display_text.to_lower().contains(search_filter.to_lower()):
			continue
		
		var idx = _effect_list.add_item(display_text)
		_effect_list.set_item_metadata(idx, effect_id)
		
		# 根据类别设置颜色
		match category:
			"buff":
				_effect_list.set_item_custom_fg_color(idx, Color.GREEN)
			"debuff":
				_effect_list.set_item_custom_fg_color(idx, Color.RED)
			"neutral":
				_effect_list.set_item_custom_fg_color(idx, Color.GRAY)
	
	var stats_label = get_node_or_null("StatsLabel")
	if stats_label:
		stats_label.text = "Total: %d effects" % effects.size()

func _on_category_filter_changed(index: int):
	var category = ""
	match index:
		0: category = ""
		1: category = "buff"
		2: category = "debuff"
		3: category = "neutral"
	_update_effect_list(category, _search_box.text)

func _on_search_changed(text: String):
	var category = ""
	match _category_filter.selected:
		0: category = ""
		1: category = "buff"
		2: category = "debuff"
		3: category = "neutral"
	_update_effect_list(category, text)

func _on_new_effect():
	var effect_id = "effect_%d" % Time.get_ticks_msec()
	var effect_data = {
		"id": effect_id,
		"name": "New Effect",
		"description": "效果描述",
		"category": "neutral",
		"icon_path": "",
		"duration": 60.0,
		"is_infinite": false,
		"is_stackable": false,
		"max_stacks": 1,
		"stack_mode": "refresh",
		"stat_modifiers": {},
		"special_effects": [],
		"tick_interval": 0.0,
		"visual_effect": "",
		"color_tint": ""
	}
	
	effects[effect_id] = effect_data
	_update_effect_list()
	_select_effect(effect_id)
	_update_status("创建了新效果: %s" % effect_id)

func _on_delete_effect():
	if current_effect_id.is_empty():
		return
	
	effects.erase(current_effect_id)
	current_effect_id = ""
	_update_effect_list()
	_clear_property_panel()
	_update_status("Deleted effect")

func _on_effect_selected(index: int):
	var effect_id = _effect_list.get_item_metadata(index)
	_select_effect(effect_id)

func _select_effect(effect_id: String):
	current_effect_id = effect_id
	var effect = effects.get(effect_id)
	if effect:
		_update_property_panel(effect)

func _clear_property_panel():
	for child in _property_panel.get_children():
		child.queue_free()

func _update_property_panel(effect: Dictionary):
	_clear_property_panel()
	_ui_elements.clear()
	
	# 基础信息
	_add_section_label("📋 基础信息")
	_add_string_field("id", "效果 ID:", effect.get("id", ""), false)
	_add_string_field("name", "显示名称:", effect.get("name", ""))
	_add_string_field("description", "描述:", effect.get("description", ""), true)
	_add_enum_field("category", "效果类别:", EFFECT_CATEGORIES, effect.get("category", "neutral"))
	_add_string_field("icon_path", "图标路径:", effect.get("icon_path", ""), false, "res://assets/icons/...")
	
	_add_separator()
	
	# 持续时间
	_add_section_label("⏱️ 持续时间")
	_add_number_field("duration", "持续时间(:", effect.get("duration", 60.0), 0.0, 99999.0, 1.0)
	_add_bool_field("is_infinite", "无限持续时间:", effect.get("is_infinite", false))
	
	_add_separator()
	
	# 叠加设置
	_add_section_label("🔢 叠加设置")
	_add_bool_field("is_stackable", "???:", effect.get("is_stackable", false))
	_add_number_field("max_stacks", "大叠加层", effect.get("max_stacks", 1), 1, 100, 1)
	_add_enum_field("stack_mode", "叠加模式:", STACK_MODES, effect.get("stack_mode", "refresh"))
	
	_add_separator()
	
	# 属性修饰符
	_add_section_label("📊 属性修饰符")
	_add_stat_modifiers_editor(effect.get("stat_modifiers", {}))
	
	_add_separator()
	
	# 特殊效果
	_add_section_label("特殊效果")
	_add_special_effects_editor(effect.get("special_effects", []))
	
	_add_separator()
	
	# 高级设置
	_add_section_label("⚙️ 高级设置")
	_add_number_field("tick_interval", "触发间隔(:", effect.get("tick_interval", 0.0), 0.0, 60.0, 0.1)
	_add_string_field("visual_effect", "视觉特效:", effect.get("visual_effect", ""))
	_add_string_field("color_tint", "屏幕色调:", effect.get("color_tint", ""), false, "#FF0000")

# ========== UI 辅助方法 ==========

func _add_section_label(text: String):
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.YELLOW)
	_property_panel.add_child(label)

func _add_separator():
	_property_panel.add_child(HSeparator.new())

func _add_string_field(key: String, label_text: String, value: String, multiline: bool = false, placeholder: String = ""):
	var hbox = HBoxContainer.new()
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(label)
	
	var line_edit = LineEdit.new()
	if multiline:
		line_edit = TextEdit.new()
		line_edit.custom_minimum_size = Vector2(0, 60)
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.text = value
	line_edit.placeholder_text = placeholder
	
	# 连接信号
	if multiline:
		line_edit.text_changed.connect(func(): _on_field_changed(key, line_edit.text))
	else:
		line_edit.text_changed.connect(func(new_text): _on_field_changed(key, new_text))
	
	hbox.add_child(line_edit)
	_property_panel.add_child(hbox)
	_ui_elements[key] = line_edit

func _add_number_field(key: String, label_text: String, value: float, min_val: float, max_val: float, step: float):
	var hbox = HBoxContainer.new()
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(label)
	
	var spin_box = SpinBox.new()
	spin_box.min_value = min_val
	spin_box.max_value = max_val
	spin_box.step = step
	spin_box.value = value
	spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin_box.value_changed.connect(func(v): _on_field_changed(key, v))
	
	hbox.add_child(spin_box)
	_property_panel.add_child(hbox)
	_ui_elements[key] = spin_box

func _add_bool_field(key: String, label_text: String, value: bool):
	var hbox = HBoxContainer.new()
	
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)
	
	var checkbox = CheckBox.new()
	checkbox.button_pressed = value
	checkbox.toggled.connect(func(v): _on_field_changed(key, v))
	
	hbox.add_child(checkbox)
	_property_panel.add_child(hbox)
	_ui_elements[key] = checkbox

func _add_enum_field(key: String, label_text: String, options: Dictionary, value: String):
	var hbox = HBoxContainer.new()
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(label)
	
	var option_btn = OptionButton.new()
	option_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var index = 0
	var selected_index = 0
	for key_opt in options.keys():
		option_btn.add_item(options[key_opt])
		option_btn.set_item_metadata(index, key_opt)
		if key_opt == value:
			selected_index = index
		index += 1
	
	option_btn.selected = selected_index
	option_btn.item_selected.connect(func(idx): 
		var selected_key = option_btn.get_item_metadata(idx)
		_on_field_changed(key, selected_key)
	)
	
	hbox.add_child(option_btn)
	_property_panel.add_child(hbox)
	_ui_elements[key] = option_btn

func _add_stat_modifiers_editor(modifiers: Dictionary):
	var container = VBoxContainer.new()
	container.name = "StatModifiersContainer"
	
	# 显示当前
	for stat_name in modifiers.keys():
		var value = modifiers[stat_name]
		_create_stat_modifier_row(container, stat_name, value)
	
	# 添加新修饰符的UI
	var add_hbox = HBoxContainer.new()
	
	var stat_option = OptionButton.new()
	stat_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for stat in AVAILABLE_STATS:
		stat_option.add_item(stat)
	add_hbox.add_child(stat_option)
	
	var value_spin = SpinBox.new()
	value_spin.min_value = -999
	value_spin.max_value = 999
	value_spin.step = 1
	value_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_hbox.add_child(value_spin)
	
	var add_btn = Button.new()
	add_btn.text = "添加"
	add_btn.pressed.connect(func():
		var stat = stat_option.get_item_text(stat_option.selected)
		var val = value_spin.value
		if not modifiers.has(stat):
			modifiers[stat] = val
			_create_stat_modifier_row(container, stat, val, modifiers)
			_on_field_changed("stat_modifiers", modifiers)
	)
	add_hbox.add_child(add_btn)
	
	container.add_child(add_hbox)
	_property_panel.add_child(container)
	_ui_elements["stat_modifiers"] = container

func _create_stat_modifier_row(container: VBoxContainer, stat_name: String, value: float, modifiers: Dictionary = {}):
	var row = HBoxContainer.new()
	
	var stat_label = Label.new()
	stat_label.text = stat_name
	stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(stat_label)
	
	var value_label = Label.new()
	value_label.text = str(value)
	value_label.custom_minimum_size = Vector2(60, 0)
	row.add_child(value_label)
	
	var del_btn = Button.new()
	del_btn.text = "删除"
	del_btn.pressed.connect(func():
		modifiers.erase(stat_name)
		row.queue_free()
		_on_field_changed("stat_modifiers", modifiers)
	)
	row.add_child(del_btn)
	
	# 插入到添加按
	var add_button_idx = container.get_child_count() - 1
	container.add_child(row)
	container.move_child(row, add_button_idx)

func _add_special_effects_editor(special_effects: Array):
	var container = VBoxContainer.new()
	
	# 显示当前特殊效果
	for i in range(special_effects.size()):
		var effect = special_effects[i]
		var row = HBoxContainer.new()
		
		var line_edit = LineEdit.new()
		line_edit.text = effect
		line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_edit.text_changed.connect(func(new_text):
			special_effects[i] = new_text
			_on_field_changed("special_effects", special_effects)
		)
		row.add_child(line_edit)
		
		var del_btn = Button.new()
		del_btn.text = "删除"
		del_btn.pressed.connect(func():
			special_effects.remove_at(i)
			_update_property_panel(effects[current_effect_id])
			_on_field_changed("special_effects", special_effects)
		)
		row.add_child(del_btn)
		
		container.add_child(row)
	
	# 添加按钮
	var add_btn = Button.new()
	add_btn.text = "+ 添加特殊效果"
	add_btn.pressed.connect(func():
		special_effects.append("")
		_update_property_panel(effects[current_effect_id])
		_on_field_changed("special_effects", special_effects)
	)
	container.add_child(add_btn)
	
	_property_panel.add_child(container)
	_ui_elements["special_effects"] = container

func _on_field_changed(key: String, value: Variant):
	if current_effect_id.is_empty():
		return
	
	var effect = effects[current_effect_id]
	
	# 处理ID变更
	if key == "id" and value != current_effect_id and not value.is_empty() and not effects.has(value):
		effects.erase(current_effect_id)
		effect.id = value
		effects[value] = effect
		current_effect_id = value
		_update_effect_list()
	else:
		effect[key] = value
	
	_update_status("已更 %s" % key)

# ========== 文件操作 ==========

func _on_save_effects():
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	if not current_dir_path.is_empty():
		_file_dialog.current_dir = current_dir_path
	_file_dialog.dir_selected.connect(_save_to_directory, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _save_to_directory(path: String):
	if effects.is_empty():
		_update_status("没有可保存的效果")
		return
	
	var dir := DirAccess.open(path)
	if dir == null:
		_update_status("无法打开目录")
		return
	
	current_dir_path = path
	for effect_id in effects.keys():
		var effect_data: Dictionary = effects[effect_id]
		if not effect_data.has("id"):
			effect_data["id"] = effect_id
		
		var file_path := "%s/%s.json" % [path, effect_id]
		var json := JSON.stringify(effect_data, "\t")
		var file := FileAccess.open(file_path, FileAccess.WRITE)
		if file:
			file.store_string(json)
			file.close()
		else:
			_update_status("保存失败: %s" % file_path)
	
	effect_saved.emit(current_effect_id)
	_update_status("已保存到目录: %s (%d)" % [path, effects.size()])

func _on_load_effects():
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	if not current_dir_path.is_empty():
		_file_dialog.current_dir = current_dir_path
	_file_dialog.dir_selected.connect(_load_from_directory, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _load_from_directory(path: String):
	var dir := DirAccess.open(path)
	if dir == null:
		_update_status("无法打开目录")
		return
	
	current_dir_path = path
	effects.clear()
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if dir.current_is_dir() or not file_name.ends_with(".json"):
			file_name = dir.get_next()
			continue
		
		var file_path := "%s/%s" % [path, file_name]
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			file_name = dir.get_next()
			continue
		
		var json_text := file.get_as_text()
		file.close()
		
		var json := JSON.new()
		var error := json.parse(json_text)
		if error != OK:
			_update_status("JSON解析错: %s" % file_name)
			file_name = dir.get_next()
			continue
		
		var data := json.data
		if data is Dictionary:
			var effect_id := file_name.trim_suffix(".json")
			if data.has("id") and not str(data.get("id", "")).is_empty():
				effect_id = str(data.get("id", effect_id))
			effects[effect_id] = data
		
		file_name = dir.get_next()
	dir.list_dir_end()
	
	_update_effect_list()
	_clear_property_panel()
	effect_loaded.emit(current_effect_id)
	_update_status("已加载目录: %s (%d)" % [path, effects.size()])

func _update_status(message: String):
	_status_bar.text = message
	print("[EffectEditor] %s" % message)

# 公共方法
func get_current_effect_id() -> String:
	return current_effect_id

func get_effects_count() -> int:
	return effects.size()
