@tool
extends EditorPlugin

const WALL_SCRIPT: Script = preload("res://addons/cdc_procedural_builder/runtime/proc_wall_3d.gd")
const FENCE_SCRIPT: Script = preload("res://addons/cdc_procedural_builder/runtime/proc_fence_3d.gd")
const HOUSE_SCRIPT: Script = preload("res://addons/cdc_procedural_builder/runtime/proc_house_3d.gd")
const INSPECTOR_PLUGIN_SCRIPT: Script = preload("res://addons/cdc_procedural_builder/editor/procedural_builder_inspector_plugin.gd")
const GIZMO_SCRIPT: Script = preload("res://addons/cdc_procedural_builder/editor/procedural_builder_gizmo_plugin.gd")
const NO_MESH_HIT_DISTANCE: float = INF

var _inspector_plugin: ProceduralBuilderInspectorPlugin = null
var _inspector_panel: ProceduralBuilderDock = null
var _gizmo_plugin: ProceduralBuilderGizmoPlugin = null
var _selection: EditorSelection = null
var _current_generator: ProcShapeGenerator3D = null
var _selected_point_index: int = -1
var _selected_opening_index: int = -1

func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()

	_selection = get_editor_interface().get_selection()
	if _selection != null and not _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.connect(_on_selection_changed)

	_inspector_plugin = INSPECTOR_PLUGIN_SCRIPT.new(self)
	add_inspector_plugin(_inspector_plugin)

	_gizmo_plugin = GIZMO_SCRIPT.new(self)
	add_node_3d_gizmo_plugin(_gizmo_plugin)

	add_custom_type("ProcWall3D", "Node3D", WALL_SCRIPT, preload("res://icon.svg"))
	add_custom_type("ProcFence3D", "Node3D", FENCE_SCRIPT, preload("res://icon.svg"))
	add_custom_type("ProcHouse3D", "Node3D", HOUSE_SCRIPT, preload("res://icon.svg"))

func _exit_tree() -> void:
	remove_custom_type("ProcHouse3D")
	remove_custom_type("ProcFence3D")
	remove_custom_type("ProcWall3D")

	if _gizmo_plugin != null:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null

	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
	_inspector_panel = null

	if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.disconnect(_on_selection_changed)

func _handles(object: Object) -> bool:
	return object is ProcShapeGenerator3D

func _edit(object: Object) -> void:
	_set_current_generator(object as ProcShapeGenerator3D)

func _make_visible(_visible: bool) -> void:
	# Inspector plugin visibility is managed by Godot based on the inspected object.
	pass

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not (event is InputEventMouseButton):
		return AFTER_GUI_INPUT_PASS

	var mouse_event: InputEventMouseButton = event
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return AFTER_GUI_INPUT_PASS
	if mouse_event.double_click:
		return AFTER_GUI_INPUT_PASS

	var hit_generator: ProcShapeGenerator3D = _pick_generator_from_mesh(camera, mouse_event.position)
	if hit_generator == null:
		return AFTER_GUI_INPUT_PASS
	if hit_generator == _current_generator:
		return AFTER_GUI_INPUT_PASS

	_select_generator(hit_generator)
	return AFTER_GUI_INPUT_STOP

func select_control_point(index: int) -> void:
	_selected_point_index = index
	if _inspector_panel != null and is_instance_valid(_inspector_panel):
		_inspector_panel.set_selected_point_index(index)

func configure_inspector_panel(panel: ProceduralBuilderDock, generator: ProcShapeGenerator3D) -> void:
	if panel == null:
		return
	_inspector_panel = panel
	if not panel.tree_exited.is_connected(_on_inspector_panel_exited):
		panel.tree_exited.connect(_on_inspector_panel_exited.bind(panel), CONNECT_ONE_SHOT)
	_connect_panel_signals(panel)
	panel.set_target(generator)
	panel.set_selected_point_index(_selected_point_index)
	panel.set_selected_opening_index(_selected_opening_index)

