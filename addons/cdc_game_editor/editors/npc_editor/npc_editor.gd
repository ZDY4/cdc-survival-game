@tool
extends Control
## NPC编辑器
## 用于创建和编辑NPC数据

signal npc_saved(npc_id: String)
signal npc_loaded(npc_id: String)

# NPC类型选项
const NPC_TYPES = {
	0: "友好",
	1: "中立",
	2: "敌对",
	3: "商人",
	4: "任务发布者",
	5: "可招募"
}

# 数据
var npcs: Dictionary = {}  # npc_id -> NPCData
var current_npc_id: String = ""
var current_file_path: String = ""

# 编辑器插件引用
var editor_plugin: EditorPlugin = null

# UI引用
@onready var npc_list: ItemList
@onready var property_panel: Control
@onready var toolbar: HBoxContainer
@onready var file_dialog: FileDialog
@onready var status_bar: Label

func _ready():
	_setup_ui()
	_setup_file_dialog()
	_load_npcs_from_data_manager()
	_update_npc_list()

func _setup_ui():
	anchors_preset = Control.PRESET_FULL_RECT
	
	# 工具栏
	toolbar = HBoxContainer.new()
	toolbar.custom_minimum_size = Vector2(0, 45)
	add_child(toolbar)
	
	var new_btn = Button.new()
	new_btn.text = "新建NPC"
	new_btn.pressed.connect(_on_new_npc)
	toolbar.add_child(new_btn)
	
	var delete_btn = Button.new()
	delete_btn.text = "删除"
	delete_btn.pressed.connect(_on_delete_npc)
	toolbar.add_child(delete_btn)
	
	toolbar.add_child(VSeparator.new())
	
	var save_btn = Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(_on_save_npcs)
	toolbar.add_child(save_btn)
	
	var load_btn = Button.new()
	load_btn.text = "加载"
	load_btn.pressed.connect(_on_load_npcs)
	toolbar.add_child(load_btn)
	
	toolbar.add_child(VSeparator.new())
	
	var export_btn = Button.new()
	export_btn.text = "导出JSON"
	export_btn.pressed.connect(_on_export_json)
	toolbar.add_child(export_btn)
	
	# 主分割容器
	var main_split = HSplitContainer.new()
	main_split.position = Vector2(0, 50)
	main_split.size = Vector2(size.x, size.y - 70)
	add_child(main_split)
	
	# 左侧：NPC列表
	var left_panel = _create_npc_list_panel()
	main_split.add_child(left_panel)
	
	# 右侧：属性面板
	property_panel = preload("res://addons/cdc_game_editor/utils/property_panel.gd").new()
	property_panel.custom_minimum_size = Vector2(400, 0)
	property_panel.panel_title = "NPC属性"
	property_panel.property_changed.connect(_on_property_changed)
	main_split.add_child(property_panel)
	
	main_split.split_offset = 250
	
	# 状态栏
	status_bar = Label.new()
	status_bar.position = Vector2(0, size.y - 20)
	status_bar.size = Vector2(size.x, 20)
	status_bar.text = "就绪"
	add_child(status_bar)

func _create_npc_list_panel() -> Control:
	var panel = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)
	
	var title = Label.new()
	title.text = "🧑 NPC列表"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)
	
	panel.add_child(HSeparator.new())
	
	# 搜索框
	var search_box = LineEdit.new()
	search_box.placeholder_text = "搜索NPC..."
	search_box.text_changed.connect(_on_search_changed)
	panel.add_child(search_box)
	
	# NPC列表
	npc_list = ItemList.new()
	npc_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	npc_list.item_selected.connect(_on_npc_selected)
	panel.add_child(npc_list)
	
	# 统计
	var stats = Label.new()
	stats.name = "StatsLabel"
	stats.text = "总计: 0个NPC"
	panel.add_child(stats)
	
	return panel

func _setup_file_dialog():
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.json; JSON文件")
	add_child(file_dialog)

func _load_npcs_from_data_manager():
	var data_manager = get_node_or_null("/root/DataManager")
	if data_manager:
		var data = data_manager.get_all_npcs()
		if not data.is_empty():
			# 转换为NPCData对象
			for npc_id in data:
				var npc_data = NPCData.new()
				npc_data.deserialize(data[npc_id])
				npcs[npc_id] = npc_data
			print("[NPCEditor] 从DataManager加载了 %d 个NPC" % npcs.size())

