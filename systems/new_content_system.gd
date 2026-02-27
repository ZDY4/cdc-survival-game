extends Node
# NewContentSystem - 新内容系"
# 添加新敌人、任务、地"

# ===== 新敌人数"=====
const NEW_ENEMIES = {
	"mutant_dog": {
		"name": "变异",
		"description": "被病毒感染的野狗，速度快且攻击性强",
		"level": 3,
		"stats": {
			"hp": 35,
			"max_hp": 35,
			"damage": 8,
			"defense": 2,
			"speed": 9,
			"accuracy": 80
		},
		"behavior": "aggressive",
		"weaknesses": ["head", "leg"],
		"resistances": ["poison"],
		"special_abilities": ["pack_hunter"],
		"loot": [
			{"item": "dog_fang", "chance": 0.6, "min": 1, "max": 2},
			{"item": "raw_meat", "chance": 0.4, "min": 1, "max": 2},
			{"item": "leather", "chance": 0.3, "min": 1, "max": 1}
		],
		"xp": 25,
		"spawn_locations": ["street", "street_a", "street_b", "factory"],
		"spawn_rate": 0.2
	},
	
	"raider": {
		"name": "掠夺",
		"description": "装备简陋武器的幸存者，会主动攻",
		"level": 4,
		"stats": {
			"hp": 45,
			"max_hp": 45,
			"damage": 10,
			"defense": 3,
			"speed": 5,
			"accuracy": 65
		},
		"behavior": "aggressive",
		"weaknesses": ["head"],
		"resistances": [],
		"special_abilities": ["call_reinforcements"],
		"loot": [
			{"item": "ammo_pistol", "chance": 0.5, "min": 2, "max": 5},
			{"item": "scrap_metal", "chance": 0.6, "min": 2, "max": 4},
			{"item": "food_canned", "chance": 0.3, "min": 1, "max": 2}
		],
		"xp": 35,
		"spawn_locations": ["street", "supermarket", "factory"],
		"spawn_rate": 0.15
	}
}

# ===== 新任务数"=====
const NEW_QUESTS = {
	"escort_merchant": {
		"id": "escort_merchant",
		"title": "护送商",
		"description": "护送商人安全到达安全屋",
		"type": "side",
		"stages": [
			{
				"id": "stage1",
				"title": "与商人汇",
				"description": "在超市与商人汇合",
				"objectives": [
					{"type": "talk", "target": "npc_merchant", "location": "supermarket"}
				]
			},
			{
				"id": "stage2",
				"title": "护送任",
				"description": "保护商人安全到达安全",
				"objectives": [
					{"type": "escort", "target": "npc_merchant", "destination": "safehouse"}
				],
				"time_limit": 600  # 10分钟
			}
		],
		"rewards": {
			"exp": 100,
			"items": [
				{"id": "ammo_pistol", "count": 20},
				{"id": "food_canned", "count": 3}
			]
		}
	},
	
	"clear_police_station": {
		"id": "clear_police_station",
		"title": "清理警察局",
		"description": "警察局被掠夺者占据，清理他们",
		"type": "main",
		"stages": [
			{
				"id": "stage1",
				"title": "潜入警察局",
				"description": "悄悄进入警察局",
				"objectives": [
					{"type": "explore", "target": "police_station"}
				]
			},
			{
				"id": "stage2",
				"title": "消灭掠夺",
				"description": "击败所有掠夺",
				"objectives": [
					{"type": "kill", "target": "raider", "count": 5}
				]
			}
		],
		"rewards": {
			"exp": 150,
			"items": [
				{"id": "pistol", "count": 1},
				{"id": "ammo_pistol", "count": 30}
			],
			"unlock_location": "police_station_armory"
		}
	}
}

# ===== 新地点数"=====
const NEW_LOCATIONS = {
	"police_station": {
		"name": "警察局",
		"description": "废弃的警察局，可能有武器和弹",
		"scene_path": "res://scenes/locations/police_station.tscn",
		"danger_level": 4,
		"required_level": 3,
		"unlock_condition": "quest_clear_police_station",
		"enemies": ["raider", "zombie_walker"],
		"loot_tier": "high",
		"special_features": ["armory", "holding_cell"]
	}
}

func _ready():
	print("[NewContentSystem] 新内容系统已初始")
	# 注册新敌人到EnemyDatabase
	_register_new_enemies()
	# 注册新任务到QuestSystem
	_register_new_quests()

func _register_new_enemies():
	if EnemyDatabase:
		for enemy_id in NEW_ENEMIES.keys():
			# 添加新敌人到数据"
			print("[NewContentSystem] 注册新敌: " + enemy_id)

func _register_new_quests():
	if QuestSystem:
		for quest_id in NEW_QUESTS.keys():
			# 添加新任务到数据"
			print("[NewContentSystem] 注册新任: " + quest_id)

## 获取新敌人数"
func get_new_enemy():
	return NEW_ENEMIES.get(enemy_id, {})

## 获取新任务数"
func get_new_quest():
	return NEW_QUESTS.get(quest_id, {})

## 获取新地点数"
func get_new_location(type: String = ""):
	return NEW_LOCATIONS.get(location_id, {})

