extends Node
# UnifiedEquipmentSystem - 统一装备系统
# 合并武器和装备，支持10个槽位

# 装备槽位枚举
enum EquipmentSlot {
	HEAD,       # 头部
	BODY,       # 身体
	HANDS,      # 手部
	LEGS,       # 腿部
	FEET,       # 脚部
	BACK,       # 背部
	MAIN_HAND,  # 主手（武器）
	OFF_HAND,   # 副手（武器/盾牌）
	ACCESSORY_1,# 饰品1
	ACCESSORY_2 # 饰品2
}

const SLOT_NAMES = {
	"head": "头部",
	"body": "身体",
	"hands": "手部",
	"legs": "腿部",
	"feet": "脚部",
	"back": "背部",
	"main_hand": "主手",
	"off_hand": "副手",
	"accessory_1": "饰品1",
	"accessory_2": "饰品2"
}

# ===== 统一物品数据 =====
const ITEMS = {
	# === 武器 (slot: main_hand/off_hand) ===
	"fist": {
		"name": "拳头",
		"description": "最基础的攻击方",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "unarmed",
		"rarity": "common",
		"weight": 0.0,
		"durability": -1,
		"max_durability": -1,
		"weapon_data": {
			"damage": 5,
			"attack_speed": 1.0,
			"range": 1,
			"stamina_cost": 2,
			"crit_chance": 0.05,
			"crit_multiplier": 1.5
		},
		"special_effects": [],
		"required_level": 0
	},
	
	"knife": {
		"name": "小刀",
		"description": "锋利的匕首，适合近距离战",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "dagger",
		"rarity": "common",
		"weight": 0.3,
		"durability": 50,
		"max_durability": 50,
		"weapon_data": {
			"damage": 12,
			"attack_speed": 1.2,
			"range": 1,
			"stamina_cost": 3,
			"crit_chance": 0.15,
			"crit_multiplier": 2.0
		},
		"special_effects": ["bleeding"],
		"effect_data": {
			"bleeding_damage": 2,
			"bleeding_duration": 3
		},
		"required_level": 1,
		"repair_materials": [{"item": "scrap_metal", "count": 2}],
		"can_craft": true,
		"craft_recipe": {
			"materials": [{"item": "scrap_metal", "count": 3}, {"item": "component_electronic", "count": 1}],
			"time": 30
		}
	},
	
	"baseball_bat": {
		"name": "棒球",
		"description": "结实的木棒，可以造成不错的伤",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "blunt",
		"rarity": "common",
		"weight": 1.2,
		"durability": 40,
		"max_durability": 40,
		"weapon_data": {
			"damage": 15,
			"attack_speed": 0.9,
			"range": 2,
			"stamina_cost": 5,
			"crit_chance": 0.10,
			"crit_multiplier": 1.5
		},
		"special_effects": ["stun"],
		"effect_data": {
			"stun_chance": 0.2,
			"stun_duration": 1
		},
		"required_level": 1,
		"repair_materials": [{"item": "scrap_metal", "count": 3}],
		"can_craft": true,
		"craft_recipe": {
			"materials": [{"item": "scrap_metal", "count": 5}],
			"time": 45
		}
	},
	
	"pipe_wrench": {
		"name": "管钳",
		"description": "沉重的金属工具，伤害可观",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "blunt",
		"rarity": "common",
		"weight": 2.0,
		"durability": 60,
		"max_durability": 60,
		"weapon_data": {
			"damage": 20,
			"attack_speed": 0.8,
			"range": 2,
			"stamina_cost": 7,
			"crit_chance": 0.08,
			"crit_multiplier": 1.8
		},
		"special_effects": ["armor_break"],
		"effect_data": {
			"armor_break_chance": 0.25
		},
		"required_level": 2,
		"repair_materials": [{"item": "scrap_metal", "count": 4}],
		"can_craft": true,
		"craft_recipe": {
			"materials": [{"item": "scrap_metal", "count": 8}, {"item": "tool_kit", "count": 1}],
			"time": 60
		}
	},
	
	"machete": {
		"name": "砍刀",
		"description": "锋利的砍刀，对付僵尸很有效",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "sword",
		"rarity": "uncommon",
		"weight": 1.0,
		"durability": 45,
		"max_durability": 45,
		"weapon_data": {
			"damage": 25,
			"attack_speed": 1.0,
			"range": 2,
			"stamina_cost": 6,
			"crit_chance": 0.12,
			"crit_multiplier": 2.0
		},
		"special_effects": ["cleave", "bleeding"],
		"effect_data": {
			"cleave_damage": 0.5,
			"bleeding_damage": 3,
			"bleeding_duration": 4
		},
		"required_level": 3,
		"repair_materials": [{"item": "scrap_metal", "count": 5}],
		"can_craft": true,
		"craft_recipe": {
			"materials": [{"item": "scrap_metal", "count": 10}, {"item": "tool_kit", "count": 1}],
			"time": 90
		}
	},
	
	"katana": {
		"name": "武士刀",
		"description": "锋利的日本刀，极其致",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "sword",
		"rarity": "rare",
		"weight": 1.2,
		"durability": 80,
		"max_durability": 80,
		"weapon_data": {
			"damage": 35,
			"attack_speed": 1.3,
			"range": 3,
			"stamina_cost": 8,
			"crit_chance": 0.20,
			"crit_multiplier": 2.5
		},
		"special_effects": ["cleave", "bleeding", "decapitation"],
		"effect_data": {
			"cleave_damage": 0.7,
			"bleeding_damage": 5,
			"bleeding_duration": 5,
			"decapitation_chance": 0.1
		},
		"required_level": 5,
		"repair_materials": [{"item": "scrap_metal", "count": 8}, {"item": "component_electronic", "count": 2}],
		"can_craft": true,
		"craft_recipe": {
			"materials": [{"item": "scrap_metal", "count": 15}, {"item": "component_electronic", "count": 3}, {"item": "tool_kit", "count": 2}],
			"time": 120
		}
	},
	
	"chainsaw": {
		"name": "电锯",
		"description": "恐怖的伤害，但需要燃",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "heavy",
		"rarity": "epic",
		"weight": 4.0,
		"durability": 100,
		"max_durability": 100,
		"weapon_data": {
			"damage": 50,
			"attack_speed": 0.6,
			"range": 2,
			"stamina_cost": 15,
			"crit_chance": 0.05,
			"crit_multiplier": 3.0,
			"fuel_consumption": 1
		},
		"special_effects": ["bleeding", "fear"],
		"effect_data": {
			"bleeding_damage": 8,
			"bleeding_duration": 6,
			"fear_chance": 0.3
		},
		"required_level": 6,
		"repair_materials": [{"item": "scrap_metal", "count": 10}, {"item": "component_electronic", "count": 3}],
		"can_craft": true,
		"craft_recipe": {
			"materials": [{"item": "scrap_metal", "count": 20}, {"item": "component_electronic", "count": 5}, {"item": "tool_kit", "count": 3}],
			"time": 180
		}
	},
	
	# === 远程武器 ===
	"slingshot": {
		"name": "弹弓",
		"description": "简易的远程武器",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "light",
		"rarity": "common",
		"weight": 0.2,
		"durability": 30,
		"max_durability": 30,
		"weapon_data": {
			"damage": 8,
			"attack_speed": 1.0,
			"range": 10,
			"accuracy": 70,
			"stamina_cost": 2,
			"crit_chance": 0.05,
			"crit_multiplier": 1.5,
			"ammo_type": "stone",
			"max_ammo": 1,
			"reload_time": 1.0
		},
		"special_effects": ["headshot_bonus"],
		"effect_data": {
			"headshot_damage": 1.5
		},
		"required_level": 1,
		"repair_materials": [{"item": "scrap_metal", "count": 2}],
		"can_craft": true,
		"craft_recipe": {
			"materials": [{"item": "scrap_metal", "count": 2}],
			"time": 20
		}
	},
	
	"pistol": {
		"name": "手枪",
		"description": "可靠的副武器",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "pistol",
		"rarity": "uncommon",
		"weight": 0.8,
		"durability": 100,
		"max_durability": 100,
		"weapon_data": {
			"damage": 25,
			"attack_speed": 1.2,
			"range": 25,
			"accuracy": 80,
			"stamina_cost": 3,
			"crit_chance": 0.10,
			"crit_multiplier": 2.0,
			"ammo_type": "ammo_pistol",
			"max_ammo": 12,
			"reload_time": 2.0
		},
		"special_effects": ["headshot_bonus"],
		"effect_data": {
			"headshot_damage": 2.0
		},
		"required_level": 3,
		"repair_materials": [{"item": "scrap_metal", "count": 5}, {"item": "component_electronic", "count": 2}],
		"can_craft": true,
		"craft_recipe": {
			"materials": [{"item": "scrap_metal", "count": 12}, {"item": "component_electronic", "count": 3}],
			"time": 100
		}
	},
	
	"shotgun": {
		"name": "霰弹",
		"description": "近距离威力巨",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "shotgun",
		"rarity": "rare",
		"weight": 4.0,
		"durability": 80,
		"max_durability": 80,
		"weapon_data": {
			"damage": 40,
			"attack_speed": 0.7,
			"range": 15,
			"accuracy": 60,
			"stamina_cost": 8,
			"crit_chance": 0.08,
			"crit_multiplier": 1.5,
			"ammo_type": "ammo_shotgun",
			"max_ammo": 6,
			"reload_time": 3.0
		},
		"special_effects": ["spread", "knockback"],
		"effect_data": {
			"spread_targets": 3,
			"spread_damage": 0.6,
			"knockback_chance": 0.4
		},
		"required_level": 4,
		"repair_materials": [{"item": "scrap_metal", "count": 8}],
		"can_craft": true,
		"craft_recipe": {
			"materials": [{"item": "scrap_metal", "count": 15}],
			"time": 120
		}
	},
	
	"rifle": {
		"name": "步枪",
		"description": "精准的中距离武器",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "rifle",
		"rarity": "rare",
		"weight": 3.5,
		"durability": 90,
		"max_durability": 90,
		"weapon_data": {
			"damage": 45,
			"attack_speed": 0.8,
			"range": 50,
			"accuracy": 90,
			"stamina_cost": 5,
			"crit_chance": 0.15,
			"crit_multiplier": 2.5,
			"ammo_type": "ammo_rifle",
			"max_ammo": 10,
			"reload_time": 2.5
		},
		"special_effects": ["headshot_bonus", "armor_pierce"],
		"effect_data": {
			"headshot_damage": 3.0,
			"armor_pierce": 0.5
		},
		"required_level": 5,
		"repair_materials": [{"item": "scrap_metal", "count": 6}, {"item": "component_electronic", "count": 3}],
		"can_craft": true,
		"craft_recipe": {
			"materials": [{"item": "scrap_metal", "count": 18}, {"item": "component_electronic", "count": 5}],
			"time": 150
		}
	},
	
	"assault_rifle": {
		"name": "突击步枪",
		"description": "全自动火力压",
		"type": "weapon",
		"slot": "main_hand",
		"subtype": "rifle",
		"rarity": "epic",
		"weight": 4.2,
		"durability": 120,
		"max_durability": 120,
		"weapon_data": {
			"damage": 30,
			"attack_speed": 2.0,
			"range": 40,
			"accuracy": 75,
			"stamina_cost": 6,
			"crit_chance": 0.08,
			"crit_multiplier": 1.8,
			"ammo_type": "ammo_rifle",
			"max_ammo": 30,
			"reload_time": 3.0
		},
		"special_effects": ["burst_fire"],
		"effect_data": {
			"burst_count": 3
		},
		"required_level": 6,
		"repair_materials": [{"item": "scrap_metal", "count": 8}, {"item": "component_electronic", "count": 4}],
		"can_craft": true,
		"craft_recipe": {
			"materials": [{"item": "scrap_metal", "count": 25}, {"item": "component_electronic", "count": 8}],
			"time": 200
		}
	},
	
	# === 防具 (slot: head/body/hands/legs/feet/back) ===
	"helmet_makeshift": {
		"name": "简易头",
		"description": "用废金属拼凑的防护头",
		"type": "armor",
		"slot": "head",
		"rarity": "common",
		"weight": 1.5,
		"durability": 30,
		"max_durability": 30,
		"armor_data": {
			"defense": 2,
			"insulation": 0.1
		},
		"special_effects": [],
		"required_level": 1,
		"repair_materials": [{"item": "scrap_metal", "count": 2}]
	},
	
	"backpack_small": {
		"name": "小背",
		"description": "简易布袋，增加负重能力",
		"type": "armor",
		"slot": "back",
		"rarity": "common",
		"weight": 0.5,
		"durability": 30,
		"max_durability": 30,
		"armor_data": {
			"carry_bonus": 5.0
		},
		"special_effects": [],
		"required_level": 1,
		"repair_materials": [{"item": "cloth", "count": 3}]
	}
}

