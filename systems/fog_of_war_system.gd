class_name FogOfWarSystem
extends Node
## Generates fog mask texture based on VisionSystem output.

signal mask_texture_updated(current_texture: Texture2D, previous_texture: Texture2D)

const MASK_VISIBLE := 0.0
const MASK_EXPLORED := 0.5
const MASK_UNEXPLORED := 1.0
const FOG_DATA_VERSION := 3

var _vision_system: Node = null
var _last_visible_set: Dictionary = {}
var _explored_set: Dictionary = {}
var _map_id: String = ""
var _bounds: Dictionary = {}
var _mask_resolution_scale: int = 1
var _mask_image: Image = null
var _mask_texture: ImageTexture = null
var _mask_dirty: bool = false
var _initialized: bool = false

func initialize(vision_system: Node, bounds: Dictionary, map_id: String, mask_resolution_scale: int) -> void:
	_vision_system = vision_system
	_bounds = bounds.duplicate(true)
	_map_id = map_id
	_mask_resolution_scale = maxi(1, mask_resolution_scale)
	_build_mask_texture()
	_load_explored_from_gamestate()
	if _vision_system:
		_vision_system.vision_updated.connect(_on_vision_updated)

func get_mask_texture() -> Texture2D:
	return _mask_texture

func get_bounds_min_xz() -> Vector2:
	if _bounds.is_empty():
		return Vector2.ZERO
	return Vector2(float(_bounds.min_x), float(_bounds.min_z))

func get_bounds_size_xz() -> Vector2:
	if _bounds.is_empty():
		return Vector2.ONE
	var width: int = int(_bounds.max_x) - int(_bounds.min_x) + 1
	var depth: int = int(_bounds.max_z) - int(_bounds.min_z) + 1
	return Vector2(float(maxi(1, width)), float(maxi(1, depth)))

func get_mask_texel_size() -> Vector2:
	if _mask_image == null:
		return Vector2.ONE
	return Vector2(1.0 / float(maxi(1, _mask_image.get_width())), 1.0 / float(maxi(1, _mask_image.get_height())))

func _build_mask_texture() -> void:
	if _bounds.is_empty():
		return
	var width: int = int(_bounds.max_x) - int(_bounds.min_x) + 1
	var depth: int = int(_bounds.max_z) - int(_bounds.min_z) + 1
	if width <= 0 or depth <= 0:
		return
	var mask_width := width * _mask_resolution_scale
	var mask_height := depth * _mask_resolution_scale
	_mask_image = Image.create(mask_width, mask_height, false, Image.FORMAT_R8)
	_mask_image.fill(Color(MASK_UNEXPLORED, 0.0, 0.0, 1.0))
	_mask_texture = ImageTexture.create_from_image(_mask_image)
	_initialized = true

func _load_explored_from_gamestate() -> void:
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return
	if _map_id.is_empty():
		return
	var fow_data = gs.get("fog_of_war_by_map")
	if not (fow_data is Dictionary):
		return
	var data_var: Variant = fow_data.get(_map_id, {})
	if not (data_var is Dictionary):
		return
	var data: Dictionary = data_var
	if int(data.get("version", 0)) != FOG_DATA_VERSION:
		fow_data.erase(_map_id)
		return
	var expected_width: int = _get_bounds_width()
	var expected_depth: int = _get_bounds_depth()
	var saved_width: int = int(data.get("width", 0))
	var saved_depth: int = int(data.get("depth", 0))
	if saved_width != expected_width or saved_depth != expected_depth:
		fow_data.erase(_map_id)
		return
	var bits_b64: String = str(data.get("explored_bits_b64", ""))
	if bits_b64.is_empty():
		fow_data.erase(_map_id)
		return
	var cells := _decode_explored_cells_from_bitset(bits_b64, expected_width, expected_depth)
	_apply_explored_cells(cells)
	if _vision_system:
		_vision_system.set_explored_cells(cells)
	_upload_mask_if_dirty()

func _apply_explored_cells(cells: Array[Vector3i]) -> void:
	if _mask_image == null:
		return
	for cell in cells:
		if not _is_cell_in_bounds(cell):
			continue
		_explored_set[cell] = true
		_set_cell_mask_state(cell, MASK_EXPLORED)

