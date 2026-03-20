@tool
extends EditorProperty

const MODE_SINGLE: String = "gameplay_tag"
const MODE_ARRAY: String = "gameplay_tags"

var _property_name: String = ""
var _property_mode: String = ""
var _editor_plugin: EditorPlugin = null

var _root: VBoxContainer = null
var _single_row: HBoxContainer = null
var _single_option_button: OptionButton = null
var _array_list: ItemList = null
var _array_controls_row: HBoxContainer = null
var _array_option_button: OptionButton = null
var _add_button: Button = null
var _remove_button: Button = null
var _clear_button: Button = null
var _open_button: Button = null
var _is_refreshing: bool = false

func setup(property_name: String, property_mode: String, editor_plugin: EditorPlugin) -> void:
	_property_name = property_name
	_property_mode = property_mode
	_editor_plugin = editor_plugin

func _ready() -> void:
	_build_ui()
	_update_property()

func _update_property() -> void:
	if _property_mode == MODE_SINGLE:
		_refresh_single_ui()
		return
	if _property_mode == MODE_ARRAY:
		_refresh_array_ui()

func _build_ui() -> void:
	if _root:
		return

	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 6)

	if _property_mode == MODE_SINGLE:
		_build_single_ui()
	elif _property_mode == MODE_ARRAY:
		_build_array_ui()

	add_child(_root)

func _build_single_ui() -> void:
	_single_row = HBoxContainer.new()
	_single_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_single_row.add_theme_constant_override("separation", 6)
	_root.add_child(_single_row)

	_single_option_button = OptionButton.new()
	_single_option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_single_option_button.item_selected.connect(_on_single_item_selected)
	_single_row.add_child(_single_option_button)
	add_focusable(_single_option_button)

	_open_button = Button.new()
	_open_button.text = "Open Editor"
	_open_button.pressed.connect(_on_open_editor_pressed)
	_single_row.add_child(_open_button)
	add_focusable(_open_button)

func _build_array_ui() -> void:
	_array_list = ItemList.new()
	_array_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_array_list.custom_minimum_size = Vector2(0, 110)
	_array_list.item_selected.connect(_on_array_item_selected)
	_array_list.empty_clicked.connect(_on_array_empty_clicked)
	_root.add_child(_array_list)
	add_focusable(_array_list)

	_array_controls_row = HBoxContainer.new()
	_array_controls_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_array_controls_row.add_theme_constant_override("separation", 6)
	_root.add_child(_array_controls_row)

	_array_option_button = OptionButton.new()
	_array_option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_array_option_button.item_selected.connect(_on_array_option_changed)
	_array_controls_row.add_child(_array_option_button)
	add_focusable(_array_option_button)

	_add_button = Button.new()
	_add_button.text = "Add"
	_add_button.pressed.connect(_on_add_tag_pressed)
	_array_controls_row.add_child(_add_button)
	add_focusable(_add_button)

	_remove_button = Button.new()
	_remove_button.text = "Remove"
	_remove_button.disabled = true
	_remove_button.pressed.connect(_on_remove_tag_pressed)
	_array_controls_row.add_child(_remove_button)
	add_focusable(_remove_button)

	_clear_button = Button.new()
	_clear_button.text = "Clear"
	_clear_button.disabled = true
	_clear_button.pressed.connect(_on_clear_tags_pressed)
	_array_controls_row.add_child(_clear_button)
	add_focusable(_clear_button)

	_open_button = Button.new()
	_open_button.text = "Open Editor"
	_open_button.pressed.connect(_on_open_editor_pressed)
	_array_controls_row.add_child(_open_button)
	add_focusable(_open_button)

func _refresh_single_ui() -> void:
	if _single_option_button == null:
		return

	var current_value: String = _get_current_single_value()
	var tags: Array[String] = _get_known_tags()
	_is_refreshing = true
	_single_option_button.clear()
	_single_option_button.add_item("<None>")
	_single_option_button.set_item_metadata(0, "")

	var selected_index: int = 0
	var item_index: int = 1
	for tag_name in tags:
		_single_option_button.add_item(tag_name)
		_single_option_button.set_item_metadata(item_index, tag_name)
		if tag_name == current_value:
			selected_index = item_index
		item_index += 1

	if not current_value.is_empty() and not tags.has(current_value):
		_single_option_button.add_item("%s (missing)" % current_value)
		_single_option_button.set_item_metadata(item_index, current_value)
		selected_index = item_index

	_single_option_button.select(selected_index)
	_is_refreshing = false
	_update_open_button_state()

