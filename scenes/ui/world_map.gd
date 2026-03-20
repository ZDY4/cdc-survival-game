extends CanvasLayer
class_name WorldMap
## 大地图场景
## 包含背景图和拖放的 MapLocation Actor

signal location_selected(location_id: String, button: MapLocation)
signal travel_confirmed(from_id: String, to_id: String)
signal map_closed

@onready var background: TextureRect = $Background
@onready var locations_container: Control = $LocationsContainer
@onready var info_panel: Panel = $InfoPanel
@onready var preview_title: Label = $InfoPanel/TitleLabel
@onready var time_label: Label = $InfoPanel/TimeLabel
@onready var food_label: Label = $InfoPanel/FoodLabel
@onready var risk_label: Label = $InfoPanel/RiskLabel
@onready var travel_button: Button = $InfoPanel/TravelButton
@onready var close_button: Button = $CloseButton

var _selected_location: String = ""
var _current_location_button: MapLocation = null

func _ready():
	_setup_ui()
	_refresh_locations()
	info_panel.hide()

func _setup_ui():
	# 连接按钮信号
	travel_button.pressed.connect(_on_travel_pressed)
	close_button.pressed.connect(_on_close_pressed)
	travel_button.text = "改用场景内入口"
	
	# 连接地点选择信号
	location_selected.connect(_on_location_selected)

## 刷新所有地点显示（用于解锁状态变化）
func _refresh_locations():
	for child in locations_container.get_children():
		if child is MapLocation:
			child.refresh()

func _on_location_selected(location_id: String, button: MapLocation):
	_selected_location = location_id
	_current_location_button = button
	
	# 检查是否已解锁
	if not button.is_unlocked():
		_show_locked_info(location_id)
		return
	
	# 计算移动消耗
	var current = GameState.player_position if GameState else "safehouse"
	var cost = MapModule._calculate_travel_cost(current, location_id)
	
	_update_info_panel(button.get_location_name(), cost)
	info_panel.show()

func _show_locked_info(location_id: String):
	preview_title.text = "未解锁"
	time_label.text = "该地点尚未解锁"
	food_label.text = "完成任务或探索以解锁"
	risk_label.text = ""
	travel_button.disabled = true
	info_panel.show()

func _update_info_panel(dest_name: String, cost: Dictionary):
	preview_title.text = "前往: %s" % dest_name
	
	# 时间
	var time_hours = cost.time_hours
	var time_text = ""
	if time_hours < 1:
		time_text = "%.0f 分钟" % (time_hours * 60)
	else:
		time_text = "%.1f 小时" % time_hours
	time_label.text = "所需时间: %s" % time_text
	
	# 食物
	var food_cost = cost.food_cost
	var food_count = 0
	if InventoryModule:
		food_count = InventoryModule.get_item_count("food_canned")
	
	food_label.text = "食物消耗: %d (拥有: %d)" % [food_cost, food_count]
	if food_count < food_cost:
		food_label.modulate = Color(0.9, 0.2, 0.2)
		travel_button.disabled = true
	else:
		food_label.modulate = Color.WHITE
		travel_button.disabled = true
	
	# 风险
	var risk = cost.risk_level
	var risk_text = ""
	match int(risk):
		0: risk_text = "安全"
		1, 2: risk_text = "低"
		3: risk_text = "中"
		4: risk_text = "高"
		_: risk_text = "极高"
	risk_label.text = "风险等级: %s" % risk_text
	
	match int(risk):
		0, 1, 2: risk_label.modulate = Color(0.2, 0.9, 0.2)
		3: risk_label.modulate = Color(0.9, 0.9, 0.2)
		_: risk_label.modulate = Color(0.9, 0.2, 0.2)

func _on_travel_pressed():
	if DialogModule:
		DialogModule.show_dialog(
			"正式旅行已切换为独立的大地图场景，请在小地图内通过交互点进入大地图后移动。",
			"地图提示",
			""
		)

func _on_close_pressed():
	map_closed.emit()
	hide_map()

func show_map():
	show()
	_refresh_locations()
	info_panel.hide()
	
	# 高亮当前位置
	_highlight_current_location()

func hide_map():
	hide()

func _highlight_current_location():
	var current = GameState.player_position if GameState else "safehouse"
	
	for child in locations_container.get_children():
		if child is MapLocation:
			if child.location_id == current:
				# 添加高亮效果
				child.modulate = Color(1.2, 1.2, 1.2)
			else:
				child.modulate = Color.WHITE
