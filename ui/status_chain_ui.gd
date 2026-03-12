extends Control
class_name StatusChainUI
# StatusChainUI - 生存状态链可视化UI
# 显示饥饿→体温→免疫力→恢复速度的影响链条

# ===== 节点引用 =====
@onready var chain_container: HBoxContainer = $ChainContainer
@onready var warning_panel: Panel = $WarningPanel
@onready var warning_label: Label = $WarningPanel/WarningLabel
var status_nodes: Dictionary = {}

# ===== 状态颜色 =====
const COLOR_GOOD: Color = Color(0.2, 0.8, 0.2)      # 绿色
const COLOR_WARNING: Color = Color(0.9, 0.7, 0.1)   # 黄色
const COLOR_DANGER: Color = Color(0.9, 0.2, 0.2)    # 红色
const COLOR_NEUTRAL: Color = Color(0.6, 0.6, 0.6)   # 灰色

# ===== 状态引用 =====
var _survival_status: Node = null
var _game_state: Node = null

func _ready():
	# 获取系统引用
	_survival_status = get_node_or_null("/root/SurvivalStatusSystem")
	_game_state = get_node_or_null("/root/GameState")
	
	# 创建状态链UI
	_create_status_chain()
	
	# 连接信号
	if _survival_status:
		_survival_status.status_chain_updated.connect(_on_chain_updated)
		_survival_status.status_warning_triggered.connect(_on_status_warning)
	
	if _game_state:
		# 假设EventBus有状态变化信号
		EventBus.connect(EventBus.EventType.STATUS_CHANGED, _on_status_changed)
	
	# 初始更新
	_update_display()

func _create_status_chain():
	# 清空容器
	for child in chain_container.get_children():
		child.queue_free()
	
	# 创建状态节点
	_create_status_node("hunger", "饥饿")
	_create_arrow()
	_create_status_node("temperature", "体温")
	_create_arrow()
	_create_status_node("immunity", "免疫力")
	_create_arrow()
	_create_status_node("regeneration", "恢复速度")

func _create_status_node(id: String, label: String):
	var panel = PanelContainer.new()
	panel.name = id + "_panel"
	panel.custom_minimum_size = Vector2(100, 80)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	var name_label = Label.new()
	name_label.text = label
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	var value_label = Label.new()
	value_label.name = "ValueLabel"
	value_label.text = "--"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(value_label)
	
	var status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "正常"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.modulate = COLOR_NEUTRAL
	vbox.add_child(status_label)
	
	chain_container.add_child(panel)
	status_nodes[id] = panel

func _create_arrow():
	var arrow = Label.new()
	arrow.text = "→"
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.custom_minimum_size = Vector2(30, 80)
	arrow.add_theme_font_size_override("font_size", 24)
	chain_container.add_child(arrow)

func _update_display():
	if not _game_state or not _survival_status:
		return
	
	# 更新饥饿
	_update_node("hunger", _game_state.player_hunger, "", _get_hunger_status())
	
	# 更新体温
	var temp = _survival_status.body_temperature
	var temp_status = _survival_status.get_temperature_status()
	_update_node("temperature", int(temp), "°C", temp_status)
	
	# 更新免疫力
	var immunity = _survival_status.immunity
	var immunity_status = _survival_status.get_immunity_status()
	_update_node("immunity", int(immunity), "%", immunity_status)
	
	# 更新恢复速度
	var regen = _survival_status.get_combat_modifiers().get("damage_mult", 1.0)
	var regen_percent = int((regen - 1.0) * 100)
	_update_node("regeneration", regen_percent, "%", _get_regen_status(regen))

func _update_node(id: String, value: int, suffix: String, status: String):
	if not status_nodes.has(id):
		return
	
	var panel = status_nodes[id]
	var value_label = panel.get_node("ValueLabel")
	var status_label = panel.get_node("StatusLabel")
	
	value_label.text = str(value) + suffix
	status_label.text = status
	
	# 设置颜色
	var color = _get_status_color(id, value, status)
	status_label.modulate = color
	
	# 添加动画效果
	if color == COLOR_DANGER:
		_add_pulse_animation(panel)
	else:
		_remove_pulse_animation(panel)

