@tool
class_name MapBuilding3D
extends "res://scripts/world/map_scene_object_3d.gd"

@export var prefab_id: String = ""
@export var wall_set_id: String = ""
@export var floor_surface_set_id: String = ""
@export_multiline var props_json: String = "{}"


func get_object_kind() -> String:
	return "building"


func build_object_props() -> Dictionary:
	var props := _json_dictionary(props_json, "props_json")
	var building := _dictionary_or_empty(props.get("building", {})).duplicate(true)
	var wall_cells: Array[Dictionary] = _blocking_wall_cell_dictionaries()
	if not wall_cells.is_empty():
		building["wall_cells"] = wall_cells
	if not prefab_id.strip_edges().is_empty():
		building["prefab_id"] = prefab_id
	var tile_set := _dictionary_or_empty(building.get("tile_set", {})).duplicate(true)
	if not wall_set_id.strip_edges().is_empty():
		tile_set["wall_set_id"] = wall_set_id
	if not floor_surface_set_id.strip_edges().is_empty():
		tile_set["floor_surface_set_id"] = floor_surface_set_id
	if not tile_set.is_empty():
		building["tile_set"] = tile_set
	if not building.is_empty():
		props["building"] = building
	return props


func _blocking_wall_cell_dictionaries() -> Array[Dictionary]:
	var cells_by_key: Dictionary = {}
	_collect_blocking_wall_cells(self, cells_by_key)
	var cells: Array[Vector2i] = []
	for key in cells_by_key.keys():
		cells.append(cells_by_key[key])
	cells.sort()
	var output: Array[Dictionary] = []
	for cell in cells:
		output.append({"x": cell.x, "z": cell.y})
	return output


func _collect_blocking_wall_cells(node: Node, cells_by_key: Dictionary) -> void:
	if node != self and node.has_method("get_blocking_cells"):
		for cell in node.call("get_blocking_cells"):
			if typeof(cell) != TYPE_VECTOR2I:
				continue
			var grid_cell: Vector2i = cell
			cells_by_key["%d,%d" % [grid_cell.x, grid_cell.y]] = grid_cell
		return
	for child in node.get_children():
		_collect_blocking_wall_cells(child, cells_by_key)
