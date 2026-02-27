# Telegram Integration for CDC Survival Game
# 处理 Telegram WebApp 特定功能

extends Node

# ========== 信号 ==========
signal theme_changed(color_scheme: String)  # 主题变化信号
signal viewport_changed()  # 视口变化信号
signal main_button_pressed()  # 主按钮按下信号
signal popup_closed(button_id: String)  # 弹窗关闭信号
signal confirm_result(confirmed: bool)  # 确认结果信号
signal alert_closed()  # 警告关闭信号
signal window_resized(new_size: Vector2)  # 窗口大小变化信号
signal visibility_changed(is_visible: bool)  # 可见性变化信号

# ========== 属性 ==========
var is_telegram: bool = false  # 是否在 Telegram 环境中
var _initialized: bool = false  # 是否已初始化

# Telegram 主题参数
var theme_params: Dictionary = {}
var color_scheme: String = "dark"

# ========== 生命周期 ==========

func _ready():
	# 检测是否在 Telegram 环境中
	_detect_telegram_environment()
	
	if is_telegram:
		print("[TelegramIntegration] Running in Telegram WebApp")
		_setup_telegram_ui()
	else:
		print("[TelegramIntegration] Running in standard browser")

func _notification(what: int):
	# 处理应用暂停/恢复
	if what == NOTIFICATION_APPLICATION_PAUSED:
		visibility_changed.emit(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		visibility_changed.emit(true)

# ========== 私有方法 ==========

# 检测 Telegram 环境
func _detect_telegram_environment() -> void:
	if OS.has_feature("web"):
		# 使用 JavaScriptBridge 检测
		var result = JavaScriptBridge.eval("typeof window !== 'undefined' && window.isTelegramWebApp === true", true)
		is_telegram = result if result != null else false
	else:
		is_telegram = false

# 设置 Telegram UI
func _setup_telegram_ui() -> void:
	if not is_telegram:
		return
	
	# 设置 JavaScript 回调
	_setup_javascript_callbacks()
	
	# 获取主题信息
	_fetch_theme_info()
	
	_initialized = true

# 设置 JavaScript 回调
func _setup_javascript_callbacks() -> void:
	if not is_telegram:
		return
	
	# 主按钮点击回调
	var main_button_callback = JavaScriptBridge.create_callback(func(args):
		main_button_pressed.emit()
	)
	JavaScriptBridge.eval("window.godotTelegramBridge.onMainButtonClick = " + main_button_callback + ";", true)
	
	# 弹窗关闭回调
	var popup_callback = JavaScriptBridge.create_callback(func(args):
		var button_id = args[0] if args.size() > 0 else ""
		popup_closed.emit(str(button_id))
	)
	JavaScriptBridge.eval("window.godotTelegramBridge.onPopupClosed = " + popup_callback + ";", true)
	
	# 确认结果回调
	var confirm_callback = JavaScriptBridge.create_callback(func(args):
		var confirmed = args[0] if args.size() > 0 else false
		confirm_result.emit(bool(confirmed))
	)
	JavaScriptBridge.eval("window.godotTelegramBridge.onConfirmResult = " + confirm_callback + ";", true)
	
	# 警告关闭回调
	var alert_callback = JavaScriptBridge.create_callback(func(args):
		alert_closed.emit()
	)
	JavaScriptBridge.eval("window.godotTelegramBridge.onAlertClosed = " + alert_callback + ";", true)

# 获取主题信息
func _fetch_theme_info() -> void:
	if not is_telegram:
		return
	
	color_scheme = JavaScriptBridge.eval("window.godotTelegramBridge.getColorScheme()", true)
	
	var params = JavaScriptBridge.eval("JSON.stringify(window.godotTelegramBridge.getThemeParams())", true)
	if params:
		theme_params = JSON.parse_string(params)
	
	print("[TelegramIntegration] Theme: ", color_scheme)
	print("[TelegramIntegration] Theme Params: ", theme_params)

# ========== 公共 API ==========

# 检查是否在 Telegram 环境中
func is_telegram_webapp() -> bool:
	return is_telegram

# 显示主按钮
func show_main_button(text: String = "继续") -> void:
	if not is_telegram:
		return
	JavaScriptBridge.eval("window.godotTelegramBridge.showMainButton('" + text + "');", true)

# 隐藏主按钮
func hide_main_button() -> void:
	if not is_telegram:
		return
	JavaScriptBridge.eval("window.godotTelegramBridge.hideMainButton();", true)

# 设置主按钮加载状态
func set_main_button_loading(loading: bool) -> void:
	if not is_telegram:
		return
	JavaScriptBridge.eval("window.godotTelegramBridge.setMainButtonLoading(" + str(loading).to_lower() + ");", true)

# 启用/禁用主按钮
func set_main_button_enabled(enabled: bool) -> void:
	if not is_telegram:
		return
	JavaScriptBridge.eval("window.godotTelegramBridge.setMainButtonEnabled(" + str(enabled).to_lower() + ");", true)

# 触发震动反馈
# type: "light", "medium", "heavy", "success", "error", "warning", "selection"
func haptic_feedback(type: String = "light") -> void:
	if not is_telegram:
		return
	JavaScriptBridge.eval("window.godotTelegramBridge.hapticFeedback('" + type + "');", true)

# 显示弹窗
func show_popup(title: String, message: String, buttons: Array = []) -> void:
	if not is_telegram:
		# 非 Telegram 环境使用标准弹窗
		print("[Popup] " + title + ": " + message)
		return
	
	var buttons_json = JSON.stringify(buttons) if buttons.size() > 0 else "[{type: 'ok'}]"
	JavaScriptBridge.eval(
		"window.godotTelegramBridge.showPopup('" + title + "', '" + message + "', " + buttons_json + ");",
		true
	)

# 显示确认对话框
func show_confirm(message: String) -> void:
	if not is_telegram:
		# 非 Telegram 环境直接返回 true
		confirm_result.emit(true)
		return
	JavaScriptBridge.eval("window.godotTelegramBridge.showConfirm('" + message + "');", true)

# 显示警告
func show_alert(message: String) -> void:
	if not is_telegram:
		print("[Alert] " + message)
		alert_closed.emit()
		return
	JavaScriptBridge.eval("window.godotTelegramBridge.showAlert('" + message + "');", true)

# 设置头部颜色
func set_header_color(color: String) -> void:
	if not is_telegram:
		return
	JavaScriptBridge.eval("window.godotTelegramBridge.setHeaderColor('" + color + "');", true)

# 设置背景颜色
func set_background_color(color: String) -> void:
	if not is_telegram:
		return
	JavaScriptBridge.eval("window.godotTelegramBridge.setBackgroundColor('" + color + "');", true)

# 打开链接
func open_link(url: String) -> void:
	if is_telegram:
		JavaScriptBridge.eval("window.godotTelegramBridge.openLink('" + url + "');", true)
	else:
		OS.shell_open(url)

# 打开 Telegram 链接
func open_telegram_link(url: String) -> void:
	if is_telegram:
		JavaScriptBridge.eval("window.godotTelegramBridge.openTelegramLink('" + url + "');", true)
	else:
		OS.shell_open(url)

# 关闭 WebApp
func close_webapp() -> void:
	if not is_telegram:
		return
	JavaScriptBridge.eval("window.godotTelegramBridge.close();", true)

# 获取启动参数
func get_init_data() -> String:
	if not is_telegram:
		return ""
	return JavaScriptBridge.eval("window.godotTelegramBridge.getInitData();", true)

# 获取用户信息
func get_user_info() -> Dictionary:
	if not is_telegram:
		return {}
	
	var user_json = JavaScriptBridge.eval("JSON.stringify(window.godotTelegramBridge.getUserInfo() || {})", true)
	if user_json:
		return JSON.parse_string(user_json)
	return {}

# 发送数据到 Bot
func send_data(data: String) -> void:
	if not is_telegram:
		print("[SendData] " + data)
		return
	JavaScriptBridge.eval("window.godotTelegramBridge.sendData('" + data + "');", true)

# 获取主题颜色值
func get_theme_color(color_key: String, default_color: String = "#000000") -> String:
	return theme_params.get(color_key, default_color)

# ========== 便捷方法 ==========

# 播放按钮点击音效和震动
func play_button_feedback() -> void:
	haptic_feedback("light")
	# 这里可以添加音效播放

# 播放成功反馈
func play_success_feedback() -> void:
	haptic_feedback("success")

# 播放错误反馈
func play_error_feedback() -> void:
	haptic_feedback("error")

# 播放警告反馈
func play_warning_feedback() -> void:
	haptic_feedback("warning")

# 保存游戏到 Telegram Cloud（发送数据到 Bot）
func save_game_to_cloud(save_data: Dictionary) -> void:
	var json_data = JSON.stringify(save_data)
	# 使用 base64 编码避免特殊字符问题
	var base64_data = Marshalls.utf8_to_base64(json_data)
	send_data("SAVE:" + base64_data)

# 从启动参数恢复游戏
func load_game_from_init_data() -> Dictionary:
	var init_data = get_init_data()
	if init_data.is_empty():
		return {}
	
	# 解析启动参数
	var params = {}
	var pairs = init_data.split("&")
	for pair in pairs:
		var kv = pair.split("=")
		if kv.size() == 2:
			params[kv[0]] = kv[1]
	
	# 检查是否有保存数据
	if params.has("start_param"):
		var start_param = params["start_param"]
		if start_param.begins_with("LOAD:"):
			var base64_data = start_param.substr(5)
			var json_data = Marshalls.base64_to_utf8(base64_data)
			return JSON.parse_string(json_data)
	
	return {}

# ========== 静态方法 ==========

# 快速检查是否在 Telegram 环境中（无需实例化）
static func check_telegram_environment() -> bool:
	if OS.has_feature("web"):
		var result = JavaScriptBridge.eval("typeof window !== 'undefined' && window.isTelegramWebApp === true", true)
		return result if result != null else false
	return false
