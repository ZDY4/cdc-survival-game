extends Node
# ItemDurabilitySystem - 物品耐久系统
# 管理所有装备和工具的耐久度、损坏机制和维修

# ===== 信号 =====
signal durability_changed(item_id: String, current: int, max: int)
signal item_broken(item_id: String, item_name: String)
signal item_repaired(item_id: String, amount: int)
signal repair_failed(item_id: String, reason: String)

# ===== 耐久配置 =====
const DURABILITY_MAX: int = 100
const DURABILITY_BROKEN: int = 0
const REPAIR_KIT_EFFICIENCY: float = 0.5  # 维修包恢复50%耐久

# ===== 物品耐久数据 =====
const ITEM_DURABILITY_DATA: Dictionary = {
	# ===== 武器 =====
	"knife": {"max": 100, "decay_per_use": 2, "type": "weapon", "repairable": true},
	"crowbar": {"max": 150, "decay_per_use": 3, "type": "weapon", "repairable": true},
	"bat": {"max": 80, "decay_per_use": 5, "type": "weapon", "repairable": true},
	"machete": {"max": 120, "decay_per_use": 2, "type": "weapon", "repairable": true},
	"axe": {"max": 100, "decay_per_use": 3, "type": "weapon", "repairable": true},
	"pistol": {"max": 200, "decay_per_use": 1, "type": "weapon", "repairable": true},
	"rifle": {"max": 250, "decay_per_use": 1, "type": "weapon", "repairable": true},
	"shotgun": {"max": 180, "decay_per_use": 2, "type": "weapon", "repairable": true},
	# 数值ID别名（与ItemDatabase保持一致）
	"1002": {"max": 100, "decay_per_use": 2, "type": "weapon", "repairable": true}, # knife
	"1003": {"max": 80, "decay_per_use": 5, "type": "weapon", "repairable": true},  # baseball_bat
	"1004": {"max": 200, "decay_per_use": 1, "type": "weapon", "repairable": true}, # pistol
	"1014": {"max": 120, "decay_per_use": 2, "type": "weapon", "repairable": true}, # machete
	"1018": {"max": 180, "decay_per_use": 2, "type": "weapon", "repairable": true}, # shotgun
	"1019": {"max": 250, "decay_per_use": 1, "type": "weapon", "repairable": true}, # rifle
	"1125": {"max": 150, "decay_per_use": 3, "type": "weapon", "repairable": true}, # crowbar
	
	# ===== 工具 =====
	"screwdriver": {"max": 80, "decay_per_use": 2, "type": "tool", "repairable": true},
	"wrench": {"max": 120, "decay_per_use": 2, "type": "tool", "repairable": true},
	"lockpick": {"max": 50, "decay_per_use": 5, "type": "tool", "repairable": false},
	"flashlight": {"max": 100, "decay_per_use": 1, "type": "tool", "repairable": true, "battery": true},
	"compass": {"max": 200, "decay_per_use": 0, "type": "tool", "repairable": false},
	"fishing_rod": {"max": 60, "decay_per_use": 4, "type": "tool", "repairable": true},
	"hammer": {"max": 120, "decay_per_use": 2, "type": "tool", "repairable": true},
	"1126": {"max": 100, "decay_per_use": 1, "type": "tool", "repairable": true, "battery": true}, # flashlight
	"1150": {"max": 50, "decay_per_use": 5, "type": "tool", "repairable": false}, # lockpick
	"1151": {"max": 80, "decay_per_use": 2, "type": "tool", "repairable": true}, # screwdriver
	"1166": {"max": 120, "decay_per_use": 2, "type": "tool", "repairable": true}, # hammer
	
	# ===== 护甲 =====
	"cloth_armor": {"max": 50, "decay_per_hit": 5, "type": "armor", "repairable": true},
	"leather_jacket": {"max": 80, "decay_per_hit": 4, "type": "armor", "repairable": true},
	"kevlar_vest": {"max": 150, "decay_per_hit": 3, "type": "armor", "repairable": true},
	"military_armor": {"max": 200, "decay_per_hit": 2, "type": "armor", "repairable": true},
	"helmet": {"max": 100, "decay_per_hit": 5, "type": "armor", "repairable": true},
	"riot_shield": {"max": 120, "decay_per_hit": 8, "type": "armor", "repairable": true},
	"2004": {"max": 50, "decay_per_hit": 5, "type": "armor", "repairable": true}, # cloth armor
	"2005": {"max": 80, "decay_per_hit": 4, "type": "armor", "repairable": true}, # leather jacket
	"2007": {"max": 150, "decay_per_hit": 3, "type": "armor", "repairable": true}, # kevlar vest
	"2001": {"max": 100, "decay_per_hit": 5, "type": "armor", "repairable": true}, # helmet
	
	# ===== 装备（背包等） =====
	"small_backpack": {"max": 80, "decay_per_use": 1, "type": "equipment", "repairable": true},
	"large_backpack": {"max": 120, "decay_per_use": 1, "type": "equipment", "repairable": true},
	"tactical_vest": {"max": 150, "decay_per_hit": 3, "type": "equipment", "repairable": true},
	
	# ===== 特殊 =====
	"night_vision": {"max": 80, "decay_per_use": 2, "type": "equipment", "repairable": true, "battery": true},
	"radio": {"max": 100, "decay_per_use": 1, "type": "equipment", "repairable": true, "battery": true},
	"gas_mask": {"max": 60, "decay_per_use": 2, "type": "equipment", "repairable": true}
}

