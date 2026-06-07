extends Control

const MapCanvasControl = preload("res://scripts/ui/controllers/map_canvas_control.gd")

var _panel: PanelContainer
var _summary_label: Label
var _counts_label: Label
var _entry_label: Label
var _locations_label: Label
var _overworld_label: Label
var _tracked_quest_label: Label
var _tracked_markers_label: Label
var _canvas: Control
var _canvas_state_label: Label
var _kinds_box: VBoxContainer


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	var size: Dictionary = _dictionary_or_empty(snapshot.get("size", {}))
	_summary_label.text = "%s (%s) | %sx%s" % [
		snapshot.get("map_name", snapshot.get("active_map_id", "")),
		snapshot.get("active_map_id", ""),
		str(size.get("width", "?")),
		str(size.get("height", "?")),
	]
	_counts_label.text = "对象 %d | 占用格 %d | 阻挡格 %d" % [
		int(snapshot.get("object_count", 0)),
		int(snapshot.get("occupied_cell_count", 0)),
		int(snapshot.get("blocking_cell_count", 0)),
	]
	_entry_label.text = "入口: %s | 当前入口: %s" % [
		", ".join(_array_of_strings(snapshot.get("entry_points", []))),
		snapshot.get("active_entry_point_id", ""),
	]
	var active_location_id := str(snapshot.get("active_location_id", ""))
	var active_location_name := str(snapshot.get("active_location_name", active_location_id))
	_locations_label.text = "当前地点: %s (%s) | 已解锁: %s" % [
		active_location_name,
		active_location_id,
		", ".join(_array_of_strings(snapshot.get("unlocked_locations", []))),
	]
	_overworld_label.text = _overworld_text(snapshot.get("overworld_overview", {}))
	_tracked_quest_label.text = _tracked_quest_text(snapshot.get("tracked_quest", {}))
	_tracked_markers_label.text = _tracked_markers_text(snapshot.get("tracked_markers", []))
	if _canvas != null and _canvas.has_method("apply_snapshot"):
		_canvas.call("apply_snapshot", snapshot)
	_canvas_state_label.text = _canvas_state_text()
	_clear_kinds()
	var kinds: Dictionary = _dictionary_or_empty(snapshot.get("objects_by_kind", {}))
	var keys: Array = kinds.keys()
	keys.sort()
	for key in keys:
		var label := _label("Kind_%s" % key)
		label.text = "%s: %d" % [key, int(kinds.get(key, 0))]
		_kinds_box.add_child(label)


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "MapPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -460
	_panel.offset_right = -16
	_panel.offset_top = -250
	_panel.offset_bottom = -24
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "MapLines"
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_summary_label = _label("SummaryLine")
	_counts_label = _label("CountsLine")
	_entry_label = _label("EntryLine")
	_locations_label = _label("LocationsLine")
	_overworld_label = _label("OverworldLine")
	_tracked_quest_label = _label("TrackedQuestLine")
	_tracked_markers_label = _label("TrackedMarkersLine")
	_canvas = MapCanvasControl.new()
	if _canvas.has_signal("view_changed"):
		_canvas.connect("view_changed", _on_canvas_view_changed)
	_canvas_state_label = _label("CanvasStateLine")
	_kinds_box = VBoxContainer.new()
	_kinds_box.name = "KindLines"
	_kinds_box.add_theme_constant_override("separation", 3)
	box.add_child(_summary_label)
	box.add_child(_counts_label)
	box.add_child(_entry_label)
	box.add_child(_locations_label)
	box.add_child(_overworld_label)
	box.add_child(_tracked_quest_label)
	box.add_child(_tracked_markers_label)
	box.add_child(_canvas_toolbar())
	box.add_child(_canvas)
	box.add_child(_canvas_state_label)
	box.add_child(_kinds_box)


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear_kinds() -> void:
	for child in _kinds_box.get_children():
		_kinds_box.remove_child(child)
		child.free()


func _array_of_strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(str(item))
	return result


func _tracked_quest_text(value: Variant) -> String:
	var tracked: Dictionary = _dictionary_or_empty(value)
	if not bool(tracked.get("active", false)):
		return "追踪任务: 无"
	return "追踪任务: %s | %s %d/%d | %s" % [
		str(tracked.get("title", tracked.get("quest_id", ""))),
		str(tracked.get("objective_text", "")),
		int(tracked.get("progress_current", 0)),
		int(tracked.get("progress_target", 0)),
		str(tracked.get("status_text", "")),
	]


