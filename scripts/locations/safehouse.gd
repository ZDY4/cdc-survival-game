extends Node2D
# Safehouse - 安全屋场景

@onready var bed_interactable = $Bed
@onready var door_interactable = $Door
@onready var locker_interactable = $Locker

var risk_system: Node = null
var time_manager: Node = null

func _ready():
	print("[Safehouse] 安全屋场景已加载")
	
	# 获取系统引用
	risk_system = get_node_or_null("/root/DayNightRiskSystem")
	time_manager = get_node_or_null("/root/TimeManager")
	
	# 设置可交互物件
	_setup_interactables()
	
	# 延迟显示欢迎信息，等待DialogModule初始化
	call_deferred("_show_welcome")
	
	# 通知风险系统已到达安全屋
	if risk_system:
		risk_system.is_in_safehouse = true
		risk_system.rest_in_safehouse()
	
	# 同步GameState位置
	GameState.player_position = "safehouse"
	
func _show_welcome():
	# 延迟显示欢迎信息，等待DialogModule初始化
	await get_tree().create_timer(0.5).timeout
	
	# 检查是否是夜晚
	var time_warning = ""
	if time_manager and time_manager.is_night():
		time_warning = "\n（现在是夜晚，外面很危险）"
	
	DialogModule.show_dialog(
		"你回到了安全屋。这里相对安全，可以休息恢复状态。" + time_warning,
		"系统",
		""
	)
	
	# 连接交互信号
	EventBus.subscribe(EventBus.EventType.SCENE_INTERACTION, _on_scene_interaction)

func _setup_interactables():
	
	# 床 - 睡觉存档
	if bed_interactable:
		bed_interactable.interaction_name = "睡觉"
		bed_interactable.interaction_description = "休息一晚，恢复状态并保存游戏"
		bed_interactable.interacted.connect(_on_bed_interacted)
	
	# 门 - 去街道
	if door_interactable:
		door_interactable.interaction_name = "出门"
		door_interactable.interaction_description = "前往废弃街道探索"
		door_interactable.interacted.connect(_on_door_interacted)
	
	# 储物柜 - 查看物品
	if locker_interactable:
		locker_interactable.interaction_name = "查看储物柜"
		locker_interactable.interaction_description = "查看存储的物品"
		locker_interactable.interacted.connect(_on_locker_interacted)

func _on_bed_interacted():
	
	print("[Safehouse] 玩家选择睡觉")
	
	# 确认对话框
	var time_msg = ""
	if time_manager:
		time_msg = "\n当前时间: " + time_manager.get_full_datetime()
	
	DialogModule.show_dialog(
		"你要在这里睡一晚吗？这将保存游戏并恢复你的状态。" + time_msg,
		"床",
		""
	)
	
	# 等待一下然后执行
	await get_tree().create_timer(2.0).timeout
	
	# 执行睡眠流程
	_perform_sleep()

func _perform_sleep():
	# 计算睡眠时间
	var sleep_hours = 0
	var old_day = 1
	
	if time_manager:
		old_day = time_manager.current_day
		
		# 计算到早上8点需要的时间
		var current_hour = time_manager.current_hour
		if current_hour < 8:
			sleep_hours = 8 - current_hour
		else:
			sleep_hours = (24 - current_hour) + 8
		
		# 推进时间
		time_manager.advance_hours(sleep_hours)
	else:
		# 回退到旧的GameState逻辑
		GameState.world_time = 8
		GameState.world_day += 1
	
	# 恢复状态
	GameState.player_hp = GameState.player_max_hp
	GameState.player_mental = 100
	GameState.player_stamina = 100
	GameState.player_hunger = min(100, GameState.player_hunger + 20)
	GameState.player_thirst = min(100, GameState.player_thirst + 20)
	
	# 疲劳清零
	if risk_system:
		risk_system.rest_in_safehouse()
	
	# 获取当前时间显示
	var time_text = "第 %d 天早上 8:00" % (old_day + 1)
	if time_manager:
		time_text = time_manager.get_full_datetime()
	
	# 保存游戏
	if SaveSystem.save_game():
		DialogModule.show_dialog(
			"你睡了一晚。现在是 " + time_text + "。\n状态已恢复，游戏已保存。",
			"系统",
			""
		)
		print("[Safehouse] 游戏已保存")
	else:
		DialogModule.show_dialog(
			"保存游戏失败，但你的状态已恢复。",
			"系统",
			""
		)

func _on_door_interacted():
	
	print("[Safehouse] 玩家选择出门")
	
	# 检查时间，给出警告
	var warning = ""
	if time_manager and time_manager.is_night():
		warning = "\n\n⚠️ 警告：现在是夜晚，外面非常危险！"
	
	DialogModule.show_dialog(
		"你准备前往废弃街道。外面可能有危险，请做好准备。" + warning,
		"门",
		""
	)
	
	await get_tree().create_timer(1.5).timeout
	
	# 切换到街道场景
	get_tree().change_scene_to_file("res://scenes/locations/street_a.tscn")

func _on_locker_interacted():
	
	print("[Safehouse] 玩家查看储物柜")
	
	var items_text = "储物柜里的物品：\n"
	for item in GameState.inventory_items:
		items_text += "- " + item.id + " x" + str(item.count) + "\n"
	
	if GameState.inventory_items.size() == 0:
		items_text += "（空）"
	
	DialogModule.show_dialog(
		items_text,
		"储物柜",
		""
	)

func _on_scene_interaction(data: Dictionary):
	
	if data.get("type") == "search":
		# 搜索安全屋
		DialogModule.show_dialog(
			"你搜索了安全屋，但没发现什么有用的东西。",
			"搜索",
			""
		)

func _exit_tree():
	# 取消订阅
	EventBus.unsubscribe(EventBus.EventType.SCENE_INTERACTION, _on_scene_interaction)
