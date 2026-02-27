extends Node2D
# Factory - 废弃工厂场景

@onready var return_door = $ReturnDoor
@onready var search_workshop = $SearchWorkshop
@onready var search_storage = $SearchStorage
@onready var search_locker_room = $SearchLockerRoom

var workshop_searched = false
var storage_searched = false
var locker_room_searched = false

func _ready():
	print("[Factory] 工厂场景已加载")
	
	_setup_interactables()
	_random_encounter()
	
	if not GameState.world_unlocked_locations.has("factory"):
		DialogModule.show_dialog(
			"废弃工厂。这里可以找到制作材料，但变异体出没频繁。",
			"探索",
			""
		)
		MapModule.unlock_location("factory")

func _setup_interactables():
	if return_door:
		return_door.interaction_name = "返回街道"
		return_door.interacted.connect(_on_return_door_interacted)
	
	if search_workshop:
		search_workshop.interaction_name = "搜索车间"
		search_workshop.interacted.connect(_on_search_workshop)
	
	if search_storage:
		search_storage.interaction_name = "搜索仓库"
		search_storage.interacted.connect(_on_search_storage)
	
	if search_locker_room:
		search_locker_room.interaction_name = "搜索更衣室"
		search_locker_room.interacted.connect(_on_search_locker_room)

func _random_encounter(enemy: Dictionary = {}):
	var roll = randf()
	
	if roll < 0.5:
		var enemy_types = [
			"zombie_brute",
			"zombie_mutant",
			"bandit_scavenger",
			"bandit_scavenger"
		]
		
		var enemy_id = enemy_types[randi() % enemy_types.size()]
		var enemy = EnemyDatabase.get_enemy(enemy_id)
		
		DialogModule.show_dialog(
			"%s从阴影中冲了出来！" % enemy.name,
			"遭遇",
			""
		)
		
		await get_tree().create_timer(2.0).timeout
		CombatModule.start_combat(enemy)
		CombatModule.combat_ended.connect(_on_combat_ended)

func _on_combat_ended():
	CombatModule.combat_ended.disconnect(_on_combat_ended)
	
	if victory:
		DialogModule.show_dialog("战斗胜利！", "战斗", "")
		SkillModule.add_skill_points(randi() % 3 + 2)
		
		# 工厂敌人掉落更多废料
		InventoryModule.add_item("scrap_metal", randi() % 3 + 2)
	else:
		DialogModule.show_dialog("你勉强逃脱...", "战斗", "")
		GameState.player_hp = maxi(10, GameState.player_hp - 40)
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/locations/street_b.tscn")

func _on_return_door_interacted():
	DialogModule.show_dialog("返回街道...", "返回", "")
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/locations/street_b.tscn")

func _on_search_workshop():
	if workshop_searched:
		DialogModule.show_dialog("车间已经搜过了。", "搜索", "")
		return
	
	workshop_searched = true
	DialogModule.show_dialog("你在工具间搜寻...", "搜索", "")
	await get_tree().create_timer(1.5).timeout
	
	var roll = randf()
	if roll < 0.5:
		DialogModule.show_dialog("你找到了工具箱和金属材料！", "搜索", "")
		InventoryModule.add_item("tool_kit", 1)
		InventoryModule.add_item("scrap_metal", randi() % 4 + 2)
	elif roll < 0.8:
		DialogModule.show_dialog("找到了一些零件。", "搜索", "")
		InventoryModule.add_item("scrap_metal", randi() % 3 + 1)
	else:
		DialogModule.show_dialog("有用的工具都被拿走了。", "搜索", "")

func _on_search_storage():
	if storage_searched:
		DialogModule.show_dialog("仓库空了。", "搜索", "")
		return
	
	storage_searched = true
	DialogModule.show_dialog("你进入仓库...", "搜索", "")
	await get_tree().create_timer(1.5).timeout
	
	var roll = randf()
	if roll < 0.4:
		DialogModule.show_dialog("大丰收！你找到了大量材料。", "搜索", "")
		InventoryModule.add_item("scrap_metal", randi() % 5 + 3)
		InventoryModule.add_item("component_electronic", randi() % 2 + 1)
	elif roll < 0.7:
		DialogModule.show_dialog("找到了一些有用的东西。", "搜索", "")
		InventoryModule.add_item("scrap_metal", randi() % 3 + 1)
	else:
		DialogModule.show_dialog("仓库被洗劫一空了。", "搜索", "")

func _on_search_locker_room():
	if locker_room_searched:
		DialogModule.show_dialog("更衣室什么都没有。", "搜索", "")
		return
	
	locker_room_searched = true
	DialogModule.show_dialog("你搜索更衣室...", "搜索", "")
	await get_tree().create_timer(1.5).timeout
	
	var roll = randf()
	if roll < 0.3:
		DialogModule.show_dialog("找到了工人留下的午餐盒！", "搜索", "")
		InventoryModule.add_item("food_canned", randi() % 2 + 1)
		InventoryModule.add_item("water_bottle", 1)
	elif roll < 0.6:
		DialogModule.show_dialog("找到了一件旧夹克。", "搜索", "")
		InventoryModule.add_item("clothing_jacket", 1)
	else:
		DialogModule.show_dialog("只有破烂的衣服。", "搜索", "")
