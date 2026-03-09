extends Node
## NPC对话组件
## 处理对话树遍历、条件检查、技能检定、事件触发
## 复用DialogModule进行UI显示

class_name NPCDialogComponent

# ========== 信号 ==========
signal dialog_started
signal dialog_ended
signal dialog_node_entered(node_id: String)
signal option_selected(option_index: int, option_data: Dictionary)
signal skill_check_requested(skill: String, difficulty: int)
signal skill_check_result(passed: bool, roll: int, difficulty: int)
signal event_triggered(event_type: String, event_data: Dictionary)

# ========== 数据 ==========
var dialog_tree: Dictionary = {}
var current_node_id: String = ""
var current_node: Dictionary = {}
var npc: Node

# 对话上下文（用于条件判断）
var context: Dictionary = {
	"player_attributes": {},
	"npc_mood": {},
	"memory": {},
	"inventory": {},
	"skill_check_results": {}
}

# ========== 初始化 ==========

func initialize(parent_npc: Node):
	npc = parent_npc

# ========== 核心对话流程 ==========

## 开始对话
func start_dialog() -> bool:
	if not npc or not npc.npc_data:
		return false
	
	if dialog_tree.is_empty():
		push_warning("[NPCDialogComponent] 对话树为空")
		return false
	
	# 准备上下文数据
	_prepare_context()
	
	# 找到起始节点
	current_node_id = _find_start_node()
	if current_node_id.is_empty():
		push_warning("[NPCDialogComponent] 找不到起始节点")
		return false
	
	dialog_started.emit()
	
	# 对话主循环
	while current_node_id != "" and current_node_id != "end":
		current_node = dialog_tree.get(current_node_id, {})
		
		if current_node.is_empty():
			push_error("[NPCDialogComponent] 节点 %s 不存在" % current_node_id)
			break
		
		# 执行节点进入事件
		_execute_node_events(current_node.get("on_enter_events", []))
		
		# 显示对话（复用DialogModule）
		var next_node = await _display_node(current_node)
		
		if next_node.is_empty():
			break
		
		current_node_id = next_node
		dialog_node_entered.emit(current_node_id)
	
	_dialog_cleanup()
	dialog_ended.emit()
	
	return true

## 准备对话上下文
func _prepare_context():
	# 获取玩家属性
	if GameState:
		context.player_attributes = {
			"level": GameState.player_level,
			"strength": GameState.player_strength if GameState.has("player_strength") else 10,
			"perception": GameState.player_perception if GameState.has("player_perception") else 10,
			"endurance": GameState.player_endurance if GameState.has("player_endurance") else 10,
			"charisma": GameState.player_charisma if GameState.has("player_charisma") else 10,
			"intelligence": GameState.player_intelligence if GameState.has("player_intelligence") else 10,
			"agility": GameState.player_agility if GameState.has("player_agility") else 10,
			"luck": GameState.player_luck if GameState.has("player_luck") else 10
		}
	
	# 获取NPC情绪
	if npc.npc_data:
		context.npc_mood = npc.npc_data.mood.duplicate()
		context.memory = npc.npc_data.memory.duplicate()

## 查找起始节点
func _find_start_node() -> String:
	# 优先查找标记为start且条件满足的节点
	for node_id in dialog_tree.keys():
		var node = dialog_tree[node_id]
		if node.get("is_start", false) or node_id == "start":
			if _check_conditions(node.get("conditions", [])):
				return node_id
	
	# 默认返回第一个节点
	if not dialog_tree.is_empty():
		return dialog_tree.keys()[0]
	
	return ""

