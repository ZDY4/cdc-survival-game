extends RefCounted
## RecipeData - 制作配方数据类
## 定义制作一个物品所需的全部条件

class_name RecipeData

# ========== 基础信息 ==========
var id: String = ""
var name: String = ""
var description: String = ""
var category: String = "misc"  # weapon, armor, medical, food, tool, misc

# ========== 产出 ==========
var output_item_id: String = ""      # 产出的物品ID
var output_count: int = 1            # 产出数量
var output_quality_bonus: int = 0    # 品质加成（影响耐久、属性等）

# ========== 材料需求 ==========
var materials: Array[Dictionary] = []  # [{"item_id": "", "count": 1}]

# ========== 工具需求 ==========
var required_tools: Array[String] = []     # 必需工具ID列表
var optional_tools: Array[String] = []     # 可选工具（可以缩短时间或提高品质）

# ========== 工作台需求 ==========
var required_station: String = ""    # 工作台类型：none, workbench, forge, medical_station

# ========== 技能需求 ==========
var skill_requirements: Dictionary = {}    # {"crafting": 2, "engineering": 1}

# ========== 属性 ==========
var craft_time: float = 10.0         # 基础制作时间（秒）
var experience_reward: int = 10      # 制作获得的经验值

# ========== 解锁条件 ==========
var unlock_conditions: Array[Dictionary] = []  # [{"type": "quest", "id": "xxx"}]
var is_default_unlocked: bool = true  # 是否默认解锁

# ========== 序列化/反序列化 ==========

func serialize() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"category": category,
		"output": {
			"item_id": output_item_id,
			"count": output_count,
			"quality_bonus": output_quality_bonus
		},
		"materials": materials.duplicate(true),
		"required_tools": required_tools.duplicate(),
		"optional_tools": optional_tools.duplicate(),
		"required_station": required_station,
		"skill_requirements": skill_requirements.duplicate(),
		"craft_time": craft_time,
		"experience_reward": experience_reward,
		"unlock_conditions": unlock_conditions.duplicate(true),
		"is_default_unlocked": is_default_unlocked
	}

func deserialize(data: Dictionary):
	id = str(data.get("id", ""))
	name = str(data.get("name", ""))
	description = str(data.get("description", ""))
	category = str(data.get("category", "misc"))
	
	var output = data.get("output", {})
	output_item_id = str(output.get("item_id", ""))
	output_count = int(output.get("count", 1))
	output_quality_bonus = int(output.get("quality_bonus", 0))
	
	var mats = data.get("materials", [])
	materials = Array(mats, TYPE_DICTIONARY, "", null)
	var req_tools = data.get("required_tools", [])
	required_tools = []
	for tool in req_tools:
		required_tools.append(str(tool))
	
	var opt_tools = data.get("optional_tools", [])
	optional_tools = []
	for tool in opt_tools:
		optional_tools.append(str(tool))
	required_station = str(data.get("required_station", ""))
	skill_requirements = data.get("skill_requirements", {}).duplicate()
	
	craft_time = float(data.get("craft_time", 10.0))
	experience_reward = int(data.get("experience_reward", 10))
	
	var unlock_conds = data.get("unlock_conditions", [])
	unlock_conditions = Array(unlock_conds, TYPE_DICTIONARY, "", null)
	is_default_unlocked = data.get("is_default_unlocked", true)

# ========== 便捷方法 ==========

## 获取材料列表（用于显示）
func get_materials_list() -> String:
	var parts = []
	for mat in materials:
		var item_name = ItemDatabase.get_item_name(mat.get("item_id", ""))
		parts.append("%s x%d" % [item_name, mat.get("count", 1)])
	return ", ".join(parts)

## 检查是否有工具需求
func requires_tools() -> bool:
	return not required_tools.is_empty()

## 检查是否需要工作台
func requires_station() -> bool:
	return not required_station.is_empty() and required_station != "none"

## 检查是否有技能需求
func requires_skills() -> bool:
	return not skill_requirements.is_empty()

## 获取总材料数量
func get_total_material_count() -> int:
	var total = 0
	for mat in materials:
		total += mat.get("count", 1)
	return total

## 检查是否产出指定物品
func produces_item(item_id: String) -> bool:
	return output_item_id == item_id
