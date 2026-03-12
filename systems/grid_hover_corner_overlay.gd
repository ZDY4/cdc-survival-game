class_name GridHoverCornerOverlay
extends CanvasLayer

@export var overlay_layer: int = 100
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.95)
@export var line_width: float = 2.0
@export var corner_length_px: float = 12.0

var _draw_surface: Control = null
var _screen_corners: Array[Vector2] = []
var _is_cell_visible: bool = false

func _ready() -> void:
	layer = overlay_layer
	_draw_surface = Control.new()
	_draw_surface.name = "DrawSurface"
	_draw_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_surface.draw.connect(_on_draw_surface)
	add_child(_draw_surface)
	hide_cell()

func show_cell(corners_world: Array[Vector3], camera: Camera3D) -> void:
	if not _draw_surface or not camera or corners_world.size() != 4:
		hide_cell()
		return

	var projected_corners: Array[Vector2] = []
	for corner_world in corners_world:
		if camera.is_position_behind(corner_world):
			hide_cell()
			return
		projected_corners.append(camera.unproject_position(corner_world))

	_screen_corners = projected_corners
	_is_cell_visible = true
	_draw_surface.visible = true
	_draw_surface.queue_redraw()

func hide_cell() -> void:
	_screen_corners.clear()
	_is_cell_visible = false
	if _draw_surface:
		_draw_surface.visible = false
		_draw_surface.queue_redraw()

func _on_draw_surface() -> void:
	if not _is_cell_visible or _screen_corners.size() != 4 or not _draw_surface:
		return

	var segment_length := maxf(corner_length_px, 1.0)
	var north_west := _screen_corners[0]
	var north_east := _screen_corners[1]
	var south_east := _screen_corners[2]
	var south_west := _screen_corners[3]

	# NW corner
	_draw_surface.draw_line(north_west, north_west + Vector2.RIGHT * segment_length, line_color, line_width)
	_draw_surface.draw_line(north_west, north_west + Vector2.DOWN * segment_length, line_color, line_width)

	# NE corner
	_draw_surface.draw_line(north_east, north_east + Vector2.LEFT * segment_length, line_color, line_width)
	_draw_surface.draw_line(north_east, north_east + Vector2.DOWN * segment_length, line_color, line_width)

	# SE corner
	_draw_surface.draw_line(south_east, south_east + Vector2.LEFT * segment_length, line_color, line_width)
	_draw_surface.draw_line(south_east, south_east + Vector2.UP * segment_length, line_color, line_width)

	# SW corner
	_draw_surface.draw_line(south_west, south_west + Vector2.RIGHT * segment_length, line_color, line_width)
	_draw_surface.draw_line(south_west, south_west + Vector2.UP * segment_length, line_color, line_width)