func _update_npc_list(filter: String = ""):
	npc_list.clear()
	
	var sorted_npcs = npcs.keys()
	sorted_npcs.sort()
	
	for npc_id in sorted_npcs:
		var npc = npcs[npc_id]
		var display_text = "%s - %s (%s)" % [npc_id, npc.name, NPC_TYPES.get(npc.npc_type, "未知")]
		
		if filter.is_empty() or display_text.to_lower().contains(filter.to_lower()):
			var idx = npc_list.add_item(display_text)
			npc_list.set_item_metadata(idx, npc_id)
		
			# 根据类型设置颜色
			match npc.npc_type:
				NPCData.Type.TRADER:
					npc_list.set_item_custom_fg_color(idx, Color.GOLD)
				NPCData.Type.HOSTILE:
					npc_list.set_item_custom_fg_color(idx, Color.RED)
				NPCData.Type.QUEST_GIVER:
					npc_list.set_item_custom_fg_color(idx, Color.CYAN)
	
	var stats_label = get_node_or_null("StatsLabel")
	if stats_label:
		stats_label.text = "总计: %d个NPC" % npcs.size()

func _on_search_changed(text: String):
	_update_npc_list(text)

func _on_new_npc():
	var npc_id = "npc_%d" % Time.get_ticks_msec()
	var npc_data = NPCData.new()
	npc_data.id = npc_id
	npc_data.name = "新NPC"
	npc_data.description = "NPC描述"
	npc_data.npc_type = NPCData.Type.FRIENDLY
	npc_data.default_location = "safehouse"
	npc_data.current_location = "safehouse"
	
	npcs[npc_id] = npc_data
	_update_npc_list()
	_select_npc(npc_id)
	_update_status("创建了新NPC: %s" % npc_id)

func _on_delete_npc():
	if current_npc_id.is_empty():
		return
	
	npcs.erase(current_npc_id)
	current_npc_id = ""
	_update_npc_list()
	property_panel.clear()
	_update_status("删除了NPC")

func _on_npc_selected(index: int):
	var npc_id = npc_list.get_item_metadata(index)
	_select_npc(npc_id)

func _select_npc(npc_id: String):
	current_npc_id = npc_id
	var npc = npcs.get(npc_id)
	if npc:
		_update_property_panel(npc)

