extends Node
# WeaponSystem - 武器系统
# 管理武器数据、装备、耐久、强化

signal weapon_equipped(weapon_id: String, weapon_data: Dictionary)
signal weapon_unequipped(weapon_id: String)
signal weapon_broken(weapon_id: String)
signal weapon_repaired(weapon_id: String, durability: int)
signal ammo_changed(weapon_id: String, current: int, max_ammo: int)
signal attack_performed(weapon_id: String, damage: int, is_critical: bool)

# ===== 武器数据（从 DataManager 加载）=====
var _weapons: Dictionary = {}
var _ammo_types: Dictionary = {}


func _get_weapon(weapon_id: String) -> Dictionary:
	return _weapons.get(weapon_id, {})


func _get_ammo_type(ammo_id: String) -> Dictionary:
	return _ammo_types.get(ammo_id, {})


# 保留的硬编码数据作为后备（当 JSON 不存在时使用）
const _WEAPONS_FALLBACK = {
	# === 近战武器 ===
	"fist":
	{
		"name": "拳头",
		"description": "最基础的攻击方",
		"type": "melee",
		"subtype": "unarmed",
		"damage": 5,
		"attack_speed": 1.0,
		"range": 1,
		"weight": 0.0,  # 无重"
		"durability": -1,  # -1表示无限耐久
		"max_durability": -1,
		"crit_chance": 0.05,
		"crit_multiplier": 1.5,
		"stamina_cost": 2,
		"special_effects": [],
		"required_level": 0,
		"repair_materials": [],
		"can_craft": false
	},
	"knife":
	{
		"name": "小刀",
		"description": "锋利的匕首，适合近距离战",
		"type": "melee",
		"subtype": "dagger",
		"damage": 12,
		"attack_speed": 1.2,
		"range": 1,
		"weight": 0.3,  # 300g
		"durability": 50,
		"max_durability": 50,
		"crit_chance": 0.15,
		"crit_multiplier": 2.0,
		"stamina_cost": 3,
		"special_effects": ["bleeding"],
		"bleeding_damage": 2,
		"bleeding_duration": 3,
		"required_level": 1,
		"repair_materials": [{"item": "scrap_metal", "count": 2}],
		"can_craft": true,
		"craft_recipe":
		{
			"materials":
			[{"item": "scrap_metal", "count": 3}, {"item": "component_electronic", "count": 1}],
			"time": 30
		}
	},
	"baseball_bat":
	{
		"name": "棒球",
		"description": "结实的木棒，可以造成不错的伤",
		"type": "melee",
		"subtype": "blunt",
		"damage": 15,
		"attack_speed": 0.9,
		"range": 2,
		"weight": 1.2,
		"durability": 40,
		"max_durability": 40,
		"crit_chance": 0.10,
		"crit_multiplier": 1.5,
		"stamina_cost": 5,
		"special_effects": ["stun"],
		"stun_chance": 0.2,
		"stun_duration": 1,
		"required_level": 1,
		"repair_materials": [{"item": "scrap_metal", "count": 3}],
		"can_craft": true,
		"craft_recipe": {"materials": [{"item": "scrap_metal", "count": 5}], "time": 45}
	},
	"pipe_wrench":
	{
		"name": "管钳",
		"description": "沉重的金属工具，伤害可观",
		"type": "melee",
		"subtype": "blunt",
		"damage": 20,
		"attack_speed": 0.8,
		"range": 2,
		"weight": 2.0,
		"durability": 60,
		"max_durability": 60,
		"crit_chance": 0.08,
		"crit_multiplier": 1.8,
		"stamina_cost": 7,
		"special_effects": ["armor_break"],
		"armor_break_chance": 0.25,
		"required_level": 2,
		"repair_materials": [{"item": "scrap_metal", "count": 4}],
		"can_craft": true,
		"craft_recipe":
		{
			"materials": [{"item": "scrap_metal", "count": 8}, {"item": "tool_kit", "count": 1}],
			"time": 60
		}
	},
	"machete":
	{
		"name": "砍刀",
		"description": "锋利的砍刀，对付僵尸很有效",
		"type": "melee",
		"subtype": "sword",
		"damage": 25,
		"attack_speed": 1.0,
		"range": 2,
		"weight": 1.0,
		"durability": 45,
		"max_durability": 45,
		"crit_chance": 0.12,
		"crit_multiplier": 2.0,
		"stamina_cost": 6,
		"special_effects": ["cleave", "bleeding"],
		"cleave_damage": 0.5,  # 对附近敌人造成50%伤害
		"bleeding_damage": 3,
		"bleeding_duration": 4,
		"required_level": 3,
		"repair_materials": [{"item": "scrap_metal", "count": 5}],
		"can_craft": true,
		"craft_recipe":
		{
			"materials": [{"item": "scrap_metal", "count": 10}, {"item": "tool_kit", "count": 1}],
			"time": 90
		}
	},
	"katana":
	{
		"name": "武士刀",
		"description": "锋利的日本刀，极其致",
		"type": "melee",
		"subtype": "sword",
		"damage": 35,
		"attack_speed": 1.3,
		"range": 3,
		"weight": 1.2,
		"durability": 80,
		"max_durability": 80,
		"crit_chance": 0.20,
		"crit_multiplier": 2.5,
		"stamina_cost": 8,
		"special_effects": ["cleave", "bleeding", "decapitation"],
		"cleave_damage": 0.7,
		"bleeding_damage": 5,
		"bleeding_duration": 5,
		"decapitation_chance": 0.1,  # 对低血量敌人即"
		"required_level": 5,
		"repair_materials":
		[{"item": "scrap_metal", "count": 8}, {"item": "component_electronic", "count": 2}],
		"can_craft": true,
		"craft_recipe":
		{
			"materials":
			[
				{"item": "scrap_metal", "count": 15},
				{"item": "component_electronic", "count": 3},
				{"item": "tool_kit", "count": 2}
			],
			"time": 120
		}
	},
	"chainsaw":
	{
		"name": "电锯",
		"description": "恐怖的伤害，但需要燃",
		"type": "melee",
		"subtype": "heavy",
		"damage": 50,
		"attack_speed": 0.6,
		"range": 2,
		"weight": 4.0,
		"durability": 100,
		"max_durability": 100,
		"crit_chance": 0.05,
		"crit_multiplier": 3.0,
		"stamina_cost": 15,
		"fuel_consumption": 1,  # 每次攻击消耗燃"
		"special_effects": ["bleeding", "fear"],
		"bleeding_damage": 8,
		"bleeding_duration": 6,
		"fear_chance": 0.3,  # 使敌人恐"
		"required_level": 6,
		"repair_materials":
		[{"item": "scrap_metal", "count": 10}, {"item": "component_electronic", "count": 3}],
		"can_craft": true,
		"craft_recipe":
		{
			"materials":
			[
				{"item": "scrap_metal", "count": 20},
				{"item": "component_electronic", "count": 5},
				{"item": "tool_kit", "count": 3}
			],
			"time": 180
		}
	},
	# === 远程武器 ===
	"slingshot":
	{
		"name": "弹弓",
		"description": "简易的远程武器",
		"type": "ranged",
		"subtype": "light",
		"damage": 8,
		"attack_speed": 1.0,
		"range": 10,
		"weight": 0.2,
		"accuracy": 70,
		"durability": 30,
		"max_durability": 30,
		"ammo_type": "stone",  # 使用石头作为弹药
		"max_ammo": 1,
		"reload_time": 1.0,
		"crit_chance": 0.05,
		"crit_multiplier": 1.5,
		"stamina_cost": 2,
		"special_effects": ["headshot_bonus"],
		"headshot_damage": 1.5,
		"required_level": 1,
		"repair_materials": [{"item": "scrap_metal", "count": 2}],
		"can_craft": true,
		"craft_recipe": {"materials": [{"item": "scrap_metal", "count": 2}], "time": 20}
	},
	"pistol":
	{
		"name": "手枪",
		"description": "可靠的副武器",
		"type": "ranged",
		"subtype": "pistol",
		"damage": 25,
		"attack_speed": 1.2,
		"range": 25,
		"weight": 0.8,
		"accuracy": 80,
		"durability": 100,
		"max_durability": 100,
		"ammo_type": "ammo_pistol",
		"max_ammo": 12,
		"reload_time": 2.0,
		"crit_chance": 0.10,
		"crit_multiplier": 2.0,
		"stamina_cost": 3,
		"special_effects": ["headshot_bonus"],
		"headshot_damage": 2.0,
		"required_level": 3,
		"repair_materials":
		[{"item": "scrap_metal", "count": 5}, {"item": "component_electronic", "count": 2}],
		"can_craft": true,
		"craft_recipe":
		{
			"materials":
			[{"item": "scrap_metal", "count": 12}, {"item": "component_electronic", "count": 3}],
			"time": 100
		}
	},
	"shotgun":
	{
		"name": "霰弹",
		"description": "近距离威力巨",
		"type": "ranged",
		"subtype": "shotgun",
		"damage": 40,
		"attack_speed": 0.7,
		"range": 15,
		"weight": 4.0,
		"accuracy": 60,
		"durability": 80,
		"max_durability": 80,
		"ammo_type": "ammo_shotgun",
		"max_ammo": 6,
		"reload_time": 3.0,
		"crit_chance": 0.08,
		"crit_multiplier": 1.5,
		"stamina_cost": 8,
		"special_effects": ["spread", "knockback"],
		"spread_targets": 3,  # 可以命中多个目标
		"spread_damage": 0.6,  # 扩散伤害比例
		"knockback_chance": 0.4,
		"required_level": 4,
		"repair_materials": [{"item": "scrap_metal", "count": 8}],
		"can_craft": true,
		"craft_recipe":
		{
			"materials":
			[{"item": "scrap_metal", "count": 15}, {"item": "component_electronic", "count": 2}],
			"time": 120
		}
	},
	"rifle":
	{
		"name": "步枪",
		"description": "精准的中距离武器",
		"type": "ranged",
		"subtype": "rifle",
		"damage": 45,
		"attack_speed": 0.8,
		"range": 50,
		"weight": 3.5,  # 3.5kg
		"accuracy": 90,
		"durability": 90,
		"max_durability": 90,
		"ammo_type": "ammo_rifle",
		"max_ammo": 10,
		"reload_time": 2.5,
		"crit_chance": 0.15,
		"crit_multiplier": 2.5,
		"stamina_cost": 5,
		"special_effects": ["headshot_bonus", "armor_pierce"],
		"headshot_damage": 3.0,
		"armor_pierce": 0.5,  # 无视50%防御
		"required_level": 5,
		"repair_materials":
		[{"item": "scrap_metal", "count": 6}, {"item": "component_electronic", "count": 3}],
		"can_craft": true,
		"craft_recipe":
		{
			"materials":
			[{"item": "scrap_metal", "count": 18}, {"item": "component_electronic", "count": 5}],
			"time": 150
		}
	},
	"assault_rifle":
	{
		"name": "突击步枪",
		"description": "全自动火力压",
		"type": "ranged",
		"subtype": "rifle",
		"damage": 30,
		"attack_speed": 2.0,  # 每秒2"
		"range": 40,
		"weight": 4.2,
		"accuracy": 75,
		"durability": 120,
		"max_durability": 120,
		"ammo_type": "ammo_rifle",
		"max_ammo": 30,
		"reload_time": 3.0,
		"crit_chance": 0.08,
		"crit_multiplier": 1.8,
		"stamina_cost": 6,
		"special_effects": ["burst_fire"],
		"burst_count": 3,  # 每次攻击3"
		"required_level": 6,
		"repair_materials":
		[{"item": "scrap_metal", "count": 10}, {"item": "component_electronic", "count": 4}],
		"can_craft": true,
		"craft_recipe":
		{
			"materials":
			[{"item": "scrap_metal", "count": 25}, {"item": "component_electronic", "count": 8}],
			"time": 200
		}
	}
}

