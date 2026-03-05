@tool
extends Control
## RecipeEditor - 配方编辑器
## 用于创建和编辑游戏中的制作配方

signal recipe_saved(recipe_id: String)
signal recipe_loaded(recipe_id: String)

# 配方类别
const RECIPE_CATEGORIES = {
	"weapon": "武器",
	"armor": "护甲",
	"accessory": "饰品",
	"medical": "医疗",
	"food": "食物",
	"ammo": "弹药",
	"tool": "工具",
	"material": "材料加工",
	"misc": "杂项"
}

# 工作台类型
const STATION_TYPES = {
	"none": "无（手持制作）",
	"workbench": "工作台",
	"forge": "锻造台",
	"medical_station": "医疗台",
	"cooking_station": "烹饪台",
	"chemistry_lab": "化学实验室"
}

# 数据
var recipes: Dictionary = {}  # recipe_id -> recipe_data
var current_recipe_id: String = ""
var editor_plugin: EditorPlugin = null

# UI节点
@onready var _recipe_list: ItemList
@onready var _property_panel: VBoxContainer
@onready var _toolbar: HBoxContainer
@onready var _file_dialog: FileDialog
@onready var _status_bar: Label
@onready var _category_filter: OptionButton
@onready var _search_box: LineEdit
@onready var _stats_label: Label

# UI元素引用
var _ui_elements: Dictionary = {}
var _materials_container: VBoxContainer
var _selected_category_filter: String = ""
var _search_filter_text: String = ""

func _ready():
	_setup_ui()
	_setup_file_dialog()
	_load_recipes_from_data_manager()
	_update_recipe_list()

func _setup_ui():
	anchors_preset = Control.PRESET_FULL_RECT
	
	# 工具栏
	_toolbar = HBoxContainer.new()
	_toolbar.custom_minimum_size = Vector2(0, 45)
	add_child(_toolbar)
	
	var new_btn = Button.new()
	new_btn.text = "新建配方"
	new_btn.pressed.connect(_on_new_recipe)
	_toolbar.add_child(new_btn)
	
	var delete_btn = Button.new()
	delete_btn.text = "删除"
	delete_btn.pressed.connect(_on_delete_recipe)
	_toolbar.add_child(delete_btn)
	
	_toolbar.add_child(VSeparator.new())
	
	var save_btn = Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(_on_save_recipes)
	_toolbar.add_child(save_btn)
	
	var load_btn = Button.new()
	load_btn.text = "加载"
	load_btn.pressed.connect(_on_load_recipes)
	_toolbar.add_child(load_btn)
	
	_toolbar.add_child(VSeparator.new())
	
	var duplicate_btn = Button.new()
	duplicate_btn.text = "复制"
	duplicate_btn.pressed.connect(_on_duplicate_recipe)
	_toolbar.add_child(duplicate_btn)
	
	# 主分割容器
	var main_split = HSplitContainer.new()
	main_split.position = Vector2(0, 50)
	main_split.size = Vector2(size.x, size.y - 70)
	add_child(main_split)
	
	# 左侧：配方列表
	var left_panel = _create_recipe_list_panel()
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

func _create_recipe_list_panel() -> Control:
	var panel = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	
	var title = Label.new()
	title.text = "📋 配方列表"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)
	
	panel.add_child(HSeparator.new())
	
	# 类别过滤
	var filter_hbox = HBoxContainer.new()
	var filter_label = Label.new()
	filter_label.text = "类别:"
	filter_hbox.add_child(filter_label)
	
	_category_filter = OptionButton.new()
	_category_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_filter.add_item("全部")
	_category_filter.set_item_metadata(0, "")
	var idx = 1
	for cat_key in RECIPE_CATEGORIES.keys():
		_category_filter.add_item(RECIPE_CATEGORIES[cat_key])
		_category_filter.set_item_metadata(idx, cat_key)
		idx += 1
	_category_filter.item_selected.connect(_on_category_filter_changed)
	filter_hbox.add_child(_category_filter)
	panel.add_child(filter_hbox)
	
	# 搜索框
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "搜索配方..."
	_search_box.text_changed.connect(_on_search_changed)
	panel.add_child(_search_box)
	
	# 配方列表
	_recipe_list = ItemList.new()
	_recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recipe_list.item_selected.connect(_on_recipe_selected)
	panel.add_child(_recipe_list)
	
	# 统计
	_stats_label = Label.new()
	_stats_label.text = "Total: 0 / Filtered: 0"
	panel.add_child(_stats_label)
	
	return panel