func _update_property_panel(npc: NPCData):
	property_panel.clear()
	
	if not npc:
		return
	
	# 基础信息
	property_panel.add_string_property("id", "NPC ID:", npc.id, false, "唯一标识符")
	property_panel.add_string_property("name", "名称:", npc.name, false, "显示名称")
	property_panel.add_string_property("title", "称号:", npc.title, false, "如：废土商人")
	property_panel.add_string_property("description", "描述:", npc.description, true, "详细描述...")
	
	property_panel.add_separator()
	
	// 类型
	var type_dict = {}
	for key in NPC_TYPES:
		type_dict[str(key)] = NPC_TYPES[key]
	property_panel.add_enum_property("npc_type", "NPC类型:", type_dict, str(npc.npc_type))
	
	// 等级
	property_panel.add_number_property("level", "等级:", npc.level, 1, 100, 1, false)
	
	property_panel.add_separator()
	
	// 属性
	property_panel.add_section_label("📊 属性")
	property_panel.add_number_property("attr_strength", "力量:", npc.attributes.get("strength", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_perception", "感知:", npc.attributes.get("perception", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_endurance", "体质:", npc.attributes.get("endurance", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_charisma", "魅力:", npc.attributes.get("charisma", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_intelligence", "智力:", npc.attributes.get("intelligence", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_agility", "敏捷:", npc.attributes.get("agility", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_luck", "幸运:", npc.attributes.get("luck", 10), 1, 20, 1, false)
	
	property_panel.add_separator()
	
	// 情绪
	property_panel.add_section_label("😊 初始情绪")
	property_panel.add_number_property("mood_friendliness", "友好度:", npc.mood.friendliness, 0, 100, 5, false)
	property_panel.add_number_property("mood_trust", "信任度:", npc.mood.trust, 0, 100, 5, false)
	property_panel.add_number_property("mood_fear", "恐惧度:", npc.mood.fear, 0, 100, 5, false)
	property_panel.add_number_property("mood_anger", "愤怒度:", npc.mood.anger, 0, 100, 5, false)
	
	property_panel.add_separator()
	
	// 能力
	property_panel.add_section_label("⚡ 能力")
	# 使用自定义控件显示布尔值
	property_panel.add_custom_control(_create_bool_checkbox("can_trade", "可以交易", npc.can_trade))
	property_panel.add_custom_control(_create_bool_checkbox("can_recruit", "可以招募", npc.can_recruit))
	property_panel.add_custom_control(_create_bool_checkbox("can_give_quest", "可以发布任务", npc.can_give_quest))
	property_panel.add_custom_control(_create_bool_checkbox("can_heal", "可以治疗", npc.can_heal))
	
	property_panel.add_separator()
	
	// 位置
	property_panel.add_string_property("default_location", "默认位置:", npc.default_location, false, "如：safehouse")
	
	property_panel.add_separator()
	
	// 外观
	property_panel.add_section_label("🎨 外观")
	property_panel.add_string_property("portrait_path", "默认立绘:", npc.portrait_path, false, "res://assets/portraits/...")
	
	// 表情立绘
	property_panel.add_section_label("😊 表情立绘（可选）")
	property_panel.add_string_property("expr_normal", "正常:", npc.expression_paths.get("normal", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_happy", "开心:", npc.expression_paths.get("happy", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_angry", "愤怒:", npc.expression_paths.get("angry", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_sad", "悲伤:", npc.expression_paths.get("sad", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_fear", "恐惧:", npc.expression_paths.get("fear", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_surprised", "惊讶:", npc.expression_paths.get("surprised", ""), false, "res://assets/portraits/...")

func _create_bool_checkbox(property_name: String, label: String, value: bool) -> Control:
	var hbox = HBoxContainer.new()
	
	var lbl = Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)
	
	var checkbox = CheckBox.new()
	checkbox.button_pressed = value
	checkbox.toggled.connect(func(v): _on_bool_property_changed(property_name, v))
	hbox.add_child(checkbox)
	
	return hbox

func _on_property_changed(property_name: String, new_value: Variant, old_value: Variant):
	if current_npc_id.is_empty():
		return
	
	var npc = npcs[current_npc_id]
	if not npc:
		return
	
	# 处理不同类型的属性
	match property_name:
		"id":
			# ID变更需要特殊处理
			if new_value != current_npc_id and not new_value.is_empty() and not npcs.has(new_value):
				npcs.erase(current_npc_id)
				npc.id = new_value
				npcs[new_value] = npc
				current_npc_id = new_value
				_update_npc_list()
		
		"name":
			npc.name = new_value
		"title":
			npc.title = new_value
		"description":
			npc.description = new_value
		"npc_type":
			npc.npc_type = int(new_value)
		"level":
			npc.level = int(new_value)
		"default_location":
			npc.default_location = new_value
			npc.current_location = new_value
		"portrait_path":
			npc.portrait_path = new_value
		
		// 表情立绘
		"expr_normal":
			npc.set_expression_path("normal", new_value)
		"expr_happy":
			npc.set_expression_path("happy", new_value)
		"expr_angry":
			npc.set_expression_path("angry", new_value)
		"expr_sad":
			npc.set_expression_path("sad", new_value)
		"expr_fear":
			npc.set_expression_path("fear", new_value)
		"expr_surprised":
			npc.set_expression_path("surprised", new_value)
		
		# 属性
		"attr_strength":
			npc.attributes.strength = int(new_value)
		"attr_perception":
			npc.attributes.perception = int(new_value)
		"attr_endurance":
			npc.attributes.endurance = int(new_value)
		"attr_charisma":
			npc.attributes.charisma = int(new_value)
		"attr_intelligence":
			npc.attributes.intelligence = int(new_value)
		"attr_agility":
			npc.attributes.agility = int(new_value)
		"attr_luck":
			npc.attributes.luck = int(new_value)
		
		// 情绪
		"mood_friendliness":
			npc.mood.friendliness = int(new_value)
		"mood_trust":
			npc.mood.trust = int(new_value)
		"mood_fear":
			npc.mood.fear = int(new_value)
		"mood_anger":
			npc.mood.anger = int(new_value)

func _on_bool_property_changed(property_name: String, value: bool):
	if current_npc_id.is_empty():
		return
	
	var npc = npcs[current_npc_id]
	match property_name:
		"can_trade":
			npc.can_trade = value
		"can_recruit":
			npc.can_recruit = value
		"can_give_quest":
			npc.can_give_quest = value
		"can_heal":
			npc.can_heal = value

func _on_save_npcs():
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = "npcs.json"
	file_dialog.file_selected.connect(_save_to_file, CONNECT_ONE_SHOT)
	file_dialog.popup_centered(Vector2(800, 600))

func _save_to_file(path: String):
	var data = {}
	for npc_id in npcs:
		data[npc_id] = npcs[npc_id].serialize()
	
	var json = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		npc_saved.emit(current_npc_id)
		_update_status("✓ 已保存: %s (%d个NPC)" % [path, npcs.size()])
	else:
		_update_status("❌ 保存失败")

func _on_load_npcs():
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.file_selected.connect(_load_from_file, CONNECT_ONE_SHOT)
	file_dialog.popup_centered(Vector2(800, 600))

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
	npcs.clear()
	
	for npc_id in data:
		var npc_data = NPCData.new()
		npc_data.deserialize(data[npc_id])
		npcs[npc_id] = npc_data
	
	_update_npc_list()
	property_panel.clear()
	npc_loaded.emit(current_npc_id)
	_update_status("✓ 已加载: %s (%d个NPC)" % [path, npcs.size()])

func _on_export_json():
	_on_save_npcs()

func _update_status(message: String):
	status_bar.text = message
	print("[NPCEditor] %s" % message)

# 公共方法
func get_current_npc_id() -> String:
	return current_npc_id

func get_npcs_count() -> int:
	return npcs.size()

func has_unsaved_changes() -> bool:
	return npcs.size() > 0
