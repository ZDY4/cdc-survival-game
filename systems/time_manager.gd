extends Node
# TimeManager - 时间管理系统
# 管理游戏时间推进、昼夜循环、活动时间消耗
# ===== 时间配置 =====
const DAY_START_HOUR: int = 6   # 白天开始时间06:00
const NIGHT_START_HOUR: int = 18 # 夜晚开始时间18:00
const HOURS_PER_DAY: int = 24
const MINUTES_PER_HOUR: int = 60

# ===== 信号 =====
signal time_advanced(old_time: Dictionary, new_time: Dictionary)
signal day_changed(new_day: int)
signal night_fallen(current_time: Dictionary)
signal sunrise(current_time: Dictionary)
signal hour_passed(hour: int)
# ===== 当前时间状态 =====
var current_day: int = 1
var current_hour: int = 8    # 游戏开始时间08:00
var current_minute: int = 0

# ===== 运行状态 =====
var is_time_running: bool = false
var time_scale: float = 1.0  # 时间流速倍率
var _accumulated_time: float = 0.0

# ===== 状态衰减配置 =====
var _status_decay_enabled: bool = true
const HUNGER_DECAY_PER_HOUR: int = 2
const THIRST_DECAY_PER_HOUR: int = 3
const STAMINA_DECAY_PER_HOUR: int = 1
const MENTAL_DECAY_PER_HOUR: int = 1

# ===== 时间流逝配置 =====
var real_seconds_per_game_minute: float = 1.0  # 1秒现实时间 = 1分钟游戏时间

func _ready():
	print("[TimeManager] 时间管理系统已初始化")
	start_time()

func _process(delta: float):
	if is_time_running:
		_accumulated_time += delta * time_scale
		var minutes_to_advance = floor(_accumulated_time / real_seconds_per_game_minute)
		if minutes_to_advance > 0:
			_accumulated_time -= minutes_to_advance * real_seconds_per_game_minute
			_advance_minutes(int(minutes_to_advance))

# ===== 时间控制 =====

func start_time():
	is_time_running = true
	print("[TimeManager] 时间开始流")

func pause_time():
	is_time_running = false
	print("[TimeManager] 时间已暂")

func resume_time():
	is_time_running = true
	print("[TimeManager] 时间已恢")

func set_time_scale(scale: float):
	time_scale = maxf(0.0, scale)
	print("[TimeManager] 时间流速设置为: ", time_scale)

# ===== 时间推进 =====

## 推进指定分钟
func advance_minutes(minutes: int) -> Dictionary:
	var old_time = get_current_time_dict()
	_advance_minutes(minutes)
	var new_time = get_current_time_dict()
	return {"old_time": old_time, "new_time": new_time}

## 推进指定小时
func advance_hours(hours: int) -> Dictionary:
	return advance_minutes(hours * MINUTES_PER_HOUR)

## 内部时间推进逻辑
func _advance_minutes(minutes: int):
	if minutes <= 0:
		return
	
	var old_hour = current_hour
	var old_day = current_day
	var old_minute = current_minute
	var was_night = is_night()
	
	# 计算新的时间
	var total_minutes = current_minute + minutes
	current_minute = total_minutes % MINUTES_PER_HOUR
	var hours_added: int = floori(float(total_minutes) / float(MINUTES_PER_HOUR))
	
	var total_hours = current_hour + hours_added
	current_hour = total_hours % HOURS_PER_DAY
	var days_added: int = floori(float(total_hours) / float(HOURS_PER_DAY))
	
	current_day += days_added
	
	# 应用状态衰减
	if _status_decay_enabled and hours_added > 0:
		_apply_status_decay(hours_added)
	
	# 发送信号
	var old_time = {"day": old_day, "hour": old_hour, "minute": old_minute}
	var new_time = get_current_time_dict()
	time_advanced.emit(old_time, new_time)
	
	# 检测小时变化
	if hours_added > 0:
		for i in range(hours_added):
			hour_passed.emit((old_hour + i + 1) % HOURS_PER_DAY)
	
	# 检测天数变化
	if days_added > 0:
		for i in range(days_added):
			day_changed.emit(old_day + i + 1)
	
	# 检测昼夜切换
	var is_night_now = is_night()
	if was_night and not is_night_now:
		sunrise.emit(new_time)
	elif not was_night and is_night_now:
		night_fallen.emit(new_time)

## 应用状态衰减
func _apply_status_decay(hours: int):
	if not GameState:
		return
	
	for i in range(hours):
		# 饥饿衰减
		GameState.player_hunger = maxi(0, GameState.player_hunger - HUNGER_DECAY_PER_HOUR)
		
		# 口渴衰减
		GameState.player_thirst = maxi(0, GameState.player_thirst - THIRST_DECAY_PER_HOUR)
		
		# 体力衰减 (根据活动状态)
		var stamina_decay = STAMINA_DECAY_PER_HOUR
		if is_night():
			stamina_decay += 1  # 夜间更累
		GameState.player_stamina = maxi(0, GameState.player_stamina - stamina_decay)
		
		# 精神衰减
		var mental_decay = MENTAL_DECAY_PER_HOUR
		if is_night() and not GameState.player_position == "survivor_outpost_01":
			mental_decay += 2  # 夜间在室外精神下降更快
			GameState.player_mental = maxi(0, GameState.player_mental - mental_decay)
	
	# 发送状态变化事件
	EventBus.emit(EventBus.EventType.STATUS_CHANGED, {
		"hunger": GameState.player_hunger,
		"thirst": GameState.player_thirst,
		"stamina": GameState.player_stamina,
		"mental": GameState.player_mental
	})