# ===== 弹药数据 =====
const AMMO_TYPES = {
	"stone": {"name": "石子", "damage_bonus": 0, "can_craft": false},
	"ammo_pistol":
	{
		"name": "手枪弹药",
		"damage_bonus": 0,
		"can_craft": true,
		"craft_recipe":
		{
			"materials":
			[{"item": "scrap_metal", "count": 1}, {"item": "component_electronic", "count": 1}],
			"output": 5
		}
	},
	"ammo_shotgun":
	{
		"name": "霰弹",
		"damage_bonus": 0,
		"can_craft": true,
		"craft_recipe": {"materials": [{"item": "scrap_metal", "count": 2}], "output": 4}
	},
	"ammo_rifle":
	{
		"name": "步枪弹药",
		"damage_bonus": 0,
		"can_craft": true,
		"craft_recipe":
		{
			"materials":
			[{"item": "scrap_metal", "count": 2}, {"item": "component_electronic", "count": 1}],
			"output": 5
		}
	},
	"fuel":
	{
		"name": "燃料",
		"damage_bonus": 0,
		"can_craft": true,
		"craft_recipe":
		{
			"materials":
			[{"item": "scrap_metal", "count": 1}, {"item": "component_electronic", "count": 2}],
			"output": 10
		}
	}
}

