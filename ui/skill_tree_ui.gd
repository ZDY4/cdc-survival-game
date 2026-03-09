extends Control
class_name SkillTreeUI
# SkillTreeUI - 技能树界面
# 显示三大技能树：战斗、生存、制作

@onready var tab_container: TabContainer = $CenterContainer/Panel/VBoxContainer/TabContainer
@onready var points_label: Label = $CenterContainer/Panel/VBoxContainer/PointsLabel
@onready var skill_info_panel: Panel = $SkillInfoPanel
@onready var skill_name: Label = $SkillInfoPanel/VBoxContainer/SkillName
@onready var skill_description: Label = $SkillInfoPanel/VBoxContainer/SkillDescription
@onready var skill_level: Label = $SkillInfoPanel/VBoxContainer/SkillLevel
@onready var skill_effects: Label = $SkillInfoPanel/VBoxContainer/SkillEffects
@onready var learn_button: Button = $SkillInfoPanel/VBoxContainer/LearnButton
@onready var close_button: Button = $CenterContainer/Panel/VBoxContainer/CloseButton

var skill_system: Node = null
var xp_system: Node = null

var selected_skill_id: String = ""
var skill_buttons: Dictionary = {}  # skill_id -> Button

func _ready():
	hide()
	skill_info_panel.hide()
	
	# 获取系统引用
	skill_system = get_node_or_null("/root/SkillSystem")
	xp_system = get_node_or_null("/root/ExperienceSystem")
	
	if skill_system:
		skill_system.skill_learned.connect(_on_skill_learned)
		skill_system.skill_points_changed.connect(_on_skill_points_changed)
	
	close_button.pressed.connect(_on_close)
	learn_button.pressed.connect(_on_learn_skill)
	
	# 构建技能树UI
	_build_skill_tree()

func _build_skill_tree():
	if not skill_system:
		return
	
	var tree_data = skill_system.get_skill_tree_data()
	
	# 清除现有标签页
	for i in range(tab_container.get_tab_count()):
		tab_container.remove_child(tab_container.get_tab_control(0))
	
	# 为每个类别创建标签页
	for category in ["combat", "survival", "crafting"]:
		var category_data = tree_data.get(category, {})
		var tab = _create_category_tab(category, category_data)
		tab_container.add_child(tab)
		tab_container.set_tab_title(tab_container.get_tab_count() - 1, category_data.get("name", category))

func _create_category_tab(category: String, data: Dictionary) -> Control:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var skills = data.get("skills", {})
	
	for skill_id in skills.keys():
		var skill_data = skills[skill_id]
		var skill_row = _create_skill_row(skill_id, skill_data)
		container.add_child(skill_row)
	
	scroll.add_child(container)
	return scroll

func _create_skill_row(skill_id: String, skill_data: Dictionary) -> Control:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# 技能按钮
	var btn = Button.new()
	btn.text = skill_data.get("name", skill_id)
	btn.tooltip_text = skill_data.get("description", "")
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func(): _on_skill_selected(skill_id, skill_data))
	
	# 根据学习状态设置样式
	_update_skill_button_style(btn, skill_data)
	
	row.add_child(btn)
	skill_buttons[skill_id] = btn
	
	# 等级显示
	var level_label = Label.new()
	level_label.text = "%d/%d" % [skill_data.get("current_level", 0), skill_data.get("max_level", 1)]
	level_label.custom_minimum_size = Vector2(50, 0)
	row.add_child(level_label)
	
	return row

func _update_skill_button_style(btn: Button, skill_data: Dictionary):
	var current = skill_data.get("current_level", 0)
	var max_level = skill_data.get("max_level", 1)
	var is_maxed = skill_data.get("is_maxed", false)
	var is_learned = skill_data.get("is_learned", false)
	
	if is_maxed:
		btn.add_theme_color_override("font_color", Color.GOLD)
	elif is_learned:
		btn.add_theme_color_override("font_color", Color.GREEN)
	else:
		btn.add_theme_color_override("font_color", Color.GRAY)

func _on_skill_selected(skill_id: String, skill_data: Dictionary):
	selected_skill_id = skill_id
	
	# 更新信息面板
	skill_name.text = skill_data.get("name", skill_id)
	skill_description.text = skill_data.get("description", "")
	
	var current = skill_data.get("current_level", 0)
	var max_level = skill_data.get("max_level", 1)
	skill_level.text = "等级: %d/%d" % [current, max_level]
	
	# 效果显示
	var effects = skill_data.get("effects", {})
	var effect_text = "效果:\n"
	for effect_name in effects.keys():
		var value = effects[effect_name]
		effect_text += "  • %s: +%s (x%d)\n" % [effect_name, str(value), current]
	skill_effects.text = effect_text
	
	# 更新学习按钮
	var can_learn = skill_system.can_learn_skill(skill_id)
	learn_button.disabled = not can_learn.can_learn
	learn_button.text = "学习" if current == 0 else "升级"
	
	if can_learn.can_learn:
		learn_button.tooltip_text = "消耗 1 技能点"
	else:
		learn_button.tooltip_text = can_learn.reason
	
	skill_info_panel.show()

func _on_learn_skill():
	if selected_skill_id.is_empty() or not skill_system:
		return
	
	var result = skill_system.learn_skill(selected_skill_id)
	if result.success:
		# 刷新显示
		_build_skill_tree()
		_update_points_display()
		
		# 刷新信息面板
		var skill_data = skill_system.get_skill(selected_skill_id)
		_on_skill_selected(selected_skill_id, skill_data)
		
		# 播放音效/动画
		_show_learn_animation()

func _show_learn_animation():
	var tween = create_tween()
	learn_button.modulate = Color.GREEN
	tween.tween_property(learn_button, "modulate", Color.WHITE, 0.5)

func _on_skill_learned(skill_id: String, skill_data: Dictionary):
	_build_skill_tree()
	_update_points_display()

func _on_skill_points_changed(points: int):
	_update_points_display()

func _update_points_display():
	var points_value: int = 0
	if skill_system and skill_system.has_method("get_available_points"):
		points_value = int(skill_system.get_available_points())
	elif xp_system and xp_system.has_method("get_available_points"):
		var points: Dictionary = xp_system.get_available_points()
		points_value = int(points.get("skill_points", 0))

	points_label.text = "技能点: %d" % points_value
	points_label.add_theme_color_override("font_color", Color.GREEN if points_value > 0 else Color.GRAY)

func show_ui():
	_build_skill_tree()
	_update_points_display()
	skill_info_panel.hide()
	selected_skill_id = ""
	show()

func _on_close():
	hide()
