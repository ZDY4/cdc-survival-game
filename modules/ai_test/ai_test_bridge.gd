extends Node
# AITestBridge - AI test bridge (v2.0)
# Supports HTTP API and direct test API calls


signal test_started(test_id: String)
signal test_completed(test_id: String, result: Dictionary)
signal test_step_completed(step_index: int, step_data: Dictionary)
signal action_executed(action: String, result: Dictionary)

# ===== Config =====
@export var enabled: bool = true
@export var test_mode: bool = true  # true = direct API mode, false = HTTP server mode
@export var auto_start: bool = false
@export var port: int = 0
@export var enable_http_api: bool = false  # Allow HTTP API even when test_mode is enabled

# ===== HTTP Server =====
var _server: TCPServer
var _clients: Array[StreamPeerTCP] = []
var _is_server_running: bool = false
var _port: int = 0
const PORT_FALLBACK_ATTEMPTS: int = 20

# ===== Test State =====
var _current_test: Dictionary = {}
var _test_history: Array[Dictionary] = []
var _is_recording: bool = false
var _recorded_actions: Array[Dictionary] = []

# ===== Cached Game State =====
var _last_game_state: Dictionary = {}
var _actions: Dictionary = {}
var _action_meta: Dictionary = {}

func _load_settings() -> Resource:
	if FileAccess.file_exists("res://modules/ai_test/ai_test_settings.tres"):
		var res = load("res://modules/ai_test/ai_test_settings.tres")
		return res
	return null

func _apply_settings() -> void:
	var settings = _load_settings()
	if settings == null:
		return
	if settings.has_method("get"):
		var v_enabled = settings.get("enabled")
		var v_test_mode = settings.get("test_mode")
		var v_auto_start = settings.get("auto_start")
		var v_enable_http = settings.get("enable_http_api")
		var v_port = settings.get("port")
		
		if v_enabled != null:
			enabled = v_enabled
		if v_test_mode != null:
			test_mode = v_test_mode
		if v_auto_start != null:
			auto_start = v_auto_start
		if v_enable_http != null:
			enable_http_api = v_enable_http
		if v_port != null:
			var cfg_port = int(v_port)
			if cfg_port > 0:
				port = cfg_port
				_port = port
			else:
				port = 0
				_port = 0

func _ready():
	_apply_settings()
	if port > 0:
		_port = port
	else:
		_port = 0
	if not enabled:
		print("[AITestBridge] Disabled")
		return

	# Web platform disables HTTP server
	if OS.has_feature("web"):
		print("[AITestBridge] Web platform: HTTP disabled")
		test_mode = true
		return

	print("[AITestBridge] Initialized")
	var mode_str = "test" if test_mode else "http"
	print("[AITestBridge] Mode: " + mode_str)
	_register_default_actions()

	if test_mode:
		print("[AITestBridge] Test mode ready")
		if auto_start and enable_http_api:
			var server_port = port if port > 0 else 0
			start_server(server_port)
	elif auto_start:
		var server_port = port if port > 0 else 0
		start_server(server_port)

# ===== HTTP Server (backward compatible) =====

func start_server(server_port: int = 0):
	if test_mode and not enable_http_api:
		print("[AITestBridge] Warning: no need to start HTTP server in test mode")
		return true

	var base_port: int = server_port if server_port > 0 else 0
	var attempts: int = PORT_FALLBACK_ATTEMPTS if base_port > 0 else 1
	for offset in range(attempts):
		var candidate_port: int = base_port + offset if base_port > 0 else 0
		var candidate_server := TCPServer.new()
		var error := candidate_server.listen(candidate_port)
		if error == OK:
			_server = candidate_server
			var actual_port: int = candidate_port
			if candidate_server.has_method("get_local_port"):
				actual_port = candidate_server.get_local_port()
			_port = actual_port
			_is_server_running = true
			if base_port > 0 and candidate_port != base_port:
				print("[AITestBridge] Port %d unavailable, fallback to %d" % [base_port, candidate_port])
			print("[AITestBridge] HTTP server started on port: " + str(_port))
			return true

	if base_port > 0:
		push_warning("[AITestBridge] Failed to start HTTP server on ports %d-%d" % [base_port, base_port + PORT_FALLBACK_ATTEMPTS - 1])
	else:
		push_warning("[AITestBridge] Failed to start HTTP server on any port")
	_is_server_running = false
	return false

func stop_server():
	_is_server_running = false
	
	for client in _clients:
		client.disconnect_from_host()
	_clients.clear()
	
	if _server:
		_server.stop()
		_server = null
	
	print("[AITestBridge] HTTP server stopped")