func _setup_file_dialog():
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.json; JSON文件")
	add_child(_file_dialog)

func _load_recipes_from_data_manager():
	var data_manager = get_node_or_null("/root/DataManager")
	if data_manager and data_manager.has_method("get_all_recipes"):
		recipes = data_manager.get_all_recipes()
		print("[RecipeEditor] 从DataManager加载了 %d 个配方" % recipes.size())

func _update_recipe_list(category_filter: String = "", search_filter: String = ""):
	_recipe_list.clear()
	_ui_elements.clear()
	
	var sorted_recipes = recipes.keys()
	sorted_recipes.sort()
	var filtered_count := 0
	
	for recipe_id in sorted_recipes:
		var recipe = recipes[recipe_id]
		var category = recipe.get("category", "misc")
		var output_name = _get_output_item_name(recipe)
		var display_text = "%s - %s → %s" % [recipe_id, recipe.get("name", "未命名"), output_name]
		
		# 类别过滤
		if not category_filter.is_empty() and category != category_filter:
			continue
		
		# 搜索过滤
		if not search_filter.is_empty():
			var search_lower = search_filter.to_lower()
			if not recipe_id.to_lower().contains(search_lower) and \
			   not recipe.get("name", "").to_lower().contains(search_lower) and \
			   not output_name.to_lower().contains(search_lower):
				continue
		
		var idx = _recipe_list.add_item(display_text)
		_recipe_list.set_item_metadata(idx, recipe_id)
		filtered_count += 1
		
		# 根据类别设置颜色
		match category:
			"weapon":
				_recipe_list.set_item_custom_fg_color(idx, Color.RED)
			"armor":
				_recipe_list.set_item_custom_fg_color(idx, Color.BLUE)
			"medical":
				_recipe_list.set_item_custom_fg_color(idx, Color.GREEN)
			"food":
				_recipe_list.set_item_custom_fg_color(idx, Color.ORANGE)
			"ammo":
				_recipe_list.set_item_custom_fg_color(idx, Color.YELLOW)
	
	if _stats_label and is_instance_valid(_stats_label):
		_stats_label.text = "Total: %d / Filtered: %d" % [recipes.size(), filtered_count]

func _get_output_item_name(recipe: Dictionary) -> String:
	var output = recipe.get("output", {})
	var item_id = output.get("item_id", "")
	# 安全访问 ItemDatabase
	var item_db = get_node_or_null("/root/ItemDatabase")
	if item_db and item_db.has_method("get_item_name"):
		return item_db.get_item_name(item_id)
	return item_id

func _on_category_filter_changed(index: int):
	var category := ""
	if _category_filter and index >= 0 and index < _category_filter.get_item_count():
		category = str(_category_filter.get_item_metadata(index))
	_selected_category_filter = category
	_update_recipe_list(_selected_category_filter, _search_filter_text)

func _on_search_changed(text: String):
	_search_filter_text = text.strip_edges()
	_update_recipe_list(_selected_category_filter, _search_filter_text)

func _on_new_recipe():
	var recipe_id = "recipe_%d" % Time.get_ticks_msec()
	var recipe_data = {
		"id": recipe_id,
		"name": "新配方",
		"description": "",
		"category": "misc",
		"output": {
			"item_id": "",
			"count": 1,
			"quality_bonus": 0
		},
		"materials": [],
		"required_tools": [],
		"optional_tools": [],
		"required_station": "none",
		"skill_requirements": {},
		"craft_time": 10.0,
		"experience_reward": 5,
		"unlock_conditions": [],
		"is_default_unlocked": true
	}
	
	recipes[recipe_id] = recipe_data
	_update_recipe_list()
	_select_recipe(recipe_id)
	_update_status("创建了新配方: %s" % recipe_id)

func _on_delete_recipe():
	if current_recipe_id.is_empty():
		return
	
	recipes.erase(current_recipe_id)
	current_recipe_id = ""
	_update_recipe_list()
	_clear_property_panel()
	_update_status("删除了配方")

