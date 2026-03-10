extends Node
## ItemDatabase - 统一物品数据库
## 管理游戏中所有物品的定义数据
## 从JSON文件加载，支持热重载
## 注意: 作为Autoload单例，不使用class_name

# ========== 信号 ==========
signal items_reloaded()
signal item_added(item_id: String)
signal item_updated(item_id: String)
signal item_removed(item_id: String)

# ========== 物品类型 ==========
enum ItemType {
	WEAPON,      # 武器
	ARMOR,       # 护甲
	ACCESSORY,   # 饰品
	CONSUMABLE,  # 消耗品
	MATERIAL,    # 材料
	AMMO,        # 弹药
	MISC         # 杂项
}

enum ItemRarity {
	COMMON,      # 普通
	UNCOMMON,    # 精良
	RARE,        # 稀有
	EPIC,        # 史诗
	LEGENDARY    # 传说
}

# ========== 数据缓存 ==========
var _items: Dictionary = {}  # item_id -> item_data

# 旧ID到数值ID的别名映射（用于平滑迁移）
const ITEM_ID_ALIASES = {
	# 武器
	"fist": "1001",
	"knife": "1002",
	"baseball_bat": "1003",
	"pistol": "1004",
	"pipe_wrench": "1013",
	"machete": "1014",
	"katana": "1015",
	"chainsaw": "1016",
	"slingshot": "1017",
	"shotgun": "1018",
	"rifle": "1019",
	"assault_rifle": "1020",
	# 弹药/材料/消耗品
	"ammo_pistol": "1009",
	"ammo_shotgun": "1021",
	"ammo_rifle": "1022",
	"stone": "1023",
	"medkit": "1005",
	"first_aid_kit": "1005",
	"bandage": "1006",
	"canned_food": "1007",
	"food_canned": "1007",
	"water_bottle": "1008",
	"scrap_metal": "1010",
	"cloth": "1011",
	"component_electronic": "1012",
	"electronics": "1012",
	"ammo": "1009",
	"weapon": "1002",
	"armor": "2004",
	"food": "1007",
	"water": "1008",
	# 装备
	"helmet_makeshift": "2001",
	"helmet_military": "2002",
	"helmet_advanced": "2003",
	"armor_cloth": "2004",
	"armor_leather": "2005",
	"armor_metal": "2006",
	"armor_tactical": "2007",
	"armor_heavy": "2008",
	"armor_hazmat": "2009",
	"gloves_leather": "2010",
	"gloves_tactical": "2011",
	"gloves_power": "2012",
	"pants_jeans": "2013",
	"pants_tactical": "2014",
	"shoes_sneakers": "2015",
	"boots_combat": "2016",
	"boots_advanced": "2017",
	"backpack_small": "2018",
	"backpack_medium": "2019",
	"backpack_large": "2020",
	"ring_luck": "2021",
	"amulet_health": "2022",
	"watch_survival": "2023",
	"backpack": "2018",
	"hazmat_suit": "2009",
	# 其他物品
	"antiseptic": "1030",
	"antibiotics": "1031",
	"medicine": "1032",
	"painkiller": "1033",
	"snack": "1034",
	"juice": "1035",
	"military_rations": "1036",
	"raw_meat": "1037",
	"herbal_medicine": "1038",
	"stimpack": "1039",
	"rare_medicine": "1040",
	"splint": "1041",
	"spear": "1050",
	"wood": "1100",
	"metal": "1101",
	"nails": "1102",
	"rope": "1103",
	"plastic": "1104",
	"gunpowder": "1105",
	"steel_ingot": "1106",
	"advanced_parts": "1107",
	"rare_materials": "1108",
	"rare_component": "1109",
	"mutant_organ": "1110",
	"rotten_flesh": "1111",
	"metal_sheet": "1112",
	"gear": "1113",
	"wire": "1114",
	"machine_part": "1115",
	"weapon_part": "1116",
	"medical_supplies": "1117",
	"tools": "1118",
	"advanced_tools": "1119",
	"basic_tools": "1120",
	"medical_equipment": "1121",
	"surgical_kit": "1122",
	"syringe": "1123",
	"medical_scissors": "1124",
	"crowbar": "1125",
	"flashlight": "1126",
	"battery": "1127",
	"radio": "1128",
	"flare": "1129",
	"map": "1130",
	"map_fragment": "1131",
	"school_map": "1132",
	"survival_guide": "1133",
	"documents": "1134",
	"personal_items": "1135",
	"stationery": "1136",
	"keys": "1137",
	"key": "1138",
	"bottle": "1139",
	"glass_bottle": "1140",
	"hidden_stash": "1141",
	"hidden_cache": "1142",
	"personal_cache": "1143",
	"tool_kit": "1144",
	"generator": "1145",
	"water_collector": "1146",
	"fuel": "1147",
	"keycard_subway": "1148",
	"weapon_pipe": "1013",
	"lockpick": "1150",
	"screwdriver": "1151",
	"repair_weapon": "1152",
	"repair_armor": "1153",
	"repair_tool": "1154",
	"repair_kit_advanced": "1155",
	"barricade_wood": "1156",
	"grow_box": "1157",
	"dog_fang": "1158",
	"leather": "1159",
	"rare_loot": "1160",
	"valuable_item": "1161",
	"valuable_loot": "1162",
	"test_item": "1163",
	"test": "1164",
	"extra_item": "1165",
	"hammer": "1166",
	"cloth_armor": "2004",
	"leather_jacket": "2005",
	"kevlar_vest": "2007",
	"helmet": "2001"
}