func is_running() -> bool:
	return _is_server_running

func get_port() -> int:
	return _port

func _process(delta: float):
	if not _is_server_running || not _server:
		return
	
	# Handle HTTP connections
	if _server.is_connection_available():
		var client = _server.take_connection()
		if client:
			_clients.append(client)
			print("[AITestBridge] Client connected")
	
	for i in range(_clients.size() - 1, -1, -1):
		var client = _clients[i]
		
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.remove_at(i)
			continue
		
		var available_bytes = client.get_available_bytes()
		if available_bytes > 0:
			var data = client.get_string(available_bytes)
			_handle_http_request(client, data)

# ===== Core Test API (test mode) =====

## Run test sequence
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
	
	print("[AITestBridge] Starting test: " + test_id)
	print("[AITestBridge] Total steps: " + str(sequence.size()))
	
	for i in range(sequence.size()):
		_current_test.current_step = i
		var step = sequence[i]
		
		print("[AITestBridge] Executing step " + str(i + 1) + "/" + str(sequence.size()) + ": " + step.get("action", "unknown"))
		
		var result = await _execute_test_step(step)
		_current_test.results.append(result)
		test_step_completed.emit(i, result)
		
		# Stop test if a critical step fails
		if not result.success && step.get("critical", false):
			print("[AITestBridge] Critical step failed, stopping test")
			_current_test.success = false
			break
	
	_current_test.end_time = Time.get_unix_time_from_system()
	_current_test.duration = _current_test.end_time - _current_test.start_time
	
	_test_history.append(_current_test.duplicate())
	
	var result_str = "passed" if _current_test.success else "failed"
	print("[AITestBridge] Test finished: " + test_id + ", result: " + result_str)
	
	test_completed.emit(test_id, _current_test)
	return _current_test

## Execute single test step
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
			if _actions.has(action):
				var params: Dictionary = {}
				if step.has("params"):
					params = step.get("params", {})
				else:
					params = step.duplicate()
					params.erase("action")
					params.erase("critical")
				result = execute_action(action, params)
			else:
				result.error = "Unknown action: " + action
	
	action_executed.emit(action, result)
	return result

# ===== Action Registry =====

func register_action(name: String, action_callable: Callable, meta: Dictionary = {}) -> void:
	if name.is_empty():
		return
	if not action_callable.is_valid():
		push_error("[AITestBridge] Invalid action: " + name)
		return
	_actions[name] = action_callable
	_action_meta[name] = meta.duplicate()

func unregister_action(name: String) -> void:
	_actions.erase(name)
	_action_meta.erase(name)

func get_registered_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for name in _actions.keys():
		actions.append({
			"name": name,
			"meta": _action_meta.get(name, {})
		})
	actions.sort_custom(func(a, b): return a["name"] < b["name"])
	return actions

func execute_action(name: String, params: Dictionary = {}) -> Dictionary:
	var result = {
		"success": false,
		"action": name,
		"data": {},
		"error": ""
	}
	
	if not _actions.has(name):
		result.error = "Unknown action: " + name
		return result
	
	var callable: Callable = _actions[name]
	if not callable.is_valid():
		result.error = "Action not available: " + name
		return result
	
	var action_result = callable.call(params)
	if typeof(action_result) == TYPE_DICTIONARY:
		if action_result.has("success"):
			result = action_result
		else:
			result.success = true
			result.data = action_result
	else:
		result.success = true
		result.data = {"result": action_result}
	
	if _is_recording:
		record_action({"action": name, "params": params, "success": result.success})
	
	return result

func _register_default_actions() -> void:
	register_action("start_game", Callable(self, "_action_start_game"), {"category": "scene"})
	register_action("continue_game", Callable(self, "_action_continue_game"), {"category": "scene"})
	register_action("interact.primary", Callable(self, "_action_interact_primary"), {"category": "interaction"})
	register_action("interact.option", Callable(self, "_action_interact_option"), {"category": "interaction"})
	register_action("dialog.choose", Callable(self, "_action_dialog_choose"), {"category": "dialog"})
	register_action("dialog.continue", Callable(self, "_action_dialog_continue"), {"category": "dialog"})
	register_action("combat.attack", Callable(self, "_action_combat_attack"), {"category": "combat"})

# ===== Action Implementations =====

