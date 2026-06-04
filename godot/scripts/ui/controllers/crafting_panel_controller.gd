extends Control

var _panel: PanelContainer
var _summary_label: Label
var _search_box: LineEdit
var _category_box: HBoxContainer
var _sort_box: HBoxContainer
var _recipe_box: VBoxContainer
var _detail_title_label: Label
var _detail_body_label: Label
var _quantity_spin: SpinBox
var _category_filter := "all"
var _sort_mode := "name"
var _search_text := ""
var _selected_recipe_id := ""
var _last_snapshot: Dictionary = {}


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	_last_snapshot = snapshot.duplicate(true)
	var recipes: Array = snapshot.get("recipes", [])
	var visible_recipes: Array[Dictionary] = _visible_recipes(recipes)
	_summary_label.text = "%s | 配方 %d/%d | 可制作 %d | %s | %s" % [
		snapshot.get("owner_name", ""),
		visible_recipes.size(),
		recipes.size(),
		int(snapshot.get("craftable_count", 0)),
		_category_label(_category_filter),
		_sort_label(_sort_mode),
	]
	_rebuild_category_buttons(recipes)
	_refresh_sort_buttons()
	_clear_recipes()
	if visible_recipes.is_empty():
		var empty := _label("EmptyLine")
		empty.text = "没有符合筛选的配方"
		_recipe_box.add_child(empty)
		_apply_detail({})
		return
	if _selected_recipe_id.is_empty() or _recipe_by_id(visible_recipes, _selected_recipe_id).is_empty():
		_selected_recipe_id = str(_dictionary_or_empty(visible_recipes[0]).get("recipe_id", ""))
	for recipe in visible_recipes:
		var recipe_data: Dictionary = recipe
		_recipe_box.add_child(_recipe_row(recipe_data))
	_apply_detail(_recipe_by_id(visible_recipes, _selected_recipe_id))


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "CraftingPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 455
	_panel.offset_right = 850
	_panel.offset_top = -245
	_panel.offset_bottom = -24
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "CraftingLines"
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_summary_label = _label("SummaryLine")
	_search_box = LineEdit.new()
	_search_box.name = "SearchBox"
	_search_box.placeholder_text = "搜索配方"
	_search_box.clear_button_enabled = true
	_search_box.custom_minimum_size = Vector2(0, 28)
	_search_box.text_changed.connect(func(text: String) -> void:
		_search_text = text.strip_edges().to_lower()
		if not _last_snapshot.is_empty():
			apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	_category_box = HBoxContainer.new()
	_category_box.name = "CategoryBar"
	_category_box.add_theme_constant_override("separation", 4)
	_sort_box = HBoxContainer.new()
	_sort_box.name = "SortBar"
	_sort_box.add_theme_constant_override("separation", 4)
	_recipe_box = VBoxContainer.new()
	_recipe_box.name = "RecipeLines"
	_recipe_box.add_theme_constant_override("separation", 4)
	_detail_title_label = _label("DetailTitleLine")
	_detail_body_label = _label("DetailBodyLine")
	_quantity_spin = SpinBox.new()
	_quantity_spin.name = "CraftQuantitySpin"
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = 1
	_quantity_spin.step = 1
	_quantity_spin.value = 1
	_quantity_spin.custom_minimum_size = Vector2(84, 28)
	_quantity_spin.value_changed.connect(func(_value: float) -> void:
		_apply_detail(_recipe_by_id(_last_snapshot.get("recipes", []), _selected_recipe_id))
	, CONNECT_DEFERRED)
	box.add_child(_summary_label)
	box.add_child(_search_box)
	box.add_child(_category_box)
	box.add_child(_sort_box)
	_add_sort_button("SortNameButton", "名称", "name")
	_add_sort_button("SortCategoryButton", "分类", "category")
	_add_sort_button("SortCraftableButton", "可制作", "craftable")
	_add_sort_button("SortMaxButton", "数量", "max")
	var recipe_scroll := ScrollContainer.new()
	recipe_scroll.name = "RecipeScroll"
	recipe_scroll.custom_minimum_size = Vector2(360, 82)
	recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	recipe_scroll.add_child(_recipe_box)
	box.add_child(recipe_scroll)
	box.add_child(_detail_title_label)
	box.add_child(_detail_body_label)
	box.add_child(_quantity_spin)


func _recipe_row(recipe: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Recipe_%s" % recipe.get("recipe_id", "unknown")
	row.custom_minimum_size = Vector2(350, 28)
	row.add_theme_constant_override("separation", 6)
	var line := Button.new()
	line.name = "Line"
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.text = "%s | %s -> %s x%d | 最大 %d | %s" % [
		_category_label(str(recipe.get("category", ""))),
		recipe.get("name", recipe.get("recipe_id", "")),
		recipe.get("output_name", recipe.get("output_item_id", "")),
		int(recipe.get("output_count", 1)),
		int(recipe.get("max_craft_count", 0)),
		_reason_text(recipe),
	]
	line.tooltip_text = "查看配方 %s" % recipe.get("name", recipe.get("recipe_id", ""))
	line.alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.toggle_mode = true
	line.button_pressed = _selected_recipe_id == str(recipe.get("recipe_id", ""))
	line.focus_mode = Control.FOCUS_NONE
	var recipe_id := str(recipe.get("recipe_id", ""))
	line.pressed.connect(func() -> void:
		_selected_recipe_id = recipe_id
		if _quantity_spin != null:
			_quantity_spin.value = 1
		apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	var button := Button.new()
	button.name = "CraftButton"
	button.text = "+"
	button.tooltip_text = "制作 %s" % recipe.get("name", recipe.get("recipe_id", ""))
	button.custom_minimum_size = Vector2(34, 28)
	button.disabled = not bool(recipe.get("can_craft", false))
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("craft_player_recipe"):
			root.craft_player_recipe(recipe_id)
	, CONNECT_DEFERRED)
	row.add_child(line)
	row.add_child(button)
	return row


func _apply_detail(recipe: Dictionary) -> void:
	if _detail_title_label == null or _detail_body_label == null or _quantity_spin == null:
		return
	if recipe.is_empty():
		_detail_title_label.text = "配方详情"
		_detail_body_label.text = "选择配方查看详情"
		_quantity_spin.max_value = 1
		_quantity_spin.value = 1
		_quantity_spin.editable = false
		return
	var max_count: int = max(1, int(recipe.get("max_craft_count", 0)))
	_quantity_spin.max_value = max_count
	_quantity_spin.value = clampi(int(_quantity_spin.value), 1, max_count)
	_quantity_spin.editable = bool(recipe.get("can_craft", false)) and max_count > 1
	var selected_count: int = int(_quantity_spin.value)
	_detail_title_label.text = "详情: %s" % recipe.get("name", recipe.get("recipe_id", ""))
	var lines: Array[String] = []
	var description := str(recipe.get("description", ""))
	if not description.is_empty():
		lines.append(description)
	lines.append("输出: %s x%d" % [
		recipe.get("output_name", recipe.get("output_item_id", "")),
		int(recipe.get("output_count", 1)) * selected_count,
	])
	lines.append("材料: %s" % _materials_text(recipe.get("materials", []), selected_count))
	lines.append("要求: %s" % _requirements_text(recipe))
	lines.append("时间 %.1fs | XP %d | 最大 %d | %s" % [
		float(recipe.get("craft_time", 0.0)),
		int(recipe.get("experience_reward", 0)),
		int(recipe.get("max_craft_count", 0)),
		_reason_text(recipe),
	])
	_detail_body_label.text = "\n".join(lines)


func _materials_text(materials: Array, multiplier: int = 1) -> String:
	var parts: Array[String] = []
	for material in materials:
		var data: Dictionary = material
		parts.append("%s %d/%d" % [
			data.get("name", data.get("item_id", "")),
			int(data.get("available", 0)),
			int(data.get("required", 0)) * multiplier,
		])
	return "无" if parts.is_empty() else ", ".join(parts)


func _requirements_text(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	var station := str(recipe.get("required_station", "none"))
	if station not in ["", "none"]:
		parts.append("工作台 %s" % station)
	var tools: Array = recipe.get("required_tools", [])
	if not tools.is_empty():
		parts.append("工具 %s" % ", ".join(tools))
	var skills: Dictionary = _dictionary_or_empty(recipe.get("skill_requirements", {}))
	for skill_id in skills.keys():
		parts.append("%s Lv%d" % [skill_id, int(skills[skill_id])])
	return "无" if parts.is_empty() else " / ".join(parts)


func _visible_recipes(recipes: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for recipe in recipes:
		var recipe_data: Dictionary = _dictionary_or_empty(recipe)
		if recipe_data.is_empty():
			continue
		if _category_filter != "all" and str(recipe_data.get("category", "")) != _category_filter:
			continue
		if not _search_matches(recipe_data):
			continue
		output.append(recipe_data)
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match _sort_mode:
			"category":
				var category_a := _category_label(str(a.get("category", "")))
				var category_b := _category_label(str(b.get("category", "")))
				if category_a == category_b:
					return str(a.get("name", a.get("recipe_id", ""))) < str(b.get("name", b.get("recipe_id", "")))
				return category_a < category_b
			"craftable":
				var can_a := 1 if bool(a.get("can_craft", false)) else 0
				var can_b := 1 if bool(b.get("can_craft", false)) else 0
				if can_a == can_b:
					return str(a.get("name", a.get("recipe_id", ""))) < str(b.get("name", b.get("recipe_id", "")))
				return can_a > can_b
			"max":
				var max_a := int(a.get("max_craft_count", 0))
				var max_b := int(b.get("max_craft_count", 0))
				if max_a == max_b:
					return str(a.get("name", a.get("recipe_id", ""))) < str(b.get("name", b.get("recipe_id", "")))
				return max_a > max_b
			_:
				return str(a.get("name", a.get("recipe_id", ""))) < str(b.get("name", b.get("recipe_id", "")))
	)
	return output


func _search_matches(recipe: Dictionary) -> bool:
	if _search_text.is_empty():
		return true
	var material_names: Array[String] = []
	for material in _array_or_empty(recipe.get("materials", [])):
		var material_data: Dictionary = _dictionary_or_empty(material)
		material_names.append("%s %s" % [
			material_data.get("item_id", ""),
			material_data.get("name", ""),
		])
	var haystack := "%s %s %s %s %s %s %s" % [
		recipe.get("recipe_id", ""),
		recipe.get("name", ""),
		recipe.get("description", ""),
		recipe.get("category", ""),
		_category_label(str(recipe.get("category", ""))),
		recipe.get("output_item_id", ""),
		recipe.get("output_name", ""),
	]
	if not material_names.is_empty():
		haystack = "%s %s" % [haystack, " ".join(material_names)]
	return haystack.to_lower().contains(_search_text)


func _rebuild_category_buttons(recipes: Array) -> void:
	if _category_box == null:
		return
	var categories: Array[String] = []
	for recipe in recipes:
		var category := str(_dictionary_or_empty(recipe).get("category", ""))
		if category.is_empty():
			category = "uncategorized"
		if not categories.has(category):
			categories.append(category)
	categories.sort_custom(func(a: String, b: String) -> bool:
		return _category_label(a) < _category_label(b)
	)
	if _category_filter != "all" and not categories.has(_category_filter):
		_category_filter = "all"
	for child in _category_box.get_children():
		_category_box.remove_child(child)
		child.free()
	_add_category_button("FilterCategoryAllButton", "全部", "all")
	for category in categories:
		_add_category_button("FilterCategory_%s" % category, _category_label(category), category)


func _add_category_button(node_name: String, text: String, category: String) -> void:
	var button := _toolbar_button(node_name, text, "显示%s配方" % text)
	button.button_pressed = _category_filter == category
	button.pressed.connect(func() -> void:
		_category_filter = category
		if not _last_snapshot.is_empty():
			apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	_category_box.add_child(button)


func _add_sort_button(node_name: String, text: String, mode: String) -> void:
	var button := _toolbar_button(node_name, text, "按%s排序" % text)
	button.button_pressed = _sort_mode == mode
	button.pressed.connect(func() -> void:
		_sort_mode = mode
		if not _last_snapshot.is_empty():
			apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	_sort_box.add_child(button)


func _toolbar_button(node_name: String, text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tooltip
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(56, 28)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _refresh_sort_buttons() -> void:
	if _sort_box == null:
		return
	for child in _sort_box.get_children():
		if child is Button:
			var button := child as Button
			match button.name:
				"SortNameButton":
					button.button_pressed = _sort_mode == "name"
				"SortCategoryButton":
					button.button_pressed = _sort_mode == "category"
				"SortCraftableButton":
					button.button_pressed = _sort_mode == "craftable"
				"SortMaxButton":
					button.button_pressed = _sort_mode == "max"


func _category_label(category: String) -> String:
	match category:
		"all":
			return "全部"
		"ammo":
			return "弹药"
		"armor":
			return "护甲"
		"base":
			return "基地"
		"medical":
			return "医疗"
		"repair":
			return "维修"
		"tool":
			return "工具"
		"weapon":
			return "武器"
		"uncategorized", "":
			return "未分类"
	return category


func _sort_label(mode: String) -> String:
	match mode:
		"category":
			return "分类排序"
		"craftable":
			return "可制作优先"
		"max":
			return "数量排序"
	return "名称排序"


func _reason_text(recipe: Dictionary) -> String:
	match str(recipe.get("craft_reason", "")):
		"available":
			return "可制作"
		"recipe_locked":
			return "未解锁"
		"required_tools_unsupported":
			return "缺工具流程"
		"required_station_unsupported":
			return "需工作台 %s" % recipe.get("required_station", "")
		"missing_skills":
			var parts: Array[String] = []
			for item in recipe.get("missing_skills", []):
				var data: Dictionary = item
				parts.append("%s %d/%d" % [
					data.get("skill_id", ""),
					int(data.get("current_level", 0)),
					int(data.get("required_level", 0)),
				])
			return "技能不足 %s" % ", ".join(parts)
		"materials_insufficient":
			var parts: Array[String] = []
			for item in recipe.get("missing_materials", []):
				var data: Dictionary = item
				parts.append("%s %d/%d" % [
					data.get("name", data.get("item_id", "")),
					int(data.get("available", 0)),
					int(data.get("required", 0)),
				])
			return "材料不足 %s" % ", ".join(parts)
	return str(recipe.get("craft_reason", ""))


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear_recipes() -> void:
	for child in _recipe_box.get_children():
		_recipe_box.remove_child(child)
		child.free()


func _recipe_by_id(recipes: Array, recipe_id: String) -> Dictionary:
	for recipe in recipes:
		var recipe_data: Dictionary = _dictionary_or_empty(recipe)
		if str(recipe_data.get("recipe_id", "")) == recipe_id:
			return recipe_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