func _on_duplicate_recipe():
	if current_recipe_id.is_empty():
		return
	
	var source_recipe = recipes.get(current_recipe_id, {})
	if source_recipe.is_empty():
		return
	
	var new_id = "recipe_%d" % Time.get_ticks_msec()
	var new_recipe = source_recipe.duplicate(true)
	new_recipe.id = new_id
	new_recipe.name = new_recipe.name + " (复制)"
	
	recipes[new_id] = new_recipe
	_update_recipe_list()
	_select_recipe(new_id)
	_update_status("复制了配方: %s" % new_id)

func _on_recipe_selected(index: int):
	var recipe_id = _recipe_list.get_item_metadata(index)
	_select_recipe(recipe_id)

func _select_recipe(recipe_id: String):
	current_recipe_id = recipe_id
	var recipe = recipes.get(recipe_id)
	if recipe:
		_update_property_panel(recipe)

func _clear_property_panel():
	for child in _property_panel.get_children():
		child.queue_free()

func _update_property_panel(recipe: Dictionary):
	_clear_property_panel()
	_ui_elements.clear()
	
	# 基础信息
	_add_section_label("📋 基础信息")
	_add_string_field("id", "配方 ID:", recipe.get("id", ""), false)
	_add_string_field("name", "显示名称:", recipe.get("name", ""))
	_add_string_field("description", "描述:", recipe.get("description", ""), true)
	_add_enum_field("category", "类别:", RECIPE_CATEGORIES, recipe.get("category", "misc"))
	_add_bool_field("is_default_unlocked", "默认解锁:", recipe.get("is_default_unlocked", true))
	
	_add_separator()
	
	# 产出
	_add_section_label("📦 产出")
	var output = recipe.get("output", {})
	_add_string_field("output_item_id", "产出物品ID:", output.get("item_id", ""))
	_add_number_field("output_count", "产出数量:", output.get("count", 1), 1, 999, 1)
	_add_number_field("output_quality", "品质加成:", output.get("quality_bonus", 0), 0, 10, 1)
	
	_add_separator()
	
	# 材料
	_add_section_label("🔧 材料")
	_add_materials_editor(recipe.get("materials", []))
	
	_add_separator()
	
	# 工具
	_add_section_label("🛠️ 工具")
	_add_string_array_field("required_tools", "必需工具:", recipe.get("required_tools", []))
	_add_string_array_field("optional_tools", "可选工具:", recipe.get("optional_tools", []))
	
	_add_separator()
	
	# 工作台和技能
	_add_section_label("⚙️ 需求")
	_add_enum_field("required_station", "工作台:", STATION_TYPES, recipe.get("required_station", "none"))
	_add_number_field("craft_time", "制作时间(秒):", recipe.get("craft_time", 10.0), 0.0, 3600.0, 1.0)
	_add_number_field("experience_reward", "经验奖励:", recipe.get("experience_reward", 5), 0, 9999, 1)

# ========== UI 辅助方法 ==========

func _add_section_label(text: String):
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.YELLOW)
	_property_panel.add_child(label)

func _add_separator():
	_property_panel.add_child(HSeparator.new())

func _add_string_field(key: String, label_text: String, value: String, multiline: bool = false):
	var hbox = HBoxContainer.new()
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(label)
	
	var line_edit = LineEdit.new()
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.text = value
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

func _add_materials_editor(materials: Array):
	_materials_container = VBoxContainer.new()
	_materials_container.name = "MaterialsContainer"
	
	# 显示当前材料
	for i in range(materials.size()):
		_create_material_row(_materials_container, i, materials[i], materials)
	
	# 添加按钮
	var add_btn = Button.new()
	add_btn.text = "+ 添加材料"
	add_btn.pressed.connect(func():
		materials.append({"item_id": "", "count": 1})
		_create_material_row(_materials_container, materials.size() - 1, materials.back(), materials)
	)
	_materials_container.add_child(add_btn)
	
	_property_panel.add_child(_materials_container)

