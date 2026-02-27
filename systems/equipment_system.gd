extends Node
# EquipmentSystem - 装备系统
# 管理装备槽位、属性加成、耐久度

signal equipment_equipped(slot: String, item_id: String, item_data: Dictionary)
signal equipment_unequipped(slot: String, item_id: String)
signal equipment_broken(slot: String, item_id: String)
signal equipment_damaged(slot: String, durability_percent: float)
signal stats_changed()

# ===== 装备槽位 =====
enum EquipmentSlot {
	HEAD,      # 头部
	BODY,      # 身体/护甲
	HANDS,     # 手部/手套
	LEGS,      # 腿部/裤子
	FEET,      # 脚部/鞋子
	BACK,      # 背部/背包
	ACCESSORY_1,  # 饰品1
	ACCESSORY_2   # 饰品2
}

const SLOT_NAMES = {
	"head": "头部",
	"body": "身体",
	"hands": "手部",
	"legs": "腿部",
	"feet": "脚部",
	"back": "背部",
	"accessory_1": "饰品1",
	"accessory_2": "饰品2"
}

# ===== 装备数据=====
const EQUIPMENT = {
	# === 头部装备 ===
	"helmet_makeshift": {
		"name": "简易头盔",
		"description": "用废金属拼凑的防护头盔",
		"slot": "head",
		"rarity": "common",
		"weight": 1.5,
		"stats": {
			"defense": 2,
			"insulation": 0.1
		},
		"durability": 30,
		"max_durability": 30,
		"special_effects": [],
		"required_level": 1,
		"repair_materials": [{"item": "scrap_metal", "count": 2}]
	},
	
	"helmet_military": {
		"name": "军用头盔",
		"description": "标准军用装备，提供良好防护",
		"slot": "head",
		"rarity": "rare",
		"stats": {
			"defense": 5,
			"insulation": 0.2,
			"headshot_protection": 0.5  # 50%概率免疫爆头
		},
		"durability": 60,
		"max_durability": 60,
		"special_effects": ["headshot_protection"],
		"required_level": 3,
		"repair_materials": [{"item": "scrap_metal", "count": 4}]
	},
	
	"helmet_advanced": {
		"name": "战术头盔",
		"description": "配备夜视仪接口的高级头盔",
		"slot": "head",
		"rarity": "epic",
		"stats": {
			"defense": 8,
			"insulation": 0.3,
			"accuracy": 10,
			"night_vision": true
		},
		"durability": 80,
		"max_durability": 80,
		"special_effects": ["night_vision", "accuracy_bonus"],
		"required_level": 5,
		"repair_materials": [{"item": "scrap_metal", "count": 6}, {"item": "component_electronic", "count": 2}]
	},
	
	# === 身体装备 ===
	"armor_cloth": {
		"name": "布衣",
		"description": "普通的旧衣服，几乎没有防护",
		"slot": "body",
		"rarity": "common",
		"stats": {
			"defense": 1,
			"insulation": 0.1
		},
		"durability": 20,
		"max_durability": 20,
		"special_effects": [],
		"required_level": 0,
		"repair_materials": [{"item": "cloth", "count": 2}]
	},
	
	"armor_leather": {
		"name": "皮夹克",
		"description": "结实的皮夹克，提供基础防护",
		"slot": "body",
		"rarity": "common",
		"stats": {
			"defense": 3,
			"insulation": 0.3
		},
		"durability": 40,
		"max_durability": 40,
		"special_effects": [],
		"required_level": 1,
		"repair_materials": [{"item": "cloth", "count": 3}]
	},
	
	"armor_metal": {
		"name": "金属护甲",
		"description": "用废金属片制成的护甲",
		"slot": "body",
		"rarity": "uncommon",
		"stats": {
			"defense": 6,
			"insulation": 0.2,
			"speed_penalty": 0.1  # 移动速度-10%
		},
		"durability": 60,
		"max_durability": 60,
		"special_effects": [],
		"required_level": 2,
		"repair_materials": [{"item": "scrap_metal", "count": 5}]
	},
	
	"armor_tactical": {
		"name": "战术背心",
		"description": "军用战术背心，轻便而坚固",
		"slot": "body",
		"rarity": "rare",
		"stats": {
			"defense": 10,
			"insulation": 0.2,
			"ammo_capacity": 20  # 额外弹药容量
		},
		"durability": 80,
		"max_durability": 80,
		"special_effects": ["ammo_capacity"],
		"required_level": 4,
		"repair_materials": [{"item": "scrap_metal", "count": 6}, {"item": "cloth", "count": 3}]
	},
	
	"armor_heavy": {
		"name": "重型护甲",
		"description": "全身重型护甲，防护极佳但行动不便",
		"slot": "body",
		"rarity": "epic",
		"stats": {
			"defense": 15,
			"insulation": 0.4,
			"speed_penalty": 0.2,
			"damage_reduction": 0.25  # 25%伤害减免
		},
		"durability": 100,
		"max_durability": 100,
		"special_effects": ["damage_reduction"],
		"required_level": 6,
		"repair_materials": [{"item": "scrap_metal", "count": 10}, {"item": "component_electronic", "count": 2}]
	},
	
	"armor_hazmat": {
		"name": "防化服",
		"description": "防护化学污染和辐射",
		"slot": "body",
		"rarity": "rare",
		"stats": {
			"defense": 4,
			"insulation": 0.5,
			"			radiation_resistance": 0.8,  # 80%辐射抗性
			"disease_resistance": 0.5
		},
		"durability": 50,
		"max_durability": 50,
		"special_effects": ["radiation_resistance", "disease_resistance"],
		"required_level": 4,
		"repair_materials": [{"item": "cloth", "count": 5}, {"item": "antiseptic", "count": 1}]
	},
	
	# === 手部装备 ===
	"gloves_leather": {
		"name": "皮手套",
		"description": "保护双手的基础手套",
		"slot": "hands",
		"rarity": "common",
		"stats": {
			"defense": 1,
			"insulation": 0.1
		},
		"durability": 25,
		"max_durability": 25,
		"special_effects": [],
		"required_level": 1,
		"repair_materials": [{"item": "cloth", "count": 2}]
	},
	
	"gloves_tactical": {
		"name": "战术手套",
		"description": "提升武器操作精度",
		"slot": "hands",
		"rarity": "uncommon",
		"stats": {
			"defense": 2,
			"accuracy": 5,
			"reload_speed": 0.2  # 装填速度+20%
		},
		"durability": 40,
		"max_durability": 40,
		"special_effects": ["reload_speed"],
		"required_level": 3,
		"repair_materials": [{"item": "cloth", "count": 3}, {"item": "scrap_metal", "count": 1}]
	},
	
	"gloves_power": {
		"name": "动力手套",
		"description": "增强力量，提升近战伤害",
		"slot": "hands",
		"rarity": "rare",
		"stats": {
			"defense": 3,
			"melee_damage": 0.15  # 近战伤害+15%
		},
		"durability": 50,
		"max_durability": 50,
		"special_effects": ["melee_damage"],
		"required_level": 4,
		"repair_materials": [{"item": "scrap_metal", "count": 4}, {"item": "component_electronic", "count": 2}]
	},
	
	# === 腿部装备 ===
	"pants_jeans": {
		"name": "牛仔裤",
		"description": "普通的牛仔裤",
		"slot": "legs",
		"rarity": "common",
		"stats": {
			"defense": 1,
			"insulation": 0.1
		},
		"durability": 20,
		"max_durability": 20,
		"special_effects": [],
		"required_level": 0,
		"repair_materials": [{"item": "cloth", "count": 2}]
	},
	
	"pants_tactical": {
		"name": "战术裤",
		"description": "带多个口袋的战术裤",
		"slot": "legs",
		"rarity": "uncommon",
		"stats": {
			"defense": 3,
			"insulation": 0.2,
			"inventory_slots": 2  # 额外背包格子
		},
		"durability": 45,
		"max_durability": 45,
		"special_effects": ["inventory_bonus"],
		"required_level": 2,
		"repair_materials": [{"item": "cloth", "count": 4}]
	},
	
	# === 脚部装备 ===
	"shoes_sneakers": {
		"name": "运动鞋",
		"description": "舒适的运动鞋",
		"slot": "feet",
		"rarity": "common",
		"stats": {
			"defense": 1,
			"speed_bonus": 0.1  # 移动速度+10%
		},
		"durability": 25,
		"max_durability": 25,
		"special_effects": [],
		"required_level": 1,
		"repair_materials": [{"item": "cloth", "count": 2}]
	},
	
	"boots_combat": {
		"name": "战斗靴",
		"description": "坚固的军靴",
		"slot": "feet",
		"rarity": "uncommon",
		"stats": {
			"defense": 3,
			"insulation": 0.2,
			"stamina_efficiency": 0.15  # 体力消耗15%
		},
		"durability": 50,
		"max_durability": 50,
		"special_effects": ["stamina_efficiency"],
		"required_level": 2,
		"repair_materials": [{"item": "cloth", "count": 3}, {"item": "scrap_metal", "count": 1}]
	},
	
	"boots_advanced": {
		"name": "战术裤",
		"description": "高科技战术靴，静音且舒",
		"slot": "feet",
		"rarity": "rare",
		"stats": {
			"defense": 4,
			"speed_bonus": 0.15,
			"noise_reduction": 0.5,  # 移动噪音-50%
			"stamina_efficiency": 0.2
		},
		"durability": 60,
		"max_durability": 60,
		"special_effects": ["noise_reduction", "stamina_efficiency"],
		"required_level": 4,
		"repair_materials": [{"item": "cloth", "count": 4}, {"item": "component_electronic", "count": 1}]
	},
	
	# === 背部装备 ===
	"backpack_small": {
		"name": "小背包",
		"description": "简易布袋，增加负重能力",
		"slot": "back",
		"rarity": "common",
		"weight": 0.5,
		"stats": {},
		"carry_bonus": 5.0,  # +5kg负重
		"durability": 30,
		"max_durability": 30,
		"special_effects": [],
		"required_level": 1,
		"repair_materials": [{"item": "cloth", "count": 3}]
	},
	
	"backpack_medium": {
		"name": "中背包",
		"description": "登山包，大幅增加负重能力",
		"slot": "back",
		"rarity": "uncommon",
		"weight": 1.2,
		"stats": {},
		"carry_bonus": 10.0,  # +10kg负重
		"durability": 50,
		"max_durability": 50,
		"special_effects": [],
		"required_level": 2,
		"repair_materials": [{"item": "cloth", "count": 5}]
	},
	
	"backpack_large": {
		"name": "大背包",
		"description": "军用级背包，极大增加负重能力",
		"slot": "back",
		"rarity": "rare",
		"weight": 2.0,
		"stats": {},
		"carry_bonus": 20.0,  # +20kg负重
		"durability": 70,
		"max_durability": 70,
		"special_effects": [],
		"required_level": 4,
		"repair_materials": [{"item": "cloth", "count": 7}, {"item": "scrap_metal", "count": 2}]
	},
	
	# === 饰品 ===
	"ring_luck": {
		"name": "幸运戒指",
		"description": "暴击率5%",
		"slot": "accessory",
		"rarity": "rare",
		"stats": {
			"crit_chance": 0.05
		},
		"durability": -1,  # 饰品不消耗耐久
		"max_durability": -1,
		"special_effects": ["crit_chance"],
		"required_level": 3,
		"repair_materials": []
	},
	
	"amulet_health": {
		"name": "生命护符",
		"description": "最大生命值20",
		"slot": "accessory",
		"rarity": "rare",
		"stats": {
			"max_hp": 20
		},
		"durability": -1,
		"max_durability": -1,
		"special_effects": ["max_hp"],
		"required_level": 3,
		"repair_materials": []
	},
	
	"watch_survival": {
		"name": "生存手表",
		"description": "显示更多生存信息",
		"slot": "accessory",
		"rarity": "epic",
		"stats": {
			"hunger_efficiency": 0.1,  # 饥饿消耗10%
			"thirst_efficiency": 0.1   # 口渴消耗10%
		},
		"durability": -1,
		"max_durability": -1,
		"special_effects": ["survival_info"],
		"required_level": 5,
		"repair_materials": []
	}
}