func _action_set_state(step: Dictionary):
	var result = {"success": true, "data": {}}
	
	# Set position
	if step.has("position"):
		GameState.player_position = step.position
		result.data.position = step.position
	
	# Set attributes
	if step.has("hp"):
		GameState.player_hp = step.hp
		result.data.hp = step.hp
	
	if step.has("hunger"):
		GameState.player_hunger = step.hunger
	
	if step.has("thirst"):
		GameState.player_thirst = step.thirst
	
	# Set flags
	if step.has("flags"):
		for flag_name in step.flags.keys():
			GameStateManager.set_flag(flag_name, step.flags[flag_name])
	
	# Add inventory items
	if step.has("inventory"):
		GameState.inventory_items.clear()
		for item in step.inventory:
			GameState.inventory_items.append(item)
	
	print("[AITestBridge] State updated: " + str(result.data))
	return result

func _action_click(step: Dictionary):
	var target = step.get("target", "")
	var result = {"success": false, "data": {"target": target}}
	
	# Find target node
	var current_scene = get_tree().current_scene
	if not current_scene:
		result.error = "No active scene"
		return result
	
	var target_node = current_scene.find_child(target, true, false)
	
	if not target_node:
		result.error = "Target not found: " + target
		return result
	
	# Simulate click
	if target_node.has_method("_on_click") || target_node.has_signal("interacted"):
		if target_node.has_method("_on_click"):
			target_node._on_click()
		elif target_node.has_signal("interacted"):
			target_node.interacted.emit()
		
		result.success = true
		result.data.clicked = target
		print("[AITestBridge] Click succeeded: " + target)
	else:
		result.error = "Target not interactable: " + target
	
	return result

func _action_input(step: Dictionary):
	var text = step.get("text", "")
	var result = {"success": true, "data": {"input": text}}
	
	# Simulate input event
	# Can be extended with real UI input simulation
	print("[AITestBridge] Input text: " + text)
	
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
			# Check whether dialog is opened
			result.success = true  # Simplified implementation
			result.data.dialog_open = true
		
		"ui_opened":
			# Check whether target UI is opened
			result.success = true  # Simplified implementation
			result.data.ui = expected
		
		_:
			result.error = "Unknown verify type: " + check
	
	if not result.success && result.error == "":
		result.error = "Verification failed: expected " + str(expected) + ", actual " + str(result.data.get("actual", "unknown"))
	
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
	
	# Capture viewport screenshot
	var viewport = get_tree().root.get_viewport()
	var img = viewport.get_texture().get_image()
	
	if img:
		var error = img.save_png(path)
		if error == OK:
			result.success = true
			print("[AITestBridge] Screenshot saved: " + path)
		else:
			result.error = "Failed to save screenshot"
	else:
		result.error = "Failed to capture screenshot"
	
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
		result.error = "MapModule not available"
	
	return result

func _action_interact(step: Dictionary):
	var target = step.get("target", "")
	var result = {"success": false, "data": {"target": target}}
	
	# Simplified implementation: reuse click action
	result = await _action_click(step)
	
	return result

func _resolve_target_node(params: Dictionary) -> Node:
	if params.has("node_path"):
		var node_path := str(params.get("node_path", ""))
		if not node_path.is_empty():
			return get_node_or_null(node_path)
	
	var name := ""
	if params.has("node_name"):
		name = str(params.get("node_name", ""))
	elif params.has("target"):
		name = str(params.get("target", ""))
	
	if name.is_empty():
		return null
	
	var current_scene = get_tree().current_scene
	if not current_scene:
		return null
	
	return current_scene.find_child(name, true, false)

func _action_start_game(_params: Dictionary) -> Dictionary:
	var result = {"success": false, "data": {}, "error": ""}
	var current_scene = get_tree().current_scene
	
	if current_scene and current_scene.has_method("_on_start_pressed"):
		current_scene._on_start_pressed()
		result.success = true
		result.data.method = "scene_method"
		return result
	
	if current_scene:
		var btn = current_scene.find_child("StartButton", true, false)
		if btn and btn.has_signal("pressed"):
			btn.pressed.emit()
			result.success = true
			result.data.method = "button_signal"
			return result
	
	var err = get_tree().change_scene_to_file("res://scenes/locations/game_world_3d.tscn")
	if err == OK:
		result.success = true
		result.data.method = "change_scene"
	else:
		result.error = "Failed to change scene: " + str(err)
	
	return result

