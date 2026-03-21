@tool
extends Control
## RecipeEditor - 目录化单文件配方编辑器

signal recipe_saved(recipe_id: String)
signal recipe_loaded(recipe_id: String)

const RECIPE_DIR := "res://data/recipes"
const LEFT_PANEL_MIN_WIDTH := 220
const LEFT_PANEL_MAX_WIDTH := 320
const LEFT_PANEL_DEFAULT_RATIO := 0.25
const RIGHT_PANEL_MIN_WIDTH := 520

const RECIPE_CATEGORIES := {
	"weapon": "武器",
	"armor": "护甲",
	"accessory": "饰品",
	"medical": "医疗",
	"food": "食物",
	"ammo": "弹药",
	"tool": "工具",
	"material": "材料加工",
	"base": "基地",
	"repair": "维修",
	"misc": "杂项"
}

const STATION_TYPES := {
	"none": "None (Hand Craft)",
	"workbench": "Workbench",
	"forge": "锻造台",
	"medical_station": "Medical Station",
	"cooking_station": "Cooking Station",
	"chemistry_lab": "Chemistry Lab"
}

var recipes: Dictionary = {}
var current_recipe_id: String = ""
var editor_plugin: EditorPlugin = null

var _recipe_file_paths: Dictionary = {}
var _pending_old_paths: Dictionary = {}
var _ui_elements: Dictionary = {}
var _materials_container: VBoxContainer
var _selected_category_filter: String = ""
var _search_filter_text: String = ""

@onready var _recipe_list: ItemList
@onready var _property_panel: VBoxContainer
@onready var _toolbar: HBoxContainer
@onready var _status_bar: Label
@onready var _category_filter: OptionButton
@onready var _search_box: LineEdit
@onready var _stats_label: Label
@onready var _main_split: HSplitContainer
var _split_layout_initialized: bool = false


func _ready() -> void:
	_setup_ui()
	resized.connect(_on_editor_resized)
	_load_recipes_from_directory()
	_update_recipe_list()
	call_deferred("_apply_split_layout")


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

	var new_btn := Button.new()
	new_btn.text = "新建配方"
	new_btn.pressed.connect(_on_new_recipe)
	_toolbar.add_child(new_btn)

	var duplicate_btn := Button.new()
	duplicate_btn.text = "复制"
	duplicate_btn.pressed.connect(_on_duplicate_recipe)
	_toolbar.add_child(duplicate_btn)

	var delete_btn := Button.new()
	delete_btn.text = "删除"
	delete_btn.pressed.connect(_on_delete_recipe)
	_toolbar.add_child(delete_btn)

	_toolbar.add_child(VSeparator.new())

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(_on_save_recipes)
	_toolbar.add_child(save_btn)

	var reload_btn := Button.new()
	reload_btn.text = "重新加载"
	reload_btn.pressed.connect(_on_reload_recipes)
	_toolbar.add_child(reload_btn)

	_main_split = HSplitContainer.new()
	_main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_main_split)

	var left_panel := _create_recipe_list_panel()
	_main_split.add_child(left_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_property_panel = VBoxContainer.new()
	_property_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_property_panel.add_theme_constant_override("separation", 10)
	scroll.add_child(_property_panel)
	_main_split.add_child(scroll)

	_status_bar = Label.new()
	_status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_bar.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_bar)
	_status_bar.text = "就绪"


func _create_recipe_list_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(LEFT_PANEL_MIN_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "配方列表"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)
	panel.add_child(HSeparator.new())

	var filter_hbox := HBoxContainer.new()
	var filter_label := Label.new()
	filter_label.text = "类别:"
	filter_hbox.add_child(filter_label)

	_category_filter = OptionButton.new()
	_category_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_filter.add_item("全部")
	_category_filter.set_item_metadata(0, "")
	var index := 1
	for category in RECIPE_CATEGORIES.keys():
		_category_filter.add_item(RECIPE_CATEGORIES[category])
		_category_filter.set_item_metadata(index, category)
		index += 1
	_category_filter.item_selected.connect(_on_category_filter_changed)
	filter_hbox.add_child(_category_filter)
	panel.add_child(filter_hbox)

	_search_box = LineEdit.new()
	_search_box.placeholder_text = "搜索配方..."
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.text_changed.connect(_on_search_changed)
	panel.add_child(_search_box)

	_recipe_list = ItemList.new()
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recipe_list.item_selected.connect(_on_recipe_selected)
	panel.add_child(_recipe_list)

	_stats_label = Label.new()
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_stats_label)

	return panel


