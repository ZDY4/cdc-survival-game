extends Node
# ResponsiveUIManager - 响应式UI管理器

const BASE_WIDTH: float = 720.0
const BASE_HEIGHT: float = 1280.0
const MIN_FONT_SIZE: int = 14
const MAX_FONT_SIZE: int = 32

var _is_mobile: bool = false
var _screen_scale: float = 1.0

func _ready():
	_is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	_calculate_screen_scale()
	
	# 监听窗口大小变化
	get_tree().root.size_changed.connect(_on_window_resized)

func _on_window_resized():
	_calculate_screen_scale()

func _calculate_screen_scale():
	var viewport_size = get_viewport().get_visible_rect().size
	var scale_x = viewport_size.x / BASE_WIDTH
	var scale_y = viewport_size.y / BASE_HEIGHT
	_screen_scale = min(scale_x, scale_y)
	
	# 移动端最小缩放限制
	if _is_mobile and _screen_scale < 0.5:
		_screen_scale = 0.5

# 获取响应式字体大小
func get_font_size(base_size: int) -> int:
	var scaled_size = int(base_size * _screen_scale)
	return clamp(scaled_size, MIN_FONT_SIZE, MAX_FONT_SIZE)

# 获取响应式间距
func get_spacing(base_spacing: int) -> int:
	return int(base_spacing * _screen_scale)

# 获取响应式按钮尺寸
func get_button_size(base_width: float, base_height: float) -> Vector2:
	# 移动端按钮增大
	var mobile_scale = 1.2 if _is_mobile else 1.0
	return Vector2(
		base_width * _screen_scale * mobile_scale,
		base_height * _screen_scale * mobile_scale
	)

# 检查是否为移动设备
func is_mobile() -> bool:
	return _is_mobile

# 检查是否为竖屏
func is_portrait() -> bool:
	var viewport_size = get_viewport().get_visible_rect().size
	return viewport_size.y > viewport_size.x

# 获取屏幕方向建议的UI布局
func get_recommended_layout() -> String:
	if _is_mobile:
		return "portrait" if is_portrait() else "landscape_mobile"
	return "desktop"

# 调整按钮样式（移动端增大触摸区域）
func apply_mobile_button_style(button: Button, min_touch_size: Vector2 = Vector2(120, 60)):
	if not _is_mobile:
		return
	
	# 确保按钮最小触摸区域
	var current_size = button.size
	if current_size.x < min_touch_size.x or current_size.y < min_touch_size.y:
		button.custom_minimum_size = min_touch_size
	
	# 增大字体
	if button.get_theme_font_size("font_size") < 20:
		button.add_theme_font_size_override("font_size", 20)
	
	# 增加内边距
	var base_padding = 12
	button.add_theme_constant_override("icon_max_width", int(32 * _screen_scale))

# 应用安全区域到Control节点
func apply_safe_area(control: Control, margin: int = 20):
	if not (_is_mobile or OS.has_feature("web")):
		return
	
	var safe_area = DisplayServer.get_display_safe_area()
	var screen_size = DisplayServer.screen_get_size()
	
	if safe_area == Rect2i() or screen_size == Vector2i.ZERO:
		return
	
	# 根据锚点设置调整边距
	if control.anchor_left == 0:
		control.offset_left += safe_area.position.x + margin
	if control.anchor_right == 1:
		control.offset_right -= (screen_size.x - safe_area.end.x) + margin
	if control.anchor_top == 0:
		control.offset_top += safe_area.position.y + margin
	if control.anchor_bottom == 1:
		control.offset_bottom -= (screen_size.y - safe_area.end.y) + margin

# 为滚动容器添加触摸支持
func setup_touch_scroll(scroll_container: ScrollContainer):
	if not _is_mobile:
		return
	
	# 启用触摸滚动
	scroll_container.follow_focus = true
	scroll_container.scroll_horizontal_enabled = true
	scroll_container.scroll_vertical_enabled = true
	
	# 增加滚动条的触摸区域
	var h_scrollbar = scroll_container.get_h_scroll_bar()
	var v_scrollbar = scroll_container.get_v_scroll_bar()
	
	if h_scrollbar:
		h_scrollbar.custom_minimum_size.y = 16
	if v_scrollbar:
		v_scrollbar.custom_minimum_size.x = 16
