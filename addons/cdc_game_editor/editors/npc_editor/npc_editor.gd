@tool
extends Control
## NPC编辑器
## 用于创建和编辑NPC数据

signal npc_saved(npc_id: String)
signal npc_loaded(npc_id: String)

# NPC类型选项
const NPC_TYPES = {
	0: "Friendly",
	1: "Neutral",
	2: "Hostile",
	3: "Trader",
	4: "Quest Giver",
	5: "Recruitable"
}

const JSON_VALIDATOR = preload("res://addons/cdc_game_editor/utils/json_validator.gd")

# 数据
var npcs: Dictionary = {}  # npc_id -> Dictionary
var current_npc_id: String = ""
var current_file_path: String = ""

# 编辑器插件引
var editor_plugin: EditorPlugin = null

# UI引用
var npc_list: ItemList
var property_panel: Control
var toolbar: HBoxContainer
var file_dialog: FileDialog
var status_bar: Label
var _stats_label: Label

func _ready():
	_setup_ui()
	_setup_file_dialog()
	_load_npcs_from_project_data()
	_update_npc_list()

func _setup_ui():
	anchors_preset = Control.PRESET_FULL_RECT
	
	# 工具栏
	toolbar = HBoxContainer.new()
	toolbar.custom_minimum_size = Vector2(0, 45)
	toolbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toolbar.offset_top = 0
	toolbar.offset_bottom = 45
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
	
	# 主分割
	var main_split = HSplitContainer.new()
	main_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_split.offset_top = 50
	main_split.offset_bottom = -20
	add_child(main_split)
	
	# 左侧：NPC列表
	var left_panel = _create_npc_list_panel()
	main_split.add_child(left_panel)
	
	# 右侧：属性面板
	property_panel = preload("res://addons/cdc_game_editor/utils/property_panel.gd").new()
	property_panel.custom_minimum_size = Vector2(400, 0)
	property_panel.panel_title = "NPC Properties"
	property_panel.property_changed.connect(_on_property_changed)
	main_split.add_child(property_panel)
	
	main_split.split_offset = 250
	
	# 状态栏
	status_bar = Label.new()
	status_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_bar.offset_top = -20
	status_bar.offset_bottom = 0
	status_bar.offset_left = 0
	status_bar.offset_right = 0
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
	
	# 搜索
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
	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	_stats_label.text = "总计: 0个NPC"
	panel.add_child(_stats_label)
	
	return panel

func _setup_file_dialog():
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.json; JSON文件")
	add_child(file_dialog)

func _load_npcs_from_project_data():
	var data_manager = get_node_or_null("/root/DataManager")
	if data_manager and data_manager.has_method("get_all_npcs"):
		var data: Variant = data_manager.get_all_npcs()
		if data is Dictionary and not data.is_empty():
			_apply_npc_dictionary(data)
			print("[NPCEditor] Loaded %d NPCs from DataManager" % npcs.size())
			return
		elif not (data is Dictionary):
			push_warning("[NPCEditor] Invalid NPC data from DataManager: expected Dictionary")

	var file_data: Dictionary = _load_json_dictionary([
		"res://data/json/npcs.json",
		"res://data/npcs.json"
	])
	if not file_data.is_empty():
		_apply_npc_dictionary(file_data)
		current_file_path = "res://data/json/npcs.json" if FileAccess.file_exists("res://data/json/npcs.json") else "res://data/npcs.json"
		print("[NPCEditor] Loaded %d NPCs from %s" % [npcs.size(), current_file_path])

func _load_json_dictionary(paths: Array[String]) -> Dictionary:
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var validation := JSON_VALIDATOR.validate_file(path, {
			"root_type": JSON_VALIDATOR.TYPE_DICTIONARY,
			"wrapper_key": "npcs",
			"wrapper_type": JSON_VALIDATOR.TYPE_DICTIONARY,
			"entry_type": JSON_VALIDATOR.TYPE_DICTIONARY,
			"entry_label": "npc"
		})
		if bool(validation.get("ok", false)):
			var loaded_npcs: Variant = validation.get("data", {})
			if loaded_npcs is Dictionary:
				return loaded_npcs
			push_warning("[JSON] %s | Invalid validator result: data must be Dictionary" % path)
			continue
		push_warning(str(validation.get("message", "[JSON] Unknown validation error")))
	return {}

