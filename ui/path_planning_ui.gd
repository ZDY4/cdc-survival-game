extends Control
class_name PathPlanningUI
# PathPlanningUI - 路径规划界面
# 显示移动成本预览（时间、体力、风险）

# ===== 节点引用 =====
@onready var map_container: Control = $MapContainer
@onready var location_buttons: Dictionary = {}
@onready var path_preview: Panel = $PathPreview
@onready var preview_title: Label = $PathPreview/PreviewTitle
@onready var time_label: Label = $PathPreview/TimeLabel
@onready var stamina_label: Label = $PathPreview/StaminaLabel
@onready var risk_label: Label = $PathPreview/RiskLabel
@onready var total_info_label: Label = $PathPreview/TotalInfoLabel
@onready var travel_button: Button = $PathPreview/TravelButton
@onready var cancel_button: Button = $PathPreview/CancelButton
@onready var current_location_label: Label = $CurrentLocationLabel

# ===== 状态 =====
var _map_module: Node = null
var _selected_destination: String = ""
var _current_path: Array = []
var _path_cost: Dictionary = {}

# ===== 地点位置配置（用于可视化）=====
const LOCATION_POSITIONS: Dictionary = {
	"safehouse": Vector2(400, 300),
	"street_a": Vector2(300, 250),
	"street_b": Vector2(500, 250),
	"supermarket": Vector2(200, 200),
	"hospital": Vector2(250, 350),
	"factory": Vector2(350, 400),
	"subway": Vector2(600, 300),
	"school": Vector2(550, 150),
	"forest": Vector2(450, 500),
	"ruins": Vector2(700, 350)
}

const LOCATION_COLORS: Dictionary = {
	"safehouse": Color(0.2, 0.8, 0.2),      # 绿色 - 安全
	"street": Color(0.9, 0.7, 0.1),         # 黄色 - 街道
	"supermarket": Color(0.4, 0.6, 0.9),    # 蓝色 - 建筑
	"hospital": Color(0.4, 0.9, 0.9),       # 青色 - 医院
	"factory": Color(0.9, 0.5, 0.2),        # 橙色 - 工厂
	"subway": Color(0.6, 0.3, 0.8),         # 紫色 - 地下
	"school": Color(0.9, 0.4, 0.6),         # 粉色 - 学校
	"forest": Color(0.2, 0.6, 0.2),         # 深绿 - 森林
	"ruins": Color(0.5, 0.5, 0.5)           # 灰色 - 废墟
}

