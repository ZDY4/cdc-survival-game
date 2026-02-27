extends Node
## 部位伤害系统 - CDC末日生存游戏
## 管理角色的5个部位：头部、躯干、左臂、右臂、腿部
## 提供部位伤害计算、状态效果、治疗恢复等功能

class_name LimbDamageSystem

# ========== 信号 ==========
signal limb_damaged(limb: LimbType, state: LimbState, is_player: bool)
signal limb_healed(limb: LimbType, amount: int, is_player: bool)
signal limb_broken(limb: LimbType, is_player: bool)
signal limb_effect_applied(limb: LimbType, effect: String, is_player: bool)
signal all_limbs_updated(player_limbs: Dictionary, enemy_limbs: Dictionary)

# ========== 枚举定义 ==========
enum LimbType {
	HEAD,       # 头部 - 暴击相关
	TORSO,      # 躯干 - 核心部位
	LEFT_ARM,   # 左臂 - 攻击力
	RIGHT_ARM,  # 右臂 - 攻击力
	LEGS        # 腿部 - 移动/闪避
}

enum LimbState {
	NORMAL,     # 正常
	DAMAGED,    # 受损 (HP <= 30%)
	BROKEN      # 损坏 (HP <= 0)
}

# ========== 部位基础数据 ==========
const LIMB_DATA: Dictionary = {
	LimbType.HEAD: {
		"name": "头部",
		"max_hp": 30,
		"damage_mult": 1.5,  # 150%伤害
		"effects": {
			"damaged": {"critical_chance": -20},
			"broken": {"stun": 1, "critical_chance": -50}
		},
		"description": {
			"damaged": "暴击率-20%",
			"broken": "眩晕，无法行动，暴击率-50%"
		}
	},
	LimbType.TORSO: {
		"name": "躯干",
		"max_hp": 100,
		"damage_mult": 1.0,  # 100%伤害
		"effects": {
			"damaged": {"defense": -20},
			"broken": {"bleeding": 3, "defense": -50}
		},
		"description": {
			"damaged": "防御-20%",
			"broken": "持续流血，防御-50%"
		}
	},
	LimbType.LEFT_ARM: {
		"name": "左臂",
		"max_hp": 40,
		"damage_mult": 0.8,
		"effects": {
			"damaged": {"left_hand_damage": -30},
			"broken": {"left_hand_disabled": true}
		},
		"description": {
			"damaged": "左手武器攻击-30%",
			"broken": "无法使用左手武器"
		}
	},
	LimbType.RIGHT_ARM: {
		"name": "右臂",
		"max_hp": 40,
		"damage_mult": 0.8,
		"effects": {
			"damaged": {"right_hand_damage": -30},
			"broken": {"right_hand_disabled": true}
		},
		"description": {
			"damaged": "右手武器攻击-30%",
			"broken": "无法使用右手武器"
		}
	},
	LimbType.LEGS: {
		"name": "腿部",
		"max_hp": 50,
		"damage_mult": 0.9,
		"effects": {
			"damaged": {"dodge": -30, "move_speed": -20},
			"broken": {"dodge_disabled": true, "move_speed": -50}
		},
		"description": {
			"damaged": "闪避-30%，移动速度-20%",
			"broken": "无法闪避，移动速度-50%"
		}
	}
}

# ========== 状态变量 ==========
var player_limbs: Dictionary = {}
var enemy_limbs: Dictionary = {}
var active_effects: Dictionary = {
	"player": {},
	"enemy": {}
}

# ========== 初始化 ==========
func _ready():
	_initialize_limbs()
	_connect_signals()

func _initialize_limbs():
	# 初始化玩家部位
	player_limbs = _create_default_limbs()
	# 初始化敌人部位
	enemy_limbs = _create_default_limbs()

func _create_default_limbs() -> Dictionary:
	var limbs = {}
	for limb_type in LimbType.values():
		var data = LIMB_DATA[limb_type]
		limbs[limb_type] = {
			"hp": data.max_hp,
			"max_hp": data.max_hp,
			"state": LimbState.NORMAL
		}
	return limbs