func _apply_npc_dictionary(data: Dictionary) -> void:
	npcs.clear()
	var npc_data_class: Script = load("res://modules/npc/npc_data.gd")
	for npc_id in data.keys():
		var raw_npc: Variant = data[npc_id]
		if raw_npc is Object:
			if raw_npc.has_method("serialize"):
				npcs[npc_id] = raw_npc.serialize()
			else:
				push_warning("[NPCEditor] NPC '%s' is Object without serialize(); skipping entry" % npc_id)
			continue
		if raw_npc is Dictionary and npc_data_class:
			var npc_data: Variant = npc_data_class.new()
			if npc_data is Object and npc_data.has_method("deserialize"):
				npc_data.deserialize(raw_npc)
				if npc_data.has_method("serialize"):
					npcs[npc_id] = npc_data.serialize()
				else:
					npcs[npc_id] = raw_npc.duplicate(true)
				continue
		if raw_npc is Dictionary:
			npcs[npc_id] = raw_npc.duplicate(true)

func _update_npc_list(filter: String = ""):
	npc_list.clear()
	
	var sorted_npcs = npcs.keys()
	sorted_npcs.sort()
	
	for npc_id in sorted_npcs:
		var npc = npcs[npc_id]
		var npc_type = int(npc.get("npc_type", 0))
		var npc_name = str(npc.get("name", npc_id))
		var display_text = "%s - %s (%s)" % [npc_id, npc_name, NPC_TYPES.get(npc_type, "未知")]
		
		if filter.is_empty() or display_text.to_lower().contains(filter.to_lower()):
			var idx = npc_list.add_item(display_text)
			npc_list.set_item_metadata(idx, npc_id)
		
			# 根据类型设置颜色 (3=TRADER, 2=HOSTILE, 4=QUEST_GIVER)
			match npc_type:
				3:  # TRADER
					npc_list.set_item_custom_fg_color(idx, Color.GOLD)
				2:  # HOSTILE
					npc_list.set_item_custom_fg_color(idx, Color.RED)
				4:  # QUEST_GIVER
					npc_list.set_item_custom_fg_color(idx, Color.CYAN)
	
	if _stats_label:
		_stats_label.text = "总计: %d个NPC" % npcs.size()

func get_data() -> Dictionary:
	# 转换
	var data = {}
	for npc_id in npcs:
		var npc: Variant = npcs[npc_id]
		if npc is Object and npc.has_method("serialize"):
			data[npc_id] = npc.serialize()
		elif npc is Dictionary:
			data[npc_id] = npc.duplicate(true)
		else:
			data[npc_id] = npc
	return data

func _on_search_changed(text: String):
	_update_npc_list(text)

func _on_new_npc():
	var npc_id = "npc_%d" % Time.get_ticks_msec()
	var NPCDataClass = load("res://modules/npc/npc_data.gd")
	if not NPCDataClass:
		_update_status("Failed to load NPCData class")
		return
	
	var npc_data = NPCDataClass.new()
	npc_data.id = npc_id
	npc_data.name = "新NPC"
	npc_data.description = "NPC描述"
	npc_data.npc_type = 0  # Type.FRIENDLY = 0
	npc_data.default_location = "safehouse"
	npc_data.current_location = "safehouse"

	if npc_data.has_method("serialize"):
		npcs[npc_id] = npc_data.serialize()
	else:
		npcs[npc_id] = {
			"id": npc_id,
			"name": "新NPC",
			"description": "NPC描述",
			"npc_type": 0,
			"default_location": "safehouse",
			"current_location": "safehouse"
		}
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

