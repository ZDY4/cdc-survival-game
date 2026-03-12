@tool
extends EditorInspectorPlugin

const MARKER_PREFIX: String = "cdc_data_id:"
const GAME_DATA_ID_EDITOR_PROPERTY_SCRIPT := preload("res://addons/cdc_game_editor/inspector/game_data_id_editor_property.gd")

var _plugin_menu: EditorPlugin = null

func _init(plugin_menu: EditorPlugin = null) -> void:
	_plugin_menu = plugin_menu

func _can_handle(_object: Object) -> bool:
	return true

func _parse_property(
	_object: Object,
	type: int,
	name: String,
	_hint_type: int,
	hint_string: String,
	usage_flags: int,
	_wide: bool
) -> bool:
	if type != TYPE_STRING:
		return false
	if (usage_flags & PROPERTY_USAGE_EDITOR) == 0:
		return false

	var data_kind: String = _extract_data_kind(hint_string)
	if data_kind.is_empty():
		return false

	var editor_property: EditorProperty = GAME_DATA_ID_EDITOR_PROPERTY_SCRIPT.new()
	editor_property.setup(name, data_kind, _plugin_menu)
	add_property_editor(name, editor_property)
	return true

func _extract_data_kind(hint_string: String) -> String:
	var normalized_hint: String = hint_string.strip_edges()
	if not normalized_hint.begins_with(MARKER_PREFIX):
		return ""

	var kind_text: String = normalized_hint.trim_prefix(MARKER_PREFIX).strip_edges()
	var comma_pos: int = kind_text.find(",")
	if comma_pos >= 0:
		kind_text = kind_text.substr(0, comma_pos).strip_edges()
	return kind_text.to_lower()