func _connect_signals():
	# 连接EventBus信号（如果存在）
	if Engine.has_singleton("EventBus"):
		var event_bus = Engine.get_singleton("EventBus")
		event_bus.connect("combat_started", _on_combat_started)
		event_bus.connect("combat_ended", _on_combat_ended)
		event_bus.connect("game_saved", _on_game_saved)
		event_bus.connect("game_loaded", _on_game_loaded)

# ========== 核心功能：部位伤害计算 ==========
## 计算部位伤害
## @param attack_damage: 基础攻击伤害
## @param target_limb: 目标部位
## @param is_player: 是否攻击玩家（false表示攻击敌人）
## @return: 伤害结果字典
func calculate_limb_damage(attack_damage: int, target_limb: LimbType, is_player: bool) -> Dictionary:
	var limb_info = LIMB_DATA[target_limb]
	var limb_state = get_limb_state(target_limb, is_player)
	
	# 基础伤害计算
	var actual_damage = int(attack_damage * limb_info.damage_mult)
	
	# 已损坏部位受到50%伤害（保护机制）
	if limb_state.hp <= 0:
		actual_damage = int(actual_damage * 0.5)
	
	# 预测新状态
	var new_hp = max(0, limb_state.hp - actual_damage)
	var new_state = _determine_limb_state(target_limb, new_hp)
	
	return {
		"damage": actual_damage,
		"limb": target_limb,
		"limb_name": limb_info.name,
		"old_hp": limb_state.hp,
		"new_hp": new_hp,
		"old_state": limb_state.state,
		"new_state": new_state,
		"is_damaged": new_state == LimbState.DAMAGED,
		"is_broken": new_state == LimbState.BROKEN,
		"state_changed": limb_state.state != new_state
	}

## 应用伤害到部位
## @param damage_result: calculate_limb_damage的返回结果
## @param is_player: 是否应用到玩家
func apply_limb_damage(damage_result: Dictionary, is_player: bool) -> void:
	var limb = damage_result.limb
	var new_hp = damage_result.new_hp
	var new_state = damage_result.new_state
	var old_state = damage_result.old_state
	
	# 更新HP
	_set_limb_hp(limb, new_hp, is_player)
	
	# 更新状态
	if old_state != new_state:
		_set_limb_state(limb, new_state, is_player)
		
		# 应用状态效果
		apply_limb_effect(limb, _state_to_string(new_state), is_player)
		
		# 发射信号
		if new_state == LimbState.BROKEN:
			limb_broken.emit(limb, is_player)
		else:
			limb_damaged.emit(limb, new_state, is_player)
	
	# 发射更新信号
	all_limbs_updated.emit(player_limbs, enemy_limbs)

# ========== 状态效果应用 ==========
## 应用部位效果
## @param limb: 目标部位
## @param state: 状态字符串 ("normal", "damaged", "broken")
## @param is_player: 是否应用到玩家
func apply_limb_effect(limb: LimbType, state: String, is_player: bool) -> void:
	var effects = LIMB_DATA[limb].effects
	var target = "player" if is_player else "enemy"
	
	# 清除该部位旧效果
	if active_effects[target].has(limb):
		_remove_limb_effects(limb, is_player)
	
	if state == "normal":
		return
	
	# 应用新效果
	if effects.has(state):
		var effect_data = effects[state]
		active_effects[target][limb] = effect_data.duplicate()
		_apply_effect_to_stats(effect_data, is_player)
		limb_effect_applied.emit(limb, state, is_player)

func _apply_effect_to_stats(effect_data: Dictionary, is_player: bool) -> void:
	# 这里将效果应用到实际的游戏数值
	# 通过EventBus或直接与战斗系统交互
	var params = {
		"effects": effect_data,
		"is_player": is_player
	}
	
	if Engine.has_singleton("EventBus"):
		Engine.get_singleton("EventBus").emit_signal("limb_effects_applied", params)
	elif Engine.has_singleton("CombatSystem"):
		Engine.get_singleton("CombatSystem").apply_limb_stat_modifiers(params)

