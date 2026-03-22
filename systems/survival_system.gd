extends Node
# SurvivalSystem - 深度生存系统
# 管理饥饿、口渴、疲劳、疾病、体温等生存要素

signal status_changed(status_type: String, value: float)
signal warning_triggered(warning_type: String, message: String)
signal critical_status(status_type: String)
signal player_died(cause: String)

# 生存状态阈"
const THRESHOLDS = {
    "hunger": {
        "full": 80,
        "satisfied": 50,
        "hungry": 30,
        "starving": 10,
        "critical": 0
    },
    "thirst": {
        "hydrated": 80,
        "satisfied": 50,
        "thirsty": 30,
        "dehydrated": 10,
        "critical": 0
    },
    "fatigue": {
        "energetic": 80,
        "rested": 50,
        "tired": 30,
        "exhausted": 10,
        "critical": 0
    },
    "body_temp": {
        "hot": 38.0,
        "normal_high": 37.0,
        "normal": 36.5,
        "normal_low": 36.0,
        "cold": 35.0,
        "critical": 30.0
    }
}

# 消耗速率（每游戏小时"
const CONSUMPTION_RATES = {
    "base": {
        "hunger": 2.0,
        "thirst": 3.0,
        "fatigue": 1.5
    },
    "movement": {
        "hunger": 0.5,
        "thirst": 1.0,
        "fatigue": 2.0
    },
    "combat": {
        "hunger": 1.0,
        "thirst": 2.0,
        "fatigue": 3.0
    }
}

# 状态效"
var active_effects: Array[Dictionary] = []
var diseases: Array[Dictionary] = []

# 体温系统
var body_temperature: float = 36.5  # 正常体温
var ambient_temperature: float = 20.0  # 环境温度
var wetness: float = 0.0  # 潮湿程度"-100"

# 计时"
var consumption_timer: float = 0.0
var disease_timer: float = 0.0

func _ready():
    # 订阅事件
    EventBus.subscribe(EventBus.EventType.COMBAT_ENDED, _on_combat_ended)
    print("[SurvivalSystem] 深度生存系统已初始化")

func _process(delta: float):
    # "0秒更新一次（游戏"小时 = 现实60秒）
    consumption_timer += delta
    
    if consumption_timer >= 10.0:  # "0"
        consumption_timer = 0.0
        _update_survival_needs()
        _update_body_temperature()
        _process_diseases()

# 更新生存需"
func _update_survival_needs():
    var activity = "base"  # base, movement, combat
    
    # 根据玩家位置判断活动类型
    if GameState.player_position in ["street_a", "street_b", "hospital"]:
        activity = "movement"
    
    # 消耗资"
    var hunger_consumption = CONSUMPTION_RATES[activity].hunger
    var thirst_consumption = CONSUMPTION_RATES[activity].thirst
    var fatigue_consumption = CONSUMPTION_RATES[activity].fatigue
    
    # 疾病会增加消"
    if has_disease("flu"):
        hunger_consumption *= 1.5
        thirst_consumption *= 1.5
    if has_disease("food_poisoning"):
        thirst_consumption *= 2.0
    
    # 应用消"
    modify_hunger(-hunger_consumption)
    modify_thirst(-thirst_consumption)
    modify_fatigue(-fatigue_consumption)
    
    # 检查状"
    _check_survival_status()

# 更新体温
func _update_body_temperature(_type: String = ""):
    # 天气影响环境温度
    var weather_effects = {
        "clear": 0.0,
        "rain": -5.0,
        "storm": -8.0,
        "fog": -3.0
    }
    
    var weather_effect = weather_effects.get(GameState.world_weather, 0.0)
    var time_effect = _get_time_temperature_effect()
    
    ambient_temperature = 20.0 + weather_effect + time_effect
    
    # 计算体温变化
    var temp_diff = ambient_temperature - body_temperature
    var insulation = _calculate_insulation()
    
    # 潮湿会加速失"
    if wetness > 0:
        insulation *= (1.0 - wetness / 200.0)  # 潮湿降低保暖
    
    body_temperature += temp_diff * 0.1 * insulation
    
    # 体温过低或过高都会扣血
    if body_temperature < THRESHOLDS.body_temp.cold:
        GameState.damage_player(2)
        warning_triggered.emit("hypothermia", "体温过低！你需要取暖！")
    elif body_temperature > THRESHOLDS.body_temp.hot:
        GameState.damage_player(2)
        warning_triggered.emit("hyperthermia", "体温过高！你需要降温！")

func _get_time_temperature_effect():
    var hour = GameState.world_time
    # 夜间更冷
    if hour >= 22 || hour <= 4:
        return -5.0
    elif hour >= 5 && hour <= 7:
        return -3.0  # 清晨
    elif hour >= 12 && hour <= 15:
        return 5.0   # 正午
    return 0.0

func _calculate_insulation():
    # 基础保暖"
    var insulation = 1.0
    
    # 可以在这里添加服装保暖加"
    # if has_clothing("jacket"): insulation += 0.5
    
    return insulation