func _load_recipes_from_directory() -> void:
	recipes.clear()
	_recipe_file_paths.clear()
	_pending_old_paths.clear()
	current_recipe_id = ""

	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		var absolute_dir := ProjectSettings.globalize_path(RECIPE_DIR)
		DirAccess.make_dir_recursive_absolute(absolute_dir)
		dir = DirAccess.open(RECIPE_DIR)

	if dir == null:
		_update_status("无法打开配方目录: %s" % RECIPE_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if dir.current_is_dir() or not file_name.ends_with(".json"):
			file_name = dir.get_next()
			continue

		var path := "%s/%s" % [RECIPE_DIR, file_name]
		var recipe_data := _read_recipe_file(path)
		if recipe_data.is_empty():
			file_name = dir.get_next()
			continue

		var recipe_id := str(recipe_data.get("id", file_name.trim_suffix(".json"))).strip_edges()
		if recipe_id.is_empty():
			file_name = dir.get_next()
			continue

		recipe_data["id"] = recipe_id
		recipes[recipe_id] = recipe_data
		_recipe_file_paths[recipe_id] = path
		file_name = dir.get_next()
	dir.list_dir_end()

	_update_status("已加载 %d 个配方" % recipes.size())


func _read_recipe_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var content := FileAccess.get_file_as_string(path)
	if content.is_empty():
		return {}

	var parsed: Variant = JSON.parse_string(content)
	if not (parsed is Dictionary):
		push_warning("[RecipeEditor] Invalid recipe JSON: %s" % path)
		return {}

	return _normalize_recipe_data(parsed as Dictionary)


func _normalize_recipe_data(recipe_data: Dictionary) -> Dictionary:
	var recipe := recipe_data.duplicate(true)
	recipe["id"] = str(recipe.get("id", ""))
	recipe["name"] = str(recipe.get("name", "New Recipe"))
	recipe["description"] = str(recipe.get("description", ""))
	recipe["category"] = str(recipe.get("category", "misc"))
	recipe["required_station"] = str(recipe.get("required_station", "none"))
	recipe["craft_time"] = float(recipe.get("craft_time", 10.0))
	recipe["experience_reward"] = int(recipe.get("experience_reward", 0))
	recipe["is_default_unlocked"] = bool(recipe.get("is_default_unlocked", true))
	recipe["durability_influence"] = float(recipe.get("durability_influence", 1.0))
	recipe["is_repair"] = bool(recipe.get("is_repair", false))
	recipe["target_type"] = str(recipe.get("target_type", "any"))
	recipe["repair_amount"] = int(recipe.get("repair_amount", 30))

	var output: Dictionary = recipe.get("output", {}).duplicate(true) if recipe.get("output", {}) is Dictionary else {}
	output["item_id"] = str(output.get("item_id", ""))
	output["count"] = int(output.get("count", 1))
	output["quality_bonus"] = int(output.get("quality_bonus", 0))
	recipe["output"] = output

	var normalized_materials: Array[Dictionary] = []
	for material_variant in recipe.get("materials", []):
		if not (material_variant is Dictionary):
			continue
		var material: Dictionary = material_variant.duplicate(true)
		material["item_id"] = str(material.get("item_id", ""))
		material["count"] = int(material.get("count", 1))
		normalized_materials.append(material)
	recipe["materials"] = normalized_materials

	var required_tools: Array[String] = []
	for tool_variant in recipe.get("required_tools", []):
		required_tools.append(str(tool_variant))
	recipe["required_tools"] = required_tools

	var optional_tools: Array[String] = []
	for tool_variant in recipe.get("optional_tools", []):
		optional_tools.append(str(tool_variant))
	recipe["optional_tools"] = optional_tools

	var skill_requirements := {}
	if recipe.get("skill_requirements", {}) is Dictionary:
		for skill_key in recipe.get("skill_requirements", {}).keys():
			skill_requirements[str(skill_key)] = int(recipe.get("skill_requirements", {}).get(skill_key, 0))
	recipe["skill_requirements"] = skill_requirements

	var unlock_conditions: Array[Dictionary] = []
	for condition_variant in recipe.get("unlock_conditions", []):
		if condition_variant is Dictionary:
			unlock_conditions.append((condition_variant as Dictionary).duplicate(true))
	recipe["unlock_conditions"] = unlock_conditions

	return recipe


func _update_recipe_list(category_filter: String = "", search_filter: String = "") -> void:
	_recipe_list.clear()

	var sorted_recipe_ids: Array[String] = []
	for recipe_variant in recipes.keys():
		sorted_recipe_ids.append(str(recipe_variant))
	sorted_recipe_ids.sort()

	var filtered_count := 0
	for recipe_id in sorted_recipe_ids:
		var recipe: Dictionary = recipes[recipe_id]
		if not category_filter.is_empty() and str(recipe.get("category", "")) != category_filter:
			continue

		var output_name := _get_output_item_name(recipe)
		if not search_filter.is_empty():
			var search_lower := search_filter.to_lower()
			if not recipe_id.to_lower().contains(search_lower) \
				and not str(recipe.get("name", "")).to_lower().contains(search_lower) \
				and not output_name.to_lower().contains(search_lower):
				continue

		var display_text := "%s - %s -> %s" % [recipe_id, str(recipe.get("name", "Unnamed")), output_name]
		var item_index := _recipe_list.add_item(display_text)
		_recipe_list.set_item_metadata(item_index, recipe_id)
		_apply_category_color(item_index, str(recipe.get("category", "")))
		filtered_count += 1

	_stats_label.text = "总计: %d | 当前筛选: %d" % [recipes.size(), filtered_count]


func _apply_category_color(item_index: int, category: String) -> void:
	match category:
		"weapon":
			_recipe_list.set_item_custom_fg_color(item_index, Color.RED)
		"armor":
			_recipe_list.set_item_custom_fg_color(item_index, Color.BLUE)
		"medical":
			_recipe_list.set_item_custom_fg_color(item_index, Color.GREEN)
		"food":
			_recipe_list.set_item_custom_fg_color(item_index, Color.ORANGE)
		"ammo":
			_recipe_list.set_item_custom_fg_color(item_index, Color.YELLOW)
		"repair":
			_recipe_list.set_item_custom_fg_color(item_index, Color.CYAN)


func _get_output_item_name(recipe: Dictionary) -> String:
	var output: Dictionary = recipe.get("output", {})
	var item_id := str(output.get("item_id", ""))
	if ItemDatabase and ItemDatabase.has_method("get_item_name"):
		return ItemDatabase.get_item_name(item_id)
	return item_id


func _on_category_filter_changed(index: int) -> void:
	_selected_category_filter = str(_category_filter.get_item_metadata(index))
	_update_recipe_list(_selected_category_filter, _search_filter_text)


func _on_search_changed(text: String) -> void:
	_search_filter_text = text.strip_edges()
	_update_recipe_list(_selected_category_filter, _search_filter_text)


func _on_new_recipe() -> void:
	var recipe_id := "recipe_%d" % Time.get_ticks_msec()
	recipes[recipe_id] = _normalize_recipe_data({
		"id": recipe_id,
		"name": "New Recipe",
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
		"experience_reward": 0,
		"unlock_conditions": [],
		"is_default_unlocked": true,
		"durability_influence": 1.0,
		"is_repair": false,
		"target_type": "any",
		"repair_amount": 30
	})
	_select_recipe(recipe_id)
	_update_recipe_list(_selected_category_filter, _search_filter_text)
	_update_status("创建了新配方: %s" % recipe_id)


func _on_delete_recipe() -> void:
	if current_recipe_id.is_empty() or not recipes.has(current_recipe_id):
		return

	var file_path := str(_recipe_file_paths.get(current_recipe_id, _get_recipe_file_path(current_recipe_id)))
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))

	var pending_old_path := str(_pending_old_paths.get(current_recipe_id, ""))
	if not pending_old_path.is_empty() and FileAccess.file_exists(pending_old_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending_old_path))

	recipes.erase(current_recipe_id)
	_recipe_file_paths.erase(current_recipe_id)
	_pending_old_paths.erase(current_recipe_id)
	current_recipe_id = ""
	_clear_property_panel()
	_update_recipe_list(_selected_category_filter, _search_filter_text)
	_update_status("已删除配方")