func _create_material_row(container: VBoxContainer, index: int, material: Dictionary, materials_ref: Array = []):
	var row = HBoxContainer.new()
	
	var item_edit = LineEdit.new()
	item_edit.placeholder_text = "物品ID"
	item_edit.text = material.get("item_id", "")
	item_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_edit.text_changed.connect(func(v): 
		material.item_id = v
		var target_materials = _resolve_materials_ref(materials_ref)
		_on_field_changed("materials", target_materials)
	)
	row.add_child(item_edit)
	
	var count_spin = SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 999
	count_spin.value = material.get("count", 1)
	count_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_spin.value_changed.connect(func(v):
		material.count = int(v)
		var target_materials = _resolve_materials_ref(materials_ref)
		_on_field_changed("materials", target_materials)
	)
	row.add_child(count_spin)
	
	var del_btn = Button.new()
	del_btn.text = "删除"
	del_btn.pressed.connect(func():
		var target_materials = _resolve_materials_ref(materials_ref)
		var target_index = target_materials.find(material)
		if target_index < 0:
			target_index = index
		if target_index >= 0 and target_index < target_materials.size():
			target_materials.remove_at(target_index)
		row.queue_free()
		_on_field_changed("materials", target_materials)
	)
	row.add_child(del_btn)
	
	# 插入到添加按钮之前
	var add_button_idx = container.get_child_count() - 1
	container.add_child(row)
	if add_button_idx >= 0:
		container.move_child(row, add_button_idx)

func _resolve_materials_ref(materials_ref: Array) -> Array:
	if not materials_ref.is_empty():
		return materials_ref
	if current_recipe_id.is_empty() or not recipes.has(current_recipe_id):
		return []
	return recipes[current_recipe_id].get("materials", [])

func _add_string_array_field(key: String, label_text: String, values: Array):
	var vbox = VBoxContainer.new()
	
	var label = Label.new()
	label.text = label_text
	vbox.add_child(label)
	
	var list_container = VBoxContainer.new()
	list_container.name = "List_" + key
	
	for i in range(values.size()):
		_create_string_array_row(list_container, i, values[i], values)
	
	var add_btn = Button.new()
	add_btn.text = "+ 添加"
	add_btn.pressed.connect(func():
		values.append("")
		_create_string_array_row(list_container, values.size() - 1, "", values)
	)
	list_container.add_child(add_btn)
	
	vbox.add_child(list_container)
	_property_panel.add_child(vbox)
	_ui_elements[key] = list_container

func _create_string_array_row(container: VBoxContainer, index: int, value: String, array_ref: Array):
	var row = HBoxContainer.new()
	
	var line_edit = LineEdit.new()
	line_edit.text = value
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.text_changed.connect(func(v):
		array_ref[index] = v
		_on_field_changed(container.name.trim_prefix("List_"), array_ref)
	)
	row.add_child(line_edit)
	
	var del_btn = Button.new()
	del_btn.text = "删除"
	del_btn.pressed.connect(func():
		array_ref.remove_at(index)
		row.queue_free()
	)
	row.add_child(del_btn)
	
	# 插入到添加按钮之前
	var add_button_idx = container.get_child_count() - 1
	container.add_child(row)
	if add_button_idx >= 0:
		container.move_child(row, add_button_idx)

func _on_field_changed(key: String, value: Variant):
	if current_recipe_id.is_empty():
		return
	
	var recipe = recipes[current_recipe_id]
	
	# 处理特殊字段
	if key == "id" and value != current_recipe_id and not value.is_empty() and not recipes.has(value):
		recipes.erase(current_recipe_id)
		recipe.id = value
		recipes[value] = recipe
		current_recipe_id = value
		_update_recipe_list()
	elif key == "output_item_id":
		if not recipe.has("output"):
			recipe.output = {}
		recipe.output.item_id = value
	elif key == "output_count":
		if not recipe.has("output"):
			recipe.output = {}
		recipe.output.count = int(value)
	elif key == "output_quality":
		if not recipe.has("output"):
			recipe.output = {}
		recipe.output.quality_bonus = int(value)
	else:
		recipe[key] = value
	
	_update_status("已更新: %s" % key)

# ========== 文件操作 ==========

func _on_save_recipes():
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "recipes.json"
	_file_dialog.file_selected.connect(_save_to_file, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _save_to_file(path: String):
	var json = JSON.stringify(recipes, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		recipe_saved.emit(current_recipe_id)
		_update_status("✓ 已保存: %s (%d个配方)" % [path, recipes.size()])
	else:
		_update_status("❌ 保存失败")

func _on_load_recipes():
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
	
	recipes = json.data
	_update_recipe_list()
	_clear_property_panel()
	recipe_loaded.emit(current_recipe_id)
	_update_status("✓ 已加载: %s (%d个配方)" % [path, recipes.size()])

func _update_status(message: String):
	_status_bar.text = message
	print("[RecipeEditor] %s" % message)

# 公共方法
func get_current_recipe_id() -> String:
	return current_recipe_id

func get_recipes_count() -> int:
	return recipes.size()