# ===== 当前装备 =====
var equipped_items: Dictionary = {}  # slot -> {id, durability, data}
var equipment_inventory: Array[Dictionary] = []  # 拥有的装备

func _ready():
	print("[EquipmentSystem] 装备系统已初始化")
	# 初始化装备槽位
	for slot in SLOT_NAMES.keys():
		equipped_items[slot] = null

# 装备物品
func equip(item_id: String):
	if not EQUIPMENT.has(item_id):
		push_error("Equipment not found: " + item_id)
		return false
	
	var item_data = EQUIPMENT[item_id]
	var slot = item_data.slot
	
	# 检查等级
	var player_level = _get_player_level()
	if player_level < item_data.required_level:
		print("[Equipment] Level too low")
		return false
	
	# 检查是否拥有
	if not _has_equipment(item_id):
		print("[Equipment] Don't have equipment: " + item_id)
		return false
	
	# 如果该槽位已有装备，先卸下
	if equipped_items[slot] != null:
		unequip(slot)
	
	# 找到背包中的装备并装备
	for item in equipment_inventory:
		if item.id == item_id:
			equipped_items[slot] = item.duplicate()
			equipment_equipped.emit(slot, item_id, item_data)
			print("[Equipment] Equipped: " + item_data.name + " to " + SLOT_NAMES[slot])
			_update_stats()
			return true
	
	return false