# ===== 维修材料需求 =====
const REPAIR_MATERIALS: Dictionary = {
	"weapon": {"scrap_metal": 2, "cloth": 1},
	"tool": {"scrap_metal": 1, "wood": 1},
	"armor": {"cloth": 3, "scrap_metal": 1},
	"equipment": {"cloth": 2, "rope": 1}
}

# ===== 当前耐久状态 =====
var _durability_data: Dictionary = {}  # item_instance_id -> {current, max, data}

func _ready():
	print("[ItemDurabilitySystem] 物品耐久系统已初始化")

# ===== 耐久管理 =====

## 注册物品到耐久系统
func register_item(item_id: String, instance_id: String = "") -> Dictionary:
	if instance_id.is_empty():
		instance_id = item_id + "_" + str(Time.get_ticks_msec())
	
	if not ITEM_DURABILITY_DATA.has(item_id):
		# 使用默认配置
		_durability_data[instance_id] = {
			"item_id": item_id,
			"current": 100,
			"max": 100,
			"broken": false,
			"data": {"type": "misc", "repairable": false}
		}
	else:
		var data = ITEM_DURABILITY_DATA[item_id]
		_durability_data[instance_id] = {
			"item_id": item_id,
			"current": data.max,
			"max": data.max,
			"broken": false,
			"data": data
		}
	
	return _durability_data[instance_id]

## 使用物品（消耗耐久）
func use_item(instance_id: String) -> bool:
	if not _durability_data.has(instance_id):
		return false
	
	var item = _durability_data[instance_id]
	if item.broken:
		return false
	
	var decay = item.data.get("decay_per_use", 1)
	return _consume_durability_internal(instance_id, decay)

## 攻击使用武器
func use_weapon(item_id: String) -> bool:
	return consume_durability(item_id, _get_decay_for_item(item_id, "decay_per_use", 2))

## 受到伤害（护甲消耗）
func on_damage_taken(instance_id: String, damage_amount: int) -> bool:
	if not _durability_data.has(instance_id):
		return false
	
	var item = _durability_data[instance_id]
	if item.broken:
		return false
	
	# 根据伤害计算耐久消耗
	var base_decay = item.data.get("decay_per_hit", 3)
	var damage_factor = damage_amount / 10.0
	var total_decay = int(base_decay * damage_factor)
	
	return _consume_durability_internal(instance_id, total_decay)

## 消耗耐久（公共接口）
func consume_durability(item_id: String, amount: int) -> bool:
	# 查找物品实例
	var instance_id = _find_item_instance(item_id)
	if instance_id.is_empty():
		# 自动注册
		var data = register_item(item_id)
		instance_id = _find_item_instance(item_id)
	
	return _consume_durability_internal(instance_id, amount)

func _consume_durability_internal(instance_id: String, amount: int) -> bool:
	if not _durability_data.has(instance_id):
		return false
	
	var item = _durability_data[instance_id]
	if item.broken:
		return false
	
	item.current = maxi(0, item.current - amount)
	
	durability_changed.emit(instance_id, item.current, item.max)
	
	# 检查是否损坏
	if item.current <= 0:
		item.broken = true
		item.current = 0
		item_broken.emit(instance_id, item.item_id)
		print("[ItemDurabilitySystem] 物品损坏: %s" % item.item_id)
		return false
	
	return true