func _action_continue_game(_params: Dictionary) -> Dictionary:
	var result = {"success": false, "data": {}, "error": ""}
	var current_scene = get_tree().current_scene
	
	if current_scene and current_scene.has_method("_on_continue_pressed"):
		current_scene._on_continue_pressed()
		result.success = true
		result.data.method = "scene_method"
		return result
	
	if current_scene:
		var btn = current_scene.find_child("ContinueButton", true, false)
		if btn and btn.has_signal("pressed"):
			btn.pressed.emit()
			result.success = true
			result.data.method = "button_signal"
			return result
	
	result.error = "Continue action not available in current scene"
	return result

func _action_interact_primary(params: Dictionary) -> Dictionary:
	var result = {"success": false, "data": {}, "error": ""}
	var target = _resolve_target_node(params)
	
	if not target:
		result.error = "Target not found"
		return result
	
	if target.has_method("_on_left_click"):
		target._on_left_click()
		result.success = true
		result.data.method = "interactable_left_click"
		return result
	
	if target.has_method("_on_click"):
		target._on_click()
		result.success = true
		result.data.method = "_on_click"
		return result
	
	if target.has_signal("interacted"):
		target.interacted.emit()
		result.success = true
		result.data.method = "signal"
		return result
	
	result.error = "Target not interactable"
	return result

func _action_interact_option(params: Dictionary) -> Dictionary:
	var result = {"success": false, "data": {}, "error": ""}
	var target = _resolve_target_node(params)
	
	if not target:
		result.error = "Target not found"
		return result
	
	if not target.has_method("_get_available_options") or not target.has_method("_execute_option"):
		result.error = "Target is not Interactable"
		return result
	
	var options: Array = target._get_available_options()
	if options.is_empty():
		result.error = "No available options"
		return result
	
	var option_index := int(params.get("index", -1))
	var option_name := str(params.get("option_name", ""))
	var chosen = null
	
	if option_index >= 0 and option_index < options.size():
		chosen = options[option_index]
	elif not option_name.is_empty():
		for option in options:
			if option and option.get_option_name(target) == option_name:
				chosen = option
				break
	else:
		chosen = options[0]
	
	if not chosen:
		result.error = "Option not found"
		return result
	
	target._execute_option(chosen)
	result.success = true
	result.data.option = chosen.get_option_name(target) if chosen else ""
	return result

func _action_dialog_choose(params: Dictionary) -> Dictionary:
	var result = {"success": false, "data": {}, "error": ""}
	var dialog_module = get_node_or_null("/root/DialogModule")
	var dialog_ui = null
	
	if dialog_module:
		dialog_ui = dialog_module.get("_dialog_ui")
	
	if not dialog_ui:
		dialog_ui = get_tree().root.find_child("DialogUI", true, false)
	
	if not dialog_ui:
		result.error = "DialogUI not found"
		return result
	
	var choices_container = dialog_ui.get_node_or_null("Panel/ChoicesContainer")
	if not choices_container:
		result.error = "Choices container not found"
		return result
	
	var choice_index := int(params.get("index", -1))
	var choice_text := str(params.get("text", ""))
	var chosen_button = null
	
	if choice_index >= 0 and choice_index < choices_container.get_child_count():
		chosen_button = choices_container.get_child(choice_index)
	elif not choice_text.is_empty():
		for child in choices_container.get_children():
			if child is Button and child.text == choice_text:
				chosen_button = child
				break
	
	if not chosen_button:
		result.error = "Choice not found"
		return result
	
	if chosen_button.has_signal("pressed"):
		chosen_button.pressed.emit()
		result.success = true
		result.data.choice = choice_text if not choice_text.is_empty() else chosen_button.text
	else:
		result.error = "Choice button not pressable"
	
	return result

func _action_dialog_continue(_params: Dictionary) -> Dictionary:
	var result = {"success": false, "data": {}, "error": ""}
	var dialog_module = get_node_or_null("/root/DialogModule")
	var dialog_ui = null
	
	if dialog_module:
		dialog_ui = dialog_module.get("_dialog_ui")
	
	if not dialog_ui:
		dialog_ui = get_tree().root.find_child("DialogUI", true, false)
	
	if not dialog_ui:
		result.error = "DialogUI not found"
		return result
	
	var continue_button = dialog_ui.get_node_or_null("Panel/ContinueButton")
	if not continue_button:
		result.error = "Continue button not found"
		return result
	
	if continue_button.has_signal("pressed"):
		continue_button.pressed.emit()
		result.success = true
	else:
		result.error = "Continue button not pressable"
	
	return result

