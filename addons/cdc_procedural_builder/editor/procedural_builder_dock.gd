@tool
class_name ProceduralBuilderDock
extends VBoxContainer

signal control_point_selected(index: int)
signal opening_selected(index: int)
signal add_point_requested
signal insert_point_requested
signal remove_point_requested(index: int)
signal closed_toggled(value: bool)
signal add_opening_requested
signal remove_opening_requested(index: int)

var _target: ProcShapeGenerator3D = null
var _selected_point_index: int = -1
var _selected_opening_index: int = -1
var _embedded_in_inspector: bool = false

var _title_label: Label = null
var _hint_label: Label = null
var _point_list: ItemList = null
var _add_point_button: Button = null
var _insert_point_button: Button = null
var _remove_point_button: Button = null
var _closed_toggle: CheckButton = null
var _segment_info_label: Label = null
var _grid_info_label: Label = null
var _opening_section: VBoxContainer = null
var _opening_list: ItemList = null
var _add_opening_button: Button = null
var _remove_opening_button: Button = null

func _ready() -> void:
	_apply_layout_mode()
	_build_ui()
	refresh()

func set_embedded_in_inspector(value: bool) -> void:
	_embedded_in_inspector = value
	_apply_layout_mode()
	if _point_list != null:
		_point_list.custom_minimum_size = Vector2(0.0, 120.0 if _embedded_in_inspector else 180.0)

func set_target(generator: ProcShapeGenerator3D) -> void:
	_target = generator
	_selected_point_index = -1
	_selected_opening_index = -1
	refresh()

func set_selected_point_index(index: int) -> void:
	_selected_point_index = index
	refresh()

func set_selected_opening_index(index: int) -> void:
	_selected_opening_index = index
	refresh()

func refresh() -> void:
	if _title_label == null:
		return

	if _target == null:
		_title_label.text = "Procedural Builder"
		_hint_label.text = "Select a ProcWall3D, ProcFence3D, or ProcHouse3D node to edit control points."
		_point_list.clear()
		_segment_info_label.text = "Segment: no selection"
		_grid_info_label.text = "Blocked Cells: no selection"
		_closed_toggle.button_pressed = false
		_closed_toggle.disabled = true
		_opening_section.visible = false
		_set_buttons_enabled(false)
		return

	_title_label.text = "%s Editor" % _target.get_class()
	_hint_label.text = "Drag handles in the 3D viewport or use the controls below."
	_fill_point_list()
	_fill_segment_info()
	_fill_grid_info()

	_closed_toggle.disabled = not _target.can_edit_closed_state()
	_closed_toggle.button_pressed = _target.closed or _target._requires_closed_shape()
	if _target._requires_closed_shape():
		_closed_toggle.tooltip_text = "This generator always uses a closed path."
	elif not _target.can_edit_closed_state():
		_closed_toggle.tooltip_text = "Closed Path requires at least 3 control points."
	else:
		_closed_toggle.tooltip_text = ""

	var is_house: bool = _target is ProcHouse3D
	_opening_section.visible = is_house
	if is_house:
		_fill_opening_list(_target as ProcHouse3D)

	_set_buttons_enabled(true)

func _build_ui() -> void:
	_title_label = Label.new()
	_title_label.text = "Procedural Builder"
	_title_label.add_theme_font_size_override("font_size", 18)
	add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)

	var point_header: Label = Label.new()
	point_header.text = "Control Points"
	add_child(point_header)

	_point_list = ItemList.new()
	_point_list.select_mode = ItemList.SELECT_SINGLE
	_point_list.size_flags_vertical = Control.SIZE_EXPAND_FILL if not _embedded_in_inspector else Control.SIZE_SHRINK_BEGIN
	_point_list.custom_minimum_size = Vector2(0.0, 120.0 if _embedded_in_inspector else 180.0)
	_point_list.item_selected.connect(_on_point_selected)
	add_child(_point_list)

	var point_button_row: HBoxContainer = HBoxContainer.new()
	add_child(point_button_row)

	_add_point_button = Button.new()
	_add_point_button.text = "Add Point"
	_add_point_button.pressed.connect(func() -> void: add_point_requested.emit())
	point_button_row.add_child(_add_point_button)

	_insert_point_button = Button.new()
	_insert_point_button.text = "Insert Midpoint"
	_insert_point_button.pressed.connect(func() -> void: insert_point_requested.emit())
	point_button_row.add_child(_insert_point_button)

	_remove_point_button = Button.new()
	_remove_point_button.text = "Delete Point"
	_remove_point_button.pressed.connect(_on_remove_point_pressed)
	point_button_row.add_child(_remove_point_button)

	_closed_toggle = CheckButton.new()
	_closed_toggle.text = "Closed Path"
	_closed_toggle.toggled.connect(func(value: bool) -> void: closed_toggled.emit(value))
	add_child(_closed_toggle)

	_segment_info_label = Label.new()
	_segment_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_segment_info_label)

	_grid_info_label = Label.new()
	_grid_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_grid_info_label)

	_opening_section = VBoxContainer.new()
	add_child(_opening_section)

	var opening_header: Label = Label.new()
	opening_header.text = "House Openings"
	_opening_section.add_child(opening_header)

	_opening_list = ItemList.new()
	_opening_list.select_mode = ItemList.SELECT_SINGLE
	_opening_list.size_flags_vertical = Control.SIZE_EXPAND_FILL if not _embedded_in_inspector else Control.SIZE_SHRINK_BEGIN
	_opening_list.custom_minimum_size = Vector2(0.0, 100.0 if _embedded_in_inspector else 160.0)
	_opening_list.item_selected.connect(_on_opening_selected)
	_opening_section.add_child(_opening_list)

	var opening_button_row: HBoxContainer = HBoxContainer.new()
	_opening_section.add_child(opening_button_row)

	_add_opening_button = Button.new()
	_add_opening_button.text = "Add Opening"
	_add_opening_button.pressed.connect(func() -> void: add_opening_requested.emit())
	opening_button_row.add_child(_add_opening_button)

	_remove_opening_button = Button.new()
	_remove_opening_button.text = "Delete Opening"
	_remove_opening_button.pressed.connect(_on_remove_opening_pressed)
	opening_button_row.add_child(_remove_opening_button)

