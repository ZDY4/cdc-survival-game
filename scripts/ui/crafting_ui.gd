extends CanvasLayer
# CraftingUI - 制作系统界面

const InputActions = preload("res://core/input_actions.gd")

@onready var crafting_panel: Control = $CraftingPanel
@onready var category_tabs: Control = $CraftingPanel/VBoxContainer/CategoryTabs
@onready var recipe_list: Control = $CraftingPanel/VBoxContainer/RecipeList
@onready var recipe_details: Control = $CraftingPanel/VBoxContainer/RecipeDetails
@onready var crafting_queue_list: Control = $CraftingPanel/VBoxContainer/CraftingQueue
@onready var progress_bar: ProgressBar = $CraftingPanel/VBoxContainer/ProgressBar
@onready var toggle_button: Button = $ToggleButton

var current_category: String = ""
var selected_recipe: String = ""

const CATEGORY_LABELS := {
	"medical": "医疗",
	"weapon": "武器",
	"ammo": "弹药",
	"tool": "工具",
	"armor": "护甲",
	"base": "基地",
	"repair": "维修",
	"material": "材料加工",
	"misc": "杂项"
}


func _ready() -> void:
	toggle_button.pressed.connect(_on_toggle_pressed)
	crafting_panel.visible = false
	progress_bar.visible = false

	CraftingSystem.crafting_started.connect(_on_crafting_started)
	CraftingSystem.crafting_completed.connect(_on_crafting_completed)
	CraftingSystem.recipe_unlocked.connect(_on_recipe_unlocked)
	CraftingSystem.repair_recipe_unlocked.connect(_on_recipe_unlocked)

	_setup_category_tabs()


func _process(_delta: float) -> void:
	if crafting_panel.visible and CraftingSystem.is_crafting:
		progress_bar.value = CraftingSystem.get_crafting_progress() * 100.0


func _setup_category_tabs() -> void:
	_clear_children(category_tabs)

	var all_button := Button.new()
	all_button.text = "全部"
	all_button.pressed.connect(_on_category_selected.bind(""))
	category_tabs.add_child(all_button)

	for category in CraftingSystem.get_categories():
		var button := Button.new()
		button.text = CATEGORY_LABELS.get(category, category.capitalize())
		button.pressed.connect(_on_category_selected.bind(category))
		category_tabs.add_child(button)


func _on_toggle_pressed() -> void:
	crafting_panel.visible = not crafting_panel.visible
	if crafting_panel.visible:
		_update_recipe_list()
		_update_recipe_details()
		_update_crafting_queue()


func _on_category_selected(category: String) -> void:
	current_category = category
	_update_recipe_list()


func _update_recipe_list() -> void:
	_clear_children(recipe_list)
	var recipes: Array[Dictionary] = CraftingSystem.get_available_recipes(current_category)

	if recipes.is_empty():
		var empty_label := Label.new()
		empty_label.text = "没有可制作的配方"
		recipe_list.add_child(empty_label)
		return

	for recipe_variant in recipes:
		var recipe: Dictionary = recipe_variant
		var button := Button.new()
		var status := "✓" if bool(recipe.get("can_craft", false)) else "✗"
		button.text = "%s %s" % [status, str(recipe.get("name", recipe.get("id", "")))]
		button.disabled = false
		button.pressed.connect(_on_recipe_selected.bind(str(recipe.get("id", ""))))

		if str(recipe.get("id", "")) == selected_recipe:
			button.add_theme_color_override("font_color", Color.YELLOW)

		recipe_list.add_child(button)


func _on_recipe_selected(recipe_id: String) -> void:
	selected_recipe = recipe_id
	_update_recipe_list()
	_update_recipe_details()