# ===== 当前装备状态 =====
var _equipped_items: Dictionary = {
	"head": null,
	"body": null,
	"hands": null,
	"legs": null,
	"feet": null,
	"back": null,
	"main_hand": "fist",  # 默认拳头
	"off_hand": null,
	"accessory_1": null,
	"accessory_2": null
}

# 装备耐久度（实例数据）
var _item_instances: Dictionary = {}

# ===== 信号 =====
signal item_equipped(slot: String, item_id: String)
signal item_unequipped(slot: String, item_id: String)
signal item_broken(slot: String, item_id: String)
signal durability_changed(slot: String, durability_percent: float)
signal ammo_changed(ammo_type: String, current: int, max_ammo: int)

func _ready():
	print("[UnifiedEquipmentSystem] 统一装备系统已初始化")
	# 确保主手有默认武器
	if not _equipped_items.main_hand:
		_equip_item_internal("main_hand", "fist")

# ===== 核心接口 =====

## 装备物品
func equip(item_id: String, slot: String = ""):
	if not ItemDatabase.has_item(item_id):
		print("[Equipment] 物品不存在: " + item_id)
		return false
	
	var item_data = ItemDatabase.get_item(item_id)
	var target_slot = slot if slot != "" else item_data.slot
	
	# 检查槽位是否匹配
	if item_data.slot != target_slot && not _is_compatible_slot(item_data.slot, target_slot):
		print("[Equipment] 物品不能装备到该槽位: " + item_id + " -> " + target_slot)
		return false
	
	# 检查等级要求
	if item_data.get("required_level", 0) > _get_player_level():
		print("[Equipment] 等级不足")
		return false
	
	# 卸下当前装备
	if _equipped_items[target_slot]:
		unequip(target_slot)
	
	# 装备新物品
	return _equip_item_internal(target_slot, item_id)

