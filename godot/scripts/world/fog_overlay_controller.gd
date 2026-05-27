extends RefCounted

const FOG_SHADER = preload("res://assets/shaders/fog_of_war_canvas.gdshader")

const OVERLAY_NAME := "FogOfWarOverlay"
const MASK_VISIBLE := 0.0
const MASK_EXPLORED := 0.5
const MASK_UNEXPLORED := 1.0

var overlay: ColorRect
var material: ShaderMaterial
var previous_mask: ImageTexture
var current_mask: ImageTexture


func ensure_overlay(parent: Node, map_snapshot: Dictionary, runtime_snapshot: Dictionary) -> ColorRect:
	if overlay == null or not is_instance_valid(overlay):
		overlay = ColorRect.new()
		overlay.name = OVERLAY_NAME
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.anchors_preset = Control.PRESET_FULL_RECT
		overlay.color = Color.WHITE
		material = ShaderMaterial.new()
		material.shader = FOG_SHADER
		overlay.material = material
		parent.add_child(overlay)
	elif overlay.get_parent() != parent:
		overlay.get_parent().remove_child(overlay)
		parent.add_child(overlay)
	update_overlay(map_snapshot, runtime_snapshot)
	return overlay


func update_overlay(map_snapshot: Dictionary, runtime_snapshot: Dictionary) -> Dictionary:
	if material == null:
		return {"ok": false, "reason": "fog_material_missing"}
	var size := _map_size(map_snapshot)
	var mask_image := _build_mask_image(size, _actor_vision(runtime_snapshot), str(runtime_snapshot.get("active_map_id", "")))
	previous_mask = current_mask if current_mask != null else ImageTexture.create_from_image(mask_image)
	current_mask = ImageTexture.create_from_image(mask_image)
	material.set_shader_parameter("current_mask_texture", current_mask)
	material.set_shader_parameter("previous_mask_texture", previous_mask)
	material.set_shader_parameter("fog_enabled", true)
	material.set_shader_parameter("mask_blend", 1.0)
	material.set_shader_parameter("explored_alpha", 0.32)
	material.set_shader_parameter("unexplored_alpha", 0.88)
	material.set_shader_parameter("edge_softness", 0.85)
	material.set_shader_parameter("mask_texel_size", Vector2(1.0 / float(size.x), 1.0 / float(size.y)))
	material.set_shader_parameter("fog_color", Color(0.015, 0.018, 0.022, 1.0))
	return {
		"ok": true,
		"width": size.x,
		"height": size.y,
	}


func _build_mask_image(size: Vector2i, actor_vision: Dictionary, active_map_id: String) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	image.fill(Color(MASK_UNEXPLORED, 0.0, 0.0, 1.0))
	for cell in _explored_cells(actor_vision, active_map_id):
		_set_mask_cell(image, _dictionary_or_empty(cell), MASK_EXPLORED)
	for cell in _array_or_empty(actor_vision.get("visible_cells", [])):
		_set_mask_cell(image, _dictionary_or_empty(cell), MASK_VISIBLE)
	return image


func _set_mask_cell(image: Image, cell: Dictionary, value: float) -> void:
	var x := int(cell.get("x", -1))
	var z := int(cell.get("z", -1))
	if x < 0 or x >= image.get_width() or z < 0 or z >= image.get_height():
		return
	image.set_pixel(x, z, Color(value, 0.0, 0.0, 1.0))


func _actor_vision(runtime_snapshot: Dictionary) -> Dictionary:
	var vision := _dictionary_or_empty(runtime_snapshot.get("vision", {}))
	for actor in _array_or_empty(vision.get("actors", [])):
		var actor_data := _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data
	return {}


func _explored_cells(actor_vision: Dictionary, active_map_id: String) -> Array:
	for map_data in _array_or_empty(actor_vision.get("explored_maps", [])):
		var explored_map := _dictionary_or_empty(map_data)
		if str(explored_map.get("map_id", "")) == active_map_id:
			return _array_or_empty(explored_map.get("explored_cells", []))
	return []


func _map_size(map_snapshot: Dictionary) -> Vector2i:
	var size := _dictionary_or_empty(map_snapshot.get("size", {}))
	return Vector2i(max(1, int(size.get("width", 1))), max(1, int(size.get("height", 1))))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
