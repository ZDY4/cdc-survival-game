class_name GridAreaOverlay
extends CanvasLayer

@export var overlay_layer: int = 110
@export var range_fill_color: Color = Color(0.25, 0.55, 0.95, 0.12)
@export var range_outline_color: Color = Color(0.45, 0.75, 1.0, 0.35)
@export var valid_fill_color: Color = Color(0.35, 0.95, 0.45, 0.28)
@export var valid_outline_color: Color = Color(0.55, 1.0, 0.65, 0.95)
@export var invalid_fill_color: Color = Color(0.95, 0.28, 0.28, 0.28)
@export var invalid_outline_color: Color = Color(1.0, 0.55, 0.55, 0.95)
@export var outline_width: float = 2.0
@export var world_height_offset: float = 0.03


class OverlayCanvas extends Control:
	var range_polygons: Array[PackedVector2Array] = []
	var preview_polygons: Array[PackedVector2Array] = []
	var range_fill: Color = Color(0.25, 0.55, 0.95, 0.12)
	var range_outline: Color = Color(0.45, 0.75, 1.0, 0.35)
	var preview_fill: Color = Color(0.35, 0.95, 0.45, 0.28)
	var preview_outline: Color = Color(0.55, 1.0, 0.65, 0.95)
	var stroke_width: float = 2.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		visible = false

	func update_polygons(
		next_preview_polygons: Array[PackedVector2Array],
		next_range_polygons: Array[PackedVector2Array],
		is_valid: bool,
		valid_fill: Color,
		valid_outline: Color,
		invalid_fill: Color,
		invalid_outline: Color,
		next_range_fill: Color,
		next_range_outline: Color,
		next_outline_width: float
	) -> void:
		preview_polygons = next_preview_polygons
		range_polygons = next_range_polygons
		range_fill = next_range_fill
		range_outline = next_range_outline
		preview_fill = valid_fill if is_valid else invalid_fill
		preview_outline = valid_outline if is_valid else invalid_outline
		stroke_width = next_outline_width
		visible = not preview_polygons.is_empty() or not range_polygons.is_empty()
		queue_redraw()

	func clear() -> void:
		range_polygons.clear()
		preview_polygons.clear()
		visible = false
		queue_redraw()

	func _draw() -> void:
		for polygon in range_polygons:
			if polygon.size() < 3:
				continue
			draw_colored_polygon(polygon, range_fill)
			_draw_polygon_outline(polygon, range_outline, stroke_width)
		for polygon in preview_polygons:
			if polygon.size() < 3:
				continue
			draw_colored_polygon(polygon, preview_fill)
			_draw_polygon_outline(polygon, preview_outline, stroke_width)

	func _draw_polygon_outline(polygon: PackedVector2Array, color: Color, width: float) -> void:
		for index in range(polygon.size()):
			var from_point: Vector2 = polygon[index]
			var to_point: Vector2 = polygon[(index + 1) % polygon.size()]
			draw_line(from_point, to_point, color, width, true)


var _overlay_canvas: OverlayCanvas = null


func _ready() -> void:
	layer = overlay_layer
	_overlay_canvas = OverlayCanvas.new()
	_overlay_canvas.name = "OverlayCanvas"
	add_child(_overlay_canvas)
	clear()


func show_preview(
	preview_cells: Array[Vector3i],
	range_cells: Array[Vector3i],
	camera: Camera3D,
	is_valid: bool
) -> void:
	if _overlay_canvas == null or camera == null:
		clear()
		return

	var preview_polygons: Array[PackedVector2Array] = _build_polygons(preview_cells, camera)
	var range_polygons: Array[PackedVector2Array] = _build_polygons(range_cells, camera)
	_overlay_canvas.update_polygons(
		preview_polygons,
		range_polygons,
		is_valid,
		valid_fill_color,
		valid_outline_color,
		invalid_fill_color,
		invalid_outline_color,
		range_fill_color,
		range_outline_color,
		outline_width
	)


func clear() -> void:
	if _overlay_canvas != null:
		_overlay_canvas.clear()


func owns_control(control: Control) -> bool:
	return control != null and _overlay_canvas != null and (_overlay_canvas == control or _overlay_canvas.is_ancestor_of(control))


func _build_polygons(cells: Array[Vector3i], camera: Camera3D) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	var cell_size: float = float(GridNavigator.GRID_SIZE)
	var half_cell: float = cell_size * 0.5
	for cell in cells:
		var world_center: Vector3 = GridMovementSystem.grid_to_world(cell)
		var y: float = world_center.y + world_height_offset
		var corners_world: Array[Vector3] = [
			Vector3(world_center.x - half_cell, y, world_center.z - half_cell),
			Vector3(world_center.x + half_cell, y, world_center.z - half_cell),
			Vector3(world_center.x + half_cell, y, world_center.z + half_cell),
			Vector3(world_center.x - half_cell, y, world_center.z + half_cell)
		]
		var polygon := PackedVector2Array()
		var failed: bool = false
		for corner_world in corners_world:
			var projected: Vector2 = camera.unproject_position(corner_world)
			if not is_finite(projected.x) or not is_finite(projected.y):
				failed = true
				break
			polygon.append(projected)
		if not failed:
			polygons.append(polygon)
	return polygons