func commit_control_point_move(generator: ProcShapeGenerator3D, handle_id: int, previous_value: Vector3, current_value: Vector3) -> void:
	if generator == null or previous_value.is_equal_approx(current_value):
		return

	var do_points: Array = generator.get_control_points_copy()
	var undo_points: Array = generator.get_control_points_copy()
	undo_points[handle_id] = generator.snap_point(previous_value)
	do_points[handle_id] = generator.snap_point(current_value)

	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	undo_redo.create_action("Move Procedural Control Point")
	undo_redo.add_do_property(generator, "control_points", do_points)
	undo_redo.add_undo_property(generator, "control_points", undo_points)
	undo_redo.add_do_method(generator, "notify_property_list_changed")
	undo_redo.add_undo_method(generator, "notify_property_list_changed")
	undo_redo.add_do_method(self, "_refresh_from_generator", generator)
	undo_redo.add_undo_method(self, "_refresh_from_generator", generator)
	undo_redo.commit_action()

func _on_selection_changed() -> void:
	if _selection == null:
		return
	var selected_nodes: Array = _selection.get_selected_nodes()
	if selected_nodes.size() == 1 and selected_nodes[0] is ProcShapeGenerator3D:
		_set_current_generator(selected_nodes[0] as ProcShapeGenerator3D)
	else:
		_set_current_generator(null)

func _set_current_generator(generator: ProcShapeGenerator3D) -> void:
	if _current_generator == generator:
		_refresh_from_generator(generator)
		return

	if _current_generator != null and _current_generator.rebuilt.is_connected(_on_generator_rebuilt):
		_current_generator.rebuilt.disconnect(_on_generator_rebuilt)

	_current_generator = generator
	_selected_point_index = -1
	_selected_opening_index = -1

	if _current_generator != null and not _current_generator.rebuilt.is_connected(_on_generator_rebuilt):
		_current_generator.rebuilt.connect(_on_generator_rebuilt)

	_refresh_inspector()

func _select_generator(generator: ProcShapeGenerator3D) -> void:
	if generator == null or _selection == null:
		return
	_selection.clear()
	_selection.add_node(generator)
	get_editor_interface().edit_node(generator)
	_set_current_generator(generator)

func _refresh_from_generator(generator: ProcShapeGenerator3D = null) -> void:
	if generator != null and generator != _current_generator:
		return
	if _inspector_panel != null and is_instance_valid(_inspector_panel):
		_inspector_panel.set_target(_current_generator)
		_inspector_panel.set_selected_point_index(_selected_point_index)
		_inspector_panel.set_selected_opening_index(_selected_opening_index)

func _on_generator_rebuilt() -> void:
	_refresh_from_generator(_current_generator)

func _on_control_point_selected(index: int) -> void:
	_selected_point_index = index
	_refresh_from_generator(_current_generator)

func _on_opening_selected(index: int) -> void:
	_selected_opening_index = index
	_refresh_from_generator(_current_generator)

func _on_add_point_requested() -> void:
	if _current_generator == null:
		return
	var updated_points: Array = _current_generator.get_control_points_copy()
	var new_point: Vector3 = _build_appended_point(_current_generator)
	updated_points.append(new_point)
	_apply_points_action("Add Procedural Control Point", updated_points)
	_selected_point_index = updated_points.size() - 1

func _on_insert_point_requested() -> void:
	if _current_generator == null or _current_generator.control_points.size() < 2:
		return
	var segment_index: int = _selected_point_index
	if segment_index < 0:
		segment_index = 0
	if segment_index >= _current_generator.get_segment_count():
		segment_index = _current_generator.get_segment_count() - 1

	var segment_points: Array = _current_generator.get_segment_points(segment_index)
	if segment_points.size() != 2:
		return

	var midpoint: Vector3 = _current_generator.snap_point((segment_points[0] + segment_points[1]) * 0.5)
	var updated_points: Array = _current_generator.get_control_points_copy()
	updated_points.insert(segment_index + 1, midpoint)
	_apply_points_action("Insert Procedural Control Point", updated_points)
	_selected_point_index = segment_index + 1

func _on_remove_point_requested(index: int) -> void:
	if _current_generator == null:
		return
	if _current_generator.control_points.size() <= _current_generator.get_minimum_point_count():
		return
	var updated_points: Array = _current_generator.get_control_points_copy()
	updated_points.remove_at(index)
	_apply_points_action("Remove Procedural Control Point", updated_points)
	_selected_point_index = clampi(index - 1, -1, updated_points.size() - 1)