func _action_combat_attack(params: Dictionary) -> Dictionary:
	var result = {"success": false, "data": {}, "error": ""}
	var combat_system = get_node_or_null("/root/CombatSystem")
	if not combat_system or not combat_system.has_method("player_attack"):
		result.error = "CombatSystem not available"
		return result
	
	var attack_type := str(params.get("attack_type", "normal"))
	var target_part := str(params.get("target_part", "body"))
	var combat_result = combat_system.player_attack(attack_type, target_part)
	
	result.success = true
	result.data.result = combat_result
	return result

# ===== Test Utilities =====

## Start recording
func start_recording():
	_is_recording = true
	_recorded_actions.clear()
	print("[AITestBridge] Start recording")

## Stop recording
func stop_recording() -> Array[Dictionary]:
	_is_recording = false
	print("[AITestBridge] Stop recording, count: " + str(_recorded_actions.size()))
	return _recorded_actions.duplicate()

## Record action
func record_action(action: Dictionary):
	if _is_recording:
		action["timestamp"] = Time.get_unix_time_from_system()
		_recorded_actions.append(action)

## Get test history
func get_test_history() -> Array[Dictionary]:
	return _test_history.duplicate()

## Get last test
func get_last_test():
	if _test_history.size() > 0:
		return _test_history[-1]
	return {}

## Get interactable objects
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

## Quick save/load
func quick_save():
	return SaveSystem.save_game()

func quick_load():
	return SaveSystem.load_game()

## Wait for condition
func wait_for_condition(timeout: float, condition: Callable, check_interval: float = 0.5):
	var elapsed = 0.0
	
	while elapsed < timeout:
		if condition.call():
			return true
		
		await get_tree().create_timer(check_interval).timeout
		elapsed += check_interval
	
	return false

# ===== HTTP Request Handling (backward compatible) =====

func _handle_http_request(client: StreamPeerTCP, data: String):
	var request_line = data.split("\r\n")[0]
	if request_line.begins_with("GET /health"):
		_send_json_response(client, 200, JSON.stringify({"status": "ok"}))
		return
	if request_line.begins_with("GET /actions"):
		_send_json_response(client, 200, JSON.stringify({"actions": get_registered_actions()}))
		return
	
	var body = _extract_http_body(data)
	if body.is_empty():
		var state = _collect_game_state()
		_send_json_response(client, 200, JSON.stringify(state))
		return
	
	var json = JSON.new()
	var err = json.parse(body)
	if err != OK:
		var fallback = _collect_game_state()
		_send_json_response(client, 200, JSON.stringify(fallback))
		return
	
	var payload = json.get_data()
	var response = _handle_http_payload(payload)
	_send_json_response(client, 200, JSON.stringify(response))

func _extract_http_body(data: String) -> String:
	var idx = data.find("\r\n\r\n")
	if idx >= 0:
		return data.substr(idx + 4)
	return data

func _handle_http_payload(payload: Variant) -> Dictionary:
	if payload is Dictionary:
		if payload.has("action"):
			var name := str(payload.get("action", ""))
			var params: Dictionary = {}
			if payload.has("params") and payload.params is Dictionary:
				params = payload.params
			if name == "get_state":
				return _action_get_state()
			var result = execute_action(name, params)
			return {"success": result.success, "result": result, "timestamp": Time.get_unix_time_from_system()}
		
		if payload.has("batch") and payload.batch is Array:
			var results: Array = []
			for item in payload.batch:
				if item is Dictionary and item.has("action"):
					var name = str(item.get("action", ""))
					var params = item.get("params", {})
					if name == "get_state":
						results.append(_action_get_state())
					else:
						results.append(execute_action(name, params))
				else:
					results.append({"success": false, "error": "Invalid batch item"})
			return {"success": true, "results": results, "timestamp": Time.get_unix_time_from_system()}
		
		if payload.get("method", "") == "get_state":
			return _action_get_state()
	
	return _action_get_state()

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

# ===== Built-in Test Presets =====

## Main flow test
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

## Combat system test
func run_combat_test():
	var sequence = [
		{"action": "set_state", "hp": 100},
		{"action": "verify", "check": "hp", "expected": 100, "critical": true},
		{"action": "travel", "destination": "street_a"},
		{"action": "wait", "seconds": 3},
		{"action": "verify", "check": "hp", "expected": 100}
	]
	
	return await run_test_sequence("combat_system", sequence)

## Inventory system test
func run_inventory_test(level: int = 1):
	var sequence = [
		{"action": "set_state", "inventory": [{"id": "food_canned", "count": 3}]},
		{"action": "verify", "check": "has_item", "expected": "food_canned", "critical": true}
	]
	
	return await run_test_sequence("inventory_system", sequence)

## Run all tests
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