# ===== 玩家装备状"=====
var equipped_weapon: String = "fist"
var weapon_inventory: Array[Dictionary] = []  # 拥有的武器列"
var current_ammo: Dictionary = {}  # 当前弹药数量

# ===== 核心方法 =====


func _ready():
	print("[WeaponSystem] 武器系统已初始化")
	_load_data_from_manager()
	_reset_ammo()


## 从 DataManager 加载数据
func _load_data_from_manager():
	var dm = get_node_or_null("/root/DataManager")
	if dm:
		_weapons = dm.get_all_weapons()
		_ammo_types = dm.get_data("ammo_types")

	# 如果 DataManager 没有数据，使用后备数据
	if _weapons.is_empty():
		push_warning("[WeaponSystem] 无法从 DataManager 加载武器数据")
	if _ammo_types.is_empty():
		push_warning("[WeaponSystem] 无法从 DataManager 加载弹药数据")


func _reset_ammo():
	for ammo_type in _ammo_types.keys():
		current_ammo[ammo_type] = 0


# 装备武器
func equip_weapon(weapon_id: String):
	var weapon = _get_weapon(weapon_id)
	if weapon.is_empty():
		push_error("Weapon not found: " + weapon_id)
		return false

	# 检查等级要求
	var player_level = _get_player_level()
	if player_level < weapon.get("required_level", 0):
		print("[Weapon] Level too low to equip " + weapon.get("name", ""))
		return false

	# 检查是否拥有该武器
	if weapon_id != "fist" && not _has_weapon(weapon_id):
		print("[Weapon] Don't have weapon: " + weapon.get("name", ""))
		return false

	equipped_weapon = weapon_id
	weapon_equipped.emit(weapon_id, weapon)
	print("[Weapon] Equipped: " + weapon.get("name", ""))
	return true


