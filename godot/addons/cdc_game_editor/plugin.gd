@tool
extends EditorPlugin

const EditorHandoffDock = preload("res://addons/cdc_game_editor/editor_handoff_dock.gd")
const ContentRecordEditorWindow = preload("res://addons/cdc_game_editor/content_record_editor_window.gd")
const MapReviewDock = preload("res://addons/cdc_game_editor/map_preview_dock.gd")
const MapTilePaletteWindow = preload("res://addons/cdc_game_editor/map_tile_palette_window.gd")
const SpriteRigInspectorPlugin = preload("res://addons/cdc_game_editor/sprite_rig_inspector_plugin.gd")
const SpriteRigInspectorWindow = preload("res://addons/cdc_game_editor/sprite_rig_inspector_window.gd")

const CONTENT_EDITOR_DEFS := {
	"item": "CDC Item Editor",
	"recipe": "CDC Recipe Editor",
	"character": "CDC Character Editor",
	"dialogue": "CDC Dialogue Editor",
	"quest": "CDC Quest Editor",
	"skill": "CDC Skill Editor",
	"skill_tree": "CDC Skill Tree Editor",
	"settlement": "CDC Settlement Editor",
	"overworld": "CDC Overworld Editor",
}

const MENU_ITEM_EDITOR := 100
const MENU_RECIPE_EDITOR := 110
const MENU_CHARACTER_EDITOR := 120
const MENU_DIALOGUE_EDITOR := 130
const MENU_QUEST_EDITOR := 140
const MENU_SKILL_EDITOR := 150
const MENU_SKILL_TREE_EDITOR := 160
const MENU_SETTLEMENT_EDITOR := 170
const MENU_OVERWORLD_EDITOR := 180
const MENU_MAP_REVIEW := 300
const MENU_AGENT_HANDOFF := 310
const MENU_MAP_TILE_PALETTE := 330
const SPRITE_RIG_EDITOR_PREVIEW_INTERVAL := 0.05
const SPRITE_RIG_EDITOR_PREVIEW_EPSILON := 0.001

var content_editor_windows: Dictionary = {}
var utility_windows: Dictionary = {}
var cdc_menu: PopupMenu
var editor_menu_bar: MenuBar
var using_tool_menu_fallback := false
var sprite_rig_inspector_plugin: EditorInspectorPlugin
var selected_sprite_rig: CharacterSpriteRig
var _sprite_rig_preview_accumulator := 0.0
var _last_editor_camera_position := Vector3(INF, INF, INF)
var _last_editor_camera_rotation := Vector3(INF, INF, INF)
var _last_preview_rig_position := Vector3(INF, INF, INF)
var _last_preview_rig_rotation := Vector3(INF, INF, INF)


func _enter_tree() -> void:
	_install_cdc_top_menu()
	_install_sprite_rig_inspector_plugin()
	_connect_editor_selection()
	set_process(true)
	if cdc_menu != null:
		print("CDC Game Editor plugin loaded with top menu and independent editor windows")
		return
	_install_tool_menu_fallback()
	using_tool_menu_fallback = true
	print("CDC Game Editor plugin loaded with Project > Tools fallback and independent editor windows")


func _exit_tree() -> void:
	set_process(false)
	_disconnect_editor_selection()
	selected_sprite_rig = null
	if cdc_menu != null:
		if is_instance_valid(cdc_menu):
			cdc_menu.queue_free()
		cdc_menu = null
	editor_menu_bar = null

	if using_tool_menu_fallback:
		for title in CONTENT_EDITOR_DEFS.values():
			remove_tool_menu_item(str(title))
		remove_tool_menu_item("CDC Map Review")
		remove_tool_menu_item("CDC Agent Handoff")
		remove_tool_menu_item("CDC Map Tile Palette")
		using_tool_menu_fallback = false
	if sprite_rig_inspector_plugin != null:
		remove_inspector_plugin(sprite_rig_inspector_plugin)
		sprite_rig_inspector_plugin = null

	for window in content_editor_windows.values():
		if is_instance_valid(window):
			(window as Window).queue_free()
	content_editor_windows.clear()

	for window in utility_windows.values():
		if is_instance_valid(window):
			(window as Window).queue_free()
	utility_windows.clear()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_sprite_rig_preview_accumulator += delta
	if _sprite_rig_preview_accumulator < SPRITE_RIG_EDITOR_PREVIEW_INTERVAL:
		return
	_sprite_rig_preview_accumulator = 0.0
	_update_selected_sprite_rig_from_editor_camera()


