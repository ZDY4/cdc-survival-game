extends Node2D
# Supermarket - 废弃超市场景

@onready var return_door = $ReturnDoor
@onready var search_shelves = $SearchShelves
@onready var search_freezer = $SearchFreezer
@onready var search_office = $SearchOffice

var shelves_searched = false
var freezer_searched = false
var office_searched = false

func _ready():
	print("[Supermarket] 超市场景已加载")
	
	_setup_interactables()
	_random_encounter()
	
	# 检查是否是首次来超市
	if not GameState.world_unlocked_locations.has("supermarket"):
		DialogModule.show_dialog(
			"你来到了废弃超市。货架上可能还有未被搜刮的食物，但要小心，这里也是掠夺者的聚集地。",
			"探索",
			""
		)
		MapModule.unlock_location("supermarket")
		QuestSystem.start_quest("find_food")

func _setup_interactables():
	if return_door:
		return_door.interaction_name = "返回街道"
		return_door.interaction_description = "返回安全区域"
		return_door.interacted.connect(_on_return_door_interacted)
	
	if search_shelves:
		search_shelves.interaction_name = "搜索货架"
		search_shelves.interaction_description = "寻找食物和物资"
		search_shelves.interacted.connect(_on_search_shelves)
	
	if search_freezer:
		search_freezer.interaction_name = "搜索冷冻柜"
		search_freezer.interaction_description = "可能有保存的食物"
		search_freezer.interacted.connect(_on_search_freezer)
	
	if search_office:
		search_office.interaction_name = "搜索经理室"
		search_office.interaction_description = "可能有值钱的东西"
		search_office.interacted.connect(_on_search_office)

func _random_encounter(enemy: Dictionary = {}):
	var roll = randf()
	
	if roll < 0.4:
		var enemy_types = [
			{"id": "zombie_walker", "name": "行尸", "hp": 25, "damage": 4},
			{"id": "bandit_scavenger", "name": "拾荒强盗", "hp": 35, "damage": 6},
			{"id": "mutant_dog", "name": "变异犬", "hp": 22, "damage": 6}
		]
		
		var enemy_template = enemy_types[randi() % enemy_types.size()]
		var enemy = EnemyDatabase.get_enemy(enemy_template.id)
		
		DialogModule.show_dialog(
			"%s出现在货架之间！" % enemy.name,
			"遭遇",
			""
		)
		
		await get_tree().create_timer(2.0).timeout
		CombatModule.start_combat(enemy)
		CombatModule.combat_ended.connect(_on_combat_ended)

func _on_combat_ended():
	CombatModule.combat_ended.disconnect(_on_combat_ended)
	
	if victory:
		DialogModule.show_dialog(
			"你击败了敌人！",
			"战斗胜利",
			""
		)
		SkillModule.add_skill_points(randi() % 2 + 1)
	else:
		DialogModule.show_dialog(
			"你逃回了街道...",
			"战斗失败",
			""
		)
		GameState.player_hp = maxi(10, GameState.player_hp - 30)
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/locations/street_a.tscn")

func _on_return_door_interacted():
	DialogModule.show_dialog("你决定返回街道。", "返回", "")
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/locations/street_a.tscn")

func _on_search_shelves(player: Dictionary = {}):
	if shelves_searched:
		DialogModule.show_dialog("货架已经被搜空了。", "搜索", "")
		return
	
	shelves_searched = true
	DialogModule.show_dialog("你在货架间翻找...", "搜索", "")
	await get_tree().create_timer(1.5).timeout
	
	var roll = randf()
	if roll < 0.5:
		var food_count = randi() % 3 + 1
		DialogModule.show_dialog("你找到了%d罐食物！" % food_count, "搜索", "")
		InventoryModule.add_item("food_canned", food_count)
		QuestSystem.on_search_completed("supermarket")
	elif roll < 0.8:
		DialogModule.show_dialog("你找到了一些瓶装水。", "搜索", "")
		InventoryModule.add_item("water_bottle", randi() % 2 + 1)
	else:
		DialogModule.show_dialog("货架上空空如也。", "搜索", "")

func _on_search_freezer():
	if freezer_searched:
		DialogModule.show_dialog("冷冻柜已经坏了，里面什么都没有。", "搜索", "")
		return
	
	freezer_searched = true
	DialogModule.show_dialog("你打开冷冻柜...", "搜索", "")
	await get_tree().create_timer(1.5).timeout
	
	var roll = randf()
	if roll < 0.3:
		DialogModule.show_dialog("你找到了一些冷冻食品！虽然解冻了，但还能吃。", "搜索", "")
		InventoryModule.add_item("food_canned", 2)
		InventoryModule.add_item("water_bottle", 1)
	elif roll < 0.6:
		DialogModule.show_dialog("一股恶臭扑面而来...食物都腐烂了。", "搜索", "")
		randf() < 0.3 ? SurvivalSystem.add_disease("food_poisoning") : null
	else:
		DialogModule.show_dialog("冷冻柜里只有冰和霉菌。", "搜索", "")

func _on_search_office():
	if office_searched:
		DialogModule.show_dialog("经理室已经被洗劫过了。", "搜索", "")
		return
	
	office_searched = true
	DialogModule.show_dialog("你在经理室搜寻...", "搜索", "")
	await get_tree().create_timer(1.5).timeout
	
	var roll = randf()
	if roll < 0.3:
		DialogModule.show_dialog("你在保险箱里发现了一些现金和珠宝！虽然末日里钱不值钱，但或许有用。", "搜索", "")
		InventoryModule.add_item("money", randi() % 100 + 50)
		InventoryModule.add_item("jewelry", 1)
	elif roll < 0.6:
		DialogModule.show_dialog("你找到了急救箱！", "搜索", "")
		InventoryModule.add_item("first_aid_kit", 1)
	else:
		DialogModule.show_dialog("办公室一片狼藉，什么都没找到。", "搜索", "")
