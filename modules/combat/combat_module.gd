extends Node
## 战斗模块 - 处理战斗中的具体动作和部位伤害
## 作为 CombatSystem 的补充，提供更细粒度的战斗控制

# ========== 信号 ==========
signal action_started(action_type: String, params: Dictionary)
signal action_completed(action_type: String, result: Dictionary)
signal limb_attack_started(target_limb: int, accuracy: float)
signal limb_hit(limb: int, damage: int, effect: String)
signal limb_miss(target_limb: int)
signal combo_triggered(combo_count: int, bonus_damage: int)

# ========== 配置常量 ==========
const BASE_HIT_CHANCE: float = 0.85  # 基础命中率85%
const HEAD_HIT_PENALTY: float = 0.15  # 头部攻击命中率-15%
const LEGS_HIT_PENALTY: float = 0.05  # 腿部攻击命中率-5%
const ARMS_HIT_PENALTY: float = 0.10  # 手臂攻击命中率-10%

# 部位命中修正 (使用整数对应 LimbType 枚举: HEAD=0, TORSO=1, LEFT_ARM=2, RIGHT_ARM=3, LEGS=4)
const LIMB_ACCURACY_MODS: Dictionary = {
	0: -0.15,    # 头部难命中
	1: 0.0,      # 躯干标准
	2: -0.10,    # 左臂较难命中
	3: -0.10,    # 右臂较难命中
	4: -0.05     # 腿部稍难命中
}

# 连续攻击奖励
const COMBO_BONUS: Array = [0, 0.1, 0.2, 0.35, 0.5]  # 连击伤害加成

# ========== 状态变量 ==========
var combat_system: Node = null
var limb_system: Node = null

var current_combo: int = 0
var last_target_limb: int = -1
var action_queue: Array = []
var _is_processing: bool = false

# 武器部位偏好 (使用整数对应 LimbType: TORSO=1, LEGS=4, HEAD=0)
var weapon_limb_preference: Dictionary = {
	"knife": [1, 4],
	"bat": [0, 1],
	"gun": [0, 1],
	"fist": [1, 0]
}

# ========== 初始化 ==========
func _ready():
	_initialize_systems()

func _initialize_systems() -> void:
	# 获取系统引用
	if Engine.has_singleton("CombatSystem"):
		combat_system = Engine.get_singleton("CombatSystem")
	elif has_node("/root/CombatSystem"):
		combat_system = get_node("/root/CombatSystem")
	
	if Engine.has_singleton("LimbDamageSystem"):
		limb_system = Engine.get_singleton("LimbDamageSystem")
	elif has_node("/root/LimbDamageSystem"):
		limb_system = get_node("/root/LimbDamageSystem")
	
	# 连接信号
	if combat_system:
		combat_system.combat_started.connect(_on_combat_started)
		combat_system.combat_ended.connect(_on_combat_ended)
		combat_system.turn_started.connect(_on_turn_started)