func _on_vision_updated(visible: Array[Vector3i], explored: Array[Vector3i]) -> void:
	if not _initialized or _mask_image == null:
		return
	var visible_set: Dictionary = {}

	for cell in visible:
		if not _is_cell_in_bounds(cell):
			continue
		visible_set[cell] = true
		_set_cell_mask_state(cell, MASK_VISIBLE)

	for cell in _last_visible_set.keys():
		if visible_set.has(cell):
			continue
		if _explored_set.has(cell):
			_set_cell_mask_state(cell, MASK_EXPLORED)
		else:
			_set_cell_mask_state(cell, MASK_UNEXPLORED)

	_last_visible_set = visible_set

	var new_added := false
	for cell in explored:
		if not _is_cell_in_bounds(cell):
			continue
		if not _explored_set.has(cell):
			_explored_set[cell] = true
			new_added = true
			if not visible_set.has(cell):
				_set_cell_mask_state(cell, MASK_EXPLORED)

	_upload_mask_if_dirty()
	if new_added:
		_write_explored_to_gamestate()

func _set_cell_mask_state(cell: Vector3i, state: float) -> void:
	if _mask_image == null:
		return
	var px0: int = (cell.x - int(_bounds.min_x)) * _mask_resolution_scale
	var py0: int = (cell.z - int(_bounds.min_z)) * _mask_resolution_scale
	var px1: int = px0 + _mask_resolution_scale
	var py1: int = py0 + _mask_resolution_scale
	var color := Color(state, 0.0, 0.0, 1.0)
	for px in range(px0, px1):
		for py in range(py0, py1):
			_mask_image.set_pixel(px, py, color)
	_mask_dirty = true

func _upload_mask_if_dirty() -> void:
	if not _mask_dirty:
		return
	if _mask_texture == null or _mask_image == null:
		return
	var previous_image: Image = _mask_texture.get_image()
	_mask_texture.update(_mask_image)
	var previous_texture: ImageTexture = ImageTexture.create_from_image(previous_image)
	mask_texture_updated.emit(_mask_texture, previous_texture)
	_mask_dirty = false

func _is_cell_in_bounds(cell: Vector3i) -> bool:
	if _bounds.is_empty():
		return false
	var min_x: int = int(_bounds.min_x)
	var max_x: int = int(_bounds.max_x)
	var min_z: int = int(_bounds.min_z)
	var max_z: int = int(_bounds.max_z)
	return cell.x >= min_x and cell.x <= max_x and cell.z >= min_z and cell.z <= max_z

func _write_explored_to_gamestate() -> void:
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return
	if _map_id.is_empty():
		return
	if not (gs.get("fog_of_war_by_map") is Dictionary):
		gs.fog_of_war_by_map = {}
	var width: int = _get_bounds_width()
	var depth: int = _get_bounds_depth()
	gs.fog_of_war_by_map[_map_id] = {
		"version": FOG_DATA_VERSION,
		"width": width,
		"depth": depth,
		"explored_bits_b64": _encode_explored_cells_to_bitset(width, depth)
	}

func _encode_explored_cells_to_bitset(width: int, depth: int) -> String:
	var tile_count: int = width * depth
	var byte_count: int = int(ceili(float(tile_count) / 8.0))
	var bytes := PackedByteArray()
	bytes.resize(byte_count)
	var min_x: int = int(_bounds.min_x)
	var min_z: int = int(_bounds.min_z)
	for key in _explored_set.keys():
		if not (key is Vector3i):
			continue
		var cell: Vector3i = key
		if not _is_cell_in_bounds(cell):
			continue
		var local_x: int = cell.x - min_x
		var local_z: int = cell.z - min_z
		var index: int = local_z * width + local_x
		if index < 0 or index >= tile_count:
			continue
		var byte_index: int = index / 8
		var bit_index: int = index % 8
		bytes[byte_index] = int(bytes[byte_index]) | (1 << bit_index)
	return Marshalls.raw_to_base64(bytes)

func _decode_explored_cells_from_bitset(bits_b64: String, width: int, depth: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var bytes: PackedByteArray = Marshalls.base64_to_raw(bits_b64)
	var tile_count: int = width * depth
	var required_byte_count: int = int(ceili(float(tile_count) / 8.0))
	if bytes.size() < required_byte_count:
		return result
	var min_x: int = int(_bounds.min_x)
	var min_z: int = int(_bounds.min_z)
	for index in range(tile_count):
		var byte_index: int = index / 8
		var bit_index: int = index % 8
		if (int(bytes[byte_index]) & (1 << bit_index)) == 0:
			continue
		var local_z: int = index / width
		var local_x: int = index % width
		result.append(Vector3i(min_x + local_x, 0, min_z + local_z))
	return result

func _get_bounds_width() -> int:
	return int(_bounds.max_x) - int(_bounds.min_x) + 1

func _get_bounds_depth() -> int:
	return int(_bounds.max_z) - int(_bounds.min_z) + 1