## 卸下装备
func unequip(slot: String):
	if not _equipped_items.has(slot):
		return false
	
	var current_id = _equipped_items[slot]
	if not current_id:
		return true  # 本来就没有装备
	
	# 如果是主手武器，切换到拳头
	if slot == "main_hand":
		_equip_item_internal("main_hand", "fist")
	else:
		_equipped_items[slot] = null
	
	item_unequipped.emit(slot, current_id)
	print("[Equipment] 卸下: " + current_id + " from " + slot)
	return true

## 获取当前装备
func get_equipped(slot: String):
	return _equipped_items.get(slot, "")

## 获取装备数据
func get_item_data(item_id: String):
	return ItemDatabase.get_item(item_id)

## 获取槽位中的完整数据
func get_equipped_data(slot: String):
	var item_id = _equipped_items.get(slot, "")
	if not item_id:
		return {}
	
	var base_data = ItemDatabase.get_item(item_id).duplicate()
	base_data.id = item_id
	
	# 添加实例数据（耐久等）
	if _item_instances.has(item_id):
		base_data.current_durability = _item_instances[item_id].durability
	
	return base_data

# ===== 战斗属性计算 =====

## 计算战斗属性
func calculate_combat_stats():
	var stats = {
		"damage": 0,
		"attack_speed": 1.0,
		"range": 1,
		"defense": 0,
		"crit_chance": 0.05,
		"crit_multiplier": 1.5,
		"stamina_cost": 0
	}
	
	# 主手武器
	var main_hand_data = get_equipped_data("main_hand")
	if main_hand_data && main_hand_data.get("type") == "weapon":
		var weapon = main_hand_data.get("weapon_data", {})
		stats.damage = weapon.get("damage", 0)
		stats.attack_speed = weapon.get("attack_speed", 1.0)
		stats.range = weapon.get("range", 1)
		stats.crit_chance = weapon.get("crit_chance", 0.05)
		stats.crit_multiplier = weapon.get("crit_multiplier", 1.5)
		stats.stamina_cost = weapon.get("stamina_cost", 0)
	
	# 防具加成
	for slot in ["head", "body", "hands", "legs", "feet"]:
		var armor_data = get_equipped_data(slot)
		if armor_data && armor_data.get("type") == "armor":
			var armor = armor_data.get("armor_data", {})
			stats.defense += armor.get("defense", 0)
	
	return stats

