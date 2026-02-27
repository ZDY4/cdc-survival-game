extends Node
# DayNightRiskSystem - 昼夜风险系统
# 管理夜晚危险度、疲劳系统、随机事"
# ===== 信号 =====
signal night_danger_increased(level: int)
signal fatigue_warning(level: String)
signal fatigue_damage_taken(amount: int)
signal night_event_triggered(event_type: String, event_data: Dictionary)
signal safehouse_warning(distance: int)

# ===== 风险等级 =====
enum DangerLevel { LOW = 0, MEDIUM = 1, HIGH = 2, EXTREME = 3 }

# ===== 疲劳等级 =====
enum FatigueLevel { FRESH = 0, TIRED = 1, EXHAUSTED = 2, COLLAPSING = 3 }

# ===== 当前状"=====
var current_danger_level: int = DangerLevel.LOW
var current_fatigue_level: int = FatigueLevel.FRESH
var fatigue_value: float = 0.0  # 0-100
var is_in_safehouse: bool = true
var hours_outside: float = 0.0
var last_sleep_day: int = 1

# ===== 配置参数 =====
var danger_check_interval: float = 60.0  # "0秒检查一次危险度
var _danger_accumulator: float = 0.0

# 疲劳增加速率（每小时）
const FATIGUE_PER_HOUR: float = 5.0
const FATIGUE_PER_HOUR_NIGHT: float = 10.0

# 疲劳阈值
const FATIGUE_TIRED: float = 30.0
const FATIGUE_EXHAUSTED: float = 60.0
const FATIGUE_COLLAPSING: float = 85.0

# 夜晚随机事件
var night_events: Dictionary = {
	"zombie_ambush": {
		"name": "丧尸伏击",
		"description": "黑暗中，一群丧尸发现了你！",
		"danger_level": DangerLevel.HIGH,
		"weight": 30
	},
	"lost_item": {
		"name": "遗失物品",
		"description": "在黑暗中你不小心丢失了物品",
		"danger_level": DangerLevel.LOW,
		"weight": 20
	},
	"strange_sound": {
		"name": "诡异声响",
		"description": "附近传来令人毛骨悚然的声音，精神受到冲击",
		"danger_level": DangerLevel.MEDIUM,
		"weight": 25
	},
	"lucky_find": {
		"name": "意外发现",
		"description": "在黑暗中你意外发现了一些有用的物资",
		"danger_level": DangerLevel.LOW,
		"weight": 15,
		"is_positive": true
	},
	"severe_injury": {
		"name": "严重摔伤",
		"description": "在黑暗中你绊倒了，受了重伤",
		"danger_level": DangerLevel.EXTREME,
		"weight": 10
	}
}

# 夜间惩罚效果
var night_penalties: Dictionary = {
	DangerLevel.LOW: {
		"enemy_damage_mult": 1.0,
		"enemy_hp_mult": 1.0,
		"player_accuracy": 1.0,
		"encounter_chance": 0.3
	},
	DangerLevel.MEDIUM: {
		"enemy_damage_mult": 1.2,
		"enemy_hp_mult": 1.1,
		"player_accuracy": 0.9,
		"encounter_chance": 0.5
	},
	DangerLevel.HIGH: {
		"enemy_damage_mult": 1.5,
		"enemy_hp_mult": 1.3,
		"player_accuracy": 0.8,
		"encounter_chance": 0.7
	},
	DangerLevel.EXTREME: {
		"enemy_damage_mult": 2.0,
		"enemy_hp_mult": 1.5,
		"player_accuracy": 0.7,
		"encounter_chance": 0.9
	}
}

func _ready():
	print("[DayNightRiskSystem] 昼夜风险系统已初始化")
	
	# 连接时间信号
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager:
		time_manager.night_fallen.connect(_on_night_fallen)
		time_manager.sunrise.connect(_on_sunrise)
		time_manager.time_advanced.connect(_on_time_advanced)
	
	# 连接位置变化信号
	EventBus.subscribe(EventBus.EventType.LOCATION_CHANGED, _on_location_changed)

func _process(delta: float):
	if not is_in_safehouse and TimeManager.is_night():
		_danger_accumulator += delta
		if _danger_accumulator >= danger_check_interval:
			_danger_accumulator = 0.0
			_check_night_danger()

# ===== 事件回调 =====

func _on_night_fallen(current_time: Dictionary):
	if not is_in_safehouse:
		print("[DayNightRiskSystem] 夜幕降临！危险度上升")
		_increase_danger_level()
		DialogModule.show_dialog(
			"夜幕已经降临！外面变得更加危险，建议你尽快返回安全屋",
			"警告",
			""
		)

func _on_sunrise(current_time: Dictionary):
	current_danger_level = DangerLevel.LOW
	print("[DayNightRiskSystem] 太阳升起，危险度恢复正常")

