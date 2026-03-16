class_name PlayerInputComponent
extends Node

const InputActions = preload("res://core/input_actions.gd")

var _player: PlayerController = null

func _ready() -> void:
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	InputActions.ensure_actions_registered()

func initialize(player: PlayerController) -> void:
	_player = player
	_sync_menu_input_block_state()

func _process(_delta: float) -> void:
	_sync_menu_input_block_state()

func _input(event: InputEvent) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	if _handle_zoom_input(event):
		if get_viewport():
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if _is_world_input_blocked():
			_player.clear_world_input_feedback()
			return
		_player.handle_pointer_motion()
		return

	if _is_world_input_blocked():
		return

	if _player.handle_input(event) and get_viewport():
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _is_menu_input_blocked():
		return
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	var handled_action := _find_triggered_menu_action(event)
	if handled_action == StringName():
		return

	var menu_service := _get_menu_hotkey_service()
	if menu_service == null or not menu_service.has_method("open_menu"):
		return
	if not bool(menu_service.open_menu(handled_action)):
		return
	_player.clear_world_input_feedback()
	if get_viewport():
		get_viewport().set_input_as_handled()

func _handle_zoom_input(event: InputEvent) -> bool:
	if _is_world_input_blocked():
		return false

	var zoom_delta := 0
	if event.is_action_pressed("zoom_in"):
		zoom_delta = -1
	elif event.is_action_pressed("zoom_out"):
		zoom_delta = 1
	elif event is InputEventMagnifyGesture:
		var magnify_event := event as InputEventMagnifyGesture
		zoom_delta = -1 if magnify_event.factor > 1.0 else 1

	if zoom_delta == 0:
		return false

	var camera_controller := _resolve_camera_controller()
	if camera_controller == null or not camera_controller.has_method("adjust_zoom"):
		return false

	camera_controller.adjust_zoom(zoom_delta)
	return true

func _is_world_input_blocked() -> bool:
	if _player == null or not is_instance_valid(_player):
		return true
	return _player.is_world_input_blocked()

func _is_menu_input_blocked() -> bool:
	if _player == null or not is_instance_valid(_player):
		return true
	if _player.is_console_input_blocked():
		return true

	var menu_service := _get_menu_hotkey_service()
	if menu_service and menu_service.has_method("is_rebinding_input") and bool(menu_service.is_rebinding_input()):
		return true
	return false

func _find_triggered_menu_action(event: InputEvent) -> StringName:
	for action_variant in InputActions.MENU_ACTIONS:
		var action_name: StringName = action_variant
		if event.is_action_pressed(action_name):
			return action_name
	return StringName()

func _get_menu_hotkey_service() -> Node:
	return get_node_or_null("/root/MenuHotkeyService")

func _resolve_camera_controller() -> Node:
	var tree := get_tree()
	if tree == null:
		return null

	var current_scene := tree.current_scene
	if current_scene == null:
		return null
	if current_scene.has_method("get_camera"):
		var camera_controller: Variant = current_scene.get_camera()
		return camera_controller as Node
	return current_scene.get_node_or_null("CameraController3D")

func _sync_menu_input_block_state() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var is_menu_open := false
	var menu_service := _get_menu_hotkey_service()
	if menu_service and menu_service.has_method("is_any_menu_open"):
		is_menu_open = bool(menu_service.is_any_menu_open())
	_player.set_menu_input_blocked(is_menu_open)
