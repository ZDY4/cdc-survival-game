@tool
extends EditorPlugin

const PLUGIN_NAME: String = "CDC Game Editor"
const PLUGIN_VERSION: String = "2.3.0"

const MENU_DIALOG_EDITOR: int = 1
const MENU_QUEST_EDITOR: int = 2
const MENU_ITEM_EDITOR: int = 3
const MENU_NPC_EDITOR: int = 4
const MENU_RECIPE_EDITOR: int = 5

const EDITOR_DIALOG: String = "dialog"
const EDITOR_QUEST: String = "quest"
const EDITOR_ITEM: String = "item"
const EDITOR_NPC: String = "npc"
const EDITOR_RECIPE: String = "recipe"

const EDITOR_CONFIGS: Dictionary = {
	EDITOR_DIALOG: {
		"window_title": "CDC - Dialog Editor",
		"script_path": "res://addons/cdc_game_editor/editors/dialog_editor/dialog_editor.gd",
		"window_size": Vector2i(1200, 800)
	},
	EDITOR_QUEST: {
		"window_title": "CDC - Quest Editor",
		"script_path": "res://addons/cdc_game_editor/editors/quest_editor/quest_editor.gd",
		"window_size": Vector2i(1200, 800)
	},
	EDITOR_ITEM: {
		"window_title": "CDC - Item Editor",
		"script_path": "res://addons/cdc_game_editor/editors/item_editor/item_editor.gd",
		"window_size": Vector2i(1200, 800)
	},
	EDITOR_NPC: {
		"window_title": "CDC - NPC Editor",
		"script_path": "res://addons/cdc_game_editor/editors/npc_editor/npc_editor.gd",
		"window_size": Vector2i(1200, 800)
	},
	EDITOR_RECIPE: {
		"window_title": "CDC - Recipe Editor",
		"script_path": "res://addons/cdc_game_editor/editors/recipe_editor/recipe_editor.gd",
		"window_size": Vector2i(1200, 800)
	}
}

const MENU_TO_EDITOR_KEY: Dictionary = {
	MENU_DIALOG_EDITOR: EDITOR_DIALOG,
	MENU_QUEST_EDITOR: EDITOR_QUEST,
	MENU_ITEM_EDITOR: EDITOR_ITEM,
	MENU_NPC_EDITOR: EDITOR_NPC,
	MENU_RECIPE_EDITOR: EDITOR_RECIPE
}

var _cdc_menu_button: MenuButton = null
var _cdc_popup_menu: PopupMenu = null
var _top_menu_bar: MenuBar = null
var _menu_in_toolbar: bool = false

var _editor_instances: Dictionary = {}
var _editor_windows: Dictionary = {}

func _enter_tree() -> void:
	print("[%s v%s] Initializing plugin..." % [PLUGIN_NAME, PLUGIN_VERSION])
	_create_cdc_menu()
	print("[%s] Plugin initialized." % PLUGIN_NAME)

func _exit_tree() -> void:
	_cleanup_editor_windows()
	_remove_cdc_menu()
	print("[%s] Plugin disabled." % PLUGIN_NAME)

func _create_cdc_menu() -> void:
	_cdc_menu_button = MenuButton.new()
	_cdc_menu_button.text = "CDC"
	_cdc_menu_button.tooltip_text = "Open CDC editors"
	_cdc_popup_menu = _cdc_menu_button.get_popup()

	_cdc_popup_menu.add_item("Dialog Editor", MENU_DIALOG_EDITOR)
	_cdc_popup_menu.add_item("Quest Editor", MENU_QUEST_EDITOR)
	_cdc_popup_menu.add_item("Item Editor", MENU_ITEM_EDITOR)
	_cdc_popup_menu.add_item("NPC Editor", MENU_NPC_EDITOR)
	_cdc_popup_menu.add_item("Recipe Editor", MENU_RECIPE_EDITOR)
	_cdc_popup_menu.id_pressed.connect(_on_cdc_menu_item_pressed)

	_top_menu_bar = _find_main_menu_bar(get_editor_interface().get_base_control())
	if _top_menu_bar:
		_top_menu_bar.add_child(_cdc_menu_button)
		_top_menu_bar.move_child(_cdc_menu_button, _top_menu_bar.get_child_count() - 1)
		_menu_in_toolbar = false
		return

	# Fallback if main menu layout is not discoverable.
	add_control_to_container(CONTAINER_TOOLBAR, _cdc_menu_button)
	_menu_in_toolbar = true
	push_warning("[%s] Main menu bar not found. CDC menu added to toolbar." % PLUGIN_NAME)

