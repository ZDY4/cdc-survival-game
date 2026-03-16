@tool
extends EditorProperty

var _property_name: String = ""
var _data_kind: String = ""
var _plugin_menu: EditorPlugin = null

var _root: HBoxContainer = null
var _option_button: OptionButton = null
var _open_button: Button = null
var _is_refreshing: bool = false

func setup(property_name: String, data_kind: String, plugin_menu: EditorPlugin) -> void:
	_property_name = property_name
	_data_kind = data_kind
	_plugin_menu = plugin_menu

func _ready() -> void:
	_build_ui()
	_reload_options()
	_update_property()

func _update_property() -> void:
	if not _option_button:
		return

	var current_value: String = _get_current_property_value()
	_reload_options()
	_select_value(current_value)
	_open_button.disabled = current_value.is_empty()

func _build_ui() -> void:
	if _root:
		return

	_root = HBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_option_button = OptionButton.new()
	_option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_button.item_selected.connect(_on_item_selected)
	_root.add_child(_option_button)
	add_focusable(_option_button)

	_open_button = Button.new()
	_open_button.text = "打开"
	_open_button.pressed.connect(_on_open_pressed)
	_root.add_child(_open_button)
	add_focusable(_open_button)

	add_child(_root)

func _reload_options() -> void:
	if not _option_button:
		return

	var current_value: String = _get_current_property_value()
	var entries: Array[Dictionary] = _fetch_data_entries()
	_is_refreshing = true
	_option_button.clear()
	_option_button.add_item("<None>")
	_option_button.set_item_metadata(0, "")

	var index: int = 1
	var known_ids: Array[String] = []
	for entry in entries:
		var id_text: String = str(entry.get("id", "")).strip_edges()
		if id_text.is_empty():
			continue
		var label_text: String = str(entry.get("label", id_text)).strip_edges()
		if label_text.is_empty():
			label_text = id_text
		_option_button.add_item(label_text)
		_option_button.set_item_metadata(index, id_text)
		known_ids.append(id_text)
		index += 1

	if not current_value.is_empty() and not known_ids.has(current_value):
		_option_button.add_item("%s (missing)" % current_value)
		_option_button.set_item_metadata(index, current_value)

	_is_refreshing = false

func _fetch_data_entries() -> Array[Dictionary]:
	if _plugin_menu and _plugin_menu.has_method("get_data_id_entries"):
		var entry_result: Variant = _plugin_menu.call("get_data_id_entries", _data_kind)
		if entry_result is Array:
			var entries: Array[Dictionary] = []
			for value in entry_result:
				if value is Dictionary:
					var entry: Dictionary = value
					var id_text: String = str(entry.get("id", "")).strip_edges()
					if id_text.is_empty():
						continue
					var label_text: String = str(entry.get("label", id_text)).strip_edges()
					entries.append({
						"id": id_text,
						"label": label_text if not label_text.is_empty() else id_text
					})
			if not entries.is_empty():
				return entries

	if _plugin_menu and _plugin_menu.has_method("get_data_ids"):
		var result: Variant = _plugin_menu.call("get_data_ids", _data_kind)
		if result is Array:
			var fallback_entries: Array[Dictionary] = []
			for value in result:
				var id_text: String = str(value).strip_edges()
				if id_text.is_empty():
					continue
				fallback_entries.append({
					"id": id_text,
					"label": id_text
				})
			return fallback_entries
	return []

func _get_current_property_value() -> String:
	var edited_object: Object = get_edited_object()
	if not edited_object or _property_name.is_empty():
		return ""
	return str(edited_object.get(_property_name)).strip_edges()

func _select_value(value: String) -> void:
	if not _option_button:
		return

	for i in range(_option_button.item_count):
		if str(_option_button.get_item_metadata(i)) == value:
			_option_button.select(i)
			return
	_option_button.select(0)

func _on_item_selected(index: int) -> void:
	if _is_refreshing:
		return

	var selected_value: String = str(_option_button.get_item_metadata(index))
	_open_button.disabled = selected_value.is_empty()
	emit_changed(_property_name, selected_value)

func _on_open_pressed() -> void:
	var selected_value: String = _get_current_property_value()
	if selected_value.is_empty():
		return
	if not _plugin_menu or not _plugin_menu.has_method("open_cdc_data_editor"):
		push_warning("[CDC Game Editor] open_cdc_data_editor is unavailable for data kind: %s" % _data_kind)
		return

	var focused: bool = bool(_plugin_menu.call("open_cdc_data_editor", _data_kind, selected_value))
	if not focused:
		push_warning("[CDC Game Editor] Editor opened but record not focused: %s (%s)" % [selected_value, _data_kind])
