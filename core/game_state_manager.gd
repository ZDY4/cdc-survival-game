extends Node
# GameStateManager - 游戏状态管理器
# 负责管理游戏全局进度、状态、剧情分支和结局

signal scene_changed(scene_id: String, scene_data: Dictionary)
signal flag_changed(flag_name: String, value)
signal progress_advanced(from_scene: String, to_scene: String, choice_id: String)
signal ending_triggered(ending_id: String, ending_data: Dictionary)
signal relationship_changed(npc_id: String, new_value: int, change: int)

# ===== 核心数据存储 =====
var current_scene_id: String = ""
var current_chapter: String = "chapter_1"
var game_flags: Dictionary = {}      # 游戏标记系统
var choice_history: Array = []        # 玩家选择历史
var relationship_points: Dictionary = {}  # NPC好感度
var forced_hostile_characters: Dictionary = {}  # 强制敌对角色
var discovered_locations: Array = []  # 已发现地点
var unlocked_content: Array = []      # 已解锁内容
var play_time: float = 0.0           # 游戏时长

# ===== 剧情配置数据 =====
const CHAPTERS = {
	"chapter_1": {
		"name": "第一章：觉醒",
		"description": "在末日中醒来，学习生存",
		"start_scene": "scene_001_wake_up",
		"required_flags": [],
		"unlock_flags": ["chapter_1_complete"]
	},
	"chapter_2": {
		"name": "第二章：探索",
		"description": "探索周边，遭遇其他幸存者",
		"start_scene": "scene_201_street_explore",
		"required_flags": ["chapter_1_complete"],
		"unlock_flags": ["chapter_2_complete"]
	},
	"chapter_3": {
		"name": "第三章：真相",
		"description": "揭开CDC阴谋",
		"start_scene": "scene_301_hospital_secret",
		"required_flags": ["chapter_2_complete", "found_evidence"],
		"unlock_flags": ["chapter_3_complete"]
	}
}

# ===== 初始化 =====
func _ready():
	print("[GameStateManager] 游戏状态管理器已初始化")

# ===== 场景管理 =====

# 跳转到指定场景
func transition_to(scene_id: String, transition_data: Dictionary = {}):
	if not _scene_exists(scene_id):
		push_error("Scene not found: " + scene_id)
		return false
	
	var previous_scene = current_scene_id
	current_scene_id = scene_id
	
	var scene_data = _get_scene_data(scene_id)
	
	# 触发场景进入事件
	_execute_scene_entry(scene_data, transition_data)
	
	# 发送信号
	scene_changed.emit(scene_id, scene_data)
	
	if previous_scene != "":
		progress_advanced.emit(previous_scene, scene_id, transition_data.get("choice_id", ""))
	
	# 检查章节切换
	_check_chapter_progression()
	
	# 检查结局条件
	_check_ending_conditions()
	
	return true

# 获取当前场景数据
func get_current_scene():
	return _get_scene_data(current_scene_id)

# 获取场景历史（用于"回到上一场景"功能）
func get_scene_history(limit: int = 5):
	var history = []
	for choice in choice_history.slice(-limit):
		history.append({
			"scene": choice.scene_id,
			"choice": choice.choice_text,
			"timestamp": choice.timestamp
		})
	return history

# ===== 标记系统（核心功能）=====

# 设置标记
func set_flag(flag_name: String, value: Variant = true):
	var _old_value = game_flags.get(flag_name)
	game_flags[flag_name] = value
	
	flag_changed.emit(flag_name, value)
	
	print("[GameState] Flag set: %s = %s" % [flag_name, str(value)])
	
	# 检查是否触发成就或解锁
	_check_flag_triggers(flag_name, value)

# 获取标记
func get_flag(flag_name: String, default_value: Variant = null):
	return game_flags.get(flag_name, default_value)

# 切换布尔标记
func toggle_flag(flag_name: String):
	var current = get_flag(flag_name, false)
	set_flag(flag_name, not current)

# 增加数值标记
func add_to_flag(flag_name: String, amount: float = 1.0):
	var current = get_flag(flag_name, 0)
	set_flag(flag_name, current + amount)

