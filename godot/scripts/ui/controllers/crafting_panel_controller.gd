extends Control

const MediaTextureLoader = preload("res://scripts/ui/media_texture_loader.gd")
const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")

var _panel: PanelContainer
var _summary_label: Label
var _search_box: LineEdit
var _category_box: HBoxContainer
var _sort_box: HBoxContainer
var _recipe_box: VBoxContainer
var _detail_title_label: Label
var _detail_body_label: Label
var _missing_reason_box: VBoxContainer
var _quantity_spin: SpinBox
var _queue_label: Label
var _queue_box: VBoxContainer
var _pending_label: Label
var _cancel_pending_button: Button
var _confirm_queue_button: Button
var _clear_queue_button: Button
var _feedback_label: Label
var _category_filter := "all"
var _sort_mode := "name"
var _search_text := ""
var _selected_recipe_id := ""
var _craft_queue: Array[Dictionary] = []
var _last_snapshot: Dictionary = {}
var _reason_catalog := ReasonCatalog.new()


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
	_summary_label.text = "%s | 配方 %d/%d | 可制作 %d | %s | %s | %s" % [
		snapshot.get("owner_name", ""),
		visible_recipes.size(),
		recipes.size(),
		int(snapshot.get("craftable_count", 0)),
		_category_label(_category_filter),
		_sort_label(_sort_mode),
		_station_summary_text(_dictionary_or_empty(snapshot.get("station_snapshot", {}))),
	]
	_rebuild_category_buttons(recipes)
	_refresh_sort_buttons()
	_clear_recipes()
	if visible_recipes.is_empty():
		var empty := _label("EmptyLine")
		empty.text = "没有符合筛选的配方"
		_recipe_box.add_child(empty)
		_apply_detail({})
		_refresh_queue_view()
		return
	if _selected_recipe_id.is_empty() or _recipe_by_id(visible_recipes, _selected_recipe_id).is_empty():
		_selected_recipe_id = str(_dictionary_or_empty(visible_recipes[0]).get("recipe_id", ""))
	for recipe in visible_recipes:
		var recipe_data: Dictionary = recipe
		_recipe_box.add_child(_recipe_row(recipe_data))
	_apply_detail(_recipe_by_id(visible_recipes, _selected_recipe_id))
	_refresh_queue_view()


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "CraftingPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 455
	_panel.offset_right = 850
	_panel.offset_top = -310
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
	_missing_reason_box = VBoxContainer.new()
	_missing_reason_box.name = "MissingReasonLines"
	_missing_reason_box.add_theme_constant_override("separation", 3)
	_feedback_label = _label("FeedbackLine")
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
	_queue_label = _label("CraftQueueLine")
	_queue_box = VBoxContainer.new()
	_queue_box.name = "CraftQueueEntries"
	_queue_box.add_theme_constant_override("separation", 3)
	_pending_label = _label("PendingCraftingLine")
	_cancel_pending_button = _toolbar_button("CancelPendingCraftingButton", "取消制作", "取消正在跨回合进行的制作")
	_cancel_pending_button.toggle_mode = false
	_cancel_pending_button.pressed.connect(_cancel_pending_crafting, CONNECT_DEFERRED)
	_confirm_queue_button = _toolbar_button("ConfirmCraftQueueButton", "执行队列", "按顺序制作队列中的配方")
	_confirm_queue_button.toggle_mode = false
	_confirm_queue_button.pressed.connect(_confirm_craft_queue, CONNECT_DEFERRED)
	_clear_queue_button = _toolbar_button("ClearCraftQueueButton", "清空", "取消全部队列")
	_clear_queue_button.toggle_mode = false
	_clear_queue_button.pressed.connect(_clear_craft_queue, CONNECT_DEFERRED)
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
	box.add_child(_missing_reason_box)
	box.add_child(_quantity_spin)
	box.add_child(_pending_label)
	box.add_child(_cancel_pending_button)
	box.add_child(_queue_label)
	box.add_child(_queue_box)
	var queue_buttons := HBoxContainer.new()
	queue_buttons.name = "CraftQueueButtons"
	queue_buttons.add_theme_constant_override("separation", 4)
	queue_buttons.add_child(_confirm_queue_button)
	queue_buttons.add_child(_clear_queue_button)
	box.add_child(queue_buttons)
	box.add_child(_feedback_label)
	_refresh_queue_view()


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
	_apply_recipe_icon(line, recipe)
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
			var count := int(_quantity_spin.value) if _quantity_spin != null and _selected_recipe_id == recipe_id else 1
			var result: Dictionary = root.craft_player_recipe(recipe_id, max(1, count))
			_set_feedback_from_result(result, recipe)
	, CONNECT_DEFERRED)
	var queue_button := Button.new()
	queue_button.name = "QueueButton"
	queue_button.text = "Q"
	queue_button.tooltip_text = "加入制作队列"
	queue_button.custom_minimum_size = Vector2(34, 28)
	queue_button.disabled = not bool(recipe.get("can_craft", false))
	queue_button.mouse_filter = Control.MOUSE_FILTER_STOP
	queue_button.focus_mode = Control.FOCUS_NONE
	queue_button.pressed.connect(func() -> void:
		var count := int(_quantity_spin.value) if _quantity_spin != null and _selected_recipe_id == recipe_id else 1
		_queue_recipe(recipe, max(1, count))
	, CONNECT_DEFERRED)
	row.add_child(line)
	row.add_child(queue_button)
	row.add_child(button)
	return row