func _fill_point_list() -> void:
	_point_list.clear()
	for index in range(_target.control_points.size()):
		var point: Vector3 = _target.control_points[index]
		_point_list.add_item("%d: (%.2f, %.2f, %.2f)" % [index, point.x, point.y, point.z])
	if _selected_point_index >= 0 and _selected_point_index < _point_list.item_count:
		_point_list.select(_selected_point_index)

func _fill_segment_info() -> void:
	if _selected_point_index < 0 or _selected_point_index >= _target.control_points.size():
		_segment_info_label.text = "Segment: select a control point to inspect the next edge."
		return

	var next_index: int = _selected_point_index + 1
	if next_index >= _target.control_points.size():
		if _target.closed or _target._requires_closed_shape():
			next_index = 0
		else:
			_segment_info_label.text = "Segment: end point selected."
			return

	var start_point: Vector3 = _target.control_points[_selected_point_index]
	var end_point: Vector3 = _target.control_points[next_index]
	_segment_info_label.text = "Segment %d -> %d length: %.2f" % [_selected_point_index, next_index, start_point.distance_to(end_point)]

func _fill_grid_info() -> void:
	var blocked_cell_count: int = _target.get_blocked_grid_cells_copy().size()
	var block_state: String = "on" if _target.block_grid_navigation else "off"
	var preview_state: String = "on" if _target.show_blocked_cells_in_editor else "off"
	_grid_info_label.text = "Blocked Cells: %d | Navigation Block: %s | Cell Preview: %s" % [
		blocked_cell_count,
		block_state,
		preview_state
	]

func _fill_opening_list(house: ProcHouse3D) -> void:
	_opening_list.clear()
	for index in range(house.openings.size()):
		var opening: HouseOpeningResource = house.openings[index]
		if opening == null:
			_opening_list.add_item("%d: <missing>" % index)
		else:
			_opening_list.add_item("%d: %s" % [index, opening.get_label()])
	if _selected_opening_index >= 0 and _selected_opening_index < _opening_list.item_count:
		_opening_list.select(_selected_opening_index)

func _set_buttons_enabled(enabled: bool) -> void:
	_add_point_button.disabled = not enabled
	_insert_point_button.disabled = not enabled
	_remove_point_button.disabled = not enabled or _selected_point_index < 0
	_add_opening_button.disabled = not enabled or not (_target is ProcHouse3D)
	_remove_opening_button.disabled = not enabled or _selected_opening_index < 0

func _on_point_selected(index: int) -> void:
	_selected_point_index = index
	control_point_selected.emit(index)
	refresh()

func _on_opening_selected(index: int) -> void:
	_selected_opening_index = index
	opening_selected.emit(index)
	refresh()

func _on_remove_point_pressed() -> void:
	if _selected_point_index < 0:
		return
	remove_point_requested.emit(_selected_point_index)

func _on_remove_opening_pressed() -> void:
	if _selected_opening_index < 0:
		return
	remove_opening_requested.emit(_selected_opening_index)

func _apply_layout_mode() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL if not _embedded_in_inspector else Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(280.0, 320.0) if not _embedded_in_inspector else Vector2(0.0, 0.0)
