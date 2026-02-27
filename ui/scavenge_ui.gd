extends Control
class_name ScavengeUI
# ScavengeUI - 搜刮系统UI
# 工具选择、时间滑块、风险预览界面

# ===== 节点引用 =====
@onready var location_label: Label = $Panel/LocationLabel
@onready var tool_container: VBoxContainer = $Panel/ToolSelection/ToolContainer
@noload var time_slider: Slider
@onready var time_label: Label = $Panel/TimeSelection/TimeLabel
@onready var preview_panel: Panel = $Panel/PreviewPanel
@onready var yield_label: Label = $Panel/PreviewPanel/YieldLabel
@onready var risk_label: Label = $Panel/PreviewPanel/RiskLabel
@onready var noise_label: Label = $Panel/PreviewPanel/NoiseLabel
@onready var search_button: Button = $Panel/SearchButton
@onready var result_panel: Panel = $ResultPanel
@onready var result_label: Label = $ResultPanel/ResultLabel
@onready var items_container: VBoxContainer = $ResultPanel/ItemsContainer
@onready var event_panel: Panel = $EventPanel
@onready var event_label: Label = $EventPanel/EventLabel
@onready var choices_container: VBoxContainer = $EventPanel/ChoicesContainer

# ===== 状态 =====
var _current_location: String = ""
var _selected_tool: String = "hands"
var _selected_time: int = 4
var _scavenge_system: Node = null
var _tool_buttons: Dictionary = {}

func _ready():
	_scavenge_system = get_node_or_null("/root/ScavengeSystem")
	
	# 获取节点引用
	time_slider = $Panel/TimeSelection/TimeSlider
	
	# 设置时间滑块
	if time_slider:
		time_slider.min_value = 2
		time_slider.max_value = 6
		time_slider.step = 2
		time_slider.value = 4
		time_slider.value_changed.connect(_on_time_changed)
	
	# 连接按钮信号
	search_button.pressed.connect(_on_search_pressed)
	
	# 创建工具选择按钮
	_create_tool_buttons()
	
	# 隐藏结果和事件面板
	result_panel.hide()
	event_panel.hide()
	
	# 初始更新
	_update_preview()

func _create_tool_buttons():
	# 清除现有按钮
	for child in tool_container.get_children():
		child.queue_free()
	_tool_buttons.clear()
	
	if not _scavenge_system:
		return
	
	var tools = _scavenge_system.get_available_tools()
	
	for tool in tools:
		var btn = Button.new()
		btn.text = tool.name
		btn.tooltip_text = tool.description
		btn.toggle_mode = true
		btn.button_group = ButtonGroup.new()
		btn.disabled = not tool.has_tool
		
		# 设置初始状态
		if tool.id == _selected_tool:
			btn.button_pressed = true
		
		btn.pressed.connect(func(): _on_tool_selected(tool.id))
		
		tool_container.add_child(btn)
		_tool_buttons[tool.id] = btn

func show_ui(location: String):
	_current_location = location
	location_label.text = "搜索地点: %s" % _get_location_name(location)
	
	# 重置选择
	_selected_tool = "hands"
	_selected_time = 4
	
	# 更新UI
	_update_tool_selection()
	if time_slider:
		time_slider.value = _selected_time
	_update_preview()
	
	# 显示UI
	show()

func _get_location_name(location_id: String) -> String:
	var names = {
		"supermarket": "超市",
		"hospital": "医院",
		"street_a": "街道A",
		"street_b": "街道B",
		"factory": "工厂",
		"subway": "地铁站",
		"safehouse": "安全屋"
	}
	return names.get(location_id, location_id)

func _on_tool_selected(tool_id: String):
	_selected_tool = tool_id
	_update_tool_selection()
	_update_preview()

func _update_tool_selection():
	for tool_id in _tool_buttons.keys():
		var btn = _tool_buttons[tool_id]
		btn.button_pressed = (tool_id == _selected_tool)

func _on_time_changed(value: float):
	_selected_time = int(value)
	match _selected_time:
		2:
			time_label.text = "快速搜索 (2小时)"
		4:
			time_label.text = "标准搜索 (4小时)"
		6:
			time_label.text = "彻底搜索 (6小时)"
	_update_preview()

func _update_preview():
	if not _scavenge_system:
		return
	
	var config = _scavenge_system.prepare_search(_current_location, _selected_tool, _selected_time)
	
	# 更新预期收益
	var yield_data = config.expected_yield
	yield_label.text = "预期收益: %d-%d 物品 (稀有率: %.0f%%)" % [
		yield_data.min_items,
		yield_data.max_items,
		yield_data.rare_chance * 100
	]
	
	# 更新风险
	var risk_data = config.noise_risk
	risk_label.text = "遭遇风险: %s (%.0f%%)" % [
		_get_risk_level_name(risk_data.risk_level),
		risk_data.enemy_attract_chance * 100
	]
	
	# 更新噪音
	noise_label.text = "噪音等级: %.1f/5.0" % [risk_data.noise_level]
	
	# 根据风险设置颜色
	match risk_data.risk_level:
		"low":
			risk_label.modulate = Color(0.2, 0.8, 0.2)
		"medium":
			risk_label.modulate = Color(0.9, 0.7, 0.1)
		"high", "extreme":
			risk_label.modulate = Color(0.9, 0.2, 0.2)