func _remove_cdc_menu() -> void:
	if _cdc_menu_button:
		if _menu_in_toolbar:
			remove_control_from_container(CONTAINER_TOOLBAR, _cdc_menu_button)
		elif _top_menu_bar and _cdc_menu_button.get_parent() == _top_menu_bar:
			_top_menu_bar.remove_child(_cdc_menu_button)
		_cdc_menu_button.queue_free()
		_cdc_menu_button = null
		_cdc_popup_menu = null
		_top_menu_bar = null
		_menu_in_toolbar = false

func _find_main_menu_bar(root: Node) -> MenuBar:
	if root is MenuBar and _looks_like_main_menu_bar(root):
		return root

	for child in root.get_children():
		var child_node: Node = child
		var found: MenuBar = _find_main_menu_bar(child_node)
		if found:
			return found

	return null

func _looks_like_main_menu_bar(menu_bar: MenuBar) -> bool:
	var menu_button_count: int = 0
	for child in menu_bar.get_children():
		if child is MenuButton:
			menu_button_count += 1
	return menu_button_count >= 4

func _on_cdc_menu_item_pressed(menu_id: int) -> void:
	var editor_key: String = MENU_TO_EDITOR_KEY.get(menu_id, "")
	if editor_key.is_empty():
		return
	_open_editor_window(editor_key)

func _open_editor_window(editor_key: String) -> void:
	if not _editor_windows.has(editor_key):
		var created: bool = _create_editor_window(editor_key)
		if not created:
			return

	var editor_window: Window = _editor_windows.get(editor_key)
	if not editor_window:
		return

	if editor_window.visible:
		editor_window.grab_focus()
		return

	var window_size: Vector2i = _get_editor_window_size(editor_key)
	_position_window_safely(editor_window, window_size)
	editor_window.show()
	editor_window.move_to_foreground()
	editor_window.grab_focus()

func _create_editor_window(editor_key: String) -> bool:
	var editor_config: Dictionary = EDITOR_CONFIGS.get(editor_key, {})
	if editor_config.is_empty():
		push_error("[%s] Missing editor config for key: %s" % [PLUGIN_NAME, editor_key])
		return false

	var script_path: String = editor_config.get("script_path", "")
	var editor_script: Script = load(script_path)
	if not editor_script:
		push_error("[%s] Failed to load editor script: %s" % [PLUGIN_NAME, script_path])
		return false

	var editor_instance: Variant = editor_script.new()
	if not editor_instance is Control:
		push_error("[%s] Editor script must extend Control: %s" % [PLUGIN_NAME, script_path])
		return false

	var editor_control: Control = editor_instance
	var window_size: Vector2i = _get_editor_window_size(editor_key)
	editor_control.size = Vector2(window_size)
	editor_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_control.set_anchors_preset(Control.PRESET_FULL_RECT)

	if _object_has_property(editor_control, "editor_plugin"):
		editor_control.set("editor_plugin", self)

	var editor_window: Window = Window.new()
	editor_window.title = editor_config.get("window_title", "CDC Editor")
	editor_window.min_size = Vector2i(900, 600)
	editor_window.size = window_size
	editor_window.popup_window = false
	editor_window.transient = true
	editor_window.unresizable = false
	editor_window.close_requested.connect(_on_editor_window_close_requested.bind(editor_key))
	editor_window.add_child(editor_control)

	get_editor_interface().get_base_control().add_child(editor_window)

	_editor_instances[editor_key] = editor_control
	_editor_windows[editor_key] = editor_window
	return true

