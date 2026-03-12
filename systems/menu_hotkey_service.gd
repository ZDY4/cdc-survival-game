extends Node

const InputActions = preload("res://core/input_actions.gd")
const GameMenuOverlay = preload("res://ui/game_menu_overlay.gd")

var _overlay: CanvasLayer = null
var _last_scene_path: String = ""

func _ready() -> void:
	InputActions.ensure_actions_registered()
	call_deferred("_sync_overlay_for_scene")
	set_process_unhandled_input(true)
	set_process(true)

func _process(_delta: float) -> void:
	var scene: Node = get_tree().current_scene
	var path: String = ""
	if scene:
		path = str(scene.scene_file_path)
	if path == _last_scene_path:
		return
	_last_scene_path = path
	_sync_overlay_for_scene()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_in_game_scene():
		return
	if _overlay and _overlay.has_method("is_rebinding_input") and _overlay.is_rebinding_input():
		return
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var handled_action: StringName = _find_triggered_menu_action(event)
	if handled_action == StringName():
		return
	_ensure_overlay()
	if _overlay and _overlay.has_method("open_menu"):
		_overlay.open_menu(handled_action)
		get_viewport().set_input_as_handled()

func _sync_overlay_for_scene() -> void:
	if _is_in_game_scene():
		_ensure_overlay()
		if _overlay:
			_overlay.visible = true
	else:
		if _overlay and _overlay.has_method("close_all_menus"):
			_overlay.close_all_menus()
		if _overlay:
			_overlay.visible = false

func _ensure_overlay() -> void:
	if _overlay:
		return
	_overlay = GameMenuOverlay.new()
	get_tree().root.call_deferred("add_child", _overlay)

func _is_in_game_scene() -> bool:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return false
	var path: String = str(scene.scene_file_path)
	return path.begins_with("res://scenes/locations/")

func _find_triggered_menu_action(event: InputEvent) -> StringName:
	for action_variant in InputActions.MENU_ACTIONS:
		var action_name: StringName = action_variant
		if event.is_action_pressed(action_name):
			return action_name
	return StringName()
