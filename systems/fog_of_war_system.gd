class_name FogOfWarSystem
extends Node3D
## Renders fog of war based on VisionSystem output.

const GRID_SIZE := 1.0

@export var unexplored_color: Color = Color(0.05, 0.05, 0.05, 0.85)
@export var explored_color: Color = Color(0.20, 0.20, 0.20, 0.55)
@export var visible_color: Color = Color(0.0, 0.0, 0.0, 0.0)

var _vision_system: Node = null
var _multimesh_instance: MultiMeshInstance3D = null
var _instance_indices: Dictionary = {}
var _last_visible_set: Dictionary = {}
var _explored_set: Dictionary = {}
var _map_id: String = ""
var _fog_height_offset: float = 0.05
var _bounds: Dictionary = {}
var _initialized: bool = false

func initialize(vision_system: Node, bounds: Dictionary, map_id: String, fog_height_offset: float) -> void:
	_vision_system = vision_system
	_bounds = bounds.duplicate(true)
	_map_id = map_id
	_fog_height_offset = fog_height_offset
	_build_fog_mesh()
	_load_explored_from_gamestate()
	if _vision_system:
		_vision_system.vision_updated.connect(_on_vision_updated)

func _build_fog_mesh() -> void:
	if _bounds.is_empty():
		return
	var min_x := int(_bounds.min_x)
	var max_x := int(_bounds.max_x)
	var min_z := int(_bounds.min_z)
	var max_z := int(_bounds.max_z)
	var width := max_x - min_x + 1
	var depth := max_z - min_z + 1
	if width <= 0 or depth <= 0:
		return

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.instance_count = width * depth
	var plane := PlaneMesh.new()
	plane.size = Vector2(GRID_SIZE, GRID_SIZE)
	multi.mesh = plane

	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = multi
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_multimesh_instance.material_override = material
	add_child(_multimesh_instance)

	var idx := 0
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var cell := Vector3i(x, 0, z)
			_instance_indices[cell] = idx
			var world_pos := GridMovementSystem.grid_to_world(cell)
			world_pos.y = _fog_height_offset
			var transform := Transform3D(Basis.IDENTITY, world_pos)
			multi.set_instance_transform(idx, transform)
			multi.set_instance_color(idx, unexplored_color)
			idx += 1
	_initialized = true

func _load_explored_from_gamestate() -> void:
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return
	if _map_id.is_empty():
		return
	var fow_data = gs.get("fog_of_war_by_map")
	if not fow_data is Dictionary:
		return
	var data = fow_data.get(_map_id, [])
	if not data is Array:
		return
	var cells: Array[Vector3i] = []
	for entry in data:
		var cell := _decode_cell(str(entry))
		cells.append(cell)
	_apply_explored_cells(cells)
	if _vision_system:
		_vision_system.set_explored_cells(cells)

func _apply_explored_cells(cells: Array[Vector3i]) -> void:
	if not _multimesh_instance:
		return
	var multi := _multimesh_instance.multimesh
	for cell in cells:
		if not _instance_indices.has(cell):
			continue
		_explored_set[cell] = true
		var idx = _instance_indices.get(cell)
		if idx == null:
			continue
		multi.set_instance_color(idx, explored_color)

func _on_vision_updated(visible: Array[Vector3i], explored: Array[Vector3i]) -> void:
	if not _initialized or not _multimesh_instance:
		return
	var multi := _multimesh_instance.multimesh
	var visible_set: Dictionary = {}

	for cell in visible:
		if not _instance_indices.has(cell):
			continue
		visible_set[cell] = true
		var idx = _instance_indices.get(cell)
		if idx != null:
			multi.set_instance_color(idx, visible_color)

	for cell in _last_visible_set.keys():
		if visible_set.has(cell):
			continue
		var idx_prev = _instance_indices.get(cell)
		if idx_prev == null:
			continue
		if _explored_set.has(cell):
			multi.set_instance_color(idx_prev, explored_color)
		else:
			multi.set_instance_color(idx_prev, unexplored_color)

	_last_visible_set = visible_set

	var new_added := false
	for cell in explored:
		if not _instance_indices.has(cell):
			continue
		if not _explored_set.has(cell):
			_explored_set[cell] = true
			new_added = true
			if not visible_set.has(cell):
				var idx_new = _instance_indices.get(cell)
				if idx_new != null:
					multi.set_instance_color(idx_new, explored_color)

	if new_added:
		_write_explored_to_gamestate()

func _write_explored_to_gamestate() -> void:
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return
	if _map_id.is_empty():
		return
	if not gs.get("fog_of_war_by_map") is Dictionary:
		gs.fog_of_war_by_map = {}
	var encoded: Array[String] = []
	for cell in _explored_set.keys():
		encoded.append(_encode_cell(cell))
	gs.fog_of_war_by_map[_map_id] = encoded

func _encode_cell(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]

func _decode_cell(text: String) -> Vector3i:
	var parts := text.split(",", false)
	if parts.size() != 3:
		return Vector3i.ZERO
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
