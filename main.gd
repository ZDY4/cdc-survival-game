extends Node2D

# 主场景脚本 - 处理标题画面和开始游戏

func _ready():
	print("[Main] Title screen loaded. Press ANY KEY to start.")

func _input():
	# 检测任意键盘按键按下
	if event is InputEventKey && event.pressed && not event.echo:
		_start_game()
		# 标记输入为已处理，防止传播
		if get_viewport():
			get_viewport().set_input_as_handled()

func _start_game():
	print("[Main] Starting game...")
	
	# 尝试加载存档，如果没有则开始新游戏
	if SaveSystem.has_save():
		print("[Main] Save file found, loading...")
		SaveSystem.load_game()
		# 加载保存的位置并切换场景
		var saved_position = GameState.player_position
		var scene_path = "res://scenes/locations/" + saved_position + ".tscn"
		print("[Main] Loading scene: " + scene_path)
		get_tree().change_scene_to_file(scene_path)
	else:
		print("[Main] No save file, starting new game at safehouse.")
		# 开始新游戏，前往安全屋
		GameState.player_position = "safehouse"
		GameState.player_hp = GameState.player_max_hp
		GameState.player_hunger = 100
		GameState.player_thirst = 100
		GameState.player_mental = 100
		
		# 给予一些初始物品
		InventoryModule.add_item("food_canned", 3)
		InventoryModule.add_item("water_bottle", 2)
		InventoryModule.add_item("bandage", 2)
		
		# 切换到安全屋场景
		get_tree().change_scene_to_file("res://scenes/locations/safehouse.tscn")
	
	print("[Main] Game started successfully!")
