@tool
extends EditorPlugin

const PLUGIN_NAME: String = "CDC Game Editor"
const PLUGIN_VERSION: String = "2.4.0"

const MENU_DIALOG_EDITOR: int = 1
const MENU_QUEST_EDITOR: int = 2
const MENU_ITEM_EDITOR: int = 3
const MENU_CHARACTER_EDITOR: int = 4
const MENU_RECIPE_EDITOR: int = 5
const MENU_SKILL_EDITOR: int = 6
const MENU_EFFECT_EDITOR: int = 7
const MENU_CDC_EDITORS_ROOT: int = 100

const CDC_SUBMENU_NAME: String = "CDCEditorsSubmenu"
const CDC_SUBMENU_LABEL: String = "CDC Editors"
const EDITOR_MENU_LABELS: PackedStringArray = ["Editor", "编辑器"]
const MENU_ATTACH_MAX_ATTEMPTS: int = 120

const EDITOR_DIALOG: String = "dialog"
const EDITOR_QUEST: String = "quest"
const EDITOR_ITEM: String = "item"
const EDITOR_CHARACTER: String = "character"
const EDITOR_EFFECT: String = "effect"
const EDITOR_RECIPE: String = "recipe"
const EDITOR_SKILL: String = "skill"

const DATA_KIND_ITEM: String = "item"
const DATA_KIND_QUEST: String = "quest"
const DATA_KIND_RECIPE: String = "recipe"
const DATA_KIND_SKILL: String = "skill"
const DATA_KIND_EFFECT: String = "effect"
const DATA_KIND_CHARACTER: String = "character"
const DATA_KIND_NPC: String = "npc"
const DATA_KIND_ENEMY: String = "enemy"

const GAME_DATA_ID_INSPECTOR_PLUGIN_SCRIPT := preload(
	"res://addons/cdc_game_editor/inspector/game_data_id_inspector_plugin.gd"
)

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
	EDITOR_CHARACTER: {
		"window_title": "CDC - Character Data Editor",
		"script_path": "res://addons/cdc_game_editor/editors/character_data_editor/character_data_editor.gd",
		"window_size": Vector2i(1320, 900)
	},
	EDITOR_EFFECT: {
		"window_title": "CDC - Effect Editor",
		"script_path": "res://addons/cdc_game_editor/editors/effect_editor/effect_editor.gd",
		"window_size": Vector2i(1200, 800)
	},
	EDITOR_RECIPE: {
		"window_title": "CDC - Recipe Editor",
		"script_path": "res://addons/cdc_game_editor/editors/recipe_editor/recipe_editor.gd",
		"window_size": Vector2i(1200, 800)
	},
	EDITOR_SKILL: {
		"window_title": "CDC - Skill Editor",
		"script_path": "res://addons/cdc_game_editor/editors/skill_editor/skill_editor.gd",
		"window_size": Vector2i(1300, 900)
	}
}

const MENU_TO_EDITOR_KEY: Dictionary = {
	MENU_DIALOG_EDITOR: EDITOR_DIALOG,
	MENU_QUEST_EDITOR: EDITOR_QUEST,
	MENU_ITEM_EDITOR: EDITOR_ITEM,
	MENU_CHARACTER_EDITOR: EDITOR_CHARACTER,
	MENU_EFFECT_EDITOR: EDITOR_EFFECT,
	MENU_RECIPE_EDITOR: EDITOR_RECIPE,
	MENU_SKILL_EDITOR: EDITOR_SKILL
}

const DATA_KIND_TO_EDITOR_KEY: Dictionary = {
	DATA_KIND_ITEM: EDITOR_ITEM,
	DATA_KIND_QUEST: EDITOR_QUEST,
	DATA_KIND_RECIPE: EDITOR_RECIPE,
	DATA_KIND_SKILL: EDITOR_SKILL,
	DATA_KIND_EFFECT: EDITOR_EFFECT,
	DATA_KIND_CHARACTER: EDITOR_CHARACTER
}

var _cdc_menu_button: MenuButton = null
var _cdc_popup_menu: PopupMenu = null
var _cdc_submenu_popup: PopupMenu = null
var _editor_menu_button: MenuButton = null
var _editor_popup_menu: PopupMenu = null
var _top_menu_bar: MenuBar = null
var _menu_in_toolbar: bool = false