# ========== 核心动作 ==========
## 执行精准部位攻击
## @param target_limb: 目标部位
## @param weapon_type: 武器类型
## @param use_aim: 是否使用瞄准（消耗行动点但提高命中率）
func perform_limb_attack(target_limb: int, weapon_type: String = "", use_aim: bool = false) -> Dictionary:
	if not combat_system or not limb_system:
		return {"success": false, "error": "系统未初始化"}
	
	if not combat_system.is_player_turn():
		return {"success": false, "error": "不是玩家回合"}
	
	# 检查部位是否可用
	if not limb_system.is_limb_functional(target_limb, false):
		_log_action("目标部位已损坏，无法攻击")
		return {"success": false, "error": "部位已损坏"}
	
	action_started.emit("limb_attack", {"target_limb": target_limb, "weapon": weapon_type})
	
	# 计算命中率
	var accuracy = _calculate_accuracy(target_limb, weapon_type, use_aim)
	limb_attack_started.emit(target_limb, accuracy)
	
	# 命中判定
	var hit_roll = randf()
	if hit_roll > accuracy:
		# 未命中
		current_combo = 0
		limb_miss.emit(target_limb)
		_log_action("攻击未命中%s的%s！" % [
			combat_system.get_enemy_stats().get("name", "敌人"),
			limb_system.get_limb_name(target_limb)
		])
		
		action_completed.emit("limb_attack", {"success": false, "hit": false})
		return {"success": true, "hit": false, "accuracy": accuracy}
	
	# 命中！计算连击奖励
	if target_limb == last_target_limb:
		current_combo = min(current_combo + 1, COMBO_BONUS.size() - 1)
	else:
		current_combo = 1
	
	var combo_bonus = COMBO_BONUS[current_combo]
	
	# 执行攻击
	var result = _execute_limb_damage(target_limb, combo_bonus)
	
	last_target_limb = target_limb
	
	# 触发连击信号
	if current_combo >= 2:
		combo_triggered.emit(current_combo, int(result.damage * combo_bonus))
	
	action_completed.emit("limb_attack", result)
	
	# 结束回合
	combat_system.end_turn()
	
	return {"success": true, "result": result}

## 执行快速攻击（低伤害但高命中）
func perform_quick_attack(target_limb: int = -1) -> Dictionary:
	if target_limb == -1:
		target_limb = _select_optimal_limb()
	
	action_started.emit("quick_attack", {"target_limb": target_limb})
	
	# 快速攻击：+20%命中率，-30%伤害
	var base_result = combat_system.perform_limb_attack(target_limb)
	
	if base_result.success and base_result.has("result"):
		# 调整伤害
		var damage = int(base_result.result.damage * 0.7)
		base_result.result.damage = max(1, damage)
		
		_log_action("快速攻击！造成 %d 伤害" % damage)
	
	action_completed.emit("quick_attack", base_result)
	return base_result

## 执行重击（高伤害但低命中）
func perform_heavy_attack(target_limb: int = -1) -> Dictionary:
	if target_limb == -1:
		target_limb = 1
	
	action_started.emit("heavy_attack", {"target_limb": target_limb})
	
	# 重击：-25%命中率，+60%伤害，+30%部位损坏几率
	var accuracy_mod = -0.25
	var damage_mult = 1.6
	
	var accuracy = _calculate_accuracy(target_limb, "", false) + accuracy_mod
	
	if randf() > accuracy:
		current_combo = 0
		limb_miss.emit(target_limb)
		_log_action("重击未命中！")
		
		# 重击未命中会损失下回合部分行动
		combat_system.end_turn()
		return {"success": true, "hit": false}
	
	# 计算基础伤害
	var player_stats = combat_system.get_player_stats()
	var base_damage = player_stats.attack
	var final_damage = int(base_damage * damage_mult)
	
	# 应用部位伤害
	var limb_result = limb_system.calculate_limb_damage(final_damage, target_limb, false)
	limb_system.apply_limb_damage(limb_result, false)
	
	# 重击更容易造成部位损坏
	if limb_result.new_state == 2:
		_log_action("重击！%s的%s被彻底破坏！" % [
			combat_system.get_enemy_stats().get("name", "敌人"),
			limb_system.get_limb_name(target_limb)
		])
	else:
		_log_action("重击！对%s造成 %d 伤害" % [
			limb_system.get_limb_name(target_limb),
			limb_result.damage
		])
	
	var result = {
		"hit": true,
		"damage": limb_result.damage,
		"limb": target_limb,
		"critical": false,
		"broken": limb_result.is_broken
	}
	
	limb_hit.emit(target_limb, limb_result.damage, "heavy")
	action_completed.emit("heavy_attack", result)
	
	combat_system.end_turn()
	
	return {"success": true, "result": result}

