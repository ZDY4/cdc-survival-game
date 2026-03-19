@tool
extends EditorPlugin

const AUTOLOAD_NAME: String = "GameplayTags"
const MANAGER_SCRIPT_PATH: String = "res://addons/gameplay_tags/runtime/gameplay_tags_manager.gd"
const WINDOW_CONTENT_SCRIPT_PATH: String = "res://addons/gameplay_tags/editor/gameplay_tags_dock.gd"
const TOOL_MENU_ITEM_NAME: String = "Gameplay Tags"
const DEFAULT_WINDOW_SIZE: Vector2i = Vector2i(1120, 760)
const MIN_WINDOW_SIZE: Vector2i = Vector2i(820, 560)

var _window_content: Control = null
var _editor_window: Window = null
var _autoload_added_by_plugin: bool = false
var _window_opened_once: bool = false

func _enter_tree() -> void:
	_ensure_autoload_singleton()
	add_tool_menu_item(TOOL_MENU_ITEM_NAME, Callable(self, "_on_tool_menu_item_pressed"))
	call_deferred("_bind_manager_to_window")

func _exit_tree() -> void:
	remove_tool_menu_item(TOOL_MENU_ITEM_NAME)
	_cleanup_window()
	_remove_autoload_singleton_if_needed()

func _ensure_autoload_singleton() -> void:
	var setting_key: String = "autoload/%s" % AUTOLOAD_NAME
	if ProjectSettings.has_setting(setting_key):
		var configured_path: String = str(ProjectSettings.get_setting(setting_key))
		var clean_path: String = configured_path.trim_prefix("*")
		if clean_path != MANAGER_SCRIPT_PATH:
			push_warning(
				"[Gameplay Tags] Autoload '%s' already exists at %s, expected %s." %
				[AUTOLOAD_NAME, configured_path, MANAGER_SCRIPT_PATH]
			)
		return

	add_autoload_singleton(AUTOLOAD_NAME, MANAGER_SCRIPT_PATH)
	_autoload_added_by_plugin = true
	ProjectSettings.save()

func _remove_autoload_singleton_if_needed() -> void:
	if not _autoload_added_by_plugin:
		return
	remove_autoload_singleton(AUTOLOAD_NAME)
	ProjectSettings.save()
	_autoload_added_by_plugin = false

func _on_tool_menu_item_pressed() -> void:
	_open_window()

func _open_window() -> void:
	if _editor_window == null:
		if not _create_window():
			return

	if _editor_window.visible:
		_editor_window.grab_focus()
		return

	if not _window_opened_once:
		_position_window_safely(_editor_window, DEFAULT_WINDOW_SIZE)
		_window_opened_once = true

	_editor_window.show()
	_editor_window.grab_focus()
	call_deferred("_bind_manager_to_window")

func _create_window() -> bool:
	var content_script: Script = load(WINDOW_CONTENT_SCRIPT_PATH)
	if content_script == null:
		push_error("[Gameplay Tags] Failed to load window content script at %s" % WINDOW_CONTENT_SCRIPT_PATH)
		return false

	var content_instance: Variant = content_script.new()
	if not (content_instance is Control):
		push_error("[Gameplay Tags] Window content script must extend Control.")
		return false

	var editor_content: Control = content_instance
	editor_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	editor_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_content.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var editor_window := Window.new()
	editor_window.title = TOOL_MENU_ITEM_NAME
	editor_window.min_size = MIN_WINDOW_SIZE
	editor_window.size = DEFAULT_WINDOW_SIZE
	editor_window.popup_window = false
	editor_window.transient = false
	editor_window.unresizable = false
	editor_window.close_requested.connect(_on_window_close_requested)
	editor_window.add_child(editor_content)

	get_editor_interface().get_base_control().add_child(editor_window)
	editor_window.hide()

	_window_content = editor_content
	_editor_window = editor_window
	return true

func _on_window_close_requested() -> void:
	if _editor_window:
		_editor_window.hide()

func _cleanup_window() -> void:
	if _editor_window:
		_editor_window.queue_free()
	_editor_window = null
	_window_content = null
	_window_opened_once = false

func _bind_manager_to_window() -> void:
	if _window_content == null:
		return

	var manager: Node = _get_manager_node()
	if manager and manager.has_method("reload_tags"):
		manager.call("reload_tags")

	if _window_content.has_method("set_manager"):
		_window_content.call("set_manager", manager)

func _position_window_safely(editor_window: Window, requested_size: Vector2i) -> void:
	var base_control: Control = get_editor_interface().get_base_control()
	var main_window: Window = base_control.get_window()
	var screen_index: int = DisplayServer.get_primary_screen()
	if main_window:
		screen_index = main_window.current_screen

	var usable_rect: Rect2i = DisplayServer.screen_get_usable_rect(screen_index)
	if usable_rect.size.x <= 0 or usable_rect.size.y <= 0:
		if main_window:
			usable_rect = Rect2i(main_window.position, main_window.size)
		else:
			editor_window.size = requested_size
			editor_window.position = Vector2i(50, 50)
			return

	var edge_margin: int = 12
	var max_width: int = max(usable_rect.size.x - edge_margin * 2, editor_window.min_size.x)
	var max_height: int = max(usable_rect.size.y - edge_margin * 2, editor_window.min_size.y)
	var safe_width: int = clampi(requested_size.x, editor_window.min_size.x, max_width)
	var safe_height: int = clampi(requested_size.y, editor_window.min_size.y, max_height)
	editor_window.size = Vector2i(safe_width, safe_height)

	var centered_x: int = usable_rect.position.x + (usable_rect.size.x - safe_width) / 2
	var centered_y: int = usable_rect.position.y + (usable_rect.size.y - safe_height) / 2

	var min_x: int = usable_rect.position.x
	var max_x: int = usable_rect.position.x + usable_rect.size.x - safe_width
	var min_y: int = usable_rect.position.y + edge_margin
	var max_y: int = usable_rect.position.y + usable_rect.size.y - safe_height

	editor_window.position = Vector2i(
		clampi(centered_x, min_x, max_x),
		clampi(centered_y, min_y, max_y)
	)

func _get_manager_node() -> Node:
	var base_control: Control = get_editor_interface().get_base_control()
	if base_control == null:
		return null
	var tree: SceneTree = base_control.get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(AUTOLOAD_NAME)
