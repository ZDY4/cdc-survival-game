extends RefCounted

const FONT_RESOURCE_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const DEFAULT_THEME_RESOURCE_PATH := "res://assets/themes/default_ui_theme.tres"
const DEFAULT_FONT_SIZE := 14
const SMALL_FONT_SIZE := 12
const TITLE_FONT_SIZE := 18
const BUTTON_MIN_HEIGHT := 30
const LINE_SEPARATION := 4


static func load_default_font() -> Font:
	var font := ResourceLoader.load(FONT_RESOURCE_PATH)
	return font as Font


static func build_default_theme() -> Theme:
	var theme := load_default_theme()
	if theme == null:
		theme = Theme.new()
	var font := load_default_font()
	if font != null:
		theme.default_font = font
		theme.default_font_size = DEFAULT_FONT_SIZE
	_apply_control_standards(theme)
	return theme


static func load_default_theme() -> Theme:
	var theme := ResourceLoader.load(DEFAULT_THEME_RESOURCE_PATH)
	return theme as Theme


static func _apply_control_standards(theme: Theme) -> void:
	if theme == null:
		return
	for theme_type in ["Label", "RichTextLabel", "LineEdit", "SpinBox", "OptionButton", "Button", "CheckBox", "TabBar"]:
		theme.set_font_size("font_size", theme_type, DEFAULT_FONT_SIZE)
	for theme_type in ["TooltipLabel", "ItemList"]:
		theme.set_font_size("font_size", theme_type, SMALL_FONT_SIZE)
	for theme_type in ["HeaderSmall", "HeaderMedium"]:
		theme.set_font_size("font_size", theme_type, TITLE_FONT_SIZE)
	for theme_type in ["VBoxContainer", "HBoxContainer", "GridContainer"]:
		theme.set_constant("separation", theme_type, LINE_SEPARATION)
	for theme_type in ["Button", "OptionButton"]:
		theme.set_constant("minimum_height", theme_type, BUTTON_MIN_HEIGHT)
		theme.set_color("font_color", theme_type, Color(0.92, 0.94, 0.93, 1.0))
		theme.set_color("font_hover_color", theme_type, Color(1.0, 1.0, 1.0, 1.0))
		theme.set_color("font_pressed_color", theme_type, Color(0.86, 0.91, 0.89, 1.0))
		theme.set_color("font_disabled_color", theme_type, Color(0.56, 0.60, 0.60, 1.0))
		theme.set_stylebox("normal", theme_type, _button_style(Color(0.13, 0.16, 0.18, 0.94), Color(0.31, 0.36, 0.38, 1.0)))
		theme.set_stylebox("hover", theme_type, _button_style(Color(0.18, 0.23, 0.25, 0.96), Color(0.46, 0.58, 0.55, 1.0)))
		theme.set_stylebox("pressed", theme_type, _button_style(Color(0.10, 0.13, 0.15, 0.98), Color(0.40, 0.62, 0.55, 1.0)))
		theme.set_stylebox("disabled", theme_type, _button_style(Color(0.10, 0.11, 0.12, 0.68), Color(0.20, 0.23, 0.24, 0.82)))
		theme.set_stylebox("focus", theme_type, _button_style(Color(0.0, 0.0, 0.0, 0.0), Color(0.67, 0.78, 0.70, 1.0), 2))


static func _button_style(background: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


static func apply_default_theme(control: Control) -> Dictionary:
	if control == null:
		return {"applied": false, "reason": "control_missing"}
	var theme := build_default_theme()
	control.theme = theme
	return theme_snapshot(theme)


static func apply_label3d_font(label: Label3D) -> Dictionary:
	if label == null:
		return {"applied": false, "reason": "label_missing"}
	var font := load_default_font()
	if font == null:
		return {
			"applied": false,
			"reason": "font_missing",
			"expected_font_resource_path": FONT_RESOURCE_PATH,
			"font_exists": FileAccess.file_exists(FONT_RESOURCE_PATH),
		}
	label.font = font
	label.set_meta("font_resource_path", font.resource_path)
	return label3d_font_snapshot(label)


static func theme_snapshot(theme: Theme) -> Dictionary:
	var font: Font = theme.default_font if theme != null else null
	var font_path := font.resource_path if font != null else ""
	return {
		"applied": font != null and font_path == FONT_RESOURCE_PATH,
		"theme_resource_path": theme.resource_path if theme != null else "",
		"expected_theme_resource_path": DEFAULT_THEME_RESOURCE_PATH,
		"theme_exists": FileAccess.file_exists(DEFAULT_THEME_RESOURCE_PATH),
		"theme_resource_loaded": theme != null and theme.resource_path == DEFAULT_THEME_RESOURCE_PATH,
		"font_resource_path": font_path,
		"expected_font_resource_path": FONT_RESOURCE_PATH,
		"font_exists": FileAccess.file_exists(FONT_RESOURCE_PATH),
		"default_font_size": theme.default_font_size if theme != null else 0,
		"control_font_sizes": _control_font_size_snapshot(theme),
		"layout_constants": _layout_constant_snapshot(theme),
		"button_state_styles": _button_state_snapshot(theme),
	}


static func _control_font_size_snapshot(theme: Theme) -> Dictionary:
	if theme == null:
		return {}
	var result := {}
	for theme_type in ["Label", "RichTextLabel", "Button", "OptionButton", "TooltipLabel", "HeaderMedium"]:
		result[theme_type] = theme.get_font_size("font_size", theme_type)
	return result


static func _layout_constant_snapshot(theme: Theme) -> Dictionary:
	if theme == null:
		return {}
	return {
		"button_minimum_height": theme.get_constant("minimum_height", "Button"),
		"option_button_minimum_height": theme.get_constant("minimum_height", "OptionButton"),
		"vbox_separation": theme.get_constant("separation", "VBoxContainer"),
		"hbox_separation": theme.get_constant("separation", "HBoxContainer"),
	}


static func _button_state_snapshot(theme: Theme) -> Dictionary:
	if theme == null:
		return {}
	var states := {}
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		states[state] = theme.has_stylebox(state, "Button")
	return {
		"states": states,
		"font_color": theme.has_color("font_color", "Button"),
		"font_hover_color": theme.has_color("font_hover_color", "Button"),
		"font_pressed_color": theme.has_color("font_pressed_color", "Button"),
		"font_disabled_color": theme.has_color("font_disabled_color", "Button"),
	}


static func label3d_font_snapshot(label: Label3D) -> Dictionary:
	var font: Font = label.font if label != null else null
	var font_path := font.resource_path if font != null else ""
	return {
		"applied": font != null and font_path == FONT_RESOURCE_PATH,
		"font_resource_path": font_path,
		"expected_font_resource_path": FONT_RESOURCE_PATH,
		"font_exists": FileAccess.file_exists(FONT_RESOURCE_PATH),
	}