## 计算总负重
func calculate_total_weight():
	var total = 0.0
	for slot in _equipped_items.keys():
		var item_id = _equipped_items[slot]
		if item_id && ItemDatabase.has_item(item_id):
			total += ItemDatabase.get_item_weight(item_id)
	return total

## 计算负重加成
func calculate_carry_bonus():
	var bonus = 0.0
	
	# 背部装备
	var back_data = get_equipped_data("back")
	if back_data && back_data.get("type") == "armor":
		bonus += back_data.get("armor_data", {}).get("carry_bonus", 0.0)
	
	# 其他装备可能有负重加成
	for slot in ["body", "hands", "legs", "feet"]:
		var item_data = get_equipped_data(slot)
		if item_data && item_data.get("type") == "armor":
			bonus += item_data.get("armor_data", {}).get("carry_bonus", 0.0)
	
	return bonus

# ===== 耐久度系统 =====

## 消耗耐久
func consume_durability(slot: String, amount: int = 1):
	var item_id = _equipped_items.get(slot, "")
	if not item_id || not _item_instances.has(item_id):
		return
	
	var instance = _item_instances[item_id]
	instance.durability = maxi(0, instance.durability - amount)
	
	var max_dur = ItemDatabase.get_max_durability(item_id)
	var percent = float(instance.durability) / max_dur
	durability_changed.emit(slot, percent)
	
	if instance.durability <= 0:
		_item_broken(slot, item_id)

