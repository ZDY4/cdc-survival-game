extends Node
# SurvivalStatusSystem - 生存状态系"# 管理体温、免疫力等核心生存状态，实现状态互相影响链

# ===== 信号 =====
signal body_temperature_changed(new_temp: float, status: String)
signal immunity_changed(new_immunity: float)
signal fatigue_changed(new_fatigue: int)
signal infection_risk_changed(risk: float)
signal status_warning_triggered(warning_type: String, severity: String)
signal status_chain_updated(chain_data: Dictionary)

# ===== 体温系统 =====
const TEMP_NORMAL_MIN: float = 35.0
const TEMP_NORMAL_MAX: float = 39.0
const TEMP_OPTIMAL: float = 37.0
const TEMP_DAMAGE_THRESHOLD_LOW: float = 32.0
const TEMP_DAMAGE_THRESHOLD_HIGH: float = 42.0
const TEMP_DAMAGE_PER_SEC: float = 1.0

var body_temperature: float = 37.0  # 当前体温
var temp_change_rate: float = 0.0   # 体温变化"
# ===== 免疫力系"=====
var immunity: float = 100.0         # 免疫"(0-100)
const IMMUNITY_MAX: float = 100.0
const IMMUNITY_MIN: float = 0.0
const IMMUNITY_REGEN_BASE: float = 0.05

# ===== 疲劳系统 =====
var fatigue: int = 0                # 疲劳"(0-100)
const FATIGUE_MAX: int = 100
const FATIGUE_EXHAUSTED: int = 80   # 精疲力竭阈值
const FATIGUE_TIRED: int = 50       # 疲劳阈值
# ===== 感染系统 =====
var infection_level: float = 0.0    # 感染程度 (0-100)
var infection_active: bool = false  # 是否感染中
const INFECTION_THRESHOLD: float = 50.0  # 感染确认阈值
# ===== 状态影响链配置 =====
# 饥饿影响体温、免疫力、恢复速度
const CHAIN_HUNGER_TO_TEMP: float = -0.1      # 每点饥饿不足降低0.1°C
const CHAIN_TEMP_TO_IMMUNITY: float = -2.0    # 每度偏离降低2点免疫力
const CHAIN_IMMUNITY_TO_REGEN: float = 0.5    # 每点免疫力提".5%恢复加成

# ===== 环境因素影响 =====
var ambient_temperature: float = 25.0  # 环境温度
var wetness: float = 0.0               # 潮湿程度 (0-100)
var weather_protection: float = 0.0    # 天气防护 (0-1)

# ===== 运行状"=====
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 1.0     # 每秒更新一"
func _ready():
	print("[SurvivalStatusSystem] 生存状态系统已初始")
	_connect_signals()

func _connect_signals():
	# 连接时间信号
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager:
		time_manager.time_advanced.connect(_on_time_advanced)
	
	# 连接事件总线
	EventBus.subscribe(EventBus.EventType.PLAYER_HURT, _on_player_hurt)
	EventBus.subscribe(EventBus.EventType.WEATHER_CHANGED, _on_weather_changed)

func _process(delta):
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_update_status_chain()

# ===== 状态更新链 =====
func _update_status_chain():
	if not GameState:
		return
	
	var chain_data = {
		"hunger_factor": 0.0,
		"temp_factor": 0.0,
		"immunity_factor": 0.0,
		"regen_factor": 1.0
	}
	
	# 1. 饥饿影响体温
	var hunger = GameState.player_hunger
	var hunger_deficit = maxi(0, 50 - hunger)  # 低于50开始影响
	if hunger_deficit > 0:
		var temp_penalty = hunger_deficit * CHAIN_HUNGER_TO_TEMP * 0.1
		body_temperature += temp_penalty * 0.01
		chain_data.hunger_factor = temp_penalty
	
	# 2. 环境温度影响
	_apply_ambient_temperature_effect()
	
	# 3. 潮湿影响 (潮湿会降低体温)
	if wetness > 0:
		var wet_penalty = (wetness / 100.0) * 0.05
		body_temperature -= wet_penalty
	
	# 4. 体温影响免疫力
	var temp_deviation = abs(body_temperature - TEMP_OPTIMAL)
	if temp_deviation > 2.0:
		var immunity_penalty = temp_deviation * CHAIN_TEMP_TO_IMMUNITY * 0.01
		immunity = maxf(IMMUNITY_MIN, immunity - immunity_penalty)
		chain_data.temp_factor = -immunity_penalty
	else:
		# 体温正常时缓慢恢复免疫力
		immunity = minf(IMMUNITY_MAX, immunity + IMMUNITY_REGEN_BASE)
		chain_data.temp_factor = IMMUNITY_REGEN_BASE
	
	# 5. 免疫力影响恢复速度
	var regen_bonus = immunity * CHAIN_IMMUNITY_TO_REGEN / 100.0
	chain_data.regen_factor = 1.0 + regen_bonus
	
	# 6. 体温伤害检"	_apply_temperature_damage()
	
	# 7. 感染风险计算
	_calculate_infection_risk()
	
	# 8. 疲劳恢复/累积
	_update_fatigue()
	
	# 发送状态链更新信号
	status_chain_updated.emit(chain_data)
	
	# 检查警"	_check_warnings()