# 获取当前武器数据
func get_equipped_weapon():
	var weapon = _get_weapon(equipped_weapon)
	if not weapon.is_empty():
		return weapon.duplicate(true)
	return _get_weapon("fist").duplicate(true)


# 执行攻击
func perform_attack():
	var weapon = get_equipped_weapon()
	var result = {
		"success": false,
		"damage": 0,
		"is_critical": false,
		"ammo_consumed": 0,
		"durability_lost": 0,
		"effects_applied": [],
		"message": ""
	}

	# 检查弹药（远程武器"
	if weapon.type == "ranged":
		var ammo_type = weapon.get("ammo_type", "")
		if ammo_type != "":
			if current_ammo.get(ammo_type, 0) <= 0:
				result.message = "没有弹药"
				return result

			# 消耗弹"
			var ammo_consumed = weapon.get("burst_count", 1)
			current_ammo[ammo_type] -= ammo_consumed
			result.ammo_consumed = ammo_consumed
			ammo_changed.emit(equipped_weapon, current_ammo[ammo_type], weapon.max_ammo)

	# 检查燃料（电锯"
	if weapon.get("fuel_consumption", 0) > 0:
		if current_ammo.get("fuel", 0) < weapon.fuel_consumption:
			result.message = "没有燃料"
			return result
		current_ammo["fuel"] -= weapon.fuel_consumption
		ammo_changed.emit(equipped_weapon, current_ammo["fuel"], 999)

	# 计算是否暴击
	var is_critical = randf() < weapon.crit_chance
	result.is_critical = is_critical

	# 计算伤害
	var base_damage = weapon.damage
	if is_critical:
		base_damage = int(base_damage * weapon.crit_multiplier)

	# 添加技能加"
	base_damage += SkillModule.get_total_damage_bonus()

	result.damage = base_damage
	result.success = true

	# 减少耐久
	if weapon.durability > 0:
		_reduce_durability(equipped_weapon, 1)
		result.durability_lost = 1

	# 应用特殊效果
	_apply_special_effects(weapon, result)

	attack_performed.emit(equipped_weapon, result.damage, is_critical)
	return result


