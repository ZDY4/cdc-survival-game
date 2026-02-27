extends BaseModule
# WeatherModule - 天气系统

signal weather_changed(new_weather: String)
signal time_changed(hour: int, day: int)
signal danger_level_changed(level: int)

enum WeatherType { CLEAR, CLOUDY, RAIN, STORM, FOG }

const WEATHER_EFFECTS = {
	"clear": {"visibility": 1.0, "movement_speed": 1.0, "danger_multiplier": 1.0},
	"cloudy": {"visibility": 0.9, "movement_speed": 1.0, "danger_multiplier": 1.1},
	"rain": {"visibility": 0.7, "movement_speed": 0.8, "danger_multiplier": 1.2},
	"storm": {"visibility": 0.5, "movement_speed": 0.6, "danger_multiplier": 1.5},
	"fog": {"visibility": 0.4, "movement_speed": 0.9, "danger_multiplier": 1.3}
}

var current_weather: String = "clear"
var current_danger_level: int = 0

func _ready():
	# 每分钟更新一次时间
	var timer = Timer.new()
	timer.wait_time = 60.0  # 60秒 = 游戏中1小时
	timer.timeout.connect(_on_time_tick)
	add_child(timer)
	timer.start()

func _on_time_tick():
	advance_time()

func advance_time(hours: int = 1):
	GameState.world_time += hours
	
	if GameState.world_time >= 24:
		GameState.world_time = 0
		GameState.world_day += 1
	
	# 每3小时随机改变天气
	if GameState.world_time % 3 == 0:
		_randomize_weather()
	
	# 每6小时更新危险等级
	if GameState.world_time % 6 == 0:
		_update_danger_level()
	
	time_changed.emit(GameState.world_time, GameState.world_day)

func set_time(hour: int, day: int = -1):
	GameState.world_time = clampi(hour, 0, 23)
	if day > 0:
		GameState.world_day = day
	time_changed.emit(GameState.world_time, GameState.world_day)

func get_time_string():
	var hour = GameState.world_time
	var am_pm = "AM" if hour < 12 else "PM"
	var display_hour = hour if hour <= 12 else hour - 12
	if display_hour == 0:
		display_hour = 12
	return "第%d天 %d:00 %s" % [GameState.world_day, display_hour, am_pm]

func _randomize_weather():
	var weathers = WEATHER_EFFECTS.keys()
	var new_weather = weathers[randi() % weathers.size()]
	
	if new_weather != current_weather:
		current_weather = new_weather
		GameState.world_weather = new_weather
		weather_changed.emit(new_weather)

func set_weather(weather_type: String):
	if WEATHER_EFFECTS.has(weather_type):
		current_weather = weather_type
		GameState.world_weather = weather_type
		weather_changed.emit(weather_type)

func get_weather_effects():
	return WEATHER_EFFECTS.get(current_weather, WEATHER_EFFECTS["clear"])

func _update_danger_level():
	var base_danger = 0
	
	# 夜晚增加危险
	if GameState.world_time >= 20 || GameState.world_time <= 5:
		base_danger += 1
	
	# 恶劣天气增加危险
	if current_weather in ["storm", "fog"]:
		base_danger += 1
	
	# 根据天数增加危险 (整数除法，每5天增加1级)
	base_danger += int(GameState.world_day / 5.0)
	
	current_danger_level = mini(base_danger, 5)
	danger_level_changed.emit(current_danger_level)

func get_current_weather():
	return current_weather

func get_current_hour():
	return GameState.world_time

func get_current_day():
	return GameState.world_day

func get_danger_level():
	return current_danger_level

# 应用天气对玩家的影响
func apply_weather_effects():
	# 雨天增加口渴消耗
	if current_weather == "rain":
		GameState.player_thirst = maxi(0, GameState.player_thirst - 1)
	
	# 暴风雪/极端天气损失体力
	if current_weather == "storm":
		GameState.player_stamina = maxi(0, GameState.player_stamina - 2)
