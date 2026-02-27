extends Node
# GodotMCPBridge - Godot端MCP桥接
# 允许外部通过Socket控制Godot（Web平台禁用）

const PORT = 9742

var _server: TCPServer
var _clients: Array[StreamPeerTCP] = []
var _is_running: bool = false

func _ready():
	# Web平台不支持TCP服务器，禁用MCP
	if OS.has_feature("web"):
		print("[GodotMCPBridge] Web平台，MCP功能已禁用")
		set_process(false)
		return
	
	print("[GodotMCPBridge] 初始化...")
	_start_server()

func _start_server():
	_server = TCPServer.new()
	var err = _server.listen(PORT)
	if err != OK:
		push_error("[GodotMCPBridge] 无法启动服务器，端口: " + str(PORT))
		return
	
	_is_running = true
	print("[GodotMCPBridge] 服务器已启动，端口: " + str(PORT))

func _process(delta: float):
	if not _is_running:
		return
	
	# 接受新连接
	if _server.is_connection_available():
		var client = _server.take_connection()
		_clients.append(client)
		print("[GodotMCPBridge] 新客户端连接")
		_send_response(client, {"status": "connected", "godot_version": Engine.get_version_info()})
	
	# 处理客户端消息
	for i in range(_clients.size() - 1, -1, -1):
		var client = _clients[i]
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.remove_at(i)
			continue
		
		var available = client.get_available_bytes()
		if available > 0:
			var data = client.get_utf8_string(available)
			_handle_message(client, data)

func _handle_message(client: StreamPeerTCP, data: String):
	var json = JSON.new()
	var err = json.parse(data)
	if err != OK:
		_send_error(client, "JSON解析错误")
		return
	
	var request = json.get_data()
	var method = request.get("method", "")
	var params = request.get("params", {})
	
	print("[GodotMCPBridge] 收到命令: " + method)
	
	match method:
		"get_scene_info":
			_get_scene_info(client)
		"get_node_info":
			_get_node_info(client, params.get("node_path", ""))
		"get_carry_info":
			_get_carry_info(client)
		"add_item":
			_add_item(client, params)
		"take_screenshot":
			_take_screenshot(client)
		_:
			_send_error(client, "未知方法: " + method)

func _get_scene_info(client):
	var current_scene = get_tree().current_scene
	var info = {}
	
	if current_scene:
		info["scene_name"] = current_scene.name
		info["scene_path"] = current_scene.scene_file_path
	else:
		info["scene_name"] = "null"
		info["scene_path"] = ""
	
	info["node_count"] = _count_nodes(get_tree().root)
	_send_response(client, info)

func _get_node_info(client: StreamPeerTCP, node_path: String):
	var node = get_node_or_null(node_path)
	if not node:
		_send_error(client, "节点不存在: " + node_path)
		return
	
	var visible_value = null
	if node.has_method("is_visible"):
		visible_value = node.visible
	
	var info = {
		"name": node.name,
		"class": node.get_class(),
		"visible": visible_value,
		"position": [node.position.x, node.position.y] if node is Node2D else null
	}
	_send_response(client, info)

func _get_carry_info(client: StreamPeerTCP):
	if not CarrySystem:
		_send_error(client, "CarrySystem未加载")
		return
	
	var info = {
		"current_weight": CarrySystem.get_current_weight(),
		"max_weight": CarrySystem.get_max_carry_weight(),
		"ratio": CarrySystem.get_weight_ratio(),
		"level": CarrySystem.get_encumbrance_name(),
		"movement_penalty": CarrySystem.get_movement_penalty()
	}
	_send_response(client, info)

func _add_item(client: StreamPeerTCP, params: Dictionary):
	var item_id = params.get("item_id", "")
	var count = params.get("count", 1)
	
	if GameState:
		var success = GameState.add_item(item_id, count)
		CarrySystem.on_inventory_changed()
		_send_response(client, {"success": success, "item": item_id, "count": count})
	else:
		_send_error(client, "GameState未加载")

func _take_screenshot(client: StreamPeerTCP):
	var viewport = get_viewport()
	var img = viewport.get_texture().get_image()
	var path = "user://screenshot_" + str(Time.get_unix_time_from_system()) + ".png"
	img.save_png(path)
	_send_response(client, {"screenshot_path": path})

func _count_nodes(node: Node):
	var count = 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count

func _send_response(client: StreamPeerTCP, data: Dictionary):
	var response = {
		"status": "ok",
		"data": data
	}
	client.put_utf8_string(JSON.stringify(response) + "\n")

func _send_error(client: StreamPeerTCP, message: String):
	var response = {
		"status": "error",
		"message": message
	}
	client.put_utf8_string(JSON.stringify(response) + "\n")
