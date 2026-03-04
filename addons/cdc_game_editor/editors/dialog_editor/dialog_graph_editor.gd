@tool
extends GraphEdit

# 自定义信号
signal node_double_clicked(node_id: String)
signal connection_created(from: String, to: String)

# 网格设置
var grid_size: int = 20
var grid_snap: bool = true

func _ready():
	# 设置视觉样式
	show_grid = true
	# Godot 4.x 使用 snapping_distance 代替 snap_distance
	if "snapping_distance" in self:
		set("snapping_distance", grid_size)
	connection_lines_curvature = 0.5
	connection_lines_thickness = 2.0
	
	# 设置网格颜色
	add_theme_color_override("grid_major", Color(0.3, 0.3, 0.3, 0.3))
	add_theme_color_override("grid_minor", Color(0.2, 0.2, 0.2, 0.2))
	
	# 连接信号
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	connection_to_empty.connect(_on_connection_to_empty)
	connection_from_empty.connect(_on_connection_from_empty)
	delete_nodes_request.connect(_on_delete_nodes_request)
	duplicate_nodes_request.connect(_on_duplicate_nodes_request)
	copy_nodes_request.connect(_on_copy_nodes_request)
	paste_nodes_request.connect(_on_paste_nodes_request)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			# 处理双击事件
			var node = get_node_at_position(event.position)
			if node:
				node_double_clicked.emit(node.name)
			return
		
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_context_menu(event.position)
			return

func get_node_at_position(pos: Vector2) -> Node:
	for child in get_children():
		if child is GraphNode:
			if child.get_rect().has_point(pos + scroll_offset):
				return child
	return null

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	# 验证连接是否有效
	if from_node == to_node:
		return  # 不能连接到自己
	
	# 检查是否已存在相同连接
	for conn in get_connection_list():
		if conn.from == from_node and conn.from_port == from_port:
			if conn.to == to_node and conn.to_port == to_port:
				return
	
	connect_node(from_node, from_port, to_node, to_port)
	connection_created.emit(String(from_node), String(to_node))

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	disconnect_node(from_node, from_port, to_node, to_port)

func _on_connection_to_empty(from_node: StringName, from_port: int, release_position: Vector2):
	# 连接到空白处的处理
	pass

func _on_connection_from_empty(to_node: StringName, to_port: int, release_position: Vector2):
	# 从空白处连接到节点的处理
	pass

func _on_delete_nodes_request(nodes_to_delete: Array):
	for node_name in nodes_to_delete:
		var node = get_node_or_null(String(node_name))
		if node:
			# 先断开所有连接
			_remove_node_connections(String(node_name))
			node.queue_free()

func _remove_node_connections(node_name: String):
	for conn in get_connection_list():
		if conn.from == node_name or conn.to == node_name:
			disconnect_node(StringName(conn.from), conn.from_port, 
				StringName(conn.to), conn.to_port)

func _on_duplicate_nodes_request():
	var selected = get_selected_nodes()
	# TODO: 实现节点复制

func _on_copy_nodes_request():
	var selected = get_selected_nodes()
	# TODO: 实现复制到剪贴板

func _on_paste_nodes_request():
	# TODO: 实现从剪贴板粘贴
	pass

func get_selected_nodes() -> Array[GraphNode]:
	var result: Array[GraphNode] = []
	for child in get_children():
		if child is GraphNode and child.selected:
			result.append(child)
	return result

func clear_graph():
	# 清除所有连接
	for conn in get_connection_list():
		disconnect_node(StringName(conn.from), conn.from_port, 
			StringName(conn.to), conn.to_port)
	
	# 清除所有节点
	for child in get_children():
		if child is GraphNode:
			child.queue_free()

func get_all_nodes() -> Array[GraphNode]:
	var result: Array[GraphNode] = []
	for child in get_children():
		if child is GraphNode:
			result.append(child)
	return result

func center_view():
	var nodes = get_all_nodes()
	if nodes.is_empty():
		return
	
	var rect = Rect2(nodes[0].position_offset, nodes[0].size)
	for i in range(1, nodes.size()):
		rect = rect.merge(Rect2(nodes[i].position_offset, nodes[i].size))
	
	var center = rect.get_center()
	scroll_offset = center - size / 2

func _show_context_menu(pos: Vector2):
	var menu = PopupMenu.new()
	menu.add_item("添加对话节点", 0)
	menu.add_item("添加选择节点", 1)
	menu.add_item("添加条件节点", 2)
	menu.add_item("添加动作节点", 3)
	menu.add_item("添加结束节点", 4)
	menu.add_separator()
	menu.add_item("居中视图", 10)
	
	menu.id_pressed.connect(func(id):
		match id:
			0, 1, 2, 3, 4:
				_context_add_node(id, pos)
			10:
				center_view()
	)
	
	add_child(menu)
	menu.position = get_global_mouse_position()
	menu.popup()

func _context_add_node(type_id: int, pos: Vector2):
	var type_map = {0: "dialog", 1: "choice", 2: "condition", 3: "action", 4: "end"}
	var type = type_map.get(type_id, "dialog")
	
	# 触发信号让父节点处理
	# 这里使用 call_deferred 来避免在输入处理中创建节点的问题
	call_deferred("_emit_add_node_request", type, pos + scroll_offset)

func _emit_add_node_request(type: String, pos: Vector2):
	# 这个函数会被编辑器主类连接
	pass