func resolve_item_id(item_id: String) -> String:
	var key = str(item_id)
	if _items.has(key):
		return key
	if ITEM_ID_ALIASES.has(key):
		return ITEM_ID_ALIASES[key]
	return key

# ========== 初始化 ==========
func _ready():
	print("[ItemDatabase] 物品数据库初始化")
	_load_all_items()

# ========== 数据加载 ==========

func _load_all_items():
	_items.clear()
	
	# 从DataManager加载
	var data_manager = get_node_or_null("/root/DataManager")
	if data_manager:
		var items_data: Dictionary = data_manager.get_all_items()
		for item_id in items_data.keys():
			_items[item_id] = _validate_and_fix_item(items_data[item_id])
		print("[ItemDatabase] 已加载 %d 个物品" % _items.size())
	else:
		push_error("[ItemDatabase] DataManager 未找到")

## 验证并修复物品数据（确保所有必需字段存在）
func _validate_and_fix_item(item_data: Dictionary) -> Dictionary:
	var defaults = {
		"id": 0,
		"name": "未命名物品",
		"description": "",
		"type": "misc",
		"subtype": "",
		"rarity": "common",
		"weight": 0.1,
		"value": 0,
		"stackable": true,
		"max_stack": 99,
		"icon_path": "",
		"model_path": "",
		"level_requirement": 0,
		"durability": -1,
		"max_durability": -1,
		"repairable": false,
		"usable": false,
		"equippable": false,
		"slot": "",
		"special_effects": [],
		"attributes_bonus": {}
	}
	
	# 合并默认值
	for key in defaults.keys():
		if not item_data.has(key):
			item_data[key] = defaults[key]
	
	return item_data

# ========== 公共 API ==========

## 获取物品数据
func get_item(item_id: String) -> Dictionary:
	var resolved = resolve_item_id(item_id)
	return _items.get(resolved, {})

## 获取物品名称
func get_item_name(item_id: String) -> String:
	var item = get_item(item_id)
	return item.get("name", "未知物品")

## 获取物品类型
func get_item_type(item_id: String) -> String:
	var item = get_item(item_id)
	return item.get("type", "misc")

## 获取物品重量
func get_item_weight(item_id: String) -> float:
	var item = get_item(item_id)
	return item.get("weight", 0.1)

## 获取物品价值
func get_item_value(item_id: String) -> int:
	var item = get_item(item_id)
	return item.get("value", 0)

## 检查物品是否存在
func has_item(item_id: String) -> bool:
	var resolved = resolve_item_id(item_id)
	return _items.has(resolved)

## 获取所有物品ID
func get_all_item_ids() -> Array:
	return _items.keys()

## 获取特定类型的所有物品
func get_items_by_type(item_type: String) -> Array:
	var result = []
	for item_id in _items.keys():
		if _items[item_id].get("type", "") == item_type:
			result.append(item_id)
	return result

## 获取可装备的物品
func get_equippable_items() -> Array:
	var result = []
	for item_id in _items.keys():
		if _items[item_id].get("equippable", false):
			result.append(item_id)
	return result

## 搜索物品
func search_items(query: String) -> Array:
	var result = []
	var lower_query = query.to_lower()
	
	for item_id in _items.keys():
		var item = _items[item_id]
		if item_id.to_lower().contains(lower_query) or \
		   item.get("name", "").to_lower().contains(lower_query) or \
		   item.get("description", "").to_lower().contains(lower_query):
			result.append(item_id)
	
	return result

