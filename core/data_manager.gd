extends Node
## DataManager - 数据管理器
## 负责加载和管理所有JSON数据文件
## 将数据与逻辑分离，便于维护和修改

# ========== 数据缓存 ==========
var _data_cache: Dictionary = {}
var _loaded_categories: Dictionary = {}

# ========== 数据文件路径配置 ==========
const ITEM_DATA_DIR := "res://data/items"

const DATA_PATHS = {
	"clues": "res://data/json/clues.json",
	"story_chapters": "res://data/json/story_chapters.json",
	"recipes": "res://data/json/recipes.json",
	"enemies": "res://data/json/enemies.json",
	"effects": "res://data/json/effects",
	"quests": "res://data/json/quests.json",
	"items": ITEM_DATA_DIR,
	"map_locations": "res://data/json/map_locations.json",
	"limb_data": "res://data/json/limb_data.json",
	"encounters": "res://data/json/encounters.json",
	"scavenge_locations": "res://data/json/scavenge_locations.json",
	"weapons": "res://data/json/weapons.json",
	"npcs": "res://data/json/npcs.json",
	"skills": "res://data/skills",
	"skill_trees": "res://data/skill_trees",
	"balance": "res://data/json/balance.json",
	"map_data": "res://data/json/map_data.json",
	"structures": "res://data/json/structures.json",
	"tools": "res://data/json/tools.json",
	"loot_tables": "res://data/json/loot_tables.json",
	"weather": "res://data/json/weather.json"
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
	if category == "items":
		var directory_items: Dictionary = _load_items_from_directory(ITEM_DATA_DIR)
		_data_cache[category] = directory_items
		_loaded_categories[category] = true
		print("[DataManager] 已加载 %s (%d 条数据)" % [category, directory_items.size()])
		return

	var path = DATA_PATHS.get(category, "")
	if path.is_empty():
		push_error("[DataManager] 未知的数据类别: %s" % category)
		return

	var data = _load_json_directory(path) if DirAccess.open(path) != null else _load_json_file(path)
	if data != null:
		_data_cache[category] = data
		_loaded_categories[category] = true
		print(
			"[DataManager] 已加载 %s (%d 条数据)" % [category, data.size() if data is Dictionary else 0]
		)

func _load_items_from_directory(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var absolute_dir_path := ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(absolute_dir_path):
		return result

	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[DataManager] 无法打开物品目录: %s" % dir_path)
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if dir.current_is_dir() or not file_name.ends_with(".json"):
			file_name = dir.get_next()
			continue

		var file_path := "%s/%s" % [dir_path, file_name]
		var item_data: Variant = _load_json_file(file_path)
		if not (item_data is Dictionary):
			push_warning("[DataManager] 跳过无效物品文件: %s" % file_path)
			file_name = dir.get_next()
			continue

		var item_id := str(item_data.get("id", ""))
		if item_id.is_empty():
			push_warning("[DataManager] 物品文件缺少 id 字段: %s" % file_path)
			file_name = dir.get_next()
			continue

		result[item_id] = item_data
		file_name = dir.get_next()

	dir.list_dir_end()
	return result


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


## 加载目录下所有JSON文件（文件名作为ID）
func _load_json_directory(directory_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(directory_path)
	if dir == null:
		push_warning("[DataManager] 数据目录不存在或无法访问: %s" % directory_path)
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path: String = "%s/%s" % [directory_path, file_name]
			var data: Variant = _load_json_file(full_path)
			if data is Dictionary:
				var skill_id: String = file_name.trim_suffix(".json")
				var item: Dictionary = data
				if item.has("id"):
					skill_id = str(item.get("id", skill_id))
				result[skill_id] = item
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


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


## 技能数据
func get_skill(skill_id: String) -> Dictionary:
	var skills = get_all_skills()
	return skills.get(skill_id, {})


func get_all_skills() -> Dictionary:
	var data = get_data("skills")
	var nested = data.get("skills", null)
	if nested is Dictionary:
		return nested as Dictionary
	return data


## 技能树数据
func get_skill_tree(tree_id: String) -> Dictionary:
	var trees = get_all_skill_trees()
	return trees.get(tree_id, {})


func get_all_skill_trees() -> Dictionary:
	var data = get_data("skill_trees")
	var nested = data.get("trees", null)
	if nested is Dictionary:
		return nested as Dictionary
	return data


## 平衡配置数据
func get_balance(category: String, key: String, default_value = 0):
	var balance = get_data("balance")
	if balance.has(category):
		return balance[category].get(key, default_value)
	return default_value


func get_all_balance() -> Dictionary:
	return get_data("balance")


## 地图数据
func get_map_connections() -> Dictionary:
	var map_data = get_data("map_data")
	return map_data.get("connections", {})


func get_map_distances() -> Dictionary:
	var map_data = get_data("map_data")
	return map_data.get("distances", {})


func get_map_risks() -> Dictionary:
	var map_data = get_data("map_data")
	return map_data.get("risks", {})


## 建筑数据
func get_structure(structure_id: String) -> Dictionary:
	return get_item("structures", structure_id)


func get_all_structures() -> Dictionary:
	return get_data("structures")


## 工具数据
func get_tool(tool_id: String) -> Dictionary:
	return get_item("tools", tool_id)


func get_all_tools() -> Dictionary:
	return get_data("tools")


## 战利品表数据
func get_loot_table(location_id: String) -> Dictionary:
	return get_item("loot_tables", location_id)


func get_all_loot_tables() -> Dictionary:
	return get_data("loot_tables")


## 天气数据
func get_weather(weather_type: String) -> Dictionary:
	return get_item("weather", weather_type)


func get_all_weather() -> Dictionary:
	return get_data("weather")


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
