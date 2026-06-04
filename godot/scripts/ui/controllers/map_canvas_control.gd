extends Control

signal view_changed(state: Dictionary)

const MIN_ZOOM := 0.55
const MAX_ZOOM := 2.5

var snapshot: Dictionary = {}
var zoom := 1.0
var pan := Vector2.ZERO
var _dragging := false
var _drag_start := Vector2.ZERO
var _pan_start := Vector2.ZERO


func _ready() -> void:
	name = "MapCanvas"
	custom_minimum_size = Vector2(420, 150)
	mouse_filter = Control.MOUSE_FILTER_STOP


func apply_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	queue_redraw()


func zoom_in() -> void:
	set_zoom(zoom + 0.15)


func zoom_out() -> void:
	set_zoom(zoom - 0.15)


func reset_view() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	queue_redraw()
	view_changed.emit(view_state())


func reset_pan() -> void:
	pan = Vector2.ZERO
	queue_redraw()
	view_changed.emit(view_state())


func set_zoom(value: float) -> void:
	zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	queue_redraw()
	view_changed.emit(view_state())


func view_state() -> Dictionary:
	return {
		"zoom": zoom,
		"pan": {"x": pan.x, "y": pan.y},
		"marker_count": _array_or_empty(snapshot.get("tracked_markers", [])).size(),
		"entry_count": _entry_points().size(),
		"overworld_location_count": _overworld_locations().size(),
	}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			if button.pressed:
				_drag_start = button.position
				_pan_start = pan
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		pan = _pan_start + (event as InputEventMouseMotion).position - _drag_start
		queue_redraw()
		view_changed.emit(view_state())
		accept_event()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.06, 0.08, 0.07, 0.92), true)
	draw_rect(rect, Color(0.28, 0.36, 0.34, 1.0), false, 1.0)
	var map_rect := _map_rect()
	draw_rect(map_rect, Color(0.12, 0.17, 0.15, 1.0), true)
	draw_rect(map_rect, Color(0.45, 0.58, 0.52, 1.0), false, 2.0)
	_draw_grid(map_rect)
	_draw_entries(map_rect)
	_draw_markers(map_rect)
	_draw_overworld_overview(rect)


func _draw_grid(map_rect: Rect2) -> void:
	var size_data: Dictionary = _dictionary_or_empty(snapshot.get("size", {}))
	var width: int = max(1, int(size_data.get("width", 1)))
	var height: int = max(1, int(size_data.get("height", 1)))
	var step_x: int = max(1, int(ceil(width / 8.0)))
	var step_z: int = max(1, int(ceil(height / 8.0)))
	for x in range(step_x, width, step_x):
		var px: float = _grid_to_canvas({"x": x, "z": 0}, map_rect).x
		draw_line(Vector2(px, map_rect.position.y), Vector2(px, map_rect.end.y), Color(0.24, 0.31, 0.28, 0.55), 1.0)
	for z in range(step_z, height, step_z):
		var py: float = _grid_to_canvas({"x": 0, "z": z}, map_rect).y
		draw_line(Vector2(map_rect.position.x, py), Vector2(map_rect.end.x, py), Color(0.24, 0.31, 0.28, 0.55), 1.0)


func _draw_entries(map_rect: Rect2) -> void:
	for entry_id in _entry_points().keys():
		var grid: Dictionary = _dictionary_or_empty(_entry_points().get(entry_id, {}))
		var point: Vector2 = _grid_to_canvas(grid, map_rect)
		draw_circle(point, 4.0, Color(0.47, 0.78, 0.95, 1.0))


func _draw_markers(map_rect: Rect2) -> void:
	for marker in _array_or_empty(snapshot.get("tracked_markers", [])):
		var marker_data: Dictionary = _dictionary_or_empty(marker)
		var grid: Dictionary = _dictionary_or_empty(marker_data.get("grid", {}))
		if grid.is_empty():
			continue
		var point: Vector2 = _grid_to_canvas(grid, map_rect)
		var color := Color(1.0, 0.76, 0.22, 1.0)
		draw_circle(point, 7.0, color)
		draw_line(point + Vector2(-9, 0), point + Vector2(9, 0), color, 2.0)
		draw_line(point + Vector2(0, -9), point + Vector2(0, 9), color, 2.0)