# 检查标记是否存在
func has_flag(flag_name: String):
	return game_flags.has(flag_name)

# ===== 条件检查系统 =====

# 通用条件检查
func check_conditions(conditions: Array):
	for condition in conditions:
		if not _check_single_condition(condition):
			return false
	return true

func _check_single_condition(condition: Dictionary):
	var type = condition.get("type", "")
	
	match type:
		"flag":  # 标记检查
			var flag_value = get_flag(condition.flag, condition.get("default", false))
			return flag_value == condition.value
		
		"flag_range":  # 数值范围检查
			var flag_value = get_flag(condition.flag, 0)
			return flag_value >= condition.min && flag_value <= condition.max
		
		"has_item":  # 物品检查
			return InventoryModule.has_item(condition.item, condition.get("count", 1))
		
		"stat":  # 属性检查
			var stat_value = _get_player_stat(condition.stat)
			match condition.get("op", ">="):
				">=": return stat_value >= condition.value
				">": return stat_value > condition.value
				"<=": return stat_value <= condition.value
				"<": return stat_value < condition.value
				"=": return stat_value == condition.value
				"!=": return stat_value != condition.value
		
		"skill":  # 技能检查
			return SkillModule.get_skill_level(condition.skill) >= condition.level
		
		"relationship":  # 好感度检查
			var relation = get_relationship(condition.npc)
			return relation >= condition.value
		
		"location":  # 地点检查
			return GameState.player_position == condition.location
		
		"time":  # 时间检查
			return _check_time_condition(condition)
		
		"completed_quest":  # 任务完成检查
			return QuestSystem.is_quest_completed(condition.quest_id)
		
		"active_quest":  # 任务进行中检查
			return QuestSystem.is_quest_active(condition.quest_id)
		
		"survival_days":  # 生存天数检查
			return GameState.world_day >= condition.days
		
		"choice_made":  # 做过某选择
			return _has_made_choice(condition.choice_id)
		
		"any":  # 任一条件满足（OR逻辑）
			for sub_condition in condition.conditions:
				if _check_single_condition(sub_condition):
					return true
			return false
		
		"all":  # 所有条件满足（AND逻辑，默认）
			for sub_condition in condition.conditions:
				if not _check_single_condition(sub_condition):
					return false
			return true
	
	return false

# ===== 后果执行系统 =====

# 执行后果列表
func execute_consequences(consequences: Array):
	for consequence in consequences:
		_execute_consequence(consequence)

func _execute_consequence(consequence: Dictionary):
	var type = consequence.get("type", "")
	
	match type:
		"set_flag":
			set_flag(consequence.flag, consequence.value)
		
		"modify_flag":
			add_to_flag(consequence.flag, consequence.get("amount", 1))
		
		"add_item":
			InventoryModule.add_item(consequence.item, consequence.get("count", 1))
		
		"remove_item":
			InventoryModule.remove_item(consequence.item, consequence.get("count", 1))
		
		"damage":
			GameState.damage_player(consequence.amount)
		
		"heal":
			GameState.heal_player(consequence.amount)
		
		"modify_stat":
			_modify_player_stat(consequence.stat, consequence.amount)
		
		"change_relationship":
			modify_relationship(consequence.npc, consequence.change)
		
		"unlock_location":
			MapModule.unlock_location(consequence.location)
			discovered_locations.append(consequence.location)
		
		"start_quest":
			QuestSystem.start_quest(consequence.quest_id)
		
		"complete_quest":
			QuestSystem.complete_quest(consequence.quest_id)
		
		"update_quest":
			QuestSystem.update_quest_progress(
				consequence.quest_id,
				consequence.objective_type,
				consequence.get("amount", 1)
			)
		
		"teleport":
			GameState.travel_to(consequence.location)
			get_tree().change_scene_to_file(consequence.scene_path)
		
		"spawn_enemy":
			# TODO: 实现生成敌人功能
			print("[GameStateManager] 生成敌人: ", consequence.enemy_data)
		
		"trigger_event":
			# TODO: 触发自定义事件
			print("[GameStateManager] 触发事件: ", consequence.event_data)
		
		"play_sound":
			# AudioManager.play_sound(consequence.sound_id)
			pass
		
		"show_dialog":
			DialogModule.show_dialog(
				consequence.text,
				consequence.get("speaker", ""),
				consequence.get("portrait", "")
			)
		
		"wait":
			await get_tree().create_timer(consequence.seconds).timeout
		
		"enable_crafting":
			CraftingSystem.unlock_recipe(consequence.recipe_id)
		
		"add_equipment":
			InventoryModule.add_item(consequence.equipment_id, 1)
		
		"ending":
			trigger_ending(consequence.ending_id)

