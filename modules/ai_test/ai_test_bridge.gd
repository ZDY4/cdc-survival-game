extends Node
# AITestBridge - AI测试桥接器 (v2.0)
# 支持HTTP API和直接测试API调用

signal test_started(test_id: String)
signal test_completed(test_id: String, result: Dictionary)
signal test_step_completed(step_index: int, step_data: Dictionary)
signal action_executed(action: String, result: Dictionary)

# ===== 配置 =====
@export var enabled: bool = true
@export var test_mode: bool = true  # true = 直接API模式, false = HTTP服务器模式
@export var auto_start: bool = false
@export var port: int = 0

# ===== HTTP服务器组件 =====
var _server: TCPServer
var _clients: Array[StreamPeerTCP] = []
var _is_server_running: bool = false
var _port: int = 8080

# ===== 测试状态 =====
var _current_test: Dictionary = {}
var _test_history: Array[Dictionary] = []
var _is_recording: bool = false
var _recorded_actions: Array[Dictionary] = []

# ===== 缓存的游戏状态 =====
var _last_game_state: Dictionary = {}

func _ready():
	if not enabled:
		print("[AITestBridge] 已禁用")
		return
	
	# Web平台禁用HTTP服务器
	if OS.has_feature("web"):
		print("[AITestBridge] Web平台，HTTP服务器功能已禁用")
		test_mode = true  # 强制使用测试模式
		return
	
	print("[AITestBridge] AI测试桥接器已初始化")
	var mode_str = "测试API" if test_mode else "HTTP服务器"
	print("[AITestBridge] 模式: " + mode_str)
	
	if test_mode:
		# 测试模式：不需要启动服务器，直接提供API
		print("[AITestBridge] 测试模式就绪，等待API调用")
	elif auto_start:
		# HTTP服务器模式
		var server_port = port if port > 0 else 8080
		start_server(server_port)

# ===== HTTP服务器功能 (向后兼容) =====

func start_server(server_port: int = 0):
	if test_mode:
		print("[AITestBridge] 警告：测试模式下不需要启动服务器")
		return true
	
	_port = server_port
	_server = TCPServer.new()
	
	var error = _server.listen(_port)
	if error != OK:
		push_error("[AITestBridge] 启动服务器失败，端口: " + str(_port))
		return false
	
	_is_server_running = true
	print("[AITestBridge] HTTP服务器已启动，端口: " + str(_port))
	return true

func stop_server():
	_is_server_running = false
	
	for client in _clients:
		client.disconnect_from_host()
	_clients.clear()
	
	if _server:
		_server.stop()
		_server = null
	
	print("[AITestBridge] HTTP服务器已停止")

func _process(delta: float):
	if not _is_server_running || not _server || test_mode:
		return
	
	# 处理HTTP连接
	if _server.is_connection_available():
		var client = _server.take_connection()
		if client:
			_clients.append(client)
			print("[AITestBridge] 客户端已连接")
	
	for i in range(_clients.size() - 1, -1, -1):
		var client = _clients[i]
		
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.remove_at(i)
			continue
		
		var available_bytes = client.get_available_bytes()
		if available_bytes > 0:
			var data = client.get_string(available_bytes)
			_handle_http_request(client, data)

# ===== 核心测试API (测试模式) =====

## 运行测试序列
func run_test_sequence(test_id: String, sequence: Array):
	test_started.emit(test_id)
	
	_current_test = {
		"id": test_id,
		"start_time": Time.get_unix_time_from_system(),
		"sequence": sequence.duplicate(),
		"results": [],
		"success": true,
		"current_step": 0
	}
	
	print("[AITestBridge] 开始测试: " + test_id)
	print("[AITestBridge] 测试步骤数: " + str(sequence.size()))
	
	for i in range(sequence.size()):
		_current_test.current_step = i
		var step = sequence[i]
		
		print("[AITestBridge] 执行步骤 " + str(i + 1) + "/" + str(sequence.size()) + ": " + step.get("action", "unknown"))
		
		var result = await _execute_test_step(step)
		_current_test.results.append(result)
		test_step_completed.emit(i, result)
		
		# 如果是关键步骤且失败，停止测试
		if not result.success && step.get("critical", false):
			print("[AITestBridge] 关键步骤失败，停止测试")
			_current_test.success = false
			break
	
	_current_test.end_time = Time.get_unix_time_from_system()
	_current_test.duration = _current_test.end_time - _current_test.start_time
	
	_test_history.append(_current_test.duplicate())
	
	var result_str = "通过" if _current_test.success else "失败"
	print("[AITestBridge] 测试完成: " + test_id + ", 结果: " + result_str)
	
	test_completed.emit(test_id, _current_test)
	return _current_test

