@tool
extends EditorPlugin

const EditorHandoffDock = preload("res://addons/cdc_game_editor/editor_handoff_dock.gd")

var handoff_dock: Control


func _enter_tree() -> void:
	# Godot 迁移期先接通 agent handoff，再逐步挂载专用内容编辑器。
	handoff_dock = EditorHandoffDock.new()
	add_control_to_dock(DOCK_SLOT_LEFT_BR, handoff_dock)
	print("CDC Game Editor plugin loaded with agent handoff dock")


func _exit_tree() -> void:
	if handoff_dock != null:
		remove_control_from_docks(handoff_dock)
		handoff_dock.queue_free()
		handoff_dock = null
