extends Control
class_name EncounterUI
# EncounterUI - 文字冒险遭遇界面
# 描述区、选择按钮区、结果展示区

# ===== 节点引用 =====
@onready var title_label: Label = $Panel/TitleLabel
@onready var location_label: Label = $Panel/LocationLabel
@onready var description_label: Label = $Panel/DescriptionLabel
@onready var choices_container: VBoxContainer = $Panel/ChoicesContainer
var skill_check_panel: Panel = null
@onready var result_panel: Panel = $ResultPanel
@onready var result_title: Label = $ResultPanel/ResultTitle
@onready var result_text: Label = $ResultPanel/ResultText
@onready var rewards_container: VBoxContainer = $ResultPanel/RewardsContainer
@onready var penalties_container: VBoxContainer = $ResultPanel/PenaltiesContainer
@onready var continue_button: Button = $ResultPanel/ContinueButton

# ===== 状态 =====
var _encounter_system: Node = null
var _current_encounter: Dictionary = {}
var _current_choices: Array = []

func _ready():
	_encounter_system = get_node_or_null("/root/EncounterSystem")
	
	# 获取节点引用
	skill_check_panel = $SkillCheckPanel
	
	# 连接信号
	if _encounter_system:
		_encounter_system.encounter_triggered.connect(_on_encounter_triggered)
		_encounter_system.encounter_resolved.connect(_on_encounter_resolved)
	
	continue_button.pressed.connect(_on_continue_pressed)
	
	# 初始隐藏
	hide()
	result_panel.hide()
	if skill_check_panel:
		skill_check_panel.hide()

func _on_encounter_triggered(encounter_id: String, encounter_data: Dictionary):
	_show_encounter(encounter_data)

func _show_encounter(encounter_data: Dictionary):
	_current_encounter = encounter_data
	
	# 更新标题和位置
	title_label.text = encounter_data.get("name", "未知遭遇")
	location_label.text = "地点: %s" % _get_location_name(GameState.player_position)
	
	# 更新描述 (打字机效果)
	var description = encounter_data.get("description", "")
	description_label.text = ""
	_show_typing_text(description_label, description)
	
	# 清空并创建选择按钮
	_clear_choices()
	_current_choices = encounter_data.get("choices", [])
	
	# 延迟创建选择按钮，等待描述显示完
	await get_tree().create_timer(1.5).timeout
	_create_choice_buttons()
	
	# 显示UI
	show()
	result_panel.hide()

func _show_typing_text(label: Label, text: String):
	label.text = ""
	for i in range(text.length()):
		label.text += text[i]
		await get_tree().create_timer(0.03).timeout

func _clear_choices():
	for child in choices_container.get_children():
		child.queue_free()

func _create_choice_buttons():
	for i in range(_current_choices.size()):
		var choice = _current_choices[i]
		var btn = Button.new()
		
		# 构建按钮文本
		var btn_text = choice.get("text", "选择 %d" % (i + 1))
		
		# 添加技能检定提示
		if choice.has("skill_check"):
			var skill_name = _get_skill_name(choice.skill_check)
			var difficulty = choice.get("difficulty", 10)
			btn_text += " [%s 检定 DC%d]" % [skill_name, difficulty]
		
		# 添加消耗提示
		if choice.has("cost"):
			btn_text += " (有消耗)"
		
		btn.text = btn_text
		btn.pressed.connect(func(): _on_choice_selected(i))
		
		# 根据风险设置颜色
		if choice.has("outcome") and choice.outcome.has("hp_loss"):
			btn.modulate = Color(0.9, 0.3, 0.3)
		elif choice.has("fail_outcome"):
			btn.modulate = Color(0.9, 0.7, 0.1)
		else:
			btn.modulate = Color(0.3, 0.9, 0.3)
		
		choices_container.add_child(btn)

func _get_location_name(location_id: String) -> String:
	var names = {
		"hospital": "医院",
		"supermarket": "超市",
		"school": "学校",
		"forest": "森林",
		"street": "公路/街道",
		"factory": "工厂废墟",
		"subway": "地铁废墟",
		"safehouse": "安全屋"
	}
	return names.get(location_id, location_id)

func _get_skill_name(skill_id: String) -> String:
	var names = {
		"strength": "力量",
		"agility": "敏捷",
		"intelligence": "智力",
		"athletics": "运动",
		"stealth": "潜行",
		"perception": "感知",
		"investigation": "调查",
		"lockpicking": "开锁",
		"survival": "生存",
		"medicine": "医疗",
		"combat": "战斗",
		"negotiation": "交涉",
		"luck": "运气"
	}
	return names.get(skill_id, skill_id)

