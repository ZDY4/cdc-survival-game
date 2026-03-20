extends Control
# MainMenu - 游戏主菜单

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var continue_button: Button = $VBoxContainer/ContinueButton
@onready var exit_button: Button = $VBoxContainer/ExitButton

func _ready():
	# 连接按钮信号
	start_button.pressed.connect(_on_start_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	
	# 检查是否有存档
	continue_button.disabled = not SaveSystem.has_save()
	
	# Web平台隐藏退出按钮
	if OS.has_feature("web"):
		exit_button.visible = false
	
	# 应用安全区域适配
	_apply_safe_area()
	
	# 阻止Web平台的默认滚动行为
	if OS.has_feature("web") and TouchInputHandler:
		TouchInputHandler.prevent_default_scroll()
	
	print("[MainMenu] 主菜单已加载")

func _on_start_pressed():
	print("[MainMenu] 开始新游戏")
	
	# 重置游戏状态
	_reset_game_state()
	
	# 进入大地图世界入口
	get_tree().change_scene_to_file("res://scenes/locations/game_overworld.tscn")

func _on_continue_pressed():
	print("[MainMenu] 继续游戏")
	
	if SaveSystem.has_save():
		if SaveSystem.load_latest_game():
			print("[MainMenu] 存档加载成功")
			get_tree().change_scene_to_file("res://scenes/locations/game_overworld.tscn")
		else:
			print("[MainMenu] 存档加载失败")
			# 显示错误提示
	else:
		print("[MainMenu] 没有存档")

func _on_exit_pressed():
	print("[MainMenu] 退出游戏")
	get_tree().quit()

func _reset_game_state(item: Dictionary = {}):
	var base_attributes := {
		"sets": {
			"base": {
				"strength": 5,
				"agility": 5,
				"constitution": 5
			},
			"combat": {
				"max_hp": 100,
				"attack_power": 5,
				"defense": 0,
				"speed": 5,
				"accuracy": 70,
				"crit_chance": 0.05,
				"crit_damage": 1.5,
				"evasion": 0.05
			}
		},
		"resources": {
			"hp": {
				"current": 100
			}
		}
	}
	if AttributeSystem:
		if AttributeSystem.has_method("reset_player_attributes"):
			AttributeSystem.reset_player_attributes()
		AttributeSystem.set_player_attributes_container(base_attributes)
	GameState.player_hunger = 100
	GameState.player_thirst = 100
	GameState.player_stamina = 100
	GameState.player_mental = 100
	GameState.player_position = "safehouse"
	GameState.last_small_map_location = "safehouse"
	GameState.clear_pending_scene_entry()
	
	if GameState.has_method("set_inventory_from_save"):
		GameState.set_inventory_from_save([], 20, 5, 4, 1)
	else:
		GameState.inventory_items.clear()
	InventoryModule.add_item("1008", 2)
	InventoryModule.add_item("1007", 1)
	InventoryModule.add_item("1006", 3)
	
	# 添加初始武器和弹药
	InventoryModule.add_item("1002", 1)
	InventoryModule.add_item("1003", 1)
	GameState.queue_ammo("1009", 12)
	GameState.queue_equip("1002", "main_hand")
	
	# 添加初始装备
	InventoryModule.add_item("2004", 1)
	InventoryModule.add_item("2013", 1)
	InventoryModule.add_item("2015", 1)
	GameState.queue_equip("2004", "body")
	GameState.queue_equip("2013", "legs")
	GameState.queue_equip("2015", "feet")
	
	GameState.world_time = 8
	GameState.world_day = 1
	GameState.world_weather = "clear"
	GameState.world_unlocked_locations = ["safehouse", "street_a", "street_b", "factory", "supermarket"]

func _apply_safe_area():
	# 移动端安全区域适配（刘海屏、圆角屏等）
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		var safe_area = DisplayServer.get_display_safe_area()
		var screen_size = DisplayServer.screen_get_size()
		
		if safe_area != Rect2i() and screen_size != Vector2i.ZERO:
			# 计算安全区域边距
			var margin_left = safe_area.position.x
			var margin_top = safe_area.position.y
			var margin_right = screen_size.x - safe_area.end.x
			var margin_bottom = screen_size.y - safe_area.end.y
			
			# 调整主容器边距
			var vbox = $VBoxContainer
			if vbox:
				vbox.offset_left += margin_left
				vbox.offset_right -= margin_right
				vbox.offset_top += margin_top
				vbox.offset_bottom -= margin_bottom
