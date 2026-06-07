extends RefCounted

const FONT_RESOURCE_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const DEFAULT_FONT_SIZE := 14


static func build_default_theme() -> Theme:
	var theme := Theme.new()
	var font := ResourceLoader.load(FONT_RESOURCE_PATH)
	if font is Font:
		theme.default_font = font
		theme.default_font_size = DEFAULT_FONT_SIZE
	return theme


static func apply_default_theme(control: Control) -> Dictionary:
	if control == null:
		return {"applied": false, "reason": "control_missing"}
	var theme := build_default_theme()
	control.theme = theme
	return theme_snapshot(theme)


static func theme_snapshot(theme: Theme) -> Dictionary:
	var font: Font = theme.default_font if theme != null else null
	var font_path := font.resource_path if font != null else ""
	return {
		"applied": font != null and font_path == FONT_RESOURCE_PATH,
		"font_resource_path": font_path,
		"expected_font_resource_path": FONT_RESOURCE_PATH,
		"font_exists": FileAccess.file_exists(FONT_RESOURCE_PATH),
		"default_font_size": theme.default_font_size if theme != null else 0,
	}