func _update_property_panel(npc):
	property_panel.clear()
	
	if not npc:
		return
	
	# 基础信息 - 使用 get() 安全访问
	property_panel.add_string_property("id", "NPC ID:", npc.get("id", ""), false, "Unique identifier")
	property_panel.add_string_property("name", "名称:", npc.get("name", ""), false, "显示名称")
	property_panel.add_string_property("title", "称号:", npc.get("title", ""), false, "如：废土商人")
	property_panel.add_string_property("description", "描述:", npc.get("description", ""), true, "详细描述...")
	
	property_panel.add_separator()
	
	# 类型
	var type_dict = {}
	for key in NPC_TYPES:
		type_dict[str(key)] = NPC_TYPES[key]
	property_panel.add_enum_property("npc_type", "NPC类型:", type_dict, str(npc.get("npc_type", 0)))
	
	# 等级
	property_panel.add_number_property("level", "等级:", npc.get("level", 1), 1, 100, 1, false)
	
	property_panel.add_separator()
	
	# 属
	property_panel.add_section_label("Attributes")
	var attributes = npc.get("attributes", {})
	property_panel.add_number_property("attr_strength", "力量:", attributes.get("strength", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_perception", "感知:", attributes.get("perception", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_endurance", "体质:", attributes.get("endurance", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_charisma", "魅力:", attributes.get("charisma", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_intelligence", "智力:", attributes.get("intelligence", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_agility", "敏捷:", attributes.get("agility", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_luck", "幸运:", attributes.get("luck", 10), 1, 20, 1, false)
	
	property_panel.add_separator()
	
	# 情绪
	property_panel.add_section_label("😊 初始情绪")
	var mood = npc.get("mood", {})
	property_panel.add_number_property("mood_friendliness", "友好", mood.get("friendliness", 0), 0, 100, 5, false)
	property_panel.add_number_property("mood_trust", "信任", mood.get("trust", 0), 0, 100, 5, false)
	property_panel.add_number_property("mood_fear", "恐惧", mood.get("fear", 0), 0, 100, 5, false)
	property_panel.add_number_property("mood_anger", "愤怒度:", mood.get("anger", 0), 0, 100, 5, false)
	
	property_panel.add_separator()
	
	# 能力
	property_panel.add_section_label("能力")
	# 使用义控件显示布尔
	property_panel.add_custom_control(_create_bool_checkbox("can_trade", "可以交易", npc.get("can_trade", false)))
	property_panel.add_custom_control(_create_bool_checkbox("can_recruit", "可以招募", npc.get("can_recruit", false)))
	property_panel.add_custom_control(_create_bool_checkbox("can_give_quest", "可以发布任务", npc.get("can_give_quest", false)))
	property_panel.add_custom_control(_create_bool_checkbox("can_heal", "可以治疗", npc.get("can_heal", false)))
	
	property_panel.add_separator()
	
	# 位置
	property_panel.add_string_property("default_location", "默认位置:", npc.get("default_location", "safehouse"), false, "如：safehouse")
	
	property_panel.add_separator()
	
	# 外观
	property_panel.add_section_label("🎨 外观")
	property_panel.add_string_property("portrait_path", "默认立绘:", npc.get("portrait_path", ""), false, "res://assets/portraits/...")
	
	property_panel.add_separator()
	
	# 表情立绘
	property_panel.add_section_label("😊 表情立绘（可选）")
	var expression_paths = npc.get("expression_paths", {})
	property_panel.add_string_property("expr_normal", "正常:", expression_paths.get("normal", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_happy", "??:", expression_paths.get("happy", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_angry", "??:", expression_paths.get("angry", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_sad", "悲伤:", expression_paths.get("sad", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_fear", "恐惧:", expression_paths.get("fear", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_surprised", "惊讶:", expression_paths.get("surprised", ""), false, "res://assets/portraits/...")

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
	
	var npc: Variant = npcs[current_npc_id]
	if not npc:
		return
	
	var attributes: Dictionary = npc.get("attributes", {})
	var mood: Dictionary = npc.get("mood", {})
	var expression_paths: Dictionary = npc.get("expression_paths", {})
	
	match property_name:
		"id":
			if new_value != current_npc_id and not new_value.is_empty() and not npcs.has(new_value):
				npcs.erase(current_npc_id)
				npc.set("id", new_value)
				npcs[new_value] = npc
				current_npc_id = new_value
				_update_npc_list()
		"name":
			npc.set("name", new_value)
		"title":
			npc.set("title", new_value)
		"description":
			npc.set("description", new_value)
		"npc_type":
			npc.set("npc_type", int(new_value))
		"level":
			npc.set("level", int(new_value))
		"default_location":
			npc.set("default_location", new_value)
			npc.set("current_location", new_value)
		"portrait_path":
			npc.set("portrait_path", new_value)
		"expr_normal":
			expression_paths["normal"] = new_value
		"expr_happy":
			expression_paths["happy"] = new_value
		"expr_angry":
			expression_paths["angry"] = new_value
		"expr_sad":
			expression_paths["sad"] = new_value
		"expr_fear":
			expression_paths["fear"] = new_value
		"expr_surprised":
			expression_paths["surprised"] = new_value
		"attr_strength":
			attributes["strength"] = int(new_value)
		"attr_perception":
			attributes["perception"] = int(new_value)
		"attr_endurance":
			attributes["endurance"] = int(new_value)
		"attr_charisma":
			attributes["charisma"] = int(new_value)
		"attr_intelligence":
			attributes["intelligence"] = int(new_value)
		"attr_agility":
			attributes["agility"] = int(new_value)
		"attr_luck":
			attributes["luck"] = int(new_value)
		"mood_friendliness":
			mood["friendliness"] = int(new_value)
		"mood_trust":
			mood["trust"] = int(new_value)
		"mood_fear":
			mood["fear"] = int(new_value)
		"mood_anger":
			mood["anger"] = int(new_value)
	
	npc.set("attributes", attributes)
	npc.set("mood", mood)
	npc.set("expression_paths", expression_paths)

func _on_bool_property_changed(property_name: String, value: bool):
	if current_npc_id.is_empty():
		return
	
	var npc: Variant = npcs[current_npc_id]
	if not npc:
		return
	
	match property_name:
		"can_trade":
			npc.set("can_trade", value)
		"can_recruit":
			npc.set("can_recruit", value)
		"can_give_quest":
			npc.set("can_give_quest", value)
		"can_heal":
			npc.set("can_heal", value)

func _on_save_npcs():
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = "npcs.json"
	file_dialog.file_selected.connect(_save_to_file, CONNECT_ONE_SHOT)
	file_dialog.popup_centered(Vector2(800, 600))

func _save_to_file(path: String):
	var data = {}
	for npc_id in npcs:
		var npc = npcs[npc_id]
		if npc is Object and npc.has_method("serialize"):
			data[npc_id] = npc.serialize()
		elif npc is Dictionary:
			data[npc_id] = npc.duplicate(true)
		else:
			data[npc_id] = npc
	
	var json = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		npc_saved.emit(current_npc_id)
		_update_status("已保 %s (%d个NPC)" % [path, npcs.size()])
	else:
		_update_status("保存失败")

func _on_load_npcs():
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.file_selected.connect(_load_from_file, CONNECT_ONE_SHOT)
	file_dialog.popup_centered(Vector2(800, 600))

func _load_from_file(path: String):
	var validation := JSON_VALIDATOR.validate_file(path, {
		"root_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"wrapper_key": "npcs",
		"wrapper_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"entry_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"entry_label": "npc"
	})
	if not bool(validation.get("ok", false)):
		_update_status(str(validation.get("message", "[JSON] Unknown validation error")))
		return

	var loaded_npcs: Variant = validation.get("data", {})
	if not (loaded_npcs is Dictionary):
		_update_status("[JSON] %s | Invalid validator result: data must be Dictionary" % path)
		return
	var data: Dictionary = loaded_npcs

	_apply_npc_dictionary(data)
	current_file_path = path
	current_npc_id = ""
	
	_update_npc_list()
	property_panel.clear()
	npc_loaded.emit(current_npc_id)
	_update_status("Loaded: %s (%d NPCs)" % [path, npcs.size()])

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