func _on_closed_toggled(value: bool) -> void:
	if _current_generator == null:
		return
	var previous_value: bool = _current_generator.closed
	if previous_value == value:
		return
	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	undo_redo.create_action("Toggle Procedural Path Closed")
	undo_redo.add_do_method(_current_generator, "set_closed", value)
	undo_redo.add_undo_method(_current_generator, "set_closed", previous_value)
	undo_redo.add_do_method(self, "_refresh_from_generator", _current_generator)
	undo_redo.add_undo_method(self, "_refresh_from_generator", _current_generator)
	undo_redo.commit_action()

func _on_add_opening_requested() -> void:
	if not (_current_generator is ProcHouse3D):
		return
	var house: ProcHouse3D = _current_generator as ProcHouse3D
	var previous_openings: Array = _duplicate_openings(house.openings)
	var updated_openings: Array = _duplicate_openings(house.openings)
	var new_opening: HouseOpeningResource = HouseOpeningResource.new()
	new_opening.edge_index = 0
	new_opening.offset_on_edge = 1.5
	new_opening.width = 1.2
	new_opening.height = 2.1
	new_opening.sill_height = 0.0
	updated_openings.append(new_opening)

	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	undo_redo.create_action("Add House Opening")
	undo_redo.add_do_method(house, "set_openings", updated_openings)
	undo_redo.add_undo_method(house, "set_openings", previous_openings)
	undo_redo.add_do_method(self, "_refresh_from_generator", house)
	undo_redo.add_undo_method(self, "_refresh_from_generator", house)
	undo_redo.commit_action()
	_selected_opening_index = updated_openings.size() - 1

func _on_remove_opening_requested(index: int) -> void:
	if not (_current_generator is ProcHouse3D):
		return
	var house: ProcHouse3D = _current_generator as ProcHouse3D
	if index < 0 or index >= house.openings.size():
		return
	var previous_openings: Array = _duplicate_openings(house.openings)
	var updated_openings: Array = _duplicate_openings(house.openings)
	updated_openings.remove_at(index)

	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	undo_redo.create_action("Remove House Opening")
	undo_redo.add_do_method(house, "set_openings", updated_openings)
	undo_redo.add_undo_method(house, "set_openings", previous_openings)
	undo_redo.add_do_method(self, "_refresh_from_generator", house)
	undo_redo.add_undo_method(self, "_refresh_from_generator", house)
	undo_redo.commit_action()
	_selected_opening_index = clampi(index - 1, -1, updated_openings.size() - 1)

func _apply_points_action(action_name: String, updated_points: Array) -> void:
	var previous_points: Array = _current_generator.get_control_points_copy()
	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	undo_redo.create_action(action_name)
	undo_redo.add_do_property(_current_generator, "control_points", updated_points)
	undo_redo.add_undo_property(_current_generator, "control_points", previous_points)
	undo_redo.add_do_method(_current_generator, "notify_property_list_changed")
	undo_redo.add_undo_method(_current_generator, "notify_property_list_changed")
	undo_redo.add_do_method(self, "_refresh_from_generator", _current_generator)
	undo_redo.add_undo_method(self, "_refresh_from_generator", _current_generator)
	undo_redo.commit_action()

func _build_appended_point(generator: ProcShapeGenerator3D) -> Vector3:
	if generator.control_points.is_empty():
		return Vector3.ZERO
	if generator.control_points.size() == 1:
		return generator.snap_point(generator.control_points[0] + Vector3.RIGHT * generator.snap_step)

	var last_point: Vector3 = generator.control_points[generator.control_points.size() - 1]
	var previous_point: Vector3 = generator.control_points[generator.control_points.size() - 2]
	var direction: Vector3 = last_point - previous_point
	if direction.length() <= 0.001:
		direction = Vector3.RIGHT * generator.snap_step
	return generator.snap_point(last_point + direction.normalized() * maxf(generator.snap_step, 1.0))

func _duplicate_openings(source: Array) -> Array:
	var duplicated: Array = []
	for opening in source:
		if opening != null:
			duplicated.append(opening.duplicate_opening())
	return duplicated

