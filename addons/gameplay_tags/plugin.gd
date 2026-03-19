@tool
extends EditorPlugin

const AUTOLOAD_NAME: String = "GameplayTags"
const MANAGER_SCRIPT_PATH: String = "res://addons/gameplay_tags/runtime/gameplay_tags_manager.gd"
const WINDOW_CONTENT_SCRIPT_PATH: String = "res://addons/gameplay_tags/editor/gameplay_tags_dock.gd"
const TOOL_MENU_ITEM_NAME: String = "Gameplay Tags"
const DEFAULT_WINDOW_SIZE: Vector2i = Vector2i(1120, 760)
const MIN_WINDOW_SIZE: Vector2i = Vector2i(820, 560)
const EDITOR_MENU_ITEM_ID: int = 42001
const EDITOR_MENU_LABELS: PackedStringArray = ["Editor", "编辑器"]
const MENU_ATTACH_MAX_ATTEMPTS: int = 120

var _window_content: Control = null
var _editor_window: Window = null
var _autoload_added_by_plugin: bool = false
var _window_opened_once: bool = false
var _editor_popup_menu: PopupMenu = null
var _fallback_menu_button: MenuButton = null
var _fallback_popup_menu: PopupMenu = null
var _top_menu_bar: MenuBar = null
var _menu_in_toolbar: bool = false

func _enter_tree() -> void:
	_ensure_autoload_singleton()
	call_deferred("_initialize_menu_deferred")
	call_deferred("_bind_manager_to_window")

func _exit_tree() -> void:
	_remove_editor_menu_item()
	_cleanup_window()
	_remove_autoload_singleton_if_needed()

func _initialize_menu_deferred() -> void:
	await _attach_menu_item_to_editor_menu()

func _attach_menu_item_to_editor_menu() -> void:
	for _attempt in range(MENU_ATTACH_MAX_ATTEMPTS):
		if not is_inside_tree():
			return
		if _attach_to_editor_menu():
			_menu_in_toolbar = false
			return
		await get_tree().process_frame

	_create_fallback_menu_button()

func _attach_to_editor_menu() -> bool:
	var base_control: Control = get_editor_interface().get_base_control()
	_top_menu_bar = _find_main_menu_bar(base_control)
	var editor_popup: PopupMenu = _find_editor_popup_menu(base_control)
	if editor_popup == null:
		return false

	if _editor_popup_menu != editor_popup and _editor_popup_menu and _editor_popup_menu.id_pressed.is_connected(_on_editor_menu_id_pressed):
		_editor_popup_menu.id_pressed.disconnect(_on_editor_menu_id_pressed)

	_editor_popup_menu = editor_popup
	_remove_existing_editor_menu_item()
	if not _editor_popup_menu.id_pressed.is_connected(_on_editor_menu_id_pressed):
		_editor_popup_menu.id_pressed.connect(_on_editor_menu_id_pressed)
	_editor_popup_menu.add_item(TOOL_MENU_ITEM_NAME, EDITOR_MENU_ITEM_ID)
	return true

func _create_fallback_menu_button() -> void:
	if _fallback_menu_button:
		return

	_fallback_menu_button = MenuButton.new()
	_fallback_menu_button.text = TOOL_MENU_ITEM_NAME
	_fallback_menu_button.tooltip_text = "Open Gameplay Tags editor"
	_fallback_popup_menu = _fallback_menu_button.get_popup()
	_fallback_popup_menu.add_item(TOOL_MENU_ITEM_NAME, EDITOR_MENU_ITEM_ID)
	_fallback_popup_menu.id_pressed.connect(_on_editor_menu_id_pressed)

	var base_control: Control = get_editor_interface().get_base_control()
	_top_menu_bar = _find_main_menu_bar(base_control)
	if _top_menu_bar:
		_top_menu_bar.add_child(_fallback_menu_button)
		_top_menu_bar.move_child(_fallback_menu_button, _top_menu_bar.get_child_count() - 1)
		return

	add_control_to_container(CONTAINER_TOOLBAR, _fallback_menu_button)
	_menu_in_toolbar = true