## 执行部位治疗
## @param limb: 目标部位，-1表示治疗所有部位
## @param item_id: 治疗物品ID
func perform_limb_heal(limb: int, item_id: String) -> Dictionary:
	action_started.emit("limb_heal", {"limb": limb, "item": item_id})
	
	var item_data = _get_heal_item_data(item_id)
	if item_data.is_empty():
		return {"success": false, "error": "无效的治疗物品"}
	
	var total_healed = 0
	
	if limb == -1:
		# 治疗所有部位
		total_healed = limb_system.heal_all_limbs(item_data.heal_amount, true)
		_log_action("使用%s治疗所有部位，共恢复%d HP" % [item_data.name, total_healed])
	else:
		# 治疗特定部位
		var healed = limb_system.heal_limb(limb, item_data.heal_amount, true)
		total_healed = healed
		_log_action("使用%s治疗%s，恢复%d HP" % [
			item_data.name,
			limb_system.get_limb_name(limb),
			healed
		])
	
	# 消耗物品
	_consume_item(item_id)
	
	var result = {
		"healed": total_healed,
		"limb": limb,
		"item": item_id
	}
	
	action_completed.emit("limb_heal", result)
	
	# 治疗消耗回合
	combat_system.end_turn()
	
	return {"success": true, "result": result}

## 执行部位检查（获取敌人部位信息）
func perform_limb_scan() -> Dictionary:
	action_started.emit("limb_scan", {})
	
	if not limb_system:
		return {"success": false, "error": "部位系统未初始化"}
	
	var enemy_limbs = limb_system.get_all_limbs_state(false)
	var scan_result = {}
	
	for limb_type in enemy_limbs:
		var limb_state = enemy_limbs[limb_type]
		var visibility = _calculate_limb_visibility(limb_type)
		
		scan_result[limb_type] = {
			"hp_percent": float(limb_state.hp) / limb_state.max_hp,
			"state": limb_state.state,
			"visible": visibility > 0.5,
			"estimated_hp": _estimate_hp(limb_state.hp, visibility)
		}
	
	_log_action("扫描完成，已获取敌人部位信息")
	action_completed.emit("limb_scan", scan_result)
	
	return {"success": true, "limbs": scan_result}

# ========== 伤害执行 ==========
func _execute_limb_damage(target_limb: int, combo_bonus: float) -> Dictionary:
	var player_stats = combat_system.get_player_stats()
	var base_damage = player_stats.attack
	
	# 应用连击加成
	if combo_bonus > 0:
		base_damage = int(base_damage * (1.0 + combo_bonus))
	
	# 计算部位伤害
	var limb_result = limb_system.calculate_limb_damage(base_damage, target_limb, false)
	limb_system.apply_limb_damage(limb_result, false)
	
	# 更新敌人HP
	var enemy_stats = combat_system.get_enemy_stats()
	enemy_stats.hp = max(0, enemy_stats.hp - limb_result.damage)
	
	# 发射信号
	var effect_type = "normal"
	if limb_result.is_broken:
		effect_type = "broken"
	elif limb_result.is_damaged:
		effect_type = "damaged"
	
	limb_hit.emit(target_limb, limb_result.damage, effect_type)
	
	# 构建结果
	return {
		"hit": true,
		"damage": limb_result.damage,
		"limb": target_limb,
		"limb_name": limb_system.get_limb_name(target_limb),
		"critical": combo_bonus >= 0.35,
		"combo": current_combo,
		"state_changed": limb_result.state_changed,
		"is_damaged": limb_result.is_damaged,
		"is_broken": limb_result.is_broken
	}