# ===== NPC关系系统 =====

# 修改好感度
func modify_relationship(npc_id: String, change: int):
	if not relationship_points.has(npc_id):
		relationship_points[npc_id] = 0
	
	var _old_value = relationship_points[npc_id]
	relationship_points[npc_id] += change
	
	# 限制范围 -100 到 100
	relationship_points[npc_id] = clampi(relationship_points[npc_id], -100, 100)
	
	relationship_changed.emit(npc_id, relationship_points[npc_id], change)
	
	print("[GameState] Relationship: %s %d -> %d" % [npc_id, _old_value, relationship_points[npc_id]])

func set_character_hostile(npc_id: String, hostile: bool = true):
	if npc_id.is_empty():
		return
	if hostile:
		forced_hostile_characters[npc_id] = true
	else:
		forced_hostile_characters.erase(npc_id)
	relationship_changed.emit(npc_id, get_relationship(npc_id), 0)
	print("[GameState] Hostility override: %s -> %s" % [npc_id, str(hostile)])

func is_character_forced_hostile(npc_id: String) -> bool:
	if npc_id.is_empty():
		return false
	return bool(forced_hostile_characters.get(npc_id, false))

# 获取好感度
func get_relationship(npc_id: String):
	return relationship_points.get(npc_id, 0)

# 获取关系等级描述
func get_relationship_level(npc_id: String):
	if is_character_forced_hostile(npc_id):
		return "敌对"
	var points = get_relationship(npc_id)
	
	if points >= 80: return "崇拜"
	if points >= 50: return "友好"
	if points >= 20: return "熟悉"
	if points >= -20: return "中立"
	if points >= -50: return "怀疑"
	if points >= -80: return "敌对"
	return "仇恨"

# ===== 选择历史 =====

# 记录选择
func record_choice(scene_id: String, choice_id: String, choice_text: String):
	choice_history.append({
		"scene_id": scene_id,
		"choice_id": choice_id,
		"choice_text": choice_text,
		"timestamp": Time.get_unix_time_from_system(),
		"game_day": GameState.world_day
	})

# 检查是否做过某选择
func _has_made_choice(choice_id: String):
	for choice in choice_history:
		if choice.choice_id == choice_id:
			return true
	return false

# 获取选择统计
func get_choice_statistics():
	var stats = {
		"total_choices": choice_history.size(),
		"good_choices": 0,
		"evil_choices": 0,
		"neutral_choices": 0
	}
	
	for choice in choice_history:
		if choice.choice_id.begins_with("good_"):
			stats.good_choices += 1
		elif choice.choice_id.begins_with("evil_"):
			stats.evil_choices += 1
		else:
			stats.neutral_choices += 1
	
	return stats

# ===== 结局系统 =====