## 获取物品耐久
func get_durability(instance_id: String) -> Dictionary:
	if not _durability_data.has(instance_id):
		return {"current": 0, "max": 0, "percent": 0, "broken": true}
	
	var item = _durability_data[instance_id]
	return {
		"current": item.current,
		"max": item.max,
		"percent": float(item.current) / item.max * 100,
		"broken": item.broken
	}

## 获取物品耐久（通过物品ID）
func get_durability_by_item_id(item_id: String) -> Dictionary:
	var instance_id = _find_item_instance(item_id)
	if instance_id.is_empty():
		return {"current": 100, "max": 100, "percent": 100, "broken": false}
	return get_durability(instance_id)

## 查找物品实例ID
func _find_item_instance(item_id: String) -> String:
	for instance_id in _durability_data.keys():
		if _durability_data[instance_id].item_id == item_id:
			return instance_id
	return ""

func _get_decay_for_item(item_id: String, decay_type: String, default_value: int) -> int:
	if ITEM_DURABILITY_DATA.has(item_id):
		return ITEM_DURABILITY_DATA[item_id].get(decay_type, default_value)
	return default_value

# ===== 维修系统 =====

## 检查是否可以维修
func can_repair(instance_id: String) -> Dictionary:
	if not _durability_data.has(instance_id):
		return {"can_repair": false, "reason": "物品未注册"}
	
	var item = _durability_data[instance_id]
	
	if not item.data.get("repairable", false):
		return {"can_repair": false, "reason": "该物品无法维修"}
	
	if item.current >= item.max:
		return {"can_repair": false, "reason": "物品完好无损"}
	
	# 检查材料
	var item_type = item.data.get("type", "misc")
	var required_materials = REPAIR_MATERIALS.get(item_type, {})
	
	var missing_materials = []
	for material in required_materials.keys():
		var needed = required_materials[material]
		if not GameState.has_item(material, needed):
			missing_materials.append("%s x%d" % [material, needed])
	
	if not missing_materials.is_empty():
		return {
			"can_repair": false,
			"reason": "缺少材料: " + ", ".join(missing_materials),
			"missing": missing_materials
		}
	
	return {
		"can_repair": true,
		"materials": required_materials,
		"repair_amount": int(item.max * REPAIR_KIT_EFFICIENCY)
	}

## 维修物品
func repair_item(instance_id: String) -> Dictionary:
	var can_repair_result = can_repair(instance_id)
	
	if not can_repair_result.can_repair:
		repair_failed.emit(instance_id, can_repair_result.reason)
		return {"success": false, "reason": can_repair_result.reason}
	
	var item = _durability_data[instance_id]
	
	# 消耗材料
	var materials = can_repair_result.materials
	for material in materials.keys():
		GameState.remove_item(material, materials[material])
	
	# 计算维修量
	var repair_amount = can_repair_result.repair_amount
	
	# 应用技能加成
	var skill_system = get_node_or_null("/root/SkillSystem")
	if skill_system and skill_system.has_method("get_crafting_bonus"):
		var bonus = skill_system.get_crafting_bonus()
		repair_amount = int(repair_amount * (1.0 + bonus))
	
	# 恢复耐久
	var old_durability = item.current
	item.current = mini(item.max, item.current + repair_amount)
	item.broken = false
	
	var actual_repair = item.current - old_durability
	
	durability_changed.emit(instance_id, item.current, item.max)
	item_repaired.emit(instance_id, actual_repair)
	
	print("[ItemDurabilitySystem] 维修完成: %s 恢复 %d 耐久" % [item.item_id, actual_repair])
	
	return {
		"success": true,
		"repair_amount": actual_repair,
		"new_durability": item.current,
		"materials_used": materials
	}

## 使用维修工具箱
func use_repair_kit(instance_id: String, kit_quality: float = 0.5) -> Dictionary:
	if not _durability_data.has(instance_id):
		return {"success": false, "reason": "物品未注册"}
	
	var item = _durability_data[instance_id]
	
	if item.current >= item.max:
		return {"success": false, "reason": "物品无需维修"}
	
	if not item.data.get("repairable", false):
		return {"success": false, "reason": "该物品无法维修"}
	
	var repair_amount = int(item.max * kit_quality)
	var old_durability = item.current
	item.current = mini(item.max, item.current + repair_amount)
	item.broken = false
	
	var actual_repair = item.current - old_durability
	
	durability_changed.emit(instance_id, item.current, item.max)
	item_repaired.emit(instance_id, actual_repair)
	
	return {
		"success": true,
		"repair_amount": actual_repair,
		"new_durability": item.current
	}

