@tool
extends GraphNode

class_name CDCDialogNode

signal data_changed(node_id: String, new_data: Dictionary)

var node_data: Dictionary = {}
var input_ports: Array[int] = []
var output_ports: Array[int] = []

func _ready():
	resizable = true
	show_close = true
	draggable = true
	selectable = true
	
	# 连接关闭按钮
	close_request.connect(_on_close_request)
	dragged.connect(_on_dragged)
	
	_update_ui()

func set_color(color: Color):
	var style = StyleBoxFlat.new()
	style.bg_color = color.darkened(0.3)
	style.border_color = color
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	add_theme_stylebox_override("titlebar", style)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = color.darkened(0.5)
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", panel_style)

func _update_ui():
	# 清除现有子节点
	for child in get_children():
		child.queue_free()
	
	input_ports.clear()
	output_ports.clear()
	
	# 根据类型创建不同的UI
	if node_data.has("type"):
		match node_data.type:
			"dialog":
				_create_dialog_ui()
			"choice":
				_create_choice_ui()
			"condition":
				_create_condition_ui()
			"action":
				_create_action_ui()
			"end":
				_create_end_ui()
			_:
				_create_default_ui()
	else:
		_create_default_ui()

func _create_dialog_ui():
	# 说话人标签
	if node_data.has("speaker"):
		var speaker_label = Label.new()
		speaker_label.text = "🎭 %s" % node_data.speaker
		speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(speaker_label)
	
	# 对话文本预览
	if node_data.has("text"):
		var text_preview = Label.new()
		text_preview.text = _truncate_text(node_data.text, 50)
		text_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_preview.custom_minimum_size = Vector2(200, 40)
		add_child(text_preview)
	
	# 头像预览
	if node_data.has("portrait") and not node_data.portrait.is_empty():
		var portrait_label = Label.new()
		portrait_label.text = "🖼️ %s" % node_data.portrait.get_file()
		portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		portrait_label.modulate = Color.GRAY
		add_child(portrait_label)

func _create_choice_ui():
	if node_data.has("options"):
		var title = Label.new()
	title.text = "选项列表 (%d个)" % node_data.options.size()
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(title)
		
		for i in range(node_data.options.size()):
			var option = node_data.options[i]
			var option_label = Label.new()
			option_label.text = "%d. %s" % [i + 1, _truncate_text(option.text, 25)]
			option_label.modulate = Color.LIGHT_GRAY
			add_child(option_label)

func _create_condition_ui():
	var icon = Label.new()
	icon.text = "🔀 条件判断"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(icon)
	
	if node_data.has("condition"):
		var cond_label = Label.new()
		cond_label.text = _truncate_text(node_data.condition, 40)
		cond_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cond_label.custom_minimum_size = Vector2(200, 40)
		cond_label.modulate = Color.YELLOW
		add_child(cond_label)

func _create_action_ui():
	var icon = Label.new()
	icon.text = "⚡ 动作节点"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(icon)
	
	if node_data.has("actions"):
		var count = node_data.actions.size()
		var label = Label.new()
		label.text = "包含 %d 个动作" % count
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.modulate = Color.GREEN
		add_child(label)

func _create_end_ui():
	var icon = Label.new()
	icon.text = "🏁 对话结束"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.modulate = Color.RED
	add_child(icon)
	
	if node_data.has("end_type"):
		var type_label = Label.new()
		type_label.text = "类型: %s" % node_data.end_type
		type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		type_label.modulate = Color.GRAY
		add_child(type_label)

func _create_default_ui():
	var label = Label.new()
	label.text = "节点数据缺失"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)

func _truncate_text(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 3) + "..."

# 端口管理
func add_input_port(name: String, type: int = 0):
	var idx = get_child_count()
	input_ports.append(idx)
	set_slot_enabled_left(idx, true)
	set_slot_type_left(idx, type)
	set_slot_color_left(idx, Color.WHITE)

func add_output_port(name: String, type: int = 0):
	var idx = get_child_count()
	output_ports.append(idx)
	set_slot_enabled_right(idx, true)
	set_slot_type_right(idx, type)
	set_slot_color_right(idx, Color.WHITE)

# 回调函数
func _on_close_request():
	queue_free()

func _on_dragged(from: Vector2, to: Vector2):
	if node_data.has("position"):
		node_data.position = to
		data_changed.emit(node_data.id, node_data)

# 数据更新
func update_data(new_data: Dictionary):
	node_data = new_data
	_update_ui()
