@tool
extends EditorPlugin

const EditorHandoffDock = preload("res://addons/cdc_game_editor/editor_handoff_dock.gd")
const ContentRecordEditorWindow = preload("res://addons/cdc_game_editor/content_record_editor_window.gd")
const MapReviewDock = preload("res://addons/cdc_game_editor/map_preview_dock.gd")

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

var content_editor_windows: Dictionary = {}
var utility_windows: Dictionary = {}


func _enter_tree() -> void:
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
	print("CDC Game Editor plugin loaded with independent editor windows")


func _exit_tree() -> void:
	for title in CONTENT_EDITOR_DEFS.values():
		remove_tool_menu_item(str(title))
	remove_tool_menu_item("CDC Map Review")
	remove_tool_menu_item("CDC Agent Handoff")

	for window in content_editor_windows.values():
		if is_instance_valid(window):
			(window as Window).queue_free()
	content_editor_windows.clear()

	for window in utility_windows.values():
		if is_instance_valid(window):
			(window as Window).queue_free()
	utility_windows.clear()


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
		add_child(window)
		content_editor_windows[kind] = window
	_show_window(window)


func _open_map_review() -> void:
	_open_utility_window("map_review", "CDC Map Review", MapReviewDock, Vector2i(1100, 760))


func _open_agent_handoff() -> void:
	_open_utility_window("agent_handoff", "CDC Agent Handoff", EditorHandoffDock, Vector2i(980, 680))


func _open_utility_window(key: String, title: String, content_script: GDScript, default_size: Vector2i) -> void:
	var window: Window = utility_windows.get(key)
	if window == null or not is_instance_valid(window):
		window = Window.new()
		window.title = title
		window.name = title
		window.min_size = Vector2i(720, 480)
		window.size = default_size
		window.close_requested.connect(window.hide)
		var content: Control = content_script.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		window.add_child(content)
		add_child(window)
		utility_windows[key] = window
	_show_window(window)


func _show_window(window: Window) -> void:
	if window.visible:
		window.grab_focus()
		return
	window.popup_centered(window.size)