## 修复装备
func repair(slot: String):
	var item_id = _equipped_items.get(slot, "")
	if not item_id:
		return false
	
	var item_data = ItemDatabase.get_item(item_id)
	var repair_materials = item_data.get("repair_materials", [])
	var max_durability = ItemDatabase.get_max_durability(item_id)
	
	# 检查材料
	for material in repair_materials:
		if not InventoryModule.has_item(material.item, material.count):
			return false
	
	# 消耗材料
	for material in repair_materials:
		InventoryModule.remove_item(material.item, material.count)
	
	# 恢复耐久
	if not _item_instances.has(item_id):
		_item_instances[item_id] = {"durability": max_durability}
	else:
		_item_instances[item_id].durability = max_durability
	
	print("[Equipment] 修复: " + item_id)
	return true

# ===== 弹药系统 =====

## 当前弹药
var _current_ammo: Dictionary = {
	"ammo_pistol": 0,
	"ammo_shotgun": 0,
	"ammo_rifle": 0,
	"stone": 999  # 石头无限
}

## 添加弹药
func add_ammo(ammo_type: String, count: int = 1):
	_current_ammo[ammo_type] = _current_ammo.get(ammo_type, 0) + count
	var max_ammo = _get_max_ammo_capacity(ammo_type)
	ammo_changed.emit(ammo_type, _current_ammo[ammo_type], max_ammo)

## 消耗弹药
func consume_ammo(ammo_type: String, count: int = 1):
	if _current_ammo.get(ammo_type, 0) >= count:
		_current_ammo[ammo_type] -= count
		var max_ammo = _get_max_ammo_capacity(ammo_type)
		ammo_changed.emit(ammo_type, _current_ammo[ammo_type], max_ammo)
		return true
	return false

## 获取当前弹药
func get_ammo(ammo_type: String):
	return _current_ammo.get(ammo_type, 0)

## 获取总属性
func get_total_stats():
	var stats = {
		"damage": 0,
		"defense": 0,
		"damage_reduction": 0.0,
		"carry_bonus": 0.0
	}
	
	# 主手武器伤害
	var main_hand_data = get_equipped_data("main_hand")
	if main_hand_data && main_hand_data.get("type") == "weapon":
		stats.damage = main_hand_data.get("weapon_data", {}).get("damage", 0)
	
	# 防具加成
	for slot in ["head", "body", "hands", "legs", "feet"]:
		var armor_data = get_equipped_data(slot)
		if armor_data && armor_data.get("type") == "armor":
			var armor = armor_data.get("armor_data", {})
			stats.defense += armor.get("defense", 0)
			stats.damage_reduction += armor.get("damage_reduction", 0.0)
	
	# 负重加成
	stats.carry_bonus = calculate_carry_bonus()
	
	return stats

## 当受到伤害时（消耗装备耐久）
func on_damage_taken(damage: int):
	var slots = ["head", "body", "hands", "legs", "feet"]
	for slot in slots:
		if _equipped_items.get(slot):
			var durability_loss = int(damage * 0.1)  # 10%伤害转化为耐久损失
			if durability_loss > 0:
				consume_durability(slot, durability_loss)