# ========== 命中率计算 ==========
func _calculate_accuracy(target_limb: int, weapon_type: String, use_aim: bool) -> float:
	var accuracy = BASE_HIT_CHANCE
	
	# 部位修正
	if LIMB_ACCURACY_MODS.has(target_limb):
		accuracy += LIMB_ACCURACY_MODS[target_limb]
	
	# 武器修正
	if weapon_limb_preference.has(weapon_type):
		var preferred = weapon_limb_preference[weapon_type]
		if target_limb in preferred:
			accuracy += 0.1  # 武器适合攻击该部位
	
	# 瞄准修正
	if use_aim:
		accuracy += 0.2
	
	# 自身状态修正
	if limb_system:
		# 手臂受伤影响命中率
		var left_arm = limb_system.get_limb_state(2, true)
		var right_arm = limb_system.get_limb_state(3, true)
		
		if left_arm.state == 1:
			accuracy -= 0.1
		elif left_arm.state == 2:
			accuracy -= 0.2
		
		if right_arm.state == 1:
			accuracy -= 0.1
		elif right_arm.state == 2:
			accuracy -= 0.2
		
		# 眼睛/头部影响
		var head = limb_system.get_limb_state(0, true)
		if head.state == 1:
			accuracy -= 0.15
	
	return clamp(accuracy, 0.1, 1.0)

# ========== 辅助方法 ==========
func _select_optimal_limb() -> int:
	# 选择最优攻击部位
	if not limb_system:
		return 1
	
	var functional = limb_system.get_functional_limbs(false)
	if functional.is_empty():
		return 1
	
	# 优先策略：优先攻击受损但未损坏的部位
	for limb in functional:
		var state = limb_system.get_limb_state(limb, false)
		if state.state == 1:
			return limb
	
	# 其次选择躯干
	if 1 in functional:
		return 1
	
	# 随机选择
	return functional[randi() % functional.size()]

func _calculate_limb_visibility(limb: int) -> float:
	# 计算部位可见度（受战斗环境影响）
	var base_visibility = 1.0
	
	match limb:
		0:
			base_visibility = 0.8
		1:
			base_visibility = 1.0
		4:
			base_visibility = 0.9
		_:
			base_visibility = 0.7
	
	return base_visibility

func _estimate_hp(actual_hp: int, visibility: float) -> String:
	if visibility >= 0.9:
		return str(actual_hp)
	elif visibility >= 0.7:
		var estimate = round(actual_hp / 10.0) * 10
		return "约%d" % estimate
	elif visibility >= 0.5:
		if actual_hp > 50:
			return "健康"
		elif actual_hp > 20:
			return "受伤"
		else:
			return "危险"
	else:
		return "???"

func _get_heal_item_data(item_id: String) -> Dictionary:
	var item_db = {
		"bandage": {"name": "绷带", "heal_amount": 15, "target": "single"},
		"medkit": {"name": "医疗包", "heal_amount": 50, "target": "single"},
		"first_aid_kit": {"name": "急救箱", "heal_amount": 30, "target": "all"},
		"splint": {"name": "夹板", "heal_amount": 20, "target": "limbs", "limb_bonus": 1.5},
		"painkiller": {"name": "止痛药", "heal_amount": 10, "target": "all"},
		"herbal_medicine": {"name": "草药", "heal_amount": 25, "target": "single"}
	}
	return item_db.get(item_id, {})

func _consume_item(item_id: String) -> void:
	# 通知物品系统消耗物品
	if Engine.has_singleton("EventBus"):
		Engine.get_singleton("EventBus").emit_signal("item_consumed", item_id)

func _log_action(message: String) -> void:
	print("[CombatModule] %s" % message)

# ========== 事件处理 ==========
func _on_combat_started(_enemy_data: Dictionary) -> void:
	current_combo = 0
	last_target_limb = -1
	action_queue.clear()
	_is_processing = false

func _on_combat_ended(_victory: bool) -> void:
	current_combo = 0
	last_target_limb = -1

func _on_turn_started(is_player: bool) -> void:
	if not is_player:
		current_combo = 0  # 敌人回合重置连击

# ========== 获取器 ==========
func get_current_combo() -> int:
	return current_combo

func get_combo_bonus() -> float:
	return COMBO_BONUS[min(current_combo, COMBO_BONUS.size() - 1)]

func get_limb_accuracy(limb: int, weapon: String = "", aim: bool = false) -> float:
	return _calculate_accuracy(limb, weapon, aim)

func get_recommended_target() -> int:
	return _select_optimal_limb()