func _overworld_text(value: Variant) -> String:
	var overview: Dictionary = _dictionary_or_empty(value)
	var locations := _array_or_empty(overview.get("locations", []))
	if locations.is_empty():
		return "世界地图: 无"
	var size: Dictionary = _dictionary_or_empty(overview.get("size", {}))
	var active_location_id := str(overview.get("active_location_id", ""))
	var active_location: Dictionary = {}
	for location in locations:
		var location_data: Dictionary = _dictionary_or_empty(location)
		if str(location_data.get("id", "")) == active_location_id:
			active_location = location_data
			break
	var grid: Dictionary = _dictionary_or_empty(active_location.get("grid", {}))
	var active_text := active_location_id
	if not grid.is_empty():
		active_text = "%s@%d,%d" % [
			str(active_location.get("name", active_location_id)),
			int(grid.get("x", 0)),
			int(grid.get("z", 0)),
		]
	return "世界地图: %sx%s | 可见地点 %d/%d | 道路 %d | 当前 %s" % [
		str(size.get("width", "?")),
		str(size.get("height", "?")),
		int(overview.get("unlocked_count", 0)),
		locations.size(),
		_array_or_empty(overview.get("route_cells", [])).size(),
		active_text,
	]


func _tracked_markers_text(value: Variant) -> String:
	var markers := _array_or_empty(value)
	if markers.is_empty():
		return "任务目标: 无"
	var parts: Array[String] = []
	for marker in markers:
		var marker_data: Dictionary = _dictionary_or_empty(marker)
		var name := str(marker_data.get("display_name", marker_data.get("target_id", "")))
		var grid: Dictionary = _dictionary_or_empty(marker_data.get("grid", {}))
		var status := str(marker_data.get("status", ""))
		if not grid.is_empty():
			parts.append("%s@%d,%d,%d" % [
				name,
				int(grid.get("x", 0)),
				int(grid.get("y", 0)),
				int(grid.get("z", 0)),
			])
		elif status == "unresolved":
			parts.append("%s(%s)" % [name, str(marker_data.get("reason", "unresolved"))])
		else:
			parts.append(name)
	return "任务目标: %d | %s" % [markers.size(), "；".join(parts)]


func _canvas_toolbar() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "MapCanvasToolbar"
	row.add_theme_constant_override("separation", 4)
	row.add_child(_canvas_button("ZoomOutButton", "-", func() -> void:
		_canvas.call("zoom_out")
		_canvas_state_label.text = _canvas_state_text()
	))
	row.add_child(_canvas_button("ZoomResetButton", "1:1", func() -> void:
		_canvas.call("reset_view")
		_canvas_state_label.text = _canvas_state_text()
	))
	row.add_child(_canvas_button("PanResetButton", "Pan", func() -> void:
		_canvas.call("reset_pan")
		_canvas_state_label.text = _canvas_state_text()
	))
	row.add_child(_canvas_button("ZoomInButton", "+", func() -> void:
		_canvas.call("zoom_in")
		_canvas_state_label.text = _canvas_state_text()
	))
	return row


func _canvas_button(node_name: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(40, 26)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(callback, CONNECT_DEFERRED)
	return button


func _canvas_state_text() -> String:
	if _canvas == null or not _canvas.has_method("view_state"):
		return "地图画布: 未就绪"
	var state: Dictionary = _dictionary_or_empty(_canvas.call("view_state"))
	return "地图画布: zoom %.2f | pan %.0f,%.0f | marker %d | entry %d | world %d | icon %d" % [
		float(state.get("zoom", 1.0)),
		float(_dictionary_or_empty(state.get("pan", {})).get("x", 0.0)),
		float(_dictionary_or_empty(state.get("pan", {})).get("y", 0.0)),
		int(state.get("marker_count", 0)),
		int(state.get("entry_count", 0)),
		int(state.get("overworld_location_count", 0)),
		int(state.get("overworld_icon_count", 0)),
	]


func _on_canvas_view_changed(_state: Dictionary) -> void:
	if _canvas_state_label != null:
		_canvas_state_label.text = _canvas_state_text()


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