var _editor_instances: Dictionary = {}
var _editor_windows: Dictionary = {}
var _is_disabling: bool = false
var _game_data_id_inspector_plugin: EditorInspectorPlugin = null

func _enter_tree() -> void:
	print("[%s v%s] Initializing plugin..." % [PLUGIN_NAME, PLUGIN_VERSION])
	_is_disabling = false
	set_input_event_forwarding_always_enabled()
	_register_inspector_plugin()
	call_deferred("_initialize_menu_deferred")

func _exit_tree() -> void:
	_is_disabling = true
	_unregister_inspector_plugin()
	_cleanup_editor_windows()
	_remove_cdc_menu()
	print("[%s] Plugin disabled." % PLUGIN_NAME)

func _register_inspector_plugin() -> void:
	if _game_data_id_inspector_plugin:
		return
	_game_data_id_inspector_plugin = GAME_DATA_ID_INSPECTOR_PLUGIN_SCRIPT.new(self)
	add_inspector_plugin(_game_data_id_inspector_plugin)

func _unregister_inspector_plugin() -> void:
	if not _game_data_id_inspector_plugin:
		return
	remove_inspector_plugin(_game_data_id_inspector_plugin)
	_game_data_id_inspector_plugin = null

func _initialize_menu_deferred() -> void:
	await _create_cdc_menu()
	if not _is_disabling:
		print("[%s] Plugin initialized." % PLUGIN_NAME)

func _create_cdc_menu() -> void:
	_cdc_submenu_popup = PopupMenu.new()
	_cdc_submenu_popup.name = CDC_SUBMENU_NAME
	_populate_cdc_menu(_cdc_submenu_popup)
	_cdc_submenu_popup.id_pressed.connect(_on_cdc_menu_item_pressed)

	for _attempt in range(MENU_ATTACH_MAX_ATTEMPTS):
		if _is_disabling or not is_inside_tree():
			return
		if _attach_to_editor_menu():
			_menu_in_toolbar = false
			print("[%s] CDC submenu attached under Editor menu." % PLUGIN_NAME)
			return
		await get_tree().process_frame

	_cdc_menu_button = MenuButton.new()
	_cdc_menu_button.text = "CDC"
	_cdc_menu_button.tooltip_text = "Open CDC editors"
	_cdc_popup_menu = _cdc_menu_button.get_popup()
	_populate_cdc_menu(_cdc_popup_menu)
	_cdc_popup_menu.id_pressed.connect(_on_cdc_menu_item_pressed)

	var base_control: Control = get_editor_interface().get_base_control()
	_top_menu_bar = _find_main_menu_bar(base_control)
	if _top_menu_bar:
		_top_menu_bar.add_child(_cdc_menu_button)
		_top_menu_bar.move_child(_cdc_menu_button, _top_menu_bar.get_child_count() - 1)
		_menu_in_toolbar = false
		push_warning("[%s] Editor menu not found after retries. CDC menu added to top menu bar." % PLUGIN_NAME)
		return

	add_control_to_container(CONTAINER_TOOLBAR, _cdc_menu_button)
	_menu_in_toolbar = true
	push_warning("[%s] Main menu bar not found after retries. CDC menu added to toolbar." % PLUGIN_NAME)

func _attach_to_editor_menu() -> bool:
	var base_control: Control = get_editor_interface().get_base_control()
	_top_menu_bar = _find_main_menu_bar(base_control)

	var editor_popup: PopupMenu = _find_editor_popup_menu(base_control)
	if not editor_popup:
		return false

	_editor_popup_menu = editor_popup
	_remove_existing_cdc_submenu()
	_editor_popup_menu.add_child(_cdc_submenu_popup)
	_editor_popup_menu.add_submenu_item(CDC_SUBMENU_LABEL, CDC_SUBMENU_NAME, MENU_CDC_EDITORS_ROOT)
	return true