func _apply_recipe_icon(button: Button, recipe: Dictionary) -> void:
	var icon_asset := _dictionary_or_empty(recipe.get("output_icon_asset", {}))
	var texture := MediaTextureLoader.texture_from_asset(icon_asset)
	if texture == null:
		button.icon = null
		return
	button.icon = texture
	button.expand_icon = true
	button.set_meta("icon_resource_path", MediaTextureLoader.resource_path_from_asset(icon_asset))
	button.set_meta("icon_fallback_key", str(icon_asset.get("fallback_key", "")))


func _apply_detail(recipe: Dictionary) -> void:
	if _detail_title_label == null or _detail_body_label == null or _quantity_spin == null:
		return
	_clear_box(_missing_reason_box)
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
	for row in _missing_reason_rows(recipe):
		_missing_reason_box.add_child(row)


func _missing_reason_rows(recipe: Dictionary) -> Array[Control]:
	var rows: Array[Control] = []
	for condition in _array_or_empty(recipe.get("missing_unlock_conditions", [])):
		var condition_data: Dictionary = _dictionary_or_empty(condition)
		var condition_id := str(condition_data.get("id", ""))
		if condition_id.is_empty():
			continue
		var condition_name := str(condition_data.get("display_name", condition_id))
		rows.append(_missing_reason_button(
			"MissingReasonUnlock_%s" % condition_id,
			"定位解锁: %s" % condition_name,
			condition_name
		))
	for material in _array_or_empty(recipe.get("missing_materials", [])):
		var data: Dictionary = _dictionary_or_empty(material)
		var query := str(data.get("name", data.get("item_id", "")))
		if query.is_empty():
			continue
		rows.append(_missing_reason_button(
			"MissingReasonMaterial_%s" % str(data.get("item_id", query)),
			"定位材料: %s %d/%d" % [
				query,
				int(data.get("available", 0)),
				int(data.get("required", 0)),
			],
			query
		))
	var skill_rows_added := false
	for skill in _array_or_empty(recipe.get("missing_skills", [])):
		var data: Dictionary = _dictionary_or_empty(skill)
		var skill_id := str(data.get("skill_id", ""))
		if skill_id.is_empty():
			continue
		skill_rows_added = true
		rows.append(_missing_reason_button(
			"MissingReasonSkill_%s" % skill_id,
			"定位技能: %s %d/%d" % [
				skill_id,
				int(data.get("current_level", 0)),
				int(data.get("required_level", 0)),
			],
			skill_id
		))
	if not skill_rows_added:
		var skills: Dictionary = _dictionary_or_empty(recipe.get("skill_requirements", {}))
		for skill_id in skills.keys():
			var normalized_skill_id := str(skill_id)
			if normalized_skill_id.is_empty():
				continue
			rows.append(_missing_reason_button(
				"MissingReasonSkill_%s" % normalized_skill_id,
				"定位技能: %s Lv%d" % [
					normalized_skill_id,
					int(skills.get(skill_id, 0)),
				],
				normalized_skill_id
			))
	var station := str(recipe.get("required_station", "none"))
	if station not in ["", "none"] and str(recipe.get("craft_reason", "")) in ["missing_station", "required_station_unsupported", "station_world_flag_missing", "station_world_flag_blocked", "station_item_missing", "station_tool_missing"]:
		var available_station: Dictionary = _dictionary_or_empty(recipe.get("available_station", {}))
		var station_label := str(available_station.get("display_name", station))
		if available_station.is_empty():
			station_label = station
		rows.append(_missing_reason_button(
			"MissingReasonStation_%s" % station,
			"定位工作台: %s" % station_label,
			station
		))
	for tool in _array_or_empty(recipe.get("missing_tools", recipe.get("required_tools", []))):
		var tool_data: Dictionary = _tool_data(tool)
		var tool_id := str(tool_data.get("item_id", ""))
		if tool_id.is_empty():
			continue
		var tool_name := str(tool_data.get("name", tool_id))
		rows.append(_missing_reason_button(
			"MissingReasonTool_%s" % tool_id,
			"定位工具: %s %d/%d" % [
				tool_name,
				int(tool_data.get("available", 0)),
				int(tool_data.get("required", 1)),
			],
			tool_name
		))
	return rows