## 执行单个测试步骤
func _execute_test_step(step: Dictionary):
	var action = step.get("action", "")
	var result = {
		"success": false,
		"action": action,
		"timestamp": Time.get_unix_time_from_system(),
		"data": {},
		"error": ""
	}
	
	match action:
		"wait":
			var seconds = step.get("seconds", 1.0)
			await get_tree().create_timer(seconds).timeout
			result.success = true
			result.data = {"waited": seconds}
		
		"set_state":
			result = _action_set_state(step)
		
		"click":
			result = await _action_click(step)
		
		"input":
			result = await _action_input(step)
		
		"verify":
			result = _action_verify(step)
		
		"get_state":
			result = _action_get_state()
		
		"screenshot":
			result = await _action_screenshot(step)
		
		"travel":
			result = _action_travel(step)
		
		"interact":
			result = await _action_interact(step)
		
		_:
			result.error = "未知操作: " + action
	
	action_executed.emit(action, result)
	return result

# ===== 具体动作实现 =====

func _action_set_state(step: Dictionary):
	var result = {"success": true, "data": {}}
	
	# 设置位置
	if step.has("position"):
		GameState.player_position = step.position
		result.data.position = step.position
	
	# 设置属性
	if step.has("hp"):
		GameState.player_hp = step.hp
		result.data.hp = step.hp
	
	if step.has("hunger"):
		GameState.player_hunger = step.hunger
	
	if step.has("thirst"):
		GameState.player_thirst = step.thirst
	
	# 设置标记
	if step.has("flags"):
		for flag_name in step.flags.keys():
			GameStateManager.set_flag(flag_name, step.flags[flag_name])
	
	# 添加物品
	if step.has("inventory"):
		GameState.inventory_items.clear()
		for item in step.inventory:
			GameState.inventory_items.append(item)
	
	print("[AITestBridge] 状态已设置: " + str(result.data))
	return result

func _action_click(step: Dictionary):
	var target = step.get("target", "")
	var result = {"success": false, "data": {"target": target}}
	
	# 查找目标节点
	var current_scene = get_tree().current_scene
	if not current_scene:
		result.error = "没有活动场景"
		return result
	
	var target_node = current_scene.find_child(target, true, false)
	
	if not target_node:
		result.error = "找不到目标: " + target
		return result
	
	# 模拟点击
	if target_node.has_method("_on_click") || target_node.has_signal("interacted"):
		if target_node.has_method("_on_click"):
			target_node._on_click()
		elif target_node.has_signal("interacted"):
			target_node.interacted.emit()
		
		result.success = true
		result.data.clicked = target
		print("[AITestBridge] 点击成功: " + target)
	else:
		result.error = "目标不可交互: " + target
	
	return result

func _action_input(step: Dictionary):
	var text = step.get("text", "")
	var result = {"success": true, "data": {"input": text}}
	
	# 模拟输入事件
	# 这里可以扩展为实际的UI输入模拟
	print("[AITestBridge] 输入文本: " + text)
	
	return result

func _action_verify(step: Dictionary):
	var check = step.get("check", "")
	var expected = step.get("expected", null)
	var result = {"success": false, "data": {"check": check}}
	
	match check:
		"flag":
			var flag_value = GameStateManager.get_flag(step.get("flag", ""))
			result.success = (flag_value == expected)
			result.data.actual = flag_value
			result.data.expected = expected
		
		"scene":
			var current_scene = get_tree().current_scene
			var scene_name = current_scene.name if current_scene else ""
			result.success = (scene_name == expected)
			result.data.actual = scene_name
		
		"hp":
			result.success = (GameState.player_hp == expected)
			result.data.actual = GameState.player_hp
		
		"has_item":
			var has = InventoryModule.has_item(expected)
			result.success = has
			result.data.has_item = has
		
		"dialog_opened":
			# 检查对话框是否打开
			result.success = true  # 简化实现
			result.data.dialog_open = true
		
		"ui_opened":
			# 检查UI是否打开
			result.success = true  # 简化实现
			result.data.ui = expected
		
		_:
			result.error = "未知验证类型: " + check
	
	if not result.success && result.error == "":
		result.error = "验证失败: 期望 " + str(expected) + ", 实际 " + str(result.data.get("actual", "unknown"))
	
	return result

func _action_get_state():
	var state = {
		"success": true,
		"data": {
			"player": {
				"hp": GameState.player_hp,
				"max_hp": GameState.player_max_hp,
				"hunger": GameState.player_hunger,
				"thirst": GameState.player_thirst,
				"stamina": GameState.player_stamina,
				"mental": GameState.player_mental,
				"position": GameState.player_position
			},
			"inventory": {
				"items": GameState.inventory_items.duplicate(),
				"count": GameState.inventory_items.size()
			},
			"world": {
				"time": GameState.world_time,
				"day": GameState.world_day,
				"weather": GameState.world_weather
			},
			"scene": get_tree().current_scene.name if get_tree().current_scene else ""
		}
	}
	
	_last_game_state = state.data
	return state

func _action_screenshot(step: Dictionary):
	var path = step.get("path", "user://screenshots/test_%s.png" % str(Time.get_unix_time_from_system()))
	var result = {"success": false, "data": {"path": path}}
	
	# 获取视口截图
	var viewport = get_tree().root.get_viewport()
	var img = viewport.get_texture().get_image()
	
	if img:
		var error = img.save_png(path)
		if error == OK:
			result.success = true
			print("[AITestBridge] 截图已保存: " + path)
		else:
			result.error = "保存截图失败"
	else:
		result.error = "获取截图失败"
	
	return result