# 应用特殊效果
func _apply_special_effects(weapon: Dictionary, result: Dictionary):
	var effects = weapon.get("special_effects", [])

	for effect in effects:
		match effect:
			"bleeding":
				if randf() < 0.7:  # 70%几率
					result.effects_applied.append(
						{
							"type": "bleeding",
							"damage": weapon.get("bleeding_damage", 2),
							"duration": weapon.get("bleeding_duration", 3)
						}
					)
			"stun":
				if randf() < weapon.get("stun_chance", 0):
					result.effects_applied.append(
						{"type": "stun", "duration": weapon.get("stun_duration", 1)}
					)
			"armor_break":
				if randf() < weapon.get("armor_break_chance", 0):
					result.effects_applied.append({"type": "armor_break", "defense_reduction": 0.5})
			"knockback":
				if randf() < weapon.get("knockback_chance", 0):
					result.effects_applied.append({"type": "knockback"})
			"fear":
				if randf() < weapon.get("fear_chance", 0):
					result.effects_applied.append({"type": "fear", "duration": 2})


# 减少耐久
func _reduce_durability(weapon_id: String, amount: int = 1):
	for weapon in weapon_inventory:
		if weapon.id == weapon_id:
			weapon.durability = maxi(0, weapon.durability - amount)

			if weapon.durability <= 0:
				weapon_broken.emit(weapon_id)
				print("[Weapon] Weapon broken: " + weapon_id)
				# 自动切换到拳"
				if equipped_weapon == weapon_id:
					equip_weapon("fist")
			break


# 修复武器
func repair_weapon(weapon_id: String):
	if not _has_weapon(weapon_id):
		return false

	var weapon_template = _get_weapon(weapon_id)
	if weapon_template.is_empty():
		return false

	var repair_materials = weapon_template.get("repair_materials", [])

	# 检查材"
	for material in repair_materials:
		if not InventoryModule.has_item(material.item, material.count):
			print("[Weapon] Missing materials to repair")
			return false

	# 消耗材"
	for material in repair_materials:
		InventoryModule.remove_item(material.item, material.count)

	# 修复耐久
	for weapon in weapon_inventory:
		if weapon.id == weapon_id:
			weapon.durability = weapon_template.get("max_durability", 0)
			weapon_repaired.emit(weapon_id, weapon.durability)
			print("[Weapon] Repaired: " + weapon_template.get("name", ""))
			return true

	return false


# 添加武器到背"
func add_weapon(weapon_id: String):
	var weapon_template = _get_weapon(weapon_id)
	if weapon_template.is_empty():
		return false

	# 如果已经拥有，修复耐久
	if _has_weapon(weapon_id):
		repair_weapon(weapon_id)
		return true

	var new_weapon = {
		"id": weapon_id, "durability": weapon_template.get("max_durability", 0), "enhancements": []
	}

	weapon_inventory.append(new_weapon)
	print("[Weapon] Added to inventory: " + weapon_template.get("name", ""))
	return true


