extends Node
# ChoiceSystem - 选择系统
# 处理所有与玩家选择相关的逻辑

signal choice_presented(choices: Array[Dictionary])
signal choice_made(choice_id: String, choice_data: Dictionary, result: Dictionary)
signal skill_check_performed(check_data: Dictionary, result: Dictionary)
signal consequence_executed(consequence_type: String, data: Dictionary)

# ===== 选择UI引用 =====
var choice_ui: Control = null
var is_waiting_for_choice: bool = false
var current_choices: Array[Dictionary] = []

func _ready():
	print("[ChoiceSystem] 选择系统已初始化")
	_setup_ui()

func _setup_ui():
	# 延迟加载UI
	call_deferred("_load_choice_ui")

func _load_choice_ui():
	# 检查文件是否存在
	if not FileAccess.file_exists("res://modules/dialog/choice_ui.tscn"):
		push_warning("[ChoiceSystem] choice_ui.tscn not found, choice system will be limited")
		return
	
	var ui_scene = load("res://modules/dialog/choice_ui.tscn")
	if ui_scene:
		choice_ui = ui_scene.instantiate()
		if choice_ui:
			get_tree().root.add_child(choice_ui)
			if choice_ui.has_signal("choice_selected"):
				choice_ui.choice_selected.connect(_on_ui_choice_selected)
			choice_ui.hide()

# ===== 核心功能：呈现选择 =====

# 呈现一组选择给玩家
func present_choices(choices_data: Array, context: Dictionary = {}):
	# 等待上一个选择完成
	while is_waiting_for_choice:
		await get_tree().create_timer(0.1).timeout
	
	is_waiting_for_choice = true
	current_choices = []
	
	# 过滤和处理选择
	for choice_data in choices_data:
		var processed_choice = _process_choice_data(choice_data, context)
		
		# 检查可见性条件
		if processed_choice.has("visible_if"):
			if not GameStateManager.check_conditions([processed_choice.visible_if]):
				continue
		
		current_choices.append(processed_choice)
	
	if current_choices.size() == 0:
		is_waiting_for_choice = false
		push_warning("No available choices to present")
		return ""
	
	# 发送信号
	choice_presented.emit(current_choices)
	
	# 显示UI
	if choice_ui:
		choice_ui.show_choices(current_choices, context.get("speaker", ""), context.get("text", ""))
	
	# 等待玩家选择
	var result = await _wait_for_player_choice()
	is_waiting_for_choice = false
	
	return result

# 处理选择数据
func _process_choice_data(choice_data: Dictionary, context: Dictionary):
	var processed = choice_data.duplicate(true)
	
	# 处理动态文本替换
	if processed.has("text"):
		processed.text = _replace_variables(processed.text, context)
	
	# 处理tooltip
	if processed.has("tooltip"):
		processed.tooltip = _replace_variables(processed.tooltip, context)
	
	# 检查可用性
	processed.enabled = true
	if processed.has("condition"):
		processed.enabled = GameStateManager.check_conditions([processed.condition])
	
	# 如果不可用，替换文本
	if not processed.enabled && processed.has("disabled_text"):
		processed.text = processed.disabled_text
	
	# 添加图标
	if processed.has("icon"):
		if processed.icon is String:
			processed.icon = load(processed.icon)
	
	return processed

# 文本变量替换
func _replace_variables(text: String, context: Dictionary):
	var result = text
	
	# 替换 {player_name}
	result = result.replace("{player_name}", context.get("player_name", "幸存者"))
	
	# 替换 {npc_name}
	result = result.replace("{npc_name}", context.get("npc_name", "陌生人"))
	
	# 替换 {stat_xxx}
	var stat_regex = RegEx.new()
	stat_regex.compile("\\{stat_(\\w+)\\}")
	for match in stat_regex.search_all(result):
		var stat_name = match.get_string(1)
		var stat_value = _get_stat_value(stat_name)
		result = result.replace(match.get_string(), str(stat_value))
	
	# 替换 {flag_xxx}
	var flag_regex = RegEx.new()
	flag_regex.compile("\\{flag_(\\w+)\\}")
	for match in flag_regex.search_all(result):
		var flag_name = match.get_string(1)
		var flag_value = GameStateManager.get_flag(flag_name, false)
		result = result.replace(match.get_string(), str(flag_value))
	
	# 替换 {item_count:xxx}
	var item_regex = RegEx.new()
	item_regex.compile("\\{item_count:(\\w+)\\}")
	for match in item_regex.search_all(result):
		var item_id = match.get_string(1)
		var count = _get_item_count(item_id)
		result = result.replace(match.get_string(), str(count))
	
	return result