func _on_duplicate_recipe() -> void:
	if current_recipe_id.is_empty() or not recipes.has(current_recipe_id):
		return

	var source_recipe: Dictionary = recipes[current_recipe_id].duplicate(true)
	var new_id := "%s_copy_%d" % [current_recipe_id, Time.get_ticks_msec()]
	source_recipe["id"] = new_id
	source_recipe["name"] = "%s (复制)" % str(source_recipe.get("name", "Recipe"))
	recipes[new_id] = source_recipe
	_select_recipe(new_id)
	_update_recipe_list(_selected_category_filter, _search_filter_text)
	_update_status("复制了配方: %s" % new_id)


func _on_save_recipes() -> void:
	if current_recipe_id.is_empty():
		var sorted_recipe_ids: Array[String] = []
		for recipe_variant in recipes.keys():
			sorted_recipe_ids.append(str(recipe_variant))
		sorted_recipe_ids.sort()
		for recipe_id in sorted_recipe_ids:
			_save_recipe_to_disk(recipe_id)
		_update_status("已保存全部配方")
		return

	_save_recipe_to_disk(current_recipe_id)


func _save_recipe_to_disk(recipe_id: String) -> bool:
	if not recipes.has(recipe_id):
		return false

	var absolute_dir := ProjectSettings.globalize_path(RECIPE_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)

	var recipe: Dictionary = _normalize_recipe_data(recipes[recipe_id])
	recipe["id"] = recipe_id
	recipes[recipe_id] = recipe

	var target_path := _get_recipe_file_path(recipe_id)
	var old_path := str(_pending_old_paths.get(recipe_id, _recipe_file_paths.get(recipe_id, "")))
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		_update_status("保存失败: %s" % target_path)
		return false

	file.store_string(JSON.stringify(recipe, "\t"))
	file.close()

	if not old_path.is_empty() and old_path != target_path and FileAccess.file_exists(old_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))

	_recipe_file_paths[recipe_id] = target_path
	_pending_old_paths.erase(recipe_id)
	recipe_saved.emit(recipe_id)
	_update_status("已保存: %s" % target_path)
	return true