func _missing_reason_button(node_name: String, text: String, query: String) -> Button:
	var button := Button.new()
	button.name = node_name.replace(" ", "_").replace(":", "_")
	button.text = text
	button.tooltip_text = "搜索 %s 相关配方" % query
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(320, 24)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_locate_missing_reason(query)
	, CONNECT_DEFERRED)
	return button


func _locate_missing_reason(query: String) -> void:
	var normalized_query := query.strip_edges()
	if normalized_query.is_empty():
		return
	_category_filter = "all"
	_search_text = normalized_query.to_lower()
	if _search_box != null:
		_search_box.text = normalized_query
		_search_box.grab_focus()
	if not _last_snapshot.is_empty():
		apply_snapshot(_last_snapshot)


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


func _station_summary_text(station_snapshot: Dictionary) -> String:
	var stations: Array = _array_or_empty(station_snapshot.get("stations", []))
	if stations.is_empty():
		return "工作台 无"
	var labels: Array[String] = []
	for station in stations:
		var data: Dictionary = _dictionary_or_empty(station)
		var label := str(data.get("display_name", data.get("station_id", "")))
		if label.is_empty():
			continue
		var distance: int = int(data.get("distance", 2147483647))
		var station_range: int = int(data.get("range", 0))
		if bool(data.get("in_range", false)):
			label = "%s@%d/%d" % [label, distance, station_range]
		else:
			label = "%s@%d" % [label, distance]
		labels.append(label)
		if labels.size() >= 3:
			break
	return "工作台 %d/%d %s" % [
		int(station_snapshot.get("in_range_count", 0)),
		int(station_snapshot.get("count", stations.size())),
		", ".join(labels),
	]


func _tools_text(tools: Array) -> String:
	var parts: Array[String] = []
	for tool in tools:
		var data: Dictionary = _tool_data(tool)
		var tool_name := str(data.get("name", data.get("item_id", "")))
		if tool_name.is_empty():
			continue
		var text := "%s %d/%d" % [
			tool_name,
			int(data.get("available", 0)),
			int(data.get("required", 1)),
		]
		if bool(data.get("consume_on_craft", false)):
			text = "%s 消耗x%d" % [text, max(1, int(data.get("consume_count", 1)))]
			if int(data.get("inventory_available", data.get("available", 0))) < max(1, int(data.get("consume_count", 1))):
				text = "%s(背包不足)" % text
		if float(data.get("durability_cost", 0.0)) > 0.0:
			text = "%s 耐久%.1f/-%.1f" % [
				text,
				float(data.get("available_durability", 0.0)),
				float(data.get("durability_cost", 0.0)),
			]
		parts.append(text)
	return "无" if parts.is_empty() else ", ".join(parts)