## 显示对话节点（复用DialogModule）
func _display_node(node: Dictionary) -> String:
	var text = node.get("text", "...")
	var speaker = node.get("speaker", npc.npc_name if npc else "")
	var emotion = node.get("emotion", "normal")
	var portrait = npc.get_current_portrait() if npc else ""
	
	# 替换变量
	text = _replace_variables(text)
	
	# 使用DialogModule显示文本
	DialogModule.show_dialog(text, speaker, portrait)
	
	# 等待文本显示完成
	await DialogModule.dialog_finished
	
	# 如果是结束节点
	if node.get("is_end", false):
		DialogModule.hide_dialog()
		return "end"
	
	# 获取可用选项
	var available_options = _get_available_options(node)
	
	if available_options.is_empty():
		DialogModule.hide_dialog()
		return "end"
	
	# 显示选项（复用DialogModule）
	var choice_texts: Array[String] = []
	for opt in available_options:
		var display_text = opt.get("text", "...")
		
		# 添加条件提示
		if opt.has("skill_check"):
			var check = opt.skill_check
			display_text += " [%s检定:%d]" % [check.get("skill", ""), check.get("difficulty", 0)]
		elif opt.has("conditions"):
			# 检查是否是条件选项
			for cond in opt.conditions:
				if cond.get("type") == "has_item":
					display_text += " [需:%s]" % cond.get("item_id", "")
					break
		
		choice_texts.append(display_text)
	
	# 等待玩家选择
	var selected_index = await DialogModule.show_choices(choice_texts)
	
	if selected_index < 0 or selected_index >= available_options.size():
		return "end"
	
	var selected_option = available_options[selected_index]
	option_selected.emit(selected_index, selected_option)
	
	# 处理选择
	return await _process_option(selected_option)

## 获取可用的选项
func _get_available_options(node: Dictionary) -> Array[Dictionary]:
	var all_options = node.get("options", [])
	var available: Array[Dictionary] = []
	
	for option in all_options:
		# 检查选项显示条件
		if _check_conditions(option.get("show_conditions", [])):
			available.append(option)
	
	return available

## 处理选项选择
func _process_option(option: Dictionary) -> String:
	# 1. 执行选择动作
	_execute_actions(option.get("actions", []))
	
	# 2. 处理技能检定
	if option.has("skill_check"):
		var check = option.skill_check
		skill_check_requested.emit(check.skill, check.difficulty)
		
		var passed = await _do_skill_check(check.skill, check.difficulty)
		
		if not passed:
			# 检定失败，跳转到失败分支
			var fail_node = option.get("fail_node", "")
			if not fail_node.is_empty():
				return fail_node
			# 如果没有指定失败节点，显示失败消息
			DialogModule.show_dialog("检定失败！%s不足。" % check.skill, "系统")
			await DialogModule.dialog_finished
			return "end"
	
	# 3. 应用情绪影响
	if option.has("mood_effects"):
		_apply_mood_effects(option.mood_effects)
	
	# 4. 记录到记忆
	if npc.memory_component:
		npc.memory_component.record_dialog_choice(option.get("text", ""))
	
	# 5. 返回下一个节点
	return option.get("next_node", "end")

## 执行节点进入事件
func _execute_node_events(events: Array):
	for event in events:
		_execute_action(event)

## 执行动作
func _execute_actions(actions: Array):
	for action in actions:
		_execute_action(action)

func _execute_action(action: Dictionary):
	var type = action.get("type", "")
	
	match type:
		"give_item":
			var item_id = action.get("item_id", "")
			var count = action.get("count", 1)
			if InventoryModule:
				InventoryModule.add_item(item_id, count)
				npc.show_floating_text("获得: %s x%d" % [item_id, count], Color.GREEN)
			event_triggered.emit("give_item", action)
		
		"remove_item":
			var item_id = action.get("item_id", "")
			var count = action.get("count", 1)
			if InventoryModule:
				InventoryModule.remove_item(item_id, count)
				npc.show_floating_text("失去: %s x%d" % [item_id, count], Color.RED)
			event_triggered.emit("remove_item", action)
		
		"give_quest":
			var quest_id = action.get("quest_id", "")
			if QuestSystem:
				QuestSystem.start_quest(quest_id)
				npc.show_floating_text("接受任务: %s" % quest_id, Color.YELLOW)
			event_triggered.emit("give_quest", action)
		
		"complete_quest_stage":
			var quest_id = action.get("quest_id", "")
			var stage = action.get("stage", "")
			if QuestSystem:
				QuestSystem.complete_stage(quest_id, stage)
			event_triggered.emit("complete_quest_stage", action)
		
		"open_trade":
			# 暂时隐藏对话，打开交易
			DialogModule.hide_dialog()
			if npc.trade_component:
				await npc.open_trade_ui()
			# 交易完成后继续对话
			event_triggered.emit("open_trade", action)
		
		"start_combat":
			DialogModule.hide_dialog()
			var enemy_data = action.get("enemy_data", {})
			if CombatSystem:
				CombatSystem.start_combat(enemy_data)
			event_triggered.emit("start_combat", action)
		
		"change_mood":
			var mood_type = action.get("mood", "")
			var delta = action.get("delta", 0)
			npc.change_mood(mood_type, delta)
			event_triggered.emit("change_mood", action)
		
		"teleport_player":
			var location = action.get("location", "")
			if MapModule:
				MapModule.travel_to(location)
			event_triggered.emit("teleport_player", action)
		
		"show_message":
			var message = action.get("text", "")
			npc.show_floating_text(message)
			event_triggered.emit("show_message", action)
		
		_:
			print("[NPCDialogComponent] 未知动作类型: %s" % type)

