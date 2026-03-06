@tool
extends GraphNode
## 任务节点

# 任务数据
var quest_id: String = ""
var quest_data: Dictionary = {}
var is_start_quest: bool = false
var is_completed: bool = false

# 依赖连接
var prerequisites: Array[String] = []
var unlocks: Array[String] = []

# 节点颜色
const COLOR_NORMAL = Color(0.3, 0.5, 0.8)
const COLOR_START = Color(0.2, 0.8, 0.4)
const COLOR_COMPLETED = Color(0.5, 0.5, 0.5)
const COLOR_LOCKED = Color(0.8, 0.4, 0.2)

signal quest_selected(quest_id: String)
signal quest_double_clicked(quest_id: String)

func _ready():
	resizable = false
	set("show_close", false)
	set("draggable", true)
	set("selectable", true)
	
	custom_minimum_size = Vector2(200, 120)
	
	# 设置视觉样式
	_update_appearance()
	
	# 连接信号
	gui_input.connect(_on_gui_input)

func setup(quest: Dictionary):
	quest_data = quest
	quest_id = quest.get("quest_id", "")
	title = quest.get("title", "Unnamed Quest")
	
	_update_ui()
	_update_appearance()

func _update_ui():
	# 清除现有子节
	for child in get_children():
		child.queue_free()
	
	# 任务ID
	var id_label = Label.new()
	id_label.text = quest_id
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	id_label.modulate = Color.GRAY
	add_child(id_label)
	
	# 分隔
	add_child(HSeparator.new())
	
	# 任务描述预览
	var desc = quest_data.get("description", "")
	var desc_label = Label.new()
	desc_label.text = _truncate_text(desc, 60)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(180, 40)
	add_child(desc_label)
	
	# 目标数量
	var objectives = quest_data.get("objectives", [])
	var obj_label = Label.new()
	obj_label.text = "Objectives: %d" % objectives.size()
	obj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	obj_label.modulate = Color.LIGHT_BLUE
	add_child(obj_label)
	
	# 奖励预览
	var rewards = quest_data.get("rewards", {})
	var exp = rewards.get("experience", 0)
	var items = rewards.get("items", [])
	
	var reward_label = Label.new()
	if items.size() > 0:
		reward_label.text = "奖励: %d经验 + %d物品" % [exp, items.size()]
	else:
		reward_label.text = "奖励: %d经验" % exp
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_label.modulate = Color.GREEN
	add_child(reward_label)
	
	# 输入/输出端口
	_add_ports()

func _add_ports():
	# 左侧输入端口（前置任务连接）
	var has_prereq = quest_data.get("prerequisites", []).size() > 0
	set_slot_enabled_left(0, has_prereq)
	set_slot_color_left(0, Color.GRAY)
	
	# 右侧输出端口（解锁后续任务）
	set_slot_enabled_right(get_child_count() - 1, true)
	set_slot_color_right(get_child_count() - 1, Color.YELLOW)

func _update_appearance():
	var base_color = COLOR_NORMAL
	
	if is_start_quest:
		base_color = COLOR_START
	elif is_completed:
		base_color = COLOR_COMPLETED
	elif prerequisites.size() > 0 and not _check_prerequisites():
		base_color = COLOR_LOCKED
	
	# 标栏样
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = base_color.darkened(0.3)
	title_style.border_color = base_color
	title_style.border_width_left = 2
	title_style.border_width_right = 2
	title_style.border_width_top = 2
	title_style.corner_radius_top_left = 8
	title_style.corner_radius_top_right = 8
	add_theme_stylebox_override("titlebar", title_style)
	
	# 面板样式
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = base_color.darkened(0.6)
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", panel_style)

func _check_prerequisites() -> bool:
	# 检查前置任务是否已完成
	# 这里要务系统，化实
	return true

func _truncate_text(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 3) + "..."

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				quest_selected.emit(quest_id)
			elif event.double_click:
				quest_double_clicked.emit(quest_id)

func set_completed(completed: bool):
	is_completed = completed
	_update_appearance()

func set_start_quest(start: bool):
	is_start_quest = start
	_update_appearance()

func add_prerequisite(prereq_id: String):
	if prereq_id not in prerequisites:
		prerequisites.append(prereq_id)
		_update_appearance()

func remove_prerequisite(prereq_id: String):
	prerequisites.erase(prereq_id)
	_update_appearance()

func add_unlock(quest_id_to_unlock: String):
	if quest_id_to_unlock not in unlocks:
		unlocks.append(quest_id_to_unlock)

func remove_unlock(quest_id_to_unlock: String):
	unlocks.erase(quest_id_to_unlock)

# 序列反序列化
func to_dict() -> Dictionary:
	return {
		"quest_id": quest_id,
		"position": {
			"x": position_offset.x,
			"y": position_offset.y
		},
		"is_start_quest": is_start_quest,
		"is_completed": is_completed
	}

func from_dict(data: Dictionary):
	position_offset = Vector2(data.get("position", {}).get("x", 0), 
		data.get("position", {}).get("y", 0))
	is_start_quest = data.get("is_start_quest", false)
	is_completed = data.get("is_completed", false)
	_update_appearance()
