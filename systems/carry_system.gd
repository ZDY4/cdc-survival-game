extends Node
# CarrySystem - 负重系统
# 管理玩家负重计算、负重等级判断和惩罚效果

signal weight_changed(current: float, max: float, ratio: float)
signal overload_started(level: int)
signal overload_ended()
signal encumbrance_changed(level: int)

# 负重等级枚举
enum EncumbranceLevel {
	LIGHT,      # 轻载 0-50%
	MEDIUM,     # 中载 50-75%
	HEAVY,      # 重载 75-90%
	OVERLOADED, # 超载 90-100%
	IMMOBILE    # 完全超载 >100%
}

# 背包配置
const BACKPACKS = {
	"none": {
		"name": "无背",
		"carry_bonus": 0.0,
		"description": "初始状"
	},
	"cloth_bag": {
		"name": "简易布",
		"carry_bonus": 5.0,
		"description": "轻量便携"
	},
	"hiking_pack": {
		"name": "登山",
		"carry_bonus": 10.0,
		"description": "户外运动"
	},
	"military_pack": {
		"name": "军用背包",
		"carry_bonus": 20.0,
		"description": "专业装备"
	},
	"tactical_pack": {
		"name": "战术背包",
		"carry_bonus": 25.0,
		"description": "顶级背包"
	}
}

# 默认物品重量 (kg)
const DEFAULT_ITEM_WEIGHT = 0.1

# 基础负重配置
const BASE_CARRY_WEIGHT = 30.0      # 基础负重 30kg
const STRENGTH_CARRY_BONUS = 3.0    # 每点力量 +3kg

# 当前状"
var _current_weight: float = 0.0
var _max_carry_weight: float = BASE_CARRY_WEIGHT
var _current_encumbrance: int = EncumbranceLevel.LIGHT

func _ready():
	print("[CarrySystem] 负重系统已初始化")
	_recalculate_max_weight()
	_recalculate_current_weight()

# ===== 核心计算 =====

## 重新计算最大负"
func _recalculate_max_weight():
	var base = BASE_CARRY_WEIGHT
	var strength_bonus = _get_strength_bonus()
	var backpack_bonus = _get_backpack_bonus()
	var equipment_bonus = _get_equipment_bonus()
	
	_max_carry_weight = base + strength_bonus + backpack_bonus + equipment_bonus
	
	# 检查负重等级变"
	_update_encumbrance_level()

## 重新计算当前重量
func _recalculate_current_weight():
	var total = 0.0
	
	# 1. 装备重量
	total += _get_equipment_weight()
	
	# 2. 武器重量
	total += _get_weapon_weight()
	
	# 3. 背包物品重量
	total += _get_inventory_weight()
	
	var old_weight = _current_weight
	_current_weight = total
	
	# 发送信"
	if not is_equal_approx(old_weight, _current_weight):
		var ratio = get_weight_ratio()
		weight_changed.emit(_current_weight, _max_carry_weight, ratio)
	
	_update_encumbrance_level()

## 获取力量加成
func _get_strength_bonus():
	if GameState.has_method("get_player_stat"):
		var strength = GameState.get_player_stat("strength")
		return strength * STRENGTH_CARRY_BONUS
	return 0.0

## 获取背包加成
func _get_backpack_bonus():
	return 0.0

## 获取装备负重加成
func _get_equipment_bonus():
	var bonus = 0.0
	
	# 使用统一装备系统
	var equip_system = GameState.get_equipment_system() if GameState else null
	if equip_system:
		bonus = equip_system.calculate_carry_bonus()
	
	return bonus

## 获取装备重量
func _get_equipment_weight():
	var weight = 0.0
	
	# 使用统一装备系统
	var equip_system = GameState.get_equipment_system() if GameState else null
	if equip_system:
		weight = equip_system.calculate_total_weight()
	
	return weight

## 获取武器重量（现在包含在统一装备系统中）
func _get_weapon_weight():
	# 统一装备系统已经包含武器重量
	# 这里返回0以避免重复计"
	return 0.0

## 获取背包物品重量
func _get_inventory_weight():
	var weight = 0.0
	
	if InventoryModule.has_method("get_inventory_weight"):
		weight = InventoryModule.get_inventory_weight()
	elif GameState.has("inventory_items"):
		# 备用计算
		for item in GameState.inventory_items:
			var item_weight = get_item_weight(item.get("id", ""))
			var count = item.get("count", 1)
			weight += item_weight * count
	
	return weight

## 更新负重等级
func _update_encumbrance_level():
	var old_level = _current_encumbrance
	var ratio = get_weight_ratio()
	
	if ratio > 1.0:
		_current_encumbrance = EncumbranceLevel.IMMOBILE
	elif ratio >= 0.9:
		_current_encumbrance = EncumbranceLevel.OVERLOADED
	elif ratio >= 0.75:
		_current_encumbrance = EncumbranceLevel.HEAVY
	elif ratio >= 0.5:
		_current_encumbrance = EncumbranceLevel.MEDIUM
	else:
		_current_encumbrance = EncumbranceLevel.LIGHT
	
	# 发送等级变化信"
	if old_level != _current_encumbrance:
		encumbrance_changed.emit(_current_encumbrance)
		
		# 超载开"结束信号
		if _current_encumbrance >= EncumbranceLevel.OVERLOADED && old_level < EncumbranceLevel.OVERLOADED:
			overload_started.emit(_current_encumbrance)
		elif _current_encumbrance < EncumbranceLevel.OVERLOADED && old_level >= EncumbranceLevel.OVERLOADED:
			overload_ended.emit()