func _update_recipe_details() -> void:
	_clear_children(recipe_details)

	if selected_recipe.is_empty():
		return

	var recipe: Dictionary = CraftingSystem.get_recipe(selected_recipe)
	if recipe.is_empty():
		return

	var name_label := Label.new()
	name_label.text = str(recipe.get("name", selected_recipe))
	name_label.add_theme_font_size_override("font_size", 20)
	recipe_details.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = str(recipe.get("description", ""))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recipe_details.add_child(desc_label)

	recipe_details.add_child(HSeparator.new())

	var materials_title := Label.new()
	materials_title.text = "所需材料:"
	recipe_details.add_child(materials_title)

	for material_variant in recipe.get("materials", []):
		var material: Dictionary = material_variant
		var material_id := str(material.get("item_id", ""))
		var required_count := int(material.get("count", 1))
		var current_count := InventoryModule.get_item_count(material_id) if InventoryModule else 0
		var material_label := Label.new()
		var status := "✓" if current_count >= required_count else "✗"
		material_label.text = "  %s %s: %d/%d" % [
			status,
			ItemDatabase.get_item_name(material_id) if ItemDatabase else material_id,
			current_count,
			required_count
		]
		recipe_details.add_child(material_label)

	var output: Dictionary = recipe.get("output", {})
	var output_label := Label.new()
	output_label.text = "产出: %s x%d" % [
		ItemDatabase.get_item_name(str(output.get("item_id", ""))) if ItemDatabase else str(output.get("item_id", "")),
		int(output.get("count", 1))
	]
	recipe_details.add_child(output_label)

	var time_label := Label.new()
	time_label.text = "制作时间: %.0f 秒" % float(recipe.get("craft_time", 0.0))
	recipe_details.add_child(time_label)

	var required_tools: Array[String] = recipe.get("required_tools", [])
	if not required_tools.is_empty():
		var tools_label := Label.new()
		var tool_names: PackedStringArray = []
		for tool_id in required_tools:
			tool_names.append(ItemDatabase.get_item_name(str(tool_id)) if ItemDatabase else str(tool_id))
		tools_label.text = "必需工具: %s" % ", ".join(tool_names)
		recipe_details.add_child(tools_label)

	var check := CraftingSystem.can_craft(selected_recipe)
	var craft_button := Button.new()
	craft_button.text = "开始制作" if bool(check.get("can_craft", false)) else str(check.get("message", "无法制作"))
	craft_button.disabled = not bool(check.get("can_craft", false))
	craft_button.pressed.connect(_on_craft_pressed)
	recipe_details.add_child(craft_button)


func _on_craft_pressed() -> void:
	if selected_recipe.is_empty():
		return

	if CraftingSystem.start_crafting(selected_recipe):
		_update_crafting_queue()
		_update_recipe_list()
		_update_recipe_details()


func _update_crafting_queue() -> void:
	_clear_children(crafting_queue_list)
	var queue: Array[Dictionary] = CraftingSystem.get_crafting_queue()

	if queue.is_empty():
		progress_bar.visible = false
		var empty_label := Label.new()
		empty_label.text = "制作队列空闲"
		crafting_queue_list.add_child(empty_label)
		return

	progress_bar.visible = true
	for index in range(queue.size()):
		var queue_item: Dictionary = queue[index]
		var recipe: Dictionary = queue_item.get("recipe", {})
		var row := HBoxContainer.new()

		var name_label := Label.new()
		name_label.text = str(recipe.get("name", queue_item.get("recipe_id", "")))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		if index == 0 and CraftingSystem.is_crafting:
			var progress_label := Label.new()
			progress_label.text = "%.0f%%" % (CraftingSystem.get_crafting_progress() * 100.0)
			row.add_child(progress_label)
		else:
			var cancel_button := Button.new()
			cancel_button.text = "取消"
			cancel_button.pressed.connect(_on_cancel_craft.bind(index))
			row.add_child(cancel_button)

		crafting_queue_list.add_child(row)


func _on_cancel_craft(index: int) -> void:
	CraftingSystem.cancel_crafting(index)
	_update_crafting_queue()
	_update_recipe_list()
	_update_recipe_details()


func _on_crafting_started(recipe_id: String, craft_time: float) -> void:
	_update_crafting_queue()
	var recipe: Dictionary = CraftingSystem.get_recipe(recipe_id)
	if DialogModule:
		DialogModule.show_dialog(
			"开始制作: %s (%.0f 秒)" % [str(recipe.get("name", recipe_id)), craft_time],
			"制作",
			""
		)


func _on_crafting_completed(item_id: String, count: int) -> void:
	_update_crafting_queue()
	_update_recipe_list()
	_update_recipe_details()
	if DialogModule:
		DialogModule.show_dialog(
			"制作完成: %s x%d" % [
				ItemDatabase.get_item_name(item_id) if ItemDatabase else item_id,
				count
			],
			"制作",
			""
		)


func _on_recipe_unlocked(recipe_id: String) -> void:
	if crafting_panel.visible:
		_update_recipe_list()

	var recipe: Dictionary = CraftingSystem.get_recipe(recipe_id)
	if DialogModule:
		DialogModule.show_dialog(
			"解锁新配方: %s" % str(recipe.get("name", recipe_id)),
			"制作",
			""
		)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.ACTION_MENU_CRAFTING):
		_on_toggle_pressed()


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()
