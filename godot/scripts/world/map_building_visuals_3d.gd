@tool
class_name MapBuildingVisuals3D
extends Node3D

const GROUP_NAME := "map_building_visuals"
const BUILDING_TILE_PATH_PREFIX := "res://assets/world_tiles/building_wall/"

var _tiles_by_cell: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(GROUP_NAME)


func _ready() -> void:
	rebuild_index()


func rebuild_index() -> void:
	_tiles_by_cell.clear()
	for child in get_children():
		var tile := child as Node3D
		if tile == null or not _is_building_tile(tile):
			continue
		var cell := Vector2i(int(round(tile.position.x)), int(round(tile.position.z)))
		var key := _cell_key(cell)
		var tiles: Array[Node3D] = _node3d_array(_tiles_by_cell.get(key, []))
		tiles.append(tile)
		_tiles_by_cell[key] = tiles


func get_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for key in _tiles_by_cell.keys():
		cells.append(_cell_from_key(str(key)))
	cells.sort()
	return cells


func get_blocking_cells() -> Array[Vector2i]:
	var cells_by_key: Dictionary = {}
	for child in get_children():
		var tile := child as Node3D
		if tile == null or not _is_blocking_tile(tile):
			continue
		var cell := Vector2i(int(round(tile.position.x)), int(round(tile.position.z)))
		cells_by_key[_cell_key(cell)] = cell
	var cells: Array[Vector2i] = []
	for key in cells_by_key.keys():
		cells.append(cells_by_key[key])
	cells.sort()
	return cells


func get_tiles_at_cell(cell: Vector2i) -> Array[Node3D]:
	var key := _cell_key(cell)
	if not _tiles_by_cell.has(key):
		rebuild_index()
	var tiles: Array[Node3D] = []
	for tile in _node3d_array(_tiles_by_cell.get(key, [])):
		if is_instance_valid(tile):
			tiles.append(tile)
	return tiles


func set_cell_visible(cell: Vector2i, visible: bool) -> void:
	for tile in get_tiles_at_cell(cell):
		tile.visible = visible


func set_cell_material(cell: Vector2i, material: Material) -> void:
	for tile in get_tiles_at_cell(cell):
		_apply_material_override(tile, material)


func clear_cell_material(cell: Vector2i) -> void:
	for tile in get_tiles_at_cell(cell):
		_apply_material_override(tile, null)


func clear_all_cell_materials() -> void:
	for key in _tiles_by_cell.keys():
		clear_cell_material(_cell_from_key(str(key)))


func _apply_material_override(root: Node, material: Material) -> void:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = material


func _is_building_tile(node: Node3D) -> bool:
	if node.scene_file_path.begins_with(BUILDING_TILE_PATH_PREFIX):
		return true
	return str(node.name).begins_with("building_wall_")


func _is_blocking_tile(node: Node3D) -> bool:
	if not _is_building_tile(node):
		return false
	var scene_path := node.scene_file_path
	var node_name := str(node.name)
	return not scene_path.contains("/floor") and not node_name.contains("_floor")


func _node3d_array(value: Variant) -> Array[Node3D]:
	var output: Array[Node3D] = []
	if typeof(value) != TYPE_ARRAY:
		return output
	for item in value:
		var node := item as Node3D
		if node != null:
			output.append(node)
	return output


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _cell_from_key(key: String) -> Vector2i:
	var parts := key.split(",", false)
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))
