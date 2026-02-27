extends Node
# TouchInputHandler - 触摸输入处理（支持鼠标和触摸）

signal touch_pressed(position: Vector2)
signal touch_released(position: Vector2)
signal touch_dragged(position: Vector2, relative: Vector2)
signal touch_cancelled

var _is_touch_device: bool = false
var _touch_positions: Dictionary = {}
var _last_touch_position: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _drag_threshold: float = 10.0

func _ready():
	# 检测是否为触摸设备
	_is_touch_device = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	
	# 设置输入处理
	set_process_input(true)

func _input(event: InputEvent):
	# 处理鼠标输入（桌面端）
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	
	# 处理触摸输入（移动端）
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)

func _handle_mouse_button(event: InputEventMouseButton):
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_touch_positions[0] = event.position
			_last_touch_position = event.position
			_is_dragging = false
			touch_pressed.emit(event.position)
		else:
			if _touch_positions.has(0):
				_touch_positions.erase(0)
				if not _is_dragging:
					touch_released.emit(event.position)
				_is_dragging = false

func _handle_mouse_motion(event: InputEventMouseMotion):
	if _touch_positions.has(0):
		var distance = event.position.distance_to(_last_touch_position)
		if distance > _drag_threshold:
			_is_dragging = true
			touch_dragged.emit(event.position, event.relative)
		_last_touch_position = event.position

func _handle_screen_touch(event: InputEventScreenTouch):
	if event.pressed:
		_touch_positions[event.index] = event.position
		_last_touch_position = event.position
		_is_dragging = false
		touch_pressed.emit(event.position)
	else:
		if _touch_positions.has(event.index):
			_touch_positions.erase(event.index)
			if not _is_dragging:
				touch_released.emit(event.position)
			_is_dragging = false

func _handle_screen_drag(event: InputEventScreenDrag):
	if _touch_positions.has(event.index):
		var distance = event.position.distance_to(_last_touch_position)
		if distance > _drag_threshold:
			_is_dragging = true
			touch_dragged.emit(event.position, event.relative)
		_last_touch_position = event.position

# 检查是否为触摸设备
func is_touch_device() -> bool:
	return _is_touch_device or DisplayServer.is_touchscreen_available()

# 获取当前触摸点数量
func get_touch_count() -> int:
	return _touch_positions.size()

# 检查是否有活跃触摸
func is_touching() -> bool:
	return _touch_positions.size() > 0

# 阻止触摸事件的默认行为（防止页面滚动）
func prevent_default_scroll():
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js_bridge = Engine.get_singleton("JavaScriptBridge")
		var js_code = """
			document.body.style.overflow = 'hidden';
			document.body.style.position = 'fixed';
			document.body.style.touchAction = 'none';
			var canvas = document.querySelector('canvas');
			if (canvas) {
				canvas.style.touchAction = 'none';
			}
		"""
		js_bridge.eval(js_code)

# 恢复触摸事件的默认行为
func restore_default_scroll():
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js_bridge = Engine.get_singleton("JavaScriptBridge")
		var js_code = """
			document.body.style.overflow = '';
			document.body.style.position = '';
			document.body.style.touchAction = '';
			var canvas = document.querySelector('canvas');
			if (canvas) {
				canvas.style.touchAction = '';
			}
		"""
		js_bridge.eval(js_code)