func _draw_overworld_overview(canvas_rect: Rect2) -> void:
	var overview: Dictionary = _dictionary_or_empty(snapshot.get("overworld_overview", {}))
	var locations := _overworld_locations()
	if locations.is_empty():
		return
	var inset_size := Vector2(126, 94)
	var inset := Rect2(canvas_rect.end - inset_size - Vector2(12, 12), inset_size)
	draw_rect(inset, Color(0.05, 0.07, 0.08, 0.9), true)
	draw_rect(inset, Color(0.37, 0.46, 0.48, 1.0), false, 1.0)
	for route in _array_or_empty(overview.get("route_cells", [])):
		var route_data: Dictionary = _dictionary_or_empty(route)
		var point := _overworld_grid_to_canvas(_dictionary_or_empty(route_data.get("grid", {})), inset, overview)
		draw_rect(Rect2(point - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.42, 0.43, 0.36, 0.72), true)
	for location in locations:
		var location_data: Dictionary = _dictionary_or_empty(location)
		var point := _overworld_grid_to_canvas(_dictionary_or_empty(location_data.get("grid", {})), inset, overview)
		var color := Color(0.42, 0.53, 0.56, 1.0)
		if bool(location_data.get("unlocked", false)):
			color = Color(0.52, 0.78, 0.58, 1.0)
		if bool(location_data.get("active", false)):
			color = Color(1.0, 0.78, 0.26, 1.0)
		draw_circle(point, 3.5 if not bool(location_data.get("active", false)) else 5.5, color)
		if bool(location_data.get("active", false)):
			draw_circle(point, 8.0, Color(1.0, 0.78, 0.26, 0.28))


func _map_rect() -> Rect2:
	var margin := 10.0
	var base := Rect2(Vector2(margin, margin), size - Vector2(margin * 2.0, margin * 2.0))
	var zoomed_size := base.size * zoom
	var center := base.position + base.size * 0.5 + pan
	return Rect2(center - zoomed_size * 0.5, zoomed_size)


func _grid_to_canvas(grid: Dictionary, map_rect: Rect2) -> Vector2:
	var size_data: Dictionary = _dictionary_or_empty(snapshot.get("size", {}))
	var width: float = max(1.0, float(size_data.get("width", 1)))
	var height: float = max(1.0, float(size_data.get("height", 1)))
	var x: float = clampf(float(grid.get("x", 0)), 0.0, width - 1.0)
	var z: float = clampf(float(grid.get("z", 0)), 0.0, height - 1.0)
	return Vector2(
		map_rect.position.x + (x / max(1.0, width - 1.0)) * map_rect.size.x,
		map_rect.position.y + (z / max(1.0, height - 1.0)) * map_rect.size.y
	)


func _entry_points() -> Dictionary:
	return _dictionary_or_empty(snapshot.get("entry_point_grids", {}))


func _overworld_locations() -> Array:
	return _array_or_empty(_dictionary_or_empty(snapshot.get("overworld_overview", {})).get("locations", []))


func _overworld_grid_to_canvas(grid: Dictionary, rect: Rect2, overview: Dictionary) -> Vector2:
	var size_data: Dictionary = _dictionary_or_empty(overview.get("size", {}))
	var width: float = max(1.0, float(size_data.get("width", 1)))
	var height: float = max(1.0, float(size_data.get("height", 1)))
	var x: float = clampf(float(grid.get("x", 0)), 0.0, width - 1.0)
	var z: float = clampf(float(grid.get("z", 0)), 0.0, height - 1.0)
	var pad := 8.0
	var inner := Rect2(rect.position + Vector2(pad, pad), rect.size - Vector2(pad * 2.0, pad * 2.0))
	return Vector2(
		inner.position.x + (x / max(1.0, width - 1.0)) * inner.size.x,
		inner.position.y + (z / max(1.0, height - 1.0)) * inner.size.y
	)


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
