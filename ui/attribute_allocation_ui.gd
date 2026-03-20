extends Control
class_name AttributeAllocationUI
# AttributeAllocationUI - 属性分配界面
# 允许玩家分配属性点到力量/敏捷/体质

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var panel: Panel = $CenterContainer/Panel

# 属性行
@onready var strength_row: HBoxContainer = $CenterContainer/Panel/VBoxContainer/StrengthRow
@onready var agility_row: HBoxContainer = $CenterContainer/Panel/VBoxContainer/AgilityRow
@onready var constitution_row: HBoxContainer = $CenterContainer/Panel/VBoxContainer/ConstitutionRow

# 属性值标签
@onready var strength_value: Label = $CenterContainer/Panel/VBoxContainer/StrengthRow/ValueLabel
@onready var agility_value: Label = $CenterContainer/Panel/VBoxContainer/AgilityRow/ValueLabel
@onready var constitution_value: Label = $CenterContainer/Panel/VBoxContainer/ConstitutionRow/ValueLabel

# 效果标签
@onready var strength_effect: Label = $CenterContainer/Panel/VBoxContainer/StrengthRow/EffectLabel
@onready var agility_effect: Label = $CenterContainer/Panel/VBoxContainer/AgilityRow/EffectLabel
@onready var constitution_effect: Label = $CenterContainer/Panel/VBoxContainer/ConstitutionRow/EffectLabel

# 点数显示
@onready var points_label: Label = $CenterContainer/Panel/VBoxContainer/PointsContainer/PointsLabel

# 按钮
@onready var strength_minus: Button = $CenterContainer/Panel/VBoxContainer/StrengthRow/MinusButton
@onready var strength_plus: Button = $CenterContainer/Panel/VBoxContainer/StrengthRow/PlusButton
@onready var agility_minus: Button = $CenterContainer/Panel/VBoxContainer/AgilityRow/MinusButton
@onready var agility_plus: Button = $CenterContainer/Panel/VBoxContainer/AgilityRow/PlusButton
@onready var constitution_minus: Button = $CenterContainer/Panel/VBoxContainer/ConstitutionRow/MinusButton
@onready var constitution_plus: Button = $CenterContainer/Panel/VBoxContainer/ConstitutionRow/PlusButton

@onready var confirm_button: Button = $CenterContainer/Panel/VBoxContainer/ButtonContainer/ConfirmButton
@onready var reset_button: Button = $CenterContainer/Panel/VBoxContainer/ButtonContainer/ResetButton
@onready var cancel_button: Button = $CenterContainer/Panel/VBoxContainer/ButtonContainer/CancelButton

var attr_system: Node = null
var xp_system: Node = null

# 临时存储（确认前）
var temp_strength: int = 5
var temp_agility: int = 5
var temp_constitution: int = 5
var temp_points: int = 0
var original_points: int = 0

func _ready():
	hide()
	
	# 获取系统引用
	attr_system = get_node_or_null("/root/AttributeSystem")
	xp_system = get_node_or_null("/root/ExperienceSystem")
	
	# 连接按钮信号
	strength_minus.pressed.connect(_on_strength_minus)
	strength_plus.pressed.connect(_on_strength_plus)
	agility_minus.pressed.connect(_on_agility_minus)
	agility_plus.pressed.connect(_on_agility_plus)
	constitution_minus.pressed.connect(_on_constitution_minus)
	constitution_plus.pressed.connect(_on_constitution_plus)
	
	confirm_button.pressed.connect(_on_confirm)
	reset_button.pressed.connect(_on_reset)
	cancel_button.pressed.connect(_on_cancel)

func show_ui():
	if not attr_system or not xp_system:
		push_error("[AttributeAllocationUI] Required systems not found")
		return
	
	# 保存当前状态
	temp_strength = int(attr_system.get_actor_attribute("player", "strength"))
	temp_agility = int(attr_system.get_actor_attribute("player", "agility"))
	temp_constitution = int(attr_system.get_actor_attribute("player", "constitution"))
	
	# 获取可用属性点
	var points = xp_system.get_available_points()
	temp_points = points.stat_points
	original_points = temp_points
	
	_update_display()
	show()
	
	if animation_player:
		animation_player.play("show")
	
	# 暂停时间
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager:
		time_manager.pause_time()