func _remove_cdc_menu() -> void:
	if _editor_popup_menu:
		var submenu_item_index: int = _find_menu_item_index_by_id(_editor_popup_menu, MENU_CDC_EDITORS_ROOT)
		if submenu_item_index >= 0:
			_editor_popup_menu.remove_item(submenu_item_index)
		if _cdc_submenu_popup and _cdc_submenu_popup.get_parent() == _editor_popup_menu:
			_editor_popup_menu.remove_child(_cdc_submenu_popup)

	if _cdc_submenu_popup:
		_cdc_submenu_popup.queue_free()
		_cdc_submenu_popup = null

	if _cdc_menu_button:
		if _menu_in_toolbar:
			remove_control_from_container(CONTAINER_TOOLBAR, _cdc_menu_button)
		elif _top_menu_bar and _cdc_menu_button.get_parent() == _top_menu_bar:
			_top_menu_bar.remove_child(_cdc_menu_button)
		_cdc_menu_button.queue_free()
		_cdc_menu_button = null

	_cdc_popup_menu = null
	_editor_menu_button = null
	_editor_popup_menu = null
	_top_menu_bar = null
	_menu_in_toolbar = false

func _populate_cdc_menu(menu: PopupMenu) -> void:
	menu.add_item("Dialog Editor", MENU_DIALOG_EDITOR)
	menu.add_item("Quest Editor", MENU_QUEST_EDITOR)
	menu.add_item("Item Editor", MENU_ITEM_EDITOR)
	menu.add_item("Character Data Editor", MENU_CHARACTER_EDITOR)
	menu.add_item("Effect Editor", MENU_EFFECT_EDITOR)
	menu.add_item("Recipe Editor", MENU_RECIPE_EDITOR)
	menu.add_item("Skill Editor", MENU_SKILL_EDITOR)

func _remove_existing_cdc_submenu() -> void:
	if not _editor_popup_menu:
		return

	var existing_item_index: int = _find_menu_item_index_by_id(_editor_popup_menu, MENU_CDC_EDITORS_ROOT)
	if existing_item_index >= 0:
		_editor_popup_menu.remove_item(existing_item_index)

	var existing_submenu: Node = _editor_popup_menu.get_node_or_null(CDC_SUBMENU_NAME)
	if existing_submenu and existing_submenu is PopupMenu:
		_editor_popup_menu.remove_child(existing_submenu)
		existing_submenu.queue_free()

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

func _on_cdc_menu_item_pressed(menu_id: int) -> void:
	var editor_key: String = MENU_TO_EDITOR_KEY.get(menu_id, "")
	if editor_key.is_empty():
		return
	open_cdc_editor(editor_key)

func open_cdc_editor(editor_key: String) -> bool:
	return _open_editor_window(editor_key)

func open_cdc_data_editor(data_kind: String, data_id: String) -> bool:
	var normalized_kind: String = data_kind.strip_edges().to_lower()
	var normalized_id: String = data_id.strip_edges()
	var editor_key: String = _resolve_editor_key_for_data(normalized_kind, normalized_id)
	if editor_key.is_empty():
		push_warning("[%s] No editor mapping for data kind: %s" % [PLUGIN_NAME, normalized_kind])
		return false

	var opened: bool = open_cdc_editor(editor_key)
	if not opened:
		return false
	if normalized_id.is_empty():
		return true

	var editor: Object = _editor_instances.get(editor_key, null)
	if not editor or not editor.has_method("focus_record"):
		push_warning("[%s] Editor '%s' does not support focus_record" % [PLUGIN_NAME, editor_key])
		return false

	var focused: bool = bool(editor.call("focus_record", normalized_id))
	if not focused:
		push_warning("[%s] Could not focus %s in %s editor" % [PLUGIN_NAME, normalized_id, editor_key])
	return focused

func _resolve_editor_key_for_data(data_kind: String, _data_id: String) -> String:
	return DATA_KIND_TO_EDITOR_KEY.get(data_kind, "")

func _open_editor_window(editor_key: String) -> bool:
	if not _editor_windows.has(editor_key):
		var created: bool = _create_editor_window(editor_key)
		if not created:
			return false

	var editor_window: Window = _editor_windows.get(editor_key)
	if not editor_window:
		return false

	if editor_window.visible:
		editor_window.grab_focus()
		return true

	var window_size: Vector2i = _get_editor_window_size(editor_key)
	editor_window.size = window_size
	_position_window_safely(editor_window, window_size)
	editor_window.show()
	call_deferred("_position_window_safely", editor_window, window_size)
	editor_window.grab_focus()
	return true

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
	editor_window.transient = false
	editor_window.unresizable = false
	editor_window.close_requested.connect(_on_editor_window_close_requested.bind(editor_key))
	editor_window.add_child(editor_control)

	get_editor_interface().get_base_control().add_child(editor_window)
	editor_window.hide()

	_editor_instances[editor_key] = editor_control
	_editor_windows[editor_key] = editor_window
	return true