# ===== 公共接口 =====

## 获取当前重量
func get_current_weight():
	_recalculate_current_weight()
	return _current_weight

## 获取最大负"
func get_max_carry_weight():
	_recalculate_max_weight()
	return _max_carry_weight

## 获取负重比例 (0.0 - 1.0+)
func get_weight_ratio():
	if _max_carry_weight <= 0:
		return 0.0
	return _current_weight / _max_carry_weight

## 获取负重等级
func get_encumbrance_level():
	return _current_encumbrance

## 获取负重等级名称
func get_encumbrance_name():
	match _current_encumbrance:
		EncumbranceLevel.LIGHT:
			return "轻载"
		EncumbranceLevel.MEDIUM:
			return "中载"
		EncumbranceLevel.HEAVY:
			return "重载"
		EncumbranceLevel.OVERLOADED:
			return "超载"
		EncumbranceLevel.IMMOBILE:
			return "完全超载"
	return "未知"

## 获取物品重量
func get_item_weight(item_id: String):
	# 优先从统一装备系统查询
	var equip_system = GameState.get_equipment_system() if GameState else null
	if equip_system:
		var item_data = equip_system.get_item_data(item_id)
		if item_data && item_data.size() > 0:
			return item_data.get("weight", DEFAULT_ITEM_WEIGHT)
	
	# 从CraftingSystem查物品数"
	var crafting_items = CraftingSystem.get("ITEMS")
	if crafting_items && crafting_items.has(item_id):
		var item_data = crafting_items[item_id]
		return item_data.get("weight", DEFAULT_ITEM_WEIGHT)
	
	# 默认重量
	return DEFAULT_ITEM_WEIGHT

## 检查是否可以拾取物"
func can_carry_item(item_id: String, count: int = 1):
	var item_weight = get_item_weight(item_id) * count
	var projected_weight = _current_weight + item_weight
	return projected_weight <= _max_carry_weight

## 获取超重数量 (用于显示还需要丢弃多"
func get_excess_weight():
	var excess = _current_weight - _max_carry_weight
	return maxf(excess, 0.0)

# ===== 惩罚效果 =====

## 获取移动时间倍数
func get_movement_penalty():
	match _current_encumbrance:
		EncumbranceLevel.LIGHT:
			return 1.0
		EncumbranceLevel.MEDIUM:
			return 1.3
		EncumbranceLevel.HEAVY:
			return 1.6
		EncumbranceLevel.OVERLOADED:
			return 2.2
		EncumbranceLevel.IMMOBILE:
			return 5.0
	return 1.0

## 获取闪避惩罚
func get_dodge_penalty():
	match _current_encumbrance:
		EncumbranceLevel.LIGHT:
			return 0.0
		EncumbranceLevel.MEDIUM:
			return 0.1  # -10%
		EncumbranceLevel.HEAVY:
			return 0.2  # -20%
		EncumbranceLevel.OVERLOADED:
			return 0.4  # -40%
		EncumbranceLevel.IMMOBILE:
			return 1.0  # -100% (无法闪避)
	return 0.0

## 获取先手惩罚
func get_initiative_penalty():
	match _current_encumbrance:
		EncumbranceLevel.LIGHT:
			return 0
		EncumbranceLevel.MEDIUM:
			return 0
		EncumbranceLevel.HEAVY:
			return 5
		EncumbranceLevel.OVERLOADED:
			return 10
		EncumbranceLevel.IMMOBILE:
			return 999  # 无法行动
	return 0

## 检查是否可以移"
func can_move():
	return _current_encumbrance < EncumbranceLevel.IMMOBILE

## 检查是否可以战"
func can_fight():
	return _current_encumbrance < EncumbranceLevel.OVERLOADED

## 获取遇敌概率加成
func get_encounter_chance_bonus():
	if _current_encumbrance >= EncumbranceLevel.OVERLOADED:
		return 0.2  # +20%遇敌
	return 0.0

# ===== 外部触发更新 =====

## 装备变化时调"
func on_equipment_changed():
	_recalculate_max_weight()
	_recalculate_current_weight()

## 背包变化时调"
func on_inventory_changed():
	_recalculate_current_weight()

## 武器变化时调"
func on_weapon_changed():
	_recalculate_current_weight()

# ===== 存档接口 =====

func get_save_data():
	return {
		"current_weight": _current_weight,
		"max_carry_weight": _max_carry_weight
	}

func load_save_data(data: Dictionary):
	_current_weight = data.get("current_weight", 0.0)
	_max_carry_weight = data.get("max_carry_weight", BASE_CARRY_WEIGHT)
	_update_encumbrance_level()
	print("[CarrySystem] 负重数据已加")

# ===== 调试 =====

func print_status():
	print("=== 负重状态 ===")
	print("当前重量: %.1f kg" % _current_weight)
	print("最大负重: %.1f kg" % _max_carry_weight)
	print("负重比例: %.1f%%" % (get_weight_ratio() * 100))
	print("负重等级: %s" % get_encumbrance_name())
	print("移动惩罚: %.1fx" % get_movement_penalty())
	print("================")

