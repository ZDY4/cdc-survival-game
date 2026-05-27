@tool
extends EditorPlugin

const EditorHandoffDock = preload("res://addons/cdc_game_editor/editor_handoff_dock.gd")
const ContentBrowserDock = preload("res://addons/cdc_game_editor/content_browser_dock.gd")
const MapPreviewDock = preload("res://addons/cdc_game_editor/map_preview_dock.gd")

var handoff_dock: Control
var content_browser_dock: Control
var map_preview_dock: Control


func _enter_tree() -> void:
	# 迁移期先提供浏览、表单保存、地图复核和 agent handoff，再逐步接上专用编辑器。
	content_browser_dock = ContentBrowserDock.new()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, content_browser_dock)
	map_preview_dock = MapPreviewDock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, map_preview_dock)
	handoff_dock = EditorHandoffDock.new()
	add_control_to_dock(DOCK_SLOT_LEFT_BR, handoff_dock)
	print("CDC Game Editor plugin loaded with content browser, map preview, and agent handoff docks")


func _exit_tree() -> void:
	if handoff_dock != null:
		remove_control_from_docks(handoff_dock)
		handoff_dock.queue_free()
		handoff_dock = null
	if content_browser_dock != null:
		remove_control_from_docks(content_browser_dock)
		content_browser_dock.queue_free()
		content_browser_dock = null
	if map_preview_dock != null:
		remove_control_from_docks(map_preview_dock)
		map_preview_dock.queue_free()
		map_preview_dock = null
