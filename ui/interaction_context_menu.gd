extends CanvasLayer
## Lightweight right-click menu for interactable world targets.

class_name InteractionContextMenu

# 1. Constants
const MENU_MIN_WIDTH: float = 180.0

# 5. Signals
signal option_selected(index: int)
signal menu_closed()

# 4. Private variables
var _menu: PopupMenu = null
var _menu_open: bool = false

# 6. Public methods
func show_options(screen_pos: Vector2, option_names: Array[String]) -> void:
	if option_names.is_empty():
		hide_menu()
		return

	_ensure_menu()
	_menu.clear()
	for index in range(option_names.size()):
		_menu.add_item(option_names[index], index)

	_menu.reset_size()
	var popup_size := _menu.size
	if popup_size.x < MENU_MIN_WIDTH:
		popup_size.x = MENU_MIN_WIDTH
	var popup_rect := Rect2i(
		Vector2i(int(screen_pos.x), int(screen_pos.y)),
		Vector2i(int(popup_size.x), max(1, int(popup_size.y)))
	)
	_menu.popup(popup_rect)
	_menu_open = true

func hide_menu() -> void:
	if _menu == null:
		return
	if _menu.visible:
		_menu.hide()
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
	if _menu != null:
		return

	_menu = PopupMenu.new()
	_menu.name = "PopupMenu"
	_menu.id_pressed.connect(_on_menu_id_pressed)
	_menu.popup_hide.connect(_on_menu_popup_hide)
	add_child(_menu)

func _on_menu_id_pressed(id: int) -> void:
	option_selected.emit(id)
	if _menu != null and _menu.visible:
		_menu.hide()

func _on_menu_popup_hide() -> void:
	_emit_menu_closed_if_needed()

func _emit_menu_closed_if_needed() -> void:
	if not _menu_open:
		return
	_menu_open = false
	menu_closed.emit()