func _on_editor_window_close_requested(editor_key: String) -> void:
	var editor: Object = _editor_instances.get(editor_key, null)
	if editor and editor.has_method("request_window_close"):
		editor.call("request_window_close", Callable(self, "_hide_editor_window").bind(editor_key))
		return
	_hide_editor_window(editor_key)

func _hide_editor_window(editor_key: String) -> void:
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
		open_cdc_editor(EDITOR_DIALOG)
	elif path.ends_with(".quest") or path.ends_with(".quest_data"):
		open_cdc_editor(EDITOR_QUEST)
	elif path.ends_with(".item") or path.ends_with(".items"):
		open_cdc_editor(EDITOR_ITEM)

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var target_spawn_point: AISpawnPoint = _find_spawn_point_from_preview_click(camera, mouse_event.position)
	if target_spawn_point == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	_select_node_in_editor(target_spawn_point)
	return EditorPlugin.AFTER_GUI_INPUT_STOP

func _find_spawn_point_from_preview_click(camera: Camera3D, screen_pos: Vector2) -> AISpawnPoint:
	if camera == null:
		return null

	var scene_root: Node = get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		return null

	var spawn_points: Array[AISpawnPoint] = _collect_ai_spawn_points(scene_root)
	for spawn_point in spawn_points:
		if spawn_point.editor_preview_hit_test(camera, screen_pos):
			return spawn_point
	return null

func _collect_ai_spawn_points(root: Node) -> Array[AISpawnPoint]:
	var result: Array[AISpawnPoint] = []
	for child in root.get_children():
		if child is AISpawnPoint:
			result.append(child as AISpawnPoint)
		result.append_array(_collect_ai_spawn_points(child))
	return result

func _select_node_in_editor(target_node: Node) -> void:
	if target_node == null:
		return

	var selection: EditorSelection = get_editor_interface().get_selection()
	if selection == null:
		return

	selection.clear()
	selection.add_node(target_node)
	get_editor_interface().edit_node(target_node)

func get_data_ids(data_kind: String) -> Array[String]:
	var entries: Array[Dictionary] = get_data_id_entries(data_kind)
	if not entries.is_empty():
		var ids: Array[String] = []
		for entry in entries:
			var id_text: String = str(entry.get("id", "")).strip_edges()
			if not id_text.is_empty():
				ids.append(id_text)
		return ids

	var normalized_kind: String = data_kind.strip_edges().to_lower()
	var result: Array[String] = []
	match normalized_kind:
		DATA_KIND_QUEST:
			result = _load_ids_from_json_directory("res://data/quests")
		DATA_KIND_RECIPE:
			result = _load_ids_from_json_directory("res://data/recipes")
		DATA_KIND_ITEM:
			var item_ids: Array[String] = _load_ids_from_json_directory("res://data/items")
			if item_ids.is_empty():
				item_ids = _load_ids_from_json_dict_files(["res://data/items.json", "res://data/json/items.json"])
			result = item_ids
		DATA_KIND_SKILL:
			result = _load_ids_from_json_directory("res://data/skills")
		DATA_KIND_EFFECT:
			result = _load_ids_from_json_directory("res://data/json/effects")
		DATA_KIND_CHARACTER:
			return _load_ids_from_json_directory("res://data/characters")
		_:
			result = []
	return result

