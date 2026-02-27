extends Node
## DataManager - 数据管理器
## 负责加载和管理所有JSON数据文件
## 将数据与逻辑分离，便于维护和修改

# ========== 数据缓存 ==========
var _data_cache: Dictionary = {}
var _loaded_categories: Dictionary = {}

# ========== 数据文件路径配置 ==========
const DATA_PATHS = {
	"clues": "res://data/json/clues.json",
	"story_chapters": "res://data/json/story_chapters.json",
	"recipes": "res://data/json/recipes.json",
	"enemies": "res://data/enemies.json",
	"ability_effects": "res://data/json/ability_effects.json",
	"effects": "res://data/json/effects.json",
	"quests": "res://data/json/quests.json",
	"equipment": "res://data/json/equipment.json",
	"items": "res://data/json/items.json",
	"map_locations": "res://data/json/map_locations.json",
	"limb_data": "res://data/json/limb_data.json",
	"encounters": "res://data/json/encounters.json",
	"scavenge_locations": "res://data/json/scavenge_locations.json",
	"weapons": "res://data/json/weapons.json",
	"npcs": "res://data/json/npcs.json"
}

# ========== 初始化 ==========
func _ready():
	print("[DataManager] 数据管理器初始化")
	_load_all_data()

## 加载所有数据文件
func _load_all_data() -> void:
	for category in DATA_PATHS.keys():
		_load_category(category)
	print("[DataManager] 已加载 %d 个数据类别" % _loaded_categories.size())

## 加载单个数据类别
func _load_category(category: String) -> void:
	var path = DATA_PATHS.get(category, "")
	if path.is_empty():
		push_error("[DataManager] 未知的数据类别: %s" % category)
		return
	
	var data = _load_json_file(path)
	if data != null:
		_data_cache[category] = data
		_loaded_categories[category] = true
		print("[DataManager] 已加载 %s (%d 条数据)" % [category, data.size() if data is Dictionary else 0])

## 加载JSON文件
func _load_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("[DataManager] 数据文件不存在: %s" % path)
		return null
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[DataManager] 无法打开文件: %s" % path)
		return null
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("[DataManager] JSON解析错误 %s: %s" % [path, json.get_error_message()])
		return null
	
	return json.data

# ========== 公共API ==========

## 获取整个数据类别
func get_data(category: String) -> Dictionary:
	return _data_cache.get(category, {})

## 获取单个数据项
func get_item(category: String, id: String) -> Dictionary:
	var data = _data_cache.get(category, {})
	return data.get(id, {})

## 检查数据项是否存在
func has_item(category: String, id: String) -> bool:
	var data = _data_cache.get(category, {})
	return data.has(id)

## 获取数据项数量
func get_count(category: String) -> int:
	var data = _data_cache.get(category, {})
	return data.size()

## 获取所有ID列表
func get_all_ids(category: String) -> Array:
	var data = _data_cache.get(category, {})
	return data.keys()

## 重新加载数据（用于热更新）
func reload_category(category: String) -> void:
	if DATA_PATHS.has(category):
		_load_category(category)
		print("[DataManager] 已重新加载 %s" % category)

## 重新加载所有数据
func reload_all() -> void:
	_data_cache.clear()
	_loaded_categories.clear()
	_load_all_data()
	print("[DataManager] 所有数据已重新加载")

# ========== 便捷方法 ==========

## 线索数据
func get_clue(clue_id: String) -> Dictionary:
	return get_item("clues", clue_id)

func get_all_clues() -> Dictionary:
	return get_data("clues")

## 故事章节数据
func get_chapter(chapter_id: String) -> Dictionary:
	return get_item("story_chapters", chapter_id)

func get_all_chapters() -> Dictionary:
	return get_data("story_chapters")

## 制作配方数据
func get_recipe(recipe_id: String) -> Dictionary:
	return get_item("recipes", recipe_id)

func get_all_recipes() -> Dictionary:
	return get_data("recipes")

## 敌人数据
func get_enemy(enemy_id: String) -> Dictionary:
	return get_item("enemies", enemy_id)

func get_all_enemies() -> Dictionary:
	return get_data("enemies")

## 任务数据
func get_quest(quest_id: String) -> Dictionary:
	return get_item("quests", quest_id)

func get_all_quests() -> Dictionary:
	return get_data("quests")

## 装备数据
func get_equipment(equipment_id: String) -> Dictionary:
	return get_item("equipment", equipment_id)

func get_all_equipment() -> Dictionary:
	return get_data("equipment")

## 物品数据
func get_item_data(item_id: String) -> Dictionary:
	return get_item("items", item_id)

func get_all_items() -> Dictionary:
	return get_data("items")

## 武器数据
func get_weapon(weapon_id: String) -> Dictionary:
	return get_item("weapons", weapon_id)

func get_all_weapons() -> Dictionary:
	return get_data("weapons")

## 地图位置数据
func get_location_data(location_id: String) -> Dictionary:
	return get_item("map_locations", location_id)

func get_all_locations() -> Dictionary:
	return get_data("map_locations")

## 部位伤害数据
func get_limb_data(limb_id: String) -> Dictionary:
	return get_item("limb_data", limb_id)

func get_all_limb_data() -> Dictionary:
	return get_data("limb_data")

## 遭遇数据
func get_encounter(encounter_id: String) -> Dictionary:
	return get_item("encounters", encounter_id)

func get_all_encounters() -> Dictionary:
	return get_data("encounters")

## 搜刮地点数据
func get_scavenge_location(location_id: String) -> Dictionary:
	return get_item("scavenge_locations", location_id)

func get_all_scavenge_locations() -> Dictionary:
	return get_data("scavenge_locations")

## NPC数据
func get_npc(npc_id: String) -> Dictionary:
	return get_item("npcs", npc_id)

func get_all_npcs() -> Dictionary:
	return get_data("npcs")

## 效果数据
func get_effect(effect_id: String) -> Dictionary:
	return get_item("effects", effect_id)

func get_all_effects() -> Dictionary:
	return get_data("effects")

# ========== 数据验证 ==========

## 验证数据完整性
func validate_data(category: String) -> bool:
	var data = get_data(category)
	if data.is_empty():
		push_warning("[DataManager] %s 数据为空或未加载" % category)
		return false
	return true

## 验证所有数据
func validate_all_data() -> Dictionary:
	var results = {}
	for category in DATA_PATHS.keys():
		results[category] = validate_data(category)
	return results