func _apply_ambient_temperature_effect():
	var temp_diff = ambient_temperature - body_temperature
	var insulation = weather_protection * 0.5  # 防护最多减"0%影响
	var effect_rate = 0.02 * (1.0 - insulation)
	
	body_temperature += temp_diff * effect_rate
	
	# 限制体温范围
	body_temperature = clampf(body_temperature, 30.0, 45.0)

func _apply_temperature_damage():
	if body_temperature < TEMP_DAMAGE_THRESHOLD_LOW:
		var damage = TEMP_DAMAGE_PER_SEC * (TEMP_DAMAGE_THRESHOLD_LOW - body_temperature) * 0.5
		GameState.damage_player(int(damage))
		if Engine.get_process_frames() % 60 == 0:  # 每分钟警告一次
			status_warning_triggered.emit("hypothermia", "critical")
	elif body_temperature > TEMP_DAMAGE_THRESHOLD_HIGH:
		var damage = TEMP_DAMAGE_PER_SEC * (body_temperature - TEMP_DAMAGE_THRESHOLD_HIGH) * 0.5
		GameState.damage_player(int(damage))
		if Engine.get_process_frames() % 60 == 0:
			status_warning_triggered.emit("hyperthermia", "critical")

func _calculate_infection_risk():
	# 基础感染风险
	var base_risk = 0.0
	
	# 免疫力降低风险
	var immunity_factor = maxf(0, 1.0 - (immunity / 100.0))
	
	# 受伤增加风险
	var hp_percent = float(GameState.player_hp) / float(GameState.player_max_hp)
	var injury_factor = maxf(0, 1.0 - hp_percent)
	
	# 环境风险 (取决于地点)
	var location_risk = _get_location_infection_risk()
	
	# 计算总风险
	var total_risk = (base_risk + injury_factor * 0.3 + location_risk) * immunity_factor
	
	# 如果感染活跃，增加感染程度
	if infection_active:
		infection_level += total_risk * 2.0
		if infection_level >= INFECTION_THRESHOLD:
			_apply_infection_effects()
	else:
		# 随机感染判定
		if randf() < total_risk * 0.01:
			infection_active = true
			status_warning_triggered.emit("infection", "warning")
	
	infection_risk_changed.emit(total_risk)

func _get_location_infection_risk() -> float:
	var location = GameState.player_position
	match location:
		"hospital": return 0.4
		"supermarket": return 0.2
		"street_a", "street_b": return 0.15
		"subway": return 0.3
		"factory": return 0.25
		"forest": return 0.1
		"safehouse": return 0.05
		_: return 0.1

func _apply_infection_effects():
	# 感染持续降低HP和免疫力
	GameState.damage_player(1)
	immunity = maxf(0, immunity - 0.1)
	
	if Engine.get_process_frames() % 120 == 0:  # 每2分钟
		DialogModule.show_dialog("你感觉身体发热，可能感染了", "健康警告", "")

func _update_fatigue():
	# 疲劳影响战斗和移动
	if GameState.player_stamina < 20:
		fatigue = mini(FATIGUE_MAX, fatigue + 1)
	elif GameState.player_stamina > 80 and fatigue > 0:
		fatigue = maxi(0, fatigue - 1)
	
	# 疲劳影响体温调节
	if fatigue > FATIGUE_EXHAUSTED:
		body_temperature += 0.01  # 疲劳时体温略微升高

func _check_warnings():
	# 体温警告
	if body_temperature < TEMP_NORMAL_MIN or body_temperature > TEMP_NORMAL_MAX:
		if body_temperature < 33.0 or body_temperature > 41.0:
			status_warning_triggered.emit("temperature", "critical")
		else:
			status_warning_triggered.emit("temperature", "warning")
	
	# 免疫力警告
	if immunity < 30.0:
		status_warning_triggered.emit("immunity", "critical")
	elif immunity < 50.0:
		status_warning_triggered.emit("immunity", "warning")
	
	# 疲劳警告
	if fatigue >= FATIGUE_EXHAUSTED:
		status_warning_triggered.emit("fatigue", "critical")
	elif fatigue >= FATIGUE_TIRED:
		status_warning_triggered.emit("fatigue", "warning")

# ===== 时间推进处理 =====
func _on_time_advanced(old_time: Dictionary, new_time: Dictionary):
	var hours_passed = new_time.hour - old_time.hour
	if hours_passed < 0:
		hours_passed += 24
	
	# 长时间流逝的状态衰减
	for i in range(hours_passed):
		_apply_hourly_decay()

func _apply_hourly_decay():
	# 每小时自然衰减
	if GameState:
		GameState.player_hunger = maxi(0, GameState.player_hunger - 2)
		GameState.player_thirst = maxi(0, GameState.player_thirst - 3)
		GameState.player_stamina = maxi(0, GameState.player_stamina - 1)