# 检查生存状"
func _check_survival_status(_type: String = ""):
    # 饥饿检"
    if GameState.player_hunger <= THRESHOLDS.hunger.starving:
        GameState.damage_player(3)
        critical_status.emit("hunger")
        warning_triggered.emit("starving", "你正在饿死！快找食物")
    elif GameState.player_hunger <= THRESHOLDS.hunger.hungry:
        warning_triggered.emit("hungry", "你很")
    
    # 口渴检"
    if GameState.player_thirst <= THRESHOLDS.thirst.dehydrated:
        GameState.damage_player(5)
        critical_status.emit("thirst")
        warning_triggered.emit("dehydrated", "你严重脱水！快喝水！")
    elif GameState.player_thirst <= THRESHOLDS.thirst.thirsty:
        warning_triggered.emit("thirsty", "你很")
    
    # 疲劳检"
    if GameState.player_stamina <= THRESHOLDS.fatigue.exhausted:
        # 过度疲劳降低属"
        warning_triggered.emit("exhausted", "你精疲力竭，需要休息！")
    
    # 死亡检"
    if int(GameState.get_player_attributes_snapshot().get("hp", 0)) <= 0:
        var cause = _determine_death_cause()
        player_died.emit(cause)

func _determine_death_cause():
    if GameState.player_hunger <= 0:
        return "饿死"
    elif GameState.player_thirst <= 0:
        return "渴死"
    elif body_temperature <= 30.0:
        return "冻死"
    elif body_temperature >= 42.0:
        return "热死"
    else:
        return "未知原因"

# 修改状态"
func modify_hunger(amount: float):
    var old = GameState.player_hunger
    GameState.player_hunger = clamp(GameState.player_hunger + amount, 0, 100)
    if abs(GameState.player_hunger - old) > 0.1:
        status_changed.emit("hunger", GameState.player_hunger)

func modify_thirst(amount: float):
    var old = GameState.player_thirst
    GameState.player_thirst = clamp(GameState.player_thirst + amount, 0, 100)
    if abs(GameState.player_thirst - old) > 0.1:
        status_changed.emit("thirst", GameState.player_thirst)

func modify_fatigue(amount: float):
    var old = GameState.player_stamina
    GameState.player_stamina = clamp(GameState.player_stamina + amount, 0, 100)
    if abs(GameState.player_stamina - old) > 0.1:
        status_changed.emit("fatigue", GameState.player_stamina)

# 疾病系统
func add_disease(disease_id: String):
    var disease = _get_disease_data(disease_id)
    if disease && not has_disease(disease_id):
        diseases.append({
            "id": disease_id,
            "name": disease.name,
            "duration": disease.duration,
            "severity": disease.severity,
            "effects": disease.effects
        })
        warning_triggered.emit("disease", "你感染了 %s" % disease.name)

func remove_disease(disease_id: String):
    for i in range(diseases.size()):
        if diseases[i].id == disease_id:
            diseases.remove_at(i)
            break

func has_disease(disease_id: String):
    for disease in diseases:
        if disease.id == disease_id:
            return true
    return false

func _get_disease_data(disease_id: String):
    var diseases_db = {
        "flu": {
            "name": "流感",
            "duration": 72,  # 游戏小时
            "severity": "medium",
            "effects": ["hp_regen_down", "fatigue_up"]
        },
        "food_poisoning": {
            "name": "食物中毒",
            "duration": 24,
            "severity": "high",
            "effects": ["hp_loss", "thirst_up"]
        },
        "infection": {
            "name": "伤口感染",
            "duration": 48,
            "severity": "high",
            "effects": ["hp_loss", "combat_down"]
        },
        "radiation": {
            "name": "辐射",
            "duration": -1,  # 需要特殊治"
            "severity": "critical",
            "effects": ["all_stats_down"]
        }
    }
    return diseases_db.get(disease_id, {})

func _process_diseases(_type: String = ""):
    for disease in diseases:
        disease.duration -= 1  # 每小时减"
        
        # 应用疾病效果
        match disease.id:
            "flu":
                modify_fatigue(-1)
            "food_poisoning":
                modify_thirst(-3)
                if randf() < 0.1:
                    GameState.damage_player(1)
            "infection":
                GameState.damage_player(2)
        
        if disease.duration == 0:
            remove_disease(disease.id)
            DialogModule.show_dialog(
                "你的 %s 已经痊愈" % disease.name,
                "健康",
                ""
            )

# 事件处理
func _on_combat_ended(_data: Dictionary):
    if int(GameState.get_player_attributes_snapshot().get("hp", 0)) < 50:
        # 低血量时可能感染
        if randf() < 0.1 && not has_disease("infection"):
            add_disease("infection")

# 公共方法
func eat_food(amount: float, nutrition_quality: float = 1.0):
    modify_hunger(amount * nutrition_quality)
    modify_fatigue(amount * 0.2)

func drink_water(amount: float):
    modify_thirst(amount)
    # 喝水也能稍微降温
    if body_temperature > 37.0:
        body_temperature -= 0.1

func rest(duration: int):
    modify_fatigue(duration * 5)
    if body_temperature < 36.0:
        body_temperature += 0.1
    else:
        body_temperature += 0

func get_survival_status():
    return {
        "hunger": GameState.player_hunger,
        "thirst": GameState.player_thirst,
        "fatigue": GameState.player_stamina,
        "body_temp": body_temperature,
        "diseases": diseases,
        "effects": active_effects
    }

# 保存/加载
func get_save_data():
    return {
        "body_temperature": body_temperature,
        "wetness": wetness,
        "diseases": diseases
    }

func load_save_data(data: Dictionary):
    body_temperature = data.get("body_temperature", 36.5)
    wetness = data.get("wetness", 0.0)
    diseases = data.get("diseases", [])

