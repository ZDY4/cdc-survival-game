@tool
extends GraphNode

signal data_changed(node_id: String, new_data: Dictionary)

var node_data: Dictionary = {}
var _input_port_requests: Array[Dictionary] = []
var _output_port_requests: Array[Dictionary] = []

func _ready() -> void:
	resizable = false
	draggable = true
	selectable = true

	if _has_property("show_close_button"):
		set("show_close_button", true)
	elif _has_property("show_close"):
		set("show_close", true)
	elif _has_property("close_button_enabled"):
		set("close_button_enabled", true)

	if has_signal("close_request"):
		connect("close_request", _on_close_request)
	elif has_signal("delete_request"):
		connect("delete_request", _on_close_request)

	if has_signal("position_offset_changed"):
		connect("position_offset_changed", _on_position_offset_changed)
	elif has_signal("dragged"):
		connect("dragged", _on_dragged)

func set_visual_style(color: Color) -> void:
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = color.darkened(0.3)
	title_style.border_color = color
	title_style.border_width_left = 2
	title_style.border_width_right = 2
	title_style.border_width_top = 2
	title_style.border_width_bottom = 2
	title_style.corner_radius_top_left = 8
	title_style.corner_radius_top_right = 8
	title_style.corner_radius_bottom_left = 8
	title_style.corner_radius_bottom_right = 8
	add_theme_stylebox_override("titlebar", title_style)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = color.darkened(0.5)
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", panel_style)

func reset_content() -> void:
	for child in get_children():
		child.queue_free()

	if has_method("clear_all_slots"):
		call("clear_all_slots")

	_input_port_requests.clear()
	_output_port_requests.clear()

func add_text_row(
	text: String,
	color: Color = Color.WHITE,
	min_size: Vector2 = Vector2.ZERO,
	autowrap: bool = false,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.modulate = color
	if min_size != Vector2.ZERO:
		label.custom_minimum_size = min_size
	if autowrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label

func add_separator() -> void:
	add_child(HSeparator.new())

func add_input_port(port_type: int = 0, color: Color = Color.WHITE) -> void:
	_input_port_requests.append({
		"type": port_type,
		"color": color
	})

func add_output_port(port_type: int = 0, color: Color = Color.WHITE) -> void:
	_output_port_requests.append({
		"type": port_type,
		"color": color
	})

func finalize_ports() -> void:
	var required_rows := maxi(get_child_count(), maxi(_input_port_requests.size(), _output_port_requests.size()))
	required_rows = maxi(required_rows, 1)
	_ensure_row_count(required_rows)

	var input_rows := _get_distributed_row_indexes(_input_port_requests.size(), get_child_count())
	for i in range(_input_port_requests.size()):
		var request: Dictionary = _input_port_requests[i]
		var row_index := input_rows[i]
		set_slot_enabled_left(row_index, true)
		set_slot_type_left(row_index, int(request.get("type", 0)))
		set_slot_color_left(row_index, request.get("color", Color.WHITE))

	var output_rows := _get_distributed_row_indexes(_output_port_requests.size(), get_child_count())
	for i in range(_output_port_requests.size()):
		var request: Dictionary = _output_port_requests[i]
		var row_index := output_rows[i]
		set_slot_enabled_right(row_index, true)
		set_slot_type_right(row_index, int(request.get("type", 0)))
		set_slot_color_right(row_index, request.get("color", Color.WHITE))

func update_data(new_data: Dictionary) -> void:
	node_data = new_data.duplicate(true)

func _on_close_request() -> void:
	queue_free()

func _on_dragged(_from: Vector2, to: Vector2) -> void:
	if node_data.get("position", Vector2.ZERO) == to:
		return
	node_data["position"] = to

func _on_position_offset_changed() -> void:
	if node_data.get("position", Vector2.ZERO) == position_offset:
		return
	node_data["position"] = position_offset

func _has_property(property_name: String) -> bool:
	for property_info_variant in get_property_list():
		if not (property_info_variant is Dictionary):
			continue
		var property_info: Dictionary = property_info_variant
		if str(property_info.get("name", "")) == property_name:
			return true
	return false

func _add_port_row() -> int:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 8)
	add_child(row)
	return get_child_count() - 1

func _ensure_row_count(target_count: int) -> void:
	while get_child_count() < target_count:
		_add_port_row()

func _get_distributed_row_indexes(port_count: int, row_count: int) -> Array[int]:
	var indexes: Array[int] = []
	if port_count <= 0:
		return indexes

	var safe_row_count := maxi(row_count, 1)
	if port_count == 1:
		indexes.append(int(floor(float(safe_row_count - 1) / 2.0)))
		return indexes

	var last_index := -1
	for i in range(port_count):
		var ratio := (float(i) + 0.5) / float(port_count)
		var row_index := int(round(ratio * float(safe_row_count) - 0.5))
		row_index = clampi(row_index, 0, safe_row_count - 1)
		if row_index <= last_index:
			row_index = mini(last_index + 1, safe_row_count - 1)
		indexes.append(row_index)
		last_index = row_index

	return indexes