func _install_cdc_top_menu() -> void:
	var base_control := get_editor_interface().get_base_control()
	editor_menu_bar = _find_menu_bar(base_control)
	if editor_menu_bar == null:
		push_warning("CDC Game Editor could not find the Godot editor MenuBar.")
		return

	cdc_menu = PopupMenu.new()
	cdc_menu.name = "CDC"
	cdc_menu.id_pressed.connect(_on_cdc_menu_id_pressed)
	_populate_cdc_menu(cdc_menu)
	editor_menu_bar.add_child(cdc_menu)
	_move_cdc_menu_after_help()


func _install_tool_menu_fallback() -> void:
	add_tool_menu_item("CDC Item Editor", _open_item_editor)
	add_tool_menu_item("CDC Recipe Editor", _open_recipe_editor)
	add_tool_menu_item("CDC Character Editor", _open_character_editor)
	add_tool_menu_item("CDC Dialogue Editor", _open_dialogue_editor)
	add_tool_menu_item("CDC Quest Editor", _open_quest_editor)
	add_tool_menu_item("CDC Skill Editor", _open_skill_editor)
	add_tool_menu_item("CDC Skill Tree Editor", _open_skill_tree_editor)
	add_tool_menu_item("CDC Settlement Editor", _open_settlement_editor)
	add_tool_menu_item("CDC Overworld Editor", _open_overworld_editor)
	add_tool_menu_item("CDC Map Review", _open_map_review)
	add_tool_menu_item("CDC Agent Handoff", _open_agent_handoff)
	add_tool_menu_item("CDC Map Tile Palette", _open_map_tile_palette)


func _populate_cdc_menu(menu: PopupMenu) -> void:
	menu.clear()
	menu.add_item("Item Editor", MENU_ITEM_EDITOR)
	menu.add_item("Recipe Editor", MENU_RECIPE_EDITOR)
	menu.add_item("Character Editor", MENU_CHARACTER_EDITOR)
	menu.add_item("Dialogue Editor", MENU_DIALOGUE_EDITOR)
	menu.add_item("Quest Editor", MENU_QUEST_EDITOR)
	menu.add_separator()
	menu.add_item("Skill Editor", MENU_SKILL_EDITOR)
	menu.add_item("Skill Tree Editor", MENU_SKILL_TREE_EDITOR)
	menu.add_item("Settlement Editor", MENU_SETTLEMENT_EDITOR)
	menu.add_item("Overworld Editor", MENU_OVERWORLD_EDITOR)
	menu.add_separator()
	menu.add_item("Map Review", MENU_MAP_REVIEW)
	menu.add_item("Agent Handoff", MENU_AGENT_HANDOFF)
	menu.add_item("Map Tile Palette", MENU_MAP_TILE_PALETTE)


func _install_sprite_rig_inspector_plugin() -> void:
	if sprite_rig_inspector_plugin != null:
		return
	sprite_rig_inspector_plugin = SpriteRigInspectorPlugin.new()
	sprite_rig_inspector_plugin.setup(self)
	add_inspector_plugin(sprite_rig_inspector_plugin)


func _connect_editor_selection() -> void:
	var selection := get_editor_interface().get_selection()
	if selection == null:
		return
	if not selection.selection_changed.is_connected(_on_editor_selection_changed):
		selection.selection_changed.connect(_on_editor_selection_changed)
	_on_editor_selection_changed()


func _disconnect_editor_selection() -> void:
	var selection := get_editor_interface().get_selection()
	if selection == null:
		return
	if selection.selection_changed.is_connected(_on_editor_selection_changed):
		selection.selection_changed.disconnect(_on_editor_selection_changed)


func _on_editor_selection_changed() -> void:
	var rig := _selected_sprite_rig_from_editor()
	if rig == selected_sprite_rig:
		return
	selected_sprite_rig = rig
	_reset_sprite_rig_editor_preview_cache()