func _on_player_hurt(data: Dictionary):
	# 受伤降低免疫力
	immunity = maxf(0, immunity - 5.0)
	# 受伤增加疲劳
	fatigue = mini(FATIGUE_MAX, fatigue + 10)

func _on_weather_changed(data: Dictionary):
	ambient_temperature = data.get("temperature", 25.0)

# ===== 公共接口 =====

## 获取体温状态
func get_temperature_status() -> String:
	if body_temperature < TEMP_NORMAL_MIN:
		return "体温过低"
	elif body_temperature > TEMP_NORMAL_MAX:
		return "体温过高"
	return "体温正常"

## 获取免疫力状态
func get_immunity_status() -> String:
	if immunity >= 80:
		return "免疫极强"
	elif immunity >= 60:
		return "免疫良好"
	elif immunity >= 40:
		return "免疫一般"
	elif immunity >= 20:
		return "免疫低下"
	return "免疫崩溃"

## 获取疲劳状态
func get_fatigue_status() -> String:
	if fatigue >= FATIGUE_EXHAUSTED:
		return "精疲力竭"
	elif fatigue >= FATIGUE_TIRED:
		return "疲劳"
	return "精神良好"

## 获取感染风险等级
func get_infection_risk_level() -> String:
	var risk = infection_level
	if risk >= 80:
		return "极高"
	elif risk >= 60:
		return "高"
	elif risk >= 40:
		return "中等"
	elif risk >= 20:
		return "低"
	return "极低"

## 获取战斗属性修正
func get_combat_modifiers() -> Dictionary:
	var modifiers = {
		"damage_mult": 1.0,
		"dodge_mult": 1.0,
		"accuracy_mult": 1.0
	}
	
	# 体温影响
	var temp_deviation = abs(body_temperature - TEMP_OPTIMAL)
	if temp_deviation > 3.0:
		modifiers.damage_mult *= 0.9
		modifiers.accuracy_mult *= 0.9
	
	# 疲劳影响
	if fatigue >= FATIGUE_EXHAUSTED:
		modifiers.damage_mult *= 0.7
		modifiers.dodge_mult *= 0.6
		modifiers.accuracy_mult *= 0.8
	elif fatigue >= FATIGUE_TIRED:
		modifiers.damage_mult *= 0.85
		modifiers.dodge_mult *= 0.85
	
	return modifiers

## 获取移动属性修饰符
func get_movement_modifiers() -> Dictionary:
	var modifiers = {
		"speed_mult": 1.0,
		"stamina_cost_mult": 1.0
	}
	
	if fatigue >= FATIGUE_EXHAUSTED:
		modifiers.speed_mult *= 0.6
		modifiers.stamina_cost_mult *= 1.5
	elif fatigue >= FATIGUE_TIRED:
		modifiers.speed_mult *= 0.8
		modifiers.stamina_cost_mult *= 1.2
	
	return modifiers

## 治疗感染
func treat_infection(medicine_strength: float = 50.0) -> bool:
	if not infection_active:
		return false
	
	infection_level = maxf(0, infection_level - medicine_strength)
	if infection_level <= 0:
		infection_active = false
		immunity = minf(IMMUNITY_MAX, immunity + 20)
		return true
	return false

## 提高体温
func warm_up(amount: float = 5.0):
	body_temperature = minf(45.0, body_temperature + amount)

## 降低体温
func cool_down(amount: float = 5.0):
	body_temperature = maxf(30.0, body_temperature - amount)

## 恢复免疫"func boost_immunity(amount: float = 10.0):
	immunity = minf(IMMUNITY_MAX, immunity + amount)

## 休息恢复
func rest(hours: int = 8):
	fatigue = maxi(0, fatigue - hours * 10)
	immunity = minf(IMMUNITY_MAX, immunity + hours * 2)
	body_temperature = lerp(body_temperature, TEMP_OPTIMAL, 0.1)

## 设置环境防护
func set_weather_protection(protection: float):
	weather_protection = clampf(protection, 0.0, 1.0)

## 设置潮湿程度
func set_wetness(new_wetness: float):
	wetness = clampf(new_wetness, 0.0, 100.0)

# ===== 序列"=====
func serialize() -> Dictionary:
	return {
		"body_temperature": body_temperature,
		"immunity": immunity,
		"fatigue": fatigue,
		"infection_level": infection_level,
		"infection_active": infection_active,
		"ambient_temperature": ambient_temperature,
		"wetness": wetness,
		"weather_protection": weather_protection
	}

func deserialize(data: Dictionary):
	body_temperature = data.get("body_temperature", 37.0)
	immunity = data.get("immunity", 100.0)
	fatigue = data.get("fatigue", 0)
	infection_level = data.get("infection_level", 0.0)
	infection_active = data.get("infection_active", false)
	ambient_temperature = data.get("ambient_temperature", 25.0)
	wetness = data.get("wetness", 0.0)
	weather_protection = data.get("weather_protection", 0.0)
	print("[SurvivalStatusSystem] 状态数据已加载")