# 卸下装备
func unequip(slot: String):
	if equipped_items[slot] == null:
		return false
	
	var item = equipped_items[slot]
	var item_data = EQUIPMENT[item.id]
	
	equipped_items[slot] = null
	equipment_unequipped.emit(slot, item.id)
	print("[Equipment] Unequipped: " + item_data.name)
	_update_stats()
	return true

# 获取装备属性总和
func get_total_stats():
	var totals = {
		"defense": 0,
		"insulation": 0.0,
		"speed_bonus": 0.0,
		"speed_penalty": 0.0,
		"accuracy": 0,
		"crit_chance": 0.0,
		"max_hp": 0,
		"melee_damage": 0.0,
		"inventory_slots": 0,
		"radiation_resistance": 0.0,
		"disease_resistance": 0.0,
		"stamina_efficiency": 0.0,
		"hunger_efficiency": 0.0,
		"thirst_efficiency": 0.0,
		"damage_reduction": 0.0,
		"headshot_protection": 0.0,
		"noise_reduction": 0.0,
		"reload_speed": 0.0
	}
	
	for slot in equipped_items.keys():
		var equipped = equipped_items[slot]
		if equipped == null:
			continue
		
		var item_data = EQUIPMENT[equipped.id]
		var stats = item_data.stats
		
		# 累加所有属性
		for stat_name in totals.keys():
			if stats.has(stat_name):
				totals[stat_name] += stats[stat_name]
	
	return totals