func _selected_sprite_rig_from_editor() -> CharacterSpriteRig:
	var selection := get_editor_interface().get_selection()
	if selection == null:
		return null
	for node in selection.get_selected_nodes():
		var rig := _sprite_rig_from_node(node)
		if rig != null:
			return rig
	return null


func _sprite_rig_from_node(node: Node) -> CharacterSpriteRig:
	var current := node
	while current != null:
		if current is CharacterSpriteRig:
			return current as CharacterSpriteRig
		current = current.get_parent()
	return null


func _reset_sprite_rig_editor_preview_cache() -> void:
	_sprite_rig_preview_accumulator = 0.0
	_last_editor_camera_position = Vector3(INF, INF, INF)
	_last_editor_camera_rotation = Vector3(INF, INF, INF)
	_last_preview_rig_position = Vector3(INF, INF, INF)
	_last_preview_rig_rotation = Vector3(INF, INF, INF)


func _update_selected_sprite_rig_from_editor_camera() -> void:
	if not is_instance_valid(selected_sprite_rig):
		selected_sprite_rig = null
		return
	if selected_sprite_rig.profile == null:
		return
	var camera := _editor_viewport_camera()
	if camera == null:
		return
	var camera_position := camera.global_position
	var camera_rotation := camera.global_transform.basis.get_euler()
	var rig_position := selected_sprite_rig.global_position
	var rig_rotation := selected_sprite_rig.global_transform.basis.get_euler()
	if not _sprite_rig_editor_preview_changed(camera_position, camera_rotation, rig_position, rig_rotation):
		return
	_last_editor_camera_position = camera_position
	_last_editor_camera_rotation = camera_rotation
	_last_preview_rig_position = rig_position
	_last_preview_rig_rotation = rig_rotation
	selected_sprite_rig.apply_direction_from_world_position(camera_position)


func _sprite_rig_editor_preview_changed(camera_position: Vector3, camera_rotation: Vector3, rig_position: Vector3, rig_rotation: Vector3) -> bool:
	var epsilon_squared := SPRITE_RIG_EDITOR_PREVIEW_EPSILON * SPRITE_RIG_EDITOR_PREVIEW_EPSILON
	return camera_position.distance_squared_to(_last_editor_camera_position) > epsilon_squared \
			or camera_rotation.distance_squared_to(_last_editor_camera_rotation) > epsilon_squared \
			or rig_position.distance_squared_to(_last_preview_rig_position) > epsilon_squared \
			or rig_rotation.distance_squared_to(_last_preview_rig_rotation) > epsilon_squared


func _editor_viewport_camera() -> Camera3D:
	for index in range(4):
		var viewport := get_editor_interface().get_editor_viewport_3d(index)
		if viewport == null:
			continue
		var camera := viewport.get_camera_3d()
		if is_instance_valid(camera):
			return camera
	return null


func _move_cdc_menu_after_help() -> void:
	if editor_menu_bar == null or cdc_menu == null:
		return
	var help_index := -1
	for i in range(editor_menu_bar.get_child_count()):
		var child := editor_menu_bar.get_child(i)
		if child is PopupMenu and str(child.name) == "Help":
			help_index = i
			break
	if help_index >= 0:
		editor_menu_bar.move_child(cdc_menu, help_index + 1)


func _find_menu_bar(root: Node) -> MenuBar:
	if root is MenuBar:
		return root as MenuBar
	for child in root.get_children():
		var found := _find_menu_bar(child)
		if found != null:
			return found
	return null


func _on_cdc_menu_id_pressed(id: int) -> void:
	match id:
		MENU_ITEM_EDITOR:
			_open_item_editor()
		MENU_RECIPE_EDITOR:
			_open_recipe_editor()
		MENU_CHARACTER_EDITOR:
			_open_character_editor()
		MENU_DIALOGUE_EDITOR:
			_open_dialogue_editor()
		MENU_QUEST_EDITOR:
			_open_quest_editor()
		MENU_SKILL_EDITOR:
			_open_skill_editor()
		MENU_SKILL_TREE_EDITOR:
			_open_skill_tree_editor()
		MENU_SETTLEMENT_EDITOR:
			_open_settlement_editor()
		MENU_OVERWORLD_EDITOR:
			_open_overworld_editor()
		MENU_MAP_REVIEW:
			_open_map_review()
		MENU_AGENT_HANDOFF:
			_open_agent_handoff()
		MENU_MAP_TILE_PALETTE:
			_open_map_tile_palette()


