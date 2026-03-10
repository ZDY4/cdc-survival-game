extends Node
# CombatPenaltySystem - 战斗惩罚系统
# 将负重惩罚集成到战斗系统

# 惩罚数值配置
const PENALTY_CONFIG = {
	"dodge": {
		"light": 0.0,      # 轻载: 无惩罚
		"medium": 0.1,     # 中载: -10%
		"heavy": 0.2,      # 重载: -20%
		"overloaded": 0.4, # 超载: -40%
		"immobile": 1.0    # 完全超载: -100% (无法闪避)
	},
	"initiative": {
		"light": 0,
		"medium": 0,
		"heavy": 5,
		"overloaded": 10,
		"immobile": 999
	},
	"stamina_cost": {
		"light": 1.0,
		"medium": 1.1,     # +10%耐力消耗
		"heavy": 1.2,      # +20%
		"overloaded": 1.4, # +40%
		"immobile": 2.0    # +100%
	}
}

func _ready():
	print("[CombatPenaltySystem] 战斗惩罚系统已初始化")
	# 连接战斗信号
	if CombatModule:
		# 使用 EventBus 订阅战斗事件
		EventBus.subscribe(EventBus.EventType.COMBAT_STARTED, _on_combat_started)
		CombatModule.action_completed.connect(_on_player_action)

## 获取当前负重等级名称
func _get_encumbrance_level_name():
	if not CarrySystem:
		return "light"
	
	var level = CarrySystem.get_encumbrance_level()
	match level:
		0: return "light"
		1: return "medium"
		2: return "heavy"
		3: return "overloaded"
		4: return "immobile"
		_: return "light"

## 计算闪避惩罚
func get_dodge_penalty():
	var level = _get_encumbrance_level_name()
	return PENALTY_CONFIG.dodge.get(level, 0.0)

## 计算先手惩罚
func get_initiative_penalty():
	var level = _get_encumbrance_level_name()
	return PENALTY_CONFIG.initiative.get(level, 0)

## 计算耐力消耗倍数
func get_stamina_cost_multiplier():
	var level = _get_encumbrance_level_name()
	return PENALTY_CONFIG.stamina_cost.get(level, 1.0)

## 计算实际闪避率
func calculate_dodge_chance(base_dodge: float):
	var penalty = get_dodge_penalty()
	return maxf(0.0, base_dodge - penalty)

## 计算实际先手值
func calculate_initiative(base_initiative: int):
	var penalty = get_initiative_penalty()
	return maxi(0, base_initiative - penalty)

## 计算实际耐力消耗
func calculate_stamina_cost(base_cost: float):
	var multiplier = get_stamina_cost_multiplier()
	return base_cost * multiplier

## 战斗开始时应用惩罚
func _on_combat_started():
	var level = _get_encumbrance_level_name()
	
	# 显示惩罚提示
	match level:
		"medium":
			DialogModule.show_dialog(
				"你感到有些沉重，移动稍微变慢了",
				"负重提示",
				""
			)
		"heavy":
			DialogModule.show_dialog(
				"负重严重影响了你的灵活性！闪避率降低20%，先手降低5%",
				"负重警告",
				""
			)
		"overloaded":
			DialogModule.show_dialog(
				"你负重太多了！闪避率降低40%，先手降低10%，耐力消耗大幅增加！",
				"负重警告",
				""
			)
		"immobile":
			DialogModule.show_dialog(
				"你负重严重超载！几乎无法战斗，建议丢弃一些物品！",
				"严重警告",
				""
			)

## 玩家行动时应用惩罚
func _on_player_action(action: String):
	if action == "attack":
		# 攻击时消耗额外耐力
		var equip_system = GameState.get_equipment_system() if GameState else null
		var base_stamina = equip_system.calculate_combat_stats().get("stamina_cost", 5) if equip_system else 5
		var actual_cost = calculate_stamina_cost(base_stamina)
		
		# 如果超载，显示提示
		if get_stamina_cost_multiplier() > 1.3:
			print("[CombatPenalty] 额外耐力消: " + str(actual_cost - base_stamina))

## 获取当前惩罚状态描述
func get_penalty_description():
	var level = _get_encumbrance_level_name()
	
	match level:
		"light":
			return "无惩罚"
		"medium":
			return "闪避-10%"
		"heavy":
			return "闪避-20%, 先手-5, 耐力+20%"
		"overloaded":
			return "闪避-40%, 先手-10, 耐力+40%"
		"immobile":
			return "几乎无法战斗"
		_:
			return "无惩罚"

