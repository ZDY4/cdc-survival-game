extends Control
# InventoryUI - 背包界面
# 显示物品列表和重量信息

@onready var item_list = $Panel/ItemList
@onready var weight_label = $Panel/WeightLabel
@onready var encumbrance_icon = $Panel/EncumbranceIcon
@onready var close_button = $Panel/CloseButton

const ENCUMBRANCE_COLORS = {
	0: Color.WHITE,      # 轻载
	1: Color.YELLOW,     # 中载
	2: Color.ORANGE,     # 重载
	3: Color.RED,        # 超载
	4: Color.DARK_RED    # 完全超载
}

const ENCUMBRANCE_ICONS = {
	0: "🟢",  # 轻载
	1: "🟡",  # 中载
	2: "🟠",  # 重载
	3: "🔴",  # 超载
	4: "⚫"   # 完全超载
}

func _ready():
	close_button.pressed.connect(_on_close)
	_update_weight_display()
	
	# 连接负重变化信号
	if CarrySystem:
		CarrySystem.weight_changed.connect(_on_weight_changed)
		CarrySystem.encumbrance_changed.connect(_on_encumbrance_changed)
	
	# 应用响应式UI
	_apply_responsive_ui()
	
	# 应用安全区域
	if ResponsiveUIManager:
		ResponsiveUIManager.apply_safe_area($Panel, 10)
	
	# 添加触摸支持
	if TouchInputHandler:
		TouchInputHandler.touch_pressed.connect(_on_touch_pressed)
	
	# 设置关闭按钮移动端样式
	if ResponsiveUIManager and ResponsiveUIManager.is_mobile():
		ResponsiveUIManager.apply_mobile_button_style(close_button)

func _update_weight_display():
	if not CarrySystem:
		return
	
	var current = CarrySystem.get_current_weight()
	var max_weight = CarrySystem.get_max_carry_weight()
	var ratio = CarrySystem.get_weight_ratio()
	var level = CarrySystem.get_encumbrance_level()
	
	# 更新重量标签
	weight_label.text = "%.1f/%.1f kg" % [current, max_weight]
	
	# 根据负重等级设置颜色
	var color = ENCUMBRANCE_COLORS.get(level, Color.WHITE)
	weight_label.modulate = color
	
	# 更新图标
	encumbrance_icon.text = ENCUMBRANCE_ICONS.get(level, "⚪")
	
	# 超重警告
	if level >= 3:  # 超载或完全超载
		weight_label.text += " ⚠️ 超重!"

func _on_weight_changed():
	_update_weight_display()

func _on_encumbrance_changed():
	_update_weight_display()

func _on_close():
	hide()

func show_ui():
	_refresh_item_list()
	_update_weight_display()
	show()

func _refresh_item_list(type: String = ""):
	item_list.clear()
	
	if not GameState:
		return
	
	for item in GameState.inventory_items:
		var item_id = item.get("id", "")
		var count = item.get("count", 1)
		var item_name = _get_item_name(item_id)
		var weight = CarrySystem ? CarrySystem.get_item_weight(item_id) : 0.1
		
		var display_text = "%s x%d (%.1fkg)" % [item_name, count, weight * count]
		item_list.add_item(display_text)

func _get_item_name(item_id: String = ""):
	# 从统一装备系统获取名称
	if UnifiedEquipmentSystem:
		var data = UnifiedEquipmentSystem.get_item_data(item_id)
		if data && data.has("name"):
			return data.name
	
	# 回退到CraftingSystem
	var crafting_items = CraftingSystem.get("ITEMS")
	if crafting_items && crafting_items.has(item_id):
		return crafting_items[item_id].get("name", item_id)
	
	return item_id

func _apply_responsive_ui():
	if not ResponsiveUIManager:
		return
	
	var is_mobile = ResponsiveUIManager.is_mobile()
	var font_size = ResponsiveUIManager.get_font_size(24)
	
	# 调整标题字体
	$Panel/Title.add_theme_font_size_override("font_size", font_size)
	
	# 调整重量标签
	$Panel/WeightLabel.add_theme_font_size_override("font_size", ResponsiveUIManager.get_font_size(18))
	
	# 移动端调整面板大小
	if is_mobile:
		var panel = $Panel
		if ResponsiveUIManager.is_portrait():
			# 竖屏模式
			panel.offset_left = -180
			panel.offset_right = 180
			panel.offset_top = -300
			panel.offset_bottom = 300
		
		# 增大列表项
		item_list.add_theme_constant_override("icon_max_width", 48)

func _on_touch_pressed(position: Vector2):
	# 触摸空白区域关闭UI
	if visible and not $Panel.get_global_rect().has_point(position):
		_on_close()