## 设置状态衰减开关
func set_status_decay_enabled(enabled: bool):
	_status_decay_enabled = enabled
	print("[TimeManager] 状态衰减已%s" % ("启用" if enabled else "禁用"))

## 获取状态衰减倍率 (用于休息)
func get_decay_multiplier() -> float:
	return 1.0

# ===== 活动耗时接口 =====

## 执行活动并消耗时间
func do_activity(activity_name: String, minutes_cost: int, callback: Callable = Callable()) -> Dictionary:
	print("[TimeManager] 执行活动 '%s'，耗时 %d 分钟" % [activity_name, minutes_cost])
	
	var result = advance_minutes(minutes_cost)
	result["activity"] = activity_name
	
	if callback.is_valid():
		callback.call(result)
	
	return result

## 快速活动 - 消耗少量时间
func quick_activity(activity_name: String) -> Dictionary:
	return do_activity(activity_name, 5)  # 5分钟

## 普通活动 - 消耗中等时间
func normal_activity(activity_name: String) -> Dictionary:
	return do_activity(activity_name, 30)  # 30分钟

## 长活动 - 消耗大量时间
func long_activity(activity_name: String) -> Dictionary:
	return do_activity(activity_name, 120)  # 2小时

## 旅行活动
func travel_activity(from_location: String, to_location: String, minutes: int = 15) -> Dictionary:
	return do_activity("%s 前往 %s" % [from_location, to_location], minutes)

## 战斗活动
func combat_activity(enemy_name: String, rounds: int = 3) -> Dictionary:
	var minutes = rounds * 2  # 每回合2分钟
	return do_activity("%s 战斗" % enemy_name, minutes)

## 搜索活动
func search_activity(location: String) -> Dictionary:
	return do_activity("%s 搜索" % location, 20)

## 制作活动
func crafting_activity(item_name: String, complexity: int = 1) -> Dictionary:
	var minutes = complexity * 15
	return do_activity("制作 %s" % item_name, minutes)

## 休息活动
func rest_activity(hours: int = 8) -> Dictionary:
	# 休息时状态衰减减缓，部分状态恢复
	_status_decay_enabled = false
	var result = do_activity("休息", hours * 60)
	_status_decay_enabled = true
	
	# 恢复体力
	if GameState:
		GameState.player_stamina = mini(100, GameState.player_stamina + hours * 15)
		GameState.player_mental = mini(100, GameState.player_mental + hours * 10)
	
	return result

# ===== 查询方法 =====

func is_day() -> bool:
	return current_hour >= DAY_START_HOUR and current_hour < NIGHT_START_HOUR

func is_night() -> bool:
	return not is_day()

func get_time_period() -> String:
	if current_hour >= 5 and current_hour < 8:
		return "清晨"
	elif current_hour >= 8 and current_hour < 12:
		return "上午"
	elif current_hour >= 12 and current_hour < 14:
		return "中午"
	elif current_hour >= 14 and current_hour < 18:
		return "下午"
	elif current_hour >= 18 and current_hour < 20:
		return "傍晚"
	elif current_hour >= 20 and current_hour < 24:
		return "夜晚"
	else:
		return "深夜"

func get_formatted_time() -> String:
	return "%02d:%02d" % [current_hour, current_minute]

func get_formatted_date() -> String:
	return "%d %s" % [current_day, get_time_period()]

func get_full_datetime() -> String:
	return "%d %s %s" % [current_day, get_formatted_time(), get_time_period()]

func get_current_time_dict() -> Dictionary:
	return {
		"day": current_day,
		"hour": current_hour,
		"minute": current_minute,
		"period": get_time_period(),
		"is_day": is_day(),
		"is_night": is_night()
	}

# ===== 时间设置 =====

func set_time(day: int, hour: int, minute: int = 0):
	current_day = maxi(1, day)
	current_hour = clampi(hour, 0, 23)
	current_minute = clampi(minute, 0, 59)
	print("[TimeManager] 时间设置为: ", get_full_datetime())

func set_hour(hour: int):
	current_hour = clampi(hour, 0, 23)

# ===== 序列化 =====

func serialize() -> Dictionary:
	return {
		"day": current_day,
		"hour": current_hour,
		"minute": current_minute,
		"time_scale": time_scale,
		"is_running": is_time_running
	}

func deserialize(data: Dictionary):
	current_day = data.get("day", 1)
	current_hour = data.get("hour", 8)
	current_minute = data.get("minute", 0)
	time_scale = data.get("time_scale", 1.0)
	is_time_running = data.get("is_running", true)
	print("[TimeManager] 时间数据已加载: ", get_full_datetime())

