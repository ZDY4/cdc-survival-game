@tool
extends EditorInspectorPlugin

const SpriteRigInspectorPanel = preload("res://addons/cdc_game_editor/sprite_rig_inspector_panel.gd")

var editor_plugin: EditorPlugin


func setup(plugin: EditorPlugin) -> void:
	editor_plugin = plugin


func _can_handle(object: Object) -> bool:
	return object is CharacterSpriteRig


func _parse_begin(object: Object) -> void:
	var rig := object as CharacterSpriteRig
	if rig == null:
		return
	var panel := SpriteRigInspectorPanel.new()
	panel.setup(rig, editor_plugin)
	add_custom_control(panel)
