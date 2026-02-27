extends TextureButton
class_name MapLocation
## 地图上的地点标记
## 拖放到 WorldMap 中，在 Inspector 设置 location_id

@export var location_id: String = "":
	set(value):
		location_id = value
		_update_display()

@export var icon_normal: Texture2D
@export var icon_hover: Texture2D
@export var icon_disabled: Texture2D

var _location_data: Dictionary = {}

func _ready():
	_update_display()
	_connect_signals()

func _update_display():
	# 加载地点数据
	_load_location_data()
	
	# 更新图标
	if _location_data.is_empty():
		# 数据未找到，显示错误状态
		modulate = Color.RED
		tooltip_text = "错误: 未找到地点 '%s'" % location_id
		return
	
	# 设置图标
	texture_normal = icon_normal
	texture_hover = icon_hover if icon_hover else icon_normal
	texture_disabled = icon_disabled if icon_disabled else icon_normal
	
	# 设置提示
	var name = _location_data.get("name", location_id)
	var desc = _location_data.get("description", "")
	tooltip_text = "%s\n%s" % [name, desc]
	
	# 检查解锁状态
	var is_unlocked = _check_unlocked()
	if not is_unlocked:
		disabled = true
		modulate = Color(0.5, 0.5, 0.5, 0.5)  # 半透明灰色
	else:
		disabled = false
		modulate = Color.WHITE

func _load_location_data():
	if location_id.is_empty():
		_location_data = {}
		return
	
	# 从 MapModule 或 DataManager 获取数据
	if MapModule:
		var all_data = MapModule._get_location_data()
		_location_data = all_data.get(location_id, {})
	else:
		# 编辑器模式下，直接读取配置表
		_location_data = _load_from_config()

func _load_from_config() -> Dictionary:
	# 编辑器模式下读取配置
	var file_path = "res://data/json/map_locations.json"
	if not FileAccess.file_exists(file_path):
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		return {}
	
	return json.data.get(location_id, {})

func _check_unlocked() -> bool:
	if Engine.is_editor_hint():
		return true  # 编辑器中总是显示
	
	if GameState:
		return location_id in GameState.world_unlocked_locations
	return true

func _connect_signals():
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)

func _on_pressed():
	print("[MapLocation] 点击地点: %s" % location_id)
	# 发送信号给父节点 WorldMap
	get_parent().emit_signal("location_selected", location_id, self)

func _on_hover():
	# 可以添加额外的悬停效果
	pass

func _on_unhover():
	pass

## 获取地点完整数据
func get_location_data() -> Dictionary:
	return _location_data

## 获取地点名称
func get_location_name() -> String:
	return _location_data.get("name", location_id)

## 检查是否已解锁
func is_unlocked() -> bool:
	return _check_unlocked()

## 刷新显示（用于解锁状态变化时）
func refresh():
	_update_display()