func _on_reload_recipes() -> void:
	var selected_id := current_recipe_id
	_load_recipes_from_directory()
	_update_recipe_list(_selected_category_filter, _search_filter_text)
	if not selected_id.is_empty() and recipes.has(selected_id):
		_select_recipe(selected_id)
	elif not recipes.is_empty():
		_select_recipe(str(recipes.keys()[0]))


func _get_recipe_file_path(recipe_id: String) -> String:
	return "%s/%s.json" % [RECIPE_DIR, recipe_id]


func _on_recipe_selected(index: int) -> void:
	_select_recipe(str(_recipe_list.get_item_metadata(index)))


func _select_recipe(recipe_id: String) -> void:
	current_recipe_id = recipe_id
	var recipe: Dictionary = recipes.get(recipe_id, {})
	if not recipe.is_empty():
		_update_property_panel(recipe)


func _clear_property_panel() -> void:
	for child in _property_panel.get_children():
		child.queue_free()
	_ui_elements.clear()


func _update_property_panel(recipe: Dictionary) -> void:
	_clear_property_panel()

	_add_section_label("基础信息")
	_add_line_field("id", "配方 ID:", str(recipe.get("id", "")), true)
	_add_line_field("name", "显示名称:", str(recipe.get("name", "")))
	_add_multiline_field("description", "描述:", str(recipe.get("description", "")))
	_add_enum_field("category", "类别:", RECIPE_CATEGORIES, str(recipe.get("category", "misc")))
	_add_bool_field("is_default_unlocked", "默认解锁:", bool(recipe.get("is_default_unlocked", true)))

	_add_separator()
	_add_section_label("产出")
	var output: Dictionary = recipe.get("output", {})
	_add_line_field("output_item_id", "产出物品 ID:", str(output.get("item_id", "")))
	_add_number_field("output_count", "产出数量:", float(output.get("count", 1)), 1, 999, 1)
	_add_number_field("output_quality", "品质加成:", float(output.get("quality_bonus", 0)), 0, 10, 1)

	_add_separator()
	_add_section_label("材料")
	_add_materials_editor(recipe.get("materials", []))

	_add_separator()
	_add_section_label("工具")
	_add_string_array_field("required_tools", "必需工具:", recipe.get("required_tools", []))
	_add_string_array_field("optional_tools", "可选工具:", recipe.get("optional_tools", []))

	_add_separator()
	_add_section_label("制作要求")
	_add_enum_field("required_station", "工作台:", STATION_TYPES, str(recipe.get("required_station", "none")))
	_add_number_field("craft_time", "制作时间(秒):", float(recipe.get("craft_time", 10.0)), 0.0, 3600.0, 1.0)
	_add_number_field("experience_reward", "经验奖励:", float(recipe.get("experience_reward", 0)), 0, 9999, 1)
	_add_json_field("skill_requirements", "技能需求(JSON):", recipe.get("skill_requirements", {}), TYPE_DICTIONARY)
	_add_json_field("unlock_conditions", "解锁条件(JSON):", recipe.get("unlock_conditions", []), TYPE_ARRAY)

	_add_separator()
	_add_section_label("特殊属性")
	_add_bool_field("is_repair", "维修配方:", bool(recipe.get("is_repair", false)))
	_add_line_field("target_type", "维修目标:", str(recipe.get("target_type", "any")))
	_add_number_field("repair_amount", "维修百分比:", float(recipe.get("repair_amount", 30)), 0, 100, 1)
	_add_number_field("durability_influence", "成功率修正:", float(recipe.get("durability_influence", 1.0)), 0.0, 1.5, 0.05)

	recipe_loaded.emit(current_recipe_id)