# 等待玩家选择
func _wait_for_player_choice():
	# 创建一个临时的信号连接
	var choice_result = ""
	var choice_made_handler = func(id): choice_result = id
	
	choice_made.connect(choice_made_handler)
	
	# 等待选择
	while choice_result == "":
		await get_tree().create_timer(0.05).timeout
	
	choice_made.disconnect(choice_made_handler)
	return choice_result

# UI选择回调
func _on_ui_choice_selected(choice_id: String):
	choice_made.emit(choice_id, _get_choice_data(choice_id), {})

# 获取选择数据
func _get_choice_data(choice_id: String):
	for choice in current_choices:
		if choice.get("id") == choice_id:
			return choice
	return {}

# ===== 处理选择后果 =====

# 处理玩家做出的选择
func handle_choice(choice_id: String, scene_id: String = ""):
	var choice_data = _get_choice_data(choice_id)
	if choice_data.is_empty():
		return {"success": false, "error": "Choice not found"}
	
	var result = {
		"success": true,
		"skill_check": null,
		"consequences": [],
		"next_scene": "",
		"dialog_text": ""
	}
	
	# 记录选择历史
	GameStateManager.record_choice(
		scene_id,
		choice_id,
		choice_data.get("text", "")
	)
	
	# 处理技能检定
	if choice_data.has("skill_check"):
		var check_result = _perform_skill_check(choice_data.skill_check)
		result.skill_check = check_result
		
		if check_result.success:
			# 成功分支
			if choice_data.has("success"):
				_apply_choice_result(choice_data.success, result)
				result.dialog_text = choice_data.success.get("text", "成功！")
		else:
			# 失败分支
			if choice_data.has("failure"):
				_apply_choice_result(choice_data.failure, result)
				result.dialog_text = choice_data.failure.get("text", "失败...")
			else:
				# 没有失败分支，使用默认
				result.dialog_text = "尝试失败了..."
				
	else:
		# 没有技能检定，直接执行后果
		_apply_choice_result(choice_data, result)
	
	# 执行后果
	if choice_data.has("consequences"):
		GameStateManager.execute_consequences(choice_data.consequences)
		result.consequences = choice_data.consequences
	
	choice_made.emit(choice_id, choice_data, result)
	return result

# 应用选择结果
func _apply_choice_result(result_data: Dictionary, result: Dictionary):
	if result_data.has("next_scene"):
		result.next_scene = result_data.next_scene
	
	if result_data.has("consequences"):
		GameStateManager.execute_consequences(result_data.consequences)
		result.consequences.append_array(result_data.consequences)
	
	if result_data.has("text"):
		result.dialog_text = result_data.text

# ===== 技能检定系统 =====

# 执行技能检定
func _perform_skill_check(check_data: Dictionary):
	var skill_name = check_data.get("skill", "")
	var difficulty = check_data.get("difficulty", 10)
	var player_level = check_data.get("player_bonus", 0)
	
	# D20系统
	var roll = randi_range(1, 20)
	var total = roll + player_level
	
	var success = total >= difficulty
	var degree = 0  # 成功程度
	
	# 大成功/大失败
	if roll == 20:
		success = true
		degree = 2
	elif roll == 1:
		success = false
		degree = -2
	# 完美成功/严重失败
	elif total >= difficulty + 5:
		degree = 1
	elif total < difficulty - 5:
		degree = -1
	
	var result = {
		"success": success,
		"roll": roll,
		"total": total,
		"difficulty": difficulty,
		"degree": degree,
		"skill": skill_name
	}
	
	skill_check_performed.emit(check_data, result)
	
	# 显示检定结果
	_show_skill_check_result(result)
	
	return result