func _on_choice_selected(choice_index: int):
	if _encounter_system:
		# 禁用所有按钮
		for btn in choices_container.get_children():
			btn.disabled = true
		
		var result = _encounter_system.resolve_encounter_choice(choice_index)
		
		# 如果有技能检定，显示检定过程
		if result.has("check_result"):
			await _show_skill_check(result.check_result)
		
		_show_result(result)

func _show_skill_check(check_result: Dictionary):
	if not skill_check_panel:
		return
	
	skill_check_panel.show()
	
	var check_label = skill_check_panel.get_node("CheckLabel")
	var breakdown_label = skill_check_panel.get_node("BreakdownLabel")
	var result_label = skill_check_panel.get_node("ResultLabel")
	
	# 显示检定详情
	var breakdown = check_result.breakdown
	breakdown_label.text = "基础: %.0f%% + 技能: %.0f%% + 属性: %.0f%% - 惩罚: %.0f%% - 难度: %.0f%%" % [
		breakdown.base * 100,
		breakdown.skill * 100,
		breakdown.attribute * 100,
		breakdown.penalty * 100,
		breakdown.difficulty * 100
	]
	
	check_label.text = "目标值: %.0f%%" % (check_result.target * 100)
	
	# 模拟掷骰动画
	for i in range(10):
		result_label.text = "掷骰: %.0f%%" % (randf() * 100)
		await get_tree().create_timer(0.1).timeout
	
	result_label.text = "掷骰: %.0f%%" % (check_result.roll * 100)
	
	if check_result.success:
		result_label.modulate = Color(0.2, 0.9, 0.2)
		result_label.text += " - 成功! (%s)" % _get_success_level_name(check_result.success_level)
	else:
		result_label.modulate = Color(0.9, 0.2, 0.2)
		result_label.text += " - 失败! (%s)" % _get_success_level_name(check_result.success_level)
	
	await get_tree().create_timer(2.0).timeout
	skill_check_panel.hide()

func _get_success_level_name(level: String) -> String:
	match level:
		"critical": return "大成功"
		"good": return "成功"
		"normal": return "普通成功"
		"bad_fail": return "失败"
		"critical_fail": return "大失败"
	return level

func _show_result(result: Dictionary):
	result_panel.show()
	
	if result.success:
		result_title.text = "遭遇解决"
		result_title.modulate = Color(0.2, 0.9, 0.2)
	else:
		result_title.text = "遭遇结果"
		result_title.modulate = Color(0.9, 0.9, 0.2)
	
	result_text.text = result.get("outcome", "")
	
	# 显示奖励
	_clear_container(rewards_container)
	if result.has("rewards") and not result.rewards.is_empty():
		var rewards_title = Label.new()
		rewards_title.text = "获得:"
		rewards_title.add_theme_font_size_override("font_size", 16)
		rewards_container.add_child(rewards_title)
		
		for reward in result.rewards:
			var reward_label = Label.new()
			match reward.type:
				"xp":
					reward_label.text = "• %d 经验值" % reward.amount
					reward_label.modulate = Color(0.9, 0.7, 0.1)
				"heal":
					reward_label.text = "• 恢复 %d HP" % reward.amount
					reward_label.modulate = Color(0.2, 0.9, 0.2)
				_:
					if reward.has("id"):
						reward_label.text = "• %s x%d" % [reward.id, reward.get("count", 1)]
						reward_label.modulate = Color(0.4, 0.8, 1.0)
			rewards_container.add_child(reward_label)
	
	# 显示惩罚
	_clear_container(penalties_container)
	if result.has("penalties") and not result.penalties.is_empty():
		var penalties_title = Label.new()
		penalties_title.text = "损失:"
		penalties_title.add_theme_font_size_override("font_size", 16)
		penalties_container.add_child(penalties_title)
		
		for penalty in result.penalties:
			var penalty_label = Label.new()
			match penalty.type:
				"damage":
					penalty_label.text = "• 受到 %d 伤害" % penalty.amount
					penalty_label.modulate = Color(0.9, 0.2, 0.2)
				"time":
					penalty_label.text = "• 消耗 %d 小时" % penalty.amount
				"item":
					penalty_label.text = "• 失去 %s x%d" % [penalty.item, penalty.count]
			penalties_container.add_child(penalty_label)

func _clear_container(container: VBoxContainer):
	for child in container.get_children():
		child.queue_free()

func _on_encounter_resolved(encounter_id: String, result: Dictionary):
	# 遭遇已解决，等待玩家点击继续
	pass

func _on_continue_pressed():
	result_panel.hide()
	hide()
	
	# 检查是否有后续遭遇
	if _current_encounter.has("follow_up"):
		var follow_up_id = _current_encounter.follow_up
		if _encounter_system:
			_encounter_system.force_encounter(follow_up_id)

# ===== 公共接口 =====
func show_encounter(encounter_data: Dictionary):
	_show_encounter(encounter_data)

func has_active_encounter() -> bool:
	return visible and not result_panel.visible
