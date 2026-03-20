extends PanelContainer

class_name SkillPanelItem

const ValueUtils = preload("res://core/value_utils.gd")

signal add_to_hotbar_requested(skill_id: String)

const MENU_ADD_TO_HOTBAR: int = 1

var skill_id: String = ""
var skill_data: Dictionary = {}

var _icon_rect: TextureRect = null
var _placeholder_rect: ColorRect = null
var _placeholder_label: Label = null
var _title_label: Label = null
var _meta_label: Label = null
var _popup_menu: PopupMenu = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(120, 132)
	_build_ui()
	_refresh_display()


func configure(new_skill_id: String, data: Dictionary) -> void:
	skill_id = new_skill_id
	skill_data = data.duplicate(true)
	if is_node_ready():
		_refresh_display()


func _gui_input(event: InputEvent) -> void:
	if not _is_hotbar_eligible():
		return
	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return

	if _popup_menu == null:
		return
	_popup_menu.clear()
	_popup_menu.add_item("添加到快捷栏", MENU_ADD_TO_HOTBAR)
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	_popup_menu.popup(Rect2i(Vector2i(floori(mouse_pos.x), floori(mouse_pos.y)), Vector2i(1, 1)))
	accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not _is_hotbar_eligible():
		return null

	var preview := duplicate() as Control
	if preview == null:
		return null
	preview.custom_minimum_size = size
	set_drag_preview(preview)
	return {
		"type": "skill_panel_item",
		"skill_id": skill_id
	}


func _build_ui() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.15, 0.18, 0.94)
	style.border_color = Color(0.34, 0.42, 0.48, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var icon_holder := CenterContainer.new()
	icon_holder.custom_minimum_size = Vector2(0, 72)
	root.add_child(icon_holder)

	var icon_stack := Control.new()
	icon_stack.custom_minimum_size = Vector2(56, 56)
	icon_stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_holder.add_child(icon_stack)

	_placeholder_rect = ColorRect.new()
	_placeholder_rect.color = Color(0.24, 0.31, 0.36, 1.0)
	_placeholder_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_stack.add_child(_placeholder_rect)

	_placeholder_label = Label.new()
	_placeholder_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder_label.add_theme_font_size_override("font_size", 18)
	_placeholder_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_stack.add_child(_placeholder_label)

	_icon_rect = TextureRect.new()
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_stack.add_child(_icon_rect)

	_title_label = Label.new()
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 14)
	root.add_child(_title_label)

	_meta_label = Label.new()
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta_label.add_theme_font_size_override("font_size", 11)
	root.add_child(_meta_label)

	_popup_menu = PopupMenu.new()
	_popup_menu.id_pressed.connect(_on_popup_id_pressed)
	add_child(_popup_menu)


func _refresh_display() -> void:
	if _title_label == null:
		return

	var skill_name: String = str(skill_data.get("name", skill_id))
	_title_label.text = skill_name
	var current_level: int = ValueUtils.to_int(skill_data.get("current_level", 0))
	var activation: Dictionary = skill_data.get("activation", {})
	var activation_mode: String = str(activation.get("mode", "passive"))
	_meta_label.text = "Lv.%d  %s" % [current_level, activation_mode]
	_meta_label.modulate = Color(0.75, 0.80, 0.84, 1.0)
	if not bool(skill_data.get("is_learned", false)):
		_meta_label.text += "  未学习"
		_meta_label.modulate = Color(0.75, 0.46, 0.40, 1.0)

	var icon_path: String = str(skill_data.get("icon", "")).strip_edges()
	var texture: Texture2D = null
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		texture = load(icon_path) as Texture2D
	_icon_rect.texture = texture
	_icon_rect.visible = texture != null
	_placeholder_rect.visible = texture == null
	_placeholder_label.visible = texture == null
	_placeholder_label.text = _build_placeholder_text(skill_name)

	tooltip_text = "%s\n%s" % [skill_name, str(skill_data.get("description", ""))]
	if _is_hotbar_eligible():
		tooltip_text += "\n右键可添加到当前快捷栏"

	var style := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if style != null:
		style.border_color = Color(0.22, 0.67, 0.47, 1.0) if _is_hotbar_eligible() else Color(0.34, 0.42, 0.48, 1.0)
		add_theme_stylebox_override("panel", style)


func _build_placeholder_text(skill_name: String) -> String:
	var trimmed: String = skill_name.strip_edges()
	if trimmed.length() <= 2:
		return trimmed
	return trimmed.substr(0, 2)


func _is_hotbar_eligible() -> bool:
	return bool(skill_data.get("hotbar_eligible", false))


func _on_popup_id_pressed(id: int) -> void:
	if id == MENU_ADD_TO_HOTBAR and not skill_id.is_empty():
		add_to_hotbar_requested.emit(skill_id)