## 装填弹药
func reload_weapon():
	var main_hand = get_equipped_data("main_hand")
	if not main_hand || main_hand.get("type") != "weapon":
		return {"success": false, "message": "没有装备武器"}
	
	var weapon_data = main_hand.get("weapon_data", {})
	var ammo_type = weapon_data.get("ammo_type", "")
	
	if not ammo_type:
		return {"success": false, "message": "不需要弹药"}
	
	var max_ammo = weapon_data.get("max_ammo", 0)
	var current_ammo = _current_ammo.get(ammo_type, 0)
	
	if current_ammo <= 0:
		return {"success": false, "message": "没有弹药"}
	
	var to_load = mini(current_ammo, max_ammo)
	_current_ammo[ammo_type] -= to_load
	
	# 这里应该跟踪武器中的弹药，简化处理
	ammo_changed.emit(ammo_type, _current_ammo[ammo_type], max_ammo)
	
	return {"success": true, "ammo_loaded": to_load}

# ===== 私有方法 =====

func _equip_item_internal(slot: String, item_id: String):
	_equipped_items[slot] = item_id
	
	# 初始化实例数据
	if not _item_instances.has(item_id):
		var max_dur = ItemDatabase.get_max_durability(item_id)
		_item_instances[item_id] = {
			"durability": max_dur if max_dur > 0 else 100,
			"enhancements": []
		}
	
	item_equipped.emit(slot, item_id)
	print("[Equipment] 装备: " + item_id + " to " + slot)
	
	# 更新负重系统
	if CarrySystem:
		CarrySystem.on_equipment_changed()
	
	return true

func _is_compatible_slot(item_slot: String, target_slot: String):
	# 武器可以装备到主手或副手
	if item_slot == "main_hand" && target_slot in ["main_hand", "off_hand"]:
		return true
	return item_slot == target_slot

func _item_broken(slot: String, item_id: String):
	item_broken.emit(slot, item_id)
	print("[Equipment] 装备损坏: " + item_id)
	# 卸下损坏的装备
	unequip(slot)

func _get_player_level():
	# 简化实现
	return 1

func _get_max_ammo_capacity(ammo_type: String):
	var main_hand = get_equipped_data("main_hand")
	if main_hand && main_hand.get("type") == "weapon":
		var weapon_ammo = main_hand.get("weapon_data", {}).get("ammo_type", "")
		if weapon_ammo == ammo_type:
			return main_hand.get("weapon_data", {}).get("max_ammo", 0)
	return 0

# ===== 存档接口 =====

func get_save_data():
	return {
		"equipped_items": _equipped_items.duplicate(),
		"item_instances": _item_instances.duplicate(),
		"current_ammo": _current_ammo.duplicate()
	}

func load_save_data(data: Dictionary):
	_equipped_items = data.get("equipped_items", _equipped_items)
	_item_instances = data.get("item_instances", {})
	_current_ammo = data.get("current_ammo", _current_ammo)
	
	# 确保主手有武器
	if not _equipped_items.get("main_hand"):
		_equip_item_internal("main_hand", "fist")
	
	print("[UnifiedEquipmentSystem] 装备数据已加载")

## 执行攻击 (兼容旧WeaponSystem接口)
func perform_attack():
	var main_hand = get_equipped_data("main_hand")
	if not main_hand || main_hand.get("type") != "weapon":
		return {"success": false, "message": "没有装备武器"}
	
	var weapon_data = main_hand.get("weapon_data", {})
	var ammo_type = weapon_data.get("ammo_type", "")
	
	# 检查弹药
	if ammo_type && ammo_type != "":
		if _current_ammo.get(ammo_type, 0) <= 0:
			return {"success": false, "message": "没有弹药"}
		_current_ammo[ammo_type] -= 1
		ammo_changed.emit(ammo_type, _current_ammo[ammo_type], weapon_data.get("max_ammo", 0))
	
	# 计算伤害
	var damage = weapon_data.get("damage", 5)
	var crit_chance = weapon_data.get("crit_chance", 0.05)
	var is_critical = randf() < crit_chance
	
	if is_critical:
		damage = int(damage * weapon_data.get("crit_multiplier", 1.5))
	
	# 消耗耐久
	consume_durability("main_hand", 1)
	
	# 应用特效
	var effects_applied = []
	for effect in main_hand.get("special_effects", []):
		match effect:
			"bleeding":
				effects_applied.append({"type": "bleeding", "damage": main_hand.get("effect_data", {}).get("bleeding_damage", 2)})
			"stun":
				if randf() < main_hand.get("effect_data", {}).get("stun_chance", 0.2):
					effects_applied.append({"type": "stun", "duration": 1})
	
	return {
		"success": true,
		"damage": damage,
		"is_critical": is_critical,
		"effects_applied": effects_applied
	}