func _open_item_editor() -> void:
	_open_content_editor("item")


func _open_recipe_editor() -> void:
	_open_content_editor("recipe")


func _open_character_editor() -> void:
	_open_content_editor("character")


func _open_dialogue_editor() -> void:
	_open_content_editor("dialogue")


func _open_quest_editor() -> void:
	_open_content_editor("quest")


func _open_skill_editor() -> void:
	_open_content_editor("skill")


func _open_skill_tree_editor() -> void:
	_open_content_editor("skill_tree")


func _open_settlement_editor() -> void:
	_open_content_editor("settlement")


func _open_overworld_editor() -> void:
	_open_content_editor("overworld")


func _open_content_editor(kind: String) -> void:
	if not CONTENT_EDITOR_DEFS.has(kind):
		push_warning("Unsupported CDC content editor kind: %s" % kind)
		return
	var window: Window = content_editor_windows.get(kind)
	if window == null or not is_instance_valid(window):
		window = ContentRecordEditorWindow.new()
		window.setup(kind, str(CONTENT_EDITOR_DEFS[kind]))
		_configure_editor_window(window)
		_attach_editor_window(window)
		content_editor_windows[kind] = window
	_show_window(window)


func _open_map_review() -> void:
	_open_utility_window("map_review", "CDC Map Review", MapReviewDock, Vector2i(1100, 760))


func _open_agent_handoff() -> void:
	_open_utility_window("agent_handoff", "CDC Agent Handoff", EditorHandoffDock, Vector2i(980, 680))


func _open_map_tile_palette() -> void:
	_open_utility_window("map_tile_palette", "CDC Map Tile Palette", MapTilePaletteWindow, Vector2i(720, 760))


func open_sprite_rig_inspector_for_rig(rig: CharacterSpriteRig) -> void:
	if rig == null:
		return
	var key := "sprite_rig_inspector_%s" % str(rig.get_instance_id())
	var window: Window = utility_windows.get(key)
	if window == null or not is_instance_valid(window):
		window = SpriteRigInspectorWindow.new()
		window.title = "Sprite Rig Inspector: %s" % rig.name
		window.name = "CDC Sprite Rig Inspector"
		window.size = Vector2i(1120, 760)
		window.setup_for_rig(rig, get_undo_redo())
		_configure_editor_window(window)
		_attach_editor_window(window)
		utility_windows[key] = window
	else:
		window.call("setup_for_rig", rig, get_undo_redo())
	_show_window(window)


func _open_utility_window(key: String, title: String, content_script: GDScript, default_size: Vector2i) -> void:
	var window: Window = utility_windows.get(key)
	if window == null or not is_instance_valid(window):
		window = Window.new()
		window.title = title
		window.name = title
		window.min_size = Vector2i(720, 480)
		window.size = default_size
		window.close_requested.connect(window.hide)
		_configure_editor_window(window)
		var content: Control = content_script.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		window.add_child(content)
		_attach_editor_window(window)
		utility_windows[key] = window
	_show_window(window)


func _configure_editor_window(window: Window) -> void:
	window.borderless = false
	window.unresizable = false
	window.exclusive = false
	window.transient = false
	window.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN


func _attach_editor_window(window: Window) -> void:
	var base_control := get_editor_interface().get_base_control()
	if base_control != null:
		base_control.add_child(window)
		return
	add_child(window)


func _show_window(window: Window) -> void:
	if window.visible:
		window.hide()
	window.popup_centered(window.size)
	if window.current_screen >= 0:
		window.position = _center_position_for_window(window)
		window.grab_focus()
		return
	window.grab_focus()


func _center_position_for_window(window: Window) -> Vector2i:
	var screen_index := window.current_screen
	var screen_position := DisplayServer.screen_get_position(screen_index)
	var screen_size := DisplayServer.screen_get_size(screen_index)
	return screen_position + ((screen_size - window.size) / 2)