# ========== 条件检查 ==========

func _check_conditions(conditions: Array) -> bool:
	for condition in conditions:
		if not _evaluate_condition(condition):
			return false
	return true

func _evaluate_condition(condition: Dictionary) -> bool:
	var type = condition.get("type", "")
	
	match type:
		"always":
			return true
		
		"has_item":
			var item_id = condition.get("item_id", "")
			var count = condition.get("count", 1)
			if InventoryModule:
				return InventoryModule.has_item(item_id, count)
			return false
		
		"quest_completed":
			var quest_id = condition.get("quest_id", "")
			if QuestSystem:
				return QuestSystem.is_quest_completed(quest_id)
			return false
		
		"quest_active":
			var quest_id = condition.get("quest_id", "")
			if QuestSystem:
				return QuestSystem.is_quest_active(quest_id)
			return false
		
		"attribute_check":
			var attr = condition.get("attribute", "")
			var min_value = condition.get("min", 0)
			return context.player_attributes.get(attr, 0) >= min_value
		
		"mood_check":
			var mood = condition.get("mood", "")
			var min_mood = condition.get("min", 0)
			return context.npc_mood.get(mood, 0) >= min_mood
		
		"has_met_player":
			return context.memory.get("met_player", false)
		
		"first_meeting":
			return not context.memory.get("met_player", false)
		
		"time_of_day":
			var start_hour = condition.get("start", 0)
			var end_hour = condition.get("end", 24)
			if TimeManager:
				var current_hour = TimeManager.get_current_hour()
				return current_hour >= start_hour and current_hour <= end_hour
			return true
		
		"can_recruit":
			return npc.can_be_recruited()
		
		"has_available_quests":
			# 检查NPC是否有可接任务
			return npc.npc_data and npc.npc_data.state.active_quests.size() > 0
		
		"random_chance":
			var chance = condition.get("chance", 0.5)
			return randf() < chance
		
		_:
			print("[NPCDialogComponent] 未知条件类型: %s" % type)
			return true

# ========== 技能检定 ==========

func _do_skill_check(skill: String, difficulty: int) -> bool:
	# 获取技能值（通常是属性+随机数）
	var skill_value = context.player_attributes.get(skill, 10)
	var roll = randi() % 100 + 1  # 1-100
	var total = skill_value + roll
	
	var passed = total >= difficulty
	
	skill_check_result.emit(passed, roll, difficulty)
	
	print("[NPCDialogComponent] %s检定: 技能%d + 掷出%d = %d vs 难度%d -> %s" % [
		skill, skill_value, roll, total, difficulty, "通过" if passed else "失败"
	])
	
	return passed

# ========== 情绪影响 ==========

func _apply_mood_effects(effects: Dictionary):
	for mood_type in effects.keys():
		var delta = effects[mood_type]
		npc.change_mood(mood_type, delta)

# ========== 工具方法 ==========

## 替换文本中的变量
func _replace_variables(text: String) -> String:
	if not npc or not npc.npc_data:
		return text
	
	# 替换{name}为NPC名字
	text = text.replace("{name}", npc.npc_name)
	
	# 替换{player_name}
	if GameState:
		text = text.replace("{player_name}", GameState.player_name if GameState.has("player_name") else "幸存者")
	
	# 替换{mood_level}
	var mood_level = npc.npc_data.get_friendlyness_level()
	text = text.replace("{mood_level}", mood_level)
	
	return text

## 清理对话
func _dialog_cleanup():
	DialogModule.hide_dialog()
	context.clear()

# ========== 数据设置 ==========

## 设置对话树
func set_dialog_tree(tree: Dictionary):
	dialog_tree = tree

## 添加对话节点
func add_dialog_node(node_id: String, node_data: Dictionary):
	dialog_tree[node_id] = node_data

## 跳转到指定节点
func jump_to_node(node_id: String):
	current_node_id = node_id
