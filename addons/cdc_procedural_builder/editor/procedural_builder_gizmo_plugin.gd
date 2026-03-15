@tool
class_name ProceduralBuilderGizmoPlugin
extends EditorNode3DGizmoPlugin

var _editor_plugin: EditorPlugin = null

func _init(editor_plugin: EditorPlugin) -> void:
	_editor_plugin = editor_plugin
	create_material("shape_lines", Color(0.15, 0.85, 1.0, 0.85), false, true, false)
	create_handle_material("shape_handles")

func _get_gizmo_name() -> String:
	return "CDCProceduralBuilderGizmo"

func _has_gizmo(node: Node3D) -> bool:
	return node is ProcShapeGenerator3D

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var generator: ProcShapeGenerator3D = gizmo.get_node_3d() as ProcShapeGenerator3D
	if generator == null:
		return

	var lines: PackedVector3Array = generator.get_debug_line_points()
	if lines.size() >= 2:
		gizmo.add_lines(lines, get_material("shape_lines", gizmo), false)

	var handles: PackedVector3Array = PackedVector3Array(generator.get_control_points_copy())
	if not handles.is_empty():
		gizmo.add_handles(handles, get_material("shape_handles", gizmo), PackedInt32Array())

func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	return "Control Point %d" % handle_id

func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	var generator: ProcShapeGenerator3D = gizmo.get_node_3d() as ProcShapeGenerator3D
	return generator.get_control_point(handle_id)

func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var generator: ProcShapeGenerator3D = gizmo.get_node_3d() as ProcShapeGenerator3D
	if generator == null:
		return

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_pos)
	var current_global: Vector3 = generator.to_global(generator.get_control_point(handle_id))
	var plane_normal: Vector3 = generator.global_transform.basis * Vector3.UP
	var plane: Plane = Plane(plane_normal, plane_normal.dot(current_global))
	var intersection: Variant = plane.intersects_ray(ray_origin, ray_direction)
	if intersection == null:
		return

	var local_hit: Vector3 = generator.to_local(intersection)
	var current_local: Vector3 = generator.get_control_point(handle_id)
	local_hit.y = current_local.y
	generator.set_control_point(handle_id, local_hit)
	if _editor_plugin.has_method("select_control_point"):
		_editor_plugin.call("select_control_point", handle_id)

func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	var generator: ProcShapeGenerator3D = gizmo.get_node_3d() as ProcShapeGenerator3D
	if generator == null:
		return

	if cancel:
		generator.set_control_point(handle_id, restore)
		return

	if _editor_plugin.has_method("commit_control_point_move"):
		_editor_plugin.call("commit_control_point_move", generator, handle_id, restore, generator.get_control_point(handle_id))
