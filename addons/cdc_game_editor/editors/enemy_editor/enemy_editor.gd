@tool
extends Control
## EnemyEditor - 敌人编辑器
## 用于创建和编辑游戏中的敌人数据

signal enemy_saved(enemy_id: String)
signal enemy_loaded(enemy_id: String)

# 敌人类型
const ENEMY_TYPES = {
	0: "普通",
	1: "精英",
	2: "Boss",
	3: "小Boss"
}

# AI类型
const AI_TYPES = {
	0: "主动攻击",
	1: "防守型",
	2: "胆小",
	3: "狂暴",
	4: "潜行",
	5: "辅助"
}

# 数据
var enemies: Dictionary = {}  # enemy_id -> enemy_data
var current_enemy_id: String = ""

# UI节点
@onready var _enemy_list: ItemList
@onready var _property_panel: VBoxContainer
@onready var _toolbar: HBoxContainer
@onready var _file_dialog: FileDialog
@onready var _status_bar: Label

# UI元素引用
var _ui_elements: Dictionary = {}

func _ready():
	_setup_ui()
	_setup_file_dialog()
	_load_enemies_from_data_manager()
	_update_enemy_list()

func _setup_ui():
	anchors_preset = Control.PRESET_FULL_RECT
	
	# 工具栏
	_toolbar = HBoxContainer.new()
	_toolbar.custom_minimum_size = Vector2(0, 45)
	add_child(_toolbar)
	
	var new_btn = Button.new()
	new_btn.text = "新建敌人"
	new_btn.pressed.connect(_on_new_enemy)
	_toolbar.add_child(new_btn)
	
	var delete_btn = Button.new()
	delete_btn.text = "删除"
	delete_btn.pressed.connect(_on_delete_enemy)
	_toolbar.add_child(delete_btn)
	
	_toolbar.add_child(VSeparator.new())
	
	var save_btn = Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(_on_save_enemies)
	_toolbar.add_child(save_btn)
	
	var load_btn = Button.new()
	load_btn.text = "加载"
	load_btn.pressed.connect(_on_load_enemies)
	_toolbar.add_child(load_btn)
	
	# 主分割容器
	var main_split = HSplitContainer.new()
	main_split.position = Vector2(0, 50)
	main_split.size = Vector2(size.x, size.y - 70)
	add_child(main_split)
	
	# 左侧：敌人列表
	var left_panel = _create_enemy_list_panel()
	main_split.add_child(left_panel)
	
	# 右侧：属性面板
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	_property_panel = VBoxContainer.new()
	_property_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_property_panel.add_theme_constant_override("separation", 10)
	scroll.add_child(_property_panel)
	
	main_split.add_child(scroll)
	main_split.split_offset = 250
	
	# 状态栏
	_status_bar = Label.new()
	_status_bar.position = Vector2(0, size.y - 20)
	_status_bar.size = Vector2(size.x, 20)
	_status_bar.text = "就绪"
	add_child(_status_bar)

func _create_enemy_list_panel() -> Control:
	var panel = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)
	
	var title = Label.new()
	title.text = "👹 敌人列表"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)
	
	panel.add_child(HSeparator.new())
	
	# 搜索框
	var search_box = LineEdit.new()
	search_box.placeholder_text = "搜索敌人..."
	search_box.text_changed.connect(_on_search_changed)
	panel.add_child(search_box)
	
	# 敌人列表
	_enemy_list = ItemList.new()
	_enemy_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_enemy_list.item_selected.connect(_on_enemy_selected)
	panel.add_child(_enemy_list)
	
	# 统计
	var stats = Label.new()
	stats.name = "StatsLabel"
	stats.text = "总计: 0个敌人"
	panel.add_child(stats)
	
	return panel

func _setup_file_dialog():
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.json; JSON文件")
	add_child(_file_dialog)

func _load_enemies_from_data_manager():
	var data_manager = get_node_or_null("/root/DataManager")
	if data_manager:
		enemies = data_manager.get_all_enemies()
		print("[EnemyEditor] 从DataManager加载了 %d 个敌人" % enemies.size())