func _remove_limb_effects(limb: LimbType, is_player: bool) -> void:
	var target = "player" if is_player else "enemy"
	if active_effects[target].has(limb):
		var old_effects = active_effects[target][limb]
		# 恢复旧效果（取反）
		var reverse_effects = {}
		for key in old_effects:
			if old_effects[key] is int or old_effects[key] is float:
				reverse_effects[key] = -old_effects[key]
			else:
				reverse_effects[key] = false
		_apply_effect_to_stats(reverse_effects, is_player)
		active_effects[target].erase(limb)

# ========== 治疗/恢复功能 ==========
## 治疗部位
## @param limb: 目标部位
## @param amount: 治疗量
## @param is_player: 是否治疗玩家
## @return: 实际治疗量
func heal_limb(limb: LimbType, amount: int, is_player: bool) -> int:
	var limb_state = get_limb_state(limb, is_player)
	var max_hp = LIMB_DATA[limb].max_hp
	
	var actual_heal = min(amount, max_hp - limb_state.hp)
	if actual_heal <= 0:
		return 0
	
	var new_hp = limb_state.hp + actual_heal
	_set_limb_hp(limb, new_hp, is_player)
	
	# 检查状态恢复
	var new_state = _determine_limb_state(limb, new_hp)
	if new_state != limb_state.state:
		_set_limb_state(limb, new_state, is_player)
		apply_limb_effect(limb, _state_to_string(new_state), is_player)
	
	limb_healed.emit(limb, actual_heal, is_player)
	all_limbs_updated.emit(player_limbs, enemy_limbs)
	
	return actual_heal

## 治疗所有部位
## @param amount: 每个部位的治疗量
## @param is_player: 是否治疗玩家
## @return: 总治疗量
func heal_all_limbs(amount: int, is_player: bool) -> int:
	var total_heal = 0
	for limb in LimbType.values():
		total_heal += heal_limb(limb, amount, is_player)
	return total_heal

## 完全恢复部位
## @param limb: 目标部位，为-1时恢复所有部位
## @param is_player: 是否恢复玩家
func fully_restore_limb(limb: int, is_player: bool) -> void:
	if limb == -1:
		for l in LimbType.values():
			_set_limb_hp(l, LIMB_DATA[l].max_hp, is_player)
			_set_limb_state(l, LimbState.NORMAL, is_player)
	else:
		var limb_type = limb as LimbType
		_set_limb_hp(limb_type, LIMB_DATA[limb_type].max_hp, is_player)
		_set_limb_state(limb_type, LimbState.NORMAL, is_player)
	
	# 清除所有效果
	var target = "player" if is_player else "enemy"
	active_effects[target].clear()
	
	all_limbs_updated.emit(player_limbs, enemy_limbs)

# ========== 查询功能 ==========
## 获取部位状态
func get_limb_state(limb: LimbType, is_player: bool) -> Dictionary:
	var limbs = player_limbs if is_player else enemy_limbs
	return limbs[limb]

## 获取所有部位状态
func get_all_limbs_state(is_player: bool) -> Dictionary:
	return player_limbs if is_player else enemy_limbs

## 获取部位名称
func get_limb_name(limb: LimbType) -> String:
	return LIMB_DATA[limb].name

## 获取部位描述
func get_limb_description(limb: LimbType) -> String:
	var data = LIMB_DATA[limb]
	var desc = "【%s】\n" % data.name
	desc += "最大HP: %d\n" % data.max_hp
	desc += "伤害倍率: %.0f%%\n" % (data.damage_mult * 100)
	desc += "\n受损效果: %s\n" % data.description.damaged
	desc += "损坏效果: %s" % data.description.broken
	return desc

## 获取部位当前效果描述
func get_limb_current_effect(limb: LimbType, is_player: bool) -> String:
	var state = get_limb_state(limb, is_player)
	if state.state == LimbState.NORMAL:
		return "正常"
	var state_str = _state_to_string(state.state)
	return LIMB_DATA[limb].description[state_str]

## 检查部位是否可用
func is_limb_functional(limb: LimbType, is_player: bool) -> bool:
	return get_limb_state(limb, is_player).state != LimbState.BROKEN