func _get_risk_level_name(level: String) -> String:
	match level:
		"low": return "低"
		"medium": return "中"
		"high": return "高"
		"extreme": return "极高"
	return "未知"

func _on_search_pressed():
	if not _scavenge_system:
		return
	
	search_button.disabled = true
	search_button.text = "搜索中..."
	
	var config = _scavenge_system.prepare_search(_current_location, _selected_tool, _selected_time)
	var results = _scavenge_system.execute_search(config)
	
	# 显示结果
	_show_results(results)
	
	search_button.disabled = false
	search_button.text = "开始搜索"

func _show_results(results: Dictionary):
	result_panel.show()
	event_panel.hide()
	
	if results.success:
		result_label.text = "搜索完成！耗时 %d 小时" % results.search_time
		result_label.modulate = Color(0.2, 0.8, 0.2)
	else:
		result_label.text = "搜索失败: %s" % results.get("reason", "未知原因")
		result_label.modulate = Color(0.9, 0.2, 0.2)
	
	# 清空并填充物品列表
	for child in items_container.get_children():
		child.queue_free()
	
	if results.items_found.is_empty():
		var no_items = Label.new()
		no_items.text = "没有找到物品"
		items_container.add_child(no_items)
	else:
		for item in results.items_found:
			var item_label = Label.new()
			var rarity_color = _get_rarity_color(item.rarity)
			item_label.text = "• %s x%d" % [item.id, item.count]
			item_label.modulate = rarity_color
			items_container.add_child(item_label)
	
	# 处理事件
	if not results.events.is_empty():
		_show_event(results.events[0])

func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(0.8, 0.8, 0.8)
		"uncommon": return Color(0.2, 0.8, 0.2)
		"rare": return Color(0.2, 0.4, 0.9)
	return Color.WHITE

func _show_event(event_data: Dictionary):
	event_panel.show()
	event_label.text = "【%s】\n%s" % [event_data.name, event_data.description]
	
	# 清空并填充选择按钮
	for child in choices_container.get_children():
		child.queue_free()
	
	if event_data.has("choices"):
		for choice in event_data.choices:
			var btn = Button.new()
			var risk_text = ""
			if choice.risk > 0:
				risk_text = " [风险: %d%%]" % int(choice.risk * 100)
			
			btn.text = choice.text + risk_text
			btn.pressed.connect(func(): _on_event_choice(choice, event_data))
			
			# 根据风险设置颜色
			if choice.risk > 0.5:
				btn.modulate = Color(0.9, 0.3, 0.3)
			elif choice.risk > 0.2:
				btn.modulate = Color(0.9, 0.7, 0.1)
			
			choices_container.add_child(btn)

func _on_event_choice(choice: Dictionary, event_data: Dictionary):
	# 处理事件选择
	var result_text = ""
	
	# 风险判定
	if choice.risk > 0 and randf() < choice.risk:
		# 不好的结果
		result_text = _handle_bad_event_result(event_data, choice)
	else:
		# 好的结果
		result_text = _handle_good_event_result(event_data, choice)
	
	# 显示结果
	var result_dialog = AcceptDialog.new()
	result_dialog.title = "事件结果"
	result_dialog.dialog_text = result_text
	result_dialog.ok_button_text = "确定"
	add_child(result_dialog)
	result_dialog.popup_centered()
	result_dialog.confirmed.connect(func(): result_dialog.queue_free())
	
	# 关闭事件面板
	event_panel.hide()

func _handle_good_event_result(event_data: Dictionary, choice: Dictionary) -> String:
	match event_data.id:
		"creaking_floor":
			return "你小心地移动，没有引起更多注意。"
		"hidden_room":
			if choice.text == "强行破开":
				GameState.add_item("rare_loot", 1)
				return "你成功打开了隐藏房间，发现了稀有物资！"
			return "你找到了隐藏入口，获得了一些额外物资。"
		"valuable_discovered":
			GameState.add_item("valuable_item", 1)
			return "你获得了贵重物品！"
		"supply_cache":
			GameState.add_item("food", 3)
			return "你获得了3份食物。"
		"locked_safe":
			GameState.add_item("valuable_loot", 2)
			return "你成功打开了保险箱！"
		_:
			return choice.get("reward", "事件解决")

func _handle_bad_event_result(event_data: Dictionary, choice: Dictionary) -> String:
	match event_data.id:
		"trap_triggered":
			var damage = randi_range(5, 15)
			GameState.damage_player(damage)
			return "你受伤了，受到 %d 点伤害！" % damage
		"collapsing_structure":
			var damage = randi_range(10, 25)
			GameState.damage_player(damage)
			return "建筑物倒塌，你受到 %d 点伤害！" % damage
		"other_survivor":
			if choice.text == "尝试交流":
				GameState.damage_player(10)
				return "对方不友好，你受到攻击，损失10点HP！"
			return "你被发现并遭到攻击！"
		"wild_animal":
			GameState.damage_player(15)
			return "野兽攻击了你，损失15点HP！"
		_:
			return "情况变糟了，但你还活着。"

func hide_ui():
	hide()

func _on_close_pressed():
	hide_ui()