func _update_enemy_list(filter: String = ""):
	_enemy_list.clear()
	_ui_elements.clear()
	
	var sorted_enemies = enemies.keys()
	sorted_enemies.sort()
	
	for enemy_id in sorted_enemies:
		var enemy = enemies[enemy_id]
		var display_text = "%s - %s" % [enemy_id, enemy.get("name", "未命名")]
		
		if filter.is_empty() or display_text.to_lower().contains(filter.to_lower()):
			var idx = _enemy_list.add_item(display_text)
			_enemy_list.set_item_metadata(idx, enemy_id)
			
			# 根据类型设置颜色
			var enemy_type = enemy.get("enemy_type", 0)
			match enemy_type:
				0: _enemy_list.set_item_custom_fg_color(idx, Color.GRAY)
				1: _enemy_list.set_item_custom_fg_color(idx, Color.ORANGE)
				2: _enemy_list.set_item_custom_fg_color(idx, Color.RED)
				3: _enemy_list.set_item_custom_fg_color(idx, Color.PURPLE)
	
	var stats_label = get_node_or_null("StatsLabel")
	if stats_label:
		stats_label.text = "总计: %d个敌人" % enemies.size()

func _on_search_changed(text: String):
	_update_enemy_list(text)

func _on_new_enemy():
	var enemy_id = "enemy_%d" % Time.get_ticks_msec()
	var enemy_data = {
		"id": enemy_id,
		"name": "新敌人",
		"description": "敌人描述",
		"level": 1,
		"portrait_path": "",
		"avatar_path": "",
		"attributes": {
			"strength": 10,
			"perception": 10,
			"endurance": 10,
			"intelligence": 10,
			"charisma": 10,
			"agility": 10,
			"luck": 10
		},
		"combat_stats": {
			"hp": 50,
			"max_hp": 50,
			"damage": 5,
			"defense": 2,
			"speed": 5,
			"crit_chance": 0.05,
			"crit_damage": 1.5,
			"accuracy": 0.9,
			"evasion": 0.05
		},
		"enemy_type": 0,
		"ai_type": 0,
		"aggression_range": 150.0,
		"patrol_radius": 50.0,
		"attack_cooldown": 1.0,
		"special_abilities": [],
		"immunities": [],
		"weaknesses": {},
		"loot_table": [],
		"exp_reward": 10,
		"spawn_weight": 10,
		"min_spawn_level": 1,
		"max_spawn_level": 99,
		"spawn_locations": [],
		"can_flee": false,
		"flee_hp_threshold": 0.2,
		"can_call_reinforcements": false
	}
	
	enemies[enemy_id] = enemy_data
	_update_enemy_list()
	_select_enemy(enemy_id)
	_update_status("创建了新敌人: %s" % enemy_id)

func _on_delete_enemy():
	if current_enemy_id.is_empty():
		return
	
	enemies.erase(current_enemy_id)
	current_enemy_id = ""
	_update_enemy_list()
	_clear_property_panel()
	_update_status("删除了敌人")

func _on_enemy_selected(index: int):
	var enemy_id = _enemy_list.get_item_metadata(index)
	_select_enemy(enemy_id)

func _select_enemy(enemy_id: String):
	current_enemy_id = enemy_id
	var enemy = enemies.get(enemy_id)
	if enemy:
		_update_property_panel(enemy)

func _clear_property_panel():
	for child in _property_panel.get_children():
		child.queue_free()