## 完全修复（用于特殊场景）
func fully_repair(instance_id: String) -> bool:
	if not _durability_data.has(instance_id):
		return false
	
	var item = _durability_data[instance_id]
	item.current = item.max
	item.broken = false
	
	durability_changed.emit(instance_id, item.current, item.max)
	return true

# ===== 获取信息 =====

## 获取物品完整信息
func get_item_full_info(item_id: String) -> Dictionary:
	if not ITEM_DURABILITY_DATA.has(item_id):
		return {
			"id": item_id,
			"has_durability": false,
			"description": "普通物品，无耐久"
		}
	
	var data = ITEM_DURABILITY_DATA[item_id]
	var durability_info = get_durability_by_item_id(item_id)
	
	var description = _generate_item_description(item_id, data)
	
	return {
		"id": item_id,
		"has_durability": true,
		"type": data.get("type", "misc"),
		"max_durability": data.max,
		"current_durability": durability_info.current,
		"durability_percent": durability_info.percent,
		"broken": durability_info.broken,
		"repairable": data.get("repairable", false),
		"decay_per_use": data.get("decay_per_use", 0),
		"decay_per_hit": data.get("decay_per_hit", 0),
		"has_battery": data.get("battery", false),
		"description": description,
		"uses": _estimate_remaining_uses(item_id, data, durability_info.current)
	}

func _generate_item_description(item_id: String, data: Dictionary) -> String:
	var desc = ""
	
	match data.get("type", "misc"):
		"weapon":
			desc = "武器: 每次攻击消耗%d耐久" % data.get("decay_per_use", 2)
			if data.get("repairable", false):
				desc += "，可维修"
		"tool":
			desc = "工具: 每次使用消耗%d耐久" % data.get("decay_per_use", 2)
			if data.get("battery", false):
				desc += "，需要电池"
		"armor":
			desc = "护甲: 每次受击消耗%d耐久" % data.get("decay_per_hit", 3)
			if data.get("repairable", false):
				desc += "，可维修"
		"equipment":
			desc = "装备: 正常使用消耗%d耐久" % data.get("decay_per_use", 1)
			if data.get("battery", false):
				desc += "，需要电池"
		_:
			desc = "普通物品"
	
	return desc

func _estimate_remaining_uses(item_id: String, data: Dictionary, current: int) -> int:
	var decay = data.get("decay_per_use", data.get("decay_per_hit", 1))
	if decay <= 0:
		return 999
	return current / decay

## 获取所有可维修物品
func get_repairable_items() -> Array:
	var items = []
	for instance_id in _durability_data.keys():
		var item = _durability_data[instance_id]
		if item.data.get("repairable", false) and item.current < item.max:
			items.append({
				"instance_id": instance_id,
				"item_id": item.item_id,
				"current": item.current,
				"max": item.max,
				"percent": float(item.current) / item.max * 100
			})
	return items

## 获取损坏物品
func get_broken_items() -> Array:
	var items = []
	for instance_id in _durability_data.keys():
		var item = _durability_data[instance_id]
		if item.broken:
			items.append({
				"instance_id": instance_id,
				"item_id": item.item_id
			})
	return items

# ===== 批量操作 =====

## 维修所有可维修物品
func repair_all() -> Dictionary:
	var results = {
		"repaired": [],
		"failed": [],
		"total_repair": 0
	}
	
	var repairable = get_repairable_items()
	for item_info in repairable:
		var result = repair_item(item_info.instance_id)
		if result.success:
			results.repaired.append(item_info.item_id)
			results.total_repair += result.repair_amount
		else:
			results.failed.append({
				"item_id": item_info.item_id,
				"reason": result.reason
			})
	
	return results

# ===== 序列 =====
func serialize() -> Dictionary:
	return {
		"durability_data": _durability_data.duplicate()
	}

func deserialize(data: Dictionary):
	var saved_data = data.get("durability_data", {})
	for instance_id in saved_data.keys():
		_durability_data[instance_id] = saved_data[instance_id]
	print("[ItemDurabilitySystem] 耐久数据已加载，%d 个物品" % _durability_data.size())

