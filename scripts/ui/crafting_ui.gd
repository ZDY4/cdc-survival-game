extends CanvasLayer
# CraftingUI - 制作系统界面

@onready var crafting_panel = $CraftingPanel
@onready var category_tabs = $CraftingPanel/VBoxContainer/CategoryTabs
@onready var recipe_list = $CraftingPanel/VBoxContainer/RecipeList
@onready var recipe_details = $CraftingPanel/VBoxContainer/RecipeDetails
@onready var crafting_queue_list = $CraftingPanel/VBoxContainer/CraftingQueue
@onready var progress_bar = $CraftingPanel/VBoxContainer/ProgressBar
@onready var toggle_button = $ToggleButton

var current_category: String = ""
var selected_recipe: String = ""

func _ready():
	toggle_button.pressed.connect(_on_toggle_pressed)
	crafting_panel.visible = false
	
	# 订阅制作事件
	CraftingSystem.crafting_started.connect(_on_crafting_started)
	CraftingSystem.crafting_completed.connect(_on_crafting_completed)
	CraftingSystem.recipe_unlocked.connect(_on_recipe_unlocked)
	
	_setup_category_tabs()

func _process():
	if crafting_panel.visible && CraftingSystem.is_crafting:
		progress_bar.value = CraftingSystem.get_crafting_progress() * 100

func _setup_category_tabs():
	# 清除现有标签
	for child in category_tabs.get_children():
		child.queue_free()
	
	# 添加"全部"标签
	var all_button = Button.new()
	all_button.text = "全部"
	all_button.pressed.connect(_on_category_selected.bind(""))
	category_tabs.add_child(all_button)
	
	# 添加分类标签
	var categories = {
		"medical": "医疗",
		"weapon": "武器",
		"ammo": "弹药",
		"tool": "工具",
		"base": "基地"
	}
	
	for cat_id in categories.keys():
		var button = Button.new()
		button.text = categories[cat_id]
		button.pressed.connect(_on_category_selected.bind(cat_id))
		category_tabs.add_child(button)

func _on_toggle_pressed():
	crafting_panel.visible = !crafting_panel.visible
	if crafting_panel.visible:
		_update_recipe_list()
		_update_crafting_queue()

func _on_category_selected():
	current_category = category
	_update_recipe_list()

func _update_recipe_list():
	# 清除列表
	for child in recipe_list.get_children():
		child.queue_free()
	
	var recipes = CraftingSystem.get_available_recipes(current_category)
	
	if recipes.size() == 0:
		var label = Label.new()
		label.text = "没有可制作的配方"
		recipe_list.add_child(label)
		return
	
	for recipe in recipes:
		var button = Button.new()
		var status = "✓" if recipe.can_craft else "✗"
		button.text = "%s %s" % [status, recipe.name]
		button.disabled = not recipe.can_craft
		button.pressed.connect(_on_recipe_selected.bind(recipe.id))
		
		if recipe.id == selected_recipe:
			button.add_theme_color_override("font_color", Color.YELLOW)
		
		recipe_list.add_child(button)

func _on_recipe_selected():
	selected_recipe = recipe_id
	_update_recipe_list()  # 刷新高亮
	_update_recipe_details()

func _update_recipe_details(recipe_id: String):
	# 清除详情
	for child in recipe_details.get_children():
		child.queue_free()
	
	if selected_recipe == "" || not CraftingSystem.RECIPES.has(selected_recipe):
		return
	
	var recipe = CraftingSystem.RECIPES[selected_recipe]
	
	# 名称
	var name_label = Label.new()
	name_label.text = recipe.name
	name_label.add_theme_font_size_override("font_size", 20)
	recipe_details.add_child(name_label)
	
	# 描述
	var desc_label = Label.new()
	desc_label.text = recipe.description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recipe_details.add_child(desc_label)
	
	# 分隔线
	recipe_details.add_child(HSeparator.new())
	
	# 所需材料
	var materials_title = Label.new()
	materials_title.text = "所需材料:"
	recipe_details.add_child(materials_title)
	
	for material in recipe.materials:
		var has_count = 0
		for item in GameState.inventory_items:
			if item.id == material.item:
				has_count = item.count
				break
		
		var mat_label = Label.new()
		var status = "✓" if has_count >= material.count else "✗"
		mat_label.text = "  %s %s: %d/%d" % [status, material.item, has_count, material.count]
		recipe_details.add_child(mat_label)
	
	# 产出
	var output_label = Label.new()
	output_label.text = "产出: %s x%d" % [recipe.output.item, recipe.output.count]
	recipe_details.add_child(output_label)
	
	# 制作时间
	var time_label = Label.new()
	time_label.text = "制作时间: %.0f秒" % recipe.craft_time
	recipe_details.add_child(time_label)
	
	# 制作按钮
	var craft_button = Button.new()
	craft_button.text = "开始制作"
	
	var check = CraftingSystem.can_craft(selected_recipe)
	craft_button.disabled = not check.can_craft
	
	if not check.can_craft:
		craft_button.text = check.message
	
	craft_button.pressed.connect(_on_craft_pressed)
	recipe_details.add_child(craft_button)

func _on_craft_pressed():
	if selected_recipe == "":
		return
	
	if CraftingSystem.start_crafting(selected_recipe):
		_update_crafting_queue()
		_update_recipe_list()
		_update_recipe_details()

func _update_crafting_queue():
	# 清除队列显示
	for child in crafting_queue_list.get_children():
		child.queue_free()
	
	var queue = CraftingSystem.get_crafting_queue()
	
	if queue.size() == 0:
		progress_bar.visible = false
		var label = Label.new()
		label.text = "制作队列空闲"
		crafting_queue_list.add_child(label)
		return
	
	progress_bar.visible = true
	
	for i in range(queue.size()):
		var item = queue[i]
		var hbox = HBoxContainer.new()
		
		var name_label = Label.new()
		name_label.text = item.recipe.name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)
		
		if i == 0 && CraftingSystem.is_crafting:
			# 正在制作的显示进度
			var progress = CraftingSystem.get_crafting_progress() * 100
			var progress_label = Label.new()
			progress_label.text = "%.0f%%" % progress
			hbox.add_child(progress_label)
		else:
			# 队列中的可以取消
			var cancel_button = Button.new()
			cancel_button.text = "取消"
			cancel_button.pressed.connect(_on_cancel_craft.bind(i))
			hbox.add_child(cancel_button)
		
		crafting_queue_list.add_child(hbox)

func _on_cancel_craft():
	CraftingSystem.cancel_crafting(index)
	_update_crafting_queue()
	_update_recipe_list()

func _on_crafting_started():
	_update_crafting_queue()
	DialogModule.show_dialog(
		"开始制作: %s (%.0f秒)" % [CraftingSystem.RECIPES[recipe_id].name, craft_time],
		"制作",
		""
	)

func _on_crafting_completed(recipe_id: String):
	_update_crafting_queue()
	DialogModule.show_dialog(
		"制作完成: %s x%d" % [item_id, count],
		"制作",
		""
	)

func _on_recipe_unlocked():
	if crafting_panel.visible:
		_update_recipe_list()
	
	DialogModule.show_dialog(
		"解锁新配方: %s" % CraftingSystem.RECIPES[recipe_id].name,
		"制作",
		""
	)

func _input():
	if event is InputEventKey:
		if event.pressed && event.keycode == KEY_C:
			_on_toggle_pressed()
