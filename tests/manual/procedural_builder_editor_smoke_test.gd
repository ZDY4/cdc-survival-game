extends Node3D

const WALL_SCRIPT_PATH: String = "res://addons/cdc_procedural_builder/runtime/proc_wall_3d.gd"
const FENCE_SCRIPT_PATH: String = "res://addons/cdc_procedural_builder/runtime/proc_fence_3d.gd"
const HOUSE_SCRIPT_PATH: String = "res://addons/cdc_procedural_builder/runtime/proc_house_3d.gd"
const PLUGIN_PATH: String = "res://addons/cdc_procedural_builder/plugin.gd"
const INSPECTOR_PLUGIN_PATH: String = "res://addons/cdc_procedural_builder/editor/procedural_builder_inspector_plugin.gd"
const GIZMO_PLUGIN_PATH: String = "res://addons/cdc_procedural_builder/editor/procedural_builder_gizmo_plugin.gd"
const DOCK_PATH: String = "res://addons/cdc_procedural_builder/editor/procedural_builder_dock.gd"

func _ready() -> void:
	_probe_script(PLUGIN_PATH)
	_probe_script(INSPECTOR_PLUGIN_PATH)
	_probe_script(GIZMO_PLUGIN_PATH)
	_probe_script(DOCK_PATH)
	_instantiate_dock()
	_instantiate_inspector_plugin()

	var wall: ProcWall3D = _instantiate_generator("SmokeWall", WALL_SCRIPT_PATH, [
		Vector3.ZERO,
		Vector3(4.0, 0.0, 0.0),
		Vector3(6.0, 0.0, 2.0)
	])
	var fence: ProcFence3D = _instantiate_generator("SmokeFence", FENCE_SCRIPT_PATH, [
		Vector3(-6.0, 0.0, 0.0),
		Vector3(-2.0, 0.0, 0.0),
		Vector3(-2.0, 0.0, 4.0)
	])
	var house: ProcHouse3D = _instantiate_generator("SmokeHouse", HOUSE_SCRIPT_PATH, [
		Vector3(-3.0, 0.0, -3.0),
		Vector3(3.0, 0.0, -3.0),
		Vector3(4.0, 0.0, 2.0),
		Vector3(-2.0, 0.0, 3.0)
	])

	assert(wall.get_preview_mesh_instance().mesh != null, "Wall mesh should be created in smoke test")
	assert(fence.get_preview_mesh_instance().mesh != null, "Fence mesh should be created in smoke test")
	assert(house.get_preview_mesh_instance().mesh != null, "House mesh should be created in smoke test")

	wall.set_control_point(1, Vector3(5.0, 0.0, 0.0))
	fence.insert_control_point(0, Vector3(-4.0, 0.0, 2.0))
	house.add_default_opening()
	house.rebuild_geometry()

	print("[ProceduralBuilderSmoke] Wall/Fence/House updated successfully")
	await get_tree().create_timer(1.5).timeout
	get_tree().quit()

func _probe_script(script_path: String) -> void:
	var script: Variant = load(script_path)
	if script == null:
		push_error("[ProceduralBuilderSmoke] Failed to load %s" % script_path)
	else:
		print("[ProceduralBuilderSmoke] Loaded %s" % script_path)

func _instantiate_dock() -> void:
	var dock_script: Script = load(DOCK_PATH)
	assert(dock_script != null, "Failed to load procedural builder dock")
	var dock: Variant = dock_script.new()
	assert(dock is Control, "Procedural builder dock should extend Control")
	var canvas_layer: CanvasLayer = CanvasLayer.new()
	add_child(canvas_layer)
	canvas_layer.add_child(dock)

func _instantiate_inspector_plugin() -> void:
	var inspector_script: Script = load(INSPECTOR_PLUGIN_PATH)
	assert(inspector_script != null, "Failed to load procedural builder inspector plugin")
	var inspector_plugin: Variant = inspector_script.new()
	assert(inspector_plugin is EditorInspectorPlugin, "Procedural builder inspector plugin should extend EditorInspectorPlugin")

func _instantiate_generator(node_name: String, script_path: String, points: Array[Vector3]) -> Variant:
	var script: Script = load(script_path)
	assert(script != null, "Failed to load %s" % script_path)
	var generator: Variant = script.new()
	assert(generator is ProcShapeGenerator3D, "Smoke test generator must derive from ProcShapeGenerator3D")
	generator.name = node_name
	add_child(generator)
	generator.set_control_points(points)
	generator.rebuild_geometry()
	return generator