func _ready():
	_map_module = get_node_or_null("/root/MapModule")
	
	travel_button.pressed.connect(_on_travel_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	
	_create_map_visualization()
	
	path_preview.hide()

func _create_map_visualization():
	# 清除现有内容
	for child in map_container.get_children():
		child.queue_free()
	location_buttons.clear()
	
	# 绘制连接线
	_draw_connections()
	
	# 创建地点按钮
	for location_id in LOCATION_POSITIONS.keys():
		var pos = LOCATION_POSITIONS[location_id]
		var btn = Button.new()
		
		btn.position = pos - Vector2(25, 25)
		btn.size = Vector2(50, 50)
		btn.text = _get_location_short_name(location_id)
		btn.tooltip_text = _get_location_full_name(location_id)
		
		# 设置颜色
		var color = _get_location_color(location_id)
		var style = StyleBoxFlat.new()
		style.bg_color = color
		style.corner_radius_top_left = 25
		style.corner_radius_top_right = 25
		style.corner_radius_bottom_left = 25
		style.corner_radius_bottom_right = 25
		btn.add_theme_stylebox_override("normal", style)
		
		# 当前地点高亮
		if GameState and GameState.player_position == location_id:
			var current_style = style.duplicate()
			current_style.border_width_left = 4
			current_style.border_width_top = 4
			current_style.border_width_right = 4
			current_style.border_width_bottom = 4
			current_style.border_color = Color.WHITE
			btn.add_theme_stylebox_override("normal", current_style)
		
		btn.pressed.connect(func(): _on_location_selected(location_id))
		
		map_container.add_child(btn)
		location_buttons[location_id] = btn

func _draw_connections():
	# 绘制地点之间的连接线
	var connections = MapModule.LOCATION_CONNECTIONS
	
	for from_loc in connections.keys():
		if not LOCATION_POSITIONS.has(from_loc):
			continue
		
		var from_pos = LOCATION_POSITIONS[from_loc]
		
		for to_loc in connections[from_loc]:
			if not LOCATION_POSITIONS.has(to_loc):
				continue
			
			var to_pos = LOCATION_POSITIONS[to_loc]
			
			# 创建线条
			var line = Line2D.new()
			line.points = [from_pos, to_pos]
			line.default_color = Color(0.4, 0.4, 0.4, 0.5)
			line.width = 2
			map_container.add_child(line)

func _get_location_short_name(location_id: String) -> String:
	var names = {
		"safehouse": "安全",
		"street_a": "街A",
		"street_b": "街B",
		"supermarket": "超市",
		"hospital": "医院",
		"factory": "工厂",
		"subway": "地铁",
		"school": "学校",
		"forest": "森林",
		"ruins": "废墟"
	}
	return names.get(location_id, "?")

func _get_location_full_name(location_id: String) -> String:
	var data = MapModule._get_location_data().get(location_id, {})
	return data.get("name", location_id)

func _get_location_color(location_id: String) -> Color:
	# 根据地点类型返回颜色
	if location_id == "safehouse":
		return LOCATION_COLORS["safehouse"]
	elif location_id.begins_with("street"):
		return LOCATION_COLORS["street"]
	elif location_id in LOCATION_COLORS:
		return LOCATION_COLORS[location_id]
	return Color.GRAY

func show_ui():
	show()
	_update_current_location()
	_create_map_visualization()
	path_preview.hide()

func _update_current_location():
	if GameState:
		var current = GameState.player_position
		current_location_label.text = "当前位置: %s" % _get_location_full_name(current)

func _on_location_selected(location_id: String):
	if not GameState:
		return
	
	var current = GameState.player_position
	
	if location_id == current:
		return
	
	_selected_destination = location_id
	_current_path = [current, location_id]  # 简化为直接路径
	
	# 计算移动消耗
	_path_cost = MapModule._calculate_travel_cost(current, location_id)
	
	# 更新预览
	_update_path_preview()
	
	# 高亮路径
	_highlight_path()

func _update_path_preview():
	path_preview.show()
	
	var dest_name = _get_location_full_name(_selected_destination)
	preview_title.text = "前往: %s" % dest_name
	
	# 时间
	var time_hours = _path_cost.time_hours
	var time_text = ""
	if time_hours < 1:
		time_text = "%.0f 分钟" % (time_hours * 60)
	else:
		time_text = "%.1f 小时" % time_hours
	time_label.text = "所需时间: %s" % time_text
	
	# 食物消耗
	var food_cost = _path_cost.food_cost
	var food_label_text = "食物消耗: %d" % food_cost
	if GameState and InventoryModule:
		var food_count = InventoryModule.get_item_count("food_canned")
		food_label_text += " (拥有: %d)" % food_count
		if food_count < food_cost:
			stamina_label.modulate = Color(0.9, 0.2, 0.2)  # 红色表示不足
		else:
			stamina_label.modulate = Color.WHITE
	stamina_label.text = food_label_text
	
	# 风险
	var risk = _path_cost.risk_level
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
	
	# 距离信息
	total_info_label.text = "距离: %.1f 单位" % _path_cost.distance
	
	# 检查是否可以出发（食物是否足够）
	var can_travel = true
	if InventoryModule:
		can_travel = InventoryModule.has_item("food_canned", food_cost)
	
	travel_button.disabled = not can_travel

func _highlight_path():
	# 清除之前的高亮
	_create_map_visualization()
	
	if _current_path.size() < 2:
		return
	
	# 绘制直接路径线（从当前位置到目的地）
	var from_loc = _current_path[0]
	var to_loc = _current_path[_current_path.size() - 1]
	
	if LOCATION_POSITIONS.has(from_loc) and LOCATION_POSITIONS.has(to_loc):
		var from_pos = LOCATION_POSITIONS[from_loc]
		var to_pos = LOCATION_POSITIONS[to_loc]
		
		var line = Line2D.new()
		line.points = [from_pos, to_pos]
		line.default_color = Color(0.9, 0.9, 0.2)
		line.width = 4
		map_container.add_child(line)
	
	# 高亮目的地按钮
	if location_buttons.has(_selected_destination):
		var btn = location_buttons[_selected_destination]
		var style = btn.get_theme_stylebox("normal").duplicate()
		style.border_width_left = 4
		style.border_width_top = 4
		style.border_width_right = 4
		style.border_width_bottom = 4
		style.border_color = Color(0.9, 0.9, 0.2)
		btn.add_theme_stylebox_override("normal", style)

func _on_travel_pressed():
	if _selected_destination.is_empty():
		return
	
	# 执行移动
	if MapModule:
		var success = MapModule.travel_to(_selected_destination)
		if success:
			hide()

func _on_cancel_pressed():
	path_preview.hide()
	_selected_destination = ""
	_current_path = []
	_create_map_visualization()

func _show_error(message: String):
	var dialog = AcceptDialog.new()
	dialog.title = "错误"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

func hide_ui():
	hide()