func _pick_generator_from_mesh(camera: Camera3D, screen_position: Vector2) -> ProcShapeGenerator3D:
	var scene_root: Node = get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		return null

	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var best_distance: float = NO_MESH_HIT_DISTANCE
	var best_generator: ProcShapeGenerator3D = null
	for generator in _collect_generators(scene_root):
		var hit_distance: float = _intersect_generator_mesh(generator, ray_origin, ray_direction)
		if hit_distance < best_distance:
			best_distance = hit_distance
			best_generator = generator
	return best_generator

func _collect_generators(root: Node) -> Array:
	var generators: Array = []
	for child in root.get_children():
		if child is ProcShapeGenerator3D:
			generators.append(child)
		generators.append_array(_collect_generators(child))
	return generators

func _intersect_generator_mesh(generator: ProcShapeGenerator3D, ray_origin: Vector3, ray_direction: Vector3) -> float:
	var preview_mesh: MeshInstance3D = generator.get_preview_mesh_instance()
	if preview_mesh == null or preview_mesh.mesh == null:
		return NO_MESH_HIT_DISTANCE

	var mesh: Mesh = preview_mesh.mesh
	var inverse_transform: Transform3D = preview_mesh.global_transform.affine_inverse()
	var local_origin: Vector3 = inverse_transform * ray_origin
	var local_direction: Vector3 = inverse_transform.basis * ray_direction

	var best_distance: float = NO_MESH_HIT_DISTANCE
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		if arrays.is_empty():
			continue

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = PackedInt32Array()
		var indices_variant: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices_variant != null:
			indices = indices_variant
		if indices.is_empty():
			for vertex_index in range(0, vertices.size(), 3):
				best_distance = minf(best_distance, _intersect_triangle(vertices[vertex_index], vertices[vertex_index + 1], vertices[vertex_index + 2], local_origin, local_direction, preview_mesh.global_transform))
		else:
			for triangle_index in range(0, indices.size(), 3):
				best_distance = minf(
					best_distance,
					_intersect_triangle(
						vertices[indices[triangle_index]],
						vertices[indices[triangle_index + 1]],
						vertices[indices[triangle_index + 2]],
						local_origin,
						local_direction,
						preview_mesh.global_transform
					)
				)
	return best_distance

func _intersect_triangle(a: Vector3, b: Vector3, c: Vector3, local_origin: Vector3, local_direction: Vector3, mesh_transform: Transform3D) -> float:
	var local_hit: Variant = Geometry3D.ray_intersects_triangle(local_origin, local_direction, a, b, c)
	if local_hit == null:
		return NO_MESH_HIT_DISTANCE

	var world_hit: Vector3 = mesh_transform * local_hit
	return world_hit.distance_to(mesh_transform * local_origin)

func _connect_panel_signals(panel: ProceduralBuilderDock) -> void:
	if not panel.control_point_selected.is_connected(_on_control_point_selected):
		panel.control_point_selected.connect(_on_control_point_selected)
	if not panel.opening_selected.is_connected(_on_opening_selected):
		panel.opening_selected.connect(_on_opening_selected)
	if not panel.add_point_requested.is_connected(_on_add_point_requested):
		panel.add_point_requested.connect(_on_add_point_requested)
	if not panel.insert_point_requested.is_connected(_on_insert_point_requested):
		panel.insert_point_requested.connect(_on_insert_point_requested)
	if not panel.remove_point_requested.is_connected(_on_remove_point_requested):
		panel.remove_point_requested.connect(_on_remove_point_requested)
	if not panel.closed_toggled.is_connected(_on_closed_toggled):
		panel.closed_toggled.connect(_on_closed_toggled)
	if not panel.add_opening_requested.is_connected(_on_add_opening_requested):
		panel.add_opening_requested.connect(_on_add_opening_requested)
	if not panel.remove_opening_requested.is_connected(_on_remove_opening_requested):
		panel.remove_opening_requested.connect(_on_remove_opening_requested)

func _on_inspector_panel_exited(panel: ProceduralBuilderDock) -> void:
	if _inspector_panel == panel:
		_inspector_panel = null

func _refresh_inspector() -> void:
	if _current_generator == null:
		return
	if _inspector_panel != null and is_instance_valid(_inspector_panel):
		_refresh_from_generator(_current_generator)
		return
	var editor_interface: EditorInterface = get_editor_interface()
	if editor_interface == null:
		return
	editor_interface.edit_node(_current_generator)