func _refresh_array_ui() -> void:
	if _array_list == null or _array_option_button == null:
		return

	var current_values: Array[String] = _get_current_array_values()
	var tags: Array[String] = _get_known_tags()
	_is_refreshing = true
	_array_list.clear()
	for tag_name in current_values:
		_array_list.add_item(tag_name)

	_array_option_button.clear()
	_array_option_button.add_item("Select tag...")
	_array_option_button.set_item_metadata(0, "")

	var item_index: int = 1
	for tag_name in tags:
		_array_option_button.add_item(tag_name)
		_array_option_button.set_item_metadata(item_index, tag_name)
		item_index += 1

	for tag_name in current_values:
		if tags.has(tag_name):
			continue
		_array_option_button.add_item("%s (missing)" % tag_name)
		_array_option_button.set_item_metadata(item_index, tag_name)
		item_index += 1

	_array_option_button.select(0)
	_is_refreshing = false
	_update_array_buttons()
	_update_open_button_state()

func _get_known_tags() -> Array[String]:
	if _editor_plugin and _editor_plugin.has_method("get_gameplay_tag_entries"):
		var entries: Variant = _editor_plugin.call("get_gameplay_tag_entries")
		if entries is Array:
			var result: Array[String] = []
			for entry in entries:
				var tag_text: String = str(entry).strip_edges()
				if not tag_text.is_empty():
					result.append(tag_text)
			result.sort()
			return result
	return []

func _get_current_single_value() -> String:
	var edited_object: Object = get_edited_object()
	if edited_object == null or _property_name.is_empty():
		return ""
	return str(edited_object.get(_property_name)).strip_edges()

func _get_current_array_values() -> Array[String]:
	var edited_object: Object = get_edited_object()
	var values: Array[String] = []
	if edited_object == null or _property_name.is_empty():
		return values

	var raw_value: Variant = edited_object.get(_property_name)
	if not (raw_value is Array):
		return values

	for entry in raw_value:
		var tag_text: String = str(entry).strip_edges()
		if not tag_text.is_empty():
			values.append(tag_text)
	return values

func _update_open_button_state() -> void:
	if _open_button == null:
		return
	if _property_mode == MODE_SINGLE:
		_open_button.disabled = false
		return
	_open_button.disabled = false

func _update_array_buttons() -> void:
	if _add_button:
		_add_button.disabled = _get_selected_array_option_value().is_empty()
	if _remove_button:
		_remove_button.disabled = _array_list == null or _array_list.get_selected_items().is_empty()
	if _clear_button:
		_clear_button.disabled = _array_list == null or _array_list.item_count == 0

func _get_selected_array_option_value() -> String:
	if _array_option_button == null or _array_option_button.item_count == 0:
		return ""
	return str(_array_option_button.get_item_metadata(_array_option_button.selected)).strip_edges()

func _emit_single_value(tag_text: String) -> void:
	emit_changed(_property_name, StringName(tag_text))

func _emit_array_values(values: Array[String]) -> void:
	var typed_values: Array[StringName] = []
	for value in values:
		var tag_text: String = value.strip_edges()
		if tag_text.is_empty():
			continue
		typed_values.append(StringName(tag_text))
	emit_changed(_property_name, typed_values)

func _on_single_item_selected(index: int) -> void:
	if _is_refreshing:
		return
	var selected_value: String = str(_single_option_button.get_item_metadata(index)).strip_edges()
	_emit_single_value(selected_value)

func _on_array_item_selected(_index: int) -> void:
	_update_array_buttons()

func _on_array_empty_clicked(_position: Vector2, _mouse_button_index: int) -> void:
	if _array_list:
		_array_list.deselect_all()
	_update_array_buttons()

func _on_array_option_changed(_index: int) -> void:
	if _is_refreshing:
		return
	_update_array_buttons()

func _on_add_tag_pressed() -> void:
	var selected_value: String = _get_selected_array_option_value()
	if selected_value.is_empty():
		return

	var current_values: Array[String] = _get_current_array_values()
	if current_values.has(selected_value):
		return
	current_values.append(selected_value)
	_emit_array_values(current_values)

func _on_remove_tag_pressed() -> void:
	if _array_list == null:
		return

	var selected_indices: PackedInt32Array = _array_list.get_selected_items()
	if selected_indices.is_empty():
		return

	var current_values: Array[String] = _get_current_array_values()
	var remove_index: int = int(selected_indices[0])
	if remove_index < 0 or remove_index >= current_values.size():
		return

	current_values.remove_at(remove_index)
	_emit_array_values(current_values)

func _on_clear_tags_pressed() -> void:
	_emit_array_values([])

func _on_open_editor_pressed() -> void:
	if not _editor_plugin or not _editor_plugin.has_method("open_gameplay_tags_editor"):
		push_warning("[Gameplay Tags] open_gameplay_tags_editor is unavailable.")
		return
	_editor_plugin.call("open_gameplay_tags_editor")