func _unlock_conditions_text(conditions: Array) -> String:
	var parts: Array[String] = []
	for condition in conditions:
		var data: Dictionary = _dictionary_or_empty(condition)
		var condition_type := str(data.get("type", ""))
		var display_name := str(data.get("display_name", data.get("id", "")))
		if display_name.is_empty():
			continue
		match condition_type:
			"recipe":
				parts.append("配方 %s" % display_name)
			"skill":
				parts.append("技能 %s Lv%d" % [
					display_name,
					max(1, int(data.get("level", data.get("required_level", 1)))),
				])
			"quest":
				parts.append("任务 %s" % display_name)
			"item":
				parts.append("物品 %s x%d" % [
					display_name,
					max(1, int(data.get("count", data.get("required", 1)))),
				])
			"book":
				parts.append("书籍 %s" % display_name)
			"world_flag", "flag":
				parts.append("世界状态 %s" % display_name)
			_:
				parts.append("%s %s" % [condition_type, display_name])
	return "无" if parts.is_empty() else ", ".join(parts)


func _tool_data(tool: Variant) -> Dictionary:
	if typeof(tool) == TYPE_DICTIONARY:
		return tool
	var tool_id := str(tool)
	return {
		"item_id": tool_id,
		"name": tool_id,
		"available": 0,
		"required": 1,
	}