# 显示技能检定结果
func _show_skill_check_result(result: Dictionary):
	var skill_names = {
		"strength": "力量",
		"agility": "敏捷",
		"intelligence": "智力",
		"lockpicking": "开锁",
		"crafting": "制作",
		"medicine": "医疗"
	}
	
	var skill_name = skill_names.get(result.skill, result.skill)
	var degree_text = ""
	
	match result.degree:
		2: degree_text = "【大成功！】"
		1: degree_text = "【完美成功】"
		-1: degree_text = "【严重失败】"
		-2: degree_text = "【大失败！】"
	
	var result_text = "%s 检定 %s\n掷骰: %d + 加成 = %d | 难度: %d" % [
		skill_name,
		degree_text,
		result.roll,
		result.total,
		result.difficulty
	]
	
	DialogModule.show_dialog(result_text, "技能检定", "")

# ===== 条件检查辅助 =====

func check_choice_availability(choice_data: Dictionary):
	var result = {
		"available": true,
		"reason": ""
	}
	
	# 检查条件
	if choice_data.has("condition"):
		if not GameStateManager.check_conditions([choice_data.condition]):
			result.available = false
			result.reason = choice_data.get("condition_hint", "条件不满足")
			return result
	
	# 检查物品
	if choice_data.has("required_items"):
		for item in choice_data.required_items:
			if not InventoryModule.has_item(item.id, item.count):
				result.available = false
				result.reason = "需要: %s x%d" % [item.id, item.count]
				return result
	
	# 检查时间
	if choice_data.has("time_limit"):
		var current_time = GameState.world_time
		if current_time < choice_data.time_limit.start || current_time > choice_data.time_limit.end:
			result.available = false
			result.reason = "当前时间无法选择"
			return result
	
	return result

# ===== 预设选择模板 =====

# 战斗选择
func get_combat_choices(enemy_data: Dictionary) -> Array[Dictionary]:
	return [
		{
			"id": "combat_attack",
			"text": "攻击",
			"icon": "res://icons/attack.png"
		},
		{
			"id": "combat_item",
			"text": "使用物品",
			"condition": {"type": "has_item", "count": 1}
		}
	]

# 对话选择
func get_dialog_choices(npc_id: String, relationship: int) -> Array[Dictionary]:
	var choices = [
		{
			"id": "dialog_talk",
			"text": "交谈"
		},
		{
			"id": "dialog_quest",
			"text": "询问任务"
		}
	]
	
	# 根据好感度添加选项
	if relationship >= 20:
		choices.append({
			"id": "dialog_trade",
			"text": "交易"
		})
	
	if relationship >= 50:
		choices.append({
			"id": "dialog_recruit",
			"text": "邀请加入"
		})
	
	if relationship < -20:
		choices.append({
			"id": "dialog_threaten",
			"text": "威胁"
		})
	
	return choices

# 生存选择
func get_survival_choices(situation: String) -> Array[Dictionary]:
	match situation:
		"hungry":
			return [
				{
					"id": "eat_food",
					"text": "吃食物",
					"condition": {"type": "has_item", "item": 1007}
				},
				{
					"id": "hunt",
					"text": "寻找食物"
				},
				{
					"id": "starve",
					"text": "忍受饥饿"
				}
			]
		"injured":
			return [
				{
					"id": "use_bandage",
					"text": "使用绷带",
					"condition": {"type": "has_item", "item": 1006}
				},
				{
					"id": "rest",
					"text": "休息"
				},
				{
					"id": "ignore",
					"text": "无视伤口"
				}
			]
		_:
			return []

# ===== 辅助方法 =====

func _get_stat_value(stat_name: String):
	match stat_name:
		"strength", "str": return 10
		"agility", "agi": return 10
		"intelligence", "int": return 10
		"luck": return 10
	return 0

func _get_item_count(item_id: String):
	for item in GameState.inventory_items:
		if item.id == item_id:
			return item.count
	return 0

# ===== 存档/读档 =====

func get_save_data():
	return {
		"is_waiting": is_waiting_for_choice,
		"current_choices": current_choices
	}

func load_save_data(data: Dictionary):
	# 恢复选择状态
	pass


