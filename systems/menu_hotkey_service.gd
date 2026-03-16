extends Node

const InputActions = preload("res://core/input_actions.gd")
const GameMenuOverlay = preload("res://ui/game_menu_overlay.gd")

var _overlay: CanvasLayer = null
var _last_scene_path: String = ""

func _ready() -> void:
	InputActions.ensure_actions_registered()
	call_deferred("_sync_overlay_for_scene")
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

func open_menu(action_name: StringName) -> bool:
	if not _is_in_game_scene():
		return false
	_ensure_overlay()
	if _overlay == null or not _overlay.has_method("open_menu"):
		return false
	_overlay.open_menu(action_name)
	return true

func close_all_menus() -> void:
	if _overlay and _overlay.has_method("close_all_menus"):
		_overlay.close_all_menus()

func is_rebinding_input() -> bool:
	return _overlay != null and _overlay.has_method("is_rebinding_input") and _overlay.is_rebinding_input()

func is_any_menu_open() -> bool:
	return _overlay != null and _overlay.has_method("is_any_menu_open") and _overlay.is_any_menu_open()

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