func _add_section_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.YELLOW)
	_property_panel.add_child(label)


func _add_separator() -> void:
	_property_panel.add_child(HSeparator.new())


func _add_line_field(key: String, label_text: String, value: String, commit_on_focus_exit: bool = false) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)

	var line_edit := LineEdit.new()
	line_edit.text = value
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if commit_on_focus_exit:
		line_edit.focus_exited.connect(func(): _on_field_commit(key, line_edit.text))
		line_edit.text_submitted.connect(func(_text): _on_field_commit(key, line_edit.text))
	else:
		line_edit.text_changed.connect(func(new_text): _on_field_changed(key, new_text))
	row.add_child(line_edit)
	_property_panel.add_child(row)
	_ui_elements[key] = line_edit


func _add_multiline_field(key: String, label_text: String, value: String) -> void:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)

	var text_edit := TextEdit.new()
	text_edit.custom_minimum_size = Vector2(0, 90)
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.text = value
	text_edit.focus_exited.connect(func(): _on_field_changed(key, text_edit.text))
	box.add_child(text_edit)

	_property_panel.add_child(box)
	_ui_elements[key] = text_edit


func _add_number_field(key: String, label_text: String, value: float, min_val: float, max_val: float, step: float) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)

	var spin_box := SpinBox.new()
	spin_box.min_value = min_val
	spin_box.max_value = max_val
	spin_box.step = step
	spin_box.value = value
	spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin_box.value_changed.connect(func(new_value): _on_field_changed(key, new_value))
	row.add_child(spin_box)

	_property_panel.add_child(row)
	_ui_elements[key] = spin_box


func _add_bool_field(key: String, label_text: String, value: bool) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)

	var checkbox := CheckBox.new()
	checkbox.button_pressed = value
	checkbox.toggled.connect(func(new_value): _on_field_changed(key, new_value))
	row.add_child(checkbox)

	_property_panel.add_child(row)
	_ui_elements[key] = checkbox


func _add_enum_field(key: String, label_text: String, options: Dictionary, value: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)

	var option_button := OptionButton.new()
	option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_index := 0
	var option_index := 0
	for option_key in options.keys():
		option_button.add_item(str(options[option_key]))
		option_button.set_item_metadata(option_index, option_key)
		if option_key == value:
			selected_index = option_index
		option_index += 1
	option_button.selected = selected_index
	option_button.item_selected.connect(func(index): _on_field_changed(key, str(option_button.get_item_metadata(index))))
	row.add_child(option_button)

	_property_panel.add_child(row)
	_ui_elements[key] = option_button


func _add_json_field(key: String, label_text: String, value: Variant, expected_type: int) -> void:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)

	var text_edit := TextEdit.new()
	text_edit.custom_minimum_size = Vector2(0, 90)
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.text = JSON.stringify(value, "\t")
	text_edit.focus_exited.connect(func(): _on_json_field_changed(key, text_edit.text, expected_type))
	box.add_child(text_edit)

	_property_panel.add_child(box)
	_ui_elements[key] = text_edit