func _on_editor_window_close_requested(editor_key: String) -> void:
	var editor_window: Window = _editor_windows.get(editor_key)
	if editor_window:
		editor_window.hide()

func _cleanup_editor_windows() -> void:
	for editor_key in _editor_windows.keys():
		var editor_window: Window = _editor_windows[editor_key]
		if editor_window:
			editor_window.queue_free()
	_editor_windows.clear()
	_editor_instances.clear()

func _get_editor_window_size(editor_key: String) -> Vector2i:
	var editor_config: Dictionary = EDITOR_CONFIGS.get(editor_key, {})
	if editor_config.is_empty():
		return Vector2i(1200, 800)
	return editor_config.get("window_size", Vector2i(1200, 800))

func _position_window_safely(editor_window: Window, requested_size: Vector2i) -> void:
	var base_control: Control = get_editor_interface().get_base_control()
	var main_window: Window = base_control.get_window()
	if not main_window:
		editor_window.size = requested_size
		return

	var margin: Vector2i = Vector2i(40, 60)
	var max_width: int = max(main_window.size.x - margin.x, editor_window.min_size.x)
	var max_height: int = max(main_window.size.y - margin.y, editor_window.min_size.y)
	var safe_width: int = clampi(requested_size.x, editor_window.min_size.x, max_width)
	var safe_height: int = clampi(requested_size.y, editor_window.min_size.y, max_height)
	editor_window.size = Vector2i(safe_width, safe_height)

	var x: int = main_window.position.x + (main_window.size.x - editor_window.size.x) / 2
	var y: int = main_window.position.y + (main_window.size.y - editor_window.size.y) / 2

	var min_y: int = main_window.position.y + 28
	if y < min_y:
		y = min_y

	editor_window.position = Vector2i(x, y)

func _object_has_property(instance: Object, property_name: String) -> bool:
	for property_info in instance.get_property_list():
		if property_info is Dictionary and property_info.get("name", "") == property_name:
			return true
	return false

func _get_plugin_name() -> String:
	return PLUGIN_NAME

func _get_plugin_icon() -> Texture2D:
	return get_editor_interface().get_base_control().get_theme_icon("Edit", "EditorIcons")

func _handles(object: Object) -> bool:
	if object is Resource:
		var path: String = object.resource_path
		if path.ends_with(".dlg") or path.ends_with(".dialog"):
			return true
		if path.ends_with(".quest") or path.ends_with(".quest_data"):
			return true
		if path.ends_with(".item") or path.ends_with(".items"):
			return true
	return false

func _edit(object: Object) -> void:
	if not object is Resource:
		return

	var path: String = object.resource_path
	if path.ends_with(".dlg") or path.ends_with(".dialog"):
		_open_editor_window(EDITOR_DIALOG)
	elif path.ends_with(".quest") or path.ends_with(".quest_data"):
		_open_editor_window(EDITOR_QUEST)
	elif path.ends_with(".item") or path.ends_with(".items"):
		_open_editor_window(EDITOR_ITEM)

func _apply_changes() -> void:
	for editor_key in _editor_instances.keys():
		var editor: Object = _editor_instances[editor_key]
		if not editor:
			continue
		if editor.has_method("has_unsaved_changes") and editor.call("has_unsaved_changes"):
			print("[%s] %s editor has unsaved changes." % [PLUGIN_NAME, editor_key])

func _build() -> bool:
	var has_errors: bool = false

	for editor_key in _editor_instances.keys():
		var editor: Object = _editor_instances[editor_key]
		if not editor:
			continue
		if not editor.has_method("get_validation_errors"):
			continue

		var errors: Variant = editor.call("get_validation_errors")
		if _validation_result_has_errors(errors):
			push_warning("[%s] Validation errors found in %s editor." % [PLUGIN_NAME, editor_key])
			has_errors = true

	return not has_errors

func _validation_result_has_errors(errors: Variant) -> bool:
	if errors == null:
		return false
	if errors is Array:
		return not errors.is_empty()
	if errors is Dictionary:
		return not errors.is_empty()
	return true
