extends Node2D
# Hospital - 废弃医院场景

@onready var return_door = $ReturnDoor
@onready var search_medical = $SearchMedical
@onready var search_pharmacy = $SearchPharmacy

var medical_searched = false
var pharmacy_searched = false

func _ready():
	print("[Hospital] 医院场景已加载")
	
	_setup_interactables()
	
	# 医院更危险，敌人出现概率更高
	_random_encounter()
	
	# 检查是否是首次来医院
	if not GameState.world_unlocked_locations.has("hospital"):
		DialogModule.show_dialog(
			"你来到了废弃医院。这里曾经是救治病人的地方，现在只剩下死亡和危险。",
			"探索",
			""
		)
		MapModule.unlock_location("hospital")

func _setup_interactables():
	if return_door:
		return_door.interaction_name = "返回街道"
		return_door.interaction_description = "返回安全区域"
		return_door.interacted.connect(_on_return_door_interacted)
	
	if search_medical:
		search_medical.interaction_name = "搜索医疗室"
		search_medical.interaction_description = "寻找医疗物资"
		search_medical.interacted.connect(_on_search_medical)
	
	if search_pharmacy:
		search_pharmacy.interaction_name = "搜索药房"
		search_pharmacy.interaction_description = "寻找药品"
		search_pharmacy.interacted.connect(_on_search_pharmacy)

func _random_encounter(enemy: Dictionary = {}):
	
	var roll = randf()
	
	if roll < 0.5:  # 50% 遭遇敌人（比街道更危险）
		var enemy_types = [
			{"name": "僵尸患者", "hp": 25, "damage": 4},
			{"name": "变异僵尸", "hp": 40, "damage": 7},
			{"name": "僵尸医生", "hp": 30, "damage": 5}
		]
		
		var enemy = enemy_types[randi() % enemy_types.size()]
		
		DialogModule.show_dialog(
			"一只%s从阴影中冲了出来！" % enemy.name,
			"遭遇",
			""
		)
		
		await get_tree().create_timer(2.0).timeout
		
		CombatModule.start_combat({
			"name": enemy.name,
			"hp": enemy.hp,
			"max_hp": enemy.hp,
			"damage": enemy.damage,
			"type": "zombie"
		})
		
		CombatModule.combat_ended.connect(_on_combat_ended)

func _on_combat_ended():
	CombatModule.combat_ended.disconnect(_on_combat_ended)
	
	if victory:
		DialogModule.show_dialog(
			"你击败了敌人！",
			"战斗胜利",
			""
		)
		InventoryModule.add_item("scrap_metal", randi() % 2 + 1)
		SkillModule.add_skill_points(randf() > 0.5 ? 2 : 1)
		
		# 更新任务
		QuestSystem.on_search_completed("hospital")
	else:
		DialogModule.show_dialog(
			"你被击倒了...勉强逃回了街道。",
			"战斗失败",
			""
		)
		GameState.player_hp = maxi(10, GameState.player_hp - 40)
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/locations/street_a.tscn")

func _on_return_door_interacted():
	DialogModule.show_dialog(
		"你决定返回街道。",
		"返回",
		""
	)
	
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/locations/street_a.tscn")

func _on_search_medical():
	if medical_searched:
		DialogModule.show_dialog(
			"这里已经被搜刮过了。",
			"搜索",
			""
		)
		return
	
	medical_searched = true
	
	DialogModule.show_dialog(
		"你在医疗室里翻找...",
		"搜索",
		""
	)
	
	await get_tree().create_timer(1.5).timeout
	
	var roll = randf()
	if roll < 0.4:
		DialogModule.show_dialog(
			"你找到了急救包和绷带！",
			"搜索",
			""
		)
		InventoryModule.add_item("first_aid_kit", 1)
		InventoryModule.add_item("bandage", 2)
		QuestSystem.on_search_completed("hospital")
	elif roll < 0.7:
		DialogModule.show_dialog(
			"你找到了一些医用酒精和纱布。",
			"搜索",
			""
		)
		InventoryModule.add_item("bandage", 1)
	else:
		DialogModule.show_dialog(
			"你什么也没找到，只发现了干涸的血迹。",
			"搜索",
			""
		)

func _on_search_pharmacy():
	if pharmacy_searched:
		DialogModule.show_dialog(
			"药房已经被洗劫一空。",
			"搜索",
			""
		)
		return
	
	pharmacy_searched = true
	
	DialogModule.show_dialog(
		"你在药房里仔细搜寻...",
		"搜索",
		""
	)
	
	await get_tree().create_timer(1.5).timeout
	
	var roll = randf()
	if roll < 0.3:
		DialogModule.show_dialog(
			"你找到了止痛药和抗生素！",
			"搜索",
			""
		)
		InventoryModule.add_item("painkiller", 2)
		QuestSystem.on_search_completed("hospital")
	elif roll < 0.6:
		DialogModule.show_dialog(
			"你找到了一些维生素片。",
			"搜索",
			""
		)
	else:
		DialogModule.show_dialog(
			"药柜都被打开了，药品早已被洗劫一空。",
			"搜索",
			""
		)