## 获取有效部位（未损坏的）
func get_functional_limbs(is_player: bool) -> Array:
	var functional = []
	for limb in LimbType.values():
		if is_limb_functional(limb, is_player):
			functional.append(limb)
	return functional

## 获取随机有效部位（用于随机攻击）
func get_random_functional_limb(is_player: bool) -> LimbType:
	var functional = get_functional_limbs(is_player)
	if functional.is_empty():
		return LimbType.TORSO  # 默认返回躯干
	return functional[randi() % functional.size()]

# ========== 辅助方法 ==========
func _determine_limb_state(limb: LimbType, hp: int) -> LimbState:
	var max_hp = LIMB_DATA[limb].max_hp
	if hp <= 0:
		return LimbState.BROKEN
	elif hp <= max_hp * 0.3:
		return LimbState.DAMAGED
	else:
		return LimbState.NORMAL

func _state_to_string(state: LimbState) -> String:
	match state:
		LimbState.NORMAL: return "normal"
		LimbState.DAMAGED: return "damaged"
		LimbState.BROKEN: return "broken"
	return "normal"

func _set_limb_hp(limb: LimbType, hp: int, is_player: bool) -> void:
	var limbs = player_limbs if is_player else enemy_limbs
	limbs[limb].hp = clamp(hp, 0, limbs[limb].max_hp)

func _set_limb_state(limb: LimbType, state: LimbState, is_player: bool) -> void:
	var limbs = player_limbs if is_player else enemy_limbs
	limbs[limb].state = state

# ========== 存档/读档 ==========
func get_save_data() -> Dictionary:
	return {
		"player_limbs": _serialize_limbs(player_limbs),
		"enemy_limbs": _serialize_limbs(enemy_limbs),
		"active_effects": active_effects.duplicate(true)
	}

func load_save_data(data: Dictionary) -> void:
	if data.has("player_limbs"):
		player_limbs = _deserialize_limbs(data.player_limbs)
	if data.has("enemy_limbs"):
		enemy_limbs = _deserialize_limbs(data.enemy_limbs)
	if data.has("active_effects"):
		active_effects = data.active_effects.duplicate(true)
	all_limbs_updated.emit(player_limbs, enemy_limbs)

func _serialize_limbs(limbs: Dictionary) -> Dictionary:
	var serialized = {}
	for limb in limbs:
		serialized[str(limb)] = limbs[limb]
	return serialized

func _deserialize_limbs(serialized: Dictionary) -> Dictionary:
	var limbs = {}
	for key in serialized:
		var limb_type = int(key)
		limbs[limb_type] = serialized[key]
	return limbs

# ========== 事件回调 ==========
func _on_combat_started(_enemy_data: Dictionary) -> void:
	# 重置敌人部位
	enemy_limbs = _create_default_limbs()
	active_effects.enemy.clear()
	all_limbs_updated.emit(player_limbs, enemy_limbs)

func _on_combat_ended() -> void:
	# 战斗结束后的处理（如持续流血等）
	pass

func _on_game_saved() -> void:
	if Engine.has_singleton("GameState"):
		Engine.get_singleton("GameState").set_data("limb_damage", get_save_data())

func _on_game_loaded() -> void:
	if Engine.has_singleton("GameState"):
		var data = Engine.get_singleton("GameState").get_data("limb_damage", {})
		if not data.is_empty():
			load_save_data(data)

# ========== 调试功能 ==========
func debug_print_status(is_player: bool = true) -> void:
	var target = "玩家" if is_player else "敌人"
	print("=== %s部位状态 ===" % target)
	var limbs = player_limbs if is_player else enemy_limbs
	for limb in LimbType.values():
		var state = limbs[limb]
		var state_name = _state_to_string(state.state).to_upper()
		print("%s: %d/%d [%s]" % [LIMB_DATA[limb].name, state.hp, state.max_hp, state_name])

func debug_damage_limb(limb: LimbType, damage: int, is_player: bool) -> void:
	var result = calculate_limb_damage(damage, limb, is_player)
	apply_limb_damage(result, is_player)
	print("调试: %s受到%d点伤害 -> %s" % [LIMB_DATA[limb].name, result.damage, _state_to_string(result.new_state)])
