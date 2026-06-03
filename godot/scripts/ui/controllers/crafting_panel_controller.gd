extends Control

var _panel: PanelContainer
var _summary_label: Label
var _recipe_box: VBoxContainer


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	var recipes: Array = snapshot.get("recipes", [])
	_summary_label.text = "%s | 配方 %d | 可制作 %d" % [
		snapshot.get("owner_name", ""),
		recipes.size(),
		int(snapshot.get("craftable_count", 0)),
	]
	_clear_recipes()
	for recipe in recipes.slice(0, 8):
		var recipe_data: Dictionary = recipe
		_recipe_box.add_child(_recipe_row(recipe_data))


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
	box.add_child(_summary_label)
	box.add_child(_recipe_box)


func _recipe_row(recipe: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Recipe_%s" % recipe.get("recipe_id", "unknown")
	row.custom_minimum_size = Vector2(350, 28)
	row.add_theme_constant_override("separation", 6)
	var line := _label("Line")
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.text = "%s -> %s x%d | %s" % [
		recipe.get("name", recipe.get("recipe_id", "")),
		recipe.get("output_name", recipe.get("output_item_id", "")),
		int(recipe.get("output_count", 1)),
		_reason_text(recipe),
	]
	var button := Button.new()
	button.name = "CraftButton"
	button.text = "+"
	button.tooltip_text = "制作 %s" % recipe.get("name", recipe.get("recipe_id", ""))
	button.custom_minimum_size = Vector2(34, 28)
	button.disabled = not bool(recipe.get("can_craft", false))
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	var recipe_id := str(recipe.get("recipe_id", ""))
	button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("craft_player_recipe"):
			root.craft_player_recipe(recipe_id)
	, CONNECT_DEFERRED)
	row.add_child(line)
	row.add_child(button)
	return row


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