const ENDINGS = {
	"ending_escape": {
		"name": "逃离",
		"description": "你成功逃离了城市...",
		"conditions": [
			{"type": "flag", "flag": "found_vehicle", "value": true},
			{"type": "flag", "flag": "has_fuel", "value": true}
		],
		"priority": 1
	},
	"ending_hero": {
		"name": "英雄",
		"description": "你揭发了CDC的阴谋，拯救了幸存者...",
		"conditions": [
			{"type": "flag", "flag": "found_evidence", "value": true},
			{"type": "flag", "flag": "broadcast_truth", "value": true}
		],
		"priority": 2
	},
	"ending_ruler": {
		"name": "暴君",
		"description": "你控制了所有资源，成为废土之王...",
		"conditions": [
			{"type": "flag", "flag": "killed_rivals", "value": true},
			{"type": "flag", "flag": "hoarded_resources", "value": true}
		],
		"priority": 3
	},
	"ending_sacrifice": {
		"name": "牺牲",
		"description": "你将血清给了别人，自己...",
		"conditions": [
			{"type": "flag", "flag": "gave_serum", "value": true}
		],
		"priority": 4
	},
	"ending_survivor": {
		"name": "生存者",
		"description": "你独自生存了100天...",
		"conditions": [
			{"type": "survival_days", "days": 100}
		],
		"priority": 99  # 最低优先级
	}
}

# 检查结局条件
func _check_ending_conditions():
	for ending_id in ENDINGS.keys():
		var ending = ENDINGS[ending_id]
		
		if check_conditions(ending.conditions):
			trigger_ending(ending_id)
			return

# 触发结局
func trigger_ending(ending_id: String):
	if not ENDINGS.has(ending_id):
		return
	
	var ending = ENDINGS[ending_id]
	ending_triggered.emit(ending_id, ending)
	
	print("[GameState] Ending triggered: " + ending.name)
	
	# 显示结局画面
	_show_ending_screen(ending)

func _show_ending_screen(ending: Dictionary):
	DialogModule.show_dialog(
		"【结局：%s】\n\n%s" % [ending.name, ending.description],
		"结局",
		""
	)
	
	_save_completion_data(ending)

# ===== 章节系统 =====

# 检查章节进度
func _check_chapter_progression():
	for chapter_id in CHAPTERS.keys():
		var chapter = CHAPTERS[chapter_id]
		
		# 构建条件数组
		var flag_conditions = []
		for f in chapter.required_flags:
			flag_conditions.append({"type": "flag", "flag": f, "value": true})
		
		if check_conditions([{"type": "all", "conditions": flag_conditions}]):
			for unlock_flag in chapter.unlock_flags:
				set_flag(unlock_flag, true)

# 获取当前章节
func get_current_chapter():
	return CHAPTERS.get(current_chapter, {})

# ===== 辅助方法 =====

func _scene_exists(_scene_id: String):
	return true

func _get_scene_data(_scene_id: String):
	return {}

func _execute_scene_entry(scene_data: Dictionary, _transition_data: Dictionary):
	if scene_data.has("entry_consequences"):
		execute_consequences(scene_data.entry_consequences)

func _check_flag_triggers(_flag_name: String, _flag_value: Variant):
	pass

func _get_player_stat(stat_name: String):
	match stat_name:
		"strength", "str": return 10
		"agility", "agi": return 10
		"intelligence", "int": return 10
		"luck": return 10
	return 10

func _modify_player_stat(_stat_name: String, _amount: int):
	pass

func _check_time_condition(_condition: Dictionary):
	return true

func _save_completion_data(ending: Dictionary):
	var save_data = {
		"ending": ending.name,
		"play_time": play_time,
		"choices": choice_history.size(),
		"day": GameState.world_day,
		"timestamp": Time.get_unix_time_from_system()
	}
	print("[GameStateManager] Completion saved: " + str(save_data))

# ===== 存档/读档 =====

func get_save_data():
	return {
		"current_scene": current_scene_id,
		"current_chapter": current_chapter,
		"flags": game_flags,
		"choice_history": choice_history,
		"relationships": relationship_points,
		"forced_hostile_characters": forced_hostile_characters,
		"discovered_locations": discovered_locations,
		"play_time": play_time
	}

func load_save_data(data: Dictionary):
	current_scene_id = data.get("current_scene", "")
	current_chapter = data.get("current_chapter", "chapter_1")
	game_flags = data.get("flags", {})
	choice_history = data.get("choice_history", [])
	relationship_points = data.get("relationships", {})
	forced_hostile_characters = data.get("forced_hostile_characters", {})
	discovered_locations = data.get("discovered_locations", [])
	play_time = data.get("play_time", 0.0)
	
	print("[GameStateManager] Loaded save data")