func _requirements_text(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	var station := str(recipe.get("required_station", "none"))
	if station not in ["", "none"]:
		var available_station: Dictionary = _dictionary_or_empty(recipe.get("available_station", {}))
		if available_station.is_empty():
			parts.append("工作台 %s" % station)
		else:
			var station_text := "工作台 %s 距离 %d" % [
				available_station.get("display_name", station),
				int(available_station.get("distance", 0)),
			]
			var station_permission := _station_permission_text(recipe)
			if not station_permission.is_empty():
				station_text = "%s %s" % [station_text, station_permission]
			parts.append(station_text)
	var tools: Array = recipe.get("required_tools", [])
	if not tools.is_empty():
		parts.append("工具 %s" % _tools_text(tools))
	var unlocks: Array = recipe.get("unlock_conditions", [])
	if not unlocks.is_empty():
		parts.append("解锁 %s" % _unlock_conditions_text(unlocks))
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
	var requirements: Array[String] = []
	requirements.append(str(recipe.get("required_station", "")))
	for tool in _array_or_empty(recipe.get("required_tools", [])):
		var tool_data: Dictionary = _tool_data(tool)
		requirements.append("%s %s" % [
			tool_data.get("item_id", ""),
			tool_data.get("name", ""),
		])
	for skill_id in _dictionary_or_empty(recipe.get("skill_requirements", {})).keys():
		requirements.append(str(skill_id))
	for condition in _array_or_empty(recipe.get("unlock_conditions", [])):
		var condition_data: Dictionary = _dictionary_or_empty(condition)
		requirements.append("%s %s %s" % [
			condition_data.get("type", ""),
			condition_data.get("id", ""),
			condition_data.get("display_name", ""),
		])
	if not requirements.is_empty():
		haystack = "%s %s" % [haystack, " ".join(requirements)]
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
			var parts: Array[String] = []
			for condition in recipe.get("missing_unlock_conditions", []):
				var data: Dictionary = _dictionary_or_empty(condition)
				var label := str(data.get("display_name", data.get("id", "")))
				if str(data.get("type", "")) == "skill":
					label = "%s %d/%d" % [
						label,
						int(data.get("current_level", 0)),
						int(data.get("required_level", 1)),
					]
				parts.append(label)
			return "未解锁 %s" % ", ".join(parts) if not parts.is_empty() else "未解锁"
		"required_tools_unsupported":
			return "缺工具流程"
		"missing_tools":
			var parts: Array[String] = []
			for item in recipe.get("missing_tools", []):
				var data: Dictionary = _tool_data(item)
				parts.append("%s %d/%d" % [
					data.get("name", data.get("item_id", "")),
					int(data.get("available", 0)),
					int(data.get("required", 1)),
				])
			return "缺工具 %s" % ", ".join(parts)
		"missing_consumable_tools":
			var parts: Array[String] = []
			for item in recipe.get("missing_tools", []):
				var data: Dictionary = _tool_data(item)
				parts.append("%s %d/%d" % [
					data.get("name", data.get("item_id", "")),
					int(data.get("available", 0)),
					int(data.get("required", 1)),
				])
			return "缺可消耗工具 %s" % ", ".join(parts)
		"tool_durability_insufficient":
			var parts: Array[String] = []
			for item in recipe.get("missing_tools", []):
				var data: Dictionary = _tool_data(item)
				parts.append("%s %.1f/%.1f" % [
					data.get("name", data.get("item_id", "")),
					float(data.get("available_durability", 0.0)),
					float(data.get("required_durability", data.get("durability_cost", 0.0))),
				])
			return "工具耐久不足 %s" % ", ".join(parts)
		"required_station_unsupported":
			return "需工作台 %s" % recipe.get("required_station", "")
		"missing_station":
			return "需工作台 %s" % recipe.get("required_station", "")
		"station_world_flag_missing":
			return "工作台未启用 %s" % _station_reason_detail(recipe)
		"station_world_flag_blocked":
			return "工作台被封锁 %s" % _station_reason_detail(recipe)
		"station_item_missing":
			return "工作台缺钥匙 %s" % _station_reason_detail(recipe)
		"station_tool_missing":
			return "工作台缺工具 %s" % _station_reason_detail(recipe)
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
	return _reason_catalog.disabled_text_for(str(recipe.get("craft_reason", "")))


func _station_permission_text(recipe: Dictionary) -> String:
	var station: Dictionary = _dictionary_or_empty(recipe.get("available_station", {}))
	if station.is_empty():
		return ""
	var permission: Dictionary = _dictionary_or_empty(station.get("permission", station))
	var reason := str(permission.get("reason", "")).strip_edges()
	if reason.is_empty() or bool(permission.get("success", false)):
		return "可用"
	match reason:
		"station_world_flag_missing":
			return "未启用 %s" % _station_reason_detail(recipe)
		"station_world_flag_blocked":
			return "被封锁 %s" % _station_reason_detail(recipe)
		"station_item_missing":
			return "缺钥匙 %s" % _station_reason_detail(recipe)
		"station_tool_missing":
			return "缺工具 %s" % _station_reason_detail(recipe)
	return reason


func _station_reason_detail(recipe: Dictionary) -> String:
	var station: Dictionary = _dictionary_or_empty(recipe.get("available_station", {}))
	var permission: Dictionary = _dictionary_or_empty(station.get("permission", station))
	for key in ["flag_id", "item_id"]:
		var value := str(permission.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return str(recipe.get("required_station", "")).strip_edges()


func _queue_recipe(recipe: Dictionary, count: int) -> void:
	var recipe_id := str(recipe.get("recipe_id", ""))
	if recipe_id.is_empty():
		return
	for index in range(_craft_queue.size()):
		var entry: Dictionary = _dictionary_or_empty(_craft_queue[index]).duplicate(true)
		if str(entry.get("recipe_id", "")) != recipe_id:
			continue
		entry["count"] = max(1, int(entry.get("count", 1))) + max(1, count)
		_craft_queue[index] = entry
		_feedback_label.text = "已加入队列: %s x%d" % [recipe.get("name", recipe_id), int(entry.get("count", 1))]
		_refresh_queue_view()
		return
	_craft_queue.append({
		"recipe_id": recipe_id,
		"name": str(recipe.get("name", recipe_id)),
		"count": max(1, count),
		"output_item_id": str(recipe.get("output_item_id", "")),
		"output_name": str(recipe.get("output_name", recipe.get("output_item_id", ""))),
		"output_count": max(1, int(recipe.get("output_count", 1))),
	})
	_feedback_label.text = "已加入队列: %s x%d" % [recipe.get("name", recipe_id), max(1, count)]
	_refresh_queue_view()


func _refresh_queue_view() -> void:
	if _queue_label == null or _queue_box == null:
		return
	_refresh_pending_crafting_view()
	_clear_box(_queue_box)
	if _craft_queue.is_empty():
		_queue_label.text = "制作队列 空"
		if _confirm_queue_button != null:
			_confirm_queue_button.disabled = true
		if _clear_queue_button != null:
			_clear_queue_button.disabled = true
		return
	var total_count := 0
	var summary_parts: Array[String] = []
	for index in range(_craft_queue.size()):
		var entry: Dictionary = _dictionary_or_empty(_craft_queue[index])
		total_count += max(1, int(entry.get("count", 1)))
		summary_parts.append("%s x%d" % [entry.get("name", entry.get("recipe_id", "")), int(entry.get("count", 1))])
		_queue_box.add_child(_queue_entry_row(index, entry))
	_queue_label.text = "制作队列 %d项/%d次 | %s" % [
		_craft_queue.size(),
		total_count,
		" | ".join(summary_parts.slice(0, 3)),
	]
	if _confirm_queue_button != null:
		_confirm_queue_button.disabled = false
	if _clear_queue_button != null:
		_clear_queue_button.disabled = false


func craft_queue_snapshot() -> Dictionary:
	var queued_entries := _craft_queue_summaries()
	var pending := _pending_crafting_snapshot()
	return {
		"active": not queued_entries.is_empty() or bool(pending.get("active", false)),
		"entry_count": queued_entries.size(),
		"total_count": _craft_queue_total_count(),
		"total_output_count": _craft_queue_total_output_count(),
		"outputs": _craft_queue_output_summaries(),
		"entries": queued_entries,
		"pending": pending,
		"confirm_enabled": _confirm_queue_button != null and not _confirm_queue_button.disabled,
		"clear_enabled": _clear_queue_button != null and not _clear_queue_button.disabled,
		"summary": str(_queue_label.text) if _queue_label != null else "",
		"pending_summary": str(_pending_label.text) if _pending_label != null else "",
		"feedback": str(_feedback_label.text) if _feedback_label != null else "",
	}


func _craft_queue_summaries() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for index in range(_craft_queue.size()):
		var entry: Dictionary = _dictionary_or_empty(_craft_queue[index])
		var count: int = max(1, int(entry.get("count", 1)))
		var output_count: int = max(1, int(entry.get("output_count", 1)))
		output.append({
			"index": index,
			"recipe_id": str(entry.get("recipe_id", "")),
			"name": str(entry.get("name", entry.get("recipe_id", ""))),
			"count": count,
			"output_item_id": str(entry.get("output_item_id", "")),
			"output_name": str(entry.get("output_name", entry.get("output_item_id", ""))),
			"output_count": output_count,
			"total_output_count": output_count * count,
			"cancel_button_name": "CancelCraftQueueEntry_%d" % index,
			"cancellable": true,
		})
	return output


func _craft_queue_total_count() -> int:
	var total := 0
	for entry in _craft_queue:
		total += max(1, int(_dictionary_or_empty(entry).get("count", 1)))
	return total


func _craft_queue_total_output_count() -> int:
	var total := 0
	for entry in _craft_queue:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		total += max(1, int(entry_data.get("count", 1))) * max(1, int(entry_data.get("output_count", 1)))
	return total


func _craft_queue_output_summaries() -> Array[Dictionary]:
	var by_item: Dictionary = {}
	for entry in _craft_queue:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var item_id: String = str(entry_data.get("output_item_id", ""))
		if item_id.is_empty():
			continue
		var count: int = max(1, int(entry_data.get("count", 1))) * max(1, int(entry_data.get("output_count", 1)))
		var existing: Dictionary = _dictionary_or_empty(by_item.get(item_id, {}))
		if existing.is_empty():
			existing = {
				"item_id": item_id,
				"name": str(entry_data.get("output_name", item_id)),
				"count": 0,
			}
		existing["count"] = int(existing.get("count", 0)) + count
		by_item[item_id] = existing
	var output: Array[Dictionary] = []
	var item_ids: Array = by_item.keys()
	item_ids.sort()
	for item_id in item_ids:
		output.append(_dictionary_or_empty(by_item.get(item_id, {})).duplicate(true))
	return output


func _pending_crafting_snapshot() -> Dictionary:
	var pending: Dictionary = _dictionary_or_empty(_last_snapshot.get("pending_crafting", {}))
	if pending.is_empty():
		return {
			"active": false,
			"cancel_enabled": _cancel_pending_button != null and not _cancel_pending_button.disabled,
		}
	var recipe_id: String = str(pending.get("recipe_id", ""))
	var recipe: Dictionary = _recipe_by_id(_last_snapshot.get("recipes", []), recipe_id)
	var required_ap: float = max(0.0, float(pending.get("required_ap", 0.0)))
	var progress_ap: float = clampf(float(pending.get("progress_ap", 0.0)), 0.0, required_ap)
	var remaining_ap: float = max(0.0, float(pending.get("remaining_ap", required_ap - progress_ap)))
	return {
		"active": true,
		"recipe_id": recipe_id,
		"name": str(recipe.get("name", recipe_id)),
		"count": max(1, int(pending.get("count", 1))),
		"progress_ap": progress_ap,
		"required_ap": required_ap,
		"remaining_ap": remaining_ap,
		"progress_ratio": 0.0 if required_ap <= 0.0 else progress_ap / required_ap,
		"cancel_enabled": _cancel_pending_button != null and not _cancel_pending_button.disabled,
	}


func _refresh_pending_crafting_view() -> void:
	if _pending_label == null or _cancel_pending_button == null:
		return
	var pending: Dictionary = _dictionary_or_empty(_last_snapshot.get("pending_crafting", {}))
	if pending.is_empty():
		_pending_label.text = "正在制作 无"
		_cancel_pending_button.disabled = true
		return
	var recipe_id: String = str(pending.get("recipe_id", ""))
	var recipe: Dictionary = _recipe_by_id(_last_snapshot.get("recipes", []), recipe_id)
	var recipe_name: String = str(recipe.get("name", recipe_id))
	var required_ap: float = max(0.0, float(pending.get("required_ap", 0.0)))
	var progress_ap: float = clampf(float(pending.get("progress_ap", 0.0)), 0.0, required_ap)
	var progress_percent: int = 0 if required_ap <= 0.0 else int(roundf((progress_ap / required_ap) * 100.0))
	_pending_label.text = "正在制作 %s x%d | 进度 %.1f/%.1f AP (%d%%) | 剩余 %.1f AP" % [
		recipe_name,
		max(1, int(pending.get("count", 1))),
		progress_ap,
		required_ap,
		progress_percent,
		float(pending.get("remaining_ap", 0.0)),
	]
	_cancel_pending_button.disabled = false


func _queue_entry_row(index: int, entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CraftQueueEntry_%d" % index
	row.add_theme_constant_override("separation", 4)
	var label := _label("CraftQueueEntryLabel_%d" % index)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s x%d -> %s x%d" % [
		entry.get("name", entry.get("recipe_id", "")),
		int(entry.get("count", 1)),
		entry.get("output_name", entry.get("output_item_id", "")),
		max(1, int(entry.get("output_count", 1))) * max(1, int(entry.get("count", 1))),
	]
	var cancel_button := Button.new()
	cancel_button.name = "CancelCraftQueueEntry_%d" % index
	cancel_button.text = "X"
	cancel_button.tooltip_text = "取消此队列项"
	cancel_button.custom_minimum_size = Vector2(32, 24)
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.pressed.connect(func() -> void:
		_cancel_queue_entry(index)
	, CONNECT_DEFERRED)
	row.add_child(label)
	row.add_child(cancel_button)
	return row


func _cancel_queue_entry(index: int) -> void:
	if index < 0 or index >= _craft_queue.size():
		return
	var entry: Dictionary = _dictionary_or_empty(_craft_queue[index])
	_craft_queue.remove_at(index)
	_feedback_label.text = "已取消队列项: %s" % entry.get("name", entry.get("recipe_id", ""))
	_refresh_queue_view()


func _clear_craft_queue() -> void:
	if _craft_queue.is_empty():
		return
	_craft_queue.clear()
	_feedback_label.text = "已清空制作队列"
	_refresh_queue_view()


func _confirm_craft_queue() -> void:
	if _craft_queue.is_empty():
		return
	var root := get_parent()
	if root == null or not root.has_method("confirm_crafting_queue"):
		_feedback_label.text = "制作失败: 队列 | 运行时未就绪"
		return
	var queued_entries := _craft_queue.duplicate(true)
	var result: Dictionary = root.confirm_crafting_queue(queued_entries)
	if bool(result.get("success", false)):
		_craft_queue.clear()
		_feedback_label.text = "已执行制作队列: %d次" % int(result.get("completed_count", 0))
	elif bool(result.get("partial_success", false)):
		_craft_queue.clear()
		_feedback_label.text = "制作队列部分完成: %d次 | 失败 %d项" % [
			int(result.get("completed_count", 0)),
			int(result.get("failed_count", 0)),
		]
	else:
		var failed: Array = _array_or_empty(result.get("failed", []))
		var reason := "unknown"
		if not failed.is_empty():
			reason = str(_dictionary_or_empty(failed[0]).get("reason", "unknown"))
		_feedback_label.text = "制作队列失败: %s" % _craft_failure_text(reason)
	_refresh_queue_view()
	if not _last_snapshot.is_empty():
		apply_snapshot(_last_snapshot)


func _cancel_pending_crafting() -> void:
	var root := get_parent()
	if root == null or not root.has_method("cancel_pending_crafting"):
		_feedback_label.text = "取消制作失败: 运行时未就绪"
		return
	var result: Dictionary = root.cancel_pending_crafting("crafting_ui")
	if bool(result.get("success", false)) and bool(result.get("had_pending", false)):
		_feedback_label.text = "已取消正在制作"
	elif bool(result.get("success", false)):
		_feedback_label.text = "没有正在制作"
	else:
		_feedback_label.text = "取消制作失败: %s" % _craft_failure_text(str(result.get("reason", "unknown")))
	if not _last_snapshot.is_empty():
		apply_snapshot(_last_snapshot)


func _set_feedback_from_result(result: Dictionary, recipe: Dictionary) -> void:
	if _feedback_label == null:
		return
	var recipe_id := str(recipe.get("recipe_id", result.get("recipe_id", "")))
	var recipe_name := str(recipe.get("name", recipe_id))
	if bool(result.get("success", false)):
		var output: Dictionary = _dictionary_or_empty(result.get("output", {}))
		var output_item_id := str(result.get("output_item_id", output.get("item_id", recipe.get("output_item_id", ""))))
		var output_count := int(result.get("output_count", output.get("count", recipe.get("output_count", 1))))
		var crafted_count := int(result.get("count", result.get("completed_count", 1)))
		var count_suffix := " x%d" % crafted_count if crafted_count > 1 else ""
		_feedback_label.text = "已制作%s: %s -> %s x%d" % [
			count_suffix,
			recipe_name,
			recipe.get("output_name", output_item_id),
			output_count,
		]
		return
	_feedback_label.text = "制作失败: %s | %s" % [
		recipe_name,
		_craft_failure_text(str(result.get("reason", "unknown"))),
	]


func _craft_failure_text(reason: String) -> String:
	match reason:
		"simulation_missing":
			return "运行时未就绪"
		"unknown_recipe":
			return "未知配方"
		"recipe_locked":
			return "配方未解锁"
		"required_tools_unsupported":
			return "缺少工具流程"
		"missing_tools":
			return "缺少工具"
		"missing_consumable_tools":
			return "缺少可消耗工具"
		"required_station_unsupported":
			return "缺少工作台"
		"missing_station":
			return "缺少工作台"
		"station_world_flag_missing":
			return "工作台未启用"
		"station_world_flag_blocked":
			return "工作台被封锁"
		"station_item_missing":
			return "缺少工作台钥匙"
		"station_tool_missing":
			return "缺少工作台工具"
		"missing_skill_requirements":
			return "技能不足"
		"materials_insufficient":
			return "材料不足"
		"ap_insufficient_craft":
			return "AP 不足"
		"ap_insufficient_craft_queued":
			return "AP 不足，已排队"
		"inventory_over_capacity":
			return "背包负重不足"
		"recipe_output_invalid":
			return "产物无效"
		"actor_missing":
			return "角色不存在"
	return _reason_catalog.disabled_text_for(reason)


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


func _clear_box(box: Node) -> void:
	if box == null:
		return
	for child in box.get_children():
		box.remove_child(child)
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
