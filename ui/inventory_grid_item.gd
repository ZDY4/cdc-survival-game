extends PanelContainer

class_name InventoryGridItem

const ItemIdResolver = preload("res://core/item_id_resolver.gd")

signal item_hovered(instance_id: String)
signal item_unhovered(instance_id: String)
signal item_selected(instance_id: String)

var instance_id: String = ""
var item_entry: Dictionary = {}
var item_data: Dictionary = {}
var footprint: Vector2i = Vector2i.ONE
var cell_size: float = 40.0
var _icon_rect: TextureRect = null
var _title_label: Label = null
var _count_label: Label = null
var _selected: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func configure(entry: Dictionary, data: Dictionary, next_footprint: Vector2i, next_cell_size: float) -> void:
	item_entry = entry.duplicate(true)
	item_data = data.duplicate(true)
	instance_id = str(item_entry.get("instance_id", ""))
	footprint = Vector2i(maxi(1, next_footprint.x), maxi(1, next_footprint.y))
	cell_size = maxf(24.0, next_cell_size)
	custom_minimum_size = Vector2(float(footprint.x) * cell_size, float(footprint.y) * cell_size)
	if is_node_ready():
		_refresh_display()


func set_selected(selected: bool) -> void:
	_selected = selected
	if is_node_ready():
		_refresh_style()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	item_selected.emit(instance_id)
	accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if instance_id.is_empty():
		return null
	var preview := duplicate() as Control
	if preview == null:
		return null
	preview.custom_minimum_size = size
	set_drag_preview(preview)
	return {
		"type": "inventory_item",
		"instance_id": instance_id,
		"item_id": str(item_entry.get("id", ""))
	}


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(24, 24)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_icon_rect)

	_title_label = Label.new()
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.add_theme_font_size_override("font_size", 11)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_title_label)

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_count_label)

	_refresh_display()


func _refresh_display() -> void:
	if _title_label == null:
		return

	var item_name: String = str(item_data.get("name", item_entry.get("id", "")))
	_title_label.text = item_name
	_count_label.text = "x%d" % int(item_entry.get("count", 1)) if int(item_entry.get("count", 1)) > 1 else ""
	_icon_rect.texture = _load_item_texture()
	tooltip_text = "%s\n%s" % [item_name, str(item_data.get("description", ""))]
	_refresh_style()


func _refresh_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.17, 0.20, 0.24, 0.95)
	style.border_color = Color(0.90, 0.79, 0.42, 1.0) if _selected else Color(0.45, 0.54, 0.60, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", style)


func _load_item_texture() -> Texture2D:
	var icon_path: String = str(item_data.get("icon_path", "")).strip_edges()
	var candidates: Array[String] = []
	var generated_path: String = ItemIdResolver.build_generated_texture_path(icon_path)
	if not generated_path.is_empty():
		candidates.append(generated_path)
	if not icon_path.is_empty():
		candidates.append(icon_path)
	for candidate in candidates:
		if not ResourceLoader.exists(candidate):
			continue
		var resource := load(candidate)
		if resource is Texture2D:
			return resource as Texture2D
	return null


func _on_mouse_entered() -> void:
	item_hovered.emit(instance_id)


func _on_mouse_exited() -> void:
	item_unhovered.emit(instance_id)