func _on_time_advanced(old_time: Dictionary, new_time: Dictionary):
	# 计算经过的时间
	var hours_passed = 0.0
	if new_time.day > old_time.day:
		hours_passed += (24 - old_time.hour) + new_time.hour
	else:
		hours_passed += new_time.hour - old_time.hour
	
	# 增加疲劳
	if not is_in_safehouse:
		var fatigue_rate = FATIGUE_PER_HOUR
		if TimeManager.is_night():
			fatigue_rate = FATIGUE_PER_HOUR_NIGHT
		_add_fatigue(hours_passed * fatigue_rate)
		hours_outside += hours_passed

func _on_location_changed(data: Dictionary):
	var location = data.get("location", "")
	is_in_safehouse = (location == "safehouse")
	
	if is_in_safehouse:
		# 进入安全屋，逐渐恢复
		_reset_danger()
	else:
		# 离开安全"		if TimeManager.is_night():
			DialogModule.show_dialog(
				"夜晚在外面非常危险！建议你留在安全屋内",
				"警告",
				""
			)

# ===== 危险度管"=====

func _increase_danger_level():
	if current_danger_level < DangerLevel.EXTREME:
		current_danger_level += 1
		night_danger_increased.emit(current_danger_level)
		print("[DayNightRiskSystem] 危险度提升至: %d" % current_danger_level)

func _reset_danger():
	current_danger_level = DangerLevel.LOW
	hours_outside = 0.0
	print("[DayNightRiskSystem] 危险度重")

func _check_night_danger():
	# 根据危险度和时间决定触发什么事件
	var base_chance = 0.1 + (current_danger_level * 0.15)
	if randf() < base_chance:
		_trigger_random_night_event()

func _trigger_random_night_event():
	# 根据危险度筛选事件
	var possible_events: Array[Dictionary] = []
	for event_id in night_events.keys():
		var event_data = night_events[event_id]
		if event_data.danger_level <= current_danger_level + 1:
			possible_events.append({"id": event_id, "data": event_data})
	
	if possible_events.is_empty():
		return
	
	# 加权随机选择
	var total_weight = 0
	for event in possible_events:
		total_weight += event.data.weight
	
	var random_value = randi() % total_weight
	var selected_event = possible_events[0]
	for event in possible_events:
		random_value -= event.data.weight
		if random_value <= 0:
			selected_event = event
			break
	
	# 触发事件
	_execute_night_event(selected_event.id, selected_event.data)

func _execute_night_event(event_id: String, event_data: Dictionary):
	print("[DayNightRiskSystem] 触发夜晚事件: %s" % event_data.name)
	
	night_event_triggered.emit(event_id, event_data)
	
	match event_id:
		"zombie_ambush":
			DialogModule.show_dialog(
				event_data.description + "\n你被迫进入战斗！",
				"危险",
				""
			)
			# 触发战斗
			EventBus.emit(EventBus.EventType.COMBAT_STARTED, {
				"enemy_type": "zombie_group",
				"enemy_count": randi_range(2, 4)
			})
		
		"lost_item":
			DialogModule.show_dialog(
				event_data.description,
				"事件",
				""
			)
			# 随机丢失物品
			if not GameState.inventory_items.is_empty():
				var random_item = GameState.inventory_items[randi() % GameState.inventory_items.size()]
				GameState.remove_item(random_item.id, 1)
		
		"strange_sound":
			DialogModule.show_dialog(
				event_data.description + "\n精神 -10",
				"事件",
				""
			)
			GameState.player_mental = maxi(0, GameState.player_mental - 10)
		
		"lucky_find":
			DialogModule.show_dialog(
				event_data.description + "\n获得了一些物资",
				"幸运",
				""
			)
			# 随机获得物品
			GameState.add_item("bandage", randi_range(1, 3))
		
		"severe_injury":
			DialogModule.show_dialog(
				event_data.description + "\nHP -30",
				"危险",
				""
			)
			GameState.damage_player(30)

# ===== 疲劳系统 =====

func _add_fatigue(amount: float):
	var old_level = current_fatigue_level
	fatigue_value = minf(100.0, fatigue_value + amount)
	_update_fatigue_level()
	
	if current_fatigue_level > old_level:
		_fatigue_level_changed(old_level)

func reduce_fatigue(amount: float):
	fatigue_value = maxf(0.0, fatigue_value - amount)
	_update_fatigue_level()

func rest_in_safehouse():
	fatigue_value = 0.0
	hours_outside = 0.0
	last_sleep_day = TimeManager.current_day
	current_fatigue_level = FatigueLevel.FRESH
	print("[DayNightRiskSystem] 休息完成，疲劳清")

