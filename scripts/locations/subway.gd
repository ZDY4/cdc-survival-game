extends Node2D
# Subway - 地铁站场景

@onready var return_door = $ReturnDoor
@onready var search_platform = $SearchPlatform
@onready var search_train = $SearchTrain
@onready var search_control_room = $SearchControlRoom

var platform_searched = false
var train_searched = false
var control_room_searched = false

func _ready():
	print("[Subway] 地铁站场景已加载")
	
	_setup_interactables()
	_random_encounter()
	
	if not GameState.world_unlocked_locations.has("subway"):
		DialogModule.show_dialog(
			"地铁站。黑暗中可能有任何东西...这里是最危险的区域之一。",
			"探索",
			""
		)
		MapModule.unlock_location("subway")
		QuestSystem.start_quest("explore_underground")

func _setup_interactables():
	if return_door:
		return_door.interaction_name = "返回地面"
		return_door.interacted.connect(_on_return_door_interacted)
	
	if search_platform:
		search_platform.interaction_name = "搜索站台"
		search_platform.interacted.connect(_on_search_platform)
	
	if search_train:
		search_train.interaction_name = "搜索列车"
		search_train.interacted.connect(_on_search_train)
	
	if search_control_room:
		search_control_room.interaction_name = "搜索控制室"
		search_control_room.interacted.connect(_on_search_control_room)

func _random_encounter(_enemy: Dictionary = {}):
	var roll = randf()
	
	# 地铁站非常危险，70%遭遇率
	if roll < 0.7:
		var enemy_types = [
			"zombie_runner",
			"zombie_runner",
			"zombie_mutant",
			"bandit_leader"
		]
		
		var enemy_id = enemy_types[randi() % enemy_types.size()]
		var enemy_data = EnemyDatabase.get_enemy(enemy_id)
		
		DialogModule.show_dialog(
			"黑暗中，%s向你扑来！" % enemy_data.name,
			"遭遇",
			""
		)
		
		await get_tree().create_timer(2.0).timeout
		CombatModule.start_combat(enemy_data)
		CombatModule.combat_ended.connect(_on_combat_ended.bind(true))

func _on_combat_ended(victory: bool = true):
	CombatModule.combat_ended.disconnect(_on_combat_ended)
	
	if victory:
		DialogModule.show_dialog("你战胜了敌人！", "战斗", "")
		SkillModule.add_skill_points(randi() % 3 + 3)
		InventoryModule.add_item("scrap_metal", randi() % 3 + 1)
		QuestSystem.update_quest_progress("explore_underground", "kill", 1)
	else:
		DialogModule.show_dialog("你拼命逃回地面...", "战斗", "")
		GameState.player_hp = maxi(5, GameState.player_hp - 50)
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/locations/street_b.tscn")

func _on_return_door_interacted():
	DialogModule.show_dialog("返回地面...", "返回", "")
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/locations/street_b.tscn")

func _on_search_platform():
	if platform_searched:
		DialogModule.show_dialog("站台已经搜过了。", "搜索", "")
		return
	
	platform_searched = true
	DialogModule.show_dialog("你在站台搜寻...", "搜索", "")
	await get_tree().create_timer(1.5).timeout
	
	var roll = randf()
	if roll < 0.3:
		DialogModule.show_dialog("你找到了一个急救包和一些水！", "搜索", "")
		InventoryModule.add_item("first_aid_kit", 1)
		InventoryModule.add_item("water_bottle", randi() % 2 + 1)
	elif roll < 0.6:
		DialogModule.show_dialog("你找到了一些遗落的物品。", "搜索", "")
		InventoryModule.add_item("scrap_metal", randi() % 2 + 1)
	else:
		DialogModule.show_dialog("只有垃圾和碎石。", "搜索", "")

func _on_search_train():
	if train_searched:
		DialogModule.show_dialog("列车已经空了。", "搜索", "")
		return
	
	train_searched = true
	DialogModule.show_dialog("你小心翼翼地进入列车...", "搜索", "")
	await get_tree().create_timer(1.5).timeout
	
	var roll = randf()
	if roll < 0.4:
		DialogModule.show_dialog("你在列车里发现了生存物资！", "搜索", "")
		InventoryModule.add_item("food_canned", randi() % 3 + 1)
		InventoryModule.add_item("bandage", randi() % 2 + 1)
		QuestSystem.update_quest_progress("explore_underground", "search", 1)
	elif roll < 0.7:
		DialogModule.show_dialog("找到了一些有用的材料。", "搜索", "")
		InventoryModule.add_item("component_electronic", 1)
		InventoryModule.add_item("scrap_metal", 2)
	else:
		DialogModule.show_dialog("列车里只有尸体。", "搜索", "")

func _on_search_control_room():
	if control_room_searched:
		DialogModule.show_dialog("控制室已经被彻底搜索。", "搜索", "")
		return
	
	control_room_searched = true
	DialogModule.show_dialog("你进入控制室...", "搜索", "")
	await get_tree().create_timer(1.5).timeout
	
	var roll = randf()
	if roll < 0.3:
		DialogModule.show_dialog("你找到了地铁系统的备用钥匙卡！或许可以开启新的通路。", "搜索", "")
		InventoryModule.add_item("keycard_subway", 1)
		QuestSystem.start_quest("find_survivors")
	elif roll < 0.6:
		DialogModule.show_dialog("找到了一些电子元件。", "搜索", "")
		InventoryModule.add_item("component_electronic", randi() % 3 + 1)
	else:
		DialogModule.show_dialog("控制设备都被破坏了。", "搜索", "")