func _add_materials_editor(materials: Array) -> void:
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "材料列表"
	box.add_child(title)

	_materials_container = VBoxContainer.new()
	box.add_child(_materials_container)
	_property_panel.add_child(box)

	_render_materials_editor(materials)


func _render_materials_editor(materials: Array) -> void:
	_clear_children(_materials_container)

	for index in range(materials.size()):
		var material: Dictionary = materials[index]
		var row := HBoxContainer.new()

		var item_edit := LineEdit.new()
		item_edit.placeholder_text = "物品ID"
		item_edit.text = str(material.get("item_id", ""))
		item_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_edit.text_changed.connect(func(new_text):
			var recipe := recipes.get(current_recipe_id, {})
			var updated_materials: Array = recipe.get("materials", [])
			if index < updated_materials.size():
				updated_materials[index]["item_id"] = new_text
				_on_field_changed("materials", updated_materials)
		)
		row.add_child(item_edit)

		var count_spin := SpinBox.new()
		count_spin.min_value = 1
		count_spin.max_value = 999
		count_spin.step = 1
		count_spin.value = float(material.get("count", 1))
		count_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count_spin.value_changed.connect(func(new_value):
			var recipe := recipes.get(current_recipe_id, {})
			var updated_materials: Array = recipe.get("materials", [])
			if index < updated_materials.size():
				updated_materials[index]["count"] = int(new_value)
				_on_field_changed("materials", updated_materials)
		)
		row.add_child(count_spin)

		var delete_btn := Button.new()
		delete_btn.text = "删除"
		delete_btn.pressed.connect(func():
			var recipe := recipes.get(current_recipe_id, {})
			var updated_materials: Array = recipe.get("materials", []).duplicate(true)
			if index < updated_materials.size():
				updated_materials.remove_at(index)
				_on_field_changed("materials", updated_materials)
				_render_materials_editor(updated_materials)
		)
		row.add_child(delete_btn)

		_materials_container.add_child(row)

	var add_btn := Button.new()
	add_btn.text = "+ 添加材料"
	add_btn.pressed.connect(func():
		var recipe := recipes.get(current_recipe_id, {})
		var updated_materials: Array = recipe.get("materials", []).duplicate(true)
		updated_materials.append({"item_id": "", "count": 1})
		_on_field_changed("materials", updated_materials)
		_render_materials_editor(updated_materials)
	)
	_materials_container.add_child(add_btn)


func _add_string_array_field(key: String, label_text: String, values: Array) -> void:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	box.add_child(label)

	var list_container := VBoxContainer.new()
	box.add_child(list_container)
	_property_panel.add_child(box)

	_render_string_array_field(key, values, list_container)
	_ui_elements[key] = list_container


func _render_string_array_field(key: String, values: Array, container: VBoxContainer) -> void:
	_clear_children(container)

	for index in range(values.size()):
		var row := HBoxContainer.new()
		var line_edit := LineEdit.new()
		line_edit.text = str(values[index])
		line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_edit.text_changed.connect(func(new_text):
			var recipe := recipes.get(current_recipe_id, {})
			var updated_values: Array = recipe.get(key, []).duplicate()
			if index < updated_values.size():
				updated_values[index] = new_text
				_on_field_changed(key, updated_values)
		)
		row.add_child(line_edit)

		var delete_btn := Button.new()
		delete_btn.text = "删除"
		delete_btn.pressed.connect(func():
			var recipe := recipes.get(current_recipe_id, {})
			var updated_values: Array = recipe.get(key, []).duplicate()
			if index < updated_values.size():
				updated_values.remove_at(index)
				_on_field_changed(key, updated_values)
				_render_string_array_field(key, updated_values, container)
		)
		row.add_child(delete_btn)

		container.add_child(row)

	var add_btn := Button.new()
	add_btn.text = "+ 添加"
	add_btn.pressed.connect(func():
		var recipe := recipes.get(current_recipe_id, {})
		var updated_values: Array = recipe.get(key, []).duplicate()
		updated_values.append("")
		_on_field_changed(key, updated_values)
		_render_string_array_field(key, updated_values, container)
	)
	container.add_child(add_btn)


func _on_field_commit(key: String, value: Variant) -> void:
	if key == "id":
		_commit_recipe_id_change(str(value))
		return
	_on_field_changed(key, value)