# 更新玩家属性
func _update_stats(level: int = 1):
	var stats = get_total_stats()
	
	# 应用到GameState
	# 防御力影响伤害减免
	GameState.player_defense = stats.defense
	
	# 背包容量
	GameState.inventory_max_slots = 20 + stats.inventory_slots
	
	# 最大生命值
	GameState.player_max_hp = 100 + stats.max_hp
	
	stats_changed.emit()

# 受到伤害时减少装备耐久
func on_damage_taken(damage: int):
	for slot in equipped_items.keys():
		var equipped = equipped_items[slot]
		if equipped == null:
			continue
		
		var item_data = EQUIPMENT[equipped.id]
		if item_data.durability <= 0:  # 饰品不消耗耐久
			continue
		
		# 根据伤害减少耐久
		var durability_loss = maxi(1, damage / 10)
		equipped.durability = maxi(0, equipped.durability - durability_loss)
		
		var durability_percent = float(equipped.durability) / item_data.max_durability
		equipment_damaged.emit(slot, durability_percent)
		
		if equipped.durability <= 0:
			equipment_broken.emit(slot, equipped.id)
			DialogModule.show_dialog(
				"你的 %s 损坏了！" % item_data.name,
				"装备",
				""
			)
			unequip(slot)

# 修复装备
func repair_equipment(item_id: String):
	if not _has_equipment(item_id):
		return false
	
	var item_data = EQUIPMENT[item_id]
	var repair_materials = item_data.get("repair_materials", [])
	
	# 检查材料
	for material in repair_materials:
		if not InventoryModule.has_item(material.item, material.count):
			return false
	
	# 消耗材料
	for material in repair_materials:
		InventoryModule.remove_item(material.item, material.count)
	
	# 修复耐久
	for item in equipment_inventory:
		if item.id == item_id:
			item.durability = item_data.max_durability
			
			# 如果当前装备着，更新equipped_items
			for slot in equipped_items.keys():
				if equipped_items[slot] != null && equipped_items[slot].id == item_id:
					equipped_items[slot].durability = item_data.max_durability
			
			return true
	
	return false

