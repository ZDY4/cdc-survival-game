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
	return _items.get(item_id, {})

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
	return _items.has(item_id)

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
