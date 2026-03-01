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
	
	# 进入3D游戏世界
	get_tree().change_scene_to_file("res://scenes/locations/game_world_3d.tscn")

func _on_continue_pressed():
	print("[MainMenu] 继续游戏")
	
	if SaveSystem.has_save():
		if SaveSystem.load_game():
			print("[MainMenu] 存档加载成功")
			# 根据存档中的位置进入相应场景
			var player_pos = GameState.player_position
			var scene_path = _get_scene_path(player_pos)
			get_tree().change_scene_to_file(scene_path)
		else:
			print("[MainMenu] 存档加载失败")
			# 显示错误提示
	else:
		print("[MainMenu] 没有存档")

func _on_exit_pressed():
	print("[MainMenu] 退出游戏")
	get_tree().quit()

func _reset_game_state(item: Dictionary = {}):
	
	GameState.player_hp = 100
	GameState.player_max_hp = 100
	GameState.player_hunger = 100
	GameState.player_thirst = 100
	GameState.player_stamina = 100
	GameState.player_mental = 100
	GameState.player_position = "safehouse"
	
	GameState.inventory_items.clear()
	GameState.inventory_items.append({"id": "water_bottle", "count": 2})
	GameState.inventory_items.append({"id": "food_canned", "count": 1})
	GameState.inventory_items.append({"id": "bandage", "count": 3})
	
	# 添加初始武器和弹药
	WeaponSystem.add_weapon("knife")
	WeaponSystem.add_weapon("baseball_bat")
	WeaponSystem.add_ammo("ammo_pistol", 12)
	WeaponSystem.equip_weapon("knife")
	
	# 添加初始装备
	EquipmentSystem.add_equipment("armor_cloth")
	EquipmentSystem.add_equipment("pants_jeans")
	EquipmentSystem.add_equipment("shoes_sneakers")
	EquipmentSystem.equip("armor_cloth")
	EquipmentSystem.equip("pants_jeans")
	EquipmentSystem.equip("shoes_sneakers")
	
	GameState.world_time = 8
	GameState.world_day = 1
	GameState.world_weather = "clear"
	GameState.world_unlocked_locations = ["safehouse", "street_a"]

func _get_scene_path(location: String):
	
	match location:
		"safehouse":
			return "res://scenes/locations/safehouse.tscn"
		"street_a":
			return "res://scenes/locations/street_a.tscn"
		"street_b":
			return "res://scenes/locations/street_b.tscn"
		"hospital":
			return "res://scenes/locations/hospital.tscn"
		"supermarket":
			return "res://scenes/locations/supermarket.tscn"
		"factory":
			return "res://scenes/locations/factory.tscn"
		"subway":
			return "res://scenes/locations/subway.tscn"
		_:
			return "res://scenes/locations/safehouse.tscn"

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