func _update_display():
	# 更新属性值
	strength_value.text = str(temp_strength)
	agility_value.text = str(temp_agility)
	constitution_value.text = str(temp_constitution)
	
	# 更新效果描述
	if attr_system:
		strength_effect.text = "+%d%%伤害, +%d负重" % [
			int((temp_strength - 5) * 5),
			(temp_strength - 5) * 10
		]
		agility_effect.text = "+%d%%闪避, +%d%%暴击" % [
			int((temp_agility - 5) * 2),
			int((temp_agility - 5) * 1)
		]
		constitution_effect.text = "+%dHP, +%d%%减伤" % [
			(temp_constitution - 5) * 10,
			int((temp_constitution - 5) * 1)
		]
	
	# 更新点数
	points_label.text = "可用属性点: %d" % temp_points
	points_label.add_theme_color_override("font_color", Color.GREEN if temp_points > 0 else Color.GRAY)
	
	# 更新按钮状态
	var current_strength: int = int(attr_system.get_actor_attribute("player", "strength"))
	var current_agility: int = int(attr_system.get_actor_attribute("player", "agility"))
	var current_constitution: int = int(attr_system.get_actor_attribute("player", "constitution"))
	strength_minus.disabled = (temp_strength <= current_strength)
	strength_plus.disabled = (temp_points <= 0 or temp_strength >= 20)
	
	agility_minus.disabled = (temp_agility <= current_agility)
	agility_plus.disabled = (temp_points <= 0 or temp_agility >= 20)
	
	constitution_minus.disabled = (temp_constitution <= current_constitution)
	constitution_plus.disabled = (temp_points <= 0 or temp_constitution >= 20)
	
	confirm_button.disabled = (temp_points == original_points)  # 没有变化时禁用确认

# ===== 按钮处理 =====

func _on_strength_plus():
	if temp_points > 0 and temp_strength < 20:
		temp_strength += 1
		temp_points -= 1
		_update_display()

func _on_strength_minus():
	if temp_strength > int(attr_system.get_actor_attribute("player", "strength")):
		temp_strength -= 1
		temp_points += 1
		_update_display()

func _on_agility_plus():
	if temp_points > 0 and temp_agility < 20:
		temp_agility += 1
		temp_points -= 1
		_update_display()

func _on_agility_minus():
	if temp_agility > int(attr_system.get_actor_attribute("player", "agility")):
		temp_agility -= 1
		temp_points += 1
		_update_display()

func _on_constitution_plus():
	if temp_points > 0 and temp_constitution < 20:
		temp_constitution += 1
		temp_points -= 1
		_update_display()

func _on_constitution_minus():
	if temp_constitution > int(attr_system.get_actor_attribute("player", "constitution")):
		temp_constitution -= 1
		temp_points += 1
		_update_display()

func _on_reset():
	temp_strength = int(attr_system.get_actor_attribute("player", "strength"))
	temp_agility = int(attr_system.get_actor_attribute("player", "agility"))
	temp_constitution = int(attr_system.get_actor_attribute("player", "constitution"))
	temp_points = original_points
	_update_display()

func _on_confirm():
	var current_strength: int = int(attr_system.get_actor_attribute("player", "strength"))
	var current_agility: int = int(attr_system.get_actor_attribute("player", "agility"))
	var current_constitution: int = int(attr_system.get_actor_attribute("player", "constitution"))
	var delta_map := {
		"strength": maxi(0, temp_strength - current_strength),
		"agility": maxi(0, temp_agility - current_agility),
		"constitution": maxi(0, temp_constitution - current_constitution)
	}
	var points_spent: int = int(delta_map.get("strength", 0)) + int(delta_map.get("agility", 0)) + int(delta_map.get("constitution", 0))
	var result: Dictionary = attr_system.allocate_player_attributes(delta_map)
	if not bool(result.get("success", false)):
		push_warning("[AttributeAllocationUI] 属性分配失败: %s" % str(result.get("reason", "unknown")))
		return
	
	print("[AttributeAllocationUI] 已分配 %d 属性点" % points_spent)
	
	_close_ui()

func _on_cancel():
	_close_ui()

func _close_ui():
	hide()
	
	# 恢复时间
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager:
		time_manager.resume_time()
