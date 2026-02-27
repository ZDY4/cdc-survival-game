extends Control
class_name ExperienceBarUI
# ExperienceBarUI - 经验条UI
# 显示在角色面板中，显示当前等级、经验值和进度

@onready var level_label: Label = $VBoxContainer/LevelContainer/LevelLabel
@onready var level_value: Label = $VBoxContainer/LevelContainer/LevelValue
@onready var xp_progress: ProgressBar = $VBoxContainer/XPProgress
@onready var xp_text: Label = $VBoxContainer/XPProgress/XPLabel
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var points_container: HBoxContainer = $VBoxContainer/PointsContainer
@onready var stat_points_label: Label = $VBoxContainer/PointsContainer/StatPointsLabel
@onready var skill_points_label: Label = $VBoxContainer/PointsContainer/SkillPointsLabel

var xp_system: Node = null

func _ready():
	# 获取ExperienceSystem引用
	xp_system = get_node_or_null("/root/ExperienceSystem")
	
	if xp_system:
		xp_system.xp_gained.connect(_on_xp_gained)
		xp_system.level_up.connect(_on_level_up)
		xp_system.xp_to_next_level_changed.connect(_on_xp_requirement_changed)
		_update_display()
	else:
		push_warning("[ExperienceBarUI] ExperienceSystem not found")

func _update_display():
	if not xp_system:
		return
	
	var level = xp_system.current_level
	var current_xp = xp_system.current_xp
	var xp_needed = xp_system.get_xp_to_next_level()
	var progress = xp_system.get_level_progress_percent()
	var title = xp_system.get_level_title()
	var points = xp_system.get_available_points()
	
	if level_value:
		level_value.text = str(level)
	
	if title_label:
		title_label.text = "[%s]" % title
	
	if xp_progress:
		xp_progress.value = progress * 100
	
	if xp_text:
		xp_text.text = "%d / %d XP" % [current_xp, xp_needed]
	
	# 更新点数显示
	if points_container:
		points_container.visible = (points.stat_points > 0 or points.skill_points > 0)
	
	if stat_points_label:
		if points.stat_points > 0:
			stat_points_label.text = "属性点: %d" % points.stat_points
			stat_points_label.visible = true
		else:
			stat_points_label.visible = false
	
	if skill_points_label:
		if points.skill_points > 0:
			skill_points_label.text = "技能点: %d" % points.skill_points
			skill_points_label.visible = true
		else:
			skill_points_label.visible = false

# ===== 信号处理 =====

func _on_xp_gained(amount: int, source: String, total_xp: int):
	_update_display()
	_show_xp_gain_animation(amount)

func _on_level_up(new_level: int, rewards: Dictionary):
	_update_display()
	_show_level_up_animation(new_level)

func _on_xp_requirement_changed(xp_needed: int):
	_update_display()

# ===== 动画效果 =====

func _show_xp_gain_animation(amount: int):
	var popup = Label.new()
	popup.text = "+%d XP" % amount
	popup.add_theme_font_size_override("font_size", 20)
	popup.add_theme_color_override("font_color", Color.GREEN)
	popup.position = xp_progress.global_position + Vector2(xp_progress.size.x / 2, -30)
	add_child(popup)
	
	var tween = create_tween()
	tween.tween_property(popup, "position:y", popup.position.y - 50, 1.0)
	tween.tween_property(popup, "modulate:a", 0, 1.0)
	tween.tween_callback(popup.queue_free)

func _show_level_up_animation(level: int):
	var popup = Label.new()
	popup.text = "升级！等级 %d" % level
	popup.add_theme_font_size_override("font_size", 32)
	popup.add_theme_color_override("font_color", Color.GOLD)
	popup.position = Vector2(size.x / 2 - 80, size.y / 2)
	add_child(popup)
	
	var tween = create_tween()
	tween.tween_property(popup, "scale", Vector2(1.5, 1.5), 0.3)
	tween.tween_property(popup, "scale", Vector2(1, 1), 0.3)
	tween.tween_interval(1.5)
	tween.tween_property(popup, "modulate:a", 0, 0.5)
	tween.tween_callback(popup.queue_free)
