@tool
extends EditorPlugin

const EditorHandoffDock = preload("res://addons/cdc_game_editor/editor_handoff_dock.gd")
const ContentBrowserDock = preload("res://addons/cdc_game_editor/content_browser_dock.gd")
const MapPreviewDock = preload("res://addons/cdc_game_editor/map_preview_dock.gd")

var handoff_dock: Control
var content_browser_dock: Control
var map_preview_dock: Control
var editor_panel: TabContainer


func _enter_tree() -> void:
	# 使用单个底部面板承载全部工具，避免多个侧边 dock 抢占 Godot editor 布局空间。
	editor_panel = TabContainer.new()
	editor_panel.name = "CDC Game Editor"
	editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_browser_dock = ContentBrowserDock.new()
	editor_panel.add_child(content_browser_dock)
	map_preview_dock = MapPreviewDock.new()
	editor_panel.add_child(map_preview_dock)
	handoff_dock = EditorHandoffDock.new()
	editor_panel.add_child(handoff_dock)
	add_control_to_bottom_panel(editor_panel, "CDC Game Editor")
	print("CDC Game Editor plugin loaded with tabbed bottom panel")


func _exit_tree() -> void:
	if editor_panel != null:
		remove_control_from_bottom_panel(editor_panel)
		editor_panel.queue_free()
		editor_panel = null
	handoff_dock = null
	content_browser_dock = null
	map_preview_dock = null
