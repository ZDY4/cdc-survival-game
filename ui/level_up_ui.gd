extends Control
class_name LevelUpUI
# LevelUpUI - 升级提示界面
# 当玩家升级时弹出，显示升级奖励

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var panel: Panel = $CenterContainer/Panel
@onready var title_label: Label = $CenterContainer/Panel/VBoxContainer/TitleLabel
@onready var level_label: Label = $CenterContainer/Panel/VBoxContainer/LevelLabel
@onready var rewards_container: VBoxContainer = $CenterContainer/Panel/VBoxContainer/RewardsContainer
@onready var ok_button: Button = $CenterContainer/Panel/VBoxContainer/OKButton

var xp_system: Node = null
var pending_rewards: Dictionary = {}

func _ready():
	hide()
	
	# 获取ExperienceSystem引用
	xp_system = get_node_or_null("/root/ExperienceSystem")
	
	if xp_system:
		xp_system.level_up.connect(_on_level_up)
	
	if ok_button:
		ok_button.pressed.connect(_on_ok_pressed)

func _on_level_up(new_level: int, rewards: Dictionary):
	pending_rewards = rewards
	_show_level_up(new_level, rewards)

func _show_level_up(level: int, rewards: Dictionary):
	# 更新显示
	if title_label:
		title_label.text = "升级！"
	
	if level_label:
		level_label.text = "等级 %d" % level
	
	# 清空并添加奖励项
	if rewards_container:
		for child in rewards_container.get_children():
			child.queue_free()
		
		# 属性点
		if rewards.get("stat_points", 0) > 0:
			_add_reward_item("🎁 属性点 x%d" % rewards.stat_points, Color.CORNFLOWER_BLUE)
		
		# 技能点
		if rewards.get("skill_points", 0) > 0:
			_add_reward_item("🎁 技能点 x%d" % rewards.skill_points, Color.MEDIUM_SEA_GREEN)
		
		# 状态恢复
		if rewards.get("hp_restored", 0) > 0:
			_add_reward_item("❤️ HP +%d%%" % rewards.hp_restored, Color.CRIMSON)
		
		if rewards.get("stamina_restored", 0) > 0:
			_add_reward_item("⚡ 体力 +%d%%" % rewards.stamina_restored, Color.YELLOW)
		
		if rewards.get("mental_restored", 0) > 0:
			_add_reward_item("🧠 精神 +%d%%" % rewards.mental_restored, Color.MEDIUM_PURPLE)
	
	# 显示界面
	show()
	
	# 播放动画
	if animation_player:
		animation_player.play("level_up_show")
	
	# 暂停游戏时间
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager:
		time_manager.pause_time()

func _add_reward_item(text: String, color: Color):
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rewards_container.add_child(label)

func _on_ok_pressed():
	# 关闭界面
	hide()
	
	# 恢复游戏时间
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager:
		time_manager.resume_time()
	
	# 检查是否有属性点需要分配
	if xp_system:
		var points = xp_system.get_available_points()
		if points.stat_points > 0:
			# 打开属性分配界面
			_open_attribute_allocation()

func _open_attribute_allocation():
	var attr_ui = get_node_or_null("/root/AttributeAllocationUI")
	if attr_ui:
		attr_ui.show_ui()

func _input(event):
	if visible and event is InputEventKey:
		if event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
			_on_ok_pressed()