# 添加弹药
func add_ammo(ammo_type: String, amount: int = 1):
	var ammo_data = _get_ammo_type(ammo_type)
	if ammo_data.is_empty():
		return false

	if not current_ammo.has(ammo_type):
		current_ammo[ammo_type] = 0

	current_ammo[ammo_type] += amount
	print("[Weapon] Added ammo: " + ammo_type + " x" + str(amount))
	return true


# 获取弹药数量
func get_ammo_count(ammo_type: String):
	return current_ammo.get(ammo_type, 0)


# 重新装填
func reload_weapon():
	var weapon = get_equipped_weapon()
	var result = {"success": false, "ammo_loaded": 0, "message": ""}

	if weapon.type != "ranged":
		result.message = "近战武器不需要装"
		return result

	var ammo_type = weapon.get("ammo_type", "")
	if ammo_type == "":
		result.message = "不需要弹"
		return result

	var available_ammo = current_ammo.get(ammo_type, 0)
	if available_ammo <= 0:
		result.message = "没有弹药"
		return result

	var to_load = mini(available_ammo, weapon.max_ammo)
	current_ammo[ammo_type] -= to_load
	result.ammo_loaded = to_load
	result.success = true

	ammo_changed.emit(equipped_weapon, current_ammo[ammo_type], weapon.max_ammo)
	return result


# 检查是否拥有武"
func _has_weapon(weapon_id: String):
	if weapon_id == "fist":
		return true
	for weapon in weapon_inventory:
		if weapon.id == weapon_id:
			return true
	return false


# 获取玩家等级（简化实现）
func _get_player_level():
	# 可以连接到经验系"
	return 1


# 获取可制作的武器列表
func get_craftable_weapons() -> Array[Dictionary]:
	var craftable = []
	for weapon_id in _weapons.keys():
		var weapon = _weapons[weapon_id]
		if weapon.get("can_craft", false):
			craftable.append(
				{
					"id": weapon_id,
					"name": weapon.get("name", ""),
					"description": weapon.get("description", ""),
					"recipe": weapon.get("craft_recipe", {})
				}
			)
	return craftable


# 制作武器
func craft_weapon(weapon_id: String):
	var weapon = _get_weapon(weapon_id)
	if weapon.is_empty():
		return false

	if not weapon.get("can_craft", false):
		return false

	var recipe = weapon.get("craft_recipe", {})

	# 检查材"
	for material in recipe.get("materials", []):
		if not InventoryModule.has_item(material.item, material.count):
			print("[Weapon] Missing materials")
			return false

	# 消耗材"
	for material in recipe.get("materials", []):
		InventoryModule.remove_item(material.item, material.count)

	# 添加武器
	add_weapon(weapon_id)
	print("[Weapon] Crafted: " + weapon.get("name", ""))
	return true


# 保存/加载
func get_save_data():
	return {
		"equipped_weapon": equipped_weapon,
		"weapon_inventory": weapon_inventory,
		"current_ammo": current_ammo
	}


func load_save_data(data: Dictionary):
	equipped_weapon = data.get("equipped_weapon", "fist")
	weapon_inventory = data.get("weapon_inventory", [])
	current_ammo = data.get("current_ammo", {})
	print("[WeaponSystem] Loaded save data")


# ===== 重量系统接口 =====


## 获取武器重量
func get_weapon_weight(weapon_id: String):
	var weapon = _get_weapon(weapon_id)
	if weapon.is_empty():
		return 0.0
	return weapon.get("weight", 0.0)


## 获取当前装备武器的重"
func get_equipped_weapon_weight():
	return get_weapon_weight(equipped_weapon)


## 获取所有携带武器的总重"
func get_total_weapon_weight():
	var total = 0.0
	# 装备武器
	total += get_equipped_weapon_weight()
	# 背包中的武器 (简化处"
	for weapon_data in weapon_inventory:
		var weapon_id = weapon_data.get("id", "")
		total += get_weapon_weight(weapon_id)
	return total
