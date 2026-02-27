# Telegram WebApp 使用示例
# 将此脚本附加到主菜单场景

extends Control

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton

func _ready():
	_setup_telegram_integration()
	_connect_buttons()

# 设置 Telegram 集成
func _setup_telegram_integration():
	if not TelegramIntegration.is_telegram_webapp():
		print("[MainMenu] 不在 Telegram 环境中，使用标准 UI")
		return
	
	print("[MainMenu] Telegram WebApp 已检测到")
	
	# 隐藏标准按钮
	start_button.visible = false
	quit_button.visible = false
	
	# 设置 Telegram 主按钮
	TelegramIntegration.show_main_button("开始游戏")
	TelegramIntegration.main_button_pressed.connect(_on_telegram_main_button)
	
	# 监听主题变化
	TelegramIntegration.theme_changed.connect(_on_telegram_theme_changed)
	
	# 应用当前主题
	_on_telegram_theme_changed(TelegramIntegration.color_scheme)
	
	# 显示欢迎弹窗
	var user_info = TelegramIntegration.get_user_info()
	var username = user_info.get("username", "")
	if username:
		TelegramIntegration.show_alert("欢迎回来, " + username + "!")

# 连接按钮信号
func _connect_buttons():
	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

# 开始游戏
func _on_start_pressed():
	TelegramIntegration.play_button_feedback()
	_start_game()

# Telegram 主按钮回调
func _on_telegram_main_button():
	TelegramIntegration.set_main_button_loading(true)
	_start_game()

func _start_game():
	# 这里添加游戏启动逻辑
	print("[MainMenu] 开始游戏")
	
	# 示例：切换到游戏场景
	# get_tree().change_scene_to_file("res://scenes/game.tscn")
	
	# 示例：保存游戏到云端
	var save_data = {
		"last_played": Time.get_datetime_string_from_system(),
		"play_count": 1
	}
	TelegramIntegration.save_game_to_cloud(save_data)
	
	TelegramIntegration.set_main_button_loading(false)
	TelegramIntegration.play_success_feedback()

# 设置
func _on_settings_pressed():
	TelegramIntegration.play_button_feedback()
	
	if TelegramIntegration.is_telegram_webapp():
		# 显示 Telegram 确认对话框
		TelegramIntegration.show_confirm("是否重置所有设置？")
		TelegramIntegration.confirm_result.connect(_on_settings_confirm)
	else:
		# 标准设置面板
		_show_settings_panel()

func _on_settings_confirm(confirmed: bool):
	if confirmed:
		_reset_settings()
		TelegramIntegration.show_alert("设置已重置")
		TelegramIntegration.play_success_feedback()
	else:
		TelegramIntegration.play_button_feedback()

func _show_settings_panel():
	print("[MainMenu] 显示设置面板")

func _reset_settings():
	print("[MainMenu] 重置设置")

# 退出游戏
func _on_quit_pressed():
	TelegramIntegration.play_button_feedback()
	
	if TelegramIntegration.is_telegram_webapp():
		TelegramIntegration.close_webapp()
	else:
		get_tree().quit()

# Telegram 主题变化处理
func _on_telegram_theme_changed(color_scheme: String):
	print("[MainMenu] 主题变化: ", color_scheme)
	
	if color_scheme == "dark":
		# 应用深色主题
		_modulate_theme(Color(0.1, 0.1, 0.15))
	else:
		# 应用浅色主题
		_modulate_theme(Color(0.95, 0.95, 0.98))

func _modulate_theme(color: Color):
	# 示例：修改背景色
	# 实际项目中应该切换到不同的主题资源
	var tween = create_tween()
	tween.tween_property(self, "modulate", color, 0.3)

# 保存游戏（示例）
func save_game():
	var save_data = {
		"player_name": "Player1",
		"health": 100,
		"inventory": ["medkit", "ammo"],
		"position": {"x": 100, "y": 200},
		"save_time": Time.get_unix_time_from_system()
	}
	
	if TelegramIntegration.is_telegram_webapp():
		TelegramIntegration.save_game_to_cloud(save_data)
		TelegramIntegration.show_alert("游戏已保存到云端！")
	else:
		# 本地保存
		var file = FileAccess.open("user://save.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(save_data))
		file.close()
		print("[MainMenu] 游戏已保存到本地")