# 添加装备到背包
func add_equipment(item_id: String):
	if not EQUIPMENT.has(item_id):
		return false
	
	# 如果已有，修复耐久
	if _has_equipment(item_id):
		repair_equipment(item_id)
		return true
	
	var item_data = EQUIPMENT[item_id]
	var new_item = {
		"id": item_id,
		"durability": item_data.max_durability,
		"enhancements": []
	}
	
	equipment_inventory.append(new_item)
	print("[Equipment] Added: " + item_data.name)
	return true

# 检查是否拥有装备
func _has_equipment(item_id: String):
	for item in equipment_inventory:
		if item.id == item_id:
			return true
	return false

# 获取某槽位的装备
func get_equipped_in_slot(slot: String):
	if equipped_items.has(slot) && equipped_items[slot] != null:
		var item = equipped_items[slot]
		var item_data = EQUIPMENT[item.id]
		return {
			"id": item.id,
			"name": item_data.name,
			"durability": item.durability,
			"max_durability": item_data.max_durability,
			"stats": item_data.stats
		}
	return {}

# 获取所有已装备
func get_all_equipped():
	var result = {}
	for slot in equipped_items.keys():
		var equipped = get_equipped_in_slot(slot)
		if not equipped.is_empty():
			result[slot] = equipped
	return result

# 获取装备列表
func get_equipment_inventory() -> Array[Dictionary]:
	var result = []
	for item in equipment_inventory:
		var item_data = EQUIPMENT[item.id]
		result.append({
			"id": item.id,
			"name": item_data.name,
			"slot": item_data.slot,
			"durability": item.durability,
			"max_durability": item_data.max_durability,
			"rarity": item_data.rarity,
			"is_equipped": _is_equipped(item.id)
		})
	return result

func _is_equipped(item_id: String):
	for slot in equipped_items.keys():
		if equipped_items[slot] != null && equipped_items[slot].id == item_id:
			return true
	return false

# 辅助方法
func _get_player_level():
	return 1

# 保存/加载
func get_save_data():
	return {
		"equipped_items": equipped_items,
		"equipment_inventory": equipment_inventory
	}

func load_save_data(data: Dictionary):
	equipped_items = data.get("equipped_items", {})
	equipment_inventory = data.get("equipment_inventory", [])
	_update_stats()
	print("[EquipmentSystem] Loaded save data")

# ===== 重量系统接口 =====

## 获取装备重量
func get_equipment_weight(item_id: String):
	if not EQUIPMENT.has(item_id):
		return 0.0
	return EQUIPMENT[item_id].get("weight", 0.0)

## 获取当前已装备装备的总重量
func get_total_weight():
	var total = 0.0
	for slot in equipped_items.keys():
		if equipped_items[slot] != null:
			var item_id = equipped_items[slot].id
			total += get_equipment_weight(item_id)
	return total

## 获取装备提供的负重加成
func get_equipment_carry_bonus(item_id: String):
	if not EQUIPMENT.has(item_id):
		return 0.0
	return EQUIPMENT[item_id].get("carry_bonus", 0.0)

## 获取当前已装备装备的总负重加成
func get_total_carry_bonus():
	var total = 0.0
	for slot in equipped_items.keys():
		if equipped_items[slot] != null:
			var item_id = equipped_items[slot].id
			total += get_equipment_carry_bonus(item_id)
	return total

## 获取背包类型（用于CarrySystem）
func get_backpack_type():
	# 检查背部装备
	if equipped_items.has("back") && equipped_items.back != null:
		var backpack_id = equipped_items.back.id
		# 返回背包类型ID
		match backpack_id:
			"backpack_cloth":
				return "cloth_bag"
			"backpack_hiking":
				return "hiking_pack"
			"backpack_military":
				return "military_pack"
			"backpack_tactical":
				return "tactical_pack"
	return "none"