# ========== 物品属性查询 ==========

## 检查是否是武器
func is_weapon(item_id: String) -> bool:
	return get_item_type(item_id) == "weapon"

## 检查是否是护甲
func is_armor(item_id: String) -> bool:
	return get_item_type(item_id) == "armor"

## 检查是否是消耗品
func is_consumable(item_id: String) -> bool:
	return get_item_type(item_id) == "consumable"

## 检查是否可堆叠
func is_stackable(item_id: String) -> bool:
	var item = get_item(item_id)
	return item.get("stackable", true)

## 获取最大堆叠数量
func get_max_stack(item_id: String) -> int:
	var item = get_item(item_id)
	return item.get("max_stack", 99)

## 检查是否可装备
func is_equippable(item_id: String) -> bool:
	var item = get_item(item_id)
	return item.get("equippable", false)

## 获取装备槽位
func get_equip_slot(item_id: String) -> String:
	var item = get_item(item_id)
	return item.get("slot", "")

## 获取装备所需等级
func get_level_requirement(item_id: String) -> int:
	var item = get_item(item_id)
	return item.get("level_requirement", 0)

# ========== 武器特定接口 ==========

## 获取武器数据
func get_weapon_data(item_id: String) -> Dictionary:
	if not is_weapon(item_id):
		return {}
	var item = get_item(item_id)
	return item.get("weapon_data", {})

## 获取武器伤害
func get_weapon_damage(item_id: String) -> int:
	var weapon_data = get_weapon_data(item_id)
	return weapon_data.get("damage", 0)

## 获取武器攻击速度
func get_weapon_attack_speed(item_id: String) -> float:
	var weapon_data = get_weapon_data(item_id)
	return weapon_data.get("attack_speed", 1.0)

# ========== 护甲特定接口 ==========

## 获取护甲数据
func get_armor_data(item_id: String) -> Dictionary:
	if not is_armor(item_id):
		return {}
	var item = get_item(item_id)
	return item.get("armor_data", {})

## 获取护甲值
func get_armor_defense(item_id: String) -> int:
	var armor_data = get_armor_data(item_id)
	return armor_data.get("defense", 0)

# ========== 消耗品特定接口 ==========

## 获取消耗品效果
func get_consumable_effects(item_id: String) -> Dictionary:
	if not is_consumable(item_id):
		return {}
	var item = get_item(item_id)
	return item.get("consumable_data", {}).get("effects", {})

## 获取消耗品使用次数
func get_consumable_uses(item_id: String) -> int:
	if not is_consumable(item_id):
		return 0
	var item = get_item(item_id)
	return item.get("consumable_data", {}).get("uses", 1)

# ========== 耐久度接口 ==========

## 检查物品是否有耐久度
func has_durability(item_id: String) -> bool:
	var item = get_item(item_id)
	var max_dur = item.get("max_durability", -1)
	return max_dur > 0

## 获取最大耐久度
func get_max_durability(item_id: String) -> int:
	var item = get_item(item_id)
	return item.get("max_durability", -1)

## 获取修理材料
func get_repair_materials(item_id: String) -> Array:
	var item = get_item(item_id)
	return item.get("repair_materials", [])

# ========== 数据统计 ==========

func get_item_count() -> int:
	return _items.size()

func get_item_count_by_type(item_type: String) -> int:
	return get_items_by_type(item_type).size()

func get_item_statistics() -> Dictionary:
	var stats = {
		"total": _items.size(),
		"weapon": get_item_count_by_type("weapon"),
		"armor": get_item_count_by_type("armor"),
		"accessory": get_item_count_by_type("accessory"),
		"consumable": get_item_count_by_type("consumable"),
		"material": get_item_count_by_type("material"),
		"ammo": get_item_count_by_type("ammo"),
		"misc": get_item_count_by_type("misc")
	}
	return stats

# ========== 热重载 ==========

func reload_items():
	_load_all_items()
	items_reloaded.emit()
	print("[ItemDatabase] 物品数据已重载")

# ========== 调试 ==========

func debug_print_all_items():
	print("=== ItemDatabase 内容 ===")
	print("总计: %d 个物品" % _items.size())
	
	var type_count = {}
	for item_id in _items.keys():
		var item_type = _items[item_id].get("type", "unknown")
		type_count[item_type] = type_count.get(item_type, 0) + 1
	
	print("按类型分布:")
	for item_type in type_count.keys():
		print("  %s: %d" % [item_type, type_count[item_type]])
