extends CanvasLayer
## Lightweight right-click menu for interactable world targets.

class_name InteractionContextMenu

const ValueUtils = preload("res://core/value_utils.gd")

# 1. Constants
const MENU_MIN_WIDTH: float = 132.0
const MENU_FONT_SIZE: int = 13
const MENU_PANEL_PADDING_X: float = 6.0
const MENU_PANEL_PADDING_Y: float = 6.0
const MENU_ITEM_HEIGHT: float = 24.0
const MENU_ITEM_TEXT_PADDING_X: float = 8.0
const MENU_ITEM_TEXT_PADDING_Y: float = 4.0
const MENU_ITEM_SEPARATION: int = 2

# 5. Signals
signal option_selected(index: int)
signal menu_closed()

# 4. Private variables
var _popup: PopupPanel = null
var _option_list: VBoxContainer = null
var _menu_open: bool = false

# 6. Public methods
func show_options(screen_pos: Vector2, option_items: Array[Dictionary]) -> void:
	if option_items.is_empty():
		hide_menu()
		return

	_ensure_menu()
	_rebuild_option_list(option_items)
	var popup_size := _measure_popup_size(option_items)
	var popup_rect := Rect2i(
		Vector2i(floori(screen_pos.x), floori(screen_pos.y)),
		Vector2i(
			maxi(1, ValueUtils.to_int(popup_size.x, 1)),
			maxi(1, ValueUtils.to_int(popup_size.y, 1))
		)
	)
	_popup.popup(popup_rect)
	_menu_open = true
	call_deferred("_focus_first_option")

func hide_menu() -> void:
	if _popup == null:
		return
	if _popup.visible:
		_popup.hide()
		return
	_emit_menu_closed_if_needed()

func is_open() -> bool:
	return _menu_open

# 7. Private methods
func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_menu()

func _ensure_menu() -> void:
	if _popup != null:
		return

	_popup = PopupPanel.new()
	_popup.name = "InteractionContextPopup"
	_popup.popup_hide.connect(_on_popup_hide)
	_popup.add_theme_stylebox_override("panel", _create_panel_stylebox())
	add_child(_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(MENU_PANEL_PADDING_X))
	margin.add_theme_constant_override("margin_top", int(MENU_PANEL_PADDING_Y))
	margin.add_theme_constant_override("margin_right", int(MENU_PANEL_PADDING_X))
	margin.add_theme_constant_override("margin_bottom", int(MENU_PANEL_PADDING_Y))
	_popup.add_child(margin)

	_option_list = VBoxContainer.new()
	_option_list.add_theme_constant_override("separation", MENU_ITEM_SEPARATION)
	margin.add_child(_option_list)

func _rebuild_option_list(option_items: Array[Dictionary]) -> void:
	if _option_list == null:
		return

	for child in _option_list.get_children():
		_option_list.remove_child(child)
		child.queue_free()

	var content_width := _measure_content_width(option_items)
	for index in range(option_items.size()):
		var item: Dictionary = option_items[index]
		var item_text: String = str(item.get("text", "")).strip_edges()
		if item_text.is_empty():
			item_text = "交互"

		var button := Button.new()
		button.text = item_text
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(content_width, MENU_ITEM_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", MENU_FONT_SIZE)
		button.add_theme_stylebox_override("normal", _create_item_stylebox(Color(0.0, 0.0, 0.0, 0.0)))
		button.add_theme_stylebox_override("hover", _create_item_stylebox(Color(0.16, 0.22, 0.28, 0.95)))
		button.add_theme_stylebox_override("pressed", _create_item_stylebox(Color(0.12, 0.18, 0.22, 0.98)))
		button.add_theme_stylebox_override("focus", _create_item_stylebox(Color(0.16, 0.22, 0.28, 0.95), Color(0.38, 0.56, 0.66, 1.0)))
		_apply_button_text_color(button, item.get("color", null))
		button.pressed.connect(_on_option_button_pressed.bind(index))
		_option_list.add_child(button)

func _measure_popup_size(option_items: Array[Dictionary]) -> Vector2:
	var content_width := _measure_content_width(option_items)
	var item_count := maxf(1.0, float(option_items.size()))
	var total_height := MENU_PANEL_PADDING_Y * 2.0
	total_height += item_count * MENU_ITEM_HEIGHT
	total_height += maxf(0.0, item_count - 1.0) * float(MENU_ITEM_SEPARATION)
	return Vector2(content_width + MENU_PANEL_PADDING_X * 2.0, total_height)

func _measure_content_width(option_items: Array[Dictionary]) -> float:
	var content_width := maxf(0.0, MENU_MIN_WIDTH - MENU_PANEL_PADDING_X * 2.0)
	if _popup == null:
		return content_width

	var font: Font = _popup.get_theme_default_font()
	if font == null:
		return content_width

	for item in option_items:
		var item_text: String = str(item.get("text", "")).strip_edges()
		if item_text.is_empty():
			item_text = "交互"
		var measured_width := font.get_string_size(
			item_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			MENU_FONT_SIZE
		).x
		content_width = maxf(content_width, measured_width + MENU_ITEM_TEXT_PADDING_X * 2.0)
	return ceilf(content_width)

func _create_panel_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.12, 0.96)
	style.border_color = Color(0.24, 0.31, 0.36, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	return style

func _create_item_stylebox(background: Color, border: Color = Color(0.0, 0.0, 0.0, 0.0)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = 1 if border.a > 0.0 else 0
	style.border_width_top = 1 if border.a > 0.0 else 0
	style.border_width_right = 1 if border.a > 0.0 else 0
	style.border_width_bottom = 1 if border.a > 0.0 else 0
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = MENU_ITEM_TEXT_PADDING_X
	style.content_margin_top = MENU_ITEM_TEXT_PADDING_Y
	style.content_margin_right = MENU_ITEM_TEXT_PADDING_X
	style.content_margin_bottom = MENU_ITEM_TEXT_PADDING_Y
	return style

func _apply_button_text_color(button: Button, item_color: Variant) -> void:
	var base_color := Color(0.92, 0.94, 0.96, 1.0)
	if item_color is Color:
		var resolved_color: Color = item_color
		if resolved_color.a > 0.0:
			base_color = resolved_color
	button.add_theme_color_override("font_color", base_color)
	button.add_theme_color_override("font_hover_color", base_color)
	button.add_theme_color_override("font_pressed_color", base_color)
	button.add_theme_color_override("font_focus_color", base_color)

func _focus_first_option() -> void:
	if _option_list == null or _option_list.get_child_count() == 0:
		return
	var first_button := _option_list.get_child(0) as Button
	if first_button != null:
		first_button.grab_focus()

func _on_option_button_pressed(index: int) -> void:
	option_selected.emit(index)
	if _popup != null and _popup.visible:
		_popup.hide()

func _on_popup_hide() -> void:
	_emit_menu_closed_if_needed()

func _emit_menu_closed_if_needed() -> void:
	if not _menu_open:
		return
	_menu_open = false
	menu_closed.emit()
