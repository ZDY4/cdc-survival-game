class_name GridHoverCornerOverlay
extends CanvasLayer

@export var overlay_layer: int = 100
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.95)
@export var line_width: float = 2.0
@export var corner_length_px: float = 12.0

class OverlayCanvas extends Control:
	var corners: PackedVector2Array = PackedVector2Array()
	var color: Color = Color(1.0, 1.0, 1.0, 0.95)
	var width: float = 2.0
	var arm_length: float = 12.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func show_corners(corners_screen: PackedVector2Array) -> void:
		corners = corners_screen
		visible = true
		queue_redraw()

	func hide_corners() -> void:
		corners = PackedVector2Array()
		visible = false
		queue_redraw()

	func _draw() -> void:
		if corners.size() != 4:
			return

		var segment_length := maxf(arm_length, 1.0)
		var north_west := corners[0]
		var north_east := corners[1]
		var south_east := corners[2]
		var south_west := corners[3]

		draw_line(north_west, north_west + Vector2.RIGHT * segment_length, color, width, true)
		draw_line(north_west, north_west + Vector2.DOWN * segment_length, color, width, true)
		draw_line(north_east, north_east + Vector2.LEFT * segment_length, color, width, true)
		draw_line(north_east, north_east + Vector2.DOWN * segment_length, color, width, true)
		draw_line(south_east, south_east + Vector2.LEFT * segment_length, color, width, true)
		draw_line(south_east, south_east + Vector2.UP * segment_length, color, width, true)
		draw_line(south_west, south_west + Vector2.RIGHT * segment_length, color, width, true)
		draw_line(south_west, south_west + Vector2.UP * segment_length, color, width, true)

var _overlay_canvas: OverlayCanvas = null

func _ready() -> void:
	layer = overlay_layer
	_overlay_canvas = OverlayCanvas.new()
	_overlay_canvas.name = "OverlayCanvas"
	add_child(_overlay_canvas)
	hide_cell()

func show_cell(corners_world: Array[Vector3], camera: Camera3D) -> void:
	if not _overlay_canvas or not camera or corners_world.size() != 4:
		hide_cell()
		return

	var projected_corners := PackedVector2Array()
	for corner_world in corners_world:
		var projected := camera.unproject_position(corner_world)
		if not is_finite(projected.x) or not is_finite(projected.y):
			hide_cell()
			return
		projected_corners.append(projected)

	_overlay_canvas.color = line_color
	_overlay_canvas.width = line_width
	_overlay_canvas.arm_length = corner_length_px
	_overlay_canvas.show_corners(projected_corners)

func hide_cell() -> void:
	if not _overlay_canvas:
		return
	_overlay_canvas.hide_corners()

func owns_control(control: Control) -> bool:
	return control != null and _overlay_canvas != null and (_overlay_canvas == control or _overlay_canvas.is_ancestor_of(control))
