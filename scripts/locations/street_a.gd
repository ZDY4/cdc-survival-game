extends Node2D
# StreetA - 废弃街道A场景

@onready var return_door = $ReturnDoor
@onready var search_area = $SearchArea

var searched = false

func _ready():
	print("[StreetA] 街道场景已加载")
	
	_setup_interactables()
	
	# 随机遭遇敌人
	_random_encounter()
	
	EventBus.subscribe(EventBus.EventType.SCENE_INTERACTION, _on_scene_interaction)

func _setup_interactables():
	
	if return_door:
		return_door.interaction_name = "返回安全屋"
		return_door.interaction_description = "返回安全屋休息"
		return_door.interacted.connect(_on_return_door_interacted)
	
	if search_area:
		search_area.interaction_name = "搜索"
		search_area.interaction_description = "搜索废弃车辆"
		search_area.interacted.connect(_on_search_interacted)

func _random_encounter(enemy: Dictionary = {}):
	
	var roll = randf()
	
	if roll < 0.3:  # 30% 遭遇敌人
		DialogModule.show_dialog(
			"一只僵尸从废弃车辆后面冲了出来！",
			"遭遇",
			""
		)
		
		# 延迟后进入战斗
		await get_tree().create_timer(2.0).timeout
		
		CombatModule.start_combat({
			"name": "僵尸",
			"hp": 30,
			"max_hp": 30,
			"damage": 5
		})
		
		# 等待战斗结束
		CombatModule.combat_ended.connect(_on_combat_ended)

func _on_combat_ended():
	CombatModule.combat_ended.disconnect(_on_combat_ended)
	
	if victory:
		DialogModule.show_dialog(
			"你击败了僵尸！在尸体上你发现了一些物品。",
			"战斗胜利",
			""
		)
		
		# 给予奖励
		InventoryModule.add_item("scrap_metal", 1)
		SkillModule.add_skill_points(5)
	else:
		DialogModule.show_dialog(
			"你被僵尸击败了...挣扎着逃回了安全屋。",
			"战斗失败",
			""
		)
		
		# 损失一些状态并返回
		GameState.player_hp = maxi(10, GameState.player_hp - 30)
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/locations/safehouse.tscn")

func _on_return_door_interacted():
	
	print("[StreetA] 玩家返回安全屋")
	
	DialogModule.show_dialog(
		"你决定返回安全屋。",
		"返回",
		""
	)
	
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/locations/safehouse.tscn")

func _on_search_interacted():
	
	if searched:
		DialogModule.show_dialog(
			"这里已经被搜刮过了。",
			"搜索",
			""
		)
		return
	
	searched = true
	
	# 随机发现物品
	var roll = randf()
	
	if roll < 0.3:
		DialogModule.show_dialog(
			"你在废弃车辆里发现了一瓶水和一罐食物！",
			"搜索",
			""
		)
		InventoryModule.add_item("water_bottle", 1)
		InventoryModule.add_item("food_canned", 1)
	elif roll < 0.6:
		DialogModule.show_dialog(
			"你发现了一些废弃材料。",
			"搜索",
			""
		)
		InventoryModule.add_item("scrap_metal", 2)
	else:
		DialogModule.show_dialog(
			"你搜索了一番，但没发现什么有用的东西。",
			"搜索",
			""
		)

func _on_scene_interaction():
	pass

func _exit_tree():
	EventBus.unsubscribe(EventBus.EventType.SCENE_INTERACTION, _on_scene_interaction)