func _update_fatigue_level():
	if fatigue_value >= FATIGUE_COLLAPSING:
		current_fatigue_level = FatigueLevel.COLLAPSING
	elif fatigue_value >= FATIGUE_EXHAUSTED:
		current_fatigue_level = FatigueLevel.EXHAUSTED
	elif fatigue_value >= FATIGUE_TIRED:
		current_fatigue_level = FatigueLevel.TIRED
	else:
		current_fatigue_level = FatigueLevel.FRESH

func _fatigue_level_changed(old_level: int):
	match current_fatigue_level:
		FatigueLevel.TIRED:
			fatigue_warning.emit("tired")
			DialogModule.show_dialog(
				"你感到有些疲劳",
				"疲劳",
				""
			)
		
		FatigueLevel.EXHAUSTED:
			fatigue_warning.emit("exhausted")
			DialogModule.show_dialog(
				"你非常疲惫！各项能力下降，需要休息",
				"疲劳",
				""
			)
			# 应用负面效果
			_apply_fatigue_penalty()
		
		FatigueLevel.COLLAPSING:
			fatigue_warning.emit("collapsing")
			DialogModule.show_dialog(
				"你快要累垮了！必须立即休息！",
				"危险",
				""
			)
			# 持续受到伤害
			_apply_fatigue_damage()

func _apply_fatigue_penalty():
	# 疲劳会影响战斗和探索
	print("[DayNightRiskSystem] 应用疲劳惩罚")

func _apply_fatigue_damage():
	var damage = 5
	GameState.damage_player(damage)
	fatigue_damage_taken.emit(damage)
	print("[DayNightRiskSystem] 疲劳伤害: %d" % damage)

# ===== 获取当前惩罚效果 =====

func get_current_penalties() -> Dictionary:
	var penalties = night_penalties[current_danger_level].duplicate()
	
	# 应用疲劳惩罚
	match current_fatigue_level:
		FatigueLevel.TIRED:
			penalties.player_accuracy *= 0.9
		FatigueLevel.EXHAUSTED:
			penalties.player_accuracy *= 0.75
			penalties.enemy_damage_mult *= 1.2
		FatigueLevel.COLLAPSING:
			penalties.player_accuracy *= 0.5
			penalties.enemy_damage_mult *= 1.5
	
	return penalties

func get_fatigue_effects() -> Dictionary:
	match current_fatigue_level:
		FatigueLevel.FRESH:
			return {"name": "精神饱满", "effects": []}
		FatigueLevel.TIRED:
			return {"name": "疲劳", "effects": ["命中-10%"]}
		FatigueLevel.EXHAUSTED:
			return {"name": "精疲力竭", "effects": ["命中-25%", "受到伤害 +20%"]}
		FatigueLevel.COLLAPSING:
			return {"name": "濒临崩溃", "effects": ["命中-50%", "受到伤害 +50%", "持续受到伤害"]}
		_:
			return {"name": "未知", "effects": []}

# ===== 查询方法 =====

func is_safe() -> bool:
	return is_in_safehouse or TimeManager.is_day()

func get_current_danger_level() -> int:
	return current_danger_level

func get_current_fatigue_level() -> int:
	return current_fatigue_level

func get_fatigue_value() -> float:
	return fatigue_value

func get_fatigue_percent() -> float:
	return fatigue_value / 100.0

func get_danger_level_name() -> String:
	match current_danger_level:
		DangerLevel.LOW: return "安全"
		DangerLevel.MEDIUM: return "警告"
		DangerLevel.HIGH: return "危险"
		DangerLevel.EXTREME: return "极度危险"
		_: return "未知"

func get_fatigue_level_name() -> String:
	match current_fatigue_level:
		FatigueLevel.FRESH: return "精神饱满"
		FatigueLevel.TIRED: return "疲"
		FatigueLevel.EXHAUSTED: return "精疲力竭"
		FatigueLevel.COLLAPSING: return "濒临崩溃"
		_: return "未知"

# ===== 序列"=====

func serialize() -> Dictionary:
	return {
		"danger_level": current_danger_level,
		"fatigue_level": current_fatigue_level,
		"fatigue_value": fatigue_value,
		"is_in_safehouse": is_in_safehouse,
		"hours_outside": hours_outside,
		"last_sleep_day": last_sleep_day
	}

func deserialize(data: Dictionary):
	current_danger_level = data.get("danger_level", DangerLevel.LOW)
	current_fatigue_level = data.get("fatigue_level", FatigueLevel.FRESH)
	fatigue_value = data.get("fatigue_value", 0.0)
	is_in_safehouse = data.get("is_in_safehouse", true)
	hours_outside = data.get("hours_outside", 0.0)
	last_sleep_day = data.get("last_sleep_day", 1)
	print("[DayNightRiskSystem] 风险系统数据已加")