func _update_property_panel(enemy: Dictionary):
	_clear_property_panel()
	_ui_elements.clear()
	
	# 基础信息
	_add_section_label("📋 基础信息")
	_add_string_field("id", "敌人 ID:", enemy.get("id", ""), false)
	_add_string_field("name", "显示名称:", enemy.get("name", ""))
	_add_string_field("description", "描述:", enemy.get("description", ""), true)
	_add_enum_field("enemy_type", "敌人类型:", ENEMY_TYPES, enemy.get("enemy_type", 0))
	_add_number_field("level", "等级:", enemy.get("level", 1), 1, 100, 1)
	_add_string_field("portrait_path", "立绘路径:", enemy.get("portrait_path", ""), false, "res://assets/images/...")
	
	_add_separator()
	
	# 战斗属性
	_add_section_label("⚔️ 战斗属性")
	var combat_stats = enemy.get("combat_stats", {})
	_add_number_field("hp", "生命值:", combat_stats.get("hp", 50), 1, 9999, 1)
	_add_number_field("damage", "攻击力:", combat_stats.get("damage", 5), 0, 999, 1)
	_add_number_field("defense", "防御力:", combat_stats.get("defense", 2), 0, 999, 1)
	_add_number_field("speed", "速度:", combat_stats.get("speed", 5), 1, 100, 1)
	
	_add_separator()
	
	# AI设置
	_add_section_label("🤖 AI设置")
	_add_enum_field("ai_type", "AI类型:", AI_TYPES, enemy.get("ai_type", 0))
	_add_number_field("aggression_range", "仇恨范围:", enemy.get("aggression_range", 150.0), 0.0, 1000.0, 10.0)
	_add_number_field("attack_cooldown", "攻击冷却:", enemy.get("attack_cooldown", 1.0), 0.1, 10.0, 0.1)
	
	_add_separator()
	
	# 生成设置
	_add_section_label("🎲 生成设置")
	_add_number_field("exp_reward", "经验奖励:", enemy.get("exp_reward", 10), 0, 9999, 5)
	_add_number_field("spawn_weight", "生成权重:", enemy.get("spawn_weight", 10), 1, 100, 1)
	_add_number_field("min_spawn_level", "最小生成等级:", enemy.get("min_spawn_level", 1), 1, 99, 1)
	_add_number_field("max_spawn_level", "最大生成等级:", enemy.get("max_spawn_level", 99), 1, 99, 1)

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
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.text = value
	line_edit.placeholder_text = placeholder
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

func _add_enum_field(key: String, label_text: String, options: Dictionary, value: int):
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

func _on_field_changed(key: String, value: Variant):
	if current_enemy_id.is_empty():
		return
	
	var enemy = enemies[current_enemy_id]
	
	# 处理特殊字段
	if key == "id" and value != current_enemy_id and not value.is_empty() and not enemies.has(value):
		enemies.erase(current_enemy_id)
		enemy.id = value
		enemies[value] = enemy
		current_enemy_id = value
		_update_enemy_list()
	elif key in ["hp", "damage", "defense", "speed"]:
		# 战斗属性嵌套
		if not enemy.has("combat_stats"):
			enemy.combat_stats = {}
		enemy.combat_stats[key] = value
	else:
		enemy[key] = value
	
	_update_status("已更新: %s" % key)

# ========== 文件操作 ==========

func _on_save_enemies():
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "enemies.json"
	_file_dialog.file_selected.connect(_save_to_file, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _save_to_file(path: String):
	var data = {}
	for enemy_id in enemies:
		data[enemy_id] = enemies[enemy_id]
	
	var json = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		enemy_saved.emit(current_enemy_id)
		_update_status("✓ 已保存: %s (%d个敌人)" % [path, enemies.size()])
	else:
		_update_status("❌ 保存失败")

func _on_load_enemies():
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.file_selected.connect(_load_from_file, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _load_from_file(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		_update_status("❌ 无法打开文件")
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		_update_status("❌ JSON解析错误")
		return
	
	var data = json.data
	enemies.clear()
	
	for enemy_id in data:
		enemies[enemy_id] = data[enemy_id]
	
	_update_enemy_list()
	_clear_property_panel()
	enemy_loaded.emit(current_enemy_id)
	_update_status("✓ 已加载: %s (%d个敌人)" % [path, enemies.size()])

func _update_status(message: String):
	_status_bar.text = message
	print("[EnemyEditor] %s" % message)