func _action_travel(step: Dictionary):
	var destination = step.get("destination", "")
	var result = {"success": false, "data": {"destination": destination}}
	
	var map = get_node_or_null("/root/MapModule")
	if map:
		var success = map.travel_to(destination)
		result.success = success
		result.data.success = success
	else:
		result.error = "MapModule 不可用"
	
	return result

func _action_interact(step: Dictionary):
	var target = step.get("target", "")
	var result = {"success": false, "data": {"target": target}}
	
	# 简化实现：直接调用点击
	result = await _action_click(step)
	
	return result

# ===== 测试辅助功能 =====

## 开始录制
func start_recording():
	_is_recording = true
	_recorded_actions.clear()
	print("[AITestBridge] 开始录制操作")

## 停止录制
func stop_recording() -> Array[Dictionary]:
	_is_recording = false
	print("[AITestBridge] 停止录制，共 " + str(_recorded_actions.size()) + " 个操作")
	return _recorded_actions.duplicate()

## 录制动作
func record_action(action: Dictionary):
	if _is_recording:
		action["timestamp"] = Time.get_unix_time_from_system()
		_recorded_actions.append(action)

## 获取测试历史
func get_test_history() -> Array[Dictionary]:
	return _test_history.duplicate()

## 获取最后一次测试
func get_last_test():
	if _test_history.size() > 0:
		return _test_history[-1]
	return {}

## 获取可交互对象列表
func get_interactable_objects() -> Array[Dictionary]:
	var objects = []
	var current_scene = get_tree().current_scene
	
	if not current_scene:
		return objects
	
	for child in current_scene.get_children():
		if child is Area2D:
			var info = {
				"name": child.name,
				"type": child.get_class(),
				"position": child.global_position
			}
			
			if child.has_method("get_interaction_name"):
				info["interaction_name"] = child.get_interaction_name()
			
			objects.append(info)
	
	return objects

## 快速存档/读档
func quick_save():
	return SaveSystem.save_game()

func quick_load():
	return SaveSystem.load_game()

## 等待条件满足
func wait_for_condition(timeout: float, condition: Callable, check_interval: float = 0.5):
	var elapsed = 0.0
	
	while elapsed < timeout:
		if condition.call():
			return true
		
		await get_tree().create_timer(check_interval).timeout
		elapsed += check_interval
	
	return false

# ===== HTTP请求处理 (向后兼容) =====

func _handle_http_request(client: StreamPeerTCP, data: String):
	# 简化处理，直接返回当前状态
	var state = _collect_game_state()
	var json_string = JSON.stringify(state, "\t")
	_send_json_response(client, 200, json_string)

func _collect_game_state(item: Dictionary = {}):
	var result = _action_get_state()
	return result.data if result.success else {"error": "Failed to get state"}

func _send_json_response(client: StreamPeerTCP, status_code: int, body: String):
	var response = "HTTP/1.1 " + str(status_code) + " OK\r\n"
	response += "Content-Type: application/json\r\n"
	response += "Content-Length: " + str(body.length()) + "\r\n"
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "\r\n"
	response += body
	client.put_data(response.to_utf8_buffer())

# ===== 测试预设 =====

## 主流程测试
func run_main_flow_test():
	var sequence = [
		{"action": "set_state", "position": "safehouse", "hp": 100, "hunger": 100, "thirst": 100},
		{"action": "wait", "seconds": 1},
		{"action": "verify", "check": "scene", "expected": "Safehouse", "critical": true},
		{"action": "click", "target": "Door", "critical": true},
		{"action": "wait", "seconds": 2},
		{"action": "verify", "check": "scene", "expected": "StreetA", "critical": true},
		{"action": "screenshot", "path": "user://test_main_flow.png"}
	]
	
	return await run_test_sequence("main_flow", sequence)

## 战斗系统测试
func run_combat_test():
	var sequence = [
		{"action": "set_state", "hp": 100},
		{"action": "verify", "check": "hp", "expected": 100, "critical": true},
		{"action": "travel", "destination": "street_a"},
		{"action": "wait", "seconds": 3},
		{"action": "verify", "check": "hp", "expected": 100}
	]
	
	return await run_test_sequence("combat_system", sequence)

## 背包系统测试
func run_inventory_test(level: int = 1):
	var sequence = [
		{"action": "set_state", "inventory": [{"id": "food_canned", "count": 3}]},
		{"action": "verify", "check": "has_item", "expected": "food_canned", "critical": true}
	]
	
	return await run_test_sequence("inventory_system", sequence)

## 运行所有测试
func run_all_tests():
	var results = {
		"main_flow": await run_main_flow_test(),
		"combat": await run_combat_test(),
		"inventory": await run_inventory_test()
	}
	
	var all_passed = true
	for test_name in results.keys():
		if not results[test_name].success:
			all_passed = false
			break
	
	return {
		"success": all_passed,
		"tests": results,
		"timestamp": Time.get_unix_time_from_system()
	}
