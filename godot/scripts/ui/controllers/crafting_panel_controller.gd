extends Control

var _panel: PanelContainer
var _summary_label: Label
var _recipe_box: VBoxContainer
var _detail_title_label: Label
var _detail_body_label: Label
var _quantity_spin: SpinBox
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
	_summary_label.text = "%s | 配方 %d | 可制作 %d" % [
		snapshot.get("owner_name", ""),
		recipes.size(),
		int(snapshot.get("craftable_count", 0)),
	]
	_clear_recipes()
	if _selected_recipe_id.is_empty() or _recipe_by_id(recipes, _selected_recipe_id).is_empty():
		_selected_recipe_id = str(_dictionary_or_empty(recipes[0] if not recipes.is_empty() else {}).get("recipe_id", ""))
	for recipe in recipes.slice(0, 8):
		var recipe_data: Dictionary = recipe
		_recipe_box.add_child(_recipe_row(recipe_data))
	_apply_detail(_recipe_by_id(recipes, _selected_recipe_id))


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
	box.add_child(_recipe_box)
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
	line.text = "%s -> %s x%d | %s" % [
		recipe.get("name", recipe.get("recipe_id", "")),
		recipe.get("output_name", recipe.get("output_item_id", "")),
		int(recipe.get("output_count", 1)),
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