func _remove_editor_menu_item() -> void:
	if _editor_popup_menu:
		_remove_existing_editor_menu_item()
		if _editor_popup_menu.id_pressed.is_connected(_on_editor_menu_id_pressed):
			_editor_popup_menu.id_pressed.disconnect(_on_editor_menu_id_pressed)

	if _fallback_popup_menu and _fallback_popup_menu.id_pressed.is_connected(_on_editor_menu_id_pressed):
		_fallback_popup_menu.id_pressed.disconnect(_on_editor_menu_id_pressed)

	if _fallback_menu_button:
		if _menu_in_toolbar:
			remove_control_from_container(CONTAINER_TOOLBAR, _fallback_menu_button)
		elif _top_menu_bar and _fallback_menu_button.get_parent() == _top_menu_bar:
			_top_menu_bar.remove_child(_fallback_menu_button)
		_fallback_menu_button.queue_free()

	_fallback_menu_button = null
	_fallback_popup_menu = null
	_editor_popup_menu = null
	_top_menu_bar = null
	_menu_in_toolbar = false

func _remove_existing_editor_menu_item() -> void:
	if _editor_popup_menu == null:
		return

	var menu_item_index: int = _find_menu_item_index_by_id(_editor_popup_menu, EDITOR_MENU_ITEM_ID)
	if menu_item_index >= 0:
		_editor_popup_menu.remove_item(menu_item_index)

func _find_menu_item_index_by_id(menu: PopupMenu, item_id: int) -> int:
	for item_index in range(menu.item_count):
		if menu.get_item_id(item_index) == item_id:
			return item_index
	return -1

func _find_main_menu_bar(root: Node) -> MenuBar:
	if root is MenuBar:
		return root

	for child in root.get_children():
		var child_node: Node = child
		var found: MenuBar = _find_main_menu_bar(child_node)
		if found:
			return found

	return null

func _find_editor_popup_menu(root: Node) -> PopupMenu:
	var menu_button: MenuButton = _find_editor_menu_button(root)
	if menu_button:
		var popup_from_button: PopupMenu = menu_button.get_popup()
		if popup_from_button:
			return popup_from_button

	return _find_editor_popup_node(root)

func _find_editor_popup_node(root: Node) -> PopupMenu:
	if root is PopupMenu:
		var popup_menu: PopupMenu = root
		if _is_editor_popup_menu(popup_menu):
			return popup_menu

	for child in root.get_children():
		var child_node: Node = child
		var found: PopupMenu = _find_editor_popup_node(child_node)
		if found:
			return found

	return null

func _find_editor_menu_button(root: Node) -> MenuButton:
	if root is MenuButton:
		var menu_button: MenuButton = root
		if _is_editor_menu_button(menu_button):
			return menu_button

	for child in root.get_children():
		var child_node: Node = child
		var found: MenuButton = _find_editor_menu_button(child_node)
		if found:
			return found

	return null

func _is_editor_menu_button(menu_button: MenuButton) -> bool:
	var menu_label: String = menu_button.text.strip_edges()
	if EDITOR_MENU_LABELS.has(menu_label):
		return true
	return menu_button.name.to_lower().contains("editor")

func _is_editor_popup_menu(popup_menu: PopupMenu) -> bool:
	var popup_title: String = popup_menu.title.strip_edges()
	if EDITOR_MENU_LABELS.has(popup_title):
		return true
	return popup_menu.name.to_lower().contains("editor")

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

func _on_editor_menu_id_pressed(menu_id: int) -> void:
	if menu_id != EDITOR_MENU_ITEM_ID:
		return
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
	if _window_content and _window_content.has_method("request_window_close"):
		_window_content.call("request_window_close", Callable(self, "_hide_editor_window"))
		return
	_hide_editor_window()

func _hide_editor_window() -> void:
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

	if manager != null and _window_content.has_method("set_manager"):
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
