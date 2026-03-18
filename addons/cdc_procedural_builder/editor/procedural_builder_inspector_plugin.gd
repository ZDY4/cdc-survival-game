@tool
class_name ProceduralBuilderInspectorPlugin
extends EditorInspectorPlugin

const PANEL_SCRIPT: Script = preload("res://addons/cdc_procedural_builder/editor/procedural_builder_dock.gd")

var _editor_plugin: EditorPlugin = null

func _init(editor_plugin: EditorPlugin = null) -> void:
	_editor_plugin = editor_plugin

func _can_handle(object: Object) -> bool:
	return object is ProcShapeGenerator3D

func _parse_begin(object: Object) -> void:
	var generator: ProcShapeGenerator3D = object as ProcShapeGenerator3D
	if generator == null:
		return

	var panel: ProceduralBuilderDock = PANEL_SCRIPT.new()
	panel.set_embedded_in_inspector(true)
	if _editor_plugin != null and _editor_plugin.has_method("configure_inspector_panel"):
		_editor_plugin.call("configure_inspector_panel", panel, generator)
	else:
		panel.set_target(generator)
	add_custom_control(panel)
