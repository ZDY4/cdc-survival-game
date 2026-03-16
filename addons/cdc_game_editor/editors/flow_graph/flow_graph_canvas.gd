@tool
extends GraphEdit

signal node_double_clicked(node_id: String)
signal connection_created(from: String, to: String)
signal add_node_requested(node_type: String, graph_position: Vector2, pending_connection: Dictionary)

var grid_size: int = 20
var grid_snap: bool = true
var node_type_definitions: Array[Dictionary] = []

func _ready() -> void:
	show_grid = true
	if _has_property("snapping_distance"):
		set("snapping_distance", grid_size)
	connection_lines_curvature = 0.5
	connection_lines_thickness = 2.0

	add_theme_color_override("grid_major", Color(0.3, 0.3, 0.3, 0.3))
	add_theme_color_override("grid_minor", Color(0.2, 0.2, 0.2, 0.2))

	if has_signal("connection_to_empty"):
		connection_to_empty.connect(_on_connection_to_empty)
	if has_signal("connection_from_empty"):
		connection_from_empty.connect(_on_connection_from_empty)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			var node := get_node_at_position(event.position)
			if node:
				node_double_clicked.emit(String(node.name))
			return

		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_context_menu(event.position)
			accept_event()
			return

func get_node_at_position(pos: Vector2) -> Node:
	for child in get_children():
		if child is GraphNode and child.get_rect().has_point(pos + scroll_offset):
			return child
	return null

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if from_node == to_node:
		return

	for conn in get_connection_list():
		if conn.from == from_node and conn.from_port == from_port and conn.to == to_node and conn.to_port == to_port:
			return

	connect_node(from_node, from_port, to_node, to_port)
	connection_created.emit(String(from_node), String(to_node))

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)

func _on_connection_to_empty(from_node: StringName, from_port: int, release_position: Vector2) -> void:
	_show_context_menu(release_position, {
		"direction": "from_output",
		"node_id": String(from_node),
		"port": from_port
	})

func _on_connection_from_empty(to_node: StringName, to_port: int, release_position: Vector2) -> void:
	_show_context_menu(release_position, {
		"direction": "to_input",
		"node_id": String(to_node),
		"port": to_port
	})

func _on_delete_nodes_request(nodes_to_delete: Array) -> void:
	for node_name in nodes_to_delete:
		var node := get_node_or_null(String(node_name))
		if node:
			_remove_node_connections(String(node_name))
			node.queue_free()

func _remove_node_connections(node_name: String) -> void:
	for conn in get_connection_list():
		if conn.from == node_name or conn.to == node_name:
			disconnect_node(StringName(conn.from), conn.from_port, StringName(conn.to), conn.to_port)

func _on_duplicate_nodes_request() -> void:
	pass

func _on_copy_nodes_request() -> void:
	pass

func _on_paste_nodes_request() -> void:
	pass

func get_selected_nodes() -> Array[GraphNode]:
	var result: Array[GraphNode] = []
	for child in get_children():
		if child is GraphNode and child.selected:
			result.append(child)
	return result

func clear_graph() -> void:
	for conn in get_connection_list():
		disconnect_node(
			StringName(str(conn.get("from", ""))),
			int(conn.get("from_port", 0)),
			StringName(str(conn.get("to", ""))),
			int(conn.get("to_port", 0))
		)

	for child in get_children():
		if child is GraphNode:
			child.queue_free()

func get_all_nodes() -> Array[GraphNode]:
	var result: Array[GraphNode] = []
	for child in get_children():
		if child is GraphNode:
			result.append(child)
	return result

func center_view() -> void:
	var all_nodes := get_all_nodes()
	if all_nodes.is_empty():
		return

	var rect := Rect2(all_nodes[0].position_offset, all_nodes[0].size)
	for i in range(1, all_nodes.size()):
		rect = rect.merge(Rect2(all_nodes[i].position_offset, all_nodes[i].size))

	scroll_offset = rect.get_center() - size / 2

func _show_context_menu(pos: Vector2, pending_connection: Dictionary = {}) -> void:
	if node_type_definitions.is_empty():
		return

	var menu := PopupMenu.new()
	for i in range(node_type_definitions.size()):
		var def: Dictionary = node_type_definitions[i]
		menu.add_item(str(def.get("name", def.get("type", "节点"))), i)

	menu.add_separator()
	menu.add_item("居中视图", 9999)

	menu.id_pressed.connect(func(id: int):
		if id == 9999:
			center_view()
		elif id >= 0 and id < node_type_definitions.size():
			var def: Dictionary = node_type_definitions[id]
			_context_add_node(str(def.get("type", "")), pos, pending_connection)
		menu.queue_free()
	)

	add_child(menu)
	menu.position = DisplayServer.mouse_get_position()
	menu.popup()

func _context_add_node(node_type: String, pos: Vector2, pending_connection: Dictionary = {}) -> void:
	if node_type.is_empty():
		return
	call_deferred("_deferred_emit_add_node_request", node_type, _canvas_to_graph_position(pos), pending_connection)

func _deferred_emit_add_node_request(node_type: String, graph_position: Vector2, pending_connection: Dictionary = {}) -> void:
	add_node_requested.emit(node_type, graph_position, pending_connection)

func _canvas_to_graph_position(pos: Vector2) -> Vector2:
	var zoom_scale := 1.0
	if _has_property("zoom"):
		zoom_scale = float(get("zoom"))
	if is_zero_approx(zoom_scale):
		zoom_scale = 1.0
	return scroll_offset + (pos / zoom_scale)

func _has_property(property_name: String) -> bool:
	for property_info_variant in get_property_list():
		if not (property_info_variant is Dictionary):
			continue
		var property_info: Dictionary = property_info_variant
		if str(property_info.get("name", "")) == property_name:
			return true
	return false