func _commit_recipe_id_change(raw_value: String) -> void:
	if current_recipe_id.is_empty() or not recipes.has(current_recipe_id):
		return

	var new_id := raw_value.strip_edges()
	if new_id.is_empty() or new_id == current_recipe_id:
		return
	if recipes.has(new_id):
		_update_status("配方 ID 已存在: %s" % new_id)
		return

	var recipe: Dictionary = recipes[current_recipe_id]
	var old_id := current_recipe_id
	var old_path := str(_recipe_file_paths.get(old_id, _get_recipe_file_path(old_id)))
	recipes.erase(old_id)
	_recipe_file_paths.erase(old_id)
	recipe["id"] = new_id
	recipes[new_id] = recipe
	_pending_old_paths[new_id] = old_path
	current_recipe_id = new_id
	_update_recipe_list(_selected_category_filter, _search_filter_text)
	_select_recipe(new_id)
	_update_status("已更新配方 ID: %s -> %s" % [old_id, new_id])


func _on_field_changed(key: String, value: Variant) -> void:
	if current_recipe_id.is_empty() or not recipes.has(current_recipe_id):
		return

	var recipe: Dictionary = recipes[current_recipe_id]
	match key:
		"output_item_id":
			var output: Dictionary = recipe.get("output", {}).duplicate(true)
			output["item_id"] = str(value)
			recipe["output"] = output
		"output_count":
			var output_count: Dictionary = recipe.get("output", {}).duplicate(true)
			output_count["count"] = int(value)
			recipe["output"] = output_count
		"output_quality":
			var output_quality: Dictionary = recipe.get("output", {}).duplicate(true)
			output_quality["quality_bonus"] = int(value)
			recipe["output"] = output_quality
		"craft_time", "durability_influence":
			recipe[key] = float(value)
		"experience_reward", "repair_amount":
			recipe[key] = int(value)
		_:
			recipe[key] = value

	recipes[current_recipe_id] = _normalize_recipe_data(recipe)
	_update_recipe_list(_selected_category_filter, _search_filter_text)
	_update_status("已更新字段: %s" % key)


func _on_json_field_changed(key: String, json_text: String, expected_type: int) -> void:
	var trimmed := json_text.strip_edges()
	var parsed: Variant = {} if expected_type == TYPE_DICTIONARY else []
	if not trimmed.is_empty():
		parsed = JSON.parse_string(trimmed)
		if parsed == null:
			_update_status("JSON 解析失败: %s" % key)
			return
		if typeof(parsed) != expected_type:
			_update_status("JSON 类型错误: %s" % key)
			return

	_on_field_changed(key, parsed)


func _update_status(message: String) -> void:
	_status_bar.text = message
	print("[RecipeEditor] %s" % message)


func _on_editor_resized() -> void:
	call_deferred("_apply_split_layout")


func _apply_split_layout() -> void:
	if _main_split == null or not is_instance_valid(_main_split):
		return

	var available_width := int(size.x)
	if available_width <= 0:
		return

	var min_left_width := LEFT_PANEL_MIN_WIDTH
	var max_left_width := min(LEFT_PANEL_MAX_WIDTH, max(min_left_width, available_width - RIGHT_PANEL_MIN_WIDTH))
	var default_left_width := int(round(float(available_width) * LEFT_PANEL_DEFAULT_RATIO))
	if not _split_layout_initialized:
		_main_split.split_offset = clampi(default_left_width, min_left_width, max_left_width)
		_split_layout_initialized = true
		return

	_main_split.split_offset = clampi(_main_split.split_offset, min_left_width, max_left_width)


func focus_record(record_id: String) -> bool:
	var target_id := record_id.strip_edges()
	if target_id.is_empty():
		return false

	_update_recipe_list(_selected_category_filter, _search_filter_text)
	if not recipes.has(target_id):
		_update_status("未找到配方: %s" % target_id)
		return false

	_select_recipe(target_id)
	for index in range(_recipe_list.get_item_count()):
		if str(_recipe_list.get_item_metadata(index)) == target_id:
			_recipe_list.select(index)
			_recipe_list.ensure_current_is_visible()
			break
	_update_status("已定位配方: %s" % target_id)
	return true


func get_current_recipe_id() -> String:
	return current_recipe_id


func get_recipes_count() -> int:
	return recipes.size()


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()