func get_data_id_entries(data_kind: String) -> Array[Dictionary]:
	var normalized_kind: String = data_kind.strip_edges().to_lower()
	match normalized_kind:
		DATA_KIND_NPC:
			return _load_named_entries_from_json_dict_files(["res://data/json/npcs.json", "res://data/npcs.json"])
		DATA_KIND_ENEMY:
			return _load_named_entries_from_json_dict_files(["res://data/json/enemies.json", "res://data/enemies.json"])
		DATA_KIND_ITEM:
			var item_entries: Array[Dictionary] = _load_named_entries_from_json_directory("res://data/items")
			if item_entries.is_empty():
				item_entries = _load_named_entries_from_json_dict_files(["res://data/items.json", "res://data/json/items.json"])
			return item_entries
		DATA_KIND_QUEST:
			return _load_named_entries_from_json_directory("res://data/quests", ["title", "name"])
		DATA_KIND_RECIPE:
			return _load_named_entries_from_json_directory("res://data/recipes")
		DATA_KIND_SKILL:
			return _load_named_entries_from_json_directory("res://data/skills")
		DATA_KIND_EFFECT:
			return _load_named_entries_from_json_directory("res://data/json/effects")
		DATA_KIND_CHARACTER:
			return _load_named_entries_from_json_directory("res://data/characters")
		_:
			return []

func _load_ids_from_json_dict_files(paths: Array[String]) -> Array[String]:
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var ids: Array[String] = _extract_ids_from_json_dict(path)
		if not ids.is_empty():
			return ids
	return []

func _extract_ids_from_json_dict(path: String) -> Array[String]:
	var json_text: String = FileAccess.get_file_as_string(path)
	if json_text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return []
	var result: Array[String] = []
	for key in parsed.keys():
		var key_text: String = str(key).strip_edges()
		if not key_text.is_empty():
			result.append(key_text)
	result.sort()
	return result

func _load_ids_from_json_directory(directory_path: String) -> Array[String]:
	var ids: Array[String] = []
	var dir: DirAccess = DirAccess.open(directory_path)
	if not dir:
		return ids

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var id_text: String = file_name.trim_suffix(".json").strip_edges()
			if not id_text.is_empty():
				ids.append(id_text)
		file_name = dir.get_next()
	dir.list_dir_end()

	ids.sort()
	return ids

func _load_named_entries_from_json_dict_files(paths: Array[String], name_keys: Array[String] = []) -> Array[Dictionary]:
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var entries: Array[Dictionary] = _extract_named_entries_from_json_dict(path, name_keys)
		if not entries.is_empty():
			return entries
	return []

func _extract_named_entries_from_json_dict(path: String, name_keys: Array[String] = []) -> Array[Dictionary]:
	var json_text: String = FileAccess.get_file_as_string(path)
	if json_text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return []
	var parsed_dict: Dictionary = parsed as Dictionary

	var ids: Array[String] = []
	for key in parsed_dict.keys():
		var key_text: String = str(key).strip_edges()
		if not key_text.is_empty():
			ids.append(key_text)
	ids.sort()

	var result: Array[Dictionary] = []
	for id_text in ids:
		var entry_data: Dictionary = parsed_dict.get(id_text, {}) as Dictionary
		var item_name: String = _extract_display_name_from_dictionary(entry_data, name_keys)
		result.append(_build_data_id_entry(id_text, item_name))
	return result

func _load_named_entries_from_json_directory(directory_path: String, name_keys: Array[String] = []) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(directory_path)
	if not dir:
		return entries

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var id_text: String = file_name.trim_suffix(".json").strip_edges()
			if not id_text.is_empty():
				var file_path: String = "%s/%s" % [directory_path, file_name]
				var item_name: String = _extract_name_from_json_file(file_path, name_keys)
				entries.append(_build_data_id_entry(id_text, item_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	entries.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("id", "")) < str(b.get("id", "")))
	return entries

func _extract_name_from_json_file(path: String, name_keys: Array[String] = []) -> String:
	var json_text: String = FileAccess.get_file_as_string(path)
	if json_text.is_empty():
		return ""
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed is Dictionary:
		return _extract_display_name_from_dictionary(parsed as Dictionary, name_keys)
	return ""

func _extract_display_name_from_dictionary(data: Dictionary, name_keys: Array[String] = []) -> String:
	var preferred_keys: Array[String] = name_keys
	if preferred_keys.is_empty():
		preferred_keys = ["name"]

	for key in preferred_keys:
		var value: String = str(data.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""

func _build_data_id_entry(id_text: String, display_name: String) -> Dictionary:
	var normalized_id: String = id_text.strip_edges()
	var normalized_name: String = display_name.strip_edges()
	var label: String = normalized_id
	if not normalized_name.is_empty():
		label = "%s | %s" % [normalized_id, normalized_name]
	return {
		"id": normalized_id,
		"label": label
	}

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