func _get_hunger_status() -> String:
	if not _game_state:
		return "未知"
	
	var hunger = _game_state.player_hunger
	if hunger >= 80:
		return "饱腹"
	elif hunger >= 50:
		return "正常"
	elif hunger >= 30:
		return "饥饿"
	elif hunger >= 10:
		return "非常饥饿"
	return " starving"

func _get_regen_status(regen: float) -> String:
	if regen >= 1.1:
		return "极佳"
	elif regen >= 1.0:
		return "良好"
	elif regen >= 0.9:
		return "一般"
	elif regen >= 0.8:
		return "较差"
	return "危险"

func _get_status_color(id: String, value: int, status: String) -> Color:
	match id:
		"hunger":
			if value >= 80:
				return COLOR_GOOD
			elif value >= 50:
				return COLOR_NEUTRAL
			elif value >= 30:
				return COLOR_WARNING
			return COLOR_DANGER
		
		"temperature":
			if status == "体温正常":
				return COLOR_GOOD
			elif value >= 34 and value <= 40:
				return COLOR_WARNING
			return COLOR_DANGER
		
		"immunity":
			if value >= 80:
				return COLOR_GOOD
			elif value >= 50:
				return COLOR_NEUTRAL
			elif value >= 30:
				return COLOR_WARNING
			return COLOR_DANGER
		
		"regeneration":
			if value >= 10:
				return COLOR_GOOD
			elif value >= 0:
				return COLOR_NEUTRAL
			elif value >= -20:
				return COLOR_WARNING
			return COLOR_DANGER
	
	return COLOR_NEUTRAL

func _add_pulse_animation(node: Control):
	# 添加脉冲动画效果
	if not node.has_meta("pulsing"):
		node.set_meta("pulsing", true)
		var tween = create_tween().set_loops()
		tween.tween_property(node, "modulate", Color(1.2, 1.0, 1.0), 0.5)
		tween.tween_property(node, "modulate", Color(1.0, 1.0, 1.0), 0.5)
		node.set_meta("tween", tween)

func _remove_pulse_animation(node: Control):
	if node.has_meta("pulsing"):
		node.remove_meta("pulsing")
		if node.has_meta("tween"):
			var tween = node.get_meta("tween")
			if tween:
				tween.kill()
			node.remove_meta("tween")
		node.modulate = Color(1, 1, 1)

func _on_chain_updated(chain_data: Dictionary):
	_update_display()

func _on_status_changed(data: Dictionary):
	_update_display()

func _on_status_warning(warning_type: String, severity: String):
	# 显示警告
	var warning_text = ""
	match warning_type:
		"temperature":
			warning_text = "体温异常！"
		"hypothermia":
			warning_text = "体温过低，正在受到伤害！"
		"hyperthermia":
			warning_text = "体温过高，正在受到伤害！"
		"immunity":
			warning_text = "免疫力低下，容易感染！"
		"infection":
			warning_text = "你感染了！"
		"fatigue":
			warning_text = "你太疲劳了！"
	
	warning_label.text = warning_text
	warning_panel.show()
	
	# 根据严重程度设置颜色
	match severity:
		"critical":
			warning_panel.modulate = COLOR_DANGER
			warning_label.modulate = Color.WHITE
		"warning":
			warning_panel.modulate = COLOR_WARNING
			warning_label.modulate = Color.BLACK
	
	# 自动隐藏
	await get_tree().create_timer(3.0).timeout
	warning_panel.hide()

# ===== 公共接口 =====
func show_ui():
	show()
	_update_display()

func hide_ui():
	hide()

func toggle():
	if visible:
		hide_ui()
	else:
		show_ui()
