extends Control
class_name TimeDisplayUI
# TimeDisplayUI - 时间显示界面
# 显示在屏幕左上角，显示当前时间和天数

@onready var time_label: Label = $VBoxContainer/TimeLabel
@onready var date_label: Label = $VBoxContainer/DateLabel
@onready var period_label: Label = $VBoxContainer/PeriodLabel
@onready var bg_panel: Panel = $BGPanel

var time_manager: Node = null

func _ready():
	# 获取TimeManager引用
	time_manager = get_node_or_null("/root/TimeManager")
	
	if time_manager:
		# 连接信号
		time_manager.time_advanced.connect(_on_time_advanced)
		time_manager.day_changed.connect(_on_day_changed)
		time_manager.night_fallen.connect(_on_night_fallen)
		time_manager.sunrise.connect(_on_sunrise)
		
		# 初始更新
		_update_display()
	else:
		push_warning("[TimeDisplayUI] TimeManager not found")

func _process(_delta):
	# 每秒更新一次时间显示
	if time_manager and Engine.get_process_frames() % 60 == 0:
		_update_display()

func _update_display():
	if not time_manager:
		return
	
	var time_text = time_manager.get_formatted_time()
	var date_text = "第 %d 天" % time_manager.current_day
	var period_text = time_manager.get_time_period()
	
	if time_label:
		time_label.text = time_text
	if date_label:
		date_label.text = date_text
	if period_label:
		period_label.text = period_text
	
	# 根据昼夜改变样式
	_update_style()

func _update_style():
	if not time_manager:
		return
	
	var is_night = time_manager.is_night()
	
	if bg_panel:
		var style = bg_panel.get_theme_stylebox("panel").duplicate()
		if style is StyleBoxFlat:
			if is_night:
				style.bg_color = Color(0.1, 0.1, 0.2, 0.8)  # 夜晚深蓝色
				style.border_color = Color(0.3, 0.3, 0.5, 1.0)
			else:
				style.bg_color = Color(0.9, 0.9, 0.8, 0.8)  # 白天浅黄色
				style.border_color = Color(0.8, 0.7, 0.4, 1.0)
			bg_panel.add_theme_stylebox_override("panel", style)
	
	# 更新标签颜色
	if time_label:
		time_label.add_theme_color_override("font_color", Color.WHITE if is_night else Color.BLACK)
	if date_label:
		date_label.add_theme_color_override("font_color", Color.WHITE if is_night else Color.BLACK)
	if period_label:
		period_label.add_theme_color_override("font_color", Color.YELLOW if is_night else Color.DARK_BLUE)

# ===== 信号处理 =====

func _on_time_advanced(old_time: Dictionary, new_time: Dictionary):
	_update_display()

func _on_day_changed(new_day: int):
	_update_display()
	_show_day_notification(new_day)

func _on_night_fallen(current_time: Dictionary):
	_update_display()
	_show_night_notification()

func _on_sunrise(current_time: Dictionary):
	_update_display()
	_show_sunrise_notification()

# ===== 通知动画 =====

func _show_day_notification(day: int):
	var tween = create_tween()
	date_label.scale = Vector2(1.5, 1.5)
	date_label.modulate = Color.YELLOW
	tween.tween_property(date_label, "scale", Vector2(1, 1), 0.5)
	tween.tween_property(date_label, "modulate", Color.WHITE, 0.5)

func _show_night_notification():
	var tween = create_tween()
	period_label.scale = Vector2(1.5, 1.5)
	period_label.modulate = Color.RED
	tween.tween_property(period_label, "scale", Vector2(1, 1), 0.5)
	tween.tween_property(period_label, "modulate", Color.YELLOW, 0.5)

func _show_sunrise_notification():
	var tween = create_tween()
	period_label.scale = Vector2(1.5, 1.5)
	period_label.modulate = Color.ORANGE
	tween.tween_property(period_label, "scale", Vector2(1, 1), 0.5)
	tween.tween_property(period_label, "modulate", Color.YELLOW, 0.5)
